class_name Pickup
extends Interactable
## A resource lying around, a gold rock that is mined with several hits (gold nuggets), or a supply crate holding
## several items (`bundle`, the softlock guard). Named "Pickup_<n>" by Main.
## Two kinds: SHARED TEAM RESOURCES (planks, rails, nails, bolts... Game.TEAM_ITEMS: they go to the crew's pool and
## carry a little "TEAM" sign) and personal loot (coal, scrap, food, nuggets: into the picker's own inventory).

const COLORS := {
	"coal": Color(0.12, 0.12, 0.14),
	"wood": Color(0.55, 0.35, 0.18),
	"scrap": Color(0.55, 0.58, 0.62),
	"gold": Color(1.0, 0.8, 0.15),
	"nails": Color(0.6, 0.45, 0.25),
	"bolts": Color(0.5, 0.5, 0.55),
}
## Gold nuggets per hit on a gold rock, and hits per rock (balance table in docs/GDD.md).
const GOLD_PER_HIT := 2
const GOLD_HITS := 3

var item := "coal"
var amount := 1
## Gold rocks need several hits; each hit gives `amount` gold.
var hits_left := 1
## Supply crate: item -> amount (all taken at once).
var bundle: Dictionary = {}


static func create(parent: Node, item_id: String, item_amount: int, pos: Vector3) -> Pickup:
	var p := Pickup.new()
	p.item = item_id
	p.amount = item_amount
	p.position = pos
	parent.add_child(p)
	return p


static func create_gold_rock(parent: Node, pos: Vector3) -> Pickup:
	var p := Pickup.new()
	p.item = "gold"
	p.amount = GOLD_PER_HIT
	p.hits_left = GOLD_HITS
	p.position = pos
	parent.add_child(p)
	return p


static func create_bundle(parent: Node, items: Dictionary, pos: Vector3) -> Pickup:
	var p := Pickup.new()
	p.item = "supply"
	p.bundle = items.duplicate()
	p.position = pos
	parent.add_child(p)
	return p


## What this pickup is worth in total: item -> amount (gold rocks: all hits).
func contents() -> Dictionary:
	if not bundle.is_empty():
		return bundle.duplicate()
	return {item: amount * hits_left}


## Blender model per pickup kind (blender/scripts/build_assets.py build_pickups, baked wear).
const MODELS := {"gold": "gold_ore", "coal": "coal_pile", "scrap": "scrap_pile", "wood": "wood_bundle",
	"nails": "nails_box", "bolts": "nails_box", "rail": "rail", "supply": "supply_crate"}


func _ready() -> void:
	var model_id: String = MODELS.get(item, "")
	if model_id != "":
		var model := Props.instance(model_id)
		model.name = "Model"
		# a little random turn so piles along the track do not all look the same
		model.rotation.y = deg_to_rad(float(hash(Vector3i(position.round())) % 360)) if item != "supply" else 0.0
		if item == "rail":
			model.scale = Vector3.ONE * 0.6
			model.position.y = 0.1
		add_child(model)
	elif Game.item_kind(item) == "food":
		_build_food()
	else:
		Build.box(self, Vector3(0.6, 0.35, 0.6), Vector3(0, 0.175, 0), COLORS.get(item, Color.WHITE))
	if item == "gold":
		Build.collider(self, Vector3(2, 1.6, 2), Vector3(0, 0.6, 0))
	elif item == "supply" or item == "nails" or item == "bolts":
		var big := item == "supply"
		var l := Build.label(self, "SUPPLIES" if big else item.to_upper(), Vector3(0, (0.7 if big else 0.35) + 0.35, 0), 40 if big else 28)
		l.modulate = Color(1.0, 0.9, 0.6)
		Build.collider(self, Vector3(1.4, 1.0, 1.4), Vector3(0, 0.4, 0))
	else:
		Build.collider(self, Vector3(1.4, 1.0, 1.4), Vector3(0, 0.4, 0))
	if Game.is_team_item(item) and item != "gold":
		# shared team resource: a small sign so it reads as "for everyone"
		var t := Build.label(self, "TEAM", Vector3(0, 1.0, 0), 22)
		t.modulate = Color(0.75, 1.0, 0.75)


## A little food pickup built in code: an apple, a can of beans, a chocolate bar, a sandwich, a cup.
func _build_food() -> void:
	match item:
		"apple":
			Build.sphere(self, 0.12, Vector3(0, 0.12, 0), Color(0.8, 0.12, 0.1))
			Build.sphere(self, 0.11, Vector3(0.2, 0.11, 0.05), Color(0.55, 0.75, 0.15))
		"beans":
			Build.cylinder(self, 0.1, 0.22, Vector3(0, 0.11, 0), Color(0.75, 0.75, 0.78))
			Build.cylinder(self, 0.102, 0.12, Vector3(0, 0.11, 0), Color(0.8, 0.3, 0.12))
		"chocolate":
			Build.box(self, Vector3(0.32, 0.04, 0.16), Vector3(0, 0.02, 0), Color(0.35, 0.18, 0.08))
			Build.box(self, Vector3(0.2, 0.045, 0.165), Vector3(0.06, 0.022, 0), Color(0.85, 0.2, 0.25))
		_:
			Build.box(self, Vector3(0.3, 0.14, 0.24), Vector3(0, 0.07, 0), Color(0.85, 0.7, 0.45))
	var l := Build.label(self, Game.item_name(item).to_upper(), Vector3(0, 0.6, 0), 22)
	l.modulate = Color(1.0, 0.95, 0.8)


func get_prompt(_player: Node) -> String:
	if item == "gold":
		return "Mine the gold rock for nuggets (%d hits left)  [E]" % hits_left
	if not bundle.is_empty():
		return "Open the supply crate (%s)  [E]" % Game.cost_text(bundle)
	if Game.is_team_item(item):
		return "Pick up %d %s for the team  [E]" % [amount, Game.item_name(item).to_lower()]
	return "Pick up %d %s  [E]" % [amount, Game.item_name(item).to_lower()]


## Host: team resources go to the shared pool, the rest into the picker's own inventory.
func interact(_player: Node) -> void:
	if is_queued_for_deletion():
		return
	if not bundle.is_empty():
		for k: String in bundle:
			Game.add(k, int(bundle[k]))
		Game.say("Supply crate: +%s" % Game.cost_text(bundle))
		queue_free()
		return
	hits_left -= 1
	if item == "gold":
		Game.add("gold_nugget", amount)
		Game.add_stat("gold_found", amount)
		Game.say("+%d gold nuggets (sell them at a station shop)" % amount)
	else:
		Game.add(item, amount)
	if hits_left <= 0:
		queue_free()
