import Foundation
@preconcurrency import Nuxie

func bridgeNowMs() -> Int {
  Int(Date().timeIntervalSince1970 * 1000)
}

func bridgeError(code: String, message: String, nativeStack: String? = nil) -> [String: Any] {
  var payload: [String: Any] = [
    "code": code,
    "message": message,
  ]

  if let nativeStack, !nativeStack.isEmpty {
    payload["nativeStack"] = nativeStack
  }

  return payload
}

func bridgeError(from error: Error, fallbackCode: String = "NATIVE_ERROR") -> [String: Any] {
  bridgeError(code: fallbackCode, message: error.localizedDescription, nativeStack: String(describing: error))
}

func jsonString(_ value: Any) -> String {
  guard JSONSerialization.isValidJSONObject(value) else {
    return "{\"ok\":false,\"error\":{\"code\":\"NATIVE_ERROR\",\"message\":\"Invalid JSON payload\"}}"
  }

  do {
    let data = try JSONSerialization.data(withJSONObject: value)
    return String(decoding: data, as: UTF8.self)
  } catch {
    return "{\"ok\":false,\"error\":{\"code\":\"NATIVE_ERROR\",\"message\":\"JSON serialization failed\"}}"
  }
}

func dictionaryFromJSON(_ raw: String) -> [String: Any]? {
  guard let data = raw.data(using: .utf8) else {
    return nil
  }

  do {
    let object = try JSONSerialization.jsonObject(with: data)
    return object as? [String: Any]
  } catch {
    return nil
  }
}

func parseInteger(_ value: Any?) -> Int? {
  switch value {
  case let int as Int:
    return int
  case let number as NSNumber:
    return number.intValue
  default:
    return nil
  }
}

func parseInt64(_ value: Any?) -> Int64? {
  switch value {
  case let int as Int64:
    return int
  case let number as NSNumber:
    return number.int64Value
  default:
    return nil
  }
}

func parseDouble(_ value: Any?) -> Double? {
  switch value {
  case let double as Double:
    return double
  case let number as NSNumber:
    return number.doubleValue
  default:
    return nil
  }
}

func parseBoolean(_ value: Any?) -> Bool? {
  switch value {
  case let bool as Bool:
    return bool
  case let number as NSNumber:
    return number.boolValue
  default:
    return nil
  }
}

func parseString(_ value: Any?) -> String? {
  switch value {
  case let string as String where !string.isEmpty:
    return string
  default:
    return nil
  }
}

func parseURL(_ raw: String) -> URL? {
  if raw.hasPrefix("/") {
    return URL(fileURLWithPath: raw)
  }
  return URL(string: raw)
}

func dictionaryFromEncodable<T: Encodable>(_ value: T) -> [String: Any] {
  do {
    let data = try JSONEncoder().encode(value)
    return (try JSONSerialization.jsonObject(with: data) as? [String: Any]) ?? [:]
  } catch {
    return [:]
  }
}

public func isTerminalTriggerUpdate(_ update: TriggerUpdate) -> Bool {
  switch update {
  case .error:
    return true
  case .journey:
    return true
  case .decision(let decision):
    switch decision {
    case .allowedImmediate, .deniedImmediate, .noMatch, .suppressed:
      return true
    case .journeyStarted, .journeyResumed, .flowShown:
      return false
    @unknown default:
      return true
    }
  case .entitlement(let entitlement):
    switch entitlement {
    case .allowed, .denied:
      return true
    case .pending:
      return false
    @unknown default:
      return true
    }
  @unknown default:
    return true
  }
}

func triggerUpdateDictionary(_ update: TriggerUpdate) -> [String: Any] {
  switch update {
  case .decision(let decision):
    return ["kind": "decision", "decision": triggerDecisionDictionary(decision)]
  case .entitlement(let entitlement):
    return ["kind": "entitlement", "entitlement": entitlementDictionary(entitlement)]
  case .journey(let journey):
    return ["kind": "journey", "journey": journeyDictionary(journey)]
  case .error(let error):
    return [
      "kind": "error",
      "error": [
        "code": error.code,
        "message": error.message,
      ],
    ]
  @unknown default:
    return [
      "kind": "error",
      "error": [
        "code": "UNKNOWN_TRIGGER_UPDATE",
        "message": "Unsupported trigger update from native SDK",
      ],
    ]
  }
}

func triggerDecisionDictionary(_ decision: TriggerDecision) -> [String: Any] {
  switch decision {
  case .noMatch:
    return ["type": "no_match"]
  case .allowedImmediate:
    return ["type": "allowed_immediate"]
  case .deniedImmediate:
    return ["type": "denied_immediate"]
  case .journeyStarted(let ref):
    return ["type": "journey_started", "ref": journeyRefDictionary(ref)]
  case .journeyResumed(let ref):
    return ["type": "journey_resumed", "ref": journeyRefDictionary(ref)]
  case .flowShown(let ref):
    return ["type": "flow_shown", "ref": journeyRefDictionary(ref)]
  case .suppressed(let reason):
    var payload: [String: Any] = ["type": "suppressed"]
    payload.merge(suppressReasonDictionary(reason)) { _, new in new }
    return payload
  @unknown default:
    return [
      "type": "suppressed",
      "reason": "unknown",
    ]
  }
}

