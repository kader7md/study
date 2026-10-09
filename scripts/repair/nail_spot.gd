class_name NailSpot
extends Interactable
## A nail to drive in (or, style "bolt", a fishplate bolt joining two rails): 3 hammer hits,
## or 1 shot with the nail gun. A nail uses 1 nail, a bolt 1 bolt from the team pool.

signal done

const HAMMER_HITS := 3

var hits := 0
var finished := false
var style := "nail"
## "" = hammer or nail gun; "nail_gun" = only the nail gun (joining planks to each other)
var require_tool := ""
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
	if require_tool == "nail_gun":
		return "Join the planks: NAIL GUN [LMB]%s" % ("" if Game.has("nail_gun") else " (you need one: station shop)")
	var gun := " · nail gun: 1 shot" if Game.has("nail_gun") else ""
	return "%s: hammer [LMB] %d/%d%s" % ["Bolt the fishplate" if style == "bolt" else "Nail", hits, HAMMER_HITS, gun]


func on_tool_hit(tool: String, _player: Node) -> bool:
	if finished or not tool in ["hammer", "nail_gun"]:
		return false
	if require_tool != "" and tool != require_tool:
		Game.say("Joining planks needs the NAIL GUN (buy one at a station shop)")
		return false
	if not _paid:  # nails and bolts cost 1 each (team pool)
		var what := "bolts" if style == "bolt" else "nails"
		if not Game.take(what):
			Game.say("No %s! Buy %s at a station shop." % [what, what])
			return false
		_paid = true
	hits = HAMMER_HITS if tool == "nail_gun" else hits + 1
	_show_hits()
	if hits >= HAMMER_HITS:
		finished = true
		set_deferred("monitorable", false)
		collision_layer = 0
		done.emit()
	return true


func _show_hits() -> void:
	if style == "bolt":
		_nail.position.x = -0.08 * float(hits) / HAMMER_HITS
	else:
		_nail.position.y = -0.2 * float(hits) / HAMMER_HITS


## NET: a client mirrors the host's progress (no nails taken, no `done` signal: the host finishes the work).
func net_set_hits(h: int) -> void:
	if h == hits:
		return
	hits = h
	_show_hits()
	if hits >= HAMMER_HITS and not finished:
		finished = true
		set_deferred("monitorable", false)
		collision_layer = 0
