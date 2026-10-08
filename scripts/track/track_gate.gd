class_name TrackGate
extends Node3D
## A locked gate across the rails (one per segment, "Gate_<segment>"): a heavy striped timber boom padlocked into
## a cradle (Blender model track_gate.glb), a red lantern, and a warning signal post GATE_SIGNAL metres before it.
## While locked, Track.blocking_distance() stops the train in front of it. The key (GateKey) lies beside the track.
## [E] on the padlock with the key: the padlock drops, the boom swings up, the lamps turn green.
## Placeholder for the quest-map mini-games that will guard each section later (GDD 7).

const OPEN_ANGLE := 82.0
const RED := Color(1.0, 0.12, 0.05)
const GREEN := Color(0.25, 1.0, 0.35)

var track: Track
var segment := 0
var locked := true

var _model: Node3D
var _boom: Node3D
var _padlock: Node3D
var _lamp: MeshInstance3D
var _lamp_light: OmniLight3D
var _signal: Node3D
var _signal_lens: MeshInstance3D
var _signal_light: OmniLight3D
var _sign: Label3D
var _lock_spot: GateLock
var _creak: AudioStreamPlayer3D
var _warned := false
var _padlock_rest := Transform3D.IDENTITY
var _boom_rest := 0.0


## The padlock / boom: what the player aims at to unlock the gate.
class GateLock extends Interactable:
	var gate: TrackGate

	func get_prompt(_player: Node) -> String:
		if not gate.locked:
			return ""
		if Game.has("key"):
			return "Unlock the gate with the key  [E]"
		return "Locked: find the key nearby (it glows beside the track)"

	func interact(player: Node) -> void:
		gate.try_unlock(player)


func setup(t: Track, seg: int, is_locked: bool) -> void:
	track = t
	segment = seg
	locked = is_locked
	name = "Gate_%d" % seg


func _ready() -> void:
	global_transform = track.transform_at(track.gate_distance(segment))
	_model = Props.instance("track_gate")
	add_child(_model)
	_boom = _model.find_child("Boom", true, false)
	_padlock = _model.find_child("Padlock", true, false)
	if _padlock:
		_padlock_rest = _padlock.transform
	if _boom:
		_boom_rest = _boom.rotation.z
	_lamp = _model.find_child("Lamp", true, false) as MeshInstance3D
	if _lamp == null and _model.find_child("Lamp", true, false):
		_lamp = _model.find_child("Lamp", true, false).find_children("*", "MeshInstance3D", true, false)[0]
	_lamp_light = _light(self, Vector3(-2.35, 2.0, 0.2), 6.0)

	_sign = Build.label(self, "LOCKED\nkey nearby", Vector3(0, 2.6, 0), 56)
	_sign.modulate = Color(1.0, 0.85, 0.75)
	_sign.outline_modulate = Color(0.25, 0.05, 0.02)

	_lock_spot = GateLock.new()
	_lock_spot.name = "Lock"
	_lock_spot.gate = self
	# covers the boom across the track and the padlock on the far post
	Build.collider(_lock_spot, Vector3(5.4, 0.9, 1.0), Vector3(0.1, 0.95, 0.1))
	add_child(_lock_spot)

	_build_signal()

	_creak = AudioStreamPlayer3D.new()
	_creak.stream = _make_creak()
	_creak.unit_size = 8.0
	_creak.position = Vector3(-2.3, 1.0, 0)
	if AudioServer.get_bus_index("SFX") >= 0:
		_creak.bus = "SFX"
	add_child(_creak)

	track.gate_opened.connect(_on_gate_opened)
	if not locked:
		_set_open_pose()
	_set_lamps(locked)


## Warning signal post at the right of the track, GATE_SIGNAL metres before the gate.
func _build_signal() -> void:
	_signal = Props.instance("gate_signal")
	_signal.name = "Signal"
	add_child(_signal)
	_signal.top_level = true
	var d := track.gate_distance(segment) - Track.GATE_SIGNAL
	var t := track.transform_at(d)
	var pos := track.ground_point(d, 2.9)
	_signal.global_transform = Transform3D(t.basis, Vector3(pos.x, maxf(pos.y, t.origin.y - 0.4), pos.z))
	var lens := _signal.find_child("Lens", true, false)
	if lens is MeshInstance3D:
		_signal_lens = lens
	elif lens:
		_signal_lens = lens.find_children("*", "MeshInstance3D", true, false)[0]
	_signal_light = _light(_signal, Vector3(0, 3.32, 0.35), 9.0)


func _light(parent: Node3D, pos: Vector3, range_m: float) -> OmniLight3D:
	var l := OmniLight3D.new()
	l.position = pos
	l.omni_range = range_m
	l.light_energy = 1.6
	l.shadow_enabled = false
	parent.add_child(l)
	return l


