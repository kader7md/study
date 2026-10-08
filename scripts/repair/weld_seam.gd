class_name WeldSeam
extends Interactable
## A joint to weld with the welder (hold LMB). Glows hot while welding, cools to steel when done.

signal done

const WELD_TIME := 1.6

var progress := 0.0
var finished := false
var _bead: MeshInstance3D
var _mat := StandardMaterial3D.new()


func _ready() -> void:
	Build.collider(self, Vector3(0.4, 0.4, 0.4), Vector3.ZERO)
	_bead = Build.box(self, Vector3(0.18, 0.08, 0.18), Vector3(0, 0.08, 0), Color.WHITE)
	_mat.albedo_color = Color(0.25, 0.25, 0.27)
	_mat.emission_enabled = true
	_mat.emission = Color(1.0, 0.45, 0.1)
	_mat.emission_energy_multiplier = 0.0
	_bead.material_override = _mat


func get_prompt(_player: Node) -> String:
	if finished:
		return ""
	return "Weld the joint: welder [hold LMB] %d%%" % int(progress * 100.0)


func on_weld(delta: float, _player: Node, _source: Node) -> bool:
	if finished:
		return false
	progress = minf(progress + delta / WELD_TIME, 1.0)
	_mat.emission_energy_multiplier = 3.0 * progress
	_mat.albedo_color = Color(0.25, 0.25, 0.27).lerp(Color(1.0, 0.6, 0.3), progress)
	if progress >= 1.0:
		finished = true
		collision_layer = 0
		var tween := create_tween()
		tween.tween_property(_mat, "emission_energy_multiplier", 0.0, 1.5)
		tween.parallel().tween_property(_mat, "albedo_color", Color(0.62, 0.64, 0.68), 1.5)
		done.emit()
	return true
