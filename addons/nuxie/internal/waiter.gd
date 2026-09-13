extends RefCounted

signal completed(value: Dictionary)
var done: bool = false
var result: Dictionary
var deadline: int
var method: String

func finish(value: Dictionary) -> void:
	if done:
		return
	done = true
	result = value
	completed.emit(value)

func wait() -> Dictionary:
	if done:
		return result
	return await completed
