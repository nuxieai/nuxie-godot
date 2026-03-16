package io.nuxie.godot

import io.nuxie.sdk.NuxieDelegate
import io.nuxie.sdk.NuxieSDK
import io.nuxie.sdk.campaigns.Campaign
import io.nuxie.sdk.config.Environment
import io.nuxie.sdk.config.EventLinkingPolicy
import io.nuxie.sdk.config.LogLevel
import io.nuxie.sdk.config.NuxieConfiguration
import io.nuxie.sdk.features.FeatureAccess
import io.nuxie.sdk.features.FeatureCheckResult
import io.nuxie.sdk.features.FeatureType
import io.nuxie.sdk.features.FeatureUsageResult
import io.nuxie.sdk.flows.RemoteFlow
import io.nuxie.sdk.network.models.ProfileResponse
import io.nuxie.sdk.purchases.NuxiePurchaseDelegate
import io.nuxie.sdk.purchases.PurchaseOutcome
import io.nuxie.sdk.purchases.PurchaseResult
import io.nuxie.sdk.purchases.RestoreResult
import io.nuxie.sdk.triggers.EntitlementUpdate
import io.nuxie.sdk.triggers.GateSource
import io.nuxie.sdk.triggers.JourneyExitReason
import io.nuxie.sdk.triggers.JourneyRef
import io.nuxie.sdk.triggers.JourneyUpdate
import io.nuxie.sdk.triggers.SuppressReason
import io.nuxie.sdk.triggers.TriggerDecision
import io.nuxie.sdk.triggers.TriggerError
import io.nuxie.sdk.triggers.TriggerHandle
import io.nuxie.sdk.triggers.TriggerUpdate
import java.util.UUID
import java.util.concurrent.ConcurrentHashMap
import java.util.concurrent.atomic.AtomicLong
import kotlinx.coroutines.CompletableDeferred
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.cancel
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import kotlinx.coroutines.withTimeout
import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonElement
import kotlinx.serialization.json.JsonNull
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.booleanOrNull
import kotlinx.serialization.json.doubleOrNull
import kotlinx.serialization.json.longOrNull
import org.godotengine.godot.Dictionary
import org.godotengine.godot.Godot
import org.godotengine.godot.plugin.GodotPlugin
import org.godotengine.godot.plugin.SignalInfo
import org.godotengine.godot.plugin.UsedByGodot

class NuxieGodotPlugin(godot: Godot) : GodotPlugin(godot), NuxieDelegate {
  private val sdk: NuxieSDK = NuxieSDK.shared()
  private val scope = CoroutineScope(SupervisorJob() + Dispatchers.Main.immediate)

  private val triggerHandles = ConcurrentHashMap<String, TriggerHandle>()
  private val pendingPurchases = ConcurrentHashMap<String, CompletableDeferred<Dictionary>>()
  private val pendingRestores = ConcurrentHashMap<String, CompletableDeferred<Dictionary>>()
  private val requestCounter = AtomicLong(0)

  @Volatile
  private var purchaseTimeoutMs: Long = 60_000L

  override fun getPluginName(): String = BuildConfig.GODOT_PLUGIN_NAME

  override fun getPluginSignals(): MutableSet<SignalInfo> {
    return mutableSetOf(
      SignalInfo(
        "operation_result",
        String::class.java,
        String::class.java,
        Boolean::class.java,
        Dictionary::class.java,
        Dictionary::class.java,
        Long::class.java,
      ),
      SignalInfo(
        "trigger_update",
        String::class.java,
        Dictionary::class.java,
        Boolean::class.java,
        Long::class.java,
      ),
      SignalInfo(
        "feature_access_changed",
        String::class.java,
        Dictionary::class.java,
        Dictionary::class.java,
        Long::class.java,
      ),
      SignalInfo("purchase_request", Dictionary::class.java),
      SignalInfo("restore_request", Dictionary::class.java),
      SignalInfo("flow_lifecycle", Dictionary::class.java),
    )
  }

  override fun onMainDestroy() {
    cleanupPendingRequests("plugin_destroyed")
    scope.cancel()
    super.onMainDestroy()
  }

  @UsedByGodot
  fun configure(
    apiKey: String,
    options: Dictionary,
    usePurchaseController: Boolean,
    wrapperVersion: String,
    requestId: String,
  ) {
    val result = Dictionary()
    val error = Dictionary()

    runCatching {
      val config = buildConfiguration(apiKey, options, usePurchaseController)
      sdk.setup(context, config)
      sdk.delegate = this
      result["isConfigured"] = true
      result["wrapperVersion"] = wrapperVersion
    }.onSuccess {
      emitOperation("configure", requestId, true, result, error)
    }.onFailure { throwable ->
      error["code"] = "CONFIGURE_FAILED"
      error["message"] = throwable.message ?: "configure_failed"
      emitOperation("configure", requestId, false, result, error)
    }
  }

