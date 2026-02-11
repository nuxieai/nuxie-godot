class_name NuxieTriggerOperation
extends RefCounted

signal update_received(update: Dictionary, is_terminal: bool, timestamp_ms: int)
signal completed(terminal_update: Dictionary)

var request_id: String
var _terminal_update: Dictionary = {}
var _is_terminal := false

func _init(id: String) -> void:
  request_id = id

func _handle_update(update: Dictionary, is_terminal: bool, timestamp_ms: int) -> void:
  update_received.emit(update, is_terminal, timestamp_ms)
  if is_terminal and not _is_terminal:
    _is_terminal = true
    _terminal_update = update
    completed.emit(update)

func emit_native_error(error: Dictionary) -> void:
  var update := {
    "kind": "error",
    "error": NuxieErrors.normalize(error),
  }
  _handle_update(update, true, Time.get_ticks_msec())

func cancel() -> void:
  Nuxie.cancel_trigger(request_id)

func wait_done() -> Dictionary:
  if _is_terminal:
    return _terminal_update
  return await completed

func is_terminal() -> bool:
  return _is_terminal

func terminal_update() -> Dictionary:
  return _terminal_update
