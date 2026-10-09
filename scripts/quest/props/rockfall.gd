class_name Rockfall
extends Node3D
## A timed hazard high on a quest map ("Rockfall_<n>"): every PERIOD seconds a chunk of ice and rock breaks off the
## top of a cliff and tumbles down its face. A crackle and falling grit warn ~1.5 s before. Each peer runs the same
## schedule (from the map's clock) and only checks its OWN player: a hit costs health (through the host) and knocks
## you off the wall.

const PERIOD := 9.0
const WARN := 1.6
const FALL_TIME := 1.3
const HIT_RADIUS := 1.5
const DAMAGE := 22.0

var top := Vector3.ZERO      # global
var bottom := Vector3.ZERO
var phase := 0.0
var _rock: MeshInstance3D
var _grit: GPUParticles3D
var _clock := 0.0
var _hit_done := false


func _ready() -> void:
	_clock = phase
	_rock = MeshInstance3D.new()
	_rock.mesh = Terrain.nature_mesh("rock_small")
	_rock.top_level = true
	_rock.scale = Vector3.ONE * 1.3
	_rock.visible = false
	add_child(_rock)
	_grit = GPUParticles3D.new()
	_grit.top_level = true
	_grit.amount = 24
	_grit.lifetime = 1.4
	_grit.emitting = false
	var pm := ParticleProcessMaterial.new()
	pm.direction = Vector3.DOWN
	pm.spread = 15.0
	pm.initial_velocity_min = 1.0
	pm.initial_velocity_max = 3.0
	pm.gravity = Vector3(0, -9.8, 0)
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	pm.emission_box_extents = Vector3(0.6, 0.1, 0.6)
	_grit.process_material = pm
	var dot := BoxMesh.new()
	dot.size = Vector3.ONE * 0.07
	dot.material = Build.material(Color(0.85, 0.88, 0.95))
	_grit.draw_pass_1 = dot
	add_child(_grit)


func _physics_process(delta: float) -> void:
	_clock += delta
	var t := fmod(_clock, PERIOD)
	var warn_start := PERIOD - WARN - FALL_TIME
	_grit.global_position = top + Vector3.UP * 0.5
	_grit.emitting = t >= warn_start and t < PERIOD - FALL_TIME
	if t >= PERIOD - FALL_TIME:
		var k := (t - (PERIOD - FALL_TIME)) / FALL_TIME
		_rock.visible = true
		_rock.global_position = top.lerp(bottom, k * k) + Vector3.UP * 0.6
		_rock.rotation.x += delta * 7.0
		_check_hit()
	else:
		_rock.visible = false
		_hit_done = false


func _check_hit() -> void:
	if _hit_done or not Game.in_quest():
		return
	var me: Player = Game.quest._local_player()
	if me == null:
		return
	if me.global_position.distance_to(_rock.global_position) < HIT_RADIUS + 0.5 or \
			(me.global_position + Vector3.UP).distance_to(_rock.global_position) < HIT_RADIUS:
		_hit_done = true
		Game.say("Falling ice! Watch the cliff tops")
		me.climber.on_teleport()
		me.velocity = (me.global_position - _rock.global_position).normalized() * 3.0
		Net.request(me, &"take_damage", [DAMAGE])
