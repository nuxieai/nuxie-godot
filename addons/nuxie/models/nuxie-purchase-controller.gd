class_name NuxiePurchaseController
extends RefCounted

func purchase(_product: NuxieStoreProduct) -> NuxiePurchaseResult:
	return NuxiePurchaseResult.failed("Implement purchase in your controller")

func restore() -> NuxieRestoreResult:
	return NuxieRestoreResult.failed("Implement restore in your controller")
