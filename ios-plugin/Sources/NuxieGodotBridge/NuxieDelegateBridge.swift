import Foundation

func nuxieNullable(_ value: Any?) -> Any {
  value ?? NSNull()
}

#if canImport(Nuxie)
import Nuxie

@MainActor
final class NuxieDelegateBridge: NuxieDelegate {
  private let emit: (String, [String: Any]) -> Void

  init(emit: @escaping (String, [String: Any]) -> Void) {
    self.emit = emit
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
      "appAction",
      [
        "name": action.name,
        "payload": nuxieNullable(action.payload?.mapValues(appActionValue)),
        "experience": [
          "experienceId": action.experience.experienceId,
          "experienceVersion": nuxieNullable(action.experience.experienceVersion),
          "journeyId": nuxieNullable(action.experience.journeyId),
        ],
      ]
    )
  }
}

func featureAccessDictionary(_ access: FeatureAccess) -> [String: Any] {
  [
    "allowed": access.allowed,
    "unlimited": access.unlimited,
    "balance": nuxieNullable(access.balance),
    "type": access.type.rawValue,
  ]
}

private func activityValue(_ value: NuxieActivityValue) -> Any {
  switch value {
  case .string(let value): value
  case .int(let value): value
  case .double(let value): value
  case .bool(let value): value
  @unknown default: NSNull()
  }
}

private func appActionValue(_ value: AppActionValue) -> Any {
  switch value {
  case .string(let value): value
  case .int(let value): value
  case .double(let value): value
  case .bool(let value): value
  @unknown default: NSNull()
  }
}
#endif
