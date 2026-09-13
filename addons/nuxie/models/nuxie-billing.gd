class_name NuxieBilling
extends RefCounted

var controller: NuxiePurchaseController

static func external(purchase_controller: NuxiePurchaseController) -> NuxieBilling:
	var billing := NuxieBilling.new()
	billing.controller = purchase_controller
	return billing
