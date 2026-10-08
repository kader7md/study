class_name Interactable
extends Area3D
## Base for anything the player can use by looking at it.
## [E] = interact, [Q] = interact_alt. If get_hold_time() > 0 the player must hold [E].
## Tools: on_tool_hit() is called when a hammer / nail gun hits it, on_weld() every frame while welding it.


func _init() -> void:
	collision_layer = Build.LAYER_INTERACT
	collision_mask = 0
	monitoring = false


func get_prompt(_player: Node) -> String:
	return ""


func get_hold_time(_player: Node) -> float:
	return 0.0


func interact(_player: Node) -> void:
	pass


func interact_alt(_player: Node) -> void:
	pass


## Hit by a tool ("hammer" or "nail_gun"). Return true if the hit did something.
func on_tool_hit(_tool: String, _player: Node) -> bool:
	return false


## Welded for `delta` seconds with power from `source` (a WelderSource). Return true while welding works.
func on_weld(_delta: float, _player: Node, _source: Node) -> bool:
	return false
