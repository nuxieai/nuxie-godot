import Foundation
@preconcurrency import Nuxie

final class NuxieGodotDelegateBridge: NuxieDelegate {
  private let emit: (String, [String: Any]) -> Void

  init(emit: @escaping (String, [String: Any]) -> Void) {
    self.emit = emit
  }

  @MainActor
  func featureAccessDidChange(_ featureId: String, from oldValue: FeatureAccess?, to newValue: FeatureAccess) {
    emit(
      "feature_access_changed",
      [
        "featureId": featureId,
        "from": featureAccessDictionary(oldValue) as Any,
        "to": featureAccessDictionary(newValue) as Any,
        "timestampMs": bridgeNowMs(),
      ]
    )
  }
}
