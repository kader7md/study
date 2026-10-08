class_name Viewmodel
extends Node3D
## First-person hands (big chunky cartoon arms), the held tool and carried items. A child of the player's
## camera; Player calls it (select_tool, play, set_welding, carry, drop_carry) and never moves the arms itself.
##
## Every pose is rebuilt each frame: rest pose of the tool (or carry pose) + idle breathing sway + walk bob
## + the current one-shot animation + the tool-switch lower/raise. Animations are keyframed below (ANIMS):
##   hammer      wind-up over the shoulder, a fast downward strike, a camera kick on impact
##   wrench      fit onto the nut, a 90° wrist twist with a ratchet tick, back
##   nail_gun    a sharp recoil with the muzzle rising and settling, a puff and a flash
##   come_along  a two-handed pump on the ratchet handle
##   welder      (continuous) a steady two-handed hold with micro-shake, sparks and a flickering blue-white light
## Carry poses: plank on the shoulder, rail held low with a strained bob, wheel in front with a wobble,
## panel flat at chest height. Placing an item lowers it out of view.

const SKIN := Color(1.0, 0.76, 0.6)
const SLEEVE := Color(0.85, 0.55, 0.3)
const RIGHT_REST := Vector3(0.42, -0.42, -0.62)
const LEFT_REST := Vector3(-0.42, -0.42, -0.62)
## Glove + sleeve size: small enough that the tool, not the glove, reads at mid-swing.
const ARM_SCALE := 0.92
const SWITCH_TIME := 0.34
const DROP_TIME := 0.24

## One-shot animations: duration, the moment (0..1) of the impact / tick, and keyframes
## [t, right arm position offset, forearm rotation offset, wrist (tool) rotation offset] (radians).
## The forearm moves a little, the wrist does most of the swing (so the tool, not the sleeve, fills the view).
## two_handed: the left hand follows the right one.
const ANIMS := {
	"hammer": {"len": 0.46, "event": 0.5, "keys": [
		[0.0, Vector3.ZERO, Vector3.ZERO, Vector3.ZERO],
		[0.36, Vector3(0.05, 0.16, 0.1), Vector3(0.4, 0.0, 0.25), Vector3(0.95, 0.45, 0.1)],
		[0.5, Vector3(-0.02, -0.1, -0.15), Vector3(-0.35, 0.0, 0.05), Vector3(-1.25, 0.0, 0.0)],
		[0.62, Vector3(-0.02, -0.09, -0.14), Vector3(-0.3, 0.0, 0.05), Vector3(-1.1, 0.0, 0.0)],
		[1.0, Vector3.ZERO, Vector3.ZERO, Vector3.ZERO]]},
	"wrench": {"len": 0.6, "event": 0.62, "keys": [
		[0.0, Vector3.ZERO, Vector3.ZERO, Vector3.ZERO],
		[0.25, Vector3(-0.12, 0.07, -0.12), Vector3(-0.2, 0.0, 0.0), Vector3(-0.6, 0.0, 0.0)],
		[0.62, Vector3(-0.13, 0.05, -0.13), Vector3(-0.2, 0.0, -0.3), Vector3(-0.85, 0.0, -1.0)],
		[0.74, Vector3(-0.13, 0.05, -0.13), Vector3(-0.2, 0.0, -0.3), Vector3(-0.85, 0.0, -1.0)],
		[1.0, Vector3.ZERO, Vector3.ZERO, Vector3.ZERO]]},
	"nail_gun": {"len": 0.3, "event": 0.0, "keys": [
		[0.0, Vector3.ZERO, Vector3.ZERO, Vector3.ZERO],
		[0.1, Vector3(0.0, 0.025, 0.09), Vector3(0.2, 0.0, 0.04), Vector3(0.35, 0.0, 0.0)],
		[0.42, Vector3(0.0, -0.006, -0.012), Vector3(-0.04, 0.0, 0.0), Vector3(-0.05, 0.0, 0.0)],
		[1.0, Vector3.ZERO, Vector3.ZERO, Vector3.ZERO]]},
	"come_along": {"len": 0.56, "event": 0.68, "two_handed": true, "keys": [
		[0.0, Vector3.ZERO, Vector3.ZERO, Vector3.ZERO],
		[0.38, Vector3(0.0, 0.14, 0.05), Vector3(0.45, 0.0, 0.0), Vector3(0.6, 0.0, 0.0)],
		[0.68, Vector3(0.0, -0.08, -0.04), Vector3(-0.2, 0.0, 0.0), Vector3(-0.3, 0.0, 0.0)],
		[1.0, Vector3.ZERO, Vector3.ZERO, Vector3.ZERO]]},
}

