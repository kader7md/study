class_name PlaceSlot
extends Interactable
## A "place it here" spot with a see-through ghost of the item. The player must be carrying that item.

signal placed(player: Node)

const NAMES := {"plank": "a plank", "rail": "a rail", "wheel": "a wheel"}

var item := "plank"
var enabled := true:
	set(value):
		enabled = value
		if _ghost:
			_ghost.visible = value
var hint := ""
var _ghost: Node3D


static func create(parent: Node, item_id: String, pos: Vector3, size: Vector3, ghost_model: Node3D) -> PlaceSlot:
	var slot := PlaceSlot.new()
	slot.item = item_id
	slot.position = pos
	Build.collider(slot, size, Vector3.ZERO)
	parent.add_child(slot)
	if ghost_model:
		Props.make_ghost(ghost_model)
		slot.add_child(ghost_model)
		slot._ghost = ghost_model
	return slot


func get_prompt(player: Node) -> String:
	if not enabled:
		return hint
	if player and player.carried_item == item:
		return "Place %s  [E]" % NAMES[item]
	return "Needs %s (take one from the cargo car)" % NAMES[item]


func interact(player: Node) -> void:
	if not enabled or player == null:
		return
	if player.carried_item != item:
		Game.say("You need to carry %s here" % NAMES[item])
		return
	player.consume_carried()
	placed.emit(player)
	queue_free()
