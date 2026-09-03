import Foundation
@preconcurrency import Nuxie

public final class NuxieGodotNativeBridge: @unchecked Sendable {
  private let stateQueue = DispatchQueue(label: "ai.nuxie.godot.bridge.state")
  private var eventEmitter: (@Sendable (String, [String: Any]) -> Void)?
  private var delegateBridge: NuxieGodotDelegateBridge?
  private var configured = false
  private lazy var purchaseDelegateBridge = NuxieGodotPurchaseDelegateBridge(emit: emitEvent)

  public init(
    eventEmitter: (@Sendable (String, [String: Any]) -> Void)? = nil
  ) {
    self.eventEmitter = eventEmitter
  }

  public func setEventEmitter(
    _ eventEmitter: (@Sendable (String, [String: Any]) -> Void)?
  ) {
    stateQueue.sync {
      self.eventEmitter = eventEmitter
    }
  }

  public func configure(
    apiKey: String,
    options: [String: Any],
    usePurchaseController: Bool,
    wrapperVersion: String,
    requestId: String
  ) {
    let trimmedApiKey = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmedApiKey.isEmpty else {
      emitOperation(
        method: "configure",
        requestId: requestId,
        ok: false,
        error: bridgeError(code: "MISSING_API_KEY", message: "Nuxie API key is required")
      )
      return
    }

    let optionsBox = UnsafeAnyDictionary(value: options)
    Task { @MainActor in
      let delegate = NuxieGodotDelegateBridge(emit: self.emitEvent)
      do {
        let configuration = self.makeConfiguration(
          apiKey: trimmedApiKey,
          options: optionsBox.value,
          usePurchaseController: usePurchaseController
        )
        self.stateQueue.sync {
          self.delegateBridge = delegate
        }
        NuxieSDK.shared.delegate = delegate
        try NuxieSDK.shared.setup(with: configuration)
        self.stateQueue.sync {
          self.configured = true
        }
        self.emitOperation(
          method: "configure",
          requestId: requestId,
          ok: true,
          result: [
            "isConfigured": true,
            "wrapperVersion": wrapperVersion,
          ]
        )
      } catch {
        NuxieSDK.shared.delegate = nil
        self.stateQueue.sync {
          self.delegateBridge = nil
          self.configured = false
        }
        self.emitOperation(
          method: "configure",
          requestId: requestId,
          ok: false,
          error: bridgeError(from: error, fallbackCode: "CONFIGURE_FAILED")
        )
      }
    }
  }

  public func shutdown(requestId: String) {
    runAsync(method: "shutdown", requestId: requestId) {
      self.purchaseDelegateBridge.cancelPending(reason: "sdk_shutdown")
      await NuxieSDK.shared.shutdown()
      await MainActor.run {
        NuxieSDK.shared.delegate = nil
      }
      self.stateQueue.sync {
        self.delegateBridge = nil
        self.configured = false
      }
      return ["isConfigured": false]
    }
  }

  public func identify(
    distinctId: String,
    userProperties: [String: Any],
    userPropertiesSetOnce: [String: Any],
    requestId: String
  ) {
    guard requireConfigured(method: "identify", requestId: requestId) else { return }
    NuxieSDK.shared.identify(
      distinctId,
      userProperties: userProperties,
      userPropertiesSetOnce: userPropertiesSetOnce
    )
    emitOperation(
      method: "identify",
      requestId: requestId,
      ok: true,
      result: ["distinctId": NuxieSDK.shared.getDistinctId()]
    )
  }

  public func reset(keepAnonymousId: Bool, requestId: String) {
    guard requireConfigured(method: "reset", requestId: requestId) else { return }
    NuxieSDK.shared.reset(keepAnonymousId: keepAnonymousId)
    emitOperation(
      method: "reset",
      requestId: requestId,
      ok: true,
      result: [
        "distinctId": NuxieSDK.shared.getDistinctId(),
        "anonymousId": NuxieSDK.shared.getAnonymousId(),
        "isIdentified": NuxieSDK.shared.isIdentified,
      ]
    )
  }

  public func getDistinctId(requestId: String) {
    guard requireConfigured(method: "getDistinctId", requestId: requestId) else { return }
    emitOperation(
      method: "getDistinctId",
      requestId: requestId,
      ok: true,
      result: ["distinctId": NuxieSDK.shared.getDistinctId()]
    )
  }

  public func getAnonymousId(requestId: String) {
    guard requireConfigured(method: "getAnonymousId", requestId: requestId) else { return }
    emitOperation(
      method: "getAnonymousId",
      requestId: requestId,
      ok: true,
      result: ["anonymousId": NuxieSDK.shared.getAnonymousId()]
    )
  }

