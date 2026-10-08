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
	"welder_machine": "res://assets/models/props/welder_machine.glb",
}

static var _cache := {}


static func instance(id: String) -> Node3D:
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
