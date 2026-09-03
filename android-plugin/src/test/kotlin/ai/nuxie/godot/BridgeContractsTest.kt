package ai.nuxie.godot

import ai.nuxie.sdk.features.FeatureAccess
import ai.nuxie.sdk.features.FeatureType
import ai.nuxie.sdk.features.FeatureUsageResult
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

class BridgeContractsTest {
  @Test
  fun `feature access preserves double balance and canonical type`() {
    val payload = FeatureAccess(
      allowed = true,
      unlimited = false,
      balance = 2.5,
      type = FeatureType.CREDIT_SYSTEM,
    ).toMap()

    assertEquals(true, payload["allowed"])
    assertEquals(false, payload["unlimited"])
    assertEquals(2.5, payload["balance"])
    assertEquals("creditSystem", payload["type"])
  }

  @Test
  fun `usage result includes authoritative access`() {
    val payload = FeatureUsageResult(
      success = true,
      featureId = "credits",
      amountUsed = 1.25,
      message = null,
      usage = FeatureUsageResult.UsageInfo(
        current = 3.75,
        limit = 10.0,
        remaining = 6.25,
      ),
      authoritativeAccess = FeatureAccess(
        allowed = true,
        unlimited = false,
        balance = 6.25,
        type = FeatureType.METERED,
      ),
    ).toMap()

    assertEquals("credits", payload["featureId"])
    assertNull(payload["message"])
    assertEquals(6.25, (payload["authoritativeAccess"] as Map<*, *>)["balance"])
  }

  @Test
  fun `purchase completions use canonical result vocabulary`() {
    val emitted = mutableListOf<Pair<String, Map<String, Any?>>>()
    val delegate = GodotPurchaseDelegate(
      emit = { event, payload -> emitted += event to payload },
    )

    delegate.completePurchase("missing", mapOf("type" to "purchased"))
    delegate.completeRestore("missing", mapOf("type" to "restored"))

    assertTrue(emitted.isEmpty())
  }

  @Test
  fun `nested bridge values remain dictionaries`() {
    val dictionary = mapOf(
      "access" to mapOf("allowed" to true, "balance" to null),
      "items" to listOf("one", 2),
    ).toGodotDictionary()

    val roundTrip = dictionary.toStringKeyMap()
    val access = roundTrip["access"] as Map<*, *>
    assertEquals(true, access["allowed"])
    assertTrue(access.containsKey("balance"))
    assertNull(access["balance"])
    assertFalse(roundTrip["items"] is org.godotengine.godot.Dictionary)
  }
}
