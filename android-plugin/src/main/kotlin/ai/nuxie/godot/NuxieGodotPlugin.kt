package ai.nuxie.godot

import ai.nuxie.sdk.AppAction
import ai.nuxie.sdk.AppActionValue
import ai.nuxie.sdk.LogLevel
import ai.nuxie.sdk.Nuxie
import ai.nuxie.sdk.NuxieActivityInfo
import ai.nuxie.sdk.NuxieActivityValue
import ai.nuxie.sdk.NuxieConfiguration
import ai.nuxie.sdk.NuxieEnvironment
import ai.nuxie.sdk.NuxieListener
import ai.nuxie.sdk.billing.NuxiePurchaseDelegate
import ai.nuxie.sdk.billing.PurchaseHandlingMode
import ai.nuxie.sdk.billing.PurchaseResult
import ai.nuxie.sdk.billing.RestoreResult
import ai.nuxie.sdk.billing.StoreProduct
import ai.nuxie.sdk.features.FeatureAccess
import ai.nuxie.sdk.features.FeatureCheckPolicy
import ai.nuxie.sdk.features.FeatureType
import ai.nuxie.sdk.features.FeatureUsageResult
import java.util.UUID
import java.util.concurrent.ConcurrentHashMap
import kotlinx.coroutines.CompletableDeferred
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.cancel
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import kotlinx.coroutines.withTimeoutOrNull
import org.godotengine.godot.Dictionary
import org.godotengine.godot.Godot
import org.godotengine.godot.plugin.GodotPlugin
import org.godotengine.godot.plugin.SignalInfo
import org.godotengine.godot.plugin.UsedByGodot

class NuxieGodotPlugin(godot: Godot) : GodotPlugin(godot) {
  private val scope = CoroutineScope(SupervisorJob() + Dispatchers.Main.immediate)
  private val purchaseDelegate = GodotPurchaseDelegate(::emitPublicEvent)
  private val listener = object : NuxieListener {
    override fun featureAccessDidChange(
      featureId: String,
      oldAccess: FeatureAccess?,
      newAccess: FeatureAccess,
    ) {
      emitPublicEvent(
        "feature_access_changed",
        mapOf(
          "featureId" to featureId,
          "from" to oldAccess?.toMap(),
          "to" to newAccess.toMap(),
          "timestampMs" to System.currentTimeMillis(),
        ),
      )
    }

    override fun onActivityEmitted(sdk: Nuxie, info: NuxieActivityInfo) {
      emitPublicEvent("activity", info.toMap())
    }

    override fun onAppActionRequested(sdk: Nuxie, action: AppAction) {
      emitPublicEvent("app_action", action.toMap())
    }
  }

  override fun getPluginName(): String = BuildConfig.GODOT_PLUGIN_NAME

  override fun getPluginSignals(): MutableSet<SignalInfo> = mutableSetOf(
    SignalInfo(
      "operation_result",
      String::class.java,
      String::class.java,
      Boolean::class.java,
      Dictionary::class.java,
      Dictionary::class.java,
      Long::class.java,
    ),
    SignalInfo("feature_access_changed", Dictionary::class.java),
    SignalInfo("activity", Dictionary::class.java),
    SignalInfo("app_action", Dictionary::class.java),
    SignalInfo("purchase_request", Dictionary::class.java),
    SignalInfo("restore_request", Dictionary::class.java),
  )

  override fun onMainDestroy() {
    purchaseDelegate.cancelPending("plugin_destroyed")
    if (Nuxie.listener === listener) {
      Nuxie.listener = null
    }
    Nuxie.shutdown()
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
    runCatching {
      require(apiKey.isNotBlank()) { "Nuxie API key is required." }
      Nuxie.listener = listener
      Nuxie.setup(
        context.applicationContext,
        buildConfiguration(apiKey, options, usePurchaseController),
      )
      Dictionary().apply {
        put("isConfigured", true)
        put("wrapperVersion", wrapperVersion)
      }
    }.onSuccess { emitOperation("configure", requestId, true, it) }
      .onFailure { error ->
        if (!Nuxie.isSetup && Nuxie.listener === listener) {
          Nuxie.listener = null
        }
        emitOperation("configure", requestId, false, error = error.toBridgeError("CONFIGURE_FAILED"))
      }
  }

