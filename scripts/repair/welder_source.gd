class_name WelderSource
extends Node3D
## A welder machine the welding torch plugs into. The cable has a fixed length.
## kind "train" = small machine on the utility car (rails; metal body panels only while the body is under Train.PATCH_LIMIT)
## kind "station" = big station machine (anything, body up to 100 %)

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


## Where the cable comes out.
func plug_position() -> Vector3:
	return global_position + global_basis.y * (1.1 if kind == "station" else 0.75)
