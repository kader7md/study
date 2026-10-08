class_name Eagle
extends CharacterBody3D
## Flies to the cargo car, steals resources, flies away.
## Kill it before it escapes (it swoops low over the cargo) to get the loot back.

enum State { APPROACH, STEAL, ESCAPE }

const SPEED := 14.0
const HP := 10.0
const STEAL_TIME := 1.5
const LOOT := ["wood", "scrap", "coal"]

var hp := HP
var state := State.APPROACH
var stolen := {}
var _timer := 0.0
var _escape_dir := Vector3.UP


static func spawn(parent: Node, pos: Vector3) -> Eagle:
	var e := Eagle.new()
	parent.add_child(e)
	e.global_position = pos
	return e


func _ready() -> void:
	add_to_group("enemy")
	collision_layer = Build.LAYER_ENEMY
	collision_mask = 0
	var cs := CollisionShape3D.new()
	var shape := SphereShape3D.new()
	shape.radius = 0.8
	cs.shape = shape
	add_child(cs)
	Build.sphere(self, 0.4, Vector3.ZERO, Color(0.35, 0.22, 0.12))
	Build.box(self, Vector3(2.2, 0.08, 0.5), Vector3.ZERO, Color(0.3, 0.18, 0.1))
	Build.sphere(self, 0.2, Vector3(0, 0.1, -0.45), Color(0.95, 0.95, 0.9))


func take_hit(amount: float) -> void:
	hp -= amount
	if hp > 0.0:
		return
	if not stolen.is_empty():
		for item: String in stolen:
			Game.add(item, stolen[item])
		Game.say("Eagle down! You got the stolen loot back")
	else:
		Game.say("Eagle down")
	queue_free()


func _physics_process(delta: float) -> void:
	var train := Game.train
	if train == null:
		queue_free()
		return
	var cargo := train.cars[1].global_position + Vector3.UP * 2.2
	match state:
		State.APPROACH:
			_fly_to(cargo, delta)
			if global_position.distance_to(cargo) < 1.5:
				state = State.STEAL
				_timer = STEAL_TIME
		State.STEAL:
			global_position = cargo  # ride along with the train while stealing
			_timer -= delta
			if _timer <= 0.0:
				_steal()
				state = State.ESCAPE
				_escape_dir = (Vector3(randf_range(-1, 1), 0.8, randf_range(-1, 1))).normalized()
				_timer = 6.0
		State.ESCAPE:
			global_position += _escape_dir * SPEED * delta
			_timer -= delta
			if _timer <= 0.0:
				queue_free()


func _fly_to(pos: Vector3, delta: float) -> void:
	var dir := pos - global_position
	var step := SPEED * delta
	if dir.length() <= step:
		global_position = pos
	else:
		global_position += dir.normalized() * step
		look_at(pos, Vector3.UP)


func _steal() -> void:
	var item: String = LOOT[randi() % LOOT.size()]
	var amount := mini(randi_range(1, 4), Game.count(item))
	if amount <= 0:
		Game.say("The eagle found nothing to steal")
		return
	Game.take(item, amount)
	stolen[item] = amount
	Game.say("🦅 An eagle stole %d %s! Hit it before it gets away!" % [amount, item])
