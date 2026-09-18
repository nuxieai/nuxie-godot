extends Control
## A real mobile client. Every API check uses the public addon and native backend.

const LabTheme = preload("lab-theme.gd")

var _settings: Dictionary = {}
var _log: RichTextLabel
var _state: Label
var _energy: Label
var _action: Button
var _inputs: Dictionary[String, LineEdit] = {}
var _running := false
var _results: Array[Dictionary] = []
var _screens: Dictionary = {}
var _saved_pause := false
var _owns_pause := false
var _score := 0

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_settings = _read_json("res://local-settings.json")
	if _settings.is_empty():
		_settings = _read_json("user://settings.json")
	theme = LabTheme.create()
	_score = int(_read_json("user://progress.json").get("score", 0))
	_build_ui()
	Nuxie.features_changed.connect(_features_changed)
	Nuxie.activity_received.connect(_activity_received)
	Nuxie.app_action_received.connect(_app_action_received)
	Nuxie.error_received.connect(_error_received)
	_features_changed(Nuxie.get_feature_snapshot())
	if _settings.get("autorun", false):
		_run_checks.call_deferred()
	elif _settings.get("autoConnect", false):
		_configure_sdk.call_deferred()

func _exit_tree() -> void:
	Nuxie.features_changed.disconnect(_features_changed)
	Nuxie.activity_received.disconnect(_activity_received)
	Nuxie.app_action_received.disconnect(_app_action_received)
	Nuxie.error_received.disconnect(_error_received)
	if _owns_pause:
		get_tree().paused = _saved_pause

func _build_ui() -> void:
	var background := ColorRect.new()
	background.color = LabTheme.BACKGROUND
	background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(background)
	var scroll := ScrollContainer.new()
	scroll.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	scroll.offset_left = 24
	scroll.offset_top = 48
	scroll.offset_right = -24
	scroll.offset_bottom = -32
	add_child(scroll)
	var column := VBoxContainer.new()
	column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	column.add_theme_constant_override("separation", 16)
	scroll.add_child(column)
	var title := Label.new()
	title.text = "Nuxie / Godot"
	title.add_theme_font_size_override("font_size", 32)
	column.add_child(title)
	var subtitle := Label.new()
	subtitle.text = "A little game. Real native access."
	subtitle.modulate = LabTheme.MUTED_FOREGROUND
	column.add_child(subtitle)
	_state = Label.new()
	_state.text = "Connect your development app"
	column.add_child(_state)
	_energy = Label.new()
	_energy.text = "Energy —  ·  Score 0"
	_energy.add_theme_font_size_override("font_size", 24)
	column.add_child(_energy)
	_action = _button(column, "Play a turn · 1 energy", _play_turn)
	_action.theme_type_variation = "PrimaryButton"
	_action.disabled = true
	var settings_panel := VBoxContainer.new()
	settings_panel.add_theme_constant_override("separation", 8)
	settings_panel.visible = false
	_button(column, "Development settings", func() -> void: settings_panel.visible = not settings_panel.visible)
	column.add_child(settings_panel)
	for field: String in ["iosApiKey", "androidApiKey", "customerId", "featureId", "entityA", "entityB", "triggerEvent"]:
		var input := LineEdit.new()
		input.placeholder_text = field
		input.text = str(_settings.get(field, ""))
		input.secret = field.ends_with("ApiKey")
		input.custom_minimum_size.y = 42
		settings_panel.add_child(input)
		_inputs[field] = input
	_button(column, "Connect", _connect_sdk)
	_button(column, "Run API checks · spends 1 unit", _run_checks)
	var row := HBoxContainer.new()
	column.add_child(row)
	_button(row, "Open Experience", _open_experience)
	_button(row, "Dismiss", _dismiss)
	var tools := HBoxContainer.new()
	column.add_child(tools)
	_button(tools, "Change scene", _change_scene)
	_button(tools, "Sign out", _reset)
	_button(tools, "Shutdown", _shutdown)
	_log = RichTextLabel.new()
	_log.custom_minimum_size.y = 250
	_log.fit_content = true
	column.add_child(_log)
	_note("Mobile backend validation. Editor calls report unsupported platform.")

func _button(parent: Node, title: String, callback: Callable) -> Button:
	var button := Button.new()
	button.text = title
	button.custom_minimum_size.y = 46
	button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	button.pressed.connect(callback)
	parent.add_child(button)
	return button

func _capture_settings() -> void:
	for field: String in _inputs:
		_settings[field] = _inputs[field].text.strip_edges()
	_write_json("user://settings.json", _settings)

func _configure_sdk() -> bool:
	_capture_settings()
	var options := NuxieOptions.new()
	options.ios_api_key = _settings.get("iosApiKey", "")
	options.android_api_key = _settings.get("androidApiKey", "")
	options.environment = NuxieOptions.EnvironmentKind.DEVELOPMENT
	var setup := await Nuxie.configure(options)
	if not _result("Configure", setup):
		return false
	var identified := await Nuxie.identify(_settings.get("customerId", ""))
	if not _result("Identify", identified):
		return false
	return true