  @UsedByGodot
  fun shutdown(requestId: String) {
    runSuspend("shutdown", requestId) {
      cleanupPendingRequests("sdk_shutdown")
      sdk.shutdown()
      Dictionary().apply { put("isConfigured", false) }
    }
  }

  @UsedByGodot
  fun identify(
    distinctId: String,
    userProperties: Dictionary,
    userPropertiesSetOnce: Dictionary,
    requestId: String,
  ) {
    val result = Dictionary()
    val error = Dictionary()

    runCatching {
      sdk.identify(
        distinctId,
        userProperties = userProperties.toStringKeyMap(),
        userPropertiesSetOnce = userPropertiesSetOnce.toStringKeyMap(),
      )
      result["distinctId"] = sdk.getDistinctId()
    }.onSuccess {
      emitOperation("identify", requestId, true, result, error)
    }.onFailure { throwable ->
      error["code"] = "IDENTIFY_FAILED"
      error["message"] = throwable.message ?: "identify_failed"
      emitOperation("identify", requestId, false, result, error)
    }
  }

  @UsedByGodot
  fun reset(keepAnonymousId: Boolean, requestId: String) {
    val result = Dictionary()
    val error = Dictionary()

    runCatching {
      sdk.reset(keepAnonymousId)
      result["distinctId"] = sdk.getDistinctId()
      result["anonymousId"] = sdk.getAnonymousId()
      result["isIdentified"] = sdk.isIdentified
    }.onSuccess {
      emitOperation("reset", requestId, true, result, error)
    }.onFailure { throwable ->
      error["code"] = "RESET_FAILED"
      error["message"] = throwable.message ?: "reset_failed"
      emitOperation("reset", requestId, false, result, error)
    }
  }

  @UsedByGodot
  fun getDistinctId(requestId: String) {
    val result = Dictionary()
    result["distinctId"] = sdk.getDistinctId()
    emitOperation("getDistinctId", requestId, true, result, Dictionary())
  }

  @UsedByGodot
  fun getAnonymousId(requestId: String) {
    val result = Dictionary()
    result["anonymousId"] = sdk.getAnonymousId()
    emitOperation("getAnonymousId", requestId, true, result, Dictionary())
  }

  @UsedByGodot
  fun getIsIdentified(requestId: String) {
    val result = Dictionary()
    result["isIdentified"] = sdk.isIdentified
    emitOperation("getIsIdentified", requestId, true, result, Dictionary())
  }

  @UsedByGodot
  fun startTrigger(
    requestId: String,
    eventName: String,
    properties: Dictionary,
    userProperties: Dictionary,
    userPropertiesSetOnce: Dictionary,
  ) {
    val result = Dictionary()
    val error = Dictionary()

    runCatching {
      val handle = sdk.trigger(
        event = eventName,
        properties = properties.toStringKeyMap(),
        userProperties = userProperties.toStringKeyMap(),
        userPropertiesSetOnce = userPropertiesSetOnce.toStringKeyMap(),
      ) { update ->
        sendTriggerUpdate(requestId, update)
      }

      triggerHandles[requestId] = handle
      result["requestId"] = requestId
    }.onSuccess {
      emitOperation("startTrigger", requestId, true, result, error)
    }.onFailure { throwable ->
      error["code"] = "TRIGGER_START_FAILED"
      error["message"] = throwable.message ?: "trigger_start_failed"
      emitOperation("startTrigger", requestId, false, result, error)
    }
  }

  @UsedByGodot
  fun cancelTrigger(requestId: String) {
    triggerHandles.remove(requestId)?.cancel()
    emitOperation("cancelTrigger", requestId, true, Dictionary(), Dictionary())
  }

  @UsedByGodot
  fun showFlow(flowId: String, requestId: String) {
    val result = Dictionary()
    val error = Dictionary()

    runCatching {
      sdk.showFlow(flowId)
      result["flowId"] = flowId
      emitFlowLifecycle(
        Dictionary().apply {
          put("type", "presented")
          put("flowId", flowId)
          put("timestampMs", System.currentTimeMillis())
        },
      )
    }.onSuccess {
      emitOperation("showFlow", requestId, true, result, error)
    }.onFailure { throwable ->
      error["code"] = "FLOW_PRESENT_FAILED"
      error["message"] = throwable.message ?: "flow_present_failed"
      emitOperation("showFlow", requestId, false, result, error)
    }
  }

  @UsedByGodot
  fun refreshProfile(requestId: String) {
    runSuspend("refreshProfile", requestId) {
      val response = sdk.refreshProfile()
      Dictionary().apply {
        put("profile", response.toBridgeDictionary())
      }
    }
  }