## Carry poses: model position / rotation / scale, and where the two hands grip.
const CARRY := {
	"plank": {"pos": Vector3(0.3, -0.17, -0.38), "rot": Vector3(0.1, PI * 0.5 + 0.06, 0.04), "scale": 0.55,
		"right": Vector3(0.28, -0.31, -0.42), "left": Vector3(0.12, -0.27, -0.82)},
	"rail": {"pos": Vector3(0.02, -0.64, -0.8), "rot": Vector3(0.05, 0.14, 0.03), "scale": Vector3(1.7, 1.7, 0.55),
		"right": Vector3(0.13, -0.55, -0.5), "left": Vector3(-0.08, -0.56, -0.98)},
	"wheel": {"pos": Vector3(0.0, -0.4, -0.78), "rot": Vector3(0.0, PI * 0.5, 0.0), "scale": 0.7,
		"right": Vector3(0.3, -0.42, -0.74), "left": Vector3(-0.3, -0.42, -0.74)},
	"panel": {"pos": Vector3(0.0, -0.44, -0.86), "rot": Vector3(-PI * 0.5 + 0.18, 0.0, 0.0), "scale": 0.6,
		"right": Vector3(0.46, -0.44, -0.8), "left": Vector3(-0.46, -0.44, -0.8)},
}

var player: CharacterBody3D
var camera: Camera3D
var right: Node3D
var left: Node3D
var tool := "hammer"
var carry_item := ""
var welding := false

var _tool_models := {}
var _tool_rest_rot := {}
var _carry_model: Node3D
var _sparks: CPUParticles3D
var _weld_light: OmniLight3D
var _puff: CPUParticles3D
var _flash: OmniLight3D
var _anim := ""
var _anim_t := 1.0
var _event_done := true
var _switch_t := 1.0
var _shown_tool := "hammer"
var _drop_t := 1.0
var _drop_item := ""
var _time := 0.0
var _bob_phase := 0.0
var _bob := 0.0
var _kick := 0.0
var _sfx: AudioStreamPlayer
var _sounds := {}


func setup(p: CharacterBody3D, cam: Camera3D) -> void:
	player = p
	camera = cam
	right = Node3D.new()
	right.name = "RightArm"
	right.position = RIGHT_REST
	add_child(right)
	_arm(right)
	left = Node3D.new()
	left.name = "LeftArm"
	left.position = LEFT_REST
	add_child(left)
	_arm(left)
	left.visible = false
	_build_tools()
	_sfx = AudioStreamPlayer.new()
	_sfx.volume_db = -6.0
	if AudioServer.get_bus_index("SFX") >= 0:
		_sfx.bus = "SFX"
	add_child(_sfx)
	_sounds = {"thunk": _make_sound("thunk"), "tick": _make_sound("tick"), "puff": _make_sound("puff"), "clank": _make_sound("clank")}
	_show_tool(tool)


## Leather work glove and jacket sleeve (Blender model arm.glb): hand at the pivot, forearm towards the camera.
func _arm(pivot: Node3D) -> void:
	var arm := Props.instance("arm")
	arm.scale = Vector3.ONE * ARM_SCALE
	if pivot == left:
		arm.scale.x = -arm.scale.x  # mirrored for the left hand
	pivot.add_child(arm)