func _set_lamps(red: bool) -> void:
	var col := RED if red else GREEN
	var m := StandardMaterial3D.new()
	m.albedo_color = col
	m.emission_enabled = true
	m.emission = col
	m.emission_energy_multiplier = 4.0
	for mesh: MeshInstance3D in [_lamp, _signal_lens]:
		if mesh:
			mesh.material_override = m
	_lamp_light.light_color = col
	_signal_light.light_color = col


func try_unlock(_player: Node) -> bool:
	if not locked:
		return false
	if not Game.take("key"):
		Game.say("Locked: find the key nearby (look for the glowing key beside the track)")
		return false
	track.open_gate(segment)
	Game.say("Gate unlocked! The line is clear, drive on")
	return true


func _on_gate_opened(seg: int) -> void:
	if seg != segment or not locked:
		return
	locked = false
	_lock_spot.collision_layer = 0
	_sign.text = "OPEN"
	_sign.modulate = Color(0.75, 1.0, 0.75)
	var fade := _sign.create_tween()
	fade.tween_interval(2.5)
	fade.tween_property(_sign, "modulate:a", 0.0, 1.0)
	fade.tween_callback(func(): _sign.visible = false)
	_set_lamps(false)
	if _creak and is_inside_tree():
		_creak.play()
	# the padlock drops off the hasp, then the boom swings up about its hinge pin
	var tween := create_tween()
	if _padlock:
		tween.tween_property(_padlock, "position:y", _padlock.position.y - 0.85, 0.35).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
		tween.parallel().tween_property(_padlock, "rotation:x", 1.2, 0.35)
		tween.tween_property(_padlock, "rotation:z", 1.5, 0.15)
	if _boom:
		tween.tween_interval(0.15)
		tween.tween_property(_boom, "rotation:z", deg_to_rad(OPEN_ANGLE), 1.6).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


## NET: back to locked (the host still has this gate locked): boom down, padlock on, red lamps.
func relock() -> void:
	locked = true
	_warned = false
	_lock_spot.collision_layer = Build.LAYER_INTERACT
	_sign.text = "LOCKED\nkey nearby"
	_sign.modulate = Color(1.0, 0.85, 0.75)
	_sign.visible = true
	if _boom:
		_boom.rotation.z = _boom_rest
	if _padlock:
		_padlock.transform = _padlock_rest
		_padlock.visible = true
	_set_lamps(true)


func _set_open_pose() -> void:
	_lock_spot.collision_layer = 0
	_sign.visible = false
	if _boom:
		_boom.rotation.z = deg_to_rad(OPEN_ANGLE)
	if _padlock:
		_padlock.visible = false


func _physics_process(_delta: float) -> void:
	# a train passing the red signal at speed gets a warning
	var train := Game.train
	if not locked or _warned or train == null or train.track != track:
		return
	var g := track.gate_distance(segment)
	if train.distance > g - Track.GATE_SIGNAL and train.distance < g and train.speed > 1.0:
		_warned = true
		Game.say("Red signal: LOCKED GATE ahead! Slow down (lever to STOP)")


## A short wooden creak + iron clunk made in code (there are no sound files yet).
static func _make_creak() -> AudioStreamWAV:
	var rate := 22050
	var n := int(rate * 1.1)
	var data := PackedByteArray()
	data.resize(n * 2)
	var rng := RandomNumberGenerator.new()
	rng.seed = 11
	var phase := 0.0
	for i in n:
		var t := float(i) / rate
		var s := 0.0
		if t < 0.12:
			# clunk: the padlock hits the ground
			s = sin(TAU * 90.0 * t) * exp(-t * 30.0) * 0.8 + rng.randf_range(-1, 1) * exp(-t * 60.0) * 0.4
		else:
			# creak: a rough, wavering low tone while the boom swings
			var k := t - 0.12
			var f := 140.0 + 60.0 * sin(k * 9.0) + 30.0 * sin(k * 23.0)
			phase += TAU * f / rate
			var saw := fmod(phase / TAU, 1.0) * 2.0 - 1.0
			s = saw * 0.35 * sin(PI * clampf(k / 0.95, 0.0, 1.0)) * (0.7 + 0.3 * sin(k * 60.0))
		var v := int(clampf(s, -1.0, 1.0) * 30000.0)
		data.encode_s16(i * 2, v)
	var wav := AudioStreamWAV.new()
	wav.format = AudioStreamWAV.FORMAT_16_BITS
	wav.mix_rate = rate
	wav.stereo = false
	wav.data = data
	return wav
