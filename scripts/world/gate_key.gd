class_name GateKey
extends Interactable
## The key to a segment's locked gate ("Key_<segment>"): a big glowing iron key (gate_key.glb) that bobs and
## spins a few metres beside the track next to its gate, with a warm light, a soft halo, a light beam and a
## KEY label so it is easy to spot from the cab. [E] picks it up (+1 "key" in the crew inventory).

const HOVER := 1.05
const GOLD := Color(1.0, 0.78, 0.32)

var segment := 0
var _pivot: Node3D
var _light: OmniLight3D
var _halo: MeshInstance3D
var _t := 0.0


static func create(parent: Node, seg: int, pos: Vector3) -> GateKey:
	var k := GateKey.new()
	k.segment = seg
	k.name = "Key_%d" % seg
	k.position = pos
	parent.add_child(k)
	return k


func _ready() -> void:
	_t = segment * 1.7
	Build.collider(self, Vector3(1.4, 1.8, 1.4), Vector3(0, 0.9, 0))
	_pivot = Node3D.new()
	_pivot.position.y = HOVER
	add_child(_pivot)
	var model := Props.instance("gate_key")
	model.scale = Vector3.ONE * 1.6
	_pivot.add_child(model)
	# warm additive overlay makes the iron and brass glow without losing their texture
	var glow := StandardMaterial3D.new()
	glow.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	glow.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	glow.albedo_color = Color(GOLD.r, GOLD.g * 0.8, GOLD.b * 0.5, 0.45)
	glow.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	for mi in model.find_children("*", "MeshInstance3D", true, false):
		(mi as MeshInstance3D).material_overlay = glow

	_light = OmniLight3D.new()
	_light.light_color = GOLD
	_light.omni_range = 5.5
	_light.light_energy = 2.2
	_light.position.y = HOVER
	add_child(_light)

	_halo = _sprite(Vector2(1.6, 1.6), _radial_texture(), Color(1.0, 0.82, 0.4, 0.55))
	_halo.position.y = HOVER
	add_child(_halo)

	# a faint beam of light rising from the key: visible from the cab over the grass
	var beam := MeshInstance3D.new()
	var cyl := CylinderMesh.new()
	cyl.top_radius = 0.05
	cyl.bottom_radius = 0.22
	cyl.height = 9.0
	cyl.cap_top = false
	cyl.cap_bottom = false
	beam.mesh = cyl
	beam.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var bm := StandardMaterial3D.new()
	bm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	bm.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	bm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	bm.cull_mode = BaseMaterial3D.CULL_DISABLED
	bm.albedo_color = Color(1.0, 0.75, 0.3, 0.16)
	beam.material_override = bm
	beam.position.y = 4.5
	add_child(beam)

	# a soft glowing ring on the ground
	var ring := _sprite(Vector2(2.6, 2.6), _radial_texture(), Color(1.0, 0.75, 0.3, 0.35), false)
	ring.rotation.x = -PI * 0.5
	ring.position.y = 0.06
	add_child(ring)

	var label := Build.label(self, "KEY", Vector3(0, HOVER + 1.05, 0), 64)
	label.modulate = GOLD
	label.outline_modulate = Color(0.25, 0.12, 0.0)


func _sprite(size: Vector2, tex: Texture2D, color: Color, billboard := true) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var quad := QuadMesh.new()
	quad.size = size
	mi.mesh = quad
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.albedo_texture = tex
	m.albedo_color = color
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	if billboard:
		m.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	mi.material_override = m
	return mi


static var _radial: GradientTexture2D

static func _radial_texture() -> GradientTexture2D:
	if _radial == null:
		var g := Gradient.new()
		g.set_color(0, Color(1, 1, 1, 1))
		g.set_color(1, Color(1, 1, 1, 0))
		g.add_point(0.35, Color(1, 1, 1, 0.45))
		_radial = GradientTexture2D.new()
		_radial.gradient = g
		_radial.fill = GradientTexture2D.FILL_RADIAL
		_radial.fill_from = Vector2(0.5, 0.5)
		_radial.fill_to = Vector2(1.0, 0.5)
		_radial.width = 64
		_radial.height = 64
	return _radial


func _process(delta: float) -> void:
	_t += delta
	_pivot.position.y = HOVER + sin(_t * 2.0) * 0.12
	_pivot.rotation.y += delta * 1.4
	var pulse := 0.5 + 0.5 * sin(_t * 3.0)
	_light.light_energy = 1.7 + pulse * 1.0
	_halo.position.y = _pivot.position.y
	_halo.scale = Vector3.ONE * (0.9 + pulse * 0.2)


func get_prompt(_player: Node) -> String:
	return "Pick up the gate key  [E]"


## Host: the crew gets the key; the key disappears.
func interact(_player: Node) -> void:
	if is_queued_for_deletion():
		return
	Game.add("key")
	Game.say("Got the KEY! Use it on the padlock of the locked gate [E]")
	queue_free()
