extends RefCounted

const MAX_QUANTITY: int = 9007199254740991

static func valid_json(value: Variant, depth: int = 0) -> bool:
	if depth > 32:
		return false
	match typeof(value):
		TYPE_NIL, TYPE_BOOL, TYPE_STRING:
			return true
		TYPE_INT:
			return value >= -MAX_QUANTITY and value <= MAX_QUANTITY
		TYPE_FLOAT:
			return is_finite(value)
		TYPE_ARRAY:
			for item: Variant in value:
				if not valid_json(item, depth + 1):
					return false
			return true
		TYPE_DICTIONARY:
			for key: Variant in value:
				if not key is String or not valid_json(value[key], depth + 1):
					return false
			return true
	return false

static func decimal(value: Variant) -> bool:
	if not value is String or value.is_empty() or value.length() > 20:
		return false
	if value.length() > 1 and value[0] == "0":
		return false
	for code in value.to_utf8_buffer():
		if code < 48 or code > 57:
			return false
	return value.length() < 20 or value <= "18446744073709551615"

static func compare(a: String, b: String) -> int:
	if a.length() != b.length():
		return 1 if a.length() > b.length() else -1
	return 0 if a == b else (1 if a > b else -1)

static func object(value: Variant) -> Dictionary:
	if value is String:
		value = JSON.parse_string(value)
	return value if value is Dictionary else {}

static func access(data: Dictionary) -> bool:
	return data.get("allowed") is bool and data.get("unlimited") is bool and data.get("type") in ["boolean", "metered", "creditSystem"] and (data.get("balance") == null or ((data.balance is float or data.balance is int) and is_finite(data.balance)))

static func snapshot(data: Dictionary) -> bool:
	if not decimal(data.get("identityGeneration")) or not decimal(data.get("revision")) or not data.get("state") in ["unknown", "ready", "reconciling"] or not data.get("all") is Dictionary:
		return false
	for key: Variant in data.all:
		if not key is String or not data.all[key] is Dictionary or not access(data.all[key]):
			return false
	return true

static func identity(data: Dictionary) -> bool:
	return data.get("distinctId") is String and not data.distinctId.is_empty() and data.get("anonymousId") is String and not data.anonymousId.is_empty() and data.get("isIdentified") is bool

static func receipt(data: Dictionary, feature: String, operation: String, quantity: int) -> bool:
	return data.get("featureId") == feature and data.get("operationId") == operation and data.get("quantity") == quantity and data.get("customerId") is String and not data.customerId.is_empty() and data.get("accepted") is bool and data.get("code") is String and data.get("unlimited") is bool and data.get("active") is bool and data.get("idempotentReplay") is bool and (data.get("occurredAtMs") == null or ((data.occurredAtMs is float or data.occurredAtMs is int) and is_finite(data.occurredAtMs))) and (data.get("balance") == null or ((data.balance is float or data.balance is int) and is_finite(data.balance)))
