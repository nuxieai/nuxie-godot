class_name NuxieStoreProduct
extends RefCounted

var platform: Variant
var product_id: Variant
var store_product_id: Variant
var placement_id: Variant
var display_name: Variant
var display_price: Variant
var description: Variant
var product_type: Variant
var period: Variant
var period_count: Variant
var eligibility_jws: Variant
var billing_plan: Variant
var introductory_terms: Variant
var base_plan_id: Variant
var purchase_option_id: Variant
var offer_id: Variant
var pricing_phases: Variant

func _init(data: Dictionary = {}) -> void:
	var copy := data.duplicate(true)
	platform = copy.get("platform", null)
	product_id = copy.get("productId", null)
	store_product_id = copy.get("storeProductId", null)
	placement_id = copy.get("placementId", null)
	display_name = copy.get("displayName", null)
	display_price = copy.get("displayPrice", null)
	description = copy.get("description", null)
	product_type = copy.get("productType", null)
	period = copy.get("period", null)
	period_count = copy.get("periodCount", null)
	eligibility_jws = copy.get("eligibilityJws", null)
	billing_plan = copy.get("billingPlan", null)
	introductory_terms = copy.get("introductoryTerms", null)
	base_plan_id = copy.get("basePlanId", null)
	purchase_option_id = copy.get("purchaseOptionId", null)
	offer_id = copy.get("offerId", null)
	pricing_phases = copy.get("pricingPhases", null)
