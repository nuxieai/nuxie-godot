extends Node
## Native Nuxie client. Registered as the Nuxie autoload by the editor plugin.

signal status_changed(status: NuxieStatus)
signal identity_changed(identity: NuxieIdentity)
signal features_changed(snapshot: NuxieFeatureSnapshot)
signal activity_received(activity: NuxieActivity)
signal app_action_received(action: NuxieAppAction)
signal error_received(error: NuxieError)

const Wire = preload("internal/wire.gd")
const Waiter = preload("internal/waiter.gd")
const CALLBACK_BUDGET := 128
const OPERATION_TIMEOUT_MS := 90000
var _bridge: Object
var _platform_override: String = ""
var _status: NuxieStatus.Kind = NuxieStatus.Kind.UNCONFIGURED
var _last_error: NuxieError
var _session: String = ""
var _configuration: Dictionary = {}
var _controller: NuxiePurchaseController
var _pending: Dictionary = {}
var _checkout: Dictionary = {}
var _setup_waiter: RefCounted
var _shutdown_waiter: RefCounted
var _snapshot: Dictionary = {}
var _buffered: Dictionary = {}
var _customer: String = ""
var _identity_epoch: int = 0
var _identity_busy: bool = false
var _sequence: int = 0

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	if Engine.has_singleton("NuxieGodot"):
		_bridge = Engine.get_singleton("NuxieGodot")

func _exit_tree() -> void:
	_cancel_pending("sdkShutdown", "Nuxie runtime left the scene tree")
	if _bridge != null and not _session.is_empty():
		_bridge.call("dispatch", JSON.stringify({"requestId": "detach", "method": "shutdown", "arguments": {"session": _session}}))
	_session = ""
	_checkout.clear()
	_controller = null

func is_available() -> bool:
	if _bridge == null and Engine.has_singleton("NuxieGodot"):
		_bridge = Engine.get_singleton("NuxieGodot")
	if _bridge == null:
		return false
	# Android JNISingleton exposes Java methods through callp, not Object.has_method.
	if _bridge.has_method("has_java_method"):
		return _bridge.call("has_java_method", "dispatch") and _bridge.call("has_java_method", "pop_message")
	return _bridge.has_method("dispatch") and _bridge.has_method("pop_message")

func get_status() -> NuxieStatus:
	return NuxieStatus.new(_status, _last_error)

func get_feature_snapshot() -> NuxieFeatureSnapshot:
	return NuxieFeatureSnapshot.new(_snapshot, _customer)

func get_feature_state(feature_id: String) -> NuxieFeatureState:
	return get_feature_snapshot().select(feature_id)

