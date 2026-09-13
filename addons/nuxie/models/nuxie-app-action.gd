class_name NuxieAppAction
extends RefCounted

var name: String
var payload: Dictionary
var experience: NuxieExperienceContext

func _init(data: Dictionary = {}) -> void:
	name = data.get("name", "")
	payload = (data.get("payload") if data.get("payload") is Dictionary else {}).duplicate(true)
	experience = NuxieExperienceContext.new(data.get("experience", {}))