  @UsedByGodot
  fun hasFeature(featureId: String, requiredBalance: Long, entityId: String, requestId: String) {
    runSuspend("hasFeature", requestId) {
      val access = if (requiredBalance < 0 && entityId.isBlank()) {
        sdk.hasFeature(featureId)
      } else {
        sdk.hasFeature(featureId, requiredBalance.toInt(), entityId.ifBlank { null })
      }
      Dictionary().apply {
        put("access", access.toBridgeDictionary())
      }
    }
  }

  @UsedByGodot
  fun getCachedFeature(featureId: String, entityId: String, requestId: String) {
    runSuspend("getCachedFeature", requestId) {
      val access = sdk.getCachedFeature(featureId, entityId.ifBlank { null })
      Dictionary().apply {
        put("access", access?.toBridgeDictionary())
      }
    }
  }

  @UsedByGodot
  fun checkFeature(featureId: String, requiredBalance: Long, entityId: String, requestId: String) {
    runSuspend("checkFeature", requestId) {
      val result = sdk.checkFeature(
        featureId = featureId,
        requiredBalance = requiredBalance.takeIf { it >= 0 }?.toInt(),
        entityId = entityId.ifBlank { null },
      )
      Dictionary().apply {
        put("result", result.toBridgeDictionary())
      }
    }
  }

  @UsedByGodot
  fun refreshFeature(featureId: String, requiredBalance: Long, entityId: String, requestId: String) {
    runSuspend("refreshFeature", requestId) {
      val result = sdk.refreshFeature(
        featureId = featureId,
        requiredBalance = requiredBalance.takeIf { it >= 0 }?.toInt(),
        entityId = entityId.ifBlank { null },
      )
      Dictionary().apply {
        put("result", result.toBridgeDictionary())
      }
    }
  }

  @UsedByGodot
  fun useFeature(featureId: String, amount: Double, entityId: String, metadata: Dictionary, requestId: String) {
    val result = Dictionary()
    val error = Dictionary()

    runCatching {
      sdk.useFeature(
        featureId = featureId,
        amount = amount,
        entityId = entityId.ifBlank { null },
        metadata = metadata.toStringKeyMap(),
      )
      result["accepted"] = true
    }.onSuccess {
      emitOperation("useFeature", requestId, true, result, error)
    }.onFailure { throwable ->
      error["code"] = "USE_FEATURE_FAILED"
      error["message"] = throwable.message ?: "use_feature_failed"
      emitOperation("useFeature", requestId, false, result, error)
    }
  }

  @UsedByGodot
  fun useFeatureAndWait(
    featureId: String,
    amount: Double,
    entityId: String,
    setUsage: Boolean,
    metadata: Dictionary,
    requestId: String,
  ) {
    runSuspend("useFeatureAndWait", requestId) {
      val usageResult = sdk.useFeatureAndWait(
        featureId = featureId,
        amount = amount,
        entityId = entityId.ifBlank { null },
        setUsage = setUsage,
        metadata = metadata.toStringKeyMap(),
      )
      Dictionary().apply {
        put("result", usageResult.toBridgeDictionary())
      }
    }
  }

  @UsedByGodot
  fun flushEvents(requestId: String) {
    runSuspend("flushEvents", requestId) {
      Dictionary().apply {
        put("flushed", sdk.flushEvents())
      }
    }
  }

  @UsedByGodot
  fun getQueuedEventCount(requestId: String) {
    runSuspend("getQueuedEventCount", requestId) {
      Dictionary().apply {
        put("queuedEventCount", sdk.getQueuedEventCount().toLong())
      }
    }
  }

  @UsedByGodot
  fun pauseEventQueue(requestId: String) {
    runSuspend("pauseEventQueue", requestId) {
      sdk.pauseEventQueue()
      Dictionary().apply { put("paused", true) }
    }
  }

  @UsedByGodot
  fun resumeEventQueue(requestId: String) {
    runSuspend("resumeEventQueue", requestId) {
      sdk.resumeEventQueue()
      Dictionary().apply { put("paused", false) }
    }
  }

  @UsedByGodot
  fun completePurchase(requestId: String, result: Dictionary) {
    val pending = pendingPurchases.remove(requestId)
    if (pending == null) {
      emitOperation(
        "completePurchase",
        requestId,
        false,
        Dictionary(),
        Dictionary().apply {
          put("code", "PURCHASE_REQUEST_NOT_FOUND")
          put("message", "No pending purchase request for $requestId")
        },
      )
      return
    }

    pending.complete(result)
    emitOperation("completePurchase", requestId, true, Dictionary(), Dictionary())
  }

