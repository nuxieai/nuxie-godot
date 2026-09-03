extends Node

class FakeBridge:
  extends RefCounted

  signal operation_result(
    request_id: String,
    method: String,
    ok: bool,
    result: Dictionary,
    error: Dictionary,
    timestamp_ms: int,
  )
  signal feature_access_changed(payload: Dictionary)
  signal activity(payload: Dictionary)
  signal app_action(payload: Dictionary)
  signal purchase_request(payload: Dictionary)
  signal restore_request(payload: Dictionary)

  var invocations: Array[Dictionary] = []

  func configure(
    api_key: String,
    options: Dictionary,
    use_purchase_controller: bool,
    wrapper_version: String,
    request_id: String,
  ) -> void:
    invocations.append({
      "method": "configure",
      "api_key": api_key,
      "options": options,
      "use_purchase_controller": use_purchase_controller,
      "wrapper_version": wrapper_version,
    })
    _complete.call_deferred("configure", request_id, {
      "isConfigured": true,
      "wrapperVersion": wrapper_version,
    })

  func reset(keep_anonymous_id: bool, request_id: String) -> void:
    invocations.append({
      "method": "reset",
      "keep_anonymous_id": keep_anonymous_id,
    })
    _complete.call_deferred("reset", request_id, {})

  func trigger(event_name: String, properties: Dictionary) -> void:
    invocations.append({
      "method": "trigger",
      "event_name": event_name,
      "properties": properties,
    })

  func hasFeature(
    feature_id: String,
    required_balance: float,
    entity_id: String,
    policy: String,
    request_id: String,
  ) -> void:
    invocations.append({
      "method": "hasFeature",
      "feature_id": feature_id,
      "required_balance": required_balance,
      "entity_id": entity_id,
      "policy": policy,
    })
    _complete.call_deferred("hasFeature", request_id, {
      "allowed": true,
      "unlimited": false,
      "balance": 2.5,
      "type": "metered",
    })

  func _complete(method: String, request_id: String, result: Dictionary) -> void:
    operation_result.emit(request_id, method, true, result, {}, Time.get_ticks_msec())


var _failures: Array[String] = []

func _ready() -> void:
  await _run_contract()
  Nuxie._disconnect_bridge()

  if _failures.is_empty():
    print("Nuxie Godot facade contract passed")
    get_tree().quit(0)
    return

  for failure in _failures:
    push_error(failure)
  get_tree().quit(1)

func _run_contract() -> void:
  Nuxie._disconnect_bridge()
  var bridge := FakeBridge.new()
  Nuxie._bridge = bridge

  var configured := await Nuxie.configure("public-key", {
    "environment": "development",
    "purchase_handling_mode": "observer",
  })
  _expect(configured.ok, "configure should resolve successfully")
  _expect(bridge.invocations[0].api_key == "public-key", "configure should preserve the API key")
  _expect(bridge.invocations[0].wrapper_version == "0.3.0", "configure should send the wrapper version")

  Nuxie.trigger("level_completed", {"level": 7})
  _expect(bridge.invocations[1].event_name == "level_completed", "trigger should preserve the event name")
  _expect(bridge.invocations[1].properties.level == 7, "trigger should preserve event properties")

  var reset_result := await Nuxie.reset()
  _expect(reset_result.ok, "reset should resolve successfully")
  _expect(bridge.invocations[2].keep_anonymous_id == false, "reset should create a fresh anonymous identity by default")

  var access := await Nuxie.has_feature(
    "credits",
    1.5,
    "workspace-1",
    Nuxie.FEATURE_POLICY_REMOTE,
  )
  _expect(access.ok, "remote feature access should resolve successfully")
  _expect(bridge.invocations[3].policy == "remote", "feature checks should preserve the remote policy")
  _expect(is_equal_approx(access.result.balance, 2.5), "feature balances should preserve fractional values")

  var received_actions: Array[Dictionary] = []
  var listener := func(payload: Dictionary) -> void:
    received_actions.append(payload)
  Nuxie.on("app_action", listener)
  bridge.app_action.emit({
    "name": "open_inventory",
    "payload": {"tab": "boosters"},
    "experience": {"experienceId": "experience-1", "journeyId": "journey-1"},
  })
  _expect(received_actions.size() == 1, "app actions should reach public listeners")
  _expect(received_actions[0].payload.tab == "boosters", "app action payloads should stay typed")
  Nuxie.off("app_action", listener)

func _expect(condition: bool, message: String) -> void:
  if not condition:
    _failures.append(message)
