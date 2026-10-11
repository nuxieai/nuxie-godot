import Foundation
import CryptoKit
import XCTest
import OSLog
import Nuxie
@testable import NuxieGodotBridge

/// Executes the shipped adapter, native profile authentication and native Journey.
/// The public adapter exposes activity/events, not rendered form editing APIs.
@MainActor
final class NativeV3Tests: XCTestCase {
  func testSignedV3JourneyProjectsTypedEventValuesThroughTheNativeAdapter() async throws {
    try await exercise("accepted", accepted: true)
  }
  func testSignedRetiredV1SchemaDoesNotAdmitAJourney() async throws {
    try await exercise("retired-v1", accepted: false)
  }
  func testSignedRetiredV2SchemaDoesNotAdmitAJourney() async throws {
    try await exercise("retired-v2", accepted: false)
  }
  func testV3BytesSignedWithTheRetiredDomainDoNotAdmitAJourney() async throws {
    try await exercise("wrong-domain", accepted: false)
  }

  private func invoke(_ bridge: NuxieGodotRuntime, _ method: String, _ arguments: [String: Any]) async throws -> Any? {
    try await withCheckedThrowingContinuation { continuation in
      bridge.invoke(method, arguments: arguments, resolve: { value in continuation.resume(returning: value) },
        reject: { code, message, _ in continuation.resume(throwing: NSError(domain: code, code: 1,
          userInfo: [NSLocalizedDescriptionKey: message])) })
    }
  }
  private func json(_ value: Any) throws -> String {
    String(decoding: try JSONSerialization.data(withJSONObject: value, options: [.sortedKeys]), as: UTF8.self)
  }
  private func wait(_ label: String, _ condition: () -> Bool) async throws {
    let deadline = Date().addingTimeInterval(15)
    while !condition() && Date() < deadline { try await Task.sleep(nanoseconds: 20_000_000) }
    XCTAssertTrue(condition(), label)
    if !condition() { throw NSError(domain: "NativeV3Tests", code: 1, userInfo: [NSLocalizedDescriptionKey: label]) }
  }
  private func exercise(_ vector: String, accepted: Bool) async throws {
    XCTAssertFalse(NuxieSDK.shared.isSetup)
#if SWIFT_PACKAGE
    let fixture = try XCTUnwrap(Bundle.module.url(forResource: vector, withExtension: "json", subdirectory: "native-v3"))
#else
    let fixture = try XCTUnwrap(Bundle(for: Self.self).url(forResource: vector, withExtension: "json"))
#endif
    let profile = try Data(contentsOf: fixture)
    let apiKey = "pk_test_wrapper_\(UUID().uuidString)"
    NativeV3Transport.reset(profile, apiKey: apiKey)
    XCTAssertTrue(URLProtocol.registerClass(NativeV3Transport.self))
    guard ProcessInfo.processInfo.environment["NUXIE_GODOT_API_ENDPOINT"] == "https://wrapper-v3-api.nuxie.test" else {
      throw NSError(domain: "NativeV3Tests", code: 1, userInfo: [NSLocalizedDescriptionKey: "Launch XCTest with NUXIE_GODOT_API_ENDPOINT set to the fixture URL"])
    }
    defer { URLProtocol.unregisterClass(NativeV3Transport.self) }
    let nativeLogs = try OSLogStore(scope: .currentProcessIdentifier)
    let logPosition = nativeLogs.position(date: Date())
    defer {
      if let entries = try? nativeLogs.getEntries(at: logPosition) {
        for entry in entries {
          if let entry = entry as? OSLogEntryLog, entry.subsystem == "io.nuxie.sdk" {
            print("NATIVE_V3_NATIVE_LOG vector=\(vector) message=\(entry.composedMessage)")
          }
        }
      }
      print("NATIVE_V3_TRANSPORT vector=\(vector) offeredHosts=\(NativeV3Transport.offeredHosts)")
    }
    let bridge = NuxieGodotRuntime()
    var emitted: [[String: Any]] = []
    bridge.emit = { value in
      if let data = value.data(using: .utf8), let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
        emitted.append(object)
      }

    }
    let session = UUID().uuidString
    do {
      let configured = try await invoke(bridge, "configure", ["configuration": try json([
        "contract": 1, "session": session, "apiKey": apiKey,
        "environment": "development", "logLevel": "debug", "purchaseHandlingMode": "observer", "externalBilling": false,

      ])])
      XCTAssertNotNil(configured)
      try await wait("Native startup must fetch the signed profile") { NativeV3Transport.profileRequests > 0 }
      let customer = "wrapper-v3-\(UUID().uuidString)"
      _ = try await invoke(bridge, "identify", ["session": session, "customerId": customer, "properties": "{}"])
      try await wait("Fresh customer must receive its profile") { NativeV3Transport.profileCustomers.contains(customer) }
      if accepted { try await wait("Signed v3 profile must publish authoritative readiness") { NuxieSDK.shared.features.state == .ready } }
      else {
        // The public SDK intentionally has no profile-error callback. Its real
        // unified log names the authentication failure even with privacy redaction.
        // Require that terminal native failure before testing lack of admission.
        var authenticationFailure: String?
        try await wait("Native profile authentication must explicitly fail") {
          authenticationFailure = try? nativeLogs.getEntries(at: logPosition).compactMap { entry -> String? in
            guard let entry = entry as? OSLogEntryLog, entry.subsystem == "io.nuxie.sdk",
              (entry.composedMessage.contains("Profile fetch failed") || entry.composedMessage.contains("Identity profile refresh failed")),
              entry.composedMessage.contains("JourneyReleaseAuthenticationError") else { return nil }
            return entry.composedMessage
          }.first
          return authenticationFailure != nil
        }
        print("NATIVE_V3_AUTH_REJECTION vector=\(vector) message=\(try XCTUnwrap(authenticationFailure))")
      }
      let values: [String: Any] = ["probeNumber": 42, "probeText": "native-v3-wrapper", "probeBoolean": true]
      _ = try await invoke(bridge, "trigger", ["session": session, "event": "wrapper_v3_probe", "properties": try json(values)])
      func activities() -> [[String: Any]] {
        emitted.filter { $0["name"] as? String == "activity" }.compactMap { $0["payload"] as? [String: Any] }
          .filter { ["journey_started", "journey_completed"].contains($0["name"] as? String ?? "") }
      }
      if accepted { try await wait("Real native Journey completion must reach the adapter") { activities().contains { $0["name"] as? String == "journey_completed" } } }
      // Cross the SDK's normal flush threshold using the actual adapter. This
      // also proves event delivery is alive when a release is correctly rejected.
      for index in 0..<45 {
        _ = try await invoke(bridge, "trigger", ["session": session, "event": "wrapper_v3_flush_probe", "properties": try json(["index": index])])
      }
      // Complete the last partial batch through the public API. These distinct
      // sentinels are not part of the 45-index oracle below.
      for index in 0..<20 {
        _ = try await invoke(bridge, "trigger", ["session": session, "event": "wrapper_v3_flush_sentinel", "properties": try json(["index": index])])
      }
      func customerEvents() -> [[String: Any]] { NativeV3Transport.events.filter { $0["distinct_id"] as? String == customer } }
      try await wait("All 45 distinct probes must complete native event transport") {
        let indexes = customerEvents().filter { $0["event"] as? String == "wrapper_v3_flush_probe" }
          .compactMap { ($0["properties"] as? [String: Any])?["index"] as? Int }
        return Set(indexes) == Set(0..<45)
      }
      XCTAssertTrue(NativeV3Transport.violations.isEmpty, NativeV3Transport.violations.joined(separator: "; "))
      let journeys = activities()
      let nativeJourneys = customerEvents().filter {
        ["$journey_leg_started", "$journey_leg_completed"].contains($0["event"] as? String ?? "")
      }
      if accepted {
        XCTAssertEqual(journeys.compactMap { $0["name"] as? String }, ["journey_started", "journey_completed"])
        let properties = try journeys.map { try XCTUnwrap($0["properties"] as? [String: Any]) }
        for item in properties {
          XCTAssertEqual(item["experience_id"] as? String, "experience_wrapper_v3")
          XCTAssertEqual(item["experience_version"] as? String, "version_wrapper_v3")
          XCTAssertEqual(item["leg_id"] as? String, String(repeating: "a", count: 64))
          XCTAssertEqual(item["leg_generation"] as? Int, 0)
          XCTAssertNotNil(UUID(uuidString: try XCTUnwrap(item["journey_id"] as? String)))
        }
        XCTAssertEqual(properties.first?["journey_id"] as? String, properties.last?["journey_id"] as? String)
        XCTAssertEqual(properties.last?["outcome"] as? String, "continue")
        XCTAssertEqual(nativeJourneys.compactMap { $0["event"] as? String }, ["$journey_leg_started", "$journey_leg_completed"])
        for item in nativeJourneys {
          let context = try XCTUnwrap(item["properties"] as? [String: Any])
          XCTAssertEqual(context["journey_id"] as? String, properties.last?["journey_id"] as? String)
          XCTAssertEqual(context["experience_id"] as? String, "experience_wrapper_v3")
          XCTAssertEqual(context["experience_version_id"] as? String, "version_wrapper_v3")
          XCTAssertEqual(context["leg_id"] as? String, String(repeating: "a", count: 64))
          XCTAssertEqual(context["leg_generation"] as? Int, 0)
        }
        XCTAssertEqual(Set(nativeJourneys.compactMap { $0["idempotency_key"] as? String }).count, 2)
        let completion = try XCTUnwrap(nativeJourneys.last)
        let nativeProperties = try XCTUnwrap(completion["properties"] as? [String: Any])
        let outputs = try XCTUnwrap(nativeProperties["outputs"] as? [String: Any])
        XCTAssertEqual(try json(outputs), try json(["event": values, "responses": [:]] as [String: Any]))
        XCTAssertEqual(nativeProperties["journey_id"] as? String, properties.last?["journey_id"] as? String)
        XCTAssertEqual(nativeProperties["outcome"] as? String, "continue")
      } else {
        XCTAssertEqual(NuxieSDK.shared.features.state, .unknown, "Rejected profile must not publish authoritative access")
        XCTAssertTrue(journeys.isEmpty, "Retired schema/signature must not admit a Journey through the adapter")
        XCTAssertTrue(nativeJourneys.isEmpty, "Retired schema/signature must not capture native Journey events")
      }
      print("NATIVE_V3_VERDICT vector=\(vector) accepted=\(accepted) profileRequests=\(NativeV3Transport.profileRequests) activities=\(journeys.count) nativeJourneyEvents=\(nativeJourneys.count)")
      _ = try await invoke(bridge, "shutdown", ["session": session])
    } catch {
      XCTAssertTrue(NativeV3Transport.violations.isEmpty, NativeV3Transport.violations.joined(separator: "; "))
      _ = try? await invoke(bridge, "shutdown", ["session": session])
      throw error
    }
    XCTAssertFalse(NuxieSDK.shared.isSetup)
  }
}

