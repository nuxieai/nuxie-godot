import Foundation
@preconcurrency import Nuxie

@MainActor
final class NuxieGodotDelegateBridge: NuxieDelegate {
  private let emit: (String, [String: Any]) -> Void

  init(emit: @escaping (String, [String: Any]) -> Void) {
    self.emit = emit
  }

  func featureAccessDidChange(
    _ featureId: String,
    from oldValue: FeatureAccess?,
    to newValue: FeatureAccess
  ) {
    emit(
      "feature_access_changed",
      [
        "featureId": featureId,
        "from": nullable(oldValue.map(featureAccessDictionary)),
        "to": featureAccessDictionary(newValue),
        "timestampMs": bridgeNowMs(),
      ]
    )
  }

  func nuxieDidEmit(_ info: NuxieActivityInfo) {
    emit(
      "activity",
      [
        "schemaVersion": NuxieActivityInfo.schemaVersion,
        "id": info.id,
        "timestampMs": Int(info.timestamp.timeIntervalSince1970 * 1_000),
        "receivedAtMs": Int(info.receivedAt.timeIntervalSince1970 * 1_000),
        "name": info.name,
        "properties": info.properties.mapValues(activityValue),
      ]
    )
  }

  func nuxie(_ sdk: NuxieSDK, didRequestAppAction action: AppAction) {
    emit(
      "app_action",
      [
        "name": action.name,
        "payload": nullable(action.payload?.mapValues(appActionValue)),
        "experience": [
          "experienceId": action.experience.experienceId,
          "experienceVersion": nullable(action.experience.experienceVersion),
          "journeyId": nullable(action.experience.journeyId),
        ],
      ]
    )
  }
}

private func activityValue(_ value: NuxieActivityValue) -> Any {
  switch value {
  case .string(let value): value
  case .int(let value): value
  case .double(let value): value
  case .bool(let value): value
  @unknown default: String(describing: value)
  }
}

private func appActionValue(_ value: AppActionValue) -> Any {
  switch value {
  case .string(let value): value
  case .int(let value): value
  case .double(let value): value
  case .bool(let value): value
  @unknown default: String(describing: value)
  }
}