func configure(options: NuxieOptions) -> NuxieResult:
	if options == null:
		return _failure("invalidArgument", "Options are required")
	if not is_available():
		return _failure("unsupportedPlatform", "Run a mobile player with the Nuxie native plugin enabled")
	var platform := _platform_override if not _platform_override.is_empty() else OS.get_name()
	var key := options.ios_api_key if platform == "iOS" else options.android_api_key
	if key.strip_edges().is_empty() or options.environment not in [0, 1] or options.log_level < 0 or options.log_level > 5 or options.billing == null:
		return _failure("invalidArgument", "Supply a platform public API key and valid options")
	var config := {"contract": 1, "apiKey": key, "environment": "development" if options.environment == NuxieOptions.EnvironmentKind.DEVELOPMENT else "production", "logLevel": ["warning", "debug", "info", "error", "none", "verbose"][options.log_level], "localeIdentifier": null if options.locale.is_empty() else options.locale, "externalBilling": options.billing.controller != null, "purchaseHandlingMode": "observer" if options.billing.controller != null else "full"}
	if _status in [NuxieStatus.Kind.CONFIGURING, NuxieStatus.Kind.READY]:
		if config != _configuration or options.billing.controller != _controller:
			return _failure("alreadyConfigured", "Shutdown before changing configuration")
		if _status == NuxieStatus.Kind.READY:
			return NuxieResult.new()
		return _ack(await _setup_waiter.wait())
	if _status == NuxieStatus.Kind.SHUTTING_DOWN or not _session.is_empty():
		return _failure("lifecycleBusy", "Await shutdown before configuring again")
	_configuration = config.duplicate(true)
	_controller = options.billing.controller
	_session = Crypto.new().generate_random_bytes(16).hex_encode()
	config.session = _session
	var configuring_session := _session
	var configuring_epoch := _identity_epoch
	var hydrated_identity: NuxieIdentity
	_setup_waiter = Waiter.new()
	var setup := _setup_waiter
	_set_status(NuxieStatus.Kind.CONFIGURING)
	if _status != NuxieStatus.Kind.CONFIGURING or _session != configuring_session:
		var interrupted := _error_wire("sdkShutdown", "Configuration interrupted by lifecycle callback")
		setup.finish(interrupted)
		return _ack(interrupted)
	var response: Dictionary = await _request("configure", {"configuration": JSON.stringify(config)})
	if not response.has("error"):
		var data := Wire.object(response.get("result"))
		if data.get("contract") != 1 or data.get("session") != _session or not data.get("snapshot") is Dictionary or not Wire.snapshot(data.snapshot):
			response = _error_wire("incompatibleBridge", "Native configuration response does not match the addon")
		else:
			_admit(data.snapshot)
	if not response.has("error") and _status == NuxieStatus.Kind.CONFIGURING and _session == configuring_session:
		var identity := await _read_identity(true)
		if not identity.ok:
			response = {"error": identity.error.details.duplicate(true)}
			response.error.merge({"code": identity.error.code, "message": identity.error.message}, true)
		else:
			hydrated_identity = identity.value
	if _status == NuxieStatus.Kind.CONFIGURING and _session == configuring_session:
		if response.has("error"):
			_customer = ""
			_snapshot.clear()
			_buffered.clear()
		_set_status(NuxieStatus.Kind.FAILED if response.has("error") else NuxieStatus.Kind.READY, _error(response))
	if not response.has("error") and hydrated_identity != null and _session == configuring_session and _status == NuxieStatus.Kind.READY and _identity_epoch == configuring_epoch:
		identity_changed.emit(hydrated_identity)
		if _session == configuring_session and _status == NuxieStatus.Kind.READY and _identity_epoch == configuring_epoch:
			features_changed.emit(get_feature_snapshot())
	if not response.has("error") and (_session != configuring_session or _status != NuxieStatus.Kind.READY):
		response = _error_wire("sdkShutdown", "Configuration interrupted by lifecycle callback")
	setup.finish(response)
	return _ack(response)

func shutdown() -> NuxieResult:
	if _status == NuxieStatus.Kind.UNCONFIGURED:
		return NuxieResult.new()
	if _status == NuxieStatus.Kind.SHUTTING_DOWN:
		return _ack(await _shutdown_waiter.wait())
	_shutdown_waiter = Waiter.new()
	var shutdown_waiter := _shutdown_waiter
	_identity_epoch += 1
	_identity_busy = false
	_checkout.clear()
	_customer = ""
	_snapshot.clear()
	_buffered.clear()
	_set_status(NuxieStatus.Kind.SHUTTING_DOWN)
	features_changed.emit(get_feature_snapshot())
	_cancel_pending("sdkShutdown", "Nuxie is shutting down; retry durable usage with the same operation ID")
	var response: Dictionary = await _request("shutdown", {})
	# A lost reply can mean native teardown is still running or already done.
	# Only an acknowledgement (including an expired native session) releases
	# ownership; other failures must leave the session available for retry.
	var detached := not response.has("error") or _error(response).code == "sessionExpired"
	if detached:
		_session = ""
		_configuration.clear()
		_controller = null
		response = {"result": null}
	_set_status(NuxieStatus.Kind.UNCONFIGURED if detached else NuxieStatus.Kind.FAILED, _error(response))
	shutdown_waiter.finish(response)
	return _ack(response)

