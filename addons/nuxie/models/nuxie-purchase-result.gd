class_name NuxiePurchaseResult
extends RefCounted

var _type: String = "failed"
var _message: String = "No checkout result"

static func purchased() -> NuxiePurchaseResult:
	var result := NuxiePurchaseResult.new()
	result._type = "purchased"
	result._message = ""
	return result

static func cancelled() -> NuxiePurchaseResult:
	var result := NuxiePurchaseResult.new()
	result._type = "cancelled"
	result._message = ""
	return result

static func pending() -> NuxiePurchaseResult:
	var result := NuxiePurchaseResult.new()
	result._type = "pending"
	result._message = ""
	return result

static func failed(message: String) -> NuxiePurchaseResult:
	var result := NuxiePurchaseResult.new()
	result._type = "failed"
	result._message = message
	return result

func _to_wire() -> Dictionary:
	return {"type": _type, "message": _message}
