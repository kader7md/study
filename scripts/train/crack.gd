class_name Crack
extends Interactable
## A glowing crack in the train body (10 % health). Weld it shut with the welder (hold LMB).

const WELD_TIME := 2.0

var train: Train
var progress := 0.0


func _ready() -> void:
	Build.collider(self, Vector3(0.7, 0.5, 0.3), Vector3.ZERO)
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(0.1, 0.05, 0.02)
	m.emission_enabled = true
	m.emission = Color(1.0, 0.35, 0.05)
	m.emission_energy_multiplier = 1.5
	for k in 3:
		var bit := Build.box(self, Vector3(0.05, 0.06, 0.3 - k * 0.06), Vector3(0, -0.12 + k * 0.12, (k - 1) * 0.12), Color.WHITE)
		bit.rotation.x = 0.5 * (k - 1)
		bit.material_override = m


func get_prompt(_player: Node) -> String:
	return "Crack in the body: welder [hold LMB] %d%%" % int(progress / WELD_TIME * 100.0)


func on_weld(delta: float, _player: Node, source: Node) -> bool:
	if source.kind != "station" and train.health >= Train.PATCH_LIMIT:
		return false
	progress += delta
	if progress >= WELD_TIME:
		train.weld_crack(self, source)
	return true