func _connect_sdk() -> bool:
	if not await _configure_sdk():
		return false
	var deadline := Time.get_ticks_msec() + 20000
	while Nuxie.get_feature_snapshot().kind != NuxieFeatureState.Kind.READY and Time.get_ticks_msec() < deadline:
		await get_tree().process_frame
	var ready := _record("Feature authority ready", Nuxie.get_feature_snapshot().kind == NuxieFeatureState.Kind.READY)
	if ready:
		var access := await _query(_settings.get("entityA", ""))
		if access.ok:
			_energy.text = "Energy %s  ·  Score %d" % [str(access.value.balance), _score]
	return ready

func _query(entity: String) -> NuxieFeatureResult:
	var query := NuxieFeatureQuery.new()
	query.entity_id = entity
	query.policy = NuxieFeatureQuery.Policy.REMOTE
	return await Nuxie.check_feature(_settings.get("featureId", ""), query)

func _run_checks() -> void:
	if _running:
		return
	_running = true
	_results.clear()
	if not await _connect_sdk():
		_finish_checks()
		return
	var identity := await Nuxie.get_identity()
	if not _result("Read identity", identity):
		_finish_checks()
		return
	var first := await _query(_settings.get("entityA", ""))
	var other := await _query(_settings.get("entityB", ""))
	if not _result("Query entity A", first) or not _result("Query entity B", other):
		_finish_checks()
		return
	if not _record("Disposable metered grant", first.value.allowed and not first.value.unlimited and first.value.balance != null):
		_finish_checks()
		return
	var command := NuxieFeatureCommand.new()
	command.entity_id = _settings.get("entityA", "")
	command.operation_id = "godot-lab-" + Crypto.new().generate_random_bytes(16).hex_encode()
	_write_json("user://pending-action.json", {"operationId": command.operation_id, "customerId": identity.value.distinct_id, "featureId": _settings.get("featureId"), "entityId": command.entity_id})
	var receipt := await Nuxie.consume_feature(_settings.get("featureId", ""), command)
	if not _result("Consume", receipt):
		_finish_checks()
		return
	_record("Accepted original receipt", receipt.value.accepted and receipt.value.operation_id == command.operation_id and receipt.value.customer_id == identity.value.distinct_id and receipt.value.quantity == 1)
	var replay := await Nuxie.consume_feature(_settings.get("featureId", ""), command)
	if _result("Retry same operation", replay):
		_record("Original decision preserved", replay.value.idempotent_replay and replay.value.accepted == receipt.value.accepted and replay.value.balance == receipt.value.balance and replay.value.occurred_at_ms == receipt.value.occurred_at_ms)
	var after := await _query(command.entity_id)
	var other_after := await _query(_settings.get("entityB", ""))
	if _result("Query debited entity", after):
		_record("Exactly one debit", after.value.balance == first.value.balance - 1)
	if _result("Query isolated entity", other_after):
		_record("Entity B unchanged", other_after.value.balance == other.value.balance)
	_result("Locale override", await Nuxie.set_locale("fr_FR"))
	_result("Device locale", await Nuxie.set_locale())
	_result("Reset", await Nuxie.reset())
	var reset_identity := await Nuxie.get_identity()
	if _result("Anonymous identity", reset_identity):
		_record("Anonymous ID rotated", not reset_identity.value.is_identified and reset_identity.value.anonymous_id != identity.value.anonymous_id)
	_result("Reidentify", await Nuxie.identify(_settings.get("customerId", "")))
	_finish_checks()

func _finish_checks() -> void:
	_running = false
	var failures := _results.filter(func(item: Dictionary) -> bool: return not item.passed).size()
	var report := {"platform": OS.get_name(), "results": _results, "failures": failures, "timestamp": Time.get_datetime_string_from_system()}
	_write_json("user://validation.json", report)
	_note("API CHECKS COMPLETE: %d checks, %d failures" % [_results.size(), failures])
	print("NUXIE_GODOT_VALIDATION " + JSON.stringify(report))

