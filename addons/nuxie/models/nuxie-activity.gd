class_name NuxieActivity
extends RefCounted

var id: String
var name: String
var timestamp_ms: int
var received_at_ms: int
var properties: Dictionary

func _init(data: Dictionary = {}) -> void:
	var copy := data.duplicate(true)
	id = copy.get("id", "")
	name = copy.get("name", "")
	timestamp_ms = copy.get("timestampMs", 0)
	received_at_ms = copy.get("receivedAtMs", 0)
	properties = copy.get("properties", {})
