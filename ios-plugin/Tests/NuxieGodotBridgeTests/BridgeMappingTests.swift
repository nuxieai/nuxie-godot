import XCTest
@preconcurrency import Nuxie
@testable import NuxieGodotBridge

final class BridgeMappingTests: XCTestCase {
  func testUsageResultPreservesFractionalValuesAndNullAuthority() {
    let result = FeatureUsageResult(
      success: true,
      featureId: "credits",
      amountUsed: 1.25,
      message: nil,
      usage: .init(current: 3.75, limit: 10, remaining: 6.25)
    )

    let payload = featureUsageResultDictionary(result)
    XCTAssertEqual(payload["featureId"] as? String, "credits")
    XCTAssertEqual(payload["amountUsed"] as? Double, 1.25)
    XCTAssertTrue(payload["message"] is NSNull)
    XCTAssertTrue(payload["authoritativeAccess"] is NSNull)

    let usage = payload["usage"] as? [String: Any]
    XCTAssertEqual(usage?["remaining"] as? Double, 6.25)
  }

  func testJSONRoundTripPreservesSnakeCaseCommerceKeys() {
    let payload: [String: Any] = [
      "request_id": "purchase-1",
      "product_id": "pro",
      "store_product_id": "pro.monthly",
      "timestamp_ms": 42,
    ]

    XCTAssertEqual(dictionaryFromJSON(jsonString(payload))?["request_id"] as? String, "purchase-1")
    XCTAssertNil(dictionaryFromJSON(jsonString(payload))?["requestId"])
  }
}
