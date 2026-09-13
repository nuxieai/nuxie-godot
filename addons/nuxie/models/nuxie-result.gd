class_name NuxieResult
extends RefCounted

var ok: bool
var error: NuxieError

func _init(failure: NuxieError = null) -> void:
	error = failure
	ok = failure == null
