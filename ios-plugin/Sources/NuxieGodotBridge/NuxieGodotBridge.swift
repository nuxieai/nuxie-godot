import Foundation
import Combine
#if DEBUG
@_spi(Testing) import Nuxie
#else
import Nuxie
#endif

@objc(NuxieGodotRuntime)
public final class NuxieGodotRuntime: NSObject {
  @objc public var emit: ((String) -> Void)?
  private var session: String?
  private var snapshotSubscription: AnyCancellable?
  private static weak var owner: NuxieGodotRuntime?
  private static var configurationKey: String?
  private lazy var purchases = NuxiePurchaseDelegateBridge { [weak self] name, payload in
    Task { @MainActor [weak self] in self?.send(name, payload) }
  }
  @MainActor private lazy var delegate = NuxieDelegateBridge { [weak self] name, payload in self?.send(name, payload) }

  @objc public func invalidate() {
    Task { @MainActor in
      self.snapshotSubscription?.cancel()
      self.purchases.cancelPending()
      self.session = nil
      self.emit = nil
      if Self.owner === self {
        NuxieSDK.shared.delegate = nil
        Self.owner = nil
      }
    }
  }

  @MainActor private func send(_ name: String, _ payload: [String: Any]) {
    guard let session else { return }
    if let json = try? encode(["session": session, "name": name, "payload": payload]) { emit?(json) }
  }

  @MainActor private func snapshot(_ value: FeatureInfo.Snapshot) -> [String: Any] {
    ["identityGeneration": String(value.identityGeneration), "revision": String(value.revision),
     "state": String(describing: value.state), "all": value.all.mapValues(featureAccessDictionary)]
  }

