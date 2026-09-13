extends SceneTree

const Client = preload("res://addons/nuxie/nuxie.gd")
const Wire = preload("res://addons/nuxie/internal/wire.gd")
const Waiter = preload("res://addons/nuxie/internal/waiter.gd")
var failures := 0
var checks := 0

class Bridge extends RefCounted:
	var messages: Array[String] = []
	var requests: Array[Dictionary] = []
	var session := ""
	var customer := "anonymous"
	var generation := "1"
	var hold := ""
	var malformed := false
	var java_checks := 0
	func has_java_method(method: String) -> bool:
		java_checks += 1
		return method in ["dispatch", "pop_message"]
	func snapshot(revision: String = "1") -> Dictionary:
		return {"identityGeneration": generation, "revision": revision, "state": "ready", "all": {"premium": {"allowed": true, "balance": null, "type": "boolean", "unlimited": true}}}
	func event(name: String, payload: Dictionary, attached: String = "") -> void:
		messages.append(JSON.stringify({"session": session if attached.is_empty() else attached, "name": name, "payload": payload}))
	func dispatch(raw: String) -> void:
		var request: Dictionary = JSON.parse_string(raw)
		requests.append(request)
		var args: Dictionary = request.arguments
		var result: Variant = null
		if hold == request.method:
			return
		match request.method:
			"configure":
				var config: Dictionary = JSON.parse_string(args.configuration)
				session = config.session
				result = {"contract": 1, "session": session, "snapshot": snapshot()}
			"getIdentity":
				result = {"distinctId": customer, "anonymousId": "anonymous", "isIdentified": customer != "anonymous"}
			"identify", "reset":
				customer = args.get("customerId", "rotated-anonymous")
				generation = str(int(generation) + 1)
				event("features", snapshot("3"))
				result = snapshot("2")
			"hasFeature":
				result = {"allowed": false, "balance": 0, "type": "metered", "unlimited": false}
			"consumeFeature":
				var command: Dictionary = JSON.parse_string(args.options)
				result = {"customerId": customer, "featureId": args.featureId, "operationId": command.operationId, "quantity": command.quantity, "occurredAtMs": null, "accepted": true, "code": "ok", "balance": 0, "unlimited": false, "active": false, "idempotentReplay": false}
		messages.append(JSON.stringify({"requestId": request.requestId} if malformed else {"requestId": request.requestId, "result": JSON.stringify(result) if result is Dictionary else result}))
	func pop_message() -> String:
		return messages.pop_front() if not messages.is_empty() else ""

class Controller extends NuxiePurchaseController:
	var count := 0
	func purchase(_product: NuxieStoreProduct) -> NuxiePurchaseResult:
		count += 1
		return NuxiePurchaseResult.cancelled()

func check(value: bool, message: String) -> void:
	checks += 1
	if not value:
		failures += 1
		push_error(message)

