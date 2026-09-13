class_name NuxieFeatureSnapshot
extends RefCounted

var kind: NuxieFeatureState.Kind
var customer_id: String
var identity_generation: String
var revision: String
var _all: Dictionary

func _init(data: Dictionary = {}, customer: String = "") -> void:
	kind = {"unknown": NuxieFeatureState.Kind.UNKNOWN, "ready": NuxieFeatureState.Kind.READY, "reconciling": NuxieFeatureState.Kind.RECONCILING}.get(data.get("state", "unknown"), NuxieFeatureState.Kind.UNKNOWN)
	customer_id = customer
	identity_generation = data.get("identityGeneration", "0")
	revision = data.get("revision", "0")
	_all = data.get("all", {}).duplicate(true)

func select(feature_id: String) -> NuxieFeatureState:
	var state := NuxieFeatureState.new()
	state.kind = kind
	if _all.has(feature_id):
		state.access = NuxieFeatureAccess.new(_all[feature_id])
	return state

func get_all() -> Dictionary[String, NuxieFeatureAccess]:
	var result: Dictionary[String, NuxieFeatureAccess] = {}
	for key: String in _all:
		result[key] = NuxieFeatureAccess.new(_all[key])
	return result
