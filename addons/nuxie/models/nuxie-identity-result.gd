class_name NuxieIdentityResult
extends NuxieResult

var value: NuxieIdentity

func _init(data: NuxieIdentity = null, failure: NuxieError = null) -> void:
	super(failure)
	value = data