  public func getIsIdentified(requestId: String) {
    guard requireConfigured(method: "getIsIdentified", requestId: requestId) else { return }
    emitOperation(
      method: "getIsIdentified",
      requestId: requestId,
      ok: true,
      result: ["isIdentified": NuxieSDK.shared.isIdentified]
    )
  }

  public func trigger(eventName: String, properties: [String: Any]) {
    NuxieSDK.shared.trigger(eventName, properties: properties)
  }

  public func dismiss(requestId: String) {
    guard requireConfigured(method: "dismiss", requestId: requestId) else { return }
    runAsync(method: "dismiss", requestId: requestId) {
      await NuxieSDK.shared.dismiss()
      return [:]
    }
  }

  public func setLocaleIdentifier(_ localeIdentifier: String?, requestId: String) {
    guard requireConfigured(method: "setLocaleIdentifier", requestId: requestId) else { return }
    runAsync(method: "setLocaleIdentifier", requestId: requestId) {
      try await NuxieSDK.shared.setLocaleIdentifier(localeIdentifier)
      return [:]
    }
  }

  public func hasFeature(
    featureId: String,
    requiredBalance: Double,
    entityId: String?,
    policy: String,
    requestId: String
  ) {
    guard requireConfigured(method: "hasFeature", requestId: requestId) else { return }
    runAsync(method: "hasFeature", requestId: requestId) {
      let access = try await NuxieSDK.shared.hasFeature(
        featureId,
        requiredBalance: requiredBalance,
        entityId: self.normalizedEntityId(entityId),
        policy: policy == "remote" ? .remote : .cacheFirst
      )
      return featureAccessDictionary(access)
    }
  }

  public func useFeature(
    featureId: String,
    amount: Double,
    entityId: String?,
    metadata: [String: Any]
  ) {
    NuxieSDK.shared.useFeature(
      featureId,
      amount: amount,
      entityId: normalizedEntityId(entityId),
      metadata: metadata
    )
  }

  public func useFeatureAndWait(
    featureId: String,
    amount: Double,
    entityId: String?,
    setUsage: Bool,
    metadata: [String: Any],
    requestId: String
  ) {
    guard requireConfigured(method: "useFeatureAndWait", requestId: requestId) else { return }
    let metadataBox = UnsafeAnyDictionary(value: metadata)
    runAsync(method: "useFeatureAndWait", requestId: requestId) {
      let result = try await NuxieSDK.shared.useFeatureAndWait(
        featureId,
        amount: amount,
        entityId: self.normalizedEntityId(entityId),
        setUsage: setUsage,
        metadata: metadataBox.value
      )
      return featureUsageResultDictionary(result)
    }
  }

  public func completePurchase(requestId: String, result: [String: Any]) {
    purchaseDelegateBridge.completePurchase(requestId: requestId, payload: result)
  }

  public func completeRestore(requestId: String, result: [String: Any]) {
    purchaseDelegateBridge.completeRestore(requestId: requestId, payload: result)
  }

  private func runAsync(
    method: String,
    requestId: String,
    operation: @escaping @Sendable () async throws -> [String: Any]
  ) {
    Task {
      do {
        emitOperation(
          method: method,
          requestId: requestId,
          ok: true,
          result: try await operation()
        )
      } catch {
        emitOperation(
          method: method,
          requestId: requestId,
          ok: false,
          error: bridgeError(from: error)
        )
      }
    }
  }

  private func requireConfigured(method: String, requestId: String) -> Bool {
    guard stateQueue.sync(execute: { configured }) else {
      emitOperation(
        method: method,
        requestId: requestId,
        ok: false,
        error: bridgeError(code: "NOT_CONFIGURED", message: "Nuxie SDK is not configured")
      )
      return false
    }
    return true
  }

  private func emitOperation(
    method: String,
    requestId: String,
    ok: Bool,
    result: [String: Any] = [:],
    error: [String: Any] = [:]
  ) {
    emitEvent(
      "operation_result",
      [
        "requestId": requestId,
        "method": method,
        "ok": ok,
        "result": result,
        "error": error,
        "timestampMs": bridgeNowMs(),
      ]
    )
  }

  private func emitEvent(_ eventName: String, _ payload: [String: Any]) {
    stateQueue.sync {
      eventEmitter?(eventName, payload)
    }
  }

