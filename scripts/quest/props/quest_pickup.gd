class_name QuestPickup
extends Interactable
## Something to take on a quest map ("Rope_<n>", "Snack_<n>", "Coconut_<n>", "Stew_<n>"): rope coils for the crew,
## food for the player who takes it (snack / coconut: stamina, stew: health). Host-side (QuestManager.take_pickup).

const MODELS := {"rope": "rope_coil", "snack": "snack"}
const LABELS := {"rope": "Take the rope coil", "snack": "Eat the energy snack", "coconut": "Drink the coconut",
	"stew": "Eat the warm stew"}

var kind := "snack"
var amount := 60.0
var _pivot: Node3D


func _ready() -> void:
	Build.collider(self, Vector3(0.9, 0.8, 0.9), Vector3(0, 0.35, 0))
	_pivot = Node3D.new()
	add_child(_pivot)
	var model: String = MODELS.get(kind, "")
	if model != "":
		var m := QuestProps.instance(model)
		m.scale = Vector3.ONE * (1.6 if kind == "snack" else 1.2)
		_pivot.add_child(m)
	elif kind == "coconut":
		Build.sphere(_pivot, 0.17, Vector3(0, 0.17, 0), Color(0.36, 0.24, 0.12))
		Build.sphere(_pivot, 0.17, Vector3(0.3, 0.15, 0.05), Color(0.33, 0.22, 0.1))
	else:
		Build.cylinder(_pivot, 0.22, 0.2, Vector3(0, 0.1, 0), Color(0.25, 0.25, 0.27))
		Build.cylinder(_pivot, 0.19, 0.02, Vector3(0, 0.2, 0), Color(0.6, 0.35, 0.15))
	var l := Build.label(self, kind.to_upper(), Vector3(0, 1.0, 0), 30)
	l.modulate = Color(1.0, 0.85, 0.4) if kind != "rope" else Color(0.85, 0.95, 1.0)


func _process(delta: float) -> void:
	if _pivot and kind == "snack":
		_pivot.rotation.y += delta


func get_prompt(_player: Node) -> String:
	return "%s  %s" % [LABELS.get(kind, "Take"), Settings.key_hint("interact")]


func interact(player: Node) -> void:
	if Game.quest and player is Player and visible:
		Game.quest.take_pickup(String(name), kind, amount, player)


func set_taken(on: bool) -> void:
	visible = not on
	collision_layer = 0 if on else Build.LAYER_INTERACT
