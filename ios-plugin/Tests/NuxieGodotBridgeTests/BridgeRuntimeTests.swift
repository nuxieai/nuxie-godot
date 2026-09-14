import XCTest
import Nuxie
@testable import NuxieGodotBridge

final class BridgeRuntimeTests: XCTestCase {
  private func invoke(_ bridge: NuxieGodotRuntime, _ method: String, _ arguments: [String: Any]) async -> String? {
    await withCheckedContinuation { continuation in
      bridge.invoke(method, arguments: arguments, resolve: { _ in continuation.resume(returning: nil) },
        reject: { code, _, _ in continuation.resume(returning: code) })
    }
  }

  private func configure(_ bridge: NuxieGodotRuntime, session: String, locale: String = "en") async -> String? {
    let input: [String: Any] = ["contract": 1, "session": session, "apiKey": "pk_test_godot_lifecycle",
      "environment": "development", "logLevel": "none", "localeIdentifier": locale,
      "purchaseHandlingMode": "observer", "externalBilling": false]
    let json = String(decoding: try! JSONSerialization.data(withJSONObject: input), as: UTF8.self)
    return await invoke(bridge, "configure", ["configuration": json])
  }

  @MainActor func testInvalidatedRuntimeCanTearDownRetainedSetup() async {
    setenv("NUXIE_GODOT_API_ENDPOINT", "http://127.0.0.1:1", 1)
    defer { unsetenv("NUXIE_GODOT_API_ENDPOINT") }
    let original = NuxieGodotRuntime()
    let initial = await configure(original, session: "original")
    XCTAssertNil(initial)
    original.invalidate()
    let detached = await invoke(original, "getIdentity", ["session": "original"])
    XCTAssertEqual(detached, "sessionExpired")
    XCTAssertTrue(NuxieSDK.shared.isSetup, "Invalidation retains the global native setup")

    let replacement = NuxieGodotRuntime()
    let conflicting = await configure(replacement, session: "replacement", locale: "fr")
    XCTAssertEqual(conflicting, "alreadyConfigured")
    let shutdown = await invoke(replacement, "shutdown", ["session": "replacement"])
    XCTAssertNil(shutdown, "A recreated runtime can tear down the orphaned Godot setup")
    XCTAssertFalse(NuxieSDK.shared.isSetup)
    let fresh = await configure(replacement, session: "fresh", locale: "fr")
    XCTAssertNil(fresh)
    _ = await invoke(replacement, "shutdown", ["session": "fresh"])
  }

  @MainActor func testShutdownCannotDetachAnotherRuntime() async {
    setenv("NUXIE_GODOT_API_ENDPOINT", "http://127.0.0.1:1", 1)
    defer { unsetenv("NUXIE_GODOT_API_ENDPOINT") }
    let owner = NuxieGodotRuntime()
    let initial = await configure(owner, session: "owner")
    XCTAssertNil(initial)
    let foreign = await invoke(NuxieGodotRuntime(), "shutdown", ["session": "foreign"])
    XCTAssertEqual(foreign, "sessionExpired")
    XCTAssertTrue(NuxieSDK.shared.isSetup)
    let identity = await invoke(owner, "getIdentity", ["session": "owner"])
    XCTAssertNil(identity)
    _ = await invoke(owner, "shutdown", ["session": "owner"])
  }

  func testShutdownAcknowledgesAnAlreadyDetachedSDK() async {
    let result = await invoke(NuxieGodotRuntime(), "shutdown", ["session": "old-session"])
    XCTAssertNil(result)
  }

  func testDetachedSessionFailsInsteadOfHanging() async {
    let bridge = NuxieGodotRuntime()
    let completed = expectation(description: "settled")
    bridge.invoke("getIdentity", arguments: ["session": "missing"], resolve: { _ in
      XCTFail("An unattached runtime must not read identity"); completed.fulfill()
    }, reject: { code, _, _ in
      XCTAssertEqual(code, "sessionExpired"); completed.fulfill()
    })
    await fulfillment(of: [completed], timeout: 5)
  }
}