func identify(customer_id: String, options: NuxieIdentityOptions = null) -> NuxieResult:
	if customer_id.strip_edges().is_empty():
		return _failure("invalidArgument", "Customer ID is required")
	if options == null:
		options = NuxieIdentityOptions.new()
	var props := {"properties": options.properties, "propertiesSetOnce": options.properties_set_once}
	if not Wire.valid_json(props):
		return _failure("invalidArgument", "Identity properties must be finite JSON values")
	return await _change_identity("identify", {"customerId": customer_id, "properties": JSON.stringify(props)})

func reset() -> NuxieResult:
	return await _change_identity("reset", {})

func _change_identity(method: String, arguments: Dictionary) -> NuxieResult:
	if _status != NuxieStatus.Kind.READY or _identity_busy:
		return _failure("lifecycleBusy", "Configure first and await any preceding identity change")
	_identity_busy = true
	_identity_epoch += 1
	var epoch := _identity_epoch
	_customer = ""
	_buffered.clear()
	var prior := _snapshot.duplicate(true)
	_snapshot = {"state": "unknown", "all": {}, "identityGeneration": prior.get("identityGeneration", "0"), "revision": prior.get("revision", "0")}
	features_changed.emit(get_feature_snapshot())
	if epoch != _identity_epoch or _status != NuxieStatus.Kind.READY:
		return _failure("identityChanged", "Identity change interrupted by lifecycle callback")
	var response: Dictionary = await _request(method, arguments)
	if epoch != _identity_epoch:
		return _failure("identityChanged", "Identity operation was superseded")
	_identity_busy = false
	if not response.has("error"):
		var data := Wire.object(response.get("result"))
		if not Wire.snapshot(data):
			response = _error_wire("invalidResponse", "Invalid identity snapshot")
		else:
			_snapshot.clear()
			_admit(data)
			if epoch != _identity_epoch:
				return _failure("identityChanged", "Identity changed during state notification")
			if not _buffered.is_empty():
				_admit(_buffered)
	if epoch != _identity_epoch:
		return _failure("identityChanged", "Identity changed during state notification")
	if not response.has("error"):
		var identity := await get_identity()
		if not identity.ok:
			return NuxieResult.new(identity.error)
	else:
		_buffered.clear()
	return _ack(response)

func get_identity() -> NuxieIdentityResult:
	return await _read_identity()

func _read_identity(during_setup: bool = false) -> NuxieIdentityResult:
	var epoch := _identity_epoch
	var response: Dictionary
	if during_setup:
		response = await _request("getIdentity", {})
	else:
		response = await _command("getIdentity", {})
	if epoch != _identity_epoch:
		return NuxieIdentityResult.new(null, NuxieError.new("identityChanged", "Identity changed during this query"))
	var failure := _error(response)
	var data := Wire.object(response.get("result"))
	if failure == null and not Wire.identity(data):
		failure = NuxieError.new("invalidResponse", "Invalid native identity")
	if failure != null:
		return NuxieIdentityResult.new(null, failure)
	_customer = data.distinctId
	if not during_setup:
		identity_changed.emit(NuxieIdentity.new(data))
	if epoch != _identity_epoch:
		return NuxieIdentityResult.new(null, NuxieError.new("identityChanged", "Identity changed during notification"))
	if not _buffered.is_empty():
		var buffered := _buffered.duplicate(true)
		_buffered.clear()
		_admit(buffered)
	elif not during_setup:
		features_changed.emit(get_feature_snapshot())
	if epoch != _identity_epoch:
		return NuxieIdentityResult.new(null, NuxieError.new("identityChanged", "Identity changed during feature notification"))
	return NuxieIdentityResult.new(NuxieIdentity.new(data))

func trigger(event_name: String, properties: Dictionary = {}) -> NuxieResult:
	if event_name.strip_edges().is_empty() or not Wire.valid_json(properties):
		return _failure("invalidArgument", "Supply an event name and finite JSON properties")
	return _ack(await _command("trigger", {"event": event_name, "properties": JSON.stringify(properties)}))

func dismiss() -> NuxieResult:
	return _ack(await _command("dismiss", {}))

func set_locale(locale: String = "") -> NuxieResult:
	return _ack(await _command("setLocaleIdentifier", {"locale": null if locale.is_empty() else locale}))

