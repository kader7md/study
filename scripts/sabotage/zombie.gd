class_name Zombie
extends CharacterBody3D
## Runs at the nearest player or train car. Damages the train while next to it, hurts players it touches.
## A fast train can outrun them.

const SPEED := 5.5
const JUMP := 6.5
const HP := 30.0
const TRAIN_DPS := 1.5
const PLAYER_DPS := 10.0
const LIFETIME := 60.0

var hp := HP
var _life := LIFETIME
var _gravity: float = ProjectSettings.get_setting("physics/3d/default_gravity")


static func spawn(parent: Node, pos: Vector3) -> Zombie:
	var z := Zombie.new()
	parent.add_child(z)
	z.global_position = pos
	return z


func _ready() -> void:
	add_to_group("enemy")
	collision_layer = Build.LAYER_ENEMY
	collision_mask = Build.LAYER_WORLD | Build.LAYER_TRAIN
	var shape := CapsuleShape3D.new()
	shape.radius = 0.35
	shape.height = 1.7
	var cs := CollisionShape3D.new()
	cs.shape = shape
	cs.position.y = 0.85
	add_child(cs)
	Build.box(self, Vector3(0.6, 1.1, 0.4), Vector3(0, 0.75, 0), Color(0.3, 0.5, 0.25))
	Build.sphere(self, 0.3, Vector3(0, 1.55, 0), Color(0.45, 0.65, 0.35))
	Build.box(self, Vector3(0.8, 0.12, 0.12), Vector3(0, 1.15, -0.35), Color(0.45, 0.65, 0.35))  # arms forward


func take_hit(amount: float) -> void:
	hp -= amount
	if hp <= 0.0:
		Game.say("Zombie down")
		queue_free()


func _physics_process(delta: float) -> void:
	_life -= delta
	var train := Game.train
	if _life <= 0.0 or train == null or global_position.distance_to(train.cars[0].global_position) > 150.0:
		queue_free()  # left behind by the train, or too old
		return

	var target := Vector3.INF
	var best := INF
	for car in train.cars:
		var dist := global_position.distance_to(car.global_position)
		if dist < best:
			best = dist
			target = car.global_position
		if dist < 5.0:
			train.take_damage(TRAIN_DPS * delta)
	for p in get_tree().get_nodes_in_group("player"):
		if p.downed:
			continue
		var dist := global_position.distance_to(p.global_position)
		if dist < best:
			best = dist
			target = p.global_position
		if dist < 1.4:
			p.take_damage(PLAYER_DPS * delta)

	var dir := target - global_position
	dir.y = 0.0
	if dir.length() > 0.5:
		dir = dir.normalized()
		velocity.x = dir.x * SPEED
		velocity.z = dir.z * SPEED
		look_at(global_position + dir, Vector3.UP)
	else:
		velocity.x = 0.0
		velocity.z = 0.0
	if is_on_floor():
		if is_on_wall():
			velocity.y = JUMP
	else:
		velocity.y -= _gravity * delta
	move_and_slide()
