class_name Voice
extends Node
## Proximity voice chat for online runs (child of the Net autoload).
## Push-to-talk (the "push_to_talk" action, V by default): the microphone plays into the muted "Mic" bus, an
## AudioEffectCapture there gives us the samples, we mix them down to 16 kHz mono, squeeze them to 8-bit mu-law and send
## 20 ms frames by unreliable RPC to everyone. Each frame plays on a 3D AudioStreamGenerator (Voice bus) at the
## speaker's body, so voices come from where people stand. CrewList / RemoteBody show who is speaking.
## Needs audio/driver/enable_input = true (the Settings workstream turns it on) and a microphone; otherwise it stays off.

const RATE := 16000
const FRAME := 320            # samples per packet (20 ms)
const SPEAKING_HOLD := 0.35   # seconds a speaker icon stays after the last packet
const MIC_BUS := "Mic"
const VOICE_BUS := "Voice"

var enabled := true
var _mic: AudioStreamPlayer
var _capture: AudioEffectCapture
var _talking := false
var _phase := 0.0
var _pending := PackedFloat32Array()
var _last_heard := {}          # peer id -> seconds since start when we last heard them
var _clock := 0.0
var _available := false
var _checked := false


func _process(delta: float) -> void:
	_clock += delta
	if not _checked:
		_checked = true
		_available = _can_capture()
	# the Settings mic test reads the same capture buffer: voice pauses while it runs
	var want := _available and enabled and Net.is_online() and Net.run_active and MicMeter.active == 0 and _wants_to_talk()
	if want != _talking:
		_set_talking(want)
	if _talking:
		_last_heard[Net.local_id()] = _clock
		_pump()
	_update_bodies()


func is_speaking(id: int) -> bool:
	return _last_heard.has(id) and _clock - float(_last_heard[id]) < SPEAKING_HOLD


func _wants_to_talk() -> bool:
	if not InputMap.has_action("push_to_talk"):
		var ev := InputEventKey.new()
		ev.physical_keycode = KEY_V
		InputMap.add_action("push_to_talk")
		InputMap.action_add_event("push_to_talk", ev)
	# Settings > Microphone: push-to-talk off = open microphone while in a run
	if not bool(Settings.get_value("mic", "push_to_talk", true)):
		return true
	if Game.ui_open:
		return false
	return Input.is_action_pressed("push_to_talk")


func _can_capture() -> bool:
	if DisplayServer.get_name() == "headless":
		return false
	if not ProjectSettings.get_setting("audio/driver/enable_input", false):
		print("[voice] microphone input is off (audio/driver/enable_input): voice chat disabled")
		return false
	return true


func _set_talking(on: bool) -> void:
	_talking = on
	if on:
		_ensure_mic()
		_capture.clear_buffer()
		_phase = 0.0
		_pending.clear()
		_mic.play()
	elif _mic:
		_mic.stop()


## The muted Mic bus with a capture effect (made here if the Settings bus layout has none).
func _ensure_mic() -> void:
	if _mic:
		return
	var bus := AudioServer.get_bus_index(MIC_BUS)
	if bus == -1:
		AudioServer.add_bus()
		bus = AudioServer.bus_count - 1
		AudioServer.set_bus_name(bus, MIC_BUS)
	AudioServer.set_bus_mute(bus, true)
	for i in AudioServer.get_bus_effect_count(bus):
		if AudioServer.get_bus_effect(bus, i) is AudioEffectCapture:
			_capture = AudioServer.get_bus_effect(bus, i)
	if _capture == null:
		_capture = AudioEffectCapture.new()
		AudioServer.add_bus_effect(bus, _capture)
	_mic = AudioStreamPlayer.new()
	_mic.stream = AudioStreamMicrophone.new()
	_mic.bus = MIC_BUS
	add_child(_mic)


## Reads the captured stereo samples, resamples to 16 kHz mono and sends whole 20 ms frames.
func _pump() -> void:
	var frames := _capture.get_frames_available()
	if frames <= 0:
		return
	var buf := _capture.get_buffer(frames)
	var step := float(RATE) / AudioServer.get_mix_rate()
	for s in buf:
		_phase += step
		if _phase >= 1.0:
			_phase -= 1.0
			_pending.append((s.x + s.y) * 0.5)
	while _pending.size() >= FRAME:
		var packet := PackedByteArray()
		packet.resize(FRAME)
		for i in FRAME:
			packet[i] = _mulaw_encode(_pending[i])
		_pending = _pending.slice(FRAME)
		_rpc_voice.rpc(packet)


@rpc("any_peer", "call_remote", "unreliable_ordered", 2)
func _rpc_voice(packet: PackedByteArray) -> void:
	var from := multiplayer.get_remote_sender_id()
	var body := Net.player_node(from)
	if body == null or packet.size() > FRAME * 4:
		return
	_last_heard[from] = _clock
	var out: AudioStreamPlayer3D = body.get_node_or_null("VoiceOut")
	if out == null:
		out = AudioStreamPlayer3D.new()
		out.name = "VoiceOut"
		var gen := AudioStreamGenerator.new()
		gen.mix_rate = RATE
		gen.buffer_length = 0.4
		out.stream = gen
		out.position = Vector3(0, 1.65, 0)
		out.unit_size = 6.0
		out.max_distance = 60.0
		if AudioServer.get_bus_index(VOICE_BUS) != -1:
			out.bus = VOICE_BUS
		body.add_child(out)
		out.play()
	var playback := out.get_stream_playback() as AudioStreamGeneratorPlayback
	if playback == null:
		return
	var samples := PackedVector2Array()
	samples.resize(packet.size())
	for i in packet.size():
		var v := _mulaw_decode(packet[i])
		samples[i] = Vector2(v, v)
	if playback.can_push_buffer(samples.size()):
		playback.push_buffer(samples)


func _update_bodies() -> void:
	for id: int in Net.players:
		var p := Net.player_node(id)
		if p and p.has_method("set_speaking"):
			p.set_speaking(is_speaking(id))


# --- mu-law (G.711) ---------------------------------------------------------------

static func _mulaw_encode(x: float) -> int:
	var s := clampf(x, -1.0, 1.0)
	var mag := log(1.0 + 255.0 * absf(s)) / log(256.0)
	var q := int(roundf(mag * 127.0))
	return (q | 128) if s < 0.0 else q


static func _mulaw_decode(b: int) -> float:
	var q := float(b & 127) / 127.0
	var mag := (pow(256.0, q) - 1.0) / 255.0
	return -mag if b & 128 else mag