  @UsedByGodot
  fun shutdown(requestId: String) {
    runSuspend("shutdown", requestId) {
      purchaseDelegate.cancelPending("sdk_shutdown")
      withContext(Dispatchers.Default) { Nuxie.shutdown() }
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
    runSync("identify", requestId) {
      Nuxie.identify(
        distinctId = distinctId,
        userProperties = userProperties.toStringKeyMap(),
        userPropertiesSetOnce = userPropertiesSetOnce.toStringKeyMap(),
      )
      Dictionary().apply { put("distinctId", Nuxie.distinctId) }
    }
  }

  @UsedByGodot
  fun reset(keepAnonymousId: Boolean, requestId: String) {
    runSync("reset", requestId) {
      Nuxie.reset(keepAnonymousId)
      Dictionary().apply {
        put("distinctId", Nuxie.distinctId)
        put("anonymousId", Nuxie.anonymousId)
        put("isIdentified", Nuxie.isIdentified)
      }
    }
  }

  @UsedByGodot
  fun getDistinctId(requestId: String) {
    emitOperation(
      "getDistinctId",
      requestId,
      true,
      Dictionary().apply { put("distinctId", Nuxie.distinctId) },
    )
  }

  @UsedByGodot
  fun getAnonymousId(requestId: String) {
    emitOperation(
      "getAnonymousId",
      requestId,
      true,
      Dictionary().apply { put("anonymousId", Nuxie.anonymousId) },
    )
  }

  @UsedByGodot
  fun getIsIdentified(requestId: String) {
    emitOperation(
      "getIsIdentified",
      requestId,
      true,
      Dictionary().apply { put("isIdentified", Nuxie.isIdentified) },
    )
  }

  @UsedByGodot
  fun trigger(eventName: String, properties: Dictionary) {
    Nuxie.trigger(eventName, properties.toStringKeyMap())
  }

  @UsedByGodot
  fun dismiss(requestId: String) {
    runSuspend("dismiss", requestId) {
      Nuxie.dismiss()
      Dictionary()
    }
  }

  @UsedByGodot
  fun setLocaleIdentifier(localeIdentifier: String?, requestId: String) {
    runSuspend("setLocaleIdentifier", requestId) {
      Nuxie.setLocaleIdentifier(localeIdentifier)
      Dictionary()
    }
  }

  @UsedByGodot
  fun hasFeature(
    featureId: String,
    requiredBalance: Double,
    entityId: String,
    policy: String,
    requestId: String,
  ) {
    runSuspend("hasFeature", requestId) {
      Nuxie.hasFeature(
        featureId = featureId,
        requiredBalance = requiredBalance,
        entityId = entityId.ifBlank { null },
        policy = if (policy == "remote") {
          FeatureCheckPolicy.REMOTE
        } else {
          FeatureCheckPolicy.CACHE_FIRST
        },
      ).toGodotDictionary()
    }
  }

  @UsedByGodot
  fun useFeature(
    featureId: String,
    amount: Double,
    entityId: String,
    metadata: Dictionary,
  ) {
    Nuxie.useFeature(
      featureId = featureId,
      amount = amount,
      entityId = entityId.ifBlank { null },
      metadata = metadata.toStringKeyMap(),
    )
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
      Nuxie.useFeatureAndWait(
        featureId = featureId,
        amount = amount,
        entityId = entityId.ifBlank { null },
        setUsage = setUsage,
        metadata = metadata.toStringKeyMap(),
      ).toGodotDictionary()
    }
  }

  @UsedByGodot
  fun completePurchase(requestId: String, result: Dictionary) {
    purchaseDelegate.completePurchase(requestId, result.toStringKeyMap())
  }

  @UsedByGodot
  fun completeRestore(requestId: String, result: Dictionary) {
    purchaseDelegate.completeRestore(requestId, result.toStringKeyMap())
  }