func entitlementDictionary(_ entitlement: EntitlementUpdate) -> [String: Any] {
  switch entitlement {
  case .pending:
    return ["type": "pending"]
  case .denied:
    return ["type": "denied"]
  case .allowed(let source):
    return [
      "type": "allowed",
      "source": gateSourceString(source),
    ]
  @unknown default:
    return ["type": "denied"]
  }
}

func suppressReasonDictionary(_ reason: SuppressReason) -> [String: Any] {
  switch reason {
  case .alreadyActive:
    return ["reason": "already_active"]
  case .reentryLimited:
    return ["reason": "reentry_limited"]
  case .holdout:
    return ["reason": "holdout"]
  case .noFlow:
    return ["reason": "no_flow"]
  case .unknown(let value):
    return ["reason": "unknown", "rawReason": value]
  @unknown default:
    return ["reason": "unknown"]
  }
}

func journeyRefDictionary(_ ref: JourneyRef) -> [String: Any] {
  [
    "journeyId": ref.journeyId,
    "campaignId": ref.campaignId,
    "flowId": ref.flowId as Any,
  ]
}

func journeyDictionary(_ update: JourneyUpdate) -> [String: Any] {
  [
    "journeyId": update.journeyId,
    "campaignId": update.campaignId,
    "flowId": update.flowId as Any,
    "exitReason": update.exitReason.rawValue,
    "goalMet": update.goalMet,
    "goalMetAtEpochMillis": update.goalMetAt.map { Int($0.timeIntervalSince1970 * 1000) } as Any,
    "durationSeconds": update.durationSeconds as Any,
    "flowExitReason": update.flowExitReason as Any,
  ]
}

func gateSourceString(_ source: GateSource) -> String {
  switch source {
  case .cache:
    return "cache"
  case .purchase:
    return "purchase"
  case .restore:
    return "restore"
  @unknown default:
    return "unknown"
  }
}

func featureAccessDictionary(_ access: FeatureAccess?) -> [String: Any]? {
  guard let access else { return nil }
  return [
    "allowed": access.allowed,
    "unlimited": access.unlimited,
    "balance": access.balance as Any,
    "type": access.type.rawValue,
  ]
}

func featureCheckResultDictionary(_ result: FeatureCheckResult) -> [String: Any] {
  [
    "customerId": result.customerId,
    "featureId": result.featureId,
    "requiredBalance": result.requiredBalance,
    "code": result.code,
    "allowed": result.allowed,
    "unlimited": result.unlimited,
    "balance": result.balance as Any,
    "type": result.type.rawValue,
    "preview": result.preview?.value as Any,
  ]
}

func featureUsageResultDictionary(_ result: FeatureUsageResult) -> [String: Any] {
  var payload: [String: Any] = [
    "success": result.success,
    "featureId": result.featureId,
    "amountUsed": result.amountUsed,
    "message": result.message as Any,
  ]

  if let usage = result.usage {
    payload["usage"] = [
      "current": usage.current,
      "limit": usage.limit as Any,
      "remaining": usage.remaining as Any,
    ]
  }

  return payload
}

extension Dictionary where Key == String, Value == Any {
  func toPurchaseOutcome(defaultProductId: String) -> PurchaseOutcome {
    let type = (self["type"] as? String)?.lowercased() ?? "failed"
    let resolvedProductId = (self["productId"] as? String) ?? defaultProductId

    switch type {
    case "success":
      return PurchaseOutcome(
        result: .success,
        transactionJws: self["transactionJws"] as? String,
        transactionId: self["transactionId"] as? String,
        originalTransactionId: self["originalTransactionId"] as? String,
        productId: resolvedProductId
      )

    case "cancelled":
      return PurchaseOutcome(result: .cancelled, productId: resolvedProductId)

    case "pending":
      return PurchaseOutcome(result: .pending, productId: resolvedProductId)

    default:
      let message = (self["message"] as? String) ?? "purchase_failed"
      let error = NSError(domain: "io.nuxie.godot", code: 1, userInfo: [NSLocalizedDescriptionKey: message])
      return PurchaseOutcome(result: .failed(error), productId: resolvedProductId)
    }
  }

  func toRestoreResult() -> RestoreResult {
    let type = (self["type"] as? String)?.lowercased() ?? "failed"

    switch type {
    case "success":
      return .success(restoredCount: parseInteger(self["restoredCount"]) ?? 0)

    case "no_purchases":
      return .noPurchases

    default:
      let message = (self["message"] as? String) ?? "restore_failed"
      let error = NSError(domain: "io.nuxie.godot", code: 1, userInfo: [NSLocalizedDescriptionKey: message])
      return .failed(error)
    }
  }
}