func _build_tools() -> void:
	var hammer := Props.instance("hammer")
	hammer.rotation = Vector3(-0.35, 0.25, 0.2)
	hammer.position = Vector3(0, 0.02, -0.03)
	hammer.scale = Vector3.ONE * 0.65
	var welder := Props.instance("welder")
	welder.position = Vector3(0, 0.02, -0.06)
	welder.scale = Vector3.ONE * 0.8
	var gun := Props.instance("nail_gun")
	gun.position = Vector3(0, 0.0, -0.04)
	var wrench := Props.instance("wrench")
	wrench.rotation = Vector3(-0.3, 0.2, 0.15)
	wrench.scale = Vector3.ONE * 0.8
	var winch := Props.instance("come_along")
	winch.rotation = Vector3(-0.2, 0.3, 0.0)
	winch.position = Vector3(-0.14, 0.0, -0.04)
	for pair in [["hammer", hammer], ["wrench", wrench], ["welder", welder], ["nail_gun", gun], ["come_along", winch]]:
		right.add_child(pair[1])
		_tool_models[pair[0]] = pair[1]
		_tool_rest_rot[pair[0]] = (pair[1] as Node3D).rotation

	_sparks = _particles(40, 0.35, Color(1.0, 0.75, 0.3), Color(1.0, 0.6, 0.2), 0.02, 0.04)
	_sparks.direction = Vector3(0, 1, 0)
	_sparks.spread = 70.0
	_sparks.initial_velocity_min = 1.5
	_sparks.initial_velocity_max = 3.5
	_sparks.gravity = Vector3(0, -9.8, 0)
	_sparks.position = Vector3(0, 0.05, -0.42)
	welder.add_child(_sparks)
	_weld_light = OmniLight3D.new()
	_weld_light.light_color = Color(0.6, 0.8, 1.0)
	_weld_light.omni_range = 4.0
	_weld_light.light_energy = 0.0
	_weld_light.position = Vector3(0, 0.05, -0.42)
	welder.add_child(_weld_light)

	# nail gun: a puff of dust and a short flash at the nose
	_puff = _particles(14, 0.4, Color(0.8, 0.78, 0.72, 0.7), Color(0, 0, 0), 0.02, 0.05)
	_puff.one_shot = true
	_puff.explosiveness = 0.9
	_puff.direction = Vector3(0, 0.3, -1)
	_puff.spread = 35.0
	_puff.initial_velocity_min = 0.4
	_puff.initial_velocity_max = 1.2
	_puff.gravity = Vector3(0, 0.3, 0)
	_puff.position = Vector3(0, 0.06, -0.3)
	gun.add_child(_puff)
	_flash = OmniLight3D.new()
	_flash.light_color = Color(1.0, 0.85, 0.6)
	_flash.omni_range = 2.0
	_flash.light_energy = 0.0
	_flash.position = Vector3(0, 0.06, -0.3)
	gun.add_child(_flash)


func _particles(amount: int, life: float, color: Color, emission: Color, s_min: float, s_max: float) -> CPUParticles3D:
	var p := CPUParticles3D.new()
	p.emitting = false
	p.amount = amount
	p.lifetime = life
	p.scale_amount_min = s_min
	p.scale_amount_max = s_max
	var mesh := SphereMesh.new()
	mesh.radius = 0.5
	mesh.height = 1.0
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	if color.a < 1.0:
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	if emission != Color(0, 0, 0):
		m.emission_enabled = true
		m.emission = emission
		m.emission_energy_multiplier = 4.0
	mesh.material = m
	p.mesh = mesh
	return p


# --- API (called by Player) -----------------------------------------------------------------

## Switch tools: the hands lower out of view, the tool changes, the hands come back up.
func select_tool(id: String) -> void:
	if id == tool:
		return
	tool = id
	if carry_item != "" or _drop_t < 1.0:
		return  # shown again after the item is put down
	_switch_t = 0.0 if _switch_t >= 1.0 else minf(_switch_t, 0.5)


## Plays a one-shot tool animation ("hammer", "wrench", "nail_gun", "come_along").
func play(action: String) -> void:
	if not ANIMS.has(action) or carry_item != "":
		return
	_anim = action
	_anim_t = 0.0
	_event_done = false
	if action == "nail_gun":
		_puff.restart()
		_puff.emitting = true
		_flash.light_energy = 2.5
		_play_sound("puff")


func set_welding(on: bool) -> void:
	welding = on
	if _sparks:
		_sparks.emitting = on
		if not on:
			_weld_light.light_energy = 0.0


## Starts carrying an item in both hands.
func carry(item: String) -> void:
	_finish_drop()
	carry_item = item
	if _carry_model:
		_carry_model.queue_free()
	_carry_model = Props.instance(item)
	add_child(_carry_model)
	_anim = ""
	_anim_t = 1.0
	_apply_carry_pose(0.0)


## The carried item was placed (or put back): it lowers out of view, then the tool comes back up.
func drop_carry() -> void:
	if carry_item == "":
		return
	_drop_item = carry_item
	carry_item = ""
	_drop_t = 0.0
	_play_sound("clank")


## Where the welding torch's tip is (the cable ends there).
func muzzle_position() -> Vector3:
	return _sparks.global_position if _sparks else global_position


func shown_tool() -> String:
	return _shown_tool


# --- Per-frame pose -----------------------------------------------------------------------

