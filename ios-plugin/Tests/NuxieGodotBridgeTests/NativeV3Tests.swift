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
  private func wait(_ label: String, _ condition: () async throws -> Bool) async throws {
    let deadline = Date().addingTimeInterval(20)
    var satisfied = try await condition()
    while !satisfied && Date() < deadline {
      try await Task.sleep(nanoseconds: 50_000_000)
      satisfied = try await condition()
    }
    XCTAssertTrue(satisfied, label)
    if !satisfied { throw NSError(domain: "NativeV3Tests", code: 1, userInfo: [NSLocalizedDescriptionKey: label]) }
  }
  private func exercise(_ vector: String, accepted: Bool) async throws {
    XCTAssertFalse(NuxieSDK.shared.isSetup)
    let fixture = try NativeV3FixtureClient()
    let apiKey = "pk_test_wrapper_\(UUID().uuidString)"
    let customer = "wrapper-v3-\(UUID().uuidString)"
    _ = try await fixture.post("/v3/register", ["vector": vector, "apiKey": apiKey,
      "customerId": customer, "processId": Int(ProcessInfo.processInfo.processIdentifier)])
    XCTAssertEqual(ProcessInfo.processInfo.environment["NUXIE_GODOT_API_ENDPOINT"], fixture.endpoint.absoluteString)
    let bridge = NuxieGodotRuntime()
    var emitted: [[String: Any]] = []
    bridge.emit = { value in
      if let data = value.data(using: .utf8), let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
        emitted.append(object)
      }

    }
    let session = UUID().uuidString
    var observation: [String: Any] = [:]
    do {
      // An external stream must actually observe this process before native
      // configuration; authentication errors cannot be inferred from silence.
      os_log("NATIVE_V3_LOG_READY %{public}@", log: OSLog(subsystem: "io.nuxie.wrapper.v3-tests", category: "NativeV3Tests"), type: .default, apiKey)
      try await wait("External simulator log stream must observe this XCTest process") {
        try await fixture.snapshot(apiKey)["logReady"] as? Bool == true
      }
      let configured = try await invoke(bridge, "configure", ["configuration": try json([
        "contract": 1, "session": session, "apiKey": apiKey,
        "environment": "development", "logLevel": "debug", "purchaseHandlingMode": "observer", "externalBilling": false,

      ])])
      let configuredJSON = try XCTUnwrap(configured as? String).data(using: .utf8)
      let configuredObject = try XCTUnwrap(JSONSerialization.jsonObject(with: try XCTUnwrap(configuredJSON)) as? [String: Any])
      observation["nativeVersion"] = try XCTUnwrap(configuredObject["nativeVersion"] as? String)
      try await wait("Native startup must fetch the signed profile") {
        !(try await fixture.profiles(apiKey)).isEmpty
      }
      _ = try await invoke(bridge, "identify", ["session": session, "customerId": customer, "properties": "{}"])
      try await wait("Fresh customer must receive its profile") {
        let profiles = try await fixture.profiles(apiKey)
        return profiles.contains { ($0["body"] as? [String: Any])?["distinct_id"] as? String == customer }
      }
      if accepted { try await wait("Signed v3 profile must publish authoritative readiness") { NuxieSDK.shared.features.state == .ready } }
      else {
        // This is the real native error site, PID and event timestamp from the
        // owned simulator stream after this customer's exact bytes were sent.
        var authenticationFailure: [String: Any]?
        try await wait("Native profile authentication must explicitly fail") {
          let snapshot = try await fixture.snapshot(apiKey)
          authenticationFailure = (snapshot["authenticationFailures"] as? [[String: Any]])?.first
          return authenticationFailure != nil
        }
        print("NATIVE_V3_AUTH_REJECTION vector=\(vector) message=\(try json(try XCTUnwrap(authenticationFailure)))")
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
      func customerEvents(_ snapshot: [String: Any]) -> [[String: Any]] {
        (snapshot["events"] as? [[String: Any]] ?? []).filter { $0["distinct_id"] as? String == customer }
      }
      try await wait("All 45 distinct probes must complete native event transport") {
        let indexes = customerEvents(try await fixture.snapshot(apiKey)).filter { $0["event"] as? String == "wrapper_v3_flush_probe" }
          .compactMap { ($0["properties"] as? [String: Any])?["index"] as? Int }
        return Set(indexes) == Set(0..<45)
      }
      let snapshot = try await fixture.snapshot(apiKey)
      XCTAssertEqual(snapshot["violations"] as? [String], [])
      let journeys = activities()
      let nativeJourneys = customerEvents(snapshot).filter {
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
      observation["activities"] = journeys
      observation["finalFeatureState"] = String(describing: NuxieSDK.shared.features.state)
      _ = try await invoke(bridge, "shutdown", ["session": session])
      XCTAssertFalse(NuxieSDK.shared.isSetup)
      _ = try await fixture.post("/v3/finish", ["apiKey": apiKey, "teardownCompleted": !NuxieSDK.shared.isSetup,
        "observation": observation, "failure": NSNull()])
      print("NATIVE_V3_OBSERVATION vector=\(vector) accepted=\(accepted) profileRequests=\((snapshot["profiles"] as? [Any])?.count ?? 0) activities=\(journeys.count) nativeJourneyEvents=\(nativeJourneys.count) teardownCompleted=true")
    } catch {
      _ = try? await invoke(bridge, "shutdown", ["session": session])
      _ = try? await fixture.post("/v3/finish", ["apiKey": apiKey, "teardownCompleted": !NuxieSDK.shared.isSetup,
        "observation": observation, "failure": String(describing: error)])
      throw error
    }
    XCTAssertFalse(NuxieSDK.shared.isSetup)
  }
}

/// The separate observation client talks to the owning loopback fixture. Native
/// requests use the shipped adapter's endpoint and original URLSession transport.
@MainActor
private struct NativeV3FixtureClient {
  let endpoint: URL
  init() throws {
    guard let value = ProcessInfo.processInfo.environment["NUXIE_NATIVE_V3_FIXTURE_ENDPOINT"],
      let endpoint = URL(string: value), endpoint.scheme == "http", endpoint.host == "127.0.0.1", endpoint.port != nil else {
      throw NSError(domain: "NativeV3Tests", code: 1, userInfo: [NSLocalizedDescriptionKey: "Run the owning test-ios frontend with its private loopback fixture"])
    }
    self.endpoint = endpoint
  }
  func request(_ path: String, body: [String: Any]? = nil) async throws -> [String: Any] {
    var request = URLRequest(url: try XCTUnwrap(URL(string: path, relativeTo: endpoint)))
    request.timeoutInterval = 5
    if let body {
      request.httpMethod = "POST"
      request.setValue("application/json", forHTTPHeaderField: "Content-Type")
      request.httpBody = try JSONSerialization.data(withJSONObject: body)
    }
    let (data, response) = try await URLSession.shared.data(for: request)
    guard (response as? HTTPURLResponse)?.statusCode == 200 else {
      throw NSError(domain: "NativeV3Tests", code: 1, userInfo: [NSLocalizedDescriptionKey: "Fixture HTTP failure: " + String(decoding: data, as: UTF8.self)])
    }
    return try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
  }
  func post(_ path: String, _ body: [String: Any]) async throws -> [String: Any] { try await request(path, body: body) }
  func snapshot(_ apiKey: String) async throws -> [String: Any] { try await request("/v3/status?apiKey=" + apiKey) }
  func profiles(_ apiKey: String) async throws -> [[String: Any]] {
    let value = try await snapshot(apiKey)
    return try XCTUnwrap(value["profiles"] as? [[String: Any]])
  }
}
