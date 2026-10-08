class_name WelderSource
extends Node3D
## A station welder machine. Players take its welding torch [E]; the cable has a fixed length.
## Welding only happens at stations: metal train panels go back on here (wood panels can be nailed anywhere).

var kind := "train"
var cable_length := 30.0


static func create(parent: Node, source_kind: String, length: float, pos: Vector3) -> WelderSource:
	var w := WelderSource.new()
	w.kind = source_kind
	w.cable_length = length
	w.position = pos
	parent.add_child(w)
	return w


func _ready() -> void:
	add_to_group("welder_source")
	var model := Props.instance("welder_machine")
	if kind == "station":
		model.scale = Vector3.ONE * 1.5
	add_child(model)
	var spot := ActionSpot.create(self, Vector3(1.6, 1.6, 1.4), Vector3(0, 0.6, 0),
		func(p):
			if p and p.welder_source == self:
				return "Welder (cable %d m): switch tools to put the torch back" % int(cable_length)
			return "Station welder: take the welding torch  [E]  (cable %d m)" % int(cable_length),
		func(p):
			if p and p.welder_source != self:
				p.take_welder(self))
	spot.name = "TakeTorch"


## Where the cable comes out.
func plug_position() -> Vector3:
	return global_position + global_basis.y * (1.1 if kind == "station" else 0.75)