func _process(delta: float) -> void:
	_time += delta
	var speed := 0.0
	var grounded := true
	if player:
		speed = Vector2(player.velocity.x, player.velocity.z).length()
		grounded = player.is_on_floor()
	var target := clampf(speed / 4.5, 0.0, 1.6) if grounded else 0.0
	_bob = lerpf(_bob, target, clampf(delta * 8.0, 0.0, 1.0))
	_bob_phase += delta * (4.0 + speed * 1.6)

	_kick = move_toward(_kick, 0.0, delta * 6.0)
	if camera:
		camera.rotation.z = -_kick * 0.035
		camera.v_offset = -_kick * 0.025
	if _flash:
		_flash.light_energy = move_toward(_flash.light_energy, 0.0, delta * 25.0)

	if _drop_t < 1.0:
		_drop_t = minf(_drop_t + delta / DROP_TIME, 1.0)
		_apply_carry_pose(ease(_drop_t, 2.0))
		if _drop_t >= 1.0:
			_finish_drop()
		return
	if carry_item != "":
		_apply_carry_pose(0.0)
		return

	# tool switch: lower, swap at the bottom, raise
	if _switch_t < 1.0:
		_switch_t = minf(_switch_t + delta / SWITCH_TIME, 1.0)
		if _switch_t >= 0.5 and _shown_tool != tool:
			_show_tool(tool)
	elif _shown_tool != tool:
		_show_tool(tool)
	var lowered := sin(PI * _switch_t) if _switch_t < 1.0 else 0.0

	var rp := RIGHT_REST
	var rr := Vector3.ZERO
	var lp := LEFT_REST
	var lr := Vector3.ZERO
	var two_hands := false
	match _shown_tool:
		"come_along":
			rp = Vector3(0.2, -0.38, -0.58)
			lp = Vector3(-0.08, -0.4, -0.58)
			two_hands = true
		"welder":
			if welding:
				rp += Vector3(-0.06, 0.04, -0.1)
				rr = Vector3(-0.18, 0.0, 0.0)
				lp = rp + Vector3(-0.15, -0.07, 0.06)  # the left hand steadies the right wrist
				lr = Vector3(0.0, 0.0, 0.5)
				two_hands = true
	# one-shot animation
	var wrist := Vector3.ZERO
	if _anim_t < 1.0:
		var info: Dictionary = ANIMS[_anim]
		_anim_t = minf(_anim_t + delta / float(info.len), 1.0)
		var pose := _sample(info.keys, _anim_t)
		rp += pose[0]
		rr += pose[1]
		wrist = pose[2]
		if info.get("two_handed", false):
			lp += pose[0]
			lr += pose[1]
		if not _event_done and _anim_t >= float(info.event):
			_event_done = true
			_on_anim_event(_anim)
	# idle breathing sway + walk bob
	var sway := Vector3(sin(_time * 1.1) * 0.004, sin(_time * 1.7) * 0.005, 0.0)
	var bob := Vector3(sin(_bob_phase) * 0.018, -absf(cos(_bob_phase)) * 0.024, 0.0) * _bob
	var bob_rot := Vector3(sin(_time * 1.3) * 0.01, 0.0, sin(_bob_phase) * 0.025 * _bob)
	# welding: a steady hand, with only a tiny tremble
	if welding:
		var j := Vector3(sin(_time * 37.0) * 0.0035 + randf_range(-0.0015, 0.0015), cos(_time * 29.0) * 0.003 + randf_range(-0.0015, 0.0015), 0.0)
		rp += j
		lp += j * 0.6
		sway *= 0.3
		bob *= 0.4
		_weld_light.light_energy = randf_range(1.2, 3.2) if randf() > 0.08 else 0.3
	var low := Vector3(0.0, -0.42, 0.06) * lowered
	right.position = rp + sway + bob + low
	right.rotation = rr + bob_rot + Vector3(-0.7 * lowered, 0.0, 0.0)
	left.visible = two_hands
	left.position = lp + sway + bob + low
	left.rotation = lr + bob_rot
	var model: Node3D = _tool_models.get(_shown_tool)
	if model:
		model.rotation = _tool_rest_rot[_shown_tool] + wrist


func _show_tool(id: String) -> void:
	_shown_tool = id
	for k: String in _tool_models:
		_tool_models[k].visible = k == id
	if id != "welder":
		set_welding(false)


