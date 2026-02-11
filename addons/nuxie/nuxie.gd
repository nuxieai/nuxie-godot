class_name Nuxie
extends Object

const _PLUGIN_NAME := "NuxieGodot"
const _WRAPPER_VERSION := "0.2.0"

static var _bridge: Object = null
static var _connected := false
static var _uses_native_signals := false
static var _uses_polled_events := false
static var _poll_loop_running := false

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
  _connected = false
  _uses_native_signals = false
  _uses_polled_events = false

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

  _ensure_connected()

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

  if not _connected:
    return {
      "ok": false,
      "result": {},
      "error": NuxieErrors.build("NATIVE_SDK_UNAVAILABLE", "Nuxie bridge is unavailable"),
    }

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

  if _uses_polled_events:
    _drain_polled_events()

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

  _uses_native_signals = _bridge_has_native_signals(bridge)
  _uses_polled_events = _bridge_supports_polled_events(bridge)

  if _uses_native_signals:
    bridge.connect("operation_result", Callable(Nuxie, "_on_operation_result"))
    bridge.connect("trigger_update", Callable(Nuxie, "_on_trigger_update"))
    bridge.connect("feature_access_changed", Callable(Nuxie, "_on_feature_access_changed"))
    bridge.connect("purchase_request", Callable(Nuxie, "_on_purchase_request"))
    bridge.connect("restore_request", Callable(Nuxie, "_on_restore_request"))
    bridge.connect("flow_lifecycle", Callable(Nuxie, "_on_flow_lifecycle"))

  if not _uses_native_signals and not _uses_polled_events:
    return

  _connected = true

  if _uses_polled_events:
    _start_poll_loop()

static func _bridge_has_native_signals(bridge: Object) -> bool:
  return (
    bridge.has_signal("operation_result") and
    bridge.has_signal("trigger_update") and
    bridge.has_signal("feature_access_changed") and
    bridge.has_signal("purchase_request") and
    bridge.has_signal("restore_request") and
    bridge.has_signal("flow_lifecycle")
  )

static func _bridge_supports_polled_events(bridge: Object) -> bool:
  return (
    bridge.has_method("get_pending_event_count") and bridge.has_method("pop_pending_event")
  ) or (
    bridge.has_method("getPendingEventCount") and bridge.has_method("popPendingEvent")
  )

static func _start_poll_loop() -> void:
  if _poll_loop_running:
    return

  _poll_loop_running = true
  _poll_loop()

static func _poll_loop() -> void:
  while _connected and _uses_polled_events:
    _drain_polled_events()

    var main_loop := Engine.get_main_loop()
    if main_loop is SceneTree:
      await (main_loop as SceneTree).process_frame
    else:
      break

  _poll_loop_running = false

static func _drain_polled_events() -> void:
  if not _uses_polled_events:
    return

  var bridge := _ensure_bridge()
  if bridge == null:
    return

  var pending_count := _pending_event_count(bridge)
  while pending_count > 0:
    var raw_envelope := _pop_pending_event(bridge)
    var envelope := _normalize_event_envelope(raw_envelope)
    _dispatch_polled_envelope(envelope)
    pending_count -= 1

static func _pending_event_count(bridge: Object) -> int:
  if bridge.has_method("get_pending_event_count"):
    return int(bridge.callv("get_pending_event_count", []))
  if bridge.has_method("getPendingEventCount"):
    return int(bridge.callv("getPendingEventCount", []))
  return 0

static func _pop_pending_event(bridge: Object) -> Variant:
  if bridge.has_method("pop_pending_event"):
    return bridge.callv("pop_pending_event", [])
  if bridge.has_method("popPendingEvent"):
    return bridge.callv("popPendingEvent", [])
  return {}

static func _normalize_event_envelope(raw_envelope: Variant) -> Dictionary:
  if raw_envelope is Dictionary:
    return raw_envelope

  if raw_envelope is String:
    var parsed := JSON.parse_string(raw_envelope)
    if parsed is Dictionary:
      return parsed

  return {}

static func _dispatch_polled_envelope(envelope: Dictionary) -> void:
  if envelope.is_empty():
    return

  var event_name := str(envelope.get("event", envelope.get("type", "")))
  if event_name == "":
    return

  var payload_variant: Variant = envelope.get("payload", envelope)
  if not (payload_variant is Dictionary):
    return

  var payload := payload_variant as Dictionary

  match event_name:
    "operation_result":
      _dispatch_operation_result(
        str(payload.get("requestId", "")),
        str(payload.get("method", "")),
        bool(payload.get("ok", false)),
        payload.get("result", {}) as Dictionary,
        payload.get("error", {}) as Dictionary,
        int(payload.get("timestampMs", Time.get_ticks_msec())),
      )
    "trigger_update":
      _dispatch_trigger_update(
        str(payload.get("requestId", "")),
        payload.get("update", {}) as Dictionary,
        bool(payload.get("isTerminal", false)),
        int(payload.get("timestampMs", Time.get_ticks_msec())),
      )
    "feature_access_changed":
      _dispatch_feature_access_changed(
        str(payload.get("featureId", "")),
        payload.get("from", {}) as Dictionary,
        payload.get("to", {}) as Dictionary,
        int(payload.get("timestampMs", Time.get_ticks_msec())),
      )
    "purchase_request":
      _dispatch_purchase_request(payload)
    "restore_request":
      _dispatch_restore_request(payload)
    "flow_lifecycle":
      _dispatch_flow_lifecycle(payload)
    _:
      pass

static func _on_operation_result(request_id: String, method: String, ok: bool, result: Dictionary, error: Dictionary, timestamp_ms: int) -> void:
  _dispatch_operation_result(request_id, method, ok, result, error, timestamp_ms)

static func _dispatch_operation_result(request_id: String, method: String, ok: bool, result: Dictionary, error: Dictionary, timestamp_ms: int) -> void:
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
  _dispatch_trigger_update(request_id, update, is_terminal, timestamp_ms)

static func _dispatch_trigger_update(request_id: String, update: Dictionary, is_terminal: bool, timestamp_ms: int) -> void:
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
  _dispatch_feature_access_changed(feature_id, old_value, new_value, timestamp_ms)

static func _dispatch_feature_access_changed(feature_id: String, old_value: Dictionary, new_value: Dictionary, timestamp_ms: int) -> void:
  _emit_event("feature_access_changed", {
    "featureId": feature_id,
    "from": old_value,
    "to": new_value,
    "timestampMs": timestamp_ms,
  })

static func _on_purchase_request(request: Dictionary) -> void:
  _dispatch_purchase_request(request)

static func _dispatch_purchase_request(request: Dictionary) -> void:
  _emit_event("purchase_request", request)
  _handle_purchase_request(request)

static func _on_restore_request(request: Dictionary) -> void:
  _dispatch_restore_request(request)

static func _dispatch_restore_request(request: Dictionary) -> void:
  _emit_event("restore_request", request)
  _handle_restore_request(request)

static func _on_flow_lifecycle(event: Dictionary) -> void:
  _dispatch_flow_lifecycle(event)

static func _dispatch_flow_lifecycle(event: Dictionary) -> void:
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
