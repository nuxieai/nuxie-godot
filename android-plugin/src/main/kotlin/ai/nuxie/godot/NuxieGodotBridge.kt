package ai.nuxie.godot

import ai.nuxie.sdk.*
import ai.nuxie.sdk.billing.PurchaseHandlingMode
import ai.nuxie.sdk.billing.RestoreResult
import ai.nuxie.sdk.features.FeatureAccess
import ai.nuxie.sdk.features.FeatureCheckPolicy
import ai.nuxie.sdk.features.FeatureInfo
import kotlinx.coroutines.*
import org.json.JSONArray
import org.json.JSONObject
import java.lang.ref.WeakReference

class NuxieGodotBridge(activity: android.app.Activity, private val callback: Callback) {
  interface Callback { fun onMessage(message: String) }
  private val activityReference = WeakReference(activity)
  private val context = activity.applicationContext
  companion object {
    const val NAME = "Nuxie"
    private var owner = WeakReference<NuxieGodotBridge>(null)
    private var configurationKey: String? = null
    private val lifecycleScope = CoroutineScope(SupervisorJob() + Dispatchers.Main.immediate)
    private var shutdownOperation: Deferred<Unit>? = null
  }
  private val scope = CoroutineScope(SupervisorJob() + Dispatchers.Main.immediate)
  private var session: String? = null
  private var snapshotJob: Job? = null
  private val purchases = NuxiePurchaseDelegateBridge(emitEvent = { name, value -> scope.launch { send(name, value) } })
  private val listener = object : NuxieListener {
    override fun onActivityEmitted(sdk: Nuxie, info: NuxieActivityInfo) {
      scope.launch { send("activity", mapOf("schemaVersion" to NuxieActivityInfo.SCHEMA_VERSION,
        "id" to info.id, "timestampMs" to info.timestampMillis, "receivedAtMs" to info.receivedAtMillis,
        "name" to info.name, "properties" to info.properties.mapValues { (_, v) -> when(v) {
          is NuxieActivityValue.String -> v.value; is NuxieActivityValue.Int -> v.value
          is NuxieActivityValue.Double -> v.value; is NuxieActivityValue.Bool -> v.value
        } })) }
    }
    override fun onAppActionRequested(sdk: Nuxie, action: AppAction) {
      scope.launch { send("appAction", mapOf("name" to action.name,
        "payload" to action.payload?.mapValues { (_, v) -> when(v) {
          is AppActionValue.String -> v.value; is AppActionValue.Int -> v.value
          is AppActionValue.Double -> v.value; is AppActionValue.Bool -> v.value
        } }, "experience" to mapOf("experienceId" to action.experience.experienceId,
          "experienceVersion" to action.experience.experienceVersion, "journeyId" to action.experience.journeyId))) }
    }
  }
  fun invalidate() {
    scope.launch {
      snapshotJob?.cancel(); purchases.cancelPending("runtime_invalidated")
      session = null
      if (owner.get() === this@NuxieGodotBridge) { owner.clear(); if (Nuxie.listener === listener) Nuxie.listener = null }
      scope.cancel()
    }
  }
  private class Promise(private val id: String, private val callback: Callback) {
    fun resolve(value: Any?) { callback.onMessage(JSONObject(mapOf("requestId" to id, "result" to (value ?: JSONObject.NULL))).toString()) }
    fun reject(code: String, message: String?, error: Exception) { callback.onMessage(JSONObject(mapOf("requestId" to id, "error" to mapOf("code" to code, "message" to (message ?: "Native operation failed")))).toString()) }
  }
  fun dispatch(json: String) {
    val request = JSONObject(json)
    val promise = Promise(request.getString("requestId"), callback)
    try {
      val a = request.getJSONObject("arguments")
      val s = a.optString("session")
      when(request.getString("method")) {
        "configure" -> configure(a.getString("configuration"), promise)
        "shutdown" -> shutdown(s, promise)
        "identify" -> identify(s, a.getString("customerId"), a.getString("properties"), promise)
        "reset" -> reset(s, false, promise)
        "getIdentity" -> getIdentity(s, promise)
        "setLocaleIdentifier" -> setLocaleIdentifier(s, a.nullableString("locale"), promise)
        "trigger" -> trigger(s, a.getString("event"), a.getString("properties"), promise)
        "dismiss" -> dismiss(s, promise)
        "hasFeature" -> hasFeature(s, a.getString("featureId"), a.getString("options"), promise)
        "consumeFeature" -> consumeFeature(s, a.getString("featureId"), a.getString("options"), promise)
        "completePurchase" -> completePurchase(s, a.getString("requestId"), a.getString("result"), promise)
        "completeRestore" -> completeRestore(s, a.getString("requestId"), a.getString("result"), promise)
        else -> throw BridgeFailure("invalidMethod", "Unknown bridge method")
      }
    } catch (e: Exception) { promise.reject("invalidArgument", e.message, e) }
  }
  private fun send(name: String, payload: Map<String, Any?>) {
    val attached = session ?: return
    callback.onMessage(JSONObject(mapOf("session" to attached, "name" to name, "payload" to payload)).toString())
  }
  private fun run(promise: Promise, attached: String? = null, block: suspend () -> Any?) {
    scope.launch {
      try {
        if (attached != null && (attached != session || owner.get() !== this@NuxieGodotBridge)) throw BridgeFailure("sessionExpired", "Configure Nuxie in this runtime first")
        promise.resolve(block())
      } catch (error: Exception) { promise.reject((error as? BridgeFailure)?.code ?: "nativeError", error.message, error) }
    }
  }
  private fun configure(configuration: String, promise: Promise) = run(promise) {
    if (shutdownOperation != null) throw BridgeFailure("lifecycleBusy", "Await native shutdown before configuring")
    if (!android.os.Process.is64Bit()) throw BridgeFailure("unsupportedArchitecture", "Nuxie requires a 64-bit Android process")
    val input = JSONObject(configuration)
    if (input.getInt("contract") != 1) throw BridgeFailure("incompatibleBridge", "Rebuild the app with the matching native SDK")
    val attached = input.getString("session")
    val apiKey = input.getString("apiKey")
    require(apiKey.isNotBlank() && attached.isNotBlank())
    input.remove("session")
    val key = JSONObject(input.toMap().toSortedMap()).toString()
    if (owner.get() != null && owner.get() !== this) throw BridgeFailure("engineAlreadyAttached", "Another runtime owns Nuxie")
    if (!Nuxie.isSetup) configurationKey = null
    if (configurationKey != null && configurationKey != key) throw BridgeFailure("alreadyConfigured", "Shutdown before changing configuration")
    if (Nuxie.isSetup && configurationKey == null) throw BridgeFailure("alreadyConfigured", "Nuxie was configured outside Godot")
    owner = WeakReference(this); session = attached
    purchases.cancelPending("session_replaced"); snapshotJob?.cancel()
    try {
      val activity = activityReference.get()?.takeUnless { it.isDestroyed }
        ?: throw BridgeFailure("missingActivity", "The Godot Activity is no longer available")
      val config = NuxieConfiguration(apiKey = apiKey).apply {
        environment = if (input.optString("environment") == "development") NuxieEnvironment.DEVELOPMENT else NuxieEnvironment.PRODUCTION
        logLevel = when(input.optString("logLevel")) {
          "verbose" -> LogLevel.DEBUG; "debug" -> LogLevel.DEBUG; "info" -> LogLevel.INFO
          "error" -> LogLevel.ERROR; "none" -> LogLevel.NONE; else -> LogLevel.WARN
        }
        localeIdentifier = input.nullableString("localeIdentifier")
        purchaseHandlingMode = if (input.optString("purchaseHandlingMode") == "observer") PurchaseHandlingMode.APP_MANAGED else PurchaseHandlingMode.NUXIE_MANAGED
        purchaseDelegate = if (input.optBoolean("externalBilling")) purchases else null
      }
      if ((context.applicationInfo.flags and android.content.pm.ApplicationInfo.FLAG_DEBUGGABLE) != 0) {
        activity.intent?.getStringExtra("NUXIE_GODOT_API_ENDPOINT")?.let {
          config.testingOverrides.apiEndpoint = java.net.URL(it)
        }
      }
      Nuxie.listener = listener
      if (Nuxie.isSetup) Nuxie.setPurchaseDelegate(config.purchaseDelegate)
      else Nuxie.setup(activity, config)
      configurationKey = key
      snapshotJob = scope.launch { Nuxie.features.snapshot.collect { send("features", it.toWire()) } }
      JSONObject(mapOf("session" to attached, "contract" to 1, "nativeVersion" to Nuxie.version,
        "snapshot" to Nuxie.features.snapshot.value.toWire())).toString()
    } catch (error: Exception) {
      if (!Nuxie.isSetup) { owner.clear(); session = null; if (Nuxie.listener === listener) Nuxie.listener = null }
      throw error
    }
  }
  private fun shutdown(session: String, promise: Promise) = run(promise) {
    require(session.isNotBlank())
    shutdownOperation?.let { it.await(); return@run null }
    if (owner.get() == null && configurationKey == null && !Nuxie.isSetup) {
      this.session = null
      return@run null
    }
    // A replacement engine can tear down Godot's retained, unowned setup.
    if (owner.get() == null && configurationKey != null) {
      owner = WeakReference(this)
      this.session = session
    }
    if (owner.get() !== this || this.session != session) throw BridgeFailure("sessionExpired", "This runtime does not own the native setup")
    snapshotJob?.cancel(); purchases.cancelPending("shutdown")
    // Native teardown outlives cancellation of the destroyed runtime's scope.
    val operation = lifecycleScope.async(start = CoroutineStart.LAZY) {
      try {
        withContext(Dispatchers.Default) { Nuxie.shutdown() }
        if (Nuxie.listener === listener) Nuxie.listener = null
        this@NuxieGodotBridge.session = null; owner.clear(); configurationKey = null
      } finally {
        shutdownOperation = null
      }
    }
    shutdownOperation = operation
    operation.await()
    null
  }
  private fun identify(session: String, customerId: String, properties: String, promise: Promise) = run(promise, session) {
    val options = JSONObject(properties)
    Nuxie.identify(customerId, options.optJSONObject("properties")?.toMap(), options.optJSONObject("propertiesSetOnce")?.toMap()); JSONObject(Nuxie.features.snapshot.value.toWire()).toString()
  }
  private fun reset(session: String, keepAnonymousId: Boolean, promise: Promise) = run(promise, session) { Nuxie.reset(false); JSONObject(Nuxie.features.snapshot.value.toWire()).toString() }
  private fun getIdentity(session: String, promise: Promise) = run(promise, session) {
    JSONObject(mapOf("distinctId" to Nuxie.distinctId, "anonymousId" to Nuxie.anonymousId, "isIdentified" to Nuxie.isIdentified)).toString()
  }
  private fun setLocaleIdentifier(session: String, locale: String?, promise: Promise) = run(promise, session) { Nuxie.setLocaleIdentifier(locale); null }
  private fun trigger(session: String, event: String, properties: String, promise: Promise) = run(promise, session) { Nuxie.trigger(event, JSONObject(properties).toMap()); null }
  private fun dismiss(session: String, promise: Promise) = run(promise, session) { Nuxie.dismiss(); null }
  private fun hasFeature(session: String, featureId: String, options: String, promise: Promise) = run(promise, session) {
    val input = JSONObject(options)
    val result = Nuxie.hasFeature(featureId, input.optDouble("requiredBalance", 1.0), input.nullableString("entityId"),
      if (input.optString("policy") == "remote") FeatureCheckPolicy.REMOTE else FeatureCheckPolicy.CACHE_FIRST)
    JSONObject(result.toWire()).toString()
  }
  private fun consumeFeature(session: String, featureId: String, options: String, promise: Promise) = run(promise, session) {
    val input = JSONObject(options)
    val result = Nuxie.consumeFeature(featureId, input.getDouble("quantity"), input.getString("operationId"), input.nullableString("entityId"))
    JSONObject(mapOf("customerId" to result.customerId, "featureId" to result.featureId, "occurredAtMs" to result.occurredAtMs,
      "operationId" to result.operationId, "accepted" to result.accepted, "code" to result.code,
      "quantity" to result.quantity, "balance" to result.balance, "unlimited" to result.unlimited,
      "active" to result.active, "idempotentReplay" to result.idempotentReplay)).toString()
  }
  private fun completePurchase(session: String, requestId: String, result: String, promise: Promise) = run(promise, session) { purchases.completePurchase(requestId, JSONObject(result).toMap()); null }
  private fun completeRestore(session: String, requestId: String, result: String, promise: Promise) = run(promise, session) { purchases.completeRestore(requestId, JSONObject(result).toMap()); null }
}
private class BridgeFailure(val code: String, message: String) : IllegalStateException(message)
private fun FeatureAccess.toWire() = mapOf("allowed" to allowed, "unlimited" to unlimited, "balance" to balance, "type" to when(type) {
  ai.nuxie.sdk.features.FeatureType.BOOLEAN -> "boolean"
  ai.nuxie.sdk.features.FeatureType.METERED -> "metered"
  ai.nuxie.sdk.features.FeatureType.CREDIT_SYSTEM -> "creditSystem"
})
private fun FeatureInfo.Snapshot.toWire(): Map<String, Any?> = mapOf("identityGeneration" to identityGeneration.toString(), "revision" to revision.toString(),
  "state" to when(state) { FeatureInfo.State.Unknown -> "unknown"; FeatureInfo.State.Ready -> "ready"; FeatureInfo.State.Reconciling -> "reconciling" },
  "all" to all.mapValues { it.value.toWire() })
private fun JSONObject.nullableString(key: String): String? = if (isNull(key)) null else getString(key)
private fun JSONObject.toMap(): Map<String, Any?> = keys().asSequence().associateWith { key -> jsonValue(get(key)) }
private fun jsonValue(value: Any?): Any? = when(value) {
  JSONObject.NULL -> null
  is JSONObject -> value.toMap()
  is JSONArray -> (0 until value.length()).map { jsonValue(value.get(it)) }
  else -> value
}
