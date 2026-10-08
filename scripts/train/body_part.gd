class_name BodyPart
extends Node
## One breakable piece of a train car's cover: a wall panel, roof panel, boiler plate or door
## (a "Panel_<wood|metal>_<n>" / "Door_<wood|metal>_<n>" node in the Blender model).
## Attached: visible and solid. Broken off: it flies away as a FallenPart and leaves the frame open.
## Refit: carry a panel to the ghost, place it, then nail it (wood: 2 nails, anywhere) or weld it
## (metal: 2 seams, only with a station welder's torch).

signal attached_changed(part: BodyPart)

const DOOR_OPEN_ANGLE := 1.7

var train: Train
var car: Node3D
var node: MeshInstance3D        # the visual from the .glb
var material := "wood"
var is_door := false
var attached := true
var door_open := false
var _home: Transform3D
var _body: StaticBody3D
var _slot: PlaceSlot
var _fasteners_left := 0
var _door_spot: Interactable


func setup(t: Train, car_body: Node3D, mesh_node: MeshInstance3D) -> void:
	train = t
	car = car_body
	node = mesh_node
	material = "metal" if "_metal_" in node.name else "wood"
	is_door = node.name.begins_with("Door_")
	_home = node.transform
	var aabb := node.get_aabb()
	_body = StaticBody3D.new()
	_body.collision_layer = Build.LAYER_TRAIN
	node.add_child(_body)
	Build.collider(_body, aabb.size.max(Vector3(0.08, 0.08, 0.08)), aabb.get_center())
	if is_door:
		_door_spot = ActionSpot.create(node, aabb.size + Vector3(0.2, 0.0, 0.0), aabb.get_center(),
			func(_p): return "%s door  [E]" % ("Close" if door_open else "Open"),
			func(_p): toggle_door())


func value() -> float:
	return 100.0 / train.parts.size()


func toggle_door() -> void:
	if not attached:
		return
	door_open = not door_open
	var side := signf(_home.origin.x) if absf(_home.origin.x) > 0.1 else 1.0
	# side doors swing outwards; cab FRONT doors (thin along the track) swing forwards
	var size := node.get_aabb().size
	var angle := side * DOOR_OPEN_ANGLE if size.x <= size.z else -side * DOOR_OPEN_ANGLE
	var target := _home.basis.rotated(Vector3.UP, angle if door_open else 0.0)
	var tween := node.create_tween()
	tween.tween_property(node, "basis", target, 0.3).set_trans(Tween.TRANS_BACK)


## Breaks the piece off. With `fly` it tumbles away as a FallenPart that can be picked up again.
func detach(fly := true) -> void:
	if not attached:
		return
	attached = false
	door_open = false
	node.transform = _home
	node.visible = false
	_body.collision_layer = 0
	if _door_spot:
		_door_spot.collision_layer = 0
	if fly:
		FallenPart.spawn(train.get_parent(), node, car)
	_make_slot()
	attached_changed.emit(self)


func _make_slot() -> void:
	var aabb := node.get_aabb()
	var ghost := MeshInstance3D.new()
	ghost.mesh = node.mesh
	_slot = PlaceSlot.create(car, "panel", Vector3.ZERO, aabb.size.max(Vector3(0.3, 0.3, 0.3)), ghost)
	# the slot sits where the piece belongs; its collider is centred on the piece
	_slot.transform = _home
	for c in _slot.get_children():
		if c is CollisionShape3D:
			c.position = aabb.get_center()
	_slot.placed.connect(_on_placed)


func _on_placed(_player: Node) -> void:
	_slot = null
	node.visible = true
	var out := _outward()
	node.transform = _home.translated(out * 0.6)
	node.create_tween().tween_property(node, "transform", _home, 0.3).set_trans(Tween.TRANS_BACK)
	_add_fasteners()


## Direction from the car's centre line out through this piece (side panels → sideways, roofs → up).
func _outward() -> Vector3:
	var aabb := node.get_aabb()
	var center := _home * aabb.get_center()
	var size := aabb.size
	if size.y < size.x and size.y < size.z:
		return Vector3.UP
	if size.z < size.x and size.z < size.y:
		return Vector3(0, 0, signf(center.z))
	return Vector3(signf(center.x) if absf(center.x) > 0.01 else 1.0, 0, 0)


func _add_fasteners() -> void:
	var aabb := node.get_aabb()
	var c := aabb.get_center()
	var out := _outward()
	# two fastening points along the long side of the piece
	var long_axis := 0 if aabb.size.x >= aabb.size.z else 2
	if out.x != 0.0:
		long_axis = 2
	elif out.z != 0.0:
		long_axis = 0
	var offsets: Array[Vector3] = []
	for k in [-0.35, 0.35]:
		var o := Vector3.ZERO
		o[long_axis] = aabb.size[long_axis] * k
		offsets.append(c + o)
	_fasteners_left = offsets.size()
	for local in offsets:
		var pos := _home * local + out * 0.08
		var f: Interactable
		if material == "wood":
			var nail := NailSpot.new()
			nail.done.connect(_on_fastened)
			f = nail
		else:
			var seam := WeldSeam.new()
			seam.done.connect(_on_fastened)
			f = seam
		f.position = pos
		car.add_child(f)
		# point the nail / seam outwards
		if out.x != 0.0:
			f.rotation.z = -out.x * PI * 0.5
		elif out.z != 0.0:
			f.rotation.x = out.z * PI * 0.5
		f.set_meta("part", self)


func _on_fastened() -> void:
	_fasteners_left -= 1
	if _fasteners_left > 0:
		return
	attached = true
	_body.collision_layer = Build.LAYER_TRAIN
	if _door_spot:
		_door_spot.collision_layer = Build.LAYER_INTERACT
	train.on_part_refitted(self)
	attached_changed.emit(self)


## Puts the piece back instantly (debug / tests / checkpoint loading).
func refit_instantly() -> void:
	if attached:
		return
	if is_instance_valid(_slot):
		_slot.queue_free()
	_slot = null
	for f in car.get_children():
		if f.has_meta("part") and f.get_meta("part") == self:
			f.queue_free()
	node.transform = _home
	node.visible = true
	attached = true
	_body.collision_layer = Build.LAYER_TRAIN
	if _door_spot:
		_door_spot.collision_layer = Build.LAYER_INTERACT
	attached_changed.emit(self)


## The piece is placed but still needs nails / welds.
func is_pending() -> bool:
	return not attached and _slot == null


func slot() -> PlaceSlot:
	return _slot
