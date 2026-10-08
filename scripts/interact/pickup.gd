class_name Pickup
extends Interactable
## A resource lying around (coal, wood, scrap, a crate of nails), a gold rock that is mined with several hits,
## or a supply crate holding several items (`bundle`, the softlock guard). Named "Pickup_<n>" by Main.

const COLORS := {
	"coal": Color(0.12, 0.12, 0.14),
	"wood": Color(0.55, 0.35, 0.18),
	"scrap": Color(0.55, 0.58, 0.62),
	"gold": Color(1.0, 0.8, 0.15),
	"nails": Color(0.6, 0.45, 0.25),
}
## Gold per hit on a gold rock, and hits per rock (balance table in docs/GDD.md).
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


func _ready() -> void:
	if item == "gold":
		Build.sphere(self, 0.9, Vector3(0, 0.5, 0), Color(0.45, 0.42, 0.4))
		for i in 4:
			var a := TAU * i / 4.0
			Build.sphere(self, 0.22, Vector3(cos(a) * 0.75, 0.7, sin(a) * 0.75), COLORS.gold)
		Build.collider(self, Vector3(2, 1.6, 2), Vector3(0, 0.6, 0))
	elif item == "supply" or item == "nails":
		var big := item == "supply"
		var size := Vector3(1.0, 0.7, 0.8) if big else Vector3(0.6, 0.35, 0.45)
		Build.box(self, size, Vector3(0, size.y * 0.5, 0), Color(0.5, 0.33, 0.17))
		for y in [0.15, size.y - 0.15]:
			Build.box(self, Vector3(size.x + 0.02, 0.05, size.z + 0.02), Vector3(0, y, 0), Color(0.3, 0.3, 0.32))
		var l := Build.label(self, "SUPPLIES" if big else "NAILS", Vector3(0, size.y + 0.35, 0), 40 if big else 28)
		l.modulate = Color(1.0, 0.9, 0.6)
		Build.collider(self, Vector3(1.4, 1.0, 1.4), Vector3(0, 0.4, 0))
	else:
		var size := Vector3(0.6, 0.35, 0.6) if item != "wood" else Vector3(1.2, 0.3, 0.3)
		Build.box(self, size, Vector3(0, size.y * 0.5, 0), COLORS.get(item, Color.WHITE))
		Build.collider(self, Vector3(1.4, 1.0, 1.4), Vector3(0, 0.4, 0))


func get_prompt(_player: Node) -> String:
	if item == "gold":
		return "Mine gold rock (%d hits left)  [E]" % hits_left
	if not bundle.is_empty():
		return "Open the supply crate (%s)  [E]" % Game.cost_text(bundle)
	return "Pick up %d %s  [E]" % [amount, item]


## Host: adds the contents to the crew inventory.
func interact(_player: Node) -> void:
	if is_queued_for_deletion():
		return
	if not bundle.is_empty():
		for k: String in bundle:
			Game.add(k, int(bundle[k]))
		Game.say("Supply crate: +%s" % Game.cost_text(bundle))
		queue_free()
		return
	Game.add(item, amount)
	hits_left -= 1
	if item == "gold":
		Game.add_stat("gold_found", amount)
		Game.say("+%d gold" % amount)
	if hits_left <= 0:
		queue_free()