  @MainActor
  private func makeConfiguration(
    apiKey: String,
    options: [String: Any],
    usePurchaseController: Bool
  ) -> NuxieConfiguration {
    let configuration = NuxieConfiguration(apiKey: apiKey)
    configuration.environment = options["environment"] as? String == "development"
      ? .development
      : .production
    configuration.logLevel = switch options["log_level"] as? String {
    case "verbose": .verbose
    case "debug": .debug
    case "info": .info
    case "error": .error
    case "none": .none
    default: .warning
    }
    if let enabled = options["enable_console_logging"] as? Bool {
      configuration.enableConsoleLogging = enabled
    }
    if let redact = options["redact_sensitive_data"] as? Bool {
      configuration.redactSensitiveData = redact
    }
    if options.keys.contains("locale_identifier") {
      configuration.localeIdentifier = options["locale_identifier"] as? String
    }
    configuration.purchaseHandlingMode =
      options["purchase_handling_mode"] as? String == "observer" ? .observer : .full
    if let enabled = options["test_store_enabled"] as? Bool {
      configuration.testStoreEnabled = enabled
    }
    if usePurchaseController {
      configuration.purchaseDelegate = purchaseDelegateBridge
    }
    return configuration
  }

  private func normalizedEntityId(_ value: String?) -> String? {
    guard let value = value?.trimmingCharacters(in: .whitespacesAndNewlines),
          !value.isEmpty
    else {
      return nil
    }
    return value
  }
}

private struct UnsafeAnyDictionary: @unchecked Sendable {
  let value: [String: Any]
}

private final class NuxieGodotRuntime: @unchecked Sendable {
  static let shared = NuxieGodotRuntime()

  private let lock = NSLock()
  private var pendingEvents: [[String: Any]] = []
  private let bridge: NuxieGodotNativeBridge

  private init() {
    bridge = NuxieGodotNativeBridge()
    bridge.setEventEmitter { [weak self] eventName, payload in
      self?.enqueue(eventName: eventName, payload: payload)
    }
  }

  func shutdown() {
    bridge.shutdown(requestId: "__runtime_shutdown__")
  }

  func invoke(method: String, argsJSON: String) -> String {
    guard let arguments = dictionaryFromJSON(argsJSON.isEmpty ? "{}" : argsJSON) else {
      return errorResponse("INVALID_ARGUMENTS", "Arguments must be a JSON object")
    }
    return dispatch(method: method, arguments: arguments)
  }

  func pendingEventCount() -> Int32 {
    lock.withLock { Int32(pendingEvents.count) }
  }

  func popPendingEventJSON() -> String? {
    lock.withLock {
      guard !pendingEvents.isEmpty else { return nil }
      return jsonString(pendingEvents.removeFirst())
    }
  }

  private func enqueue(eventName: String, payload: [String: Any]) {
    lock.withLock {
      pendingEvents.append([
        "event": eventName,
        "payload": payload,
      ])
    }
  }

