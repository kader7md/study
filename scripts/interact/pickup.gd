class_name Pickup
extends Interactable
## A resource lying around (coal, wood, scrap) or a gold rock that is mined with several hits.

const COLORS := {
	"coal": Color(0.12, 0.12, 0.14),
	"wood": Color(0.55, 0.35, 0.18),
	"scrap": Color(0.55, 0.58, 0.62),
	"gold": Color(1.0, 0.8, 0.15),
}

var item := "coal"
var amount := 1
## Gold rocks need several hits; each hit gives `amount` gold.
var hits_left := 1


static func create(parent: Node, item_id: String, item_amount: int, pos: Vector3) -> Pickup:
	var p := Pickup.new()
	p.item = item_id
	p.amount = item_amount
	p.position = pos
	parent.add_child(p)
	return p


static func create_gold_rock(parent: Node, pos: Vector3) -> Pickup:
	var p := create(parent, "gold", 1, pos)
	p.hits_left = 3
	return p


func _ready() -> void:
	if item == "gold":
		Build.sphere(self, 0.9, Vector3(0, 0.5, 0), Color(0.45, 0.42, 0.4))
		for i in 4:
			var a := TAU * i / 4.0
			Build.sphere(self, 0.22, Vector3(cos(a) * 0.75, 0.7, sin(a) * 0.75), COLORS.gold)
		Build.collider(self, Vector3(2, 1.6, 2), Vector3(0, 0.6, 0))
	else:
		var size := Vector3(0.6, 0.35, 0.6) if item != "wood" else Vector3(1.2, 0.3, 0.3)
		Build.box(self, size, Vector3(0, size.y * 0.5, 0), COLORS.get(item, Color.WHITE))
		Build.collider(self, Vector3(1.4, 1.0, 1.4), Vector3(0, 0.4, 0))


func get_prompt(_player: Node) -> String:
	if item == "gold":
		return "Mine gold rock (%d hits left)  [E]" % hits_left
	return "Pick up %d %s  [E]" % [amount, item]


func interact(_player: Node) -> void:
	Game.add(item, amount)
	hits_left -= 1
	if item == "gold":
		Game.say("+%d gold" % amount)
	if hits_left <= 0:
		queue_free()