  private fun buildConfiguration(
    apiKey: String,
    options: Dictionary,
    usePurchaseController: Boolean,
  ): NuxieConfiguration = NuxieConfiguration(apiKey).apply {
    environment = if (options["environment"] == "development") {
      NuxieEnvironment.DEVELOPMENT
    } else {
      NuxieEnvironment.PRODUCTION
    }
    logLevel = when (options["log_level"] as? String) {
      "debug", "verbose" -> LogLevel.DEBUG
      "info" -> LogLevel.INFO
      "error" -> LogLevel.ERROR
      "none" -> LogLevel.NONE
      else -> LogLevel.WARN
    }
    if (options.containsKey("locale_identifier")) {
      localeIdentifier = options["locale_identifier"] as? String
    }
    purchaseHandlingMode = if (options["purchase_handling_mode"] == "observer") {
      PurchaseHandlingMode.APP_MANAGED
    } else {
      PurchaseHandlingMode.NUXIE_MANAGED
    }
    if (usePurchaseController) {
      purchaseDelegate = this@NuxieGodotPlugin.purchaseDelegate
    }
  }

  private fun runSync(method: String, requestId: String, block: () -> Dictionary) {
    runCatching(block)
      .onSuccess { emitOperation(method, requestId, true, it) }
      .onFailure { emitOperation(method, requestId, false, error = it.toBridgeError()) }
  }

  private fun runSuspend(method: String, requestId: String, block: suspend () -> Dictionary) {
    scope.launch {
      runCatching { block() }
        .onSuccess { emitOperation(method, requestId, true, it) }
        .onFailure { emitOperation(method, requestId, false, error = it.toBridgeError()) }
    }
  }

