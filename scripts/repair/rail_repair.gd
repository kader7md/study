class_name RailRepair
extends Node3D
## A broken piece of track rebuilt by hand, step by step:
##   1. place 2 wooden planks (sleepers)      → carry planks from the cargo car
##   2. nail each plank down (2 nails each)   → hammer (3 hits) or nail gun (1 shot)
##   3. place the 2 steel rails                → carry rails from the cargo car
##   4. weld both ends of each rail            → welder (hold LMB), cable from the train's welder machine
## When every joint is welded the piece is fixed and the train can pass.

var track: Track
var index := 0
var _nails_left := 4
var _seams_left := 4
var _planks_placed := 0
var _rail_slots: Array[PlaceSlot] = []
var _label: Label3D


func setup(t: Track, piece_index: int) -> void:
	track = t
	index = piece_index


func _ready() -> void:
	_label = Build.label(self, "", Vector3(0, 2.0, 0), 40)
	Build.box(self, Vector3(2.8, 0.03, Track.PIECE_LENGTH - 0.2), Vector3(0, 0.0, 0), Color(1.0, 0.45, 0.1, 0.3))
	for k in 2:
		var z := (k - 0.5) * Track.PIECE_LENGTH * 0.5
		var slot := PlaceSlot.create(self, "plank", Vector3(0, 0.06, z), Vector3(2.4, 0.5, 0.6), Props.instance("plank"))
		slot.placed.connect(_on_plank_placed.bind(z))
	for side in 2:
		var x := (side - 0.5) * Track.GAUGE
		var slot := PlaceSlot.create(self, "rail", Vector3(x, 0.2, 0), Vector3(0.45, 0.45, Track.PIECE_LENGTH - 0.6), Props.instance("rail"))
		slot.enabled = false
		slot.hint = "Place and nail both planks first"
		slot.placed.connect(_on_rail_placed.bind(x))
		_rail_slots.append(slot)
	_update_label()


func step() -> int:
	if _planks_placed < 2:
		return 1
	if _nails_left > 0:
		return 2
	if _rail_slots.any(func(s): return is_instance_valid(s)):
		return 3
	return 4


func _update_label() -> void:
	var lines := ["BROKEN TRACK"]
	match step():
		1: lines.append("1/4 Place planks (%d/2)" % _planks_placed)
		2: lines.append("2/4 Nail the planks (%d left)" % _nails_left)
		3: lines.append("3/4 Place the rails")
		4: lines.append("4/4 Weld the rails (%d joints left)" % _seams_left)
	_label.text = "\n".join(lines)


func _on_plank_placed(_player: Node, z: float) -> void:
	var plank := Props.instance("plank")
	plank.position = Vector3(0, 0.06, z)
	add_child(plank)
	plank.scale = Vector3.ONE * 0.6
	create_tween().tween_property(plank, "scale", Vector3.ONE, 0.15)
	_planks_placed += 1
	for x in [-0.95, 0.95]:
		var nail := NailSpot.new()
		nail.position = Vector3(x, 0.08, z)
		add_child(nail)
		nail.done.connect(_on_nail_done)
	_update_label()


func _on_nail_done() -> void:
	_nails_left -= 1
	if _nails_left == 0 and _planks_placed == 2:
		for slot in _rail_slots:
			slot.enabled = true
	_update_label()


func _on_rail_placed(_player: Node, x: float) -> void:
	var rail := Props.instance("rail")
	rail.position = Vector3(x, 0.6, 0)
	add_child(rail)
	create_tween().tween_property(rail, "position:y", 0.2, 0.2).set_trans(Tween.TRANS_BOUNCE).set_ease(Tween.EASE_OUT)
	for z in [-Track.PIECE_LENGTH * 0.5 + 0.1, Track.PIECE_LENGTH * 0.5 - 0.1]:
		var seam := WeldSeam.new()
		seam.position = Vector3(x, 0.22, z)
		add_child(seam)
		seam.done.connect(_on_seam_done)
	_update_label()


func _on_seam_done() -> void:
	_seams_left -= 1
	_update_label()
	if _seams_left == 0:
		Game.say("Track rebuilt!")
		track.repair_piece.call_deferred(index)


## Debug/test helper: finishes the whole repair instantly.
func finish_instantly() -> void:
	track.repair_piece(index)
