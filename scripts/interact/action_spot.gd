class_name ActionSpot
extends Interactable
## An interactable defined with callables, so train/station parts don't each need their own script.
##   prompt_fn(player) -> String
##   action_fn(player)            on [E] (after holding, if hold_fn returns > 0)
##   alt_fn(player)               on [Q]
##   hold_fn(player) -> float     seconds to hold [E]

var prompt_fn: Callable
var action_fn: Callable
var alt_fn: Callable
var hold_fn: Callable


static func create(parent: Node, size: Vector3, pos: Vector3, prompt: Callable, action: Callable) -> ActionSpot:
	var spot := ActionSpot.new()
	spot.prompt_fn = prompt
	spot.action_fn = action
	spot.position = pos
	Build.collider(spot, size, Vector3.ZERO)
	parent.add_child(spot)
	return spot


func get_prompt(player: Node) -> String:
	return prompt_fn.call(player) if prompt_fn.is_valid() else ""


func get_hold_time(player: Node) -> float:
	return hold_fn.call(player) if hold_fn.is_valid() else 0.0


func interact(player: Node) -> void:
	if action_fn.is_valid():
		action_fn.call(player)


func interact_alt(player: Node) -> void:
	if alt_fn.is_valid():
		alt_fn.call(player)