  @UsedByGodot
  fun completeRestore(requestId: String, result: Dictionary) {
    val pending = pendingRestores.remove(requestId)
    if (pending == null) {
      emitOperation(
        "completeRestore",
        requestId,
        false,
        Dictionary(),
        Dictionary().apply {
          put("code", "RESTORE_REQUEST_NOT_FOUND")
          put("message", "No pending restore request for $requestId")
        },
      )
      return
    }

    pending.complete(result)
    emitOperation("completeRestore", requestId, true, Dictionary(), Dictionary())
  }

  override fun featureAccessDidChange(featureId: String, from: FeatureAccess?, to: FeatureAccess) {
    val fromDictionary = from?.toBridgeDictionary() ?: Dictionary()
    val toDictionary = to.toBridgeDictionary()

    runOnHostThread {
      emitSignal(
        "feature_access_changed",
        featureId,
        fromDictionary,
        toDictionary,
        System.currentTimeMillis(),
      )
    }
  }

  override fun flowDelegateCalled(message: String, payload: Any?, journeyId: String, campaignId: String?) {
    emitFlowLifecycle(
      Dictionary().apply {
        put("type", "delegate_called")
        put("timestampMs", System.currentTimeMillis())
        put("payload", mapOf(
          "message" to message,
          "payload" to payload,
          "journeyId" to journeyId,
          "campaignId" to campaignId,
        ).toGodotDictionary())
      },
    )
  }

  override fun flowPurchaseRequested(
    journeyId: String,
    campaignId: String?,
    screenId: String?,
    productId: String,
    placementIndex: Any?,
  ) {
    emitFlowLifecycle(
      Dictionary().apply {
        put("type", "purchase_requested")
        put("timestampMs", System.currentTimeMillis())
        put("payload", mapOf(
          "journeyId" to journeyId,
          "campaignId" to campaignId,
          "screenId" to screenId,
          "productId" to productId,
          "placementIndex" to placementIndex,
        ).toGodotDictionary())
      },
    )
  }

  override fun flowRestoreRequested(journeyId: String, campaignId: String?, screenId: String?) {
    emitFlowLifecycle(
      Dictionary().apply {
        put("type", "restore_requested")
        put("timestampMs", System.currentTimeMillis())
        put("payload", mapOf(
          "journeyId" to journeyId,
          "campaignId" to campaignId,
          "screenId" to screenId,
        ).toGodotDictionary())
      },
    )
  }

  override fun flowOpenLinkRequested(
    journeyId: String,
    campaignId: String?,
    screenId: String?,
    url: String,
    target: String?,
  ) {
    emitFlowLifecycle(
      Dictionary().apply {
        put("type", "open_link_requested")
        put("timestampMs", System.currentTimeMillis())
        put("payload", mapOf(
          "journeyId" to journeyId,
          "campaignId" to campaignId,
          "screenId" to screenId,
          "url" to url,
          "target" to target,
        ).toGodotDictionary())
      },
    )
  }

  override fun flowDismissed(
    journeyId: String,
    campaignId: String?,
    screenId: String?,
    reason: String,
    error: String?,
  ) {
    emitFlowLifecycle(
      Dictionary().apply {
        put("type", "dismissed")
        put("reason", reason)
        put("timestampMs", System.currentTimeMillis())
        put("payload", mapOf(
          "journeyId" to journeyId,
          "campaignId" to campaignId,
          "screenId" to screenId,
          "error" to error,
        ).toGodotDictionary())
      },
    )
  }

  override fun flowBackRequested(journeyId: String, campaignId: String?, screenId: String?, steps: Int) {
    emitFlowLifecycle(
      Dictionary().apply {
        put("type", "back_requested")
        put("timestampMs", System.currentTimeMillis())
        put("payload", mapOf(
          "journeyId" to journeyId,
          "campaignId" to campaignId,
          "screenId" to screenId,
          "steps" to steps,
        ).toGodotDictionary())
      },
    )
  }

