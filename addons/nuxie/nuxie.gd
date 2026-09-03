class_name Nuxie
extends Object

const FEATURE_POLICY_CACHE_FIRST := "cache_first"
const FEATURE_POLICY_REMOTE := "remote"

const _PLUGIN_NAME := "NuxieGodot"
const _WRAPPER_VERSION := "0.3.0"
const _PUBLIC_EVENTS := [
  "feature_access_changed",
  "activity",
  "app_action",
  "purchase_request",
  "restore_request",
]

static var _bridge: Object = null
static var _connected := false
static var _uses_native_signals := false
static var _uses_polled_events := false
static var _poll_loop_running := false
static var _pending_operations := {}
static var _listeners := {
  "feature_access_changed": [],
  "activity": [],
  "app_action": [],
  "purchase_request": [],
  "restore_request": [],
}
static var _purchase_controller := {
  "on_purchase": Callable(),
  "on_restore": Callable(),
}

class _OperationWaiter:
  extends RefCounted

  signal resolved(payload: Dictionary)

  var _done := false
  var _payload: Dictionary = {}

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

static func set_purchase_controller(
  on_purchase: Callable = Callable(),
  on_restore: Callable = Callable(),
) -> void:
  _purchase_controller["on_purchase"] = on_purchase
  _purchase_controller["on_restore"] = on_restore

static func on(event_name: String, callback: Callable) -> void:
  if not event_name in _PUBLIC_EVENTS:
    push_error("[Nuxie] Unknown event '%s'" % event_name)
    return
  if not callback.is_valid():
    push_error("[Nuxie] Listener for '%s' is not callable" % event_name)
    return
  (_listeners[event_name] as Array).append(callback)

static func off(event_name: String, callback: Callable) -> void:
  if not event_name in _PUBLIC_EVENTS:
    return
  (_listeners[event_name] as Array).erase(callback)

static func configure(
  api_key: String,
  options: Dictionary = {},
  use_purchase_controller := false,
) -> Dictionary:
  var request_id := _new_request_id("configure")
  return await _invoke_async(
    "configure",
    [api_key, options, use_purchase_controller or _has_purchase_handlers(), _WRAPPER_VERSION, request_id],
    request_id,
  )

static func shutdown() -> Dictionary:
  var request_id := _new_request_id("shutdown")
  var payload := await _invoke_async("shutdown", [request_id], request_id)
  _disconnect_bridge()
  return payload

static func identify(
  distinct_id: String,
  user_properties: Dictionary = {},
  user_properties_set_once: Dictionary = {},
) -> Dictionary:
  var request_id := _new_request_id("identify")
  return await _invoke_async(
    "identify",
    [distinct_id, user_properties, user_properties_set_once, request_id],
    request_id,
  )

static func reset(keep_anonymous_id := false) -> Dictionary:
  var request_id := _new_request_id("reset")
  return await _invoke_async("reset", [keep_anonymous_id, request_id], request_id)

static func get_distinct_id() -> String:
  return await _read_string("getDistinctId", "distinctId")

static func get_anonymous_id() -> String:
  return await _read_string("getAnonymousId", "anonymousId")

static func get_is_identified() -> bool:
  var request_id := _new_request_id("getIsIdentified")
  var payload := await _invoke_async("getIsIdentified", [request_id], request_id)
  if not payload.ok:
    NuxieErrors.emit("get_is_identified", payload.error)
    return false
  return bool((payload.result as Dictionary).get("isIdentified", false))

## Captures an event. Any matching Journey runs asynchronously in the native SDK.
static func trigger(event_name: String, properties: Dictionary = {}) -> void:
  var bridge := _require_bridge("trigger")
  if bridge == null:
    return
  bridge.callv("trigger", [event_name, properties])

static func dismiss() -> Dictionary:
  var request_id := _new_request_id("dismiss")
  return await _invoke_async("dismiss", [request_id], request_id)

static func set_locale_identifier(locale_identifier: Variant = null) -> Dictionary:
  if locale_identifier != null and not locale_identifier is String:
    return _failure("INVALID_ARGUMENTS", "locale_identifier must be a String or null")
  var request_id := _new_request_id("setLocaleIdentifier")
  return await _invoke_async(
    "setLocaleIdentifier",
    [locale_identifier, request_id],
    request_id,
  )