func _apply_carry_pose(lower: float) -> void:
	var item := carry_item if carry_item != "" else _drop_item
	if not CARRY.has(item) or _carry_model == null:
		return
	var c: Dictionary = CARRY[item]
	for m: Node3D in _tool_models.values():
		m.visible = false
	left.visible = true
	# each item moves differently: the rail strains, the wheel wobbles, the plank rocks on the shoulder
	var t := _time
	var bob := Vector3(sin(_bob_phase) * 0.015, -absf(cos(_bob_phase)) * 0.02, 0.0) * _bob
	var wobble := Vector3.ZERO
	match item:
		"rail":
			bob = Vector3(sin(_bob_phase * 0.7) * 0.01, -absf(cos(_bob_phase * 0.7)) * 0.045, 0.0) * maxf(_bob, 0.3)
			bob += Vector3(0.0, sin(t * 23.0) * 0.003, 0.0)  # strained tremble
			wobble = Vector3(0.0, 0.0, sin(_bob_phase * 0.7) * 0.03)
		"wheel":
			wobble = Vector3(sin(t * 1.9) * 0.03, 0.0, sin(t * 2.3) * 0.07 + sin(_bob_phase) * 0.05 * _bob)
		"plank":
			wobble = Vector3(sin(_bob_phase) * 0.03 * _bob + sin(t * 1.2) * 0.01, 0.0, sin(t * 1.5) * 0.015)
		"panel":
			wobble = Vector3(sin(t * 1.4) * 0.02, 0.0, sin(_bob_phase) * 0.03 * _bob)
	var down := Vector3(0.0, -0.45, -0.1) * lower
	_carry_model.position = c.pos + bob + down
	_carry_model.rotation = c.rot + wobble + Vector3(0.3 * lower, 0.0, 0.0)
	_carry_model.scale = c.scale if c.scale is Vector3 else Vector3.ONE * float(c.scale)
	right.position = c.right + bob + down
	left.position = c.left + bob + down
	right.rotation = Vector3(0.2, 0.0, -0.3)
	left.rotation = Vector3(0.2, 0.0, 0.3)


func _finish_drop() -> void:
	if _drop_item == "":
		return
	_drop_item = ""
	_drop_t = 1.0
	if _carry_model:
		_carry_model.queue_free()
		_carry_model = null
	# bring the tool back up from below
	_switch_t = 0.5
	_show_tool(tool)


## Smoothly interpolates the keyframes [t, pos, forearm rot, wrist rot] at time u (0..1).
func _sample(keys: Array, u: float) -> Array:
	for i in range(1, keys.size()):
		var b: Array = keys[i]
		if u <= float(b[0]):
			var a: Array = keys[i - 1]
			var k := smoothstep(float(a[0]), float(b[0]), u)
			return [(a[1] as Vector3).lerp(b[1], k), (a[2] as Vector3).lerp(b[2], k), (a[3] as Vector3).lerp(b[3], k)]
	var last: Array = keys[-1]
	return [last[1], last[2], last[3]]


func _on_anim_event(action: String) -> void:
	match action:
		"hammer":
			_kick = 1.0
			_play_sound("thunk")
		"wrench":
			_kick = 0.25
			_play_sound("tick")
		"come_along":
			_kick = 0.3
			_play_sound("tick")


# --- Little procedural sounds (no sound files yet) ------------------------------------------

func _play_sound(id: String) -> void:
	if _sfx and _sounds.has(id) and is_inside_tree():
		_sfx.stream = _sounds[id]
		_sfx.play()


static func _make_sound(kind: String) -> AudioStreamWAV:
	var rate := 22050
	var length := {"thunk": 0.18, "tick": 0.07, "puff": 0.16, "clank": 0.14}[kind] as float
	var n := int(rate * length)
	var data := PackedByteArray()
	data.resize(n * 2)
	var rng := RandomNumberGenerator.new()
	rng.seed = kind.hash()
	for i in n:
		var t := float(i) / rate
		var s := 0.0
		match kind:
			"thunk":
				s = sin(TAU * 110.0 * t) * exp(-t * 28.0) + rng.randf_range(-1, 1) * exp(-t * 90.0) * 0.5
			"tick":
				s = (sin(TAU * 2400.0 * t) * 0.5 + rng.randf_range(-1, 1) * 0.5) * exp(-t * 120.0)
			"puff":
				s = rng.randf_range(-1, 1) * exp(-t * 30.0) * 0.8 + sin(TAU * 180.0 * t) * exp(-t * 50.0) * 0.4
			"clank":
				s = (sin(TAU * 520.0 * t) + sin(TAU * 830.0 * t) * 0.6) * exp(-t * 35.0) * 0.5
		data.encode_s16(i * 2, int(clampf(s, -1.0, 1.0) * 26000.0))
	var wav := AudioStreamWAV.new()
	wav.format = AudioStreamWAV.FORMAT_16_BITS
	wav.mix_rate = rate
	wav.data = data
	return wav