  private fun buildConfiguration(apiKey: String, options: Dictionary, usePurchaseController: Boolean): NuxieConfiguration {
    val config = NuxieConfiguration(apiKey)

    options.string("environment")?.let { config.environment = it.toEnvironment() }
    options.string("apiEndpoint")?.takeIf { it.isNotBlank() }?.let { config.setApiEndpoint(it) }

    options.string("logLevel")?.let { config.logLevel = it.toLogLevel() }
    options.boolean("enableConsoleLogging")?.let { config.enableConsoleLogging = it }
    options.boolean("enableFileLogging")?.let { config.enableFileLogging = it }
    options.boolean("redactSensitiveData")?.let { config.redactSensitiveData = it }

    options.long("requestTimeoutSeconds")?.let { config.requestTimeoutSeconds = it }
    options.int("retryCount")?.let { config.retryCount = it }
    options.long("retryDelaySeconds")?.let { config.retryDelaySeconds = it }
    options.long("syncIntervalSeconds")?.let { config.syncIntervalSeconds = it }
    options.boolean("enableCompression")?.let { config.enableCompression = it }

    options.int("eventBatchSize")?.let { config.eventBatchSize = it }
    options.int("flushAt")?.let { config.flushAt = it }
    options.long("flushIntervalSeconds")?.let { config.flushIntervalSeconds = it }
    options.int("maxQueueSize")?.let { config.maxQueueSize = it }

    options.long("maxCacheSizeBytes")?.let { config.maxCacheSizeBytes = it }
    options.long("cacheExpirationSeconds")?.let { config.cacheExpirationSeconds = it }
    options.boolean("enableEncryption")?.let { config.enableEncryption = it }

    options.long("featureCacheTtlSeconds")?.let { config.featureCacheTtlSeconds = it }

    options.long("defaultPaywallTimeoutSeconds")?.let { config.defaultPaywallTimeoutSeconds = it }
    options.boolean("respectDoNotTrack")?.let { config.respectDoNotTrack = it }
    options.string("localeIdentifier")?.let { config.localeIdentifier = it }
    options.boolean("isDebugMode")?.let { config.isDebugMode = it }

    options.boolean("enablePlugins")?.let { config.enablePlugins = it }

    options.long("maxFlowCacheSizeBytes")?.let { config.maxFlowCacheSizeBytes = it }
    options.long("flowCacheExpirationSeconds")?.let { config.flowCacheExpirationSeconds = it }
    options.int("maxConcurrentFlowDownloads")?.let { config.maxConcurrentFlowDownloads = it }
    options.long("flowDownloadTimeoutSeconds")?.let { config.flowDownloadTimeoutSeconds = it }

    options.string("customStoragePath")?.takeIf { it.isNotBlank() }?.let { config.customStoragePath = it }
    options.string("flowCacheDirectory")?.takeIf { it.isNotBlank() }?.let { config.flowCacheDirectory = it }

    options.string("eventLinkingPolicy")?.let {
      config.eventLinkingPolicy = when (it.lowercase()) {
        "keep_separate", "keepseparate" -> EventLinkingPolicy.KEEP_SEPARATE
        else -> EventLinkingPolicy.MIGRATE_ON_IDENTIFY
      }
    }

    options.long("purchaseTimeoutSeconds")?.let { purchaseTimeoutMs = it * 1000L }

    if (usePurchaseController) {
      config.purchaseDelegate = GodotPurchaseDelegate()
    }

    return config
  }

  private fun sendTriggerUpdate(requestId: String, update: TriggerUpdate) {
    val payload = update.toBridgeDictionary()
    val isTerminal = update.isTerminal()

    runOnHostThread {
      emitSignal(
        "trigger_update",
        requestId,
        payload,
        isTerminal,
        System.currentTimeMillis(),
      )
    }

    if (isTerminal) {
      triggerHandles.remove(requestId)
    }
  }

  private fun emitFlowLifecycle(event: Dictionary) {
    runOnHostThread {
      emitSignal("flow_lifecycle", event)
    }
  }

  private fun emitOperation(method: String, requestId: String, ok: Boolean, result: Dictionary, error: Dictionary) {
    runOnHostThread {
      emitSignal(
        "operation_result",
        requestId,
        method,
        ok,
        result,
        error,
        System.currentTimeMillis(),
      )
    }
  }

  private fun runSuspend(method: String, requestId: String, block: suspend () -> Dictionary) {
    scope.launch {
      runCatching {
        block()
      }.onSuccess { result ->
        emitOperation(method, requestId, true, result, Dictionary())
      }.onFailure { throwable ->
        emitOperation(
          method,
          requestId,
          false,
          Dictionary(),
          Dictionary().apply {
            put("code", "NATIVE_ERROR")
            put("message", throwable.message ?: throwable.toString())
          },
        )
      }
    }
  }

  private fun cleanupPendingRequests(reason: String) {
    for ((_, deferred) in pendingPurchases) {
      if (deferred.isActive) {
        deferred.complete(Dictionary().apply {
          put("type", "failed")
          put("message", reason)
        })
      }
    }
    pendingPurchases.clear()

    for ((_, deferred) in pendingRestores) {
      if (deferred.isActive) {
        deferred.complete(Dictionary().apply {
          put("type", "failed")
          put("message", reason)
        })
      }
    }
    pendingRestores.clear()

    for ((_, handle) in triggerHandles) {
      handle.cancel()
    }
    triggerHandles.clear()
  }

