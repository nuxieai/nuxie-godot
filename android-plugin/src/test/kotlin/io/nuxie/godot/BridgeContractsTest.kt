package io.nuxie.godot

import io.nuxie.sdk.purchases.PurchaseResult
import io.nuxie.sdk.purchases.RestoreResult
import io.nuxie.sdk.triggers.EntitlementUpdate
import io.nuxie.sdk.triggers.GateSource
import io.nuxie.sdk.triggers.JourneyExitReason
import io.nuxie.sdk.triggers.JourneyUpdate
import io.nuxie.sdk.triggers.TriggerDecision
import io.nuxie.sdk.triggers.TriggerError
import io.nuxie.sdk.triggers.TriggerUpdate
import org.godotengine.godot.Dictionary
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class BridgeContractsTest {
  @Test
  fun `terminal rules match wrapper contract fixtures`() {
    assertTrue(TriggerUpdate.Error(TriggerError("code", "message")).isTerminal())

    assertTrue(
      TriggerUpdate.Journey(
        JourneyUpdate(
          journeyId = "j1",
          campaignId = "c1",
          flowId = null,
          exitReason = JourneyExitReason.COMPLETED,
          goalMet = true,
          goalMetAtEpochMillis = null,
          durationSeconds = null,
          flowExitReason = null,
        ),
      ).isTerminal(),
    )

    assertTrue(TriggerUpdate.Decision(TriggerDecision.AllowedImmediate).isTerminal())
    assertFalse(
      TriggerUpdate.Decision(
        TriggerDecision.FlowShown(
          io.nuxie.sdk.triggers.JourneyRef(
            journeyId = "j2",
            campaignId = "c2",
            flowId = "f1",
          ),
        ),
      ).isTerminal(),
    )

    assertFalse(TriggerUpdate.Entitlement(EntitlementUpdate.Pending).isTerminal())
    assertTrue(TriggerUpdate.Entitlement(EntitlementUpdate.Allowed(GateSource.CACHE)).isTerminal())
    assertTrue(TriggerUpdate.Entitlement(EntitlementUpdate.Denied).isTerminal())
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
}
