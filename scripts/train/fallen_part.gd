class_name FallenPart
extends RigidBody3D
## A piece of the train that broke off: it tumbles away and lies on the ground.
## Pick it up [E] to carry it back as a "panel" (free), or it disappears after a while.

const LIFETIME := 120.0


## `part_index`: the train.parts index of the piece (kept as "net_part" metadata for WorldSync).
static func spawn(parent: Node, from: MeshInstance3D, car: Node3D, part_index := -1) -> FallenPart:
	var p := FallenPart.new()
	p.set_meta("net_part", part_index)
	parent.add_child(p)
	p.global_transform = from.global_transform
	var mi := MeshInstance3D.new()
	mi.mesh = from.mesh
	p.add_child(mi)
	var aabb := from.get_aabb()
	var size := aabb.size.max(Vector3(0.1, 0.1, 0.1))
	Build.collider(p, size, aabb.get_center())
	p.center_of_mass_mode = RigidBody3D.CENTER_OF_MASS_MODE_CUSTOM
	p.center_of_mass = aabb.get_center()
	# fly outwards from the car, keep some of the train's speed
	var center := from.global_transform * aabb.get_center()
	var away := center - car.global_position
	away.y = 0.0
	away = away.normalized() if away.length() > 0.01 else Vector3.UP
	p.linear_velocity = away * randf_range(3.0, 6.0) + Vector3.UP * randf_range(3.0, 5.0)
	if Game.train:
		p.linear_velocity += -car.global_basis.z * Game.train.speed * 0.7
	p.angular_velocity = Vector3(randf_range(-4, 4), randf_range(-4, 4), randf_range(-4, 4))
	var spot := ActionSpot.create(p, size + Vector3(0.4, 0.4, 0.4), aabb.get_center(),
		func(pl): return "Hands full" if pl and pl.carried_item != "" else "Pick up the broken panel  [E]",
		func(pl): p._pick_up(pl))
	spot.name = "PickUp"
	return p


func _ready() -> void:
	collision_layer = Build.LAYER_DEBRIS
	collision_mask = Build.LAYER_WORLD | Build.LAYER_DEBRIS
	mass = 20.0
	get_tree().create_timer(LIFETIME).timeout.connect(queue_free)


func _pick_up(player: Node) -> void:
	if player == null or player.carried_item != "":
		return
	player.carry("panel")
	queue_free()
