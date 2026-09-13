class_name NuxieIdentity
extends RefCounted

var distinct_id: String
var anonymous_id: String
var is_identified: bool

func _init(data: Dictionary = {}) -> void:
	var copy := data.duplicate(true)
	distinct_id = copy.get("distinctId", "")
	anonymous_id = copy.get("anonymousId", "")
	is_identified = copy.get("isIdentified", false)