func _play_turn() -> void:
	if _running or _owns_pause:
		return
	_running = true
	var identity := await Nuxie.get_identity()
	if not identity.ok or not identity.value.is_identified or identity.value.distinct_id != _settings.get("customerId"):
		_note("Connect the selected player before spending or recovering a turn.")
		_running = false
		return
	var pending := _read_json("user://game-action.json")
	if pending.is_empty():
		pending = {"id": Crypto.new().generate_random_bytes(16).hex_encode(), "customer": identity.value.distinct_id, "feature": _settings.get("featureId"), "entity": _settings.get("entityA")}
		if not _write_json("user://game-action.json", pending):
			_note("Could not save this turn. No energy was spent.")
			_running = false
			return
	if pending.get("customer") != identity.value.distinct_id:
		_note("Saved turn belongs to another player; reconnect that player to recover it.")
		_running = false
		return
	var command := NuxieFeatureCommand.new()
	command.operation_id = pending.id
	command.entity_id = pending.entity
	var result := await Nuxie.consume_feature(pending.feature, command)
	if result.ok and result.value.customer_id != pending.customer:
		_note("Receipt customer does not match saved turn. Preserving it for recovery.")
		_running = false
		return
	if _result("Play turn", result) and result.value.accepted:
		var progress := _read_json("user://progress.json")
		if progress.get("lastAction") != pending.id:
			progress = {"lastAction": pending.id, "score": int(progress.get("score", 0)) + 1}
			if not _write_json("user://progress.json", progress):
				_note("Turn accepted; reconnect to retry saving your progress.")
				_running = false
				return
		_score = progress.score
		DirAccess.remove_absolute("user://game-action.json")
		_energy.text = "Energy %s  ·  Score %d" % [str(result.value.balance), _score]
	elif result.ok:
		# A rejected receipt is final for this operation, so the next turn needs a new ID.
		DirAccess.remove_absolute("user://game-action.json")
	_running = false

func _features_changed(_snapshot: NuxieFeatureSnapshot) -> void:
	var state := Nuxie.get_feature_state(_settings.get("featureId", "energy"))
	_state.text = ["Waiting for access", "Reconciling access", "Connected · native authority"][state.kind]
	_action.disabled = state.kind == NuxieFeatureState.Kind.UNKNOWN or _owns_pause

func _activity_received(activity: NuxieActivity) -> void:
	_note("Activity: " + activity.name)
	var journey: String = str(activity.properties.get("journey_id", ""))
	if activity.name == "journey_completed":
		for key: String in _screens.keys():
			if key.begins_with(journey + ":"):
				_screens.erase(key)
		if _screens.is_empty() and _owns_pause:
			get_tree().paused = _saved_pause
			_owns_pause = false
		_features_changed(Nuxie.get_feature_snapshot())
		return
	var screen_id: String = str(activity.properties.get("screen_id", ""))
	if screen_id.is_empty():
		return
	var screen := journey + ":" + screen_id
	if activity.name == "screen_shown":
		if not _owns_pause:
			_saved_pause = get_tree().paused
			_owns_pause = true
		_screens[screen] = true
		get_tree().paused = true
	elif activity.name == "screen_dismissed":
		_screens.erase(screen)
		var revealed: String = str(activity.properties.get("revealing_screen_id", ""))
		if not revealed.is_empty():
			_screens[journey + ":" + revealed] = true
		if _screens.is_empty() and _owns_pause:
			get_tree().paused = _saved_pause
			_owns_pause = false
	_features_changed(Nuxie.get_feature_snapshot())

func _app_action_received(action: NuxieAppAction) -> void:
	_note("APP ACTION: " + action.name + " " + JSON.stringify(action.payload))
	_write_json("user://last-app-action.json", {"name": action.name, "payload": action.payload, "experienceId": action.experience.experience_id})

func _error_received(error: NuxieError) -> void:
	_note(error.code + ": " + error.message)

func _open_experience() -> void:
	_result("Trigger", await Nuxie.trigger(_settings.get("triggerEvent", ""), {"source": "godot_sdk_lab"}))

func _dismiss() -> void:
	_result("Dismiss", await Nuxie.dismiss())

func _reset() -> void:
	_result("Sign out", await Nuxie.reset())

func _shutdown() -> void:
	_result("Shutdown", await Nuxie.shutdown())
	_screens.clear()
	if _owns_pause:
		get_tree().paused = _saved_pause
		_owns_pause = false
	_features_changed(Nuxie.get_feature_snapshot())

func _change_scene() -> void:
	get_tree().change_scene_to_file("res://startup.tscn")

func _result(label: String, result: NuxieResult) -> bool:
	return _record(label, result.ok, "" if result.ok else result.error.code + ": " + result.error.message)

func _record(label: String, passed: bool, details: String = "") -> bool:
	_results.append({"name": label, "passed": passed, "details": details})
	_note(("PASS " if passed else "FAIL ") + label + " " + details)
	return passed

func _note(message: String) -> void:
	_log.append_text(message + "\n")
	print("NUXIE_GODOT_LAB " + message)

func _read_json(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {}
	var value: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	return value if value is Dictionary else {}

func _write_json(path: String, value: Dictionary) -> bool:
	# Keep the previous durable record intact until the replacement is complete.
	var temporary := path + ".tmp"
	var file := FileAccess.open(temporary, FileAccess.WRITE)
	if file == null:
		return false
	file.store_string(JSON.stringify(value, "  "))
	file.flush()
	var success := file.get_error() == OK
	file.close()
	return success and DirAccess.rename_absolute(temporary, path) == OK
