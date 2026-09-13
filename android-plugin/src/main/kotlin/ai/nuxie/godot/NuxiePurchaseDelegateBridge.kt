package ai.nuxie.godot

import ai.nuxie.sdk.billing.NuxiePurchaseDelegate
import ai.nuxie.sdk.billing.PurchaseResult
import ai.nuxie.sdk.billing.RestoreResult
import ai.nuxie.sdk.billing.StoreProduct
import java.util.UUID
import java.util.concurrent.ConcurrentHashMap
import kotlinx.coroutines.CompletableDeferred
import kotlinx.coroutines.withTimeoutOrNull

class NuxiePurchaseDelegateBridge(
  private val emitEvent: (eventName: String, payload: Map<String, Any?>) -> Unit,
  private val timeoutMs: Long = 60_000,
) : NuxiePurchaseDelegate {
  private val purchaseRequests = ConcurrentHashMap<String, CompletableDeferred<PurchaseResult>>()
  private val restoreRequests = ConcurrentHashMap<String, CompletableDeferred<RestoreResult>>()

  override suspend fun purchase(product: StoreProduct): PurchaseResult {
    val requestId = UUID.randomUUID().toString()
    val deferred = CompletableDeferred<PurchaseResult>()
    purchaseRequests[requestId] = deferred

    emitEvent(
      "purchase",
      mapOf(
        "requestId" to requestId,
        "deadlineMs" to System.currentTimeMillis() + timeoutMs,
        "product" to mapOf(
          "platform" to "android", "productId" to product.productId, "storeProductId" to product.storeProductId,
          "basePlanId" to product.basePlanId, "purchaseOptionId" to product.purchaseOptionId,
          "offerId" to product.offerId, "placementId" to product.placementId,
          "displayName" to product.rawProduct?.name, "description" to product.rawProduct?.description,
          "productType" to product.rawProduct?.productType,
          "displayPrice" to selectedPrice(product),
          "pricingPhases" to product.rawProduct?.subscriptionOfferDetails
            ?.firstOrNull { it.basePlanId == product.basePlanId && it.offerId == product.offerId }
            ?.pricingPhases?.pricingPhaseList?.map { phase -> mapOf(
              "displayPrice" to phase.formattedPrice, "billingPeriod" to phase.billingPeriod,
              "billingCycleCount" to phase.billingCycleCount, "recurrenceMode" to phase.recurrenceMode,
            ) },
        ),
        "timestamp_ms" to System.currentTimeMillis(),
      ),
    )

    return try {
      withTimeoutOrNull(timeoutMs) { deferred.await() }
        ?: PurchaseResult.Failed(bridgeError("purchase_timeout"))
    } finally {
      purchaseRequests.remove(requestId)
    }
  }

  override suspend fun restorePurchases(): RestoreResult {
    val requestId = UUID.randomUUID().toString()
    val deferred = CompletableDeferred<RestoreResult>()
    restoreRequests[requestId] = deferred

    emitEvent(
      "restore",
      mapOf(
        "requestId" to requestId,
        "deadlineMs" to System.currentTimeMillis() + timeoutMs,
        "platform" to "android",
        "timestamp_ms" to System.currentTimeMillis(),
      ),
    )

    return try {
      withTimeoutOrNull(timeoutMs) { deferred.await() }
        ?: RestoreResult.Failed(bridgeError("restore_timeout"))
    } finally {
      restoreRequests.remove(requestId)
    }
  }

  fun completePurchase(requestId: String, payload: Map<String, Any?>) {
    purchaseRequests.remove(requestId)?.complete(purchaseResult(payload))
  }

  fun completeRestore(requestId: String, payload: Map<String, Any?>) {
    restoreRequests.remove(requestId)?.complete(restoreResult(payload))
  }

  fun cancelPending(reason: String) {
    purchaseRequests.values.forEach { request ->
      request.complete(PurchaseResult.Failed(bridgeError(reason)))
    }
    restoreRequests.values.forEach { request ->
      request.complete(RestoreResult.Failed(bridgeError(reason)))
    }
    purchaseRequests.clear()
    restoreRequests.clear()
  }

  private fun purchaseResult(payload: Map<String, Any?>): PurchaseResult =
    when ((payload["type"] as? String)) {
      "purchased" -> PurchaseResult.Purchased
      "cancelled" -> PurchaseResult.Cancelled
      "pending" -> PurchaseResult.Pending
      else -> PurchaseResult.Failed(
        bridgeError((payload["message"] as? String) ?: "purchase_failed"),
      )
    }

  private fun restoreResult(payload: Map<String, Any?>): RestoreResult =
    when ((payload["type"] as? String)) {
      "restored" -> RestoreResult.Restored
      "noPurchases" -> RestoreResult.NoPurchases
      else -> RestoreResult.Failed(
        bridgeError((payload["message"] as? String) ?: "restore_failed"),
      )
    }

  private fun selectedPrice(product: StoreProduct): String? {
    val details = product.rawProduct ?: return null
    return if (details.productType == "subs") details.subscriptionOfferDetails
      ?.firstOrNull { it.basePlanId == product.basePlanId && it.offerId == product.offerId }
      ?.pricingPhases?.pricingPhaseList?.lastOrNull()?.formattedPrice
    else details.oneTimePurchaseOfferDetailsList
      ?.firstOrNull { it.purchaseOptionId == product.purchaseOptionId && it.offerId == product.offerId }
      ?.formattedPrice
  }

  private fun bridgeError(message: String): Throwable = IllegalStateException(message)
}
