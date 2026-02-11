import XCTest
@testable import NuxieGodotBridge
@preconcurrency import Nuxie

final class PurchaseMappingTests: XCTestCase {
  func testPurchasePayloadSuccessMapping() {
    let payload: [String: Any] = [
      "type": "success",
      "productId": "pro_monthly",
      "transactionId": "tx_1",
    ]

    let outcome = payload.toPurchaseOutcome(defaultProductId: "fallback")
    XCTAssertEqual(outcome.productId, "pro_monthly")

    if case .success = outcome.result {
      XCTAssertTrue(true)
    } else {
      XCTFail("Expected success")
    }
  }

  func testPurchasePayloadFallbackMapping() {
    let payload: [String: Any] = [
      "type": "failed",
      "message": "purchase_failed_test",
    ]

    let outcome = payload.toPurchaseOutcome(defaultProductId: "fallback")
    XCTAssertEqual(outcome.productId, "fallback")

    if case .failed = outcome.result {
      XCTAssertTrue(true)
    } else {
      XCTFail("Expected failed")
    }
  }

  func testRestorePayloadMapping() {
    let success: [String: Any] = [
      "type": "success",
      "restoredCount": 2,
    ]

    let noPurchases: [String: Any] = [
      "type": "no_purchases",
    ]

    switch success.toRestoreResult() {
    case .success(let restoredCount):
      XCTAssertEqual(restoredCount, 2)
    default:
      XCTFail("Expected success")
    }

    switch noPurchases.toRestoreResult() {
    case .noPurchases:
      XCTAssertTrue(true)
    default:
      XCTFail("Expected no purchases")
    }
  }

  func testPurchaseDelegateTimeoutProducesFailedOutcome() async {
    let bridge = NuxieGodotPurchaseDelegateBridge { _, _ in }
    bridge.timeoutSeconds = 0.01

    let product = MockStoreProduct(
      id: "pro_monthly",
      displayName: "Pro Monthly",
      price: 9.99,
      displayPrice: "$9.99"
    )

    let outcome = await bridge.purchaseOutcome(product)
    XCTAssertEqual(outcome.productId, "pro_monthly")

    switch outcome.result {
    case .failed(let error):
      XCTAssertEqual((error as NSError).localizedDescription, "purchase_timeout")
    default:
      XCTFail("Expected timeout failure")
    }
  }

  func testRestoreDelegateTimeoutProducesFailedOutcome() async {
    let bridge = NuxieGodotPurchaseDelegateBridge { _, _ in }
    bridge.timeoutSeconds = 0.01

    let result = await bridge.restore()
    switch result {
    case .failed(let error):
      XCTAssertEqual((error as NSError).localizedDescription, "restore_timeout")
    default:
      XCTFail("Expected timeout failure")
    }
  }

  func testCompletePurchaseReturnsFalseForUnknownRequest() {
    let bridge = NuxieGodotPurchaseDelegateBridge { _, _ in }
    let completed = bridge.completePurchase(requestId: "missing", payload: ["type": "success"])
    XCTAssertFalse(completed)
  }

  func testCompleteRestoreReturnsFalseForUnknownRequest() {
    let bridge = NuxieGodotPurchaseDelegateBridge { _, _ in }
    let completed = bridge.completeRestore(requestId: "missing", payload: ["type": "success"])
    XCTAssertFalse(completed)
  }
}
