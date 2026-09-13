class_name NuxieError
extends RefCounted

var code: String
var message: String
var details: Dictionary

func _init(error_code: String = "nativeError", error_message: String = "", error_details: Dictionary = {}) -> void:
	code = error_code
	message = error_message
	details = error_details.duplicate(true)
