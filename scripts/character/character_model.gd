class_name CharacterModel
extends Node3D
## One crew member (assets/models/character/character.glb, built by blender/scripts/build_character.py):
## shows an Appearance (skin, eyes, mouth, accessory, colours), plays the animations through a CharacterAnimator,
## holds the current tool in the right hand and carried items on the shoulder / in the arms, and tilts the upper body
## and head with the look pitch. Used for other players (RemoteBody), the mirror reflection and the customise preview.
##   var c := CharacterModel.new(); add_child(c); c.apply_look(Appearance.load_local())
##   c.anim.state.speed = 3.0; c.play_tool("hammer")

const SCENE := "res://assets/models/character/character.glb"
const SHADER := preload("res://scripts/character/character_toon.gdshader")
## Fixed colours of the parts players don't pick.
const FIXED := {
	"Pants": Color("3d4a66"), "Boots": Color("5a3a24"), "Belt": Color("2e2119"), "Stripe": Color("f4e27a"),
	"EyeWhite": Color("fbfaf5"), "Pupil": Color("141010"), "Mouth": Color("5a1c1c"), "Tongue": Color("e9757a"),
	"Teeth": Color("fffdf4"), "Hair": Color("4a2c18"), "Frame": Color("1e1a1a"), "Glass": Color(0.8, 0.92, 1.0, 0.28),
}
## How each tool sits in the fist (in the arm's rest frame: arm hanging down, Y up, -Z forward).
const TOOL_GRIP := {
	"hammer": [Vector3(0.0, -0.04, 0.0), Vector3(-PI * 0.5, 0.0, 0.0), 0.75],
	"wrench": [Vector3(0.0, -0.04, 0.0), Vector3(-PI * 0.5, 0.0, 0.0), 0.85],
	"nail_gun": [Vector3(0.0, -0.06, -0.02), Vector3(-PI * 0.5, 0.0, 0.0), 0.95],
	"welder": [Vector3(0.0, -0.05, 0.0), Vector3(-PI * 0.5, 0.0, 0.0), 0.9],
	"come_along": [Vector3(0.0, -0.05, 0.0), Vector3(-PI * 0.5, 0.0, 0.0), 0.9],
}
## Carried items (on the chest bone, model axes): position, rotation, scale.
const CARRY_POSE := {
	"plank": [Vector3(0.36, 0.36, -0.08), Vector3(0.08, 0.0, 0.0), 0.6],
	"rail": [Vector3(0.0, 0.06, -0.34), Vector3(0.0, PI * 0.5, 0.0), Vector3(0.9, 0.9, 0.42)],
	"wheel": [Vector3(0.0, -0.02, -0.46), Vector3(0.0, PI * 0.5, 0.0), 0.62],
	"panel": [Vector3(0.0, -0.05, -0.42), Vector3(0.0, 0.0, 0.0), 0.55],
}
## Share of the look pitch each bone takes (the head nods most).
const PITCH_SHARE := {"spine": 0.12, "chest": 0.25, "head": 0.45}

var look := Appearance.new()
var anim: CharacterAnimator
var skeleton: Skeleton3D
var anim_player: AnimationPlayer
var held_tool := ""
var carried := ""
## Render layers of every mesh (the local player's own body uses layer 2: hidden from their camera).
var render_layers := 1

var _scene: Node3D
var _parts := {}   # mesh name -> MeshInstance3D
var _hand_r: BoneAttachment3D
var _chest: BoneAttachment3D
var _tool_node: Node3D
var _carry_node: Node3D
var _pitch: PitchModifier
static var _materials := {}


func _init() -> void:
	_build()


