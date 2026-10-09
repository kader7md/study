class_name LeaveSign
extends Interactable
## A signpost at the start of a quest map ("LeaveSign"): [hold E] takes the whole crew back to the train without the key.

const HOLD := 1.5


func _ready() -> void:
	Build.collider(self, Vector3(1.2, 2.4, 0.6), Vector3(0, 1.2, 0))
	Build.cylinder(self, 0.08, 2.4, Vector3(0, 1.2, 0), Color(0.3, 0.2, 0.12))
	Build.box(self, Vector3(1.4, 0.45, 0.06), Vector3(0.3, 2.0, 0), Color(0.55, 0.36, 0.18))
	var l := Build.label(self, "BACK TO THE TRAIN", Vector3(0, 2.7, 0), 36)
	l.modulate = Color(1.0, 0.92, 0.75)


func get_hold_time(_player: Node) -> float:
	return HOLD


func get_prompt(_player: Node) -> String:
	return "Give up: back to the train without the key (hold %s)" % Settings.key_hint("interact")


func interact(_player: Node) -> void:
	if Game.quest and Game.quest.active:
		Game.quest.leave(false)
