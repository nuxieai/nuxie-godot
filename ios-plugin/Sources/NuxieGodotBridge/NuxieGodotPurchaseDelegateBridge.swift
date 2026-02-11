import Foundation
@preconcurrency import Nuxie

final class NuxieGodotPurchaseDelegateBridge: NuxiePurchaseDelegate {
  private struct PendingPurchase {
    let productId: String
    let continuation: CheckedContinuation<PurchaseOutcome, Never>
  }

  private let emit: (String, [String: Any]) -> Void
  private let lock = NSLock()

  var timeoutSeconds: TimeInterval = 60

  private var purchaseContinuations: [String: PendingPurchase] = [:]
  private var restoreContinuations: [String: CheckedContinuation<RestoreResult, Never>] = [:]

  init(emit: @escaping (String, [String: Any]) -> Void) {
    self.emit = emit
  }

  func purchase(_ product: any StoreProductProtocol) async -> PurchaseResult {
    await purchaseOutcome(product).result
  }

  func purchaseOutcome(_ product: any StoreProductProtocol) async -> PurchaseOutcome {
    let requestId = UUID().uuidString
    let payload: [String: Any] = [
      "requestId": requestId,
      "platform": "ios",
      "productId": product.id,
      "displayName": product.displayName,
      "displayPrice": product.displayPrice,
      "price": NSDecimalNumber(decimal: product.price).doubleValue,
      "timestampMs": bridgeNowMs(),
    ]

    return await withCheckedContinuation { continuation in
      lock.withLock {
        purchaseContinuations[requestId] = PendingPurchase(productId: product.id, continuation: continuation)
      }

      emit("purchase_request", payload)
      schedulePurchaseTimeout(requestId: requestId)
    }
  }

  func restore() async -> RestoreResult {
    let requestId = UUID().uuidString
    let payload: [String: Any] = [
      "requestId": requestId,
      "platform": "ios",
      "timestampMs": bridgeNowMs(),
    ]

    return await withCheckedContinuation { continuation in
      lock.withLock {
        restoreContinuations[requestId] = continuation
      }

      emit("restore_request", payload)
      scheduleRestoreTimeout(requestId: requestId)
    }
  }

  @discardableResult
  func completePurchase(requestId: String, payload: [String: Any]) -> Bool {
    let pending = lock.withLock {
      purchaseContinuations.removeValue(forKey: requestId)
    }

    guard let pending else { return false }
    pending.continuation.resume(returning: payload.toPurchaseOutcome(defaultProductId: pending.productId))
    return true
  }

  @discardableResult
  func completeRestore(requestId: String, payload: [String: Any]) -> Bool {
    let continuation = lock.withLock {
      restoreContinuations.removeValue(forKey: requestId)
    }

    guard let continuation else { return false }
    continuation.resume(returning: payload.toRestoreResult())
    return true
  }

  func clearPending(reason: String) {
    let snapshots = lock.withLock {
      let pendingPurchases = Array(purchaseContinuations.values)
      let pendingRestores = Array(restoreContinuations.values)
      purchaseContinuations.removeAll()
      restoreContinuations.removeAll()
      return (pendingPurchases, pendingRestores)
    }

    for pending in snapshots.0 {
      let outcome = PurchaseOutcome(
        result: .failed(nuxieBridgeError(reason)),
        productId: pending.productId
      )
      pending.continuation.resume(returning: outcome)
    }

    for continuation in snapshots.1 {
      continuation.resume(returning: .failed(nuxieBridgeError(reason)))
    }
  }

  private func schedulePurchaseTimeout(requestId: String) {
    let timeout = timeoutSeconds
    DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + timeout) { [weak self] in
      guard let self else { return }

      let pending = self.lock.withLock {
        self.purchaseContinuations.removeValue(forKey: requestId)
      }

      guard let pending else { return }
      pending.continuation.resume(
        returning: PurchaseOutcome(
          result: .failed(self.nuxieBridgeError("purchase_timeout")),
          productId: pending.productId
        )
      )
    }
  }

  private func scheduleRestoreTimeout(requestId: String) {
    let timeout = timeoutSeconds
    DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + timeout) { [weak self] in
      guard let self else { return }

      let continuation = self.lock.withLock {
        self.restoreContinuations.removeValue(forKey: requestId)
      }

      guard let continuation else { return }
      continuation.resume(returning: .failed(self.nuxieBridgeError("restore_timeout")))
    }
  }

  private func nuxieBridgeError(_ message: String) -> Error {
    NSError(domain: "io.nuxie.godot", code: 1, userInfo: [NSLocalizedDescriptionKey: message])
  }
}
