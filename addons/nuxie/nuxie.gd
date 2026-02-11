class_name Nuxie
extends Object

const _PLUGIN_NAME := "NuxieGodot"
const _WRAPPER_VERSION := "0.1.0"

static var _bridge: Object = null
static var _connected := false

static var _pending_operations := {}
static var _trigger_operations := {}

static var _listeners := {
  "operation_result": [],
  "trigger_update": [],
  "feature_access_changed": [],
  "purchase_request": [],
  "restore_request": [],
  "flow_lifecycle": [],
}

static var _purchase_controller := {
  "on_purchase": Callable(),
  "on_restore": Callable(),
}

class _OperationWaiter:
  extends RefCounted

  signal resolved(payload: Dictionary)

  var _done := false
  var _payload: Dictionary = {
    "ok": false,
    "result": {},
    "error": {},
  }

  func finish(ok: bool, result: Dictionary, error: Dictionary) -> void:
    if _done:
      return
    _done = true
    _payload = {
      "ok": ok,
      "result": result,
      "error": error,
    }
    resolved.emit(_payload)

  func wait() -> Dictionary:
    if _done:
      return _payload
    return await resolved

static func is_available() -> bool:
  return Engine.has_singleton(_PLUGIN_NAME)

static func set_purchase_controller(on_purchase: Callable = Callable(), on_restore: Callable = Callable()) -> void:
  _purchase_controller["on_purchase"] = on_purchase
  _purchase_controller["on_restore"] = on_restore

static func on(event_name: String, callback: Callable) -> void:
  if not _listeners.has(event_name):
    _listeners[event_name] = []
  (_listeners[event_name] as Array).append(callback)

static func off(event_name: String, callback: Callable) -> void:
  if not _listeners.has(event_name):
    return
  (_listeners[event_name] as Array).erase(callback)

static func configure(api_key: String, options: Dictionary = {}, use_purchase_controller: bool = false) -> Dictionary:
  var request_id := _new_request_id("configure")
  var effective_purchase_bridge := use_purchase_controller or _has_purchase_handlers()
  return await _invoke_async(
    "configure",
    [api_key, options, effective_purchase_bridge, _WRAPPER_VERSION, request_id],
    request_id,
  )

static func shutdown() -> Dictionary:
  var request_id := _new_request_id("shutdown")
  var payload := await _invoke_async("shutdown", [request_id], request_id)
  _pending_operations.clear()
  _trigger_operations.clear()
  return payload

static func identify(distinct_id: String, user_properties: Dictionary = {}, user_properties_set_once: Dictionary = {}) -> Dictionary:
  var request_id := _new_request_id("identify")
  return await _invoke_async(
    "identify",
    [distinct_id, user_properties, user_properties_set_once, request_id],
    request_id,
  )

static func reset(keep_anonymous_id := true) -> Dictionary:
  var request_id := _new_request_id("reset")
  return await _invoke_async("reset", [keep_anonymous_id, request_id], request_id)

static func get_distinct_id() -> String:
  var request_id := _new_request_id("getDistinctId")
  var payload := await _invoke_async("getDistinctId", [request_id], request_id)
  if not payload.ok:
    NuxieErrors.emit("get_distinct_id", payload.error)
    return ""
  return str((payload.result as Dictionary).get("distinctId", ""))

static func get_anonymous_id() -> String:
  var request_id := _new_request_id("getAnonymousId")
  var payload := await _invoke_async("getAnonymousId", [request_id], request_id)
  if not payload.ok:
    NuxieErrors.emit("get_anonymous_id", payload.error)
    return ""
  return str((payload.result as Dictionary).get("anonymousId", ""))

static func get_is_identified() -> bool:
  var request_id := _new_request_id("getIsIdentified")
  var payload := await _invoke_async("getIsIdentified", [request_id], request_id)
  if not payload.ok:
    NuxieErrors.emit("get_is_identified", payload.error)
    return false
  return bool((payload.result as Dictionary).get("isIdentified", false))

static func trigger(event_name: String, options: Dictionary = {}) -> NuxieTriggerOperation:
  var request_id := _new_request_id("trigger")
  var operation := NuxieTriggerOperation.new(request_id)
  _trigger_operations[request_id] = operation

  var bridge := _ensure_bridge()
  if bridge == null:
    operation.emit_native_error(NuxieErrors.build("NATIVE_SDK_UNAVAILABLE", "Nuxie bridge is unavailable"))
    return operation

  var properties: Dictionary = options.get("properties", {})
  var user_properties: Dictionary = options.get("userProperties", {})
  var user_properties_set_once: Dictionary = options.get("userPropertiesSetOnce", {})

  bridge.callv(
    "startTrigger",
    [request_id, event_name, properties, user_properties, user_properties_set_once],
  )

  return operation

