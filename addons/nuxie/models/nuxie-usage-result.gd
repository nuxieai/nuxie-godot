class_name NuxieUsageResult
extends NuxieResult

var value: NuxieUsageReceipt

func _init(data: NuxieUsageReceipt = null, failure: NuxieError = null) -> void:
	super(failure)
	value = data
