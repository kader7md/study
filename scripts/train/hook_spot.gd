class_name HookSpot
extends Interactable
## Lifting eye on the locomotive frame: hook the come-along here when the train has tipped over.

var train: Train


func _ready() -> void:
	Build.collider(self, Vector3(0.5, 0.5, 0.5), Vector3.ZERO)
	var ring := Build.cylinder(self, 0.09, 0.04, Vector3.ZERO, Color(0.25, 0.25, 0.27))
	ring.rotation.z = PI * 0.5


func get_prompt(_player: Node) -> String:
	if not train.tipped:
		return ""
	if train.hook == self:
		return "Come-along hooked here. Now hook the chain to a tree or rock on the high side"
	return "Lifting eye: hook the come-along here [LMB with the come-along]"
