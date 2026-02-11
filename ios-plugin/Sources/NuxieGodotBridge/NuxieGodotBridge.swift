import Foundation
@preconcurrency import Nuxie

public final class NuxieGodotBridge: @unchecked Sendable {
  private let stateQueue = DispatchQueue(label: "io.nuxie.godot.bridge.state")
  private var triggerHandles: [String: TriggerHandle] = [:]
  private var eventEmitter: (@Sendable (_ eventName: String, _ payload: [String: Any]) -> Void)?
  private var delegateBridge: NuxieGodotDelegateBridge?

  private lazy var purchaseDelegateBridge = NuxieGodotPurchaseDelegateBridge(emit: emitEvent)

  public init(eventEmitter: (@Sendable (_ eventName: String, _ payload: [String: Any]) -> Void)? = nil) {
    self.eventEmitter = eventEmitter
  }

  public func setEventEmitter(_ eventEmitter: (@Sendable (_ eventName: String, _ payload: [String: Any]) -> Void)?) {
    stateQueue.sync {
      self.eventEmitter = eventEmitter
    }
  }

  public func configure(
    apiKey: String,
    options: [String: Any] = [:],
    usePurchaseController: Bool = false,
    wrapperVersion: String = "",
    requestId: String
  ) {
    let trimmedApiKey = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmedApiKey.isEmpty else {
      emitOperation(
        method: "configure",
        requestId: requestId,
        ok: false,
        result: [:],
        error: bridgeError(code: "MISSING_API_KEY", message: "Nuxie API key is required")
      )
      return
    }

    let configuration = makeConfiguration(
      apiKey: trimmedApiKey,
      options: options,
      usePurchaseController: usePurchaseController
    )

    Task { @MainActor in
      do {
        let delegateBridge = NuxieGodotDelegateBridge(emit: self.emitEvent)
        self.stateQueue.sync {
          self.delegateBridge = delegateBridge
        }
        NuxieSDK.shared.delegate = delegateBridge
        try NuxieSDK.shared.setup(with: configuration)

        emitOperation(
          method: "configure",
          requestId: requestId,
          ok: true,
          result: [
            "isConfigured": true,
            "wrapperVersion": wrapperVersion,
          ],
          error: [:]
        )
      } catch {
        self.stateQueue.sync {
          self.delegateBridge = nil
        }

        emitOperation(
          method: "configure",
          requestId: requestId,
          ok: false,
          result: [:],
          error: bridgeError(from: error, fallbackCode: "INVALID_CONFIGURATION")
        )
      }
    }
  }

  public func shutdown(requestId: String) {
    runAsync(method: "shutdown", requestId: requestId) {
      await NuxieSDK.shared.shutdown()
      NuxieSDK.shared.delegate = nil
      self.purchaseDelegateBridge.clearPending(reason: "sdk_shutdown")
      self.stateQueue.sync {
        self.triggerHandles.removeAll()
        self.delegateBridge = nil
      }
      return ["isConfigured": false]
    }
  }

