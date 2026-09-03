import Foundation
@preconcurrency import Nuxie

func bridgeNowMs() -> Int {
  Int(Date().timeIntervalSince1970 * 1_000)
}

func nullable(_ value: Any?) -> Any {
  value ?? NSNull()
}

func bridgeError(
  code: String,
  message: String,
  nativeStack: String? = nil
) -> [String: Any] {
  var value: [String: Any] = [
    "code": code,
    "message": message,
  ]
  if let nativeStack, !nativeStack.isEmpty {
    value["nativeStack"] = nativeStack
  }
  return value
}

func bridgeError(
  from error: Error,
  fallbackCode: String = "NATIVE_ERROR"
) -> [String: Any] {
  bridgeError(
    code: fallbackCode,
    message: error.localizedDescription,
    nativeStack: String(describing: error)
  )
}

func jsonString(_ value: Any) -> String {
  guard JSONSerialization.isValidJSONObject(value),
        let data = try? JSONSerialization.data(withJSONObject: value)
  else {
    return #"{"ok":false,"error":{"code":"NATIVE_ERROR","message":"Invalid JSON payload"}}"#
  }
  return String(decoding: data, as: UTF8.self)
}

func dictionaryFromJSON(_ raw: String) -> [String: Any]? {
  guard let data = raw.data(using: .utf8),
        let object = try? JSONSerialization.jsonObject(with: data)
  else {
    return nil
  }
  return object as? [String: Any]
}

func number(_ value: Any?) -> Double? {
  (value as? NSNumber)?.doubleValue
}

func boolean(_ value: Any?) -> Bool? {
  (value as? NSNumber)?.boolValue
}

func featureAccessDictionary(_ access: FeatureAccess) -> [String: Any] {
  [
    "allowed": access.allowed,
    "unlimited": access.unlimited,
    "balance": nullable(access.balance),
    "type": access.type.rawValue,
  ]
}

func featureUsageResultDictionary(_ result: FeatureUsageResult) -> [String: Any] {
  let usage: Any
  if let value = result.usage {
    usage = [
      "current": value.current,
      "limit": nullable(value.limit),
      "remaining": nullable(value.remaining),
    ]
  } else {
    usage = NSNull()
  }

  return [
    "success": result.success,
    "featureId": result.featureId,
    "amountUsed": result.amountUsed,
    "message": nullable(result.message),
    "usage": usage,
    "authoritativeAccess": nullable(result.authoritativeAccess.map(featureAccessDictionary)),
  ]
}
