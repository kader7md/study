class_name QuestPortal
extends Interactable
## The overworld entrance of a quest map ("Portal_<seg>", a child of Main/Quest): a trailhead gate (portal.glb) with a
## glowing doorway, a sign with the map's name and a light beam so it is easy to find from the stopped train.
## [hold E] takes the WHOLE crew into the quest map (QuestManager.enter, on the host).
## Placement: the terrain's reserved quest zone for this segment (Terrain.quest_zone(seg) -> {center, size,
## gate_index}) when that API exists, otherwise beside the gate where its key used to lie, facing the track.

const HOLD := 1.0

var segment := 0
var _glow: MeshInstance3D
var _t := 0.0


func place() -> void:
	var track := Game.track
	var terrain := Game.terrain
	var pos := Vector3.ZERO
	var used_zone := false
	if terrain and terrain.has_method("quest_zone"):
		var zone: Variant = terrain.call("quest_zone", segment)
		if zone is Dictionary and (zone as Dictionary).has("center"):
			pos = (zone as Dictionary).center
			used_zone = true
	if not used_zone:
		pos = track.key_position(segment)
	# face the track at the gate
	var gd := track.gate_distance(segment)
	var near := track.point_at(track.closest_distance(pos) if used_zone else track.key_spots[segment].x)
	var to_track := Vector3(near.x - pos.x, 0.0, near.z - pos.z)
	if to_track.length() < 0.5:
		to_track = track.transform_at(gd).basis.x
	global_transform = Transform3D(Basis.looking_at(-to_track.normalized(), Vector3.UP), pos)


func _ready() -> void:
	add_child(QuestProps.instance("portal"))
	# the glowing doorway between the posts
	_glow = MeshInstance3D.new()
	var quad := QuadMesh.new()
	quad.size = Vector2(3.6, 3.6)
	_glow.mesh = quad
	_glow.position = Vector3(0, 1.95, 0)
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	m.albedo_color = Color(0.55, 0.85, 1.0, 0.45)
	m.albedo_texture = GateKey._radial_texture()
	_glow.material_override = m
	_glow.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_glow)
	var light := OmniLight3D.new()
	light.light_color = Color(0.6, 0.85, 1.0)
	light.omni_range = 7.0
	light.light_energy = 1.6
	light.position = Vector3(0, 2.0, 0.5)
	add_child(light)
	var label := Build.label(self, "%s\nquest: the gate key" % QuestManager.map_title(segment), Vector3(0, 5.4, 0), 56)
	label.modulate = Color(0.75, 0.92, 1.0)
	Build.collider(self, Vector3(4.0, 3.8, 1.6), Vector3(0, 1.9, 0))


func _process(delta: float) -> void:
	_t += delta
	if _glow:
		_glow.scale = Vector3.ONE * (0.92 + 0.08 * sin(_t * 2.2))
		_glow.visible = (Game.quest == null or not Game.quest.active) and Game.track.is_gate_locked(segment)


func get_hold_time(_player: Node) -> float:
	return HOLD


func get_prompt(_player: Node) -> String:
	var q := Game.quest
	if q == null or not Game.track.is_gate_locked(segment):
		return ""
	if q.active:
		return ""
	if Game.has("key"):
		return "You already have a key: use it on the gate"
	return "Enter %s with the whole crew (hold %s)" % [QuestManager.map_title(segment), Settings.key_hint("interact")]


## Host: the crew goes in.
func interact(_player: Node) -> void:
	if Game.quest:
		Game.quest.enter(segment)


## Where player `index` stands after coming back: in front of the portal, side by side.
func exit_transform(index: int) -> Transform3D:
	var x := global_transform
	var side := (index - 2) * 1.1
	var p := x.origin + x.basis.z * 3.0 + x.basis.x * side + Vector3.UP * 0.6
	var ground := _ground_y(p)
	if ground > -INF:
		p.y = ground + 0.3
	return Transform3D(x.basis, p)


func _ground_y(p: Vector3) -> float:
	var q := PhysicsRayQueryParameters3D.create(p + Vector3.UP * 6.0, p + Vector3.DOWN * 20.0, Build.LAYER_WORLD)
	var hit := get_world_3d().direct_space_state.intersect_ray(q)
	return hit.position.y if hit else -INF