  @objc public func invoke(_ method: String, arguments: [String: Any],
    resolve: @escaping (Any?) -> Void, reject: @escaping (String, String, NSError?) -> Void) {
    Task { @MainActor in
      do {
        if method != "configure" {
          guard Self.owner === self, let session = self.session, arguments["session"] as? String == session else {
            throw failure("sessionExpired", "Configure Nuxie in this Godot runtime before calling its API")
          }
        }
        let sdk = NuxieSDK.shared
        switch method {
        case "configure":
          let input = try object(arguments["configuration"])
          guard input["contract"] as? Int == 1 else { throw failure("incompatibleBridge", "Rebuild the app with the matching Nuxie native module") }
          let session = try required(input, "session")
          let apiKey = try required(input, "apiKey")
          var keyInput = input; keyInput.removeValue(forKey: "session")
          let key = try encode(keyInput)
          if let owner = Self.owner, owner !== self { throw failure("engineAlreadyAttached", "Another runtime owns Nuxie") }
          if let previous = Self.configurationKey, previous != key { throw failure("alreadyConfigured", "Shutdown before changing Nuxie configuration") }
          if sdk.isSetup && Self.configurationKey == nil { throw failure("alreadyConfigured", "Nuxie was configured outside Godot") }
          Self.owner = self
          self.session = session
          self.purchases.cancelPending()
          self.snapshotSubscription?.cancel()
          let config = NuxieConfiguration(apiKey: apiKey)
          config.environment = input["environment"] as? String == "development" ? .development : .production
          switch input["logLevel"] as? String {
          case "verbose": config.logLevel = .verbose
          case "debug": config.logLevel = .debug
          case "info": config.logLevel = .info
          case "error": config.logLevel = .error
          case "none": config.logLevel = .none
          default: config.logLevel = .warning
          }
          config.localeIdentifier = input["localeIdentifier"] as? String
          config.purchaseHandlingMode = input["purchaseHandlingMode"] as? String == "observer" ? .observer : .full
          config.purchaseDelegate = input["externalBilling"] as? Bool == true ? self.purchases : nil
#if DEBUG
          if let endpoint = ProcessInfo.processInfo.environment["NUXIE_GODOT_API_ENDPOINT"], let url = URL(string: endpoint) {
            config.testingOverrides.apiEndpoint = url
          }
#endif
          sdk.delegate = self.delegate
          if sdk.isSetup { try sdk.setPurchaseDelegate(config.purchaseDelegate) }
          else { try sdk.setup(with: config) }
          Self.configurationKey = key
          self.snapshotSubscription = sdk.features.$snapshot.sink { [weak self] value in
            guard let self else { return }
            self.send("features", self.snapshot(value))
          }
          resolve(try encode(["contract": 1, "session": session, "nativeVersion": sdk.version,
            "snapshot": self.snapshot(sdk.features.snapshot)]))
        case "shutdown":
          self.snapshotSubscription?.cancel()
          self.purchases.cancelPending()
          await sdk.shutdown()
          sdk.delegate = nil
          self.session = nil; Self.owner = nil; Self.configurationKey = nil
          resolve(nil)
        case "identify":
          let options = try object(arguments["properties"])
          sdk.identify(try required(arguments, "customerId"), userProperties: options["properties"] as? [String: Any],
            userPropertiesSetOnce: options["propertiesSetOnce"] as? [String: Any])
          resolve(try encode(self.snapshot(sdk.features.snapshot)))
        case "reset": sdk.reset(keepAnonymousId: false); resolve(try encode(self.snapshot(sdk.features.snapshot)))
        case "getIdentity": resolve(try encode(["distinctId": sdk.getDistinctId(), "anonymousId": sdk.getAnonymousId(), "isIdentified": sdk.isIdentified]))
        case "setLocaleIdentifier": try await sdk.setLocaleIdentifier(arguments["locale"] as? String); resolve(nil)
        case "trigger": sdk.trigger(try required(arguments, "event"), properties: try object(arguments["properties"])); resolve(nil)
        case "dismiss": await sdk.dismiss(); resolve(nil)
        case "hasFeature":
          let options = try object(arguments["options"])
          let access = try await sdk.hasFeature(try required(arguments, "featureId"),
            requiredBalance: options["requiredBalance"] as? Double ?? 1, entityId: options["entityId"] as? String,
            policy: options["policy"] as? String == "remote" ? .remote : .cacheFirst)
          resolve(try encode(featureAccessDictionary(access)))
        case "consumeFeature":
          let options = try object(arguments["options"])
          let result = try await sdk.consumeFeature(try required(arguments, "featureId"),
            quantity: options["quantity"] as? Double ?? 1, operationId: try required(options, "operationId"),
            entityId: options["entityId"] as? String)
          resolve(try encode(["customerId": result.customerId, "featureId": result.featureId, "occurredAtMs": nuxieNullable(result.occurredAtMs),
            "operationId": result.operationId, "accepted": result.accepted, "code": result.code,
            "quantity": result.quantity, "balance": nuxieNullable(result.balance), "unlimited": result.unlimited,
            "active": result.active, "idempotentReplay": result.idempotentReplay]))
        case "completePurchase": self.purchases.completePurchase(requestId: try required(arguments, "requestId"), payload: try object(arguments["result"])); resolve(nil)
        case "completeRestore": self.purchases.completeRestore(requestId: try required(arguments, "requestId"), payload: try object(arguments["result"])); resolve(nil)
        default: throw failure("invalidMethod", "Unsupported bridge method")
        }
      } catch {
        if method == "configure", !NuxieSDK.shared.isSetup {
          self.snapshotSubscription?.cancel(); self.purchases.cancelPending()
          self.session = nil
          if Self.owner === self { Self.owner = nil; NuxieSDK.shared.delegate = nil }
        }
        let error = error as NSError
        reject(error.userInfo["code"] as? String ?? "nativeError", error.localizedDescription, error)
      }
    }
  }
}

private func failure(_ code: String, _ message: String) -> NSError {
  NSError(domain: "ai.nuxie.godot", code: 1, userInfo: ["code": code, NSLocalizedDescriptionKey: message])
}
private func required(_ object: [String: Any], _ key: String) throws -> String {
  guard let value = object[key] as? String, !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
    throw failure("invalidArgument", "Missing or empty \(key)")
  }
  return value
}
private func object(_ raw: Any?) throws -> [String: Any] {
  guard let raw = raw as? String, let data = raw.data(using: .utf8),
    let value = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
    throw failure("invalidArgument", "Expected a JSON object")
  }
  return value
}
private func encode(_ value: [String: Any]) throws -> String {
  String(decoding: try JSONSerialization.data(withJSONObject: value, options: [.sortedKeys]), as: UTF8.self)
}