  private fun nextRequestId(prefix: String): String {
    val id = requestCounter.incrementAndGet()
    return "$prefix-${System.currentTimeMillis()}-$id-${UUID.randomUUID()}"
  }

  private inner class GodotPurchaseDelegate : NuxiePurchaseDelegate {
    override suspend fun purchase(productId: String): PurchaseResult {
      return purchaseOutcome(productId).result
    }

    override suspend fun purchaseOutcome(productId: String): PurchaseOutcome {
      val requestId = nextRequestId("purchase")
      val deferred = CompletableDeferred<Dictionary>()
      pendingPurchases[requestId] = deferred

      val request = Dictionary().apply {
        put("requestId", requestId)
        put("platform", "android")
        put("productId", productId)
        put("timestampMs", System.currentTimeMillis())
      }

      withContext(Dispatchers.Main.immediate) {
        emitSignal("purchase_request", request)
      }

      val response = try {
        withTimeout(purchaseTimeoutMs) { deferred.await() }
      } catch (_: Throwable) {
        Dictionary().apply {
          put("type", "failed")
          put("message", "purchase_timeout")
          put("productId", productId)
        }
      } finally {
        pendingPurchases.remove(requestId)
      }

      return response.toPurchaseOutcome(defaultProductId = productId)
    }

    override suspend fun restore(): RestoreResult {
      val requestId = nextRequestId("restore")
      val deferred = CompletableDeferred<Dictionary>()
      pendingRestores[requestId] = deferred

      val request = Dictionary().apply {
        put("requestId", requestId)
        put("platform", "android")
        put("timestampMs", System.currentTimeMillis())
      }

      withContext(Dispatchers.Main.immediate) {
        emitSignal("restore_request", request)
      }

      val response = try {
        withTimeout(purchaseTimeoutMs) { deferred.await() }
      } catch (_: Throwable) {
        Dictionary().apply {
          put("type", "failed")
          put("message", "restore_timeout")
        }
      } finally {
        pendingRestores.remove(requestId)
      }

      return response.toRestoreResult()
    }
  }
}

private fun Dictionary.string(key: String): String? = this[key] as? String

private fun Dictionary.boolean(key: String): Boolean? = when (val value = this[key]) {
  is Boolean -> value
  else -> null
}

private fun Dictionary.int(key: String): Int? = (this[key] as? Number)?.toInt()

private fun Dictionary.long(key: String): Long? = (this[key] as? Number)?.toLong()

private fun Dictionary.toStringKeyMap(): Map<String, Any?> {
  if (isEmpty()) return emptyMap()
  val output = mutableMapOf<String, Any?>()
  for ((key, value) in this) {
    output[key] = value.toBridgeValue()
  }
  return output
}

internal fun TriggerUpdate.isTerminal(): Boolean {
  return when (this) {
    is TriggerUpdate.Error -> true
    is TriggerUpdate.Journey -> true
    is TriggerUpdate.Decision -> when (decision) {
      TriggerDecision.AllowedImmediate,
      TriggerDecision.DeniedImmediate,
      TriggerDecision.NoMatch,
      is TriggerDecision.Suppressed,
      -> true
      else -> false
    }

    is TriggerUpdate.Entitlement -> when (entitlement) {
      is EntitlementUpdate.Allowed,
      EntitlementUpdate.Denied,
      -> true
      EntitlementUpdate.Pending -> false
    }
  }
}

private fun TriggerUpdate.toBridgeDictionary(): Dictionary {
  return when (this) {
    is TriggerUpdate.Decision -> Dictionary().apply {
      put("kind", "decision")
      put("decision", decision.toBridgeDictionary())
    }

    is TriggerUpdate.Entitlement -> Dictionary().apply {
      put("kind", "entitlement")
      put("entitlement", entitlement.toBridgeDictionary())
    }

    is TriggerUpdate.Journey -> Dictionary().apply {
      put("kind", "journey")
      put("journey", journey.toBridgeDictionary())
    }

    is TriggerUpdate.Error -> Dictionary().apply {
      put("kind", "error")
      put("error", error.toBridgeDictionary())
    }
  }
}

private fun TriggerDecision.toBridgeDictionary(): Dictionary {
  return when (this) {
    TriggerDecision.NoMatch -> Dictionary().apply { put("type", "no_match") }
    TriggerDecision.AllowedImmediate -> Dictionary().apply { put("type", "allowed_immediate") }
    TriggerDecision.DeniedImmediate -> Dictionary().apply { put("type", "denied_immediate") }
    is TriggerDecision.JourneyStarted -> Dictionary().apply {
      put("type", "journey_started")
      put("ref", ref.toBridgeDictionary())
    }

    is TriggerDecision.JourneyResumed -> Dictionary().apply {
      put("type", "journey_resumed")
      put("ref", ref.toBridgeDictionary())
    }

    is TriggerDecision.FlowShown -> Dictionary().apply {
      put("type", "flow_shown")
      put("ref", ref.toBridgeDictionary())
    }

    is TriggerDecision.Suppressed -> Dictionary().apply {
      put("type", "suppressed")
      putAll(reason.toBridgeDictionary())
    }
  }
}

