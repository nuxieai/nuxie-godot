class_name NuxieFeatureResult
extends NuxieResult

var value: NuxieFeatureAccess

func _init(data: NuxieFeatureAccess = null, failure: NuxieError = null) -> void:
	super(failure)
	value = data