func check_feature(feature_id: String, query: NuxieFeatureQuery = null) -> NuxieFeatureResult:
	if query == null:
		query = NuxieFeatureQuery.new()
	if feature_id.strip_edges().is_empty() or query.required_balance < 1 or query.required_balance > Wire.MAX_QUANTITY or query.policy not in [0, 1]:
		return NuxieFeatureResult.new(null, NuxieError.new("invalidArgument", "Invalid feature query"))
	var epoch := _identity_epoch
	var response: Dictionary = await _command("hasFeature", {"featureId": feature_id, "options": JSON.stringify({"requiredBalance": query.required_balance, "entityId": null if query.entity_id.is_empty() else query.entity_id, "policy": "remote" if query.policy == NuxieFeatureQuery.Policy.REMOTE else "cacheFirst"})})
	var failure := _error(response)
	var data := Wire.object(response.get("result"))
	if epoch != _identity_epoch:
		failure = NuxieError.new("identityChanged", "Identity changed during feature query")
	elif failure == null and not Wire.access(data):
		failure = NuxieError.new("invalidResponse", "Invalid feature access response")
	return NuxieFeatureResult.new(NuxieFeatureAccess.new(data) if failure == null else null, failure)

func consume_feature(feature_id: String, command: NuxieFeatureCommand) -> NuxieUsageResult:
	if feature_id.strip_edges().is_empty() or command == null or command.operation_id.strip_edges().is_empty() or command.quantity < 1 or command.quantity > Wire.MAX_QUANTITY:
		return NuxieUsageResult.new(null, NuxieError.new("invalidArgument", "Feature, durable operation ID and positive integer quantity are required"))
	var operation := command.operation_id
	var quantity := command.quantity
	var response: Dictionary = await _command("consumeFeature", {"featureId": feature_id, "options": JSON.stringify({"operationId": operation, "quantity": quantity, "entityId": null if command.entity_id.is_empty() else command.entity_id})})
	var failure := _error(response)
	var data := Wire.object(response.get("result"))
	if failure == null and not Wire.receipt(data, feature_id, operation, quantity):
		failure = NuxieError.new("invalidResponse", "Receipt did not match the requested operation; retry the same ID")
	return NuxieUsageResult.new(NuxieUsageReceipt.new(data) if failure == null else null, failure)

func _command(method: String, arguments: Dictionary) -> Dictionary:
	if _status != NuxieStatus.Kind.READY or _identity_busy:
		return _error_wire("notConfigured", "Configure and await identity changes before using this command")
	return await _request(method, arguments)

func _request(method: String, arguments: Dictionary) -> Dictionary:
	_sequence += 1
	var id := "%s:%d" % [_session, _sequence]
	var waiter := Waiter.new()
	waiter.method = method
	waiter.deadline = Time.get_ticks_msec() + OPERATION_TIMEOUT_MS
	_pending[id] = waiter
	arguments = arguments.duplicate(true)
	arguments.session = _session
	_bridge.call("dispatch", JSON.stringify({"requestId": id, "method": method, "arguments": arguments}))
	return await waiter.wait()

func _process(_delta: float) -> void:
	if is_available():
		for _index in CALLBACK_BUDGET:
			var raw: Variant = _bridge.call("pop_message")
			if raw == null or raw == "":
				break
			_receive(raw)
	for checkout_id: String in _checkout.keys():
		if _checkout[checkout_id] <= Time.get_unix_time_from_system() * 1000:
			_checkout.erase(checkout_id)
	var now := Time.get_ticks_msec()
	for id: String in _pending.keys():
		if _pending.has(id) and _pending[id].deadline <= now:
			var waiter: RefCounted = _pending[id]
			_pending.erase(id)
			waiter.finish(_error_wire("operationTimeout", "Native operation timed out; durable usage may have completed. Retry the same operation ID."))