static func trigger_once(event_name: String, options: Dictionary = {}, timeout_ms: int = 0) -> Dictionary:
  var operation := trigger(event_name, options)
  if timeout_ms <= 0:
    return await operation.wait_done()

  var start_ms := Time.get_ticks_msec()
  while Time.get_ticks_msec() - start_ms < timeout_ms:
    if operation.is_terminal():
      return operation.terminal_update()

    var main_loop := Engine.get_main_loop()
    if main_loop is SceneTree:
      await (main_loop as SceneTree).process_frame
    else:
      await operation.completed

  return {
    "kind": "error",
    "error": NuxieErrors.build("TRIGGER_TIMEOUT", "Timed out waiting for trigger terminal update"),
  }

static func cancel_trigger(request_id: String) -> void:
  var bridge := _ensure_bridge()
  if bridge == null:
    return

  bridge.callv("cancelTrigger", [request_id])

static func show_flow(flow_id: String) -> Dictionary:
  var request_id := _new_request_id("showFlow")
  return await _invoke_async("showFlow", [flow_id, request_id], request_id)

static func refresh_profile() -> Dictionary:
  var request_id := _new_request_id("refreshProfile")
  return await _invoke_async("refreshProfile", [request_id], request_id)

static func has_feature(feature_id: String, required_balance: int = -1, entity_id: String = "") -> Dictionary:
  var request_id := _new_request_id("hasFeature")
  return await _invoke_async("hasFeature", [feature_id, required_balance, entity_id, request_id], request_id)

static func get_cached_feature(feature_id: String, entity_id: String = "") -> Dictionary:
  var request_id := _new_request_id("getCachedFeature")
  return await _invoke_async("getCachedFeature", [feature_id, entity_id, request_id], request_id)

static func check_feature(feature_id: String, required_balance: int = -1, entity_id: String = "") -> Dictionary:
  var request_id := _new_request_id("checkFeature")
  return await _invoke_async("checkFeature", [feature_id, required_balance, entity_id, request_id], request_id)

static func refresh_feature(feature_id: String, required_balance: int = -1, entity_id: String = "") -> Dictionary:
  var request_id := _new_request_id("refreshFeature")
  return await _invoke_async("refreshFeature", [feature_id, required_balance, entity_id, request_id], request_id)

static func use_feature(feature_id: String, amount: float = 1.0, entity_id: String = "", metadata: Dictionary = {}) -> Dictionary:
  var request_id := _new_request_id("useFeature")
  return await _invoke_async("useFeature", [feature_id, amount, entity_id, metadata, request_id], request_id)

static func use_feature_and_wait(
  feature_id: String,
  amount: float = 1.0,
  entity_id: String = "",
  set_usage: bool = false,
  metadata: Dictionary = {},
) -> Dictionary:
  var request_id := _new_request_id("useFeatureAndWait")
  return await _invoke_async(
    "useFeatureAndWait",
    [feature_id, amount, entity_id, set_usage, metadata, request_id],
    request_id,
  )

static func flush_events() -> Dictionary:
  var request_id := _new_request_id("flushEvents")
  return await _invoke_async("flushEvents", [request_id], request_id)

static func get_queued_event_count() -> Dictionary:
  var request_id := _new_request_id("getQueuedEventCount")
  return await _invoke_async("getQueuedEventCount", [request_id], request_id)

static func pause_event_queue() -> Dictionary:
  var request_id := _new_request_id("pauseEventQueue")
  return await _invoke_async("pauseEventQueue", [request_id], request_id)

static func resume_event_queue() -> Dictionary:
  var request_id := _new_request_id("resumeEventQueue")
  return await _invoke_async("resumeEventQueue", [request_id], request_id)

static func complete_purchase(request_id: String, result: Dictionary) -> Dictionary:
  var op_id := _new_request_id("completePurchase")
  return await _invoke_async("completePurchase", [request_id, result], op_id)

static func complete_restore(request_id: String, result: Dictionary) -> Dictionary:
  var op_id := _new_request_id("completeRestore")
  return await _invoke_async("completeRestore", [request_id, result], op_id)

static func _invoke_async(method: String, args: Array, request_id: String) -> Dictionary:
  _ensure_connected()

  var bridge := _ensure_bridge()
  if bridge == null:
    return {
      "ok": false,
      "result": {},
      "error": NuxieErrors.build("NATIVE_SDK_UNAVAILABLE", "Nuxie bridge is unavailable"),
    }

  var waiter := _OperationWaiter.new()
  _pending_operations[request_id] = waiter
  bridge.callv(method, args)
  var payload := await waiter.wait()
  _pending_operations.erase(request_id)
  return payload

