class_name AnchorSpot
extends Interactable
## A tree or rock you can chain the come-along to (appears around a tipped train).

var train: Train


func _ready() -> void:
	Build.collider(self, Vector3(1.4, 3.0, 1.4), Vector3(0, 1.2, 0))
	# a red strap around the trunk / rock
	var strap := Build.cylinder(self, 0.45, 0.12, Vector3(0, 1.0, 0), Color(0.8, 0.12, 0.08))
	strap.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF


func get_prompt(_player: Node) -> String:
	if train.anchor == self:
		return "Chain anchored here. Crank the come-along [LMB] to pull the train up"
	if train.hook == null:
		return "Anchor point: first hook the come-along to the train's lifting eye"
	return "Anchor the chain here [LMB with the come-along]"