  private func dispatch(method: String, arguments: [String: Any]) -> String {
    switch method {
    case "configure":
      guard let apiKey = arguments["apiKey"] as? String,
            let requestId = arguments["requestId"] as? String
      else {
        return errorResponse("INVALID_ARGUMENTS", "configure requires apiKey and requestId")
      }
      bridge.configure(
        apiKey: apiKey,
        options: arguments["options"] as? [String: Any] ?? [:],
        usePurchaseController: boolean(arguments["usePurchaseController"]) ?? false,
        wrapperVersion: arguments["wrapperVersion"] as? String ?? "",
        requestId: requestId
      )

    case "shutdown":
      guard let requestId = arguments["requestId"] as? String else {
        return errorResponse("INVALID_ARGUMENTS", "shutdown requires requestId")
      }
      bridge.shutdown(requestId: requestId)

    case "identify":
      guard let distinctId = arguments["distinctId"] as? String,
            let requestId = arguments["requestId"] as? String
      else {
        return errorResponse("INVALID_ARGUMENTS", "identify requires distinctId and requestId")
      }
      bridge.identify(
        distinctId: distinctId,
        userProperties: arguments["userProperties"] as? [String: Any] ?? [:],
        userPropertiesSetOnce: arguments["userPropertiesSetOnce"] as? [String: Any] ?? [:],
        requestId: requestId
      )

    case "reset":
      guard let requestId = arguments["requestId"] as? String else {
        return errorResponse("INVALID_ARGUMENTS", "reset requires requestId")
      }
      bridge.reset(
        keepAnonymousId: boolean(arguments["keepAnonymousId"]) ?? false,
        requestId: requestId
      )

    case "getDistinctId":
      guard let requestId = arguments["requestId"] as? String else {
        return errorResponse("INVALID_ARGUMENTS", "getDistinctId requires requestId")
      }
      bridge.getDistinctId(requestId: requestId)

    case "getAnonymousId":
      guard let requestId = arguments["requestId"] as? String else {
        return errorResponse("INVALID_ARGUMENTS", "getAnonymousId requires requestId")
      }
      bridge.getAnonymousId(requestId: requestId)

    case "getIsIdentified":
      guard let requestId = arguments["requestId"] as? String else {
        return errorResponse("INVALID_ARGUMENTS", "getIsIdentified requires requestId")
      }
      bridge.getIsIdentified(requestId: requestId)

    case "trigger":
      guard let eventName = arguments["eventName"] as? String else {
        return errorResponse("INVALID_ARGUMENTS", "trigger requires eventName")
      }
      bridge.trigger(
        eventName: eventName,
        properties: arguments["properties"] as? [String: Any] ?? [:]
      )

    case "dismiss":
      guard let requestId = arguments["requestId"] as? String else {
        return errorResponse("INVALID_ARGUMENTS", "dismiss requires requestId")
      }
      bridge.dismiss(requestId: requestId)

    case "setLocaleIdentifier":
      guard let requestId = arguments["requestId"] as? String else {
        return errorResponse("INVALID_ARGUMENTS", "setLocaleIdentifier requires requestId")
      }
      bridge.setLocaleIdentifier(
        arguments["localeIdentifier"] as? String,
        requestId: requestId
      )

    case "hasFeature":
      guard let featureId = arguments["featureId"] as? String,
            let requestId = arguments["requestId"] as? String
      else {
        return errorResponse("INVALID_ARGUMENTS", "hasFeature requires featureId and requestId")
      }
      bridge.hasFeature(
        featureId: featureId,
        requiredBalance: number(arguments["requiredBalance"]) ?? 1,
        entityId: arguments["entityId"] as? String,
        policy: arguments["policy"] as? String ?? "cache_first",
        requestId: requestId
      )

    case "useFeature":
      guard let featureId = arguments["featureId"] as? String else {
        return errorResponse("INVALID_ARGUMENTS", "useFeature requires featureId")
      }
      bridge.useFeature(
        featureId: featureId,
        amount: number(arguments["amount"]) ?? 1,
        entityId: arguments["entityId"] as? String,
        metadata: arguments["metadata"] as? [String: Any] ?? [:]
      )

    case "useFeatureAndWait":
      guard let featureId = arguments["featureId"] as? String,
            let requestId = arguments["requestId"] as? String
      else {
        return errorResponse("INVALID_ARGUMENTS", "useFeatureAndWait requires featureId and requestId")
      }
      bridge.useFeatureAndWait(
        featureId: featureId,
        amount: number(arguments["amount"]) ?? 1,
        entityId: arguments["entityId"] as? String,
        setUsage: boolean(arguments["setUsage"]) ?? false,
        metadata: arguments["metadata"] as? [String: Any] ?? [:],
        requestId: requestId
      )

    case "completePurchase":
      guard let requestId = arguments["requestId"] as? String,
            let result = arguments["result"] as? [String: Any]
      else {
        return errorResponse("INVALID_ARGUMENTS", "completePurchase requires requestId and result")
      }
      bridge.completePurchase(requestId: requestId, result: result)

    case "completeRestore":
      guard let requestId = arguments["requestId"] as? String,
            let result = arguments["result"] as? [String: Any]
      else {
        return errorResponse("INVALID_ARGUMENTS", "completeRestore requires requestId and result")
      }
      bridge.completeRestore(requestId: requestId, result: result)

    default:
      return errorResponse("NATIVE_ERROR", "Unsupported method '\(method)'")
    }

    return jsonString(["ok": true])
  }

  private func errorResponse(_ code: String, _ message: String) -> String {
    jsonString([
      "ok": false,
      "error": bridgeError(code: code, message: message),
    ])
  }
}

@_cdecl("NuxieGodot_Invoke")
public func NuxieGodot_Invoke(
  _ methodPointer: UnsafePointer<CChar>?,
  _ argumentsPointer: UnsafePointer<CChar>?
) -> UnsafeMutablePointer<CChar>? {
  let method = methodPointer.map(String.init(cString:)) ?? ""
  let arguments = argumentsPointer.map(String.init(cString:)) ?? "{}"
  return strdup(NuxieGodotRuntime.shared.invoke(method: method, argsJSON: arguments))
}

@_cdecl("NuxieGodot_GetPendingEventCount")
public func NuxieGodot_GetPendingEventCount() -> Int32 {
  NuxieGodotRuntime.shared.pendingEventCount()
}

@_cdecl("NuxieGodot_PopPendingEvent")
public func NuxieGodot_PopPendingEvent() -> UnsafeMutablePointer<CChar>? {
  guard let event = NuxieGodotRuntime.shared.popPendingEventJSON() else {
    return nil
  }
  return strdup(event)
}

@_cdecl("NuxieGodot_FreeCString")
public func NuxieGodot_FreeCString(_ pointer: UnsafeMutablePointer<CChar>?) {
  free(pointer)
}

@_cdecl("NuxieGodot_Shutdown")
public func NuxieGodot_Shutdown() {
  NuxieGodotRuntime.shared.shutdown()
}
