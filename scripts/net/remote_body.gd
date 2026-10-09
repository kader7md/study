class_name RemoteBody
extends Node3D
## How another player looks on your screen: their animated cartoon crew member (CharacterModel) in their own look
## (Appearance code synced as Player.look), a name tag, a "speaking" marker, the tool in their hand or the item they
## carry, and their actions (hammer swings, wrench turns, shovelling, the lever...) played as they happen.
## (The first-person arms are only for yourself.)

var model: CharacterModel
var _tag: Label3D
var _speaking: Label3D
var _look_code := ""
var _color := Color.WHITE
var _speed := 0.0
var _vertical := 0.0
var _air_time := 0.0


func setup(display_name: String, color: Color) -> void:
	_color = color
	model = CharacterModel.new()
	model.name = "Character"
	add_child(model)
	model.rotation.y = 0.0
	if _look_code == "":
		model.apply_look(Appearance.for_color(color))
	else:
		model.apply_look(Appearance.decode(_look_code))
	# name tag
	_tag = Label3D.new()
	_tag.text = display_name
	_tag.position = Vector3(0, 2.25, 0)
	_tag.font_size = 44
	_tag.outline_size = 14
	_tag.pixel_size = 0.006
	_tag.modulate = color.lightened(0.35)
	_tag.outline_modulate = Color(0.12, 0.08, 0.06)
	_tag.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_tag.fixed_size = false
	_tag.no_depth_test = true
	_tag.render_priority = 2
	add_child(_tag)
	_speaking = Label3D.new()
	_speaking.text = "((•))"
	_speaking.position = Vector3(0, 2.53, 0)
	_speaking.font_size = 40
	_speaking.outline_size = 12
	_speaking.pixel_size = 0.006
	_speaking.modulate = Color(1.0, 0.9, 0.4)
	_speaking.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_speaking.no_depth_test = true
	_speaking.visible = false
	add_child(_speaking)


## Their Appearance code ("" = the default look in their lobby colour).
func set_look(code: String) -> void:
	if code == _look_code:
		return
	_look_code = code
	if model:
		model.apply_look(Appearance.decode(code) if code != "" else Appearance.for_color(_color))


## Look pitch (camera rotation.x): the head nods, the upper body follows a little.
func set_pitch(pitch: float) -> void:
	if model:
		model.set_pitch(pitch)


func set_speaking(on: bool) -> void:
	if _speaking:
		_speaking.visible = on


## What is in the hands: a carried item wins over the tool.
func set_held(tool: String, carried: String) -> void:
	if model:
		model.set_tool(tool)
		model.set_carried(carried)


func set_welding(on: bool) -> void:
	if model:
		model.anim.state.welding = on


func set_downed(on: bool) -> void:
	if model:
		model.anim.state.downed = on
		_tag.position.y = 0.9 if on else 2.25


## One action clip (CharacterAnimator.ACTIONS), e.g. when they swing the hammer.
func play_action(clip: String) -> void:
	if model:
		model.play_action(clip)


## Per frame: `speed` is how fast they walk (relative to the car they ride), `vertical` their vertical speed.
func animate(delta: float, speed: float, vertical := 0.0) -> void:
	if model == null:
		return
	_speed = lerpf(_speed, speed, clampf(delta * 10.0, 0.0, 1.0))
	_vertical = lerpf(_vertical, vertical, clampf(delta * 12.0, 0.0, 1.0))
	# airborne only after a moment of clear vertical motion (synced positions are a bit jittery)
	_air_time = _air_time + delta if absf(_vertical) > 1.2 else 0.0
	var s := model.anim.state
	s.speed = _speed
	s.vertical = _vertical
	s.on_floor = _air_time < 0.08
