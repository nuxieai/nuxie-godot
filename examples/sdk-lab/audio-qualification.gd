extends Node
## Opt-in development probe for the Lab's explicit pause-all-game-audio policy.

var _tone: AudioStreamPlayer
var _shown_at := -1.0
var _paused_position := 0.0
var _resumed_at := -1.0
var _resume_position := 0.0
var _baseline_passed := false
var _pause_passed := false
var _dismissed := false
var _finished := false

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	var wave := AudioStreamWAV.new()
	wave.format = AudioStreamWAV.FORMAT_16_BITS
	wave.mix_rate = 48000
	wave.loop_mode = AudioStreamWAV.LOOP_FORWARD
	wave.loop_end = 480000
	var samples := PackedByteArray()
	samples.resize(960000)
	for i in range(480000):
		var sample := int(sin(float(i) * TAU * 440.0 / 48000.0) * 3276.0)
		samples.encode_s16(i * 2, sample)
	wave.data = samples
	_tone = AudioStreamPlayer.new()
	_tone.process_mode = Node.PROCESS_MODE_PAUSABLE
	_tone.stream = wave
	add_child(_tone)
	_tone.play()
	Nuxie.activity_received.connect(_activity)

func _exit_tree() -> void:
	Nuxie.activity_received.disconnect(_activity)

func _activity(activity: NuxieActivity) -> void:
	if activity.name == "screen_shown" and _shown_at < 0.0:
		_shown_at = Time.get_ticks_msec() / 1000.0
		_paused_position = _tone.get_playback_position()
	elif activity.name in ["screen_dismissed", "journey_completed"] and _shown_at >= 0.0 and _resumed_at < 0.0:
		_resumed_at = Time.get_ticks_msec() / 1000.0
		_resume_position = _tone.get_playback_position()

func _process(_delta: float) -> void:
	if _finished:
		return
	var now := Time.get_ticks_msec() / 1000.0
	var position := _tone.get_playback_position()
	var peak_db := AudioServer.get_bus_peak_volume_left_db(0, 0)
	if _shown_at < 0.0 and not _baseline_passed and position > 0.2 and peak_db > -50.0:
		_baseline_passed = true
		print("NUXIE_GAME_AUDIO baseline position=", position, " peakDb=", AudioServer.get_bus_peak_volume_left_db(0, 0))
	if _shown_at >= 0.0 and not _dismissed and now - _shown_at > 8.0:
		_pause_passed = get_tree().paused and abs(position - _paused_position) < 0.03
		print("NUXIE_GAME_AUDIO presented paused=", get_tree().paused, " delta=", position - _paused_position, " pass=", _pause_passed)
		_dismissed = true
		Nuxie.dismiss.call_deferred()
	if _resumed_at >= 0.0 and now - _resumed_at > 0.5 and (peak_db > -50.0 or now - _resumed_at > 3.0):
		var resumed := not get_tree().paused and position - _resume_position > 0.1 and peak_db > -50.0
		_finished = true
		print("NUXIE_GAME_AUDIO completed pass=", _baseline_passed and _pause_passed and resumed, " resumed=", resumed, " delta=", position - _resume_position, " peakDb=", AudioServer.get_bus_peak_volume_left_db(0, 0))
		_tone.stop()