func _build() -> void:
	_scene = (load(SCENE) as PackedScene).instantiate()
	_scene.name = "Model"
	add_child(_scene)
	skeleton = _scene.find_children("*", "Skeleton3D", true, false)[0]
	anim_player = _scene.find_children("*", "AnimationPlayer", true, false)[0]
	for mi: MeshInstance3D in skeleton.find_children("*", "MeshInstance3D", true, false):
		_parts[String(mi.name)] = mi
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	anim = CharacterAnimator.new()
	anim.name = "AnimationTree"
	_scene.add_child(anim)
	anim.setup(anim_player, skeleton)
	_pitch = PitchModifier.new()
	_pitch.name = "Pitch"
	skeleton.add_child(_pitch)
	_hand_r = _attachment("hand.R")
	_chest = _attachment("chest")
	apply_look(look)


func _attachment(bone: String) -> BoneAttachment3D:
	var att := BoneAttachment3D.new()
	att.name = "At_" + bone.replace(".", "_")
	att.bone_name = bone
	skeleton.add_child(att)
	# a child that undoes the bone's rest orientation: offsets below are in plain model axes (as in the rest pose)
	var grip := Node3D.new()
	grip.name = "Grip"
	var rest := skeleton.get_bone_global_rest(skeleton.find_bone(bone))
	grip.basis = rest.basis.inverse()
	att.add_child(grip)
	return att


## Applies a look: shows one eye / mouth style and the accessory, colours every part.
func apply_look(a: Appearance) -> void:
	look = a.duplicate_look()
	if _scene == null:
		return
	for n: String in _parts:
		var mi: MeshInstance3D = _parts[n]
		if n.begins_with("Eyes_"):
			mi.visible = n == "Eyes_" + look.eyes
		elif n.begins_with("Mouth_"):
			mi.visible = n == "Mouth_" + look.mouth
		elif n.begins_with("Acc_"):
			mi.visible = n == "Acc_" + look.accessory
		elif n == "Hair":
			mi.visible = not look.accessory in Appearance.HATS
		_paint(mi)


func _paint(mi: MeshInstance3D) -> void:
	for i in mi.mesh.get_surface_count():
		var src := mi.mesh.surface_get_material(i)
		var id := src.resource_name if src else ""
		mi.set_surface_override_material(i, material_for(id, color_for(id)))


func color_for(id: String) -> Color:
	return part_color(look, id)


## The colour of material `id` (Skin, Outfit, Hat, Iris... see build_character.py) for look `a`.
static func part_color(a: Appearance, id: String) -> Color:
	match id:
		"Skin", "Lid":
			return a.skin_color()
		"Outfit":
			return a.outfit_tint()
		"OutfitDark":
			return a.outfit_tint().darkened(0.3)
		"Hat":
			return a.hat_tint()
		"HatDark":
			return a.hat_tint().darkened(0.25)
		"Iris":
			return a.eye_tint()
	return FIXED.get(id, Color(1, 0, 1))


## Shared cartoon material per (part, colour).
static func material_for(id: String, color: Color) -> Material:
	var key := "%s/%s" % [id, color.to_html()]
	if _materials.has(key):
		return _materials[key]
	var m: Material
	if id == "Glass":
		var g := StandardMaterial3D.new()
		g.albedo_color = color
		g.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		g.roughness = 0.05
		g.metallic_specular = 0.9
		m = g
	else:
		var s := ShaderMaterial.new()
		s.shader = SHADER
		s.set_shader_parameter("albedo", color)
		var shiny := id in ["EyeWhite", "Pupil", "Iris", "Teeth", "Frame", "Boots", "Belt"]
		s.set_shader_parameter("roughness", 0.3 if shiny else 0.8)
		s.set_shader_parameter("rim_strength", 0.08 if shiny else 0.22)
		m = s
	_materials[key] = m
	return m


## Puts every mesh of the character (and what it holds) on these render layers.
func set_render_layers(mask: int) -> void:
	render_layers = mask
	_apply_layers(self)


func _apply_layers(node: Node) -> void:
	for vi: VisualInstance3D in node.find_children("*", "VisualInstance3D", true, false):
		vi.layers = render_layers
	if node is VisualInstance3D:
		(node as VisualInstance3D).layers = render_layers


# --- Held things ---------------------------------------------------------------------------------