static func has_feature(
  feature_id: String,
  required_balance: float = 1.0,
  entity_id: String = "",
  policy: String = FEATURE_POLICY_CACHE_FIRST,
) -> Dictionary:
  if policy != FEATURE_POLICY_CACHE_FIRST and policy != FEATURE_POLICY_REMOTE:
    return _failure("INVALID_ARGUMENTS", "policy must be 'cache_first' or 'remote'")
  var request_id := _new_request_id("hasFeature")
  return await _invoke_async(
    "hasFeature",
    [feature_id, required_balance, entity_id, policy, request_id],
    request_id,
  )

## Records feature use without waiting for server confirmation.
static func use_feature(
  feature_id: String,
  amount: float = 1.0,
  entity_id: String = "",
  metadata: Dictionary = {},
) -> void:
  var bridge := _require_bridge("use_feature")
  if bridge == null:
    return
  bridge.callv("useFeature", [feature_id, amount, entity_id, metadata])

static func use_feature_and_wait(
  feature_id: String,
  amount: float = 1.0,
  entity_id: String = "",
  set_usage := false,
  metadata: Dictionary = {},
) -> Dictionary:
  var request_id := _new_request_id("useFeatureAndWait")
  return await _invoke_async(
    "useFeatureAndWait",
    [feature_id, amount, entity_id, set_usage, metadata, request_id],
    request_id,
  )

static func complete_purchase(request_id: String, result: Dictionary) -> void:
  var bridge := _require_bridge("complete_purchase")
  if bridge != null:
    bridge.callv("completePurchase", [request_id, result])

static func complete_restore(request_id: String, result: Dictionary) -> void:
  var bridge := _require_bridge("complete_restore")
  if bridge != null:
    bridge.callv("completeRestore", [request_id, result])

static func _read_string(method: String, key: String) -> String:
  var request_id := _new_request_id(method)
  var payload := await _invoke_async(method, [request_id], request_id)
  if not payload.ok:
    NuxieErrors.emit(method, payload.error)
    return ""
  return str((payload.result as Dictionary).get(key, ""))

static func _invoke_async(method: String, args: Array, request_id: String) -> Dictionary:
  _ensure_connected()
  if not _connected:
    return _failure("NATIVE_SDK_UNAVAILABLE", "Nuxie bridge is unavailable")

  var waiter := _OperationWaiter.new()
  _pending_operations[request_id] = waiter
  _bridge.callv(method, args)

  if _uses_polled_events:
    _drain_polled_events()

  var payload := await waiter.wait()
  _pending_operations.erase(request_id)
  return payload

static func _require_bridge(operation: String) -> Object:
  _ensure_connected()
  if _connected:
    return _bridge
  NuxieErrors.emit(
    operation,
    NuxieErrors.build("NATIVE_SDK_UNAVAILABLE", "Nuxie bridge is unavailable"),
  )
  return null

static func _ensure_bridge() -> Object:
  if _bridge == null and Engine.has_singleton(_PLUGIN_NAME):
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
    bridge.connect("feature_access_changed", Callable(Nuxie, "_on_feature_access_changed"))
    bridge.connect("activity", Callable(Nuxie, "_on_activity"))
    bridge.connect("app_action", Callable(Nuxie, "_on_app_action"))
    bridge.connect("purchase_request", Callable(Nuxie, "_on_purchase_request"))
    bridge.connect("restore_request", Callable(Nuxie, "_on_restore_request"))

  if not _uses_native_signals and not _uses_polled_events:
    return

  _connected = true
  if _uses_polled_events:
    _start_poll_loop()

static func _disconnect_bridge() -> void:
  if _bridge != null and _uses_native_signals:
    for event_name in ["operation_result"] + _PUBLIC_EVENTS:
      var callback := Callable(Nuxie, "_on_%s" % event_name)
      if _bridge.is_connected(event_name, callback):
        _bridge.disconnect(event_name, callback)

  for waiter in _pending_operations.values():
    waiter.finish(
      false,
      {},
      NuxieErrors.build("SDK_SHUTDOWN", "Nuxie SDK shut down before the operation completed"),
    )
  _pending_operations.clear()
  _bridge = null
  _connected = false
  _uses_native_signals = false
  _uses_polled_events = false

static func _bridge_has_native_signals(bridge: Object) -> bool:
  for event_name in ["operation_result"] + _PUBLIC_EVENTS:
    if not bridge.has_signal(event_name):
      return false
  return true

