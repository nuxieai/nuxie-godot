import XCTest
@testable import NuxieGodotBridge

final class BridgeRuntimeTests: XCTestCase {
  override func tearDown() {
    super.tearDown()
    drainPendingEvents()
  }

  func testInvokeReturnsErrorForMalformedArgs() {
    let response = invoke(method: "configure", rawArgsJSON: "not-json")
    XCTAssertEqual(response["ok"] as? Bool, false)

    guard let error = response["error"] as? [String: Any] else {
      XCTFail("Expected error payload")
      return
    }

    XCTAssertEqual(error["code"] as? String, "INVALID_CONFIGURATION")
  }

  func testConfigureWithMissingApiKeyEmitsOperationResultEvent() {
    drainPendingEvents()

    let response = invoke(method: "configure", args: [
      "apiKey": "",
      "requestId": "configure-1",
    ])
    XCTAssertEqual(response["ok"] as? Bool, true)

    let envelope = waitForPendingEvent(timeout: 0.5)
    XCTAssertNotNil(envelope)
    XCTAssertEqual(envelope?["event"] as? String, "operation_result")

    guard let payload = envelope?["payload"] as? [String: Any] else {
      XCTFail("Missing operation_result payload")
      return
    }

    XCTAssertEqual(payload["requestId"] as? String, "configure-1")
    XCTAssertEqual(payload["method"] as? String, "configure")
    XCTAssertEqual(payload["ok"] as? Bool, false)

    guard let error = payload["error"] as? [String: Any] else {
      XCTFail("Missing error payload")
      return
    }

    XCTAssertEqual(error["code"] as? String, "MISSING_API_KEY")
  }

  private func invoke(method: String, args: [String: Any]) -> [String: Any] {
    invoke(method: method, rawArgsJSON: jsonString(args))
  }

  private func invoke(method: String, rawArgsJSON: String) -> [String: Any] {
    let responsePtr = method.withCString { methodCString in
      rawArgsJSON.withCString { argsCString in
        NuxieGodot_Invoke(methodCString, argsCString)
      }
    }

    guard let responsePtr else {
      return [
        "ok": false,
        "error": [
          "code": "NATIVE_ERROR",
          "message": "Missing response from C API",
        ],
      ]
    }

    defer { NuxieGodot_FreeCString(responsePtr) }
    let responseString = String(cString: responsePtr)
    return dictionaryFromJSON(responseString) ?? [:]
  }

  private func waitForPendingEvent(timeout: TimeInterval) -> [String: Any]? {
    let deadline = Date().addingTimeInterval(timeout)
    while Date() < deadline {
      if let event = popPendingEvent() {
        return event
      }
      usleep(1_000)
    }
    return nil
  }

  private func popPendingEvent() -> [String: Any]? {
    guard NuxieGodot_GetPendingEventCount() > 0 else {
      return nil
    }

    guard let eventPtr = NuxieGodot_PopPendingEvent() else {
      return nil
    }

    defer { NuxieGodot_FreeCString(eventPtr) }

    let eventJSON = String(cString: eventPtr)
    return dictionaryFromJSON(eventJSON)
  }

  private func drainPendingEvents() {
    while NuxieGodot_GetPendingEventCount() > 0 {
      guard let eventPtr = NuxieGodot_PopPendingEvent() else {
        break
      }
      NuxieGodot_FreeCString(eventPtr)
    }
  }
}
