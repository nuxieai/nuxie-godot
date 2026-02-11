package io.nuxie.godot

import android.content.Context
import io.nuxie.sdk.NuxieSDK
import io.nuxie.sdk.config.Environment
import io.nuxie.sdk.config.NuxieConfiguration
import org.godotengine.godot.Godot
import org.godotengine.godot.Dictionary
import org.godotengine.godot.plugin.GodotPlugin
import org.godotengine.godot.plugin.SignalInfo
import org.godotengine.godot.plugin.UsedByGodot

class NuxieGodotPlugin(godot: Godot) : GodotPlugin(godot) {
  private val sdk = NuxieSDK.shared()

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
    )
  }

  @UsedByGodot
  fun configure(apiKey: String, requestId: String, options: Dictionary = Dictionary(), usePurchaseController: Boolean = false) {
    val result = Dictionary()
    val error = Dictionary()

    try {
      val config = makeConfiguration(apiKey, options, usePurchaseController)
      sdk.setup(getAppContext(), config)
      result["isConfigured"] = true
      emitOperation("configure", requestId, true, result, error)
    } catch (t: Throwable) {
      error["code"] = "CONFIGURE_FAILED"
      error["message"] = t.message ?: "configure_failed"
      emitOperation("configure", requestId, false, result, error)
    }
  }

  @UsedByGodot
  fun shutdown(requestId: String) {
    val result = Dictionary()
    val error = Dictionary()

    runOnHostThread {
      runCatching {
        kotlinx.coroutines.runBlocking {
          sdk.shutdown()
        }
      }.onSuccess {
        result["isConfigured"] = false
        emitOperation("shutdown", requestId, true, result, error)
      }.onFailure { t ->
        error["code"] = "SHUTDOWN_FAILED"
        error["message"] = t.message ?: "shutdown_failed"
        emitOperation("shutdown", requestId, false, result, error)
      }
    }
  }

  @UsedByGodot
  fun identify(requestId: String, distinctId: String, userProperties: Dictionary = Dictionary(), userPropertiesSetOnce: Dictionary = Dictionary()) {
    val result = Dictionary()
    val error = Dictionary()

    runCatching {
      sdk.identify(
        distinctId = distinctId,
        userProperties = userProperties.toMap(),
        userPropertiesSetOnce = userPropertiesSetOnce.toMap(),
      )
      result["distinctId"] = sdk.getDistinctId()
    }.onSuccess {
      emitOperation("identify", requestId, true, result, error)
    }.onFailure { t ->
      error["code"] = "IDENTIFY_FAILED"
      error["message"] = t.message ?: "identify_failed"
      emitOperation("identify", requestId, false, result, error)
    }
  }

  @UsedByGodot
  fun reset(requestId: String, keepAnonymousId: Boolean = true) {
    val result = Dictionary()
    val error = Dictionary()

    runCatching {
      sdk.reset(keepAnonymousId)
      result["distinctId"] = sdk.getDistinctId()
      result["anonymousId"] = sdk.getAnonymousId()
    }.onSuccess {
      emitOperation("reset", requestId, true, result, error)
    }.onFailure { t ->
      error["code"] = "RESET_FAILED"
      error["message"] = t.message ?: "reset_failed"
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

  private fun makeConfiguration(apiKey: String, options: Dictionary, _usePurchaseController: Boolean): NuxieConfiguration {
    val config = NuxieConfiguration(apiKey)
    val environment = options["environment"] as? String
    when (environment) {
      "production" -> config.environment = Environment.PRODUCTION
      "staging" -> config.environment = Environment.STAGING
      "development" -> config.environment = Environment.DEVELOPMENT
      "custom" -> config.environment = Environment.CUSTOM
    }

    val endpoint = options["apiEndpoint"] as? String
    if (!endpoint.isNullOrBlank()) {
      config.setApiEndpoint(endpoint)
    }

    return config
  }

  private fun getAppContext(): Context {
    return activity?.applicationContext ?: throw IllegalStateException("No foreground activity")
  }

  private fun emitOperation(
    method: String,
    requestId: String,
    ok: Boolean,
    result: Dictionary,
    error: Dictionary,
  ) {
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

  private fun Dictionary.toMap(): Map<String, Any?> {
    val output = mutableMapOf<String, Any?>()
    for ((key, value) in this) {
      output[key] = value
    }
    return output
  }
}