static func _ensure_bridge() -> Object:
  if _bridge != null:
    return _bridge

  if Engine.has_singleton(_PLUGIN_NAME):
    _bridge = Engine.get_singleton(_PLUGIN_NAME)
  return _bridge

static func _ensure_connected() -> void:
  if _connected:
    return

  var bridge := _ensure_bridge()
  if bridge == null:
    return

  bridge.connect("operation_result", Callable(Nuxie, "_on_operation_result"))
  bridge.connect("trigger_update", Callable(Nuxie, "_on_trigger_update"))
  bridge.connect("feature_access_changed", Callable(Nuxie, "_on_feature_access_changed"))
  bridge.connect("purchase_request", Callable(Nuxie, "_on_purchase_request"))
  bridge.connect("restore_request", Callable(Nuxie, "_on_restore_request"))
  bridge.connect("flow_lifecycle", Callable(Nuxie, "_on_flow_lifecycle"))

  _connected = true

static func _on_operation_result(request_id: String, method: String, ok: bool, result: Dictionary, error: Dictionary, timestamp_ms: int) -> void:
  var normalized_error := NuxieErrors.normalize(error)

  var waiter = _pending_operations.get(request_id)
  if waiter != null:
    waiter.finish(ok, result, normalized_error)

  if method == "startTrigger" and not ok:
    var operation: NuxieTriggerOperation = _trigger_operations.get(request_id)
    if operation != null:
      operation.emit_native_error(normalized_error)
      _trigger_operations.erase(request_id)

  _emit_event("operation_result", {
    "requestId": request_id,
    "method": method,
    "ok": ok,
    "result": result,
    "error": normalized_error,
    "timestampMs": timestamp_ms,
  })

static func _on_trigger_update(request_id: String, update: Dictionary, is_terminal: bool, timestamp_ms: int) -> void:
  var operation: NuxieTriggerOperation = _trigger_operations.get(request_id)
  if operation != null:
    operation._handle_update(update, is_terminal, timestamp_ms)

  _emit_event("trigger_update", {
    "requestId": request_id,
    "update": update,
    "isTerminal": is_terminal,
    "timestampMs": timestamp_ms,
  })

  if is_terminal:
    _trigger_operations.erase(request_id)

static func _on_feature_access_changed(feature_id: String, old_value: Dictionary, new_value: Dictionary, timestamp_ms: int) -> void:
  _emit_event("feature_access_changed", {
    "featureId": feature_id,
    "from": old_value,
    "to": new_value,
    "timestampMs": timestamp_ms,
  })

static func _on_purchase_request(request: Dictionary) -> void:
  _emit_event("purchase_request", request)
  _handle_purchase_request(request)

static func _on_restore_request(request: Dictionary) -> void:
  _emit_event("restore_request", request)
  _handle_restore_request(request)

static func _on_flow_lifecycle(event: Dictionary) -> void:
  _emit_event("flow_lifecycle", event)

static func _handle_purchase_request(request: Dictionary) -> void:
  var callback: Callable = _purchase_controller.get("on_purchase", Callable())
  if not callback.is_valid():
    return

  _handle_purchase_request_async(callback, request)

static func _handle_purchase_request_async(callback: Callable, request: Dictionary) -> void:
  var result: Variant = callback.call(request)
  if result is GDScriptFunctionState:
    result = await result

  var payload: Dictionary = result if result is Dictionary else {
    "type": "failed",
    "message": "invalid_purchase_result",
  }

  await complete_purchase(str(request.get("requestId", "")), payload)

static func _handle_restore_request(request: Dictionary) -> void:
  var callback: Callable = _purchase_controller.get("on_restore", Callable())
  if not callback.is_valid():
    return

  _handle_restore_request_async(callback, request)

static func _handle_restore_request_async(callback: Callable, request: Dictionary) -> void:
  var result: Variant = callback.call(request)
  if result is GDScriptFunctionState:
    result = await result

  var payload: Dictionary = result if result is Dictionary else {
    "type": "failed",
    "message": "invalid_restore_result",
  }

  await complete_restore(str(request.get("requestId", "")), payload)

static func _has_purchase_handlers() -> bool:
  return (
    (_purchase_controller.get("on_purchase", Callable()) as Callable).is_valid() or
    (_purchase_controller.get("on_restore", Callable()) as Callable).is_valid()
  )

static func _emit_event(event_name: String, payload: Dictionary) -> void:
  if not _listeners.has(event_name):
    return

  for listener in _listeners[event_name]:
    var callback := listener as Callable
    if callback.is_valid():
      callback.call(payload)

static func _new_request_id(prefix: String) -> String:
  return "%s-%d-%s" % [prefix, Time.get_ticks_msec(), str(randi())]
