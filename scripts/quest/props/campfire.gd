class_name Campfire
extends Node3D
## A camp checkpoint on a quest map ("Camp_<i>"): stone ring, logs, a flickering fire and a warm light once the crew
## has reached it (QuestManager.camp >= index). Players respawn around the last one; near it the cold goes away.

const WARM_RADIUS := 8.0

var index := 0
var title := ""
var _flames: Array[MeshInstance3D] = []
var _light: OmniLight3D
var _label: Label3D
var _lit := false
var _t := 0.0


func _ready() -> void:
	add_child(QuestProps.instance("campfire"))
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.billboard_mode = BaseMaterial3D.BILLBOARD_FIXED_Y
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	mat.albedo_texture = GateKey._radial_texture()
	mat.albedo_color = Color(1.0, 0.55, 0.15, 0.9)
	for k in 3:
		var f := MeshInstance3D.new()
		var q := QuadMesh.new()
		q.size = Vector2(0.9 - k * 0.2, 1.4 - k * 0.3)
		f.mesh = q
		f.material_override = mat
		f.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		f.position = Vector3(0, 0.6 + k * 0.2, 0)
		add_child(f)
		_flames.append(f)
	_light = OmniLight3D.new()
	_light.light_color = Color(1.0, 0.62, 0.3)
	_light.omni_range = 11.0
	_light.position = Vector3(0, 1.2, 0)
	add_child(_light)
	_label = Build.label(self, title, Vector3(0, 2.6, 0), 48)
	set_lit(index == 0)


func set_lit(on: bool) -> void:
	_lit = on
	for f in _flames:
		f.visible = on
	_light.visible = on
	_label.modulate = Color(1.0, 0.85, 0.55) if on else Color(0.8, 0.8, 0.8, 0.8)


func _process(delta: float) -> void:
	if not _lit:
		return
	_t += delta
	for k in _flames.size():
		var f := _flames[k]
		f.scale = Vector3(1.0 + 0.12 * sin(_t * 9.0 + k), 1.0 + 0.2 * sin(_t * 13.0 + k * 2.0), 1.0)
	_light.light_energy = 1.8 + 0.4 * sin(_t * 11.0) + 0.2 * sin(_t * 23.0)
