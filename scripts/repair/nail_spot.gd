class_name NailSpot
extends Interactable
## A nail to drive in (or, style "bolt", a fishplate bolt joining two rails): 3 hammer hits,
## or 1 shot with the nail gun. Uses 1 nail from the inventory.

signal done

const HAMMER_HITS := 3

var hits := 0
var finished := false
var style := "nail"
var _paid := false
var _nail: Node3D


func _ready() -> void:
	Build.collider(self, Vector3(0.35, 0.35, 0.35), Vector3(0, 0.1, 0))
	_nail = Node3D.new()
	add_child(_nail)
	if style == "bolt":
		Build.box(self, Vector3(0.05, 0.12, 0.5), Vector3(0.05, 0.0, 0), Color(0.35, 0.33, 0.32))  # fishplate
		Build.cylinder(_nail, 0.035, 0.18, Vector3(0.1, 0.0, 0), Color(0.6, 0.6, 0.62)).rotation.z = PI * 0.5
		Build.cylinder(_nail, 0.055, 0.04, Vector3(0.19, 0.0, 0), Color(0.5, 0.5, 0.52)).rotation.z = PI * 0.5
	else:
		Build.cylinder(_nail, 0.025, 0.25, Vector3(0, 0.12, 0), Color(0.7, 0.7, 0.72))
		Build.cylinder(_nail, 0.06, 0.03, Vector3(0, 0.25, 0), Color(0.75, 0.75, 0.78))


func get_prompt(player: Node) -> String:
	if finished:
		return ""
	var gun := " · nail gun: 1 shot" if Game.has("nail_gun") else ""
	return "%s: hammer [LMB] %d/%d%s" % ["Bolt the fishplate" if style == "bolt" else "Nail", hits, HAMMER_HITS, gun]


func on_tool_hit(tool: String, _player: Node) -> bool:
	if finished or not tool in ["hammer", "nail_gun"]:
		return false
	if not _paid:
		if not Game.take("nails"):
			Game.say("No nails! Buy nails at a station shop.")
			return false
		_paid = true
	hits = HAMMER_HITS if tool == "nail_gun" else hits + 1
	if style == "bolt":
		_nail.position.x = -0.08 * float(hits) / HAMMER_HITS
	else:
		_nail.position.y = -0.2 * float(hits) / HAMMER_HITS
	if hits >= HAMMER_HITS:
		finished = true
		set_deferred("monitorable", false)
		collision_layer = 0
		done.emit()
	return true