  public func identify(
    distinctId: String,
    userProperties: [String: Any] = [:],
    userPropertiesSetOnce: [String: Any] = [:],
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
      result: ["distinctId": NuxieSDK.shared.getDistinctId()],
      error: [:]
    )
  }

  public func reset(keepAnonymousId: Bool = true, requestId: String) {
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
      ],
      error: [:]
    )
  }

  public func getDistinctId(requestId: String) {
    guard requireConfigured(method: "getDistinctId", requestId: requestId) else { return }

    emitOperation(
      method: "getDistinctId",
      requestId: requestId,
      ok: true,
      result: ["distinctId": NuxieSDK.shared.getDistinctId()],
      error: [:]
    )
  }

  public func getAnonymousId(requestId: String) {
    guard requireConfigured(method: "getAnonymousId", requestId: requestId) else { return }

    emitOperation(
      method: "getAnonymousId",
      requestId: requestId,
      ok: true,
      result: ["anonymousId": NuxieSDK.shared.getAnonymousId()],
      error: [:]
    )
  }

  public func getIsIdentified(requestId: String) {
    guard requireConfigured(method: "getIsIdentified", requestId: requestId) else { return }

    emitOperation(
      method: "getIsIdentified",
      requestId: requestId,
      ok: true,
      result: ["isIdentified": NuxieSDK.shared.isIdentified],
      error: [:]
    )
  }

  public func startTrigger(
    requestId: String,
    eventName: String,
    properties: [String: Any] = [:],
    userProperties: [String: Any] = [:],
    userPropertiesSetOnce: [String: Any] = [:]
  ) {
    guard requireConfigured(method: "startTrigger", requestId: requestId) else { return }

    let trimmedEventName = eventName.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmedEventName.isEmpty else {
      emitOperation(
        method: "startTrigger",
        requestId: requestId,
        ok: false,
        result: [:],
        error: bridgeError(code: "INVALID_CONFIGURATION", message: "startTrigger requires a non-empty eventName")
      )
      return
    }

    let handle = NuxieSDK.shared.trigger(
      trimmedEventName,
      properties: properties,
      userProperties: userProperties,
      userPropertiesSetOnce: userPropertiesSetOnce
    ) { [weak self] update in
      guard let self else { return }

      let isTerminal = isTerminalTriggerUpdate(update)
      self.emitEvent(
        "trigger_update",
        [
          "requestId": requestId,
          "update": triggerUpdateDictionary(update),
          "isTerminal": isTerminal,
          "timestampMs": bridgeNowMs(),
        ]
      )

      if isTerminal {
        self.stateQueue.sync {
          _ = self.triggerHandles.removeValue(forKey: requestId)
        }
      }
    }

    stateQueue.sync {
      triggerHandles[requestId] = handle
    }

    emitOperation(
      method: "startTrigger",
      requestId: requestId,
      ok: true,
      result: ["requestId": requestId],
      error: [:]
    )
  }

  public func cancelTrigger(requestId: String) {
    stateQueue.sync {
      triggerHandles.removeValue(forKey: requestId)?.cancel()
    }

    emitOperation(
      method: "cancelTrigger",
      requestId: requestId,
      ok: true,
      result: [:],
      error: [:]
    )
  }

  public func showFlow(flowId: String, requestId: String) {
    guard requireConfigured(method: "showFlow", requestId: requestId) else { return }

    let trimmedFlowId = flowId.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmedFlowId.isEmpty else {
      emitOperation(
        method: "showFlow",
        requestId: requestId,
        ok: false,
        result: [:],
        error: bridgeError(code: "INVALID_CONFIGURATION", message: "showFlow requires a non-empty flowId")
      )
      return
    }

    Task { @MainActor in
      do {
        try await NuxieSDK.shared.showFlow(with: trimmedFlowId)

        emitEvent(
          "flow_lifecycle",
          [
            "type": "presented",
            "flowId": trimmedFlowId,
            "timestampMs": bridgeNowMs(),
          ]
        )

        emitOperation(
          method: "showFlow",
          requestId: requestId,
          ok: true,
          result: ["flowId": trimmedFlowId],
          error: [:]
        )
      } catch {
        emitOperation(
          method: "showFlow",
          requestId: requestId,
          ok: false,
          result: [:],
          error: bridgeError(from: error, fallbackCode: "FLOW_PRESENT_FAILED")
        )
      }
    }
  }

  public func refreshProfile(requestId: String) {
    guard requireConfigured(method: "refreshProfile", requestId: requestId) else { return }

    runAsync(method: "refreshProfile", requestId: requestId) {
      let response = try await NuxieSDK.shared.refreshProfile()
      return ["profile": dictionaryFromEncodable(response)]
    }
  }

  public func hasFeature(
    featureId: String,
    requiredBalance: Int? = nil,
    entityId: String? = nil,
    requestId: String
  ) {
    guard requireConfigured(method: "hasFeature", requestId: requestId) else { return }

    runAsync(method: "hasFeature", requestId: requestId) {
      let normalizedEntityId = self.normalizeEntityId(entityId)
      let normalizedRequiredBalance = self.normalizeRequiredBalance(requiredBalance)

      let access: FeatureAccess
      if let normalizedRequiredBalance {
        access = try await NuxieSDK.shared.hasFeature(
          featureId,
          requiredBalance: normalizedRequiredBalance,
          entityId: normalizedEntityId
        )
      } else if normalizedEntityId != nil {
        access = try await NuxieSDK.shared.hasFeature(featureId, requiredBalance: 0, entityId: normalizedEntityId)
      } else {
        access = try await NuxieSDK.shared.hasFeature(featureId)
      }

      return ["access": featureAccessDictionary(access) as Any]
    }
  }

  public func getCachedFeature(featureId: String, entityId: String? = nil, requestId: String) {
    guard requireConfigured(method: "getCachedFeature", requestId: requestId) else { return }

    runAsync(method: "getCachedFeature", requestId: requestId) {
      let access = await NuxieSDK.shared.getCachedFeature(featureId, entityId: self.normalizeEntityId(entityId))
      return ["access": featureAccessDictionary(access) as Any]
    }
  }

  public func checkFeature(
    featureId: String,
    requiredBalance: Int? = nil,
    entityId: String? = nil,
    requestId: String
  ) {
    guard requireConfigured(method: "checkFeature", requestId: requestId) else { return }

    runAsync(method: "checkFeature", requestId: requestId) {
      let result = try await NuxieSDK.shared.checkFeature(
        featureId,
        requiredBalance: self.normalizeRequiredBalance(requiredBalance),
        entityId: self.normalizeEntityId(entityId)
      )

      return ["result": featureCheckResultDictionary(result)]
    }
  }

  public func refreshFeature(
    featureId: String,
    requiredBalance: Int? = nil,
    entityId: String? = nil,
    requestId: String
  ) {
    guard requireConfigured(method: "refreshFeature", requestId: requestId) else { return }

    runAsync(method: "refreshFeature", requestId: requestId) {
      let result = try await NuxieSDK.shared.refreshFeature(
        featureId,
        requiredBalance: self.normalizeRequiredBalance(requiredBalance),
        entityId: self.normalizeEntityId(entityId)
      )

      return ["result": featureCheckResultDictionary(result)]
    }
  }

  public func useFeature(
    featureId: String,
    amount: Double = 1,
    entityId: String? = nil,
    metadata: [String: Any] = [:],
    requestId: String
  ) {
    guard requireConfigured(method: "useFeature", requestId: requestId) else { return }

    NuxieSDK.shared.useFeature(featureId, amount: amount, entityId: normalizeEntityId(entityId), metadata: metadata)
    emitOperation(
      method: "useFeature",
      requestId: requestId,
      ok: true,
      result: ["accepted": true],
      error: [:]
    )
  }

  public func useFeatureAndWait(
    featureId: String,
    amount: Double = 1,
    entityId: String? = nil,
    setUsage: Bool = false,
    metadata: [String: Any] = [:],
    requestId: String
  ) {
    guard requireConfigured(method: "useFeatureAndWait", requestId: requestId) else { return }
    let sendableMetadata = UnsafeAnyDictionary(value: metadata)

    runAsync(method: "useFeatureAndWait", requestId: requestId) {
      let result = try await NuxieSDK.shared.useFeatureAndWait(
        featureId,
        amount: amount,
        entityId: self.normalizeEntityId(entityId),
        setUsage: setUsage,
        metadata: sendableMetadata.value
      )

      return ["result": featureUsageResultDictionary(result)]
    }
  }

  public func flushEvents(requestId: String) {
    guard requireConfigured(method: "flushEvents", requestId: requestId) else { return }

    runAsync(method: "flushEvents", requestId: requestId) {
      ["flushed": await NuxieSDK.shared.flushEvents()]
    }
  }

  public func getQueuedEventCount(requestId: String) {
    guard requireConfigured(method: "getQueuedEventCount", requestId: requestId) else { return }

    runAsync(method: "getQueuedEventCount", requestId: requestId) {
      ["queuedEventCount": await NuxieSDK.shared.getQueuedEventCount()]
    }
  }

  public func pauseEventQueue(requestId: String) {
    guard requireConfigured(method: "pauseEventQueue", requestId: requestId) else { return }

    runAsync(method: "pauseEventQueue", requestId: requestId) {
      await NuxieSDK.shared.pauseEventQueue()
      return ["paused": true]
    }
  }

  public func resumeEventQueue(requestId: String) {
    guard requireConfigured(method: "resumeEventQueue", requestId: requestId) else { return }

    runAsync(method: "resumeEventQueue", requestId: requestId) {
      await NuxieSDK.shared.resumeEventQueue()
      return ["paused": false]
    }
  }

  public func completePurchase(requestId: String, result: [String: Any]) {
    let completed = purchaseDelegateBridge.completePurchase(requestId: requestId, payload: result)

    if completed {
      emitOperation(method: "completePurchase", requestId: requestId, ok: true, result: [:], error: [:])
    } else {
      emitOperation(
        method: "completePurchase",
        requestId: requestId,
        ok: false,
        result: [:],
        error: bridgeError(code: "PURCHASE_REQUEST_NOT_FOUND", message: "No pending purchase request for \(requestId)")
      )
    }
  }

  public func completeRestore(requestId: String, result: [String: Any]) {
    let completed = purchaseDelegateBridge.completeRestore(requestId: requestId, payload: result)

    if completed {
      emitOperation(method: "completeRestore", requestId: requestId, ok: true, result: [:], error: [:])
    } else {
      emitOperation(
        method: "completeRestore",
        requestId: requestId,
        ok: false,
        result: [:],
        error: bridgeError(code: "RESTORE_REQUEST_NOT_FOUND", message: "No pending restore request for \(requestId)")
      )
    }
  }

  private func runAsync(
    method: String,
    requestId: String,
    operation: @escaping @Sendable () async throws -> [String: Any]
  ) {
    Task {
      do {
        let result = try await operation()
        emitOperation(method: method, requestId: requestId, ok: true, result: result, error: [:])
      } catch {
        emitOperation(
          method: method,
          requestId: requestId,
          ok: false,
          result: [:],
          error: bridgeError(from: error)
        )
      }
    }
  }

  private func requireConfigured(method: String, requestId: String) -> Bool {
    guard NuxieSDK.shared.configuration != nil else {
      emitOperation(
        method: method,
        requestId: requestId,
        ok: false,
        result: [:],
        error: bridgeError(code: "NOT_CONFIGURED", message: "Nuxie SDK is not configured")
      )
      return false
    }

    return true
  }

  private func emitOperation(method: String, requestId: String, ok: Bool, result: [String: Any], error: [String: Any]) {
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

  private func makeConfiguration(
    apiKey: String,
    options: [String: Any],
    usePurchaseController: Bool
  ) -> NuxieConfiguration {
    let config = NuxieConfiguration(apiKey: apiKey)

    if let environment = options["environment"] as? String {
      switch environment {
      case "production":
        config.environment = .production
      case "staging":
        config.environment = .staging
      case "development":
        config.environment = .development
      case "custom":
        config.environment = .custom
      default:
        break
      }
    }

    if let endpoint = parseString(options["apiEndpoint"]), let url = URL(string: endpoint) {
      config.apiEndpoint = url
      config.environment = .custom
    }

    if let logLevel = options["logLevel"] as? String {
      switch logLevel {
      case "verbose": config.logLevel = .verbose
      case "debug": config.logLevel = .debug
      case "info": config.logLevel = .info
      case "warning": config.logLevel = .warning
      case "error": config.logLevel = .error
      case "none": config.logLevel = .none
      default: break
      }
    }

    if let value = parseBoolean(options["enableConsoleLogging"]) { config.enableConsoleLogging = value }
    if let value = parseBoolean(options["enableFileLogging"]) { config.enableFileLogging = value }
    if let value = parseBoolean(options["redactSensitiveData"]) { config.redactSensitiveData = value }
    if let value = parseDouble(options["requestTimeoutSeconds"]) { config.requestTimeout = value }
    if let value = parseInteger(options["retryCount"]) { config.retryCount = value }
    if let value = parseDouble(options["retryDelaySeconds"]) { config.retryDelay = value }
    if let value = parseDouble(options["syncIntervalSeconds"]) { config.syncInterval = value }
    if let value = parseBoolean(options["enableCompression"]) { config.enableCompression = value }
    if let value = parseInteger(options["eventBatchSize"]) { config.eventBatchSize = value }
    if let value = parseInteger(options["flushAt"]) { config.flushAt = value }
    if let value = parseDouble(options["flushIntervalSeconds"]) { config.flushInterval = value }
    if let value = parseInteger(options["maxQueueSize"]) { config.maxQueueSize = value }
    if let value = parseInt64(options["maxCacheSizeBytes"]) { config.maxCacheSize = value }
    if let value = parseDouble(options["cacheExpirationSeconds"]) { config.cacheExpiration = value }
    if let value = parseBoolean(options["enableEncryption"]) { config.enableEncryption = value }
    if let value = parseDouble(options["featureCacheTtlSeconds"]) { config.featureCacheTTL = value }
    if let value = parseDouble(options["defaultPaywallTimeoutSeconds"]) { config.defaultPaywallTimeout = value }
    if let value = parseBoolean(options["respectDoNotTrack"]) { config.respectDoNotTrack = value }
    if let value = options["localeIdentifier"] as? String { config.localeIdentifier = value.isEmpty ? nil : value }
    if let value = parseBoolean(options["isDebugMode"]) { config.isDebugMode = value }
    if let value = parseBoolean(options["enablePlugins"]) { config.enablePlugins = value }
    if let value = parseInt64(options["maxFlowCacheSizeBytes"]) { config.maxFlowCacheSize = value }
    if let value = parseDouble(options["flowCacheExpirationSeconds"]) { config.flowCacheExpiration = value }
    if let value = parseInteger(options["maxConcurrentFlowDownloads"]) { config.maxConcurrentFlowDownloads = value }
    if let value = parseDouble(options["flowDownloadTimeoutSeconds"]) { config.flowDownloadTimeout = value }

    if let value = parseString(options["customStoragePath"]), let url = parseURL(value) {
      config.customStoragePath = url
    }

    if let value = parseString(options["flowCacheDirectory"]), let url = parseURL(value) {
      config.flowCacheDirectory = url
    }

    if let linking = options["eventLinkingPolicy"] as? String {
      config.eventLinkingPolicy = (linking == "keep_separate" || linking == "keepSeparate")
        ? .keepSeparate
        : .migrateOnIdentify
    }

    if let timeoutSeconds = parseDouble(options["purchaseTimeoutSeconds"]), timeoutSeconds > 0 {
      purchaseDelegateBridge.timeoutSeconds = timeoutSeconds
    }

    if usePurchaseController {
      config.purchaseDelegate = purchaseDelegateBridge
    }

    return config
  }

  private func normalizeRequiredBalance(_ value: Int?) -> Int? {
    guard let value else { return nil }
    if value < 0 {
      return nil
    }
    return value
  }

  private func normalizeEntityId(_ value: String?) -> String? {
    guard let value = value?.trimmingCharacters(in: .whitespacesAndNewlines), !value.isEmpty else {
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
  private let bridge: NuxieGodotBridge

  private init() {
    bridge = NuxieGodotBridge()
    bridge.setEventEmitter { [weak self] eventName, payload in
      self?.enqueue(eventName: eventName, payload: payload)
    }
  }

  func shutdown() {
    bridge.shutdown(requestId: "__runtime_shutdown__")
    lock.lock()
    pendingEvents.removeAll()
    lock.unlock()
  }

  func invoke(method: String, argsJSON: String) -> String {
    let normalized = argsJSON.isEmpty ? "{}" : argsJSON
    guard let args = dictionaryFromJSON(normalized) else {
      return errorResponse(code: "INVALID_CONFIGURATION", message: "Failed to parse args JSON")
    }

    return dispatch(method: method, args: args)
  }

  func pendingEventCount() -> Int32 {
    lock.lock()
    defer { lock.unlock() }
    return Int32(pendingEvents.count)
  }

  func popPendingEventJSON() -> String? {
    lock.lock()
    defer { lock.unlock() }

    guard !pendingEvents.isEmpty else {
      return nil
    }

    let event = pendingEvents.removeFirst()
    return jsonString(event)
  }

  private func enqueue(eventName: String, payload: [String: Any]) {
    lock.lock()
    pendingEvents.append([
      "event": eventName,
      "payload": payload,
    ])
    lock.unlock()
  }

  private func dispatch(method: String, args: [String: Any]) -> String {
    switch method {
    case "configure":
      guard let apiKey = args["apiKey"] as? String,
            let requestId = args["requestId"] as? String
      else {
        return errorResponse(code: "INVALID_CONFIGURATION", message: "configure requires apiKey and requestId")
      }

      bridge.configure(
        apiKey: apiKey,
        options: (args["options"] as? [String: Any]) ?? [:],
        usePurchaseController: parseBoolean(args["usePurchaseController"]) ?? false,
        wrapperVersion: (args["wrapperVersion"] as? String) ?? "",
        requestId: requestId
      )
      return okResponse()

    case "shutdown":
      guard let requestId = args["requestId"] as? String else {
        return errorResponse(code: "INVALID_CONFIGURATION", message: "shutdown requires requestId")
      }
      bridge.shutdown(requestId: requestId)
      return okResponse()

    case "identify":
      guard let distinctId = args["distinctId"] as? String,
            let requestId = args["requestId"] as? String
      else {
        return errorResponse(code: "INVALID_CONFIGURATION", message: "identify requires distinctId and requestId")
      }

      bridge.identify(
        distinctId: distinctId,
        userProperties: (args["userProperties"] as? [String: Any]) ?? [:],
        userPropertiesSetOnce: (args["userPropertiesSetOnce"] as? [String: Any]) ?? [:],
        requestId: requestId
      )
      return okResponse()

    case "reset":
      guard let requestId = args["requestId"] as? String else {
        return errorResponse(code: "INVALID_CONFIGURATION", message: "reset requires requestId")
      }

      bridge.reset(
        keepAnonymousId: parseBoolean(args["keepAnonymousId"]) ?? true,
        requestId: requestId
      )
      return okResponse()

    case "getDistinctId":
      guard let requestId = args["requestId"] as? String else {
        return errorResponse(code: "INVALID_CONFIGURATION", message: "getDistinctId requires requestId")
      }
      bridge.getDistinctId(requestId: requestId)
      return okResponse()

    case "getAnonymousId":
      guard let requestId = args["requestId"] as? String else {
        return errorResponse(code: "INVALID_CONFIGURATION", message: "getAnonymousId requires requestId")
      }
      bridge.getAnonymousId(requestId: requestId)
      return okResponse()

    case "getIsIdentified":
      guard let requestId = args["requestId"] as? String else {
        return errorResponse(code: "INVALID_CONFIGURATION", message: "getIsIdentified requires requestId")
      }
      bridge.getIsIdentified(requestId: requestId)
      return okResponse()

    case "startTrigger":
      guard let requestId = args["requestId"] as? String,
            let eventName = args["eventName"] as? String
      else {
        return errorResponse(code: "INVALID_CONFIGURATION", message: "startTrigger requires requestId and eventName")
      }

      bridge.startTrigger(
        requestId: requestId,
        eventName: eventName,
        properties: (args["properties"] as? [String: Any]) ?? [:],
        userProperties: (args["userProperties"] as? [String: Any]) ?? [:],
        userPropertiesSetOnce: (args["userPropertiesSetOnce"] as? [String: Any]) ?? [:]
      )
      return okResponse()

    case "cancelTrigger":
      guard let requestId = args["requestId"] as? String else {
        return errorResponse(code: "INVALID_CONFIGURATION", message: "cancelTrigger requires requestId")
      }
      bridge.cancelTrigger(requestId: requestId)
      return okResponse()

    case "showFlow":
      guard let flowId = args["flowId"] as? String,
            let requestId = args["requestId"] as? String
      else {
        return errorResponse(code: "INVALID_CONFIGURATION", message: "showFlow requires flowId and requestId")
      }
      bridge.showFlow(flowId: flowId, requestId: requestId)
      return okResponse()

    case "refreshProfile":
      guard let requestId = args["requestId"] as? String else {
        return errorResponse(code: "INVALID_CONFIGURATION", message: "refreshProfile requires requestId")
      }
      bridge.refreshProfile(requestId: requestId)
      return okResponse()

    case "hasFeature":
      guard let featureId = args["featureId"] as? String,
            let requestId = args["requestId"] as? String
      else {
        return errorResponse(code: "INVALID_CONFIGURATION", message: "hasFeature requires featureId and requestId")
      }

      bridge.hasFeature(
        featureId: featureId,
        requiredBalance: parseInteger(args["requiredBalance"]),
        entityId: args["entityId"] as? String,
        requestId: requestId
      )
      return okResponse()

    case "getCachedFeature":
      guard let featureId = args["featureId"] as? String,
            let requestId = args["requestId"] as? String
      else {
        return errorResponse(code: "INVALID_CONFIGURATION", message: "getCachedFeature requires featureId and requestId")
      }

      bridge.getCachedFeature(featureId: featureId, entityId: args["entityId"] as? String, requestId: requestId)
      return okResponse()

    case "checkFeature":
      guard let featureId = args["featureId"] as? String,
            let requestId = args["requestId"] as? String
      else {
        return errorResponse(code: "INVALID_CONFIGURATION", message: "checkFeature requires featureId and requestId")
      }

      bridge.checkFeature(
        featureId: featureId,
        requiredBalance: parseInteger(args["requiredBalance"]),
        entityId: args["entityId"] as? String,
        requestId: requestId
      )
      return okResponse()

    case "refreshFeature":
      guard let featureId = args["featureId"] as? String,
            let requestId = args["requestId"] as? String
      else {
        return errorResponse(code: "INVALID_CONFIGURATION", message: "refreshFeature requires featureId and requestId")
      }

      bridge.refreshFeature(
        featureId: featureId,
        requiredBalance: parseInteger(args["requiredBalance"]),
        entityId: args["entityId"] as? String,
        requestId: requestId
      )
      return okResponse()

    case "useFeature":
      guard let featureId = args["featureId"] as? String,
            let requestId = args["requestId"] as? String
      else {
        return errorResponse(code: "INVALID_CONFIGURATION", message: "useFeature requires featureId and requestId")
      }

      bridge.useFeature(
        featureId: featureId,
        amount: parseDouble(args["amount"]) ?? 1,
        entityId: args["entityId"] as? String,
        metadata: (args["metadata"] as? [String: Any]) ?? [:],
        requestId: requestId
      )
      return okResponse()

    case "useFeatureAndWait":
      guard let featureId = args["featureId"] as? String,
            let requestId = args["requestId"] as? String
      else {
        return errorResponse(code: "INVALID_CONFIGURATION", message: "useFeatureAndWait requires featureId and requestId")
      }

      bridge.useFeatureAndWait(
        featureId: featureId,
        amount: parseDouble(args["amount"]) ?? 1,
        entityId: args["entityId"] as? String,
        setUsage: parseBoolean(args["setUsage"]) ?? false,
        metadata: (args["metadata"] as? [String: Any]) ?? [:],
        requestId: requestId
      )
      return okResponse()

    case "flushEvents":
      guard let requestId = args["requestId"] as? String else {
        return errorResponse(code: "INVALID_CONFIGURATION", message: "flushEvents requires requestId")
      }
      bridge.flushEvents(requestId: requestId)
      return okResponse()

    case "getQueuedEventCount":
      guard let requestId = args["requestId"] as? String else {
        return errorResponse(code: "INVALID_CONFIGURATION", message: "getQueuedEventCount requires requestId")
      }
      bridge.getQueuedEventCount(requestId: requestId)
      return okResponse()

    case "pauseEventQueue":
      guard let requestId = args["requestId"] as? String else {
        return errorResponse(code: "INVALID_CONFIGURATION", message: "pauseEventQueue requires requestId")
      }
      bridge.pauseEventQueue(requestId: requestId)
      return okResponse()

    case "resumeEventQueue":
      guard let requestId = args["requestId"] as? String else {
        return errorResponse(code: "INVALID_CONFIGURATION", message: "resumeEventQueue requires requestId")
      }
      bridge.resumeEventQueue(requestId: requestId)
      return okResponse()

    case "completePurchase":
      guard let requestId = args["requestId"] as? String,
            let result = args["result"] as? [String: Any]
      else {
        return errorResponse(code: "INVALID_CONFIGURATION", message: "completePurchase requires requestId and result")
      }
      bridge.completePurchase(requestId: requestId, result: result)
      return okResponse()

    case "completeRestore":
      guard let requestId = args["requestId"] as? String,
            let result = args["result"] as? [String: Any]
      else {
        return errorResponse(code: "INVALID_CONFIGURATION", message: "completeRestore requires requestId and result")
      }
      bridge.completeRestore(requestId: requestId, result: result)
      return okResponse()

    default:
      return errorResponse(code: "NATIVE_ERROR", message: "Unsupported method '\(method)'")
    }
  }

  private func okResponse() -> String {
    jsonString(["ok": true])
  }

  private func errorResponse(code: String, message: String) -> String {
    jsonString([
      "ok": false,
      "error": bridgeError(code: code, message: message),
    ])
  }
}

@_cdecl("NuxieGodot_Invoke")
public func NuxieGodot_Invoke(
  _ methodPtr: UnsafePointer<CChar>?,
  _ argsJsonPtr: UnsafePointer<CChar>?
) -> UnsafeMutablePointer<CChar>? {
  let method = methodPtr.map(String.init(cString:)) ?? ""
  let argsJson = argsJsonPtr.map(String.init(cString:)) ?? "{}"

  let response = NuxieGodotRuntime.shared.invoke(method: method, argsJSON: argsJson)
  return strdup(response)
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
  guard let pointer else { return }
  free(pointer)
}

@_cdecl("nuxie_godot_init")
public func nuxie_godot_init() {
  _ = NuxieGodotRuntime.shared
}

@_cdecl("nuxie_godot_deinit")
public func nuxie_godot_deinit() {
  NuxieGodotRuntime.shared.shutdown()
}
