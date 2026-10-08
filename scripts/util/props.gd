class_name Props
## Loads the Blender-made models (assets/models) and makes instances of them.

const PATHS := {
	"locomotive": "res://assets/models/train/locomotive.glb",
	"cargo": "res://assets/models/train/cargo_wagon.glb",
	"utility": "res://assets/models/train/utility_wagon.glb",
	"container": "res://assets/models/train/container_wagon.glb",
	"wheel": "res://assets/models/props/wheel.glb",
	"plank": "res://assets/models/props/plank.glb",
	"rail": "res://assets/models/props/rail.glb",
	"hammer": "res://assets/models/props/hammer.glb",
	"welder": "res://assets/models/props/welder_torch.glb",
	"nail_gun": "res://assets/models/props/nail_gun.glb",
	"wrench": "res://assets/models/props/wrench.glb",
	"welder_machine": "res://assets/models/props/welder_machine.glb",
}

static var _cache := {}


static func instance(id: String) -> Node3D:
	if id == "panel":
		# generic spare panel carried by the player (fits any missing piece)
		var n := Node3D.new()
		Build.box(n, Vector3(1.6, 1.0, 0.1), Vector3.ZERO, Color(0.55, 0.33, 0.16))
		Build.box(n, Vector3(1.64, 0.12, 0.12), Vector3(0, 0.3, 0), Color(0.36, 0.2, 0.1))
		Build.box(n, Vector3(1.64, 0.12, 0.12), Vector3(0, -0.3, 0), Color(0.36, 0.2, 0.1))
		return n
	if id == "come_along":
		# hand winch / ratchet puller: red body, long pump handle, two hooks
		var c := Node3D.new()
		var red := Color(0.75, 0.08, 0.06)
		Build.cylinder(c, 0.035, 0.22, Vector3(0, 0, 0), red).rotation.x = PI * 0.5
		Build.box(c, Vector3(0.025, 0.04, 0.42), Vector3(0, 0.06, -0.18), red).rotation.x = -0.5
		Build.cylinder(c, 0.06, 0.03, Vector3(0, 0, 0), Color(0.3, 0.3, 0.32)).rotation.z = PI * 0.5
		for z in [-0.16, 0.16]:
			var hk := Build.cylinder(c, 0.03, 0.015, Vector3(0, -0.04, z), red)
			hk.rotation.x = PI * 0.5
		return c
	if not _cache.has(id):
		_cache[id] = load(PATHS[id])
	return _cache[id].instantiate()


## Makes every mesh under `node` see-through (used for "place here" ghosts).
static func make_ghost(node: Node, color := Color(0.4, 0.9, 1.0, 0.35)) -> void:
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	for child in node.find_children("*", "MeshInstance3D", true, false):
		(child as MeshInstance3D).material_override = m
	if node is MeshInstance3D:
		node.material_override = m
