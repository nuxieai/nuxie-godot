import Foundation
@preconcurrency import Nuxie

final class NuxieGodotPurchaseDelegateBridge: NuxiePurchaseDelegate, @unchecked Sendable {
  private let emit: (String, [String: Any]) -> Void
  private let timeoutSeconds: TimeInterval
  private let lock = NSLock()
  private var purchaseContinuations: [String: CheckedContinuation<PurchaseResult, Never>] = [:]
  private var restoreContinuations: [String: CheckedContinuation<RestoreResult, Never>] = [:]

  init(
    timeoutSeconds: TimeInterval = 60,
    emit: @escaping (String, [String: Any]) -> Void
  ) {
    self.timeoutSeconds = timeoutSeconds
    self.emit = emit
  }

  func purchase(product: StoreProduct) async -> PurchaseResult {
    let requestId = UUID().uuidString
    let payload: [String: Any] = [
      "request_id": requestId,
      "platform": "ios",
      "product_id": product.productId,
      "store_product_id": product.storeProductId,
      "base_plan_id": NSNull(),
      "purchase_option_id": NSNull(),
      "offer_id": NSNull(),
      "placement_id": product.placementId,
      "display_name": product.name,
      "display_price": product.price,
      "timestamp_ms": bridgeNowMs(),
    ]

    return await withCheckedContinuation { continuation in
      lock.withLock {
        purchaseContinuations[requestId] = continuation
      }
      emit("purchase_request", payload)
      schedulePurchaseTimeout(requestId: requestId)
    }
  }

  func restorePurchases() async -> RestoreResult {
    let requestId = UUID().uuidString
    let payload: [String: Any] = [
      "request_id": requestId,
      "platform": "ios",
      "timestamp_ms": bridgeNowMs(),
    ]

    return await withCheckedContinuation { continuation in
      lock.withLock {
        restoreContinuations[requestId] = continuation
      }
      emit("restore_request", payload)
      scheduleRestoreTimeout(requestId: requestId)
    }
  }

  func completePurchase(requestId: String, payload: [String: Any]) {
    let continuation = lock.withLock {
      purchaseContinuations.removeValue(forKey: requestId)
    }
    continuation?.resume(returning: purchaseResult(from: payload))
  }

  func completeRestore(requestId: String, payload: [String: Any]) {
    let continuation = lock.withLock {
      restoreContinuations.removeValue(forKey: requestId)
    }
    continuation?.resume(returning: restoreResult(from: payload))
  }

  func cancelPending(reason: String) {
    let (purchases, restores) = lock.withLock {
      let purchases = Array(purchaseContinuations.values)
      let restores = Array(restoreContinuations.values)
      purchaseContinuations.removeAll()
      restoreContinuations.removeAll()
      return (purchases, restores)
    }
    purchases.forEach { $0.resume(returning: .failed(bridgeError(reason))) }
    restores.forEach { $0.resume(returning: .failed(bridgeError(reason))) }
  }

  private func schedulePurchaseTimeout(requestId: String) {
    Task { [weak self] in
      guard let self else { return }
      try? await Task.sleep(nanoseconds: UInt64(self.timeoutSeconds * 1_000_000_000))
      let continuation = self.lock.withLock {
        self.purchaseContinuations.removeValue(forKey: requestId)
      }
      continuation?.resume(returning: .failed(self.bridgeError("purchase_timeout")))
    }
  }

  private func scheduleRestoreTimeout(requestId: String) {
    Task { [weak self] in
      guard let self else { return }
      try? await Task.sleep(nanoseconds: UInt64(self.timeoutSeconds * 1_000_000_000))
      let continuation = self.lock.withLock {
        self.restoreContinuations.removeValue(forKey: requestId)
      }
      continuation?.resume(returning: .failed(self.bridgeError("restore_timeout")))
    }
  }

  private func purchaseResult(from payload: [String: Any]) -> PurchaseResult {
    switch (payload["type"] as? String)?.lowercased() {
    case "purchased": .purchased
    case "cancelled": .cancelled
    case "pending": .pending
    default: .failed(bridgeError((payload["message"] as? String) ?? "purchase_failed"))
    }
  }

  private func restoreResult(from payload: [String: Any]) -> RestoreResult {
    switch (payload["type"] as? String)?.lowercased() {
    case "restored": .restored
    case "no_purchases": .noPurchases
    default: .failed(bridgeError((payload["message"] as? String) ?? "restore_failed"))
    }
  }

  private func bridgeError(_ message: String) -> Error {
    NSError(
      domain: "ai.nuxie.godot",
      code: 1,
      userInfo: [NSLocalizedDescriptionKey: message]
    )
  }
}
