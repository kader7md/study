class_name Interactable
extends Area3D
## Base for anything the player can use by looking at it.
## [E] = interact, [Q] = interact_alt. If get_hold_time() > 0 the player must hold [E].


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
