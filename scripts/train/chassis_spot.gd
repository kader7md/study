class_name ChassisSpot
extends Interactable
## A weld point on the locomotive's frame. Glows while the chassis is damaged.
## Only a station welder's torch can weld it (welders only exist at stations).

const WELD_RATE := 3.0  # chassis damage welded per second

var train: Train
var _mat := StandardMaterial3D.new()
var _mesh: MeshInstance3D


func _ready() -> void:
	Build.collider(self, Vector3(0.5, 0.5, 1.2), Vector3.ZERO)
	_mesh = Build.box(self, Vector3(0.12, 0.08, 0.9), Vector3.ZERO, Color.WHITE)
	_mat.albedo_color = Color(0.15, 0.05, 0.02)
	_mat.emission_enabled = true
	_mat.emission = Color(1.0, 0.35, 0.05)
	_mesh.material_override = _mat


func _process(_delta: float) -> void:
	var damaged := train.chassis_damage > 0.0
	_mesh.visible = damaged
	collision_layer = Build.LAYER_INTERACT if damaged else 0
	_mat.emission_energy_multiplier = 1.0 + sin(Time.get_ticks_msec() * 0.005) * 0.5


func get_prompt(_player: Node) -> String:
	return "Chassis %d%%: weld it with a station torch [hold LMB]" % int(100.0 - train.chassis_damage / Train.CHASSIS_MAX * 100.0)


func on_weld(delta: float, _player: Node, _source: Node) -> bool:
	if train.chassis_damage <= 0.0:
		return false
	train.weld_chassis(WELD_RATE * delta)
	if train.chassis_damage <= 0.0:
		Game.say("Chassis welded")
	return true
