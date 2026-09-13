import Foundation

#if canImport(Nuxie)
import Nuxie

final class NuxiePurchaseDelegateBridge: NuxiePurchaseDelegate, @unchecked Sendable {
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
      "requestId": requestId,
      "deadlineMs": Int((Date().timeIntervalSince1970 + timeoutSeconds) * 1_000),
      "product": [
        "platform": "ios", "productId": product.productId, "storeProductId": product.storeProductId,
        "placementId": product.placementId, "displayName": product.name, "displayPrice": product.price,
        "description": product.description, "productType": product.productType.rawValue,
        "period": nuxieNullable(product.period?.rawValue), "periodCount": nuxieNullable(product.periodCount),
        "eligibilityJws": nuxieNullable(product.introductoryOfferEligibilityJWS), "billingPlan": product.billingPlan.rawValue,
        "introductoryTerms": nuxieNullable(product.introductoryTerms.map { terms in [
          "price": terms.price, "period": terms.period.rawValue, "periodCount": terms.periodCount,
          "cycles": terms.cycles, "paymentMode": terms.paymentMode.rawValue, "displayDuration": terms.trialPeriodText,
        ] as [String: Any] }),
      ] as [String: Any],
    ]

    return await withCheckedContinuation { continuation in
      lock.withLock {
        purchaseContinuations[requestId] = continuation
      }
      emit("purchase", payload)
      schedulePurchaseTimeout(requestId: requestId)
    }
  }

  func restorePurchases() async -> RestoreResult {
    let requestId = UUID().uuidString
    let payload: [String: Any] = [
      "requestId": requestId,
      "deadlineMs": Int((Date().timeIntervalSince1970 + timeoutSeconds) * 1_000),
      "platform": "ios",
      "timestamp_ms": Int(Date().timeIntervalSince1970 * 1_000),
    ]

    return await withCheckedContinuation { continuation in
      lock.withLock {
        restoreContinuations[requestId] = continuation
      }
      emit("restore", payload)
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

  func cancelPending() {
    let (purchases, restores) = lock.withLock {
      let purchases = Array(purchaseContinuations.values)
      let restores = Array(restoreContinuations.values)
      purchaseContinuations.removeAll()
      restoreContinuations.removeAll()
      return (purchases, restores)
    }
    purchases.forEach { $0.resume(returning: .failed(bridgeError("sdk_shutdown"))) }
    restores.forEach { $0.resume(returning: .failed(bridgeError("sdk_shutdown"))) }
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
    switch (payload["type"] as? String) {
    case "purchased": .purchased
    case "cancelled": .cancelled
    case "pending": .pending
    default: .failed(bridgeError((payload["message"] as? String) ?? "purchase_failed"))
    }
  }

  private func restoreResult(from payload: [String: Any]) -> RestoreResult {
    switch (payload["type"] as? String) {
    case "restored": .restored
    case "noPurchases": .noPurchases
    default: .failed(bridgeError((payload["message"] as? String) ?? "restore_failed"))
    }
  }

  private func bridgeError(_ message: String) -> Error {
    NSError(
      domain: "io.nuxie.godot",
      code: 1,
      userInfo: [NSLocalizedDescriptionKey: message]
    )
  }
}
#endif
