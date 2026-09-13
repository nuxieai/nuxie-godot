class_name NuxieExperienceContext
extends RefCounted

var experience_id: String
var experience_version: Variant
var journey_id: Variant

func _init(data: Dictionary = {}) -> void:
	var copy := data.duplicate(true)
	experience_id = copy.get("experienceId", "")
	experience_version = copy.get("experienceVersion", null)
	journey_id = copy.get("journeyId", null)