## The tool in the right hand ("" = none). A carried item hides it.
func set_tool(tool: String) -> void:
	if tool == held_tool:
		return
	held_tool = tool
	anim.state.tool = tool
	if _tool_node:
		_tool_node.queue_free()
		_tool_node = null
	if tool == "" or not TOOL_GRIP.has(tool) or _hand_r == null:
		return
	_tool_node = Props.instance(tool)
	var g: Array = TOOL_GRIP[tool]
	_tool_node.position = g[0]
	_tool_node.rotation = g[1]
	_tool_node.scale = Vector3.ONE * float(g[2])
	_hand_r.get_node("Grip").add_child(_tool_node)
	_tool_node.visible = carried == ""
	_apply_layers(_tool_node)


## A carried repair item (plank, rail, wheel, panel; "" = none).
func set_carried(item: String) -> void:
	if item == carried:
		return
	carried = item
	anim.state.carried = item
	if _carry_node:
		_carry_node.queue_free()
		_carry_node = null
	if _tool_node:
		_tool_node.visible = item == ""
	if item == "" or not CARRY_POSE.has(item) or _chest == null:
		return
	_carry_node = Props.instance(item)
	var c: Array = CARRY_POSE[item]
	_carry_node.position = c[0]
	_carry_node.rotation = c[1]
	_carry_node.scale = c[2] if c[2] is Vector3 else Vector3.ONE * float(c[2])
	_chest.get_node("Grip").add_child(_carry_node)
	_apply_layers(_carry_node)


## One tool use (hammer swing, wrench turn, nail gun shot, come-along pump) or another action clip.
func play_tool(tool: String) -> void:
	var clip := CharacterAnimator.action_clip(tool)
	if clip != "":
		anim.play_action(clip)


func play_action(clip: String) -> void:
	if anim.play_action(clip) and clip == "shovel":
		_show_shovel()


## A coal shovel appears in the hand for the shovelling swing (the furnace has no shovel to pick up).
func _show_shovel() -> void:
	if _hand_r == null or carried != "":
		return
	var grip := _hand_r.get_node("Grip")
	var old := grip.get_node_or_null("Shovel")
	if old:
		old.free()
	var sh := Node3D.new()
	sh.name = "Shovel"
	var shaft := Build.cylinder(sh, 0.022, 0.9, Vector3(0, -0.32, 0), Color("8a5a32"))
	shaft.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	Build.box(sh, Vector3(0.12, 0.05, 0.05), Vector3(0, 0.15, 0), Color("4a3020"))  # D grip
	var blade := Build.box(sh, Vector3(0.24, 0.3, 0.025), Vector3(0, -0.88, -0.04), Color("6d7178"))
	blade.rotation.x = 0.35
	grip.add_child(sh)
	_apply_layers(sh)
	if _tool_node:
		_tool_node.visible = false
	get_tree().create_timer(0.95).timeout.connect(func() -> void:
		if is_instance_valid(sh):
			sh.queue_free()
		if _tool_node:
			_tool_node.visible = carried == "")


## Look pitch (camera rotation.x, + = up): the upper body and head follow.
func set_pitch(pitch: float) -> void:
	if _pitch:
		_pitch.pitch = 0.0 if anim.state.downed else clampf(pitch, -1.1, 1.1)


func _process(delta: float) -> void:
	if anim:
		anim.update_state(delta)


## Tilts the spine, chest and head by the look pitch after the animation is applied.
class PitchModifier extends SkeletonModifier3D:
	var pitch := 0.0
	var _shown := 0.0

	func _process_modification_with_delta(delta: float) -> void:
		_shown = lerpf(_shown, pitch, clampf(delta * 12.0, 0.0, 1.0))
		var sk := get_skeleton()
		if sk == null or absf(_shown) < 0.001:
			return
		for bone: String in CharacterModel.PITCH_SHARE:
			var i := sk.find_bone(bone)
			if i < 0:
				continue
			var g := sk.get_bone_global_pose(i)
			g.basis = Basis(Vector3.RIGHT, _shown * float(CharacterModel.PITCH_SHARE[bone])) * g.basis
			sk.set_bone_global_pose(i, g)
