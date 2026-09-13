class_name NuxieUsageReceipt
extends RefCounted

var customer_id: String
var feature_id: String
var operation_id: String
var occurred_at_ms: Variant
var quantity: int
var accepted: bool
var code: String
var balance: Variant
var unlimited: bool
var active: bool
var idempotent_replay: bool

func _init(data: Dictionary = {}) -> void:
	var copy := data.duplicate(true)
	customer_id = copy.get("customerId", "")
	feature_id = copy.get("featureId", "")
	operation_id = copy.get("operationId", "")
	occurred_at_ms = copy.get("occurredAtMs", null)
	quantity = copy.get("quantity", 0)
	accepted = copy.get("accepted", false)
	code = copy.get("code", "")
	balance = copy.get("balance", null)
	unlimited = copy.get("unlimited", false)
	active = copy.get("active", false)
	idempotent_replay = copy.get("idempotentReplay", false)
