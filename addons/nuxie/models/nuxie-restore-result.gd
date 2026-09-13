class_name NuxieRestoreResult
extends RefCounted

var _type: String = "failed"
var _message: String = "No checkout result"

static func restored() -> NuxieRestoreResult:
	var result := NuxieRestoreResult.new()
	result._type = "restored"
	result._message = ""
	return result

static func no_purchases() -> NuxieRestoreResult:
	var result := NuxieRestoreResult.new()
	result._type = "noPurchases"
	result._message = ""
	return result

static func failed(message: String) -> NuxieRestoreResult:
	var result := NuxieRestoreResult.new()
	result._type = "failed"
	result._message = message
	return result

func _to_wire() -> Dictionary:
	return {"type": _type, "message": _message}
