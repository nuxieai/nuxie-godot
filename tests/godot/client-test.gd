extends SceneTree

const ExportPlugin = preload("res://addons/nuxie/android/export_plugin.gd")
const Client = preload("res://addons/nuxie/nuxie.gd")
const Wire = preload("res://addons/nuxie/internal/wire.gd")
const Waiter = preload("res://addons/nuxie/internal/waiter.gd")
const EditorIntegration = preload("res://addons/nuxie/editor-plugin.gd")
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
	var bad_snapshot := false
	var shutdown_error := ""
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
				result = {"contract": 1, "session": session, "snapshot": null if bad_snapshot else snapshot()}
			"shutdown":
				if not shutdown_error.is_empty():
					messages.append(JSON.stringify({"requestId": request.requestId, "error": {"code": shutdown_error, "message": "Native setup is still owned"}}))
					return
				if not session.is_empty() and args.session != session:
					messages.append(JSON.stringify({"requestId": request.requestId, "error": {"code": "sessionExpired", "message": "Session already detached"}}))
					return
				session = ""
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
	var descriptor := "user://nuxie-descriptor-test.gdip"
	var marker := descriptor + ".sha256"
	for changed in [false, true]:
		var file := FileAccess.open(descriptor, FileAccess.WRITE)
		file.store_string("managed descriptor")
		file.close()
		file = FileAccess.open(marker, FileAccess.WRITE)
		file.store_string(FileAccess.get_sha256(descriptor))
		file.close()
		if changed:
			file = FileAccess.open(descriptor, FileAccess.WRITE)
			file.store_string("user modification")
			file.close()
		EditorIntegration._remove_ios_descriptor(descriptor)
		check(FileAccess.file_exists(descriptor) == changed and FileAccess.file_exists(marker) == changed, "Disable removes only the unchanged managed descriptor and marker")
	DirAccess.remove_absolute(marker)
	EditorIntegration._remove_ios_descriptor(descriptor)
	check(FileAccess.get_file_as_string(descriptor) == "user modification", "Disable preserves a descriptor without an ownership marker")
	DirAccess.remove_absolute(descriptor)
	var orphan_marker := FileAccess.open(marker, FileAccess.WRITE)
	orphan_marker.store_string("previous checksum")
	orphan_marker.close()
	EditorIntegration._remove_ios_descriptor(descriptor)
	check(not FileAccess.file_exists(marker), "Disable removes an orphan ownership marker")
	for pair in [
		["/Users/Game Projects/a#b", "file:///Users/Game%20Projects/a%23b"],
		["C:/Game Projects/a#b", "file:///C:/Game%20Projects/a%23b"],
		["C:\\Game Projects\\maven", "file:///C:/Game%20Projects/maven"],
		["//server/share/Game Projects/maven", "file://server/share/Game%20Projects/maven"],
	]:
		check(ExportPlugin._maven_repository_uri(pair[0]) == pair[1], "Portable Maven file URI: " + pair[0])
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
	var published_customers: Array[String] = []
	var ready_feature_statuses: Array[int] = []
	client.features_changed.connect(func(value: NuxieFeatureSnapshot) -> void:
		if value.kind == NuxieFeatureState.Kind.READY:
			published_customers.append(value.customer_id)
			ready_feature_statuses.append(client.get_status().kind))
	check((await client.configure(options)).ok, "Configure")
	check(client.get_feature_state("premium").access.allowed, "Initial access")
	check(ready_feature_statuses == [NuxieStatus.Kind.READY], "Initial feature notification arrives after command readiness")
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
	var expired_session: String = client._session
	bridge.shutdown_error = "sessionExpired"
	var expired_shutdown := await client.shutdown()
	check(not expired_shutdown.ok and expired_shutdown.error.code == "sessionExpired", "An expired session does not prove native teardown")
	check(client.get_status().kind == NuxieStatus.Kind.FAILED and client._session == expired_session, "Unconfirmed teardown retains recovery ownership")
	bridge.shutdown_error = ""
	check((await client.shutdown()).ok and (await client.configure(options)).ok, "Explicit native acknowledgement permits reconfiguration")
	for native_completed in [false, true]:
		bridge.hold = "shutdown"
		var failed_shutdown: Array = []
		var retained_session: String = client._session
		var invalidated: Array[int] = []
		var shutting_down_access: Array[int] = []
		var feature_listener := func(value: NuxieFeatureSnapshot) -> void: invalidated.append(value.kind)
		var status_listener := func(value: NuxieStatus) -> void:
			if value.kind == NuxieStatus.Kind.SHUTTING_DOWN:
				shutting_down_access.append(client.get_feature_state("premium").kind)
		client.features_changed.connect(feature_listener)
		client.status_changed.connect(status_listener)
		_capture.call(failed_shutdown, client.shutdown)
		check(shutting_down_access == [NuxieFeatureState.Kind.UNKNOWN], "Shutdown status observers see revoked authority")
		check(invalidated == [NuxieFeatureState.Kind.UNKNOWN] and client.get_feature_state("premium").kind == NuxieFeatureState.Kind.UNKNOWN, "Pending shutdown immediately publishes and exposes unknown access")
		client.features_changed.disconnect(feature_listener)
		client.status_changed.disconnect(status_listener)
		await process_frame
		for pending: RefCounted in client._pending.values():
			pending.deadline = 0
		await process_frame
		check(failed_shutdown.size() == 1 and failed_shutdown[0].error.code == "operationTimeout", "Shutdown timeout settles")
		check(client.get_status().kind == NuxieStatus.Kind.FAILED and client._session == retained_session, "Failed shutdown retains retry ownership")
		check(not (await client.configure(options)).ok, "Reconfiguration waits for confirmed detach")
		bridge.hold = ""
		if native_completed:
			bridge.session = ""
		check((await client.shutdown()).ok, "Retry explicitly confirms native teardown")
		check(bridge.requests[-1].method == "shutdown" and bridge.requests[-1].arguments.session == retained_session, "Retry sends the retained native session")
		check((await client.configure(options)).ok, "Configure after recovered shutdown")
	await client.shutdown()
	for timeout in [false, true]:
		bridge.hold = "getIdentity"
		var setup_results: Array = []
		_capture.call(setup_results, client.configure.bind(options))
		await process_frame
		await process_frame
		_capture.call(setup_results, client.configure.bind(options))
		check(client.get_status().kind == NuxieStatus.Kind.CONFIGURING and setup_results.is_empty(), "Configure callers wait for initial identity hydration")
		if timeout:
			for pending: RefCounted in client._pending.values():
				pending.deadline = 0
		else:
			bridge.messages.append(JSON.stringify({"requestId": bridge.requests[-1].requestId, "error": {"code": "identityUnavailable", "message": "Identity query failed"}}))
		await process_frame
		await process_frame
		var expected_error := "operationTimeout" if timeout else "identityUnavailable"
		check(setup_results.size() == 2 and not setup_results[0].ok and not setup_results[1].ok and setup_results[0].error.code == expected_error and setup_results[1].error.code == expected_error, "Hydration failure reaches every configure caller")
		check(client.get_status().kind == NuxieStatus.Kind.FAILED and client.get_feature_state("premium").kind == NuxieFeatureState.Kind.UNKNOWN, "Hydration failure cannot report ready authority")
		bridge.hold = ""
		check((await client.shutdown()).ok, "Failed hydration keeps the native session available for shutdown")
	var shutdown_results: Array = []
	var shutdown_callback := func(status: NuxieStatus) -> void:
		if status.kind == NuxieStatus.Kind.CONFIGURING:
			_capture.call(shutdown_results, client.shutdown)
	client.status_changed.connect(shutdown_callback)
	var configure_interrupted := await client.configure(options)
	await process_frame
	check(not configure_interrupted.ok and client.get_status().kind == NuxieStatus.Kind.UNCONFIGURED, "Reentrant shutdown cannot leave native setup attached")
	client.status_changed.disconnect(shutdown_callback)
	check(not published_customers.has(""), "Every admitted authority includes its customer")
	bridge.bad_snapshot = true
	check(not (await client.configure(options)).ok, "Null native snapshot settles configuration")
	check(client.get_status().kind == NuxieStatus.Kind.FAILED, "Malformed setup publishes failed status")
	await client.shutdown()
	client.queue_free()
	await process_frame
	print("Godot client checks: %d, failures: %d" % [checks, failures])
	quit(1 if failures else 0)
