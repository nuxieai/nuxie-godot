import XCTest
import Nuxie
@testable import NuxieGodotBridge

final class BridgeMappingTests: XCTestCase {
  func testRestoreHasBoundedSettlement() async {
    let bridge = NuxiePurchaseDelegateBridge(timeoutSeconds: 0.01) { _, _ in }
    let result = await bridge.restorePurchases()
    guard case .failed = result else { return XCTFail("Missing controller reply must time out") }
  }

  func testRestoreCorrelationAndDuplicateCompletion() async {
    var bridge: NuxiePurchaseDelegateBridge!
    bridge = NuxiePurchaseDelegateBridge { name, payload in
      XCTAssertEqual(name, "restore")
      let id = payload["requestId"] as! String
      bridge.completeRestore(requestId: "wrong-id", payload: ["type": "failed"])
      bridge.completeRestore(requestId: id, payload: ["type": "restored"])
      bridge.completeRestore(requestId: id, payload: ["type": "failed"])
    }
    let result = await bridge.restorePurchases()
    guard case .restored = result else { return XCTFail("Matching first result wins") }
  }
}