func _capture(output: Array, operation: Callable) -> void:
	output.append(await operation.call())

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	var client := Client.new()
	root.add_child(client)
	var unsupported := await client.configure(NuxieOptions.new())
	check(not unsupported.ok, "Desktop must not silently simulate native success")
	var bridge := Bridge.new()
	client._bridge = bridge
	client._platform_override = "iOS"
	var options := NuxieOptions.new()
	options.ios_api_key = "public-test-key"
	var controller := Controller.new()
	options.billing = NuxieBilling.external(controller)
	check((await client.configure(options)).ok, "Configure")
	check(client.get_feature_state("premium").access.allowed, "Initial access")
	var exposed := client.get_feature_state("premium")
	exposed.access.allowed = false
	check(client.get_feature_state("premium").access.allowed, "Returned access cannot mutate cache")
	check((await client.configure(options)).ok, "Equivalent setup")
	var conflict := NuxieOptions.new()
	conflict.ios_api_key = "different"
	check(not (await client.configure(conflict)).ok, "Conflicting setup")
	check((await client.identify("player")).ok, "Identify")
	check(client.get_feature_snapshot().revision == "3", "Newest snapshot preceding identity completion retained")
	check(client.get_feature_snapshot().customer_id == "player", "Coherent snapshot customer")
	var denied := await client.check_feature("energy")
	check(denied.ok and not denied.value.allowed, "Denial is a successful query")
	check(client.get_feature_state("premium").access.allowed, "Scoped query does not replace global snapshot")
	var command := NuxieFeatureCommand.new()
	command.operation_id = "persisted-action"
	var spent := await client.consume_feature("energy", command)
	check(spent.ok and spent.value.accepted and not spent.value.active, "Last unit is a successful spend")
	command.quantity = 0
	check(not (await client.consume_feature("energy", command)).ok, "Reject zero quantity")
	check(Wire.compare("18446744073709551615", "9223372036854775807") > 0, "Exact unsigned comparison")
	check(not Wire.decimal("18446744073709551616"), "Reject overflow")
	check(not Wire.valid_json({"value": INF}), "Reject nonfinite JSON")
	var cyclic: Array = []
	cyclic.append(cyclic)
	check(not Wire.valid_json(cyclic), "Reject cyclic JSON")
	cyclic.clear()
	bridge.event("features", bridge.snapshot("99"), "old-session")
	await process_frame
	check(client.get_feature_snapshot().revision == "3", "Old session ignored")
	bridge.event("purchase", {"requestId": "checkout-1", "deadlineMs": Time.get_unix_time_from_system() * 1000 + 60000, "product": {"storeProductId": "sku"}})
	bridge.event("purchase", {"requestId": "checkout-1", "deadlineMs": Time.get_unix_time_from_system() * 1000 + 60000, "product": {"storeProductId": "sku"}})
	await process_frame
	await process_frame
	check(controller.count == 1, "Duplicate checkout starts once")
	var replies := bridge.requests.filter(func(r: Dictionary) -> bool: return r.method == "completePurchase")
	check(replies.size() == 1 and replies[0].requestId != replies[0].arguments.requestId, "Purchase completion has independent correlation ID")
	paused = true
	check((await client.trigger("paused_game")).ok, "Dispatcher runs while SceneTree paused")
	paused = false
	bridge.malformed = true
	check(not (await client.trigger("bad_response")).ok, "Malformed matching response settles")
	bridge.malformed = false
	var waiter := Waiter.new()
	waiter.finish({"result": 1})
	waiter.finish({"result": 2})
	check((await waiter.wait()).result == 1 and (await waiter.wait()).result == 1, "Late awaits and duplicate settlement")
	check(bridge.java_checks > 0, "Use Android JNI method introspection")
	var timeout_results: Array = []
	bridge.hold = "trigger"
	_capture.call(timeout_results, client.trigger.bind("timeout"))
	await process_frame
	for pending: RefCounted in client._pending.values():
		pending.deadline = 0
	await process_frame
	check(timeout_results.size() == 1 and timeout_results[0].error.code == "operationTimeout", "Missing native reply settles with timeout")
	var interrupted_results: Array = []
	_capture.call(interrupted_results, client.trigger.bind("shutdown_pending"))
	await process_frame
	bridge.hold = ""
	check((await client.shutdown()).ok, "Shutdown")
	check(interrupted_results.size() == 1 and interrupted_results[0].error.code == "sdkShutdown", "Shutdown settles outstanding commands")
	check(client.get_feature_state("premium").kind == NuxieFeatureState.Kind.UNKNOWN, "Shutdown invalidates access")
	check((await client.configure(options)).ok, "Reconfigure")
	await client.shutdown()
	var shutdown_results: Array = []
	var shutdown_callback := func(status: NuxieStatus) -> void:
		if status.kind == NuxieStatus.Kind.CONFIGURING:
			_capture.call(shutdown_results, client.shutdown)
	client.status_changed.connect(shutdown_callback)
	var configure_interrupted := await client.configure(options)
	await process_frame
	check(not configure_interrupted.ok and client.get_status().kind == NuxieStatus.Kind.UNCONFIGURED, "Reentrant shutdown cannot leave native setup attached")
	client.status_changed.disconnect(shutdown_callback)
	client.queue_free()
	await process_frame
	print("Godot client checks: %d, failures: %d" % [checks, failures])
	quit(1 if failures else 0)
