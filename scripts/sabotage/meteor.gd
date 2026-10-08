class_name Meteor
extends Node3D
## Falls for FALL_TIME seconds onto a target spot on the ground (a red warning circle shows where).
## The train keeps moving while it falls, so a badly timed meteor misses.

const FALL_TIME := 3.0
const HEIGHT := 140.0
const RADIUS := 5.0
const TRAIN_DAMAGE := 25.0
const PLAYER_DAMAGE := 35.0
const WHEEL_CHANCE := 0.4

var target := Vector3.ZERO
var _t := 0.0
var _rock: MeshInstance3D
var _warning: MeshInstance3D


static func spawn(parent: Node, target_pos: Vector3) -> Meteor:
	var m := Meteor.new()
	m.target = target_pos
	parent.add_child(m)
	return m


func _ready() -> void:
	global_position = target
	_warning = Build.cylinder(self, RADIUS, 0.05, Vector3(0, 0.05, 0), Color(1, 0.1, 0.05, 0.35))
	_rock = Build.sphere(self, 1.4, Vector3(0, HEIGHT, 0), Color(0.35, 0.15, 0.05))
	var glow := Build.sphere(_rock, 1.9, Vector3.ZERO, Color(1, 0.5, 0.1, 0.4))
	glow.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF


func _process(delta: float) -> void:
	_t += delta
	var k := clampf(_t / FALL_TIME, 0.0, 1.0)
	_rock.position.y = lerpf(HEIGHT, 0.5, k * k)
	if k >= 1.0:
		_impact()


func _impact() -> void:
	set_process(false)
	var train := Game.train
	var track := Game.track
	var hit_train := false
	if train:
		for car in train.cars:
			if car.global_position.distance_to(target) < RADIUS + 4.0:
				hit_train = true
		if hit_train:
			train.take_damage(TRAIN_DAMAGE)
			if randf() < WHEEL_CHANCE:
				train.lose_wheel()
			Game.say("☄ METEOR HIT THE TRAIN!")
	if track:
		var skip_from := train.rear_distance() - 1.0 if train else -1.0
		var skip_to := train.distance + 1.0 if train else -1.0
		var broken := track.break_around(target, RADIUS, skip_from, skip_to)
		if broken > 0:
			Game.say("☄ The meteor destroyed %d rail pieces!" % broken)
	for p in get_tree().get_nodes_in_group("player"):
		if p.global_position.distance_to(target) < RADIUS * 1.5:
			p.take_damage(PLAYER_DAMAGE)
	# Leave a crater
	_rock.queue_free()
	_warning.queue_free()
	Build.cylinder(self, RADIUS * 0.8, 0.04, Vector3(0, 0.03, 0), Color(0.15, 0.1, 0.08))
	get_tree().create_timer(30.0).timeout.connect(queue_free)