private fun JourneyRef.toBridgeDictionary(): Dictionary {
  return Dictionary().apply {
    put("journeyId", journeyId)
    put("campaignId", campaignId)
    put("flowId", flowId)
  }
}

private fun SuppressReason.toBridgeDictionary(): Dictionary {
  return when (this) {
    SuppressReason.AlreadyActive -> Dictionary().apply { put("reason", "already_active") }
    SuppressReason.ReentryLimited -> Dictionary().apply { put("reason", "reentry_limited") }
    SuppressReason.Holdout -> Dictionary().apply { put("reason", "holdout") }
    SuppressReason.NoFlow -> Dictionary().apply { put("reason", "no_flow") }
    is SuppressReason.Unknown -> Dictionary().apply {
      put("reason", "unknown")
      put("rawReason", value)
    }
  }
}

private fun EntitlementUpdate.toBridgeDictionary(): Dictionary {
  return when (this) {
    EntitlementUpdate.Pending -> Dictionary().apply { put("type", "pending") }
    EntitlementUpdate.Denied -> Dictionary().apply { put("type", "denied") }
    is EntitlementUpdate.Allowed -> Dictionary().apply {
      put("type", "allowed")
      put("source", source.toBridgeValue())
    }
  }
}

private fun GateSource.toBridgeValue(): String {
  return when (this) {
    GateSource.CACHE -> "cache"
    GateSource.PURCHASE -> "purchase"
    GateSource.RESTORE -> "restore"
  }
}

private fun JourneyUpdate.toBridgeDictionary(): Dictionary {
  return Dictionary().apply {
    put("journeyId", journeyId)
    put("campaignId", campaignId)
    put("flowId", flowId)
    put("exitReason", exitReason.toBridgeValue())
    put("goalMet", goalMet)
    put("goalMetAtEpochMillis", goalMetAtEpochMillis)
    put("durationSeconds", durationSeconds)
    put("flowExitReason", flowExitReason)
  }
}

private fun JourneyExitReason.toBridgeValue(): String {
  return when (this) {
    JourneyExitReason.COMPLETED -> "completed"
    JourneyExitReason.DISMISSED -> "dismissed"
    JourneyExitReason.GOAL_MET -> "goal_met"
    JourneyExitReason.TRIGGER_UNMATCHED -> "trigger_unmatched"
    JourneyExitReason.EXPIRED -> "expired"
    JourneyExitReason.ERROR -> "error"
    JourneyExitReason.CANCELLED -> "cancelled"
  }
}

private fun TriggerError.toBridgeDictionary(): Dictionary {
  return Dictionary().apply {
    put("code", code)
    put("message", message)
  }
}

private fun FeatureType.toBridgeValue(): String {
  return when (this) {
    FeatureType.BOOLEAN -> "boolean"
    FeatureType.METERED -> "metered"
    FeatureType.CREDIT_SYSTEM -> "creditSystem"
  }
}

private fun FeatureAccess.toBridgeDictionary(): Dictionary {
  return Dictionary().apply {
    put("allowed", allowed)
    put("unlimited", unlimited)
    put("balance", balance)
    put("type", type.toBridgeValue())
  }
}

private fun FeatureCheckResult.toBridgeDictionary(): Dictionary {
  return Dictionary().apply {
    put("customerId", customerId)
    put("featureId", featureId)
    put("requiredBalance", requiredBalance)
    put("code", code)
    put("allowed", allowed)
    put("unlimited", unlimited)
    put("balance", balance)
    put("type", type.toBridgeValue())
    put("preview", preview?.toBridgeValue())
  }
}

private fun FeatureUsageResult.toBridgeDictionary(): Dictionary {
  return Dictionary().apply {
    put("success", success)
    put("featureId", featureId)
    put("amountUsed", amountUsed)
    put("message", message)
    put(
      "usage",
      usage?.let {
        Dictionary().apply {
          put("current", it.current)
          put("limit", it.limit)
          put("remaining", it.remaining)
        }
      },
    )
  }
}

