import Foundation
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
    NativeV3Transport.reset(profile)
    XCTAssertTrue(URLProtocol.registerClass(NativeV3Transport.self))
    setenv("NUXIE_GODOT_API_ENDPOINT", "https://wrapper-v3-api.nuxie.test", 1)
    defer { URLProtocol.unregisterClass(NativeV3Transport.self); unsetenv("NUXIE_GODOT_API_ENDPOINT") }
    let nativeLogs = try OSLogStore(scope: .currentProcessIdentifier)
    let logPosition = nativeLogs.position(date: Date())
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
        "contract": 1, "session": session, "apiKey": "pk_test_wrapper_\(UUID().uuidString)",
        "environment": "development", "logLevel": "debug", "purchaseHandlingMode": "observer", "externalBilling": false,
        "testingApiEndpoint": "https://wrapper-v3-api.nuxie.test",
      ])])
      XCTAssertNotNil(configured)
      try await wait("Native startup must fetch the signed profile") { NativeV3Transport.profileRequests > 0 }
      let requests = NativeV3Transport.profileRequests
      _ = try await invoke(bridge, "identify", ["session": session, "customerId": "wrapper-v3-\(UUID().uuidString)", "properties": "{}"])
      try await wait("Fresh customer must receive its profile") { NativeV3Transport.profileRequests > requests }
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
      try await wait("Actual native event transport must be functioning") {
        NativeV3Transport.events.contains { $0["event"] as? String == "wrapper_v3_flush_probe" }
      }
      try await Task.sleep(nanoseconds: 2_000_000_000)
      let journeys = activities()
      let nativeJourneys = NativeV3Transport.events.filter {
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
        let completion = try XCTUnwrap(nativeJourneys.first { $0["event"] as? String == "$journey_leg_completed" })
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
  nonisolated(unsafe) private static var requests = 0
  nonisolated(unsafe) private static var captured: [[String: Any]] = []
  static func reset(_ data: Data) { lock.withLock { profile = data; requests = 0; captured = [] } }
  static var profileRequests: Int { lock.withLock { requests } }
  static var events: [[String: Any]] { lock.withLock { captured } }
  override class func canInit(with request: URLRequest) -> Bool { request.url?.host == "wrapper-v3-api.nuxie.test" }
  override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
  override func stopLoading() {}
  override func startLoading() {
    guard let url = request.url else { return }
    var headers = ["Content-Type": "application/json"]
    let response: Data
    if url.path == "/profile" {
      headers["Nuxie-App-Id"] = "app_wrapper_v3"; headers["Nuxie-App-Environment"] = "test"
      response = Self.lock.withLock { Self.requests += 1; return Self.profile }
    } else {
      var body = request.httpBody ?? Data()
      if body.isEmpty, let stream = request.httpBodyStream {
        stream.open(); defer { stream.close() }
        var buffer = [UInt8](repeating: 0, count: 4096)
        while stream.hasBytesAvailable { let count = stream.read(&buffer, maxLength: buffer.count); if count <= 0 { break }; body.append(buffer, count: count) }
      }
      let parsed = (try? JSONSerialization.jsonObject(with: body)) as? [String: Any] ?? [:]
      let events = parsed["batch"] as? [[String: Any]] ?? (parsed["event"] is String ? [parsed] : [])
      Self.lock.withLock { Self.captured.append(contentsOf: events) }
      response = try! JSONSerialization.data(withJSONObject: ["status": "ok", "processed": events.count, "failed": 0, "total": events.count])
    }
    let http = HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: headers)!
    client?.urlProtocol(self, didReceive: http, cacheStoragePolicy: .notAllowed)
    client?.urlProtocol(self, didLoad: response)
    client?.urlProtocolDidFinishLoading(self)
  }
}
