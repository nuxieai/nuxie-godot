package io.nuxie.godot

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
import io.nuxie.sdk.triggers.TriggerUpdate
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.boolean
import kotlinx.serialization.json.contentOrNull
import kotlinx.serialization.json.jsonArray
import kotlinx.serialization.json.jsonObject
import kotlinx.serialization.json.jsonPrimitive
import org.godotengine.godot.Dictionary
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

class BridgeContractsTest {
  private data class TriggerFixture(
    val name: String,
    val updateKind: String,
    val expectedTerminal: Boolean,
    val decisionKind: String? = null,
    val entitlementKind: String? = null,
  )

  @Test
  fun `terminal rules match wrapper contract fixtures`() {
    val fixtures = loadFixtures()

    fixtures.forEach { fixture ->
      val update = fixture.toTriggerUpdate()
      assertEquals(
        "Fixture '${fixture.name}' had mismatched terminal state",
        fixture.expectedTerminal,
        update.isTerminal(),
      )
    }
  }

  @Test
  fun `purchase dictionary maps success outcome`() {
    val payload = Dictionary().apply {
      put("type", "success")
      put("productId", "pro_monthly")
      put("purchaseToken", "token_1")
      put("orderId", "order_1")
    }

    val outcome = payload.toPurchaseOutcome(defaultProductId = "fallback")
    assertTrue(outcome.result is PurchaseResult.Success)
    assertEquals("pro_monthly", outcome.productId)
    assertEquals("token_1", outcome.purchaseToken)
    assertEquals("order_1", outcome.orderId)
  }

  @Test
  fun `purchase dictionary maps failed outcome`() {
    val payload = Dictionary().apply {
      put("type", "failed")
      put("message", "purchase_failed_test")
    }

    val outcome = payload.toPurchaseOutcome(defaultProductId = "fallback")
    assertTrue(outcome.result is PurchaseResult.Failed)
    assertEquals("fallback", outcome.productId)
  }

  @Test
  fun `restore dictionary maps variants`() {
    val success = Dictionary().apply {
      put("type", "success")
      put("restoredCount", 3)
    }
    val noPurchases = Dictionary().apply {
      put("type", "no_purchases")
    }
    val failed = Dictionary().apply {
      put("type", "failed")
      put("message", "restore_failed_test")
    }

    assertTrue(success.toRestoreResult() is RestoreResult.Success)
    assertTrue(noPurchases.toRestoreResult() is RestoreResult.NoPurchases)
    assertTrue(failed.toRestoreResult() is RestoreResult.Failed)
  }

  private fun loadFixtures(): List<TriggerFixture> {
    val raw = checkNotNull(
      javaClass.classLoader?.getResource("trigger_terminal_cases.json")?.readText(),
    ) {
      "Missing trigger_terminal_cases.json fixture"
    }

    val array = json.parseToJsonElement(raw).jsonArray
    val fixtures = mutableListOf<TriggerFixture>()

    for (entry in array) {
      fixtures += entry.toTriggerFixture()
    }

    return fixtures
  }

  private fun TriggerFixture.toTriggerUpdate(): TriggerUpdate {
    return when (updateKind) {
      "error" -> TriggerUpdate.Error(TriggerError("code", "message"))
      "journey" -> TriggerUpdate.Journey(
        JourneyUpdate(
          journeyId = "journey-1",
          campaignId = "campaign-1",
          flowId = null,
          exitReason = JourneyExitReason.COMPLETED,
          goalMet = true,
          goalMetAtEpochMillis = null,
          durationSeconds = null,
          flowExitReason = null,
        ),
      )

      "decision" -> TriggerUpdate.Decision(
        when (decisionKind) {
          "noMatch", "no_match" -> TriggerDecision.NoMatch
          "allowedImmediate", "allowed_immediate" -> TriggerDecision.AllowedImmediate
          "deniedImmediate", "denied_immediate" -> TriggerDecision.DeniedImmediate
          "journeyStarted", "journey_started" -> TriggerDecision.JourneyStarted(defaultJourneyRef())
          "journeyResumed", "journey_resumed" -> TriggerDecision.JourneyResumed(defaultJourneyRef())
          "flowShown", "flow_shown" -> TriggerDecision.FlowShown(defaultJourneyRef())
          else -> TriggerDecision.Suppressed(SuppressReason.AlreadyActive)
        },
      )

      "entitlement" -> TriggerUpdate.Entitlement(
        when (entitlementKind) {
          "allowed" -> EntitlementUpdate.Allowed(GateSource.CACHE)
          "denied" -> EntitlementUpdate.Denied
          else -> EntitlementUpdate.Pending
        },
      )

      else -> error("Unsupported fixture update kind: $updateKind")
    }
  }

  private fun defaultJourneyRef(): JourneyRef {
    return JourneyRef(
      journeyId = "journey-1",
      campaignId = "campaign-1",
      flowId = "flow-1",
    )
  }

  private fun kotlinx.serialization.json.JsonElement.toTriggerFixture(): TriggerFixture {
    val objectValue = this.jsonObject
    return TriggerFixture(
      name = objectValue.requiredString("name"),
      updateKind = objectValue.requiredString("updateKind"),
      expectedTerminal = objectValue.requiredBoolean("expectedTerminal"),
      decisionKind = objectValue.optionalString("decisionKind"),
      entitlementKind = objectValue.optionalString("entitlementKind"),
    )
  }

  private fun JsonObject.requiredString(key: String): String {
    return this[key]?.jsonPrimitive?.contentOrNull
      ?: error("Missing required string key '$key' in fixture")
  }

  private fun JsonObject.requiredBoolean(key: String): Boolean {
    return this[key]?.jsonPrimitive?.boolean
      ?: error("Missing required boolean key '$key' in fixture")
  }

  private fun JsonObject.optionalString(key: String): String? {
    return this[key]?.jsonPrimitive?.contentOrNull
  }

  private val json = Json {
    ignoreUnknownKeys = true
  }
}
