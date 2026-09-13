class_name NuxieStatus
extends RefCounted

enum Kind { UNCONFIGURED, CONFIGURING, READY, SHUTTING_DOWN, FAILED }
var kind: Kind
var error: NuxieError

func _init(state: Kind = Kind.UNCONFIGURED, failure: NuxieError = null) -> void:
	kind = state
	error = failure
