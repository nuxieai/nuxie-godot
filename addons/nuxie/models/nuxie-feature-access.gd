class_name NuxieFeatureAccess
extends RefCounted

var allowed: bool
var unlimited: bool
var balance: Variant
var type: String

func _init(data: Dictionary = {}) -> void:
	var copy := data.duplicate(true)
	allowed = copy.get("allowed", false)
	unlimited = copy.get("unlimited", false)
	balance = copy.get("balance", null)
	type = copy.get("type", "boolean")