func _receive(raw: Variant) -> void:
	var envelope := Wire.object(raw)
	if envelope.has("requestId"):
		var id: Variant = envelope.requestId
		if not id is String or not _pending.has(id):
			return
		var waiter: RefCounted = _pending[id]
		_pending.erase(id)
		if not envelope.has("result") and not envelope.has("error"):
			envelope = _error_wire("invalidResponse", "Native response omitted its result")
		waiter.finish(envelope)
		return
	if envelope.get("session") != _session or _session.is_empty() or _status == NuxieStatus.Kind.SHUTTING_DOWN:
		return
	var payload := Wire.object(envelope.get("payload"))
	match envelope.get("name"):
		"features":
			if _identity_busy:
				if Wire.snapshot(payload) and (_buffered.is_empty() or _newer(payload, _buffered)):
					_buffered = payload.duplicate(true)
			else:
				_admit(payload)
		"activity":
			if payload.get("name") is String:
				activity_received.emit(NuxieActivity.new(payload))
		"appAction":
			if payload.get("name") is String and payload.get("experience") is Dictionary:
				app_action_received.emit(NuxieAppAction.new(payload))
		"purchase", "restore":
			_checkout_request(envelope.name, payload)

func _admit(data: Dictionary) -> void:
	if not Wire.snapshot(data):
		error_received.emit(NuxieError.new("invalidResponse", "Invalid feature snapshot"))
		return
	if _customer.is_empty():
		if _buffered.is_empty() or _newer(data, _buffered):
			_buffered = data.duplicate(true)
		return
	if not _snapshot.is_empty() and not _newer(data, _snapshot):
		return
	_snapshot = data.duplicate(true)
	if _status != NuxieStatus.Kind.CONFIGURING:
		features_changed.emit(get_feature_snapshot())

func _newer(a: Dictionary, b: Dictionary) -> bool:
	var generation := Wire.compare(a.identityGeneration, b.identityGeneration)
	return generation > 0 or (generation == 0 and Wire.compare(a.revision, b.revision) > 0)

func _checkout_request(kind: String, payload: Dictionary) -> void:
	var id: Variant = payload.get("requestId")
	if not id is String or id.is_empty() or _checkout.has(id):
		return
	var deadline: float = payload.get("deadlineMs", 0)
	if deadline <= Time.get_unix_time_from_system() * 1000:
		return
	_checkout[id] = deadline
	var session := _session
	var result: Variant
	if _controller == null:
		result = NuxiePurchaseResult.failed("External checkout controller unavailable") if kind == "purchase" else NuxieRestoreResult.failed("External checkout controller unavailable")
	elif kind == "purchase":
		result = await _controller.purchase(NuxieStoreProduct.new(Wire.object(payload.get("product"))))
	else:
		result = await _controller.restore()
	if session != _session or _status == NuxieStatus.Kind.SHUTTING_DOWN or deadline <= Time.get_unix_time_from_system() * 1000:
		return
	var valid := result is NuxiePurchaseResult if kind == "purchase" else result is NuxieRestoreResult
	var output: Dictionary = result._to_wire() if valid else {"type": "failed", "message": "Controller returned an invalid result"}
	await _request("completePurchase" if kind == "purchase" else "completeRestore", {"requestId": id, "result": JSON.stringify(output)})

func _cancel_pending(code: String, message: String) -> void:
	var pending := _pending.values()
	_pending.clear()
	for waiter: RefCounted in pending:
		waiter.finish(_error_wire(code, message))

func _set_status(kind: NuxieStatus.Kind, failure: NuxieError = null) -> void:
	_status = kind
	_last_error = failure
	status_changed.emit(get_status())

func _error_wire(code: String, message: String) -> Dictionary:
	return {"error": {"code": code, "message": message}}

func _error(response: Dictionary) -> NuxieError:
	if not response.has("error"):
		return null
	var value := Wire.object(response.error)
	return NuxieError.new(str(value.get("code", "nativeError")), str(value.get("message", "Native operation failed")), value)

func _ack(response: Dictionary) -> NuxieResult:
	return NuxieResult.new(_error(response))

func _failure(code: String, message: String) -> NuxieResult:
	return NuxieResult.new(NuxieError.new(code, message))
