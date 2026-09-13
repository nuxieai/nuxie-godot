package ai.nuxie.godot

import ai.nuxie.sdk.billing.RestoreResult
import kotlinx.coroutines.runBlocking
import org.junit.Assert.*
import org.junit.Test

class BridgeContractsTest {
  @Test fun missingControllerReplyTimesOut() = runBlocking {
    val bridge = NuxiePurchaseDelegateBridge({ _, _ -> }, timeoutMs = 10)
    assertTrue(bridge.restorePurchases() is RestoreResult.Failed)
  }

  @Test fun completionUsesMatchingIdAndSettlesOnlyOnce() = runBlocking {
    lateinit var bridge: NuxiePurchaseDelegateBridge
    bridge = NuxiePurchaseDelegateBridge({ name, payload ->
      assertEquals("restore", name)
      val id = payload["requestId"] as String
      bridge.completeRestore("wrong-id", mapOf("type" to "failed"))
      bridge.completeRestore(id, mapOf("type" to "restored"))
      bridge.completeRestore(id, mapOf("type" to "failed"))
    })
    assertEquals(RestoreResult.Restored, bridge.restorePurchases())
  }

  @Test fun shutdownSettlesOutstandingControllerRequests() = runBlocking {
    lateinit var bridge: NuxiePurchaseDelegateBridge
    bridge = NuxiePurchaseDelegateBridge({ _, _ -> bridge.cancelPending("shutdown") })
    assertTrue(bridge.restorePurchases() is RestoreResult.Failed)
  }
}
