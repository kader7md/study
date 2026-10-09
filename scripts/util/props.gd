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
	"panel": "res://assets/models/props/panel.glb",
	"track_spike": "res://assets/models/props/track_spike.glb",
	"track_bolt": "res://assets/models/props/track_bolt.glb",
	"hammer": "res://assets/models/props/hammer.glb",
	"welder": "res://assets/models/props/welder_torch.glb",
	"nail_gun": "res://assets/models/props/nail_gun.glb",
	"wrench": "res://assets/models/props/wrench.glb",
	"welder_machine": "res://assets/models/props/welder_machine.glb",
	"track_gate": "res://assets/models/props/track_gate.glb",
	"gate_signal": "res://assets/models/props/gate_signal.glb",
	"gate_key": "res://assets/models/props/gate_key.glb",
	"come_along": "res://assets/models/props/come_along.glb",
	"arm": "res://assets/models/props/arm.glb",
	"station_shelter": "res://assets/models/props/station_shelter.glb",
	"shop_kiosk": "res://assets/models/props/shop_kiosk.glb",
	"station_sign": "res://assets/models/props/station_sign.glb",
	"platform_section": "res://assets/models/props/platform_section.glb",
	"station_bench": "res://assets/models/props/station_bench.glb",
	"station_lamp": "res://assets/models/props/station_lamp.glb",
	"gravestone": "res://assets/models/props/gravestone.glb",
	"gold_ore": "res://assets/models/props/gold_ore.glb",
	"coal_pile": "res://assets/models/props/coal_pile.glb",
	"scrap_pile": "res://assets/models/props/scrap_pile.glb",
	"wood_bundle": "res://assets/models/props/wood_bundle.glb",
	"nails_box": "res://assets/models/props/nails_box.glb",
	"supply_crate": "res://assets/models/props/supply_crate.glb",
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