static func _bridge_supports_polled_events(bridge: Object) -> bool:
  return bridge.has_method("get_pending_event_count") and bridge.has_method("pop_pending_event")

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
  if not _uses_polled_events or _bridge == null:
    return

  var pending_count := int(_bridge.callv("get_pending_event_count", []))
  while pending_count > 0:
    var envelope := _normalize_event_envelope(_bridge.callv("pop_pending_event", []))
    _dispatch_polled_envelope(envelope)
    pending_count -= 1

static func _normalize_event_envelope(raw_envelope: Variant) -> Dictionary:
  if raw_envelope is Dictionary:
    return raw_envelope
  if raw_envelope is String:
    var parsed := JSON.parse_string(raw_envelope)
    if parsed is Dictionary:
      return parsed
  return {}

static func _dispatch_polled_envelope(envelope: Dictionary) -> void:
  var event_name := str(envelope.get("event", envelope.get("type", "")))
  var payload: Variant = envelope.get("payload", {})
  if not payload is Dictionary:
    return

  match event_name:
    "operation_result":
      _dispatch_operation_result(payload)
    "feature_access_changed", "activity", "app_action", "purchase_request", "restore_request":
      _dispatch_public_event(event_name, payload)

static func _on_operation_result(
  request_id: String,
  method: String,
  ok: bool,
  result: Dictionary,
  error: Dictionary,
  _timestamp_ms: int,
) -> void:
  _dispatch_operation_result({
    "requestId": request_id,
    "method": method,
    "ok": ok,
    "result": result,
    "error": error,
  })

static func _dispatch_operation_result(payload: Dictionary) -> void:
  var request_id := str(payload.get("requestId", ""))
  var waiter = _pending_operations.get(request_id)
  if waiter == null:
    return

  var ok := bool(payload.get("ok", false))
  var result: Variant = payload.get("result", {})
  if not result is Dictionary:
    result = {}
  var error := {} if ok else NuxieErrors.normalize(payload.get("error", {}))
  waiter.finish(ok, result, error)

static func _on_feature_access_changed(payload: Dictionary) -> void:
  _dispatch_public_event("feature_access_changed", payload)

static func _on_activity(payload: Dictionary) -> void:
  _dispatch_public_event("activity", payload)

static func _on_app_action(payload: Dictionary) -> void:
  _dispatch_public_event("app_action", payload)

static func _on_purchase_request(payload: Dictionary) -> void:
  _dispatch_public_event("purchase_request", payload)

static func _on_restore_request(payload: Dictionary) -> void:
  _dispatch_public_event("restore_request", payload)

static func _dispatch_public_event(event_name: String, payload: Dictionary) -> void:
  _emit_event(event_name, payload)
  if event_name == "purchase_request":
    _handle_purchase_request(payload)
  elif event_name == "restore_request":
    _handle_restore_request(payload)

static func _handle_purchase_request(request: Dictionary) -> void:
  var callback: Callable = _purchase_controller.get("on_purchase", Callable())
  if callback.is_valid():
    _handle_purchase_request_async(callback, request)

static func _handle_purchase_request_async(callback: Callable, request: Dictionary) -> void:
  var result: Variant = await callback.call(request)
  var payload: Dictionary = result if result is Dictionary else {
    "type": "failed",
    "message": "invalid_purchase_result",
  }
  complete_purchase(str(request.get("request_id", "")), payload)

static func _handle_restore_request(request: Dictionary) -> void:
  var callback: Callable = _purchase_controller.get("on_restore", Callable())
  if callback.is_valid():
    _handle_restore_request_async(callback, request)

static func _handle_restore_request_async(callback: Callable, request: Dictionary) -> void:
  var result: Variant = await callback.call(request)
  var payload: Dictionary = result if result is Dictionary else {
    "type": "failed",
    "message": "invalid_restore_result",
  }
  complete_restore(str(request.get("request_id", "")), payload)

static func _has_purchase_handlers() -> bool:
  return (
    (_purchase_controller.get("on_purchase", Callable()) as Callable).is_valid() or
    (_purchase_controller.get("on_restore", Callable()) as Callable).is_valid()
  )

static func _emit_event(event_name: String, payload: Dictionary) -> void:
  for listener in _listeners[event_name]:
    var callback := listener as Callable
    if callback.is_valid():
      callback.call(payload)

static func _failure(code: String, message: String) -> Dictionary:
  return {
    "ok": false,
    "result": {},
    "error": NuxieErrors.build(code, message),
  }

static func _new_request_id(prefix: String) -> String:
  return "%s-%d-%s" % [prefix, Time.get_ticks_msec(), str(randi())]