  private fun emitOperation(
    method: String,
    requestId: String,
    ok: Boolean,
    result: Dictionary = Dictionary(),
    error: Dictionary = Dictionary(),
  ) {
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

  private fun emitPublicEvent(eventName: String, payload: Map<String, Any?>) {
    val dictionary = payload.toGodotDictionary()
    runOnHostThread { emitSignal(eventName, dictionary) }
  }
}

internal class GodotPurchaseDelegate(
  private val emit: (String, Map<String, Any?>) -> Unit,
  private val timeoutMs: Long = 60_000,
) : NuxiePurchaseDelegate {
  private val purchases = ConcurrentHashMap<String, CompletableDeferred<PurchaseResult>>()
  private val restores = ConcurrentHashMap<String, CompletableDeferred<RestoreResult>>()

  override suspend fun purchase(product: StoreProduct): PurchaseResult {
    val requestId = UUID.randomUUID().toString()
    val deferred = CompletableDeferred<PurchaseResult>()
    purchases[requestId] = deferred

    emit(
      "purchase_request",
      mapOf(
        "request_id" to requestId,
        "platform" to "android",
        "product_id" to product.productId,
        "store_product_id" to product.storeProductId,
        "base_plan_id" to product.basePlanId,
        "purchase_option_id" to product.purchaseOptionId,
        "offer_id" to product.offerId,
        "placement_id" to product.placementId,
        "display_name" to product.rawProduct?.name,
        "display_price" to null,
        "timestamp_ms" to System.currentTimeMillis(),
      ),
    )

    return try {
      withTimeoutOrNull(timeoutMs) { deferred.await() }
        ?: PurchaseResult.Failed(bridgeError("purchase_timeout"))
    } finally {
      purchases.remove(requestId)
    }
  }

  override suspend fun restorePurchases(): RestoreResult {
    val requestId = UUID.randomUUID().toString()
    val deferred = CompletableDeferred<RestoreResult>()
    restores[requestId] = deferred
    emit(
      "restore_request",
      mapOf(
        "request_id" to requestId,
        "platform" to "android",
        "timestamp_ms" to System.currentTimeMillis(),
      ),
    )

    return try {
      withTimeoutOrNull(timeoutMs) { deferred.await() }
        ?: RestoreResult.Failed(bridgeError("restore_timeout"))
    } finally {
      restores.remove(requestId)
    }
  }

  fun completePurchase(requestId: String, payload: Map<String, Any?>) {
    purchases.remove(requestId)?.complete(
      when ((payload["type"] as? String)?.lowercase()) {
        "purchased" -> PurchaseResult.Purchased
        "cancelled" -> PurchaseResult.Cancelled
        "pending" -> PurchaseResult.Pending
        else -> PurchaseResult.Failed(
          bridgeError((payload["message"] as? String) ?: "purchase_failed"),
        )
      },
    )
  }

  fun completeRestore(requestId: String, payload: Map<String, Any?>) {
    restores.remove(requestId)?.complete(
      when ((payload["type"] as? String)?.lowercase()) {
        "restored" -> RestoreResult.Restored
        "no_purchases" -> RestoreResult.NoPurchases
        else -> RestoreResult.Failed(
          bridgeError((payload["message"] as? String) ?: "restore_failed"),
        )
      },
    )
  }

  fun cancelPending(reason: String) {
    purchases.values.forEach { it.complete(PurchaseResult.Failed(bridgeError(reason))) }
    restores.values.forEach { it.complete(RestoreResult.Failed(bridgeError(reason))) }
    purchases.clear()
    restores.clear()
  }

  private fun bridgeError(message: String): Throwable = IllegalStateException(message)
}

internal fun FeatureAccess.toMap(): Map<String, Any?> = mapOf(
  "allowed" to allowed,
  "unlimited" to unlimited,
  "balance" to balance,
  "type" to when (type) {
    FeatureType.BOOLEAN -> "boolean"
    FeatureType.METERED -> "metered"
    FeatureType.CREDIT_SYSTEM -> "creditSystem"
  },
)

internal fun FeatureUsageResult.toMap(): Map<String, Any?> = mapOf(
  "success" to success,
  "featureId" to featureId,
  "amountUsed" to amountUsed,
  "message" to message,
  "usage" to usage?.let {
    mapOf(
      "current" to it.current,
      "limit" to it.limit,
      "remaining" to it.remaining,
    )
  },
  "authoritativeAccess" to authoritativeAccess?.toMap(),
)

private fun NuxieActivityInfo.toMap(): Map<String, Any?> = mapOf(
  "schemaVersion" to NuxieActivityInfo.SCHEMA_VERSION,
  "id" to id,
  "timestampMs" to timestampMillis,
  "receivedAtMs" to receivedAtMillis,
  "name" to name,
  "properties" to properties.mapValues { (_, value) -> value.toBridgeValue() },
)

private fun NuxieActivityValue.toBridgeValue(): Any = when (this) {
  is NuxieActivityValue.String -> value
  is NuxieActivityValue.Int -> value
  is NuxieActivityValue.Double -> value
  is NuxieActivityValue.Bool -> value
}

private fun AppAction.toMap(): Map<String, Any?> = mapOf(
  "name" to name,
  "payload" to payload?.mapValues { (_, value) -> value.toBridgeValue() },
  "experience" to mapOf(
    "experienceId" to experience.experienceId,
    "experienceVersion" to experience.experienceVersion,
    "journeyId" to experience.journeyId,
  ),
)

private fun AppActionValue.toBridgeValue(): Any = when (this) {
  is AppActionValue.String -> value
  is AppActionValue.Int -> value
  is AppActionValue.Double -> value
  is AppActionValue.Bool -> value
}

internal fun Map<String, Any?>.toGodotDictionary(): Dictionary = Dictionary().also { output ->
  forEach { (key, value) -> output[key] = value.toGodotValue() }
}

private fun Any?.toGodotValue(): Any? = when (this) {
  is Map<*, *> -> Dictionary().also { output ->
    forEach { (key, value) ->
      if (key is String) {
        output[key] = value.toGodotValue()
      }
    }
  }
  is List<*> -> map { it.toGodotValue() }.toTypedArray()
  is Array<*> -> map { it.toGodotValue() }.toTypedArray()
  else -> this
}

internal fun Dictionary.toStringKeyMap(): Map<String, Any?> = buildMap {
  this@toStringKeyMap.forEach { (key, value) ->
    put(key, value.toKotlinValue())
  }
}

private fun Any?.toKotlinValue(): Any? = when (this) {
  is Dictionary -> toStringKeyMap()
  is Array<*> -> map { it.toKotlinValue() }
  else -> this
}

private fun FeatureAccess.toGodotDictionary(): Dictionary = toMap().toGodotDictionary()

private fun FeatureUsageResult.toGodotDictionary(): Dictionary = toMap().toGodotDictionary()

private fun Throwable.toBridgeError(code: String = "NATIVE_ERROR"): Dictionary =
  Dictionary().apply {
    put("code", code)
    put("message", message ?: toString())
  }