private fun ProfileResponse.toBridgeDictionary(): Dictionary {
  return Dictionary().apply {
    put("campaigns", campaigns.map { it.toBridgeDictionary() })
    put("segments", segments.map { mapOf("id" to it.id, "name" to it.name).toGodotDictionary() })
    put("flows", flows.map { it.toBridgeDictionary() })
    put("userProperties", userProperties?.toBridgeValue())
    put(
      "experiments",
      experiments?.mapValues { (_, assignment) ->
        mapOf(
          "experimentKey" to assignment.experimentKey,
          "variantKey" to assignment.variantKey,
          "status" to assignment.status,
          "isHoldout" to assignment.isHoldout,
        ).toGodotDictionary()
      }?.toGodotDictionary(),
    )
    put(
      "features",
      features?.map {
        mapOf(
          "id" to it.id,
          "type" to it.type.toBridgeValue(),
          "balance" to it.balance,
          "unlimited" to it.unlimited,
          "nextResetAt" to it.nextResetAt,
          "interval" to it.interval,
          "entities" to it.entities?.mapValues { (_, balance) ->
            mapOf("balance" to balance.balance).toGodotDictionary()
          }?.toGodotDictionary(),
        ).toGodotDictionary()
      } ?: emptyList<Dictionary>(),
    )
    put(
      "journeys",
      journeys?.map {
        mapOf(
          "sessionId" to it.sessionId,
          "campaignId" to it.campaignId,
          "currentNodeId" to it.currentNodeId,
          "context" to it.context.toBridgeValue(),
        ).toGodotDictionary()
      } ?: emptyList<Dictionary>(),
    )
  }
}

private fun Campaign.toBridgeDictionary(): Dictionary {
  return Dictionary().apply {
    put("id", id)
    put("name", name)
    put("flowId", flowId)
    put("flowNumber", flowNumber)
    put("flowName", flowName)
    put("publishedAt", publishedAt)
    put("campaignType", campaignType)
  }
}

private fun RemoteFlow.toBridgeDictionary(): Dictionary {
  return Dictionary().apply {
    put("id", id)
  }
}

private fun JsonElement.toBridgeValue(): Any? {
  return when (this) {
    JsonNull -> null
    is JsonArray -> map { it.toBridgeValue() }
    is JsonObject -> entries.associate { (key, value) -> key to value.toBridgeValue() }.toGodotDictionary()
    is JsonPrimitive -> {
      booleanOrNull ?: longOrNull ?: doubleOrNull ?: content
    }
  }
}

internal fun Dictionary.toPurchaseOutcome(defaultProductId: String): PurchaseOutcome {
  val type = (this["type"] as? String)?.lowercase() ?: "failed"
  val productId = this["productId"] as? String ?: defaultProductId

  val result = when (type) {
    "success" -> PurchaseResult.Success
    "cancelled" -> PurchaseResult.Cancelled
    "pending" -> PurchaseResult.Pending
    else -> PurchaseResult.Failed((this["message"] as? String) ?: "purchase_failed")
  }

  return PurchaseOutcome(
    result = result,
    productId = productId,
    purchaseToken = this["purchaseToken"] as? String,
    orderId = this["orderId"] as? String,
  )
}

internal fun Dictionary.toRestoreResult(): RestoreResult {
  return when ((this["type"] as? String)?.lowercase()) {
    "success" -> RestoreResult.Success((this["restoredCount"] as? Number)?.toInt() ?: 0)
    "no_purchases" -> RestoreResult.NoPurchases
    else -> RestoreResult.Failed((this["message"] as? String) ?: "restore_failed")
  }
}

private fun String.toEnvironment(): Environment {
  return when (lowercase()) {
    "staging" -> Environment.STAGING
    "development" -> Environment.DEVELOPMENT
    "custom" -> Environment.CUSTOM
    else -> Environment.PRODUCTION
  }
}

private fun String.toLogLevel(): LogLevel {
  return when (lowercase()) {
    "verbose" -> LogLevel.VERBOSE
    "debug" -> LogLevel.DEBUG
    "info" -> LogLevel.INFO
    "warning" -> LogLevel.WARNING
    "error" -> LogLevel.ERROR
    "none" -> LogLevel.NONE
    else -> LogLevel.WARNING
  }
}

private fun Map<String, Any?>.toGodotDictionary(): Dictionary {
  val dictionary = Dictionary()
  for ((key, value) in this) {
    dictionary[key] = value.toBridgeValue()
  }
  return dictionary
}

private fun Any?.toBridgeValue(): Any? {
  return when (this) {
    null,
    is String,
    is Boolean,
    is Int,
    is Long,
    is Float,
    is Double,
    -> this

    is Number -> this.toDouble()
    is Dictionary -> this
    is Map<*, *> -> {
      val dictionary = Dictionary()
      for ((key, value) in this) {
        dictionary[key?.toString() ?: ""] = value.toBridgeValue()
      }
      dictionary
    }

    is Iterable<*> -> this.map { it.toBridgeValue() }
    else -> this.toString()
  }
}