/// A transport fixture, not a native SDK fake: original signed bytes enter the
/// SDK's network parser, verifier, storage, event routing and Journey executor.
private final class NativeV3Transport: URLProtocol, @unchecked Sendable {
  private static let lock = NSLock()
  nonisolated(unsafe) private static var profile = Data()
  nonisolated(unsafe) private static var expectedApiKey = ""
  nonisolated(unsafe) private static var customers: [String] = []
  nonisolated(unsafe) private static var captured: [[String: Any]] = []
  nonisolated(unsafe) private static var failures: [String] = []
  nonisolated(unsafe) private static var hosts: Set<String> = []
  static func reset(_ data: Data, apiKey: String) {
    lock.withLock { profile = data; expectedApiKey = apiKey; customers = []; captured = []; failures = []; hosts = [] }
  }
  static var profileRequests: Int { lock.withLock { customers.count } }
  static var profileCustomers: [String] { lock.withLock { customers } }
  static var events: [[String: Any]] { lock.withLock { captured } }
  static var violations: [String] { lock.withLock { failures } }
  static var offeredHosts: [String] { lock.withLock { hosts.sorted() } }
  override class func canInit(with request: URLRequest) -> Bool {
    if let host = request.url?.host { lock.withLock { _ = hosts.insert(host) } }
    return request.url?.host == "wrapper-v3-api.nuxie.test"
  }
  override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
  override func stopLoading() {}
  private func fail(_ message: String) {
    Self.lock.withLock { Self.failures.append(message) }
    client?.urlProtocol(self, didFailWithError: NSError(domain: "NativeV3Transport", code: 1,
      userInfo: [NSLocalizedDescriptionKey: message]))
  }
  override func startLoading() {
    guard let url = request.url else { fail("Missing URL"); return }
    var body = request.httpBody ?? Data()
    if body.isEmpty, let stream = request.httpBodyStream {
      stream.open(); defer { stream.close() }
      var buffer = [UInt8](repeating: 0, count: 4096)
      while stream.hasBytesAvailable { let count = stream.read(&buffer, maxLength: buffer.count); if count <= 0 { break }; body.append(buffer, count: count) }
    }
    guard request.httpMethod == "POST", request.value(forHTTPHeaderField: "Content-Encoding") == nil,
      let parsed = (try? JSONSerialization.jsonObject(with: body)) as? [String: Any],
      parsed["apiKey"] as? String == Self.lock.withLock({ Self.expectedApiKey }) else {
      fail("Expected the native POST JSON transport with this case's apiKey"); return
    }
    var headers = ["Content-Type": "application/json"]
    let response: Data
    switch url.path {
    case "/profile":
      guard let customer = parsed["distinct_id"] as? String, !customer.isEmpty else {
        fail("Profile must encode distinct_id"); return
      }
      headers["Nuxie-App-Id"] = "app_wrapper_v3"; headers["Nuxie-App-Environment"] = "test"
      response = Self.lock.withLock { Self.customers.append(customer); return Self.profile }
      headers["ETag"] = "\"" + SHA256.hash(data: response).map { String(format: "%02x", $0) }.joined() + "\""
    case "/batch", "/event":
      let events = url.path == "/batch" ? parsed["batch"] as? [[String: Any]] : [parsed]
      guard let events, !events.isEmpty, events.allSatisfy({
        $0["event"] is String && $0["distinct_id"] is String && $0["idempotency_key"] is String
      }) else { fail("Native event transport must carry event, distinct_id and idempotency_key"); return }
      Self.lock.withLock { Self.captured.append(contentsOf: events) }
      response = try! JSONSerialization.data(withJSONObject: ["status": "ok", "processed": events.count, "failed": 0, "total": events.count])
    default:
      fail("Unexpected native API route: " + url.path); return
    }
    let http = HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: headers)!
    client?.urlProtocol(self, didReceive: http, cacheStoragePolicy: .notAllowed)
    client?.urlProtocol(self, didLoad: response)
    client?.urlProtocolDidFinishLoading(self)
  }
}
