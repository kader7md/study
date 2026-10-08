class_name RemoteBody
extends Node3D
## How another player looks on your screen: a chunky little railway worker in their colour (jacket and cap), a head
## that tilts with their camera pitch, two big hands, a name tag, and whatever they hold: their current tool in the
## right hand, or a plank / rail / wheel / panel carried in both hands. (The first-person arms are only for yourself.)

const SKIN := Color(1.0, 0.76, 0.6)
const TROUSERS := Color(0.22, 0.24, 0.3)
const BOOTS := Color(0.16, 0.11, 0.08)

var _head: Node3D
var _arms: Node3D
var _hand_r: Node3D
var _hand_l: Node3D
var _tag: Label3D
var _speaking: Label3D
var _held: Node3D
var _held_id := ""
var _carry_id := ""
var _walk := 0.0
var _legs: Array[Node3D] = []


func setup(display_name: String, color: Color) -> void:
	var jacket := color
	var dark := color.darkened(0.35)
	# legs and boots
	for side in [-1.0, 1.0]:
		var leg := Node3D.new()
		leg.position = Vector3(side * 0.14, 0.82, 0)
		add_child(leg)
		_capsule(leg, 0.11, 0.78, Vector3(0, -0.38, 0), TROUSERS)
		Build.box(leg, Vector3(0.2, 0.12, 0.3), Vector3(0, -0.76, -0.05), BOOTS)
		_legs.append(leg)
	# torso: jacket with a darker belt and two reflective stripes
	_capsule(self, 0.3, 0.86, Vector3(0, 1.18, 0), jacket)
	Build.cylinder(self, 0.305, 0.07, Vector3(0, 0.92, 0), dark)
	for y in [1.08, 1.28]:
		Build.cylinder(self, 0.307, 0.035, Vector3(0, y, 0), Color(0.95, 0.9, 0.55))
	# head with a cap in the player's colour
	_head = Node3D.new()
	_head.position = Vector3(0, 1.68, 0)
	add_child(_head)
	Build.sphere(_head, 0.21, Vector3(0, 0, 0), SKIN)
	Build.sphere(_head, 0.035, Vector3(-0.08, 0.03, -0.19), Color(0.1, 0.08, 0.07))
	Build.sphere(_head, 0.035, Vector3(0.08, 0.03, -0.19), Color(0.1, 0.08, 0.07))
	Build.sphere(_head, 0.045, Vector3(0, -0.03, -0.21), SKIN.darkened(0.08))  # nose
	var cap := Build.sphere(_head, 0.22, Vector3(0, 0.08, 0.0), dark)
	cap.scale = Vector3(1.0, 0.55, 1.0)
	Build.box(_head, Vector3(0.3, 0.03, 0.18), Vector3(0, 0.08, -0.22), dark)  # cap visor
	# arms pivot at the shoulders and follow the look pitch a little
	_arms = Node3D.new()
	_arms.position = Vector3(0, 1.42, 0)
	add_child(_arms)
	_hand_r = _arm(0.36, jacket)
	_hand_l = _arm(-0.36, jacket)
	# name tag
	_tag = Label3D.new()
	_tag.text = display_name
	_tag.position = Vector3(0, 2.22, 0)
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
	_speaking.position = Vector3(0, 2.5, 0)
	_speaking.font_size = 40
	_speaking.outline_size = 12
	_speaking.pixel_size = 0.006
	_speaking.modulate = Color(1.0, 0.9, 0.4)
	_speaking.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_speaking.no_depth_test = true
	_speaking.visible = false
	add_child(_speaking)


func _arm(x: float, jacket: Color) -> Node3D:
	var shoulder := Node3D.new()
	shoulder.position = Vector3(x, 0, 0)
	_arms.add_child(shoulder)
	_capsule(shoulder, 0.085, 0.5, Vector3(0, -0.12, -0.16), jacket).rotation.x = -1.1
	var hand := Node3D.new()
	hand.position = Vector3(0, -0.24, -0.4)
	shoulder.add_child(hand)
	Build.sphere(hand, 0.095, Vector3.ZERO, SKIN)
	return hand


func _capsule(parent: Node, radius: float, height: float, pos: Vector3, color: Color) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var m := CapsuleMesh.new()
	m.radius = radius
	m.height = height
	mi.mesh = m
	mi.material_override = Build.material(color)
	mi.position = pos
	parent.add_child(mi)
	return mi


## Look pitch (camera rotation.x): the head nods fully, the arms follow half way.
func set_pitch(pitch: float) -> void:
	if _head:
		_head.rotation.x = clampf(pitch, -0.9, 0.9)
		_arms.rotation.x = clampf(pitch * 0.5, -0.6, 0.6)


func set_speaking(on: bool) -> void:
	if _speaking:
		_speaking.visible = on


## What is in the hands: a carried item wins over the tool.
func set_held(tool: String, carried: String) -> void:
	var id := carried if carried != "" else tool
	if id == _held_id and carried == _carry_id:
		return
	_held_id = id
	_carry_id = carried
	if _held:
		_held.queue_free()
		_held = null
	_hand_l.get_parent().rotation = Vector3.ZERO
	_hand_r.get_parent().rotation = Vector3.ZERO
	if id == "" or (carried == "" and not Props.PATHS.has(id) and id != "come_along"):
		return
	_held = Props.instance(id)
	if carried != "":
		# both hands forward, the item in front of the chest
		_arms.add_child(_held)
		match carried:
			"plank":
				_held.position = Vector3(0, -0.2, -0.5)
				_held.scale = Vector3.ONE * 0.55
			"rail":
				_held.position = Vector3(0.05, -0.3, -0.55)
				_held.rotation = Vector3(0, 0.15, 0)
				_held.scale = Vector3.ONE * 0.45
			"wheel":
				_held.position = Vector3(0, -0.2, -0.5)
				_held.rotation = Vector3(0, PI * 0.5, 0)
				_held.scale = Vector3.ONE * 0.75
			_:
				_held.position = Vector3(0, -0.15, -0.5)
				_held.scale = Vector3.ONE * 0.6
		_hand_l.get_parent().rotation.y = -0.35
		_hand_r.get_parent().rotation.y = 0.35
	else:
		_hand_r.add_child(_held)
		_held.rotation = Vector3(-0.4, 0, 0)
		_held.scale = Vector3.ONE * 0.8


## Simple walk cycle. `speed` is how fast the player walks (relative to the train car they ride, if any).
func animate(delta: float, speed: float) -> void:
	if speed > 0.4:
		_walk += delta * minf(speed, 8.0) * 2.2
	else:
		_walk = move_toward(_walk, roundf(_walk / PI) * PI, delta * 4.0)
	var swing := sin(_walk) * 0.6
	if _legs.size() == 2:
		_legs[0].rotation.x = swing
		_legs[1].rotation.x = -swing
