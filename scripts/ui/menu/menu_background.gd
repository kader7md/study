class_name MenuBackground
extends Node3D
## Living backdrop for the main menu: the real Chapter 1 world (Track, Terrain, the departure station and the
## train, all from Main.SEED) in warm late-afternoon light, with a slow dolly/orbit camera and chimney smoke.
## Does NOT set Game.track / Game.train and spawns no Player, HUD or sabotage.

const MainScript := preload("res://scripts/world/main.gd")
const ORBIT_RADIUS := 15.0
const ORBIT_SPEED := 0.045     # rad/s of the sway phase

var track: Track
var train: Train
var terrain: Terrain
var station: Station
var camera: Camera3D
var time := 0.0
var _focus := Vector3.ZERO
var _smoke: CPUParticles3D


func _ready() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = MainScript.SEED
	_build_environment()

	track = Track.new()
	track.name = "Track"
	add_child(track)
	track.build(rng)

	station = Station.new()
	add_child(station)
	station.setup(track, 0)

	terrain = Terrain.new()
	terrain.name = "Terrain"
	add_child(terrain)
	terrain.build(track, rng)

	train = Train.new()
	train.name = "Train"
	add_child(train)
	train.setup(track, track.station_distances[0] + 18.0)
	train.current_station = 0
	train.fuel = Train.MAX_FUEL
	var old_smoke: Variant = train.get("_smoke")
	if old_smoke is Node3D:
		(old_smoke as Node3D).visible = false
	_add_smoke()

	camera = Camera3D.new()
	camera.fov = 55.0
	camera.far = 2500.0
	camera.h_offset = -3.2   # keep the train right of centre, the title sits on the left
	add_child(camera)
	camera.make_current()
	_update_camera(0.0)


func _process(delta: float) -> void:
	time += delta
	if train:
		train.fuel = Train.MAX_FUEL
	_update_camera(delta)


func _update_camera(_delta: float) -> void:
	if train == null or train.cars.is_empty():
		return
	var loco := train.cars[0]
	var tt := track.transform_at(train.distance - 6.0)
	_focus = tt.origin + Vector3.UP * 2.2
	# Sway between a 3/4 front view and a long side view on the open (non-platform) side, slowly drifting in and out
	var phase := sin(time * ORBIT_SPEED * TAU * 0.25 - 0.6)
	var angle := lerpf(0.35, 1.45, phase * 0.5 + 0.5)
	var side := -tt.basis.x
	var fwd := -tt.basis.z
	var radius := ORBIT_RADIUS + sin(time * 0.07) * 3.0
	var height := 3.6 + sin(time * 0.05 + 1.0) * 1.2
	var dir := (side * sin(angle) + fwd * cos(angle)).normalized()
	camera.global_position = _focus + dir * radius + Vector3.UP * height
	camera.look_at(_focus + fwd * 1.5, Vector3.UP)
	if _smoke and is_instance_valid(loco):
		_smoke.emitting = true


func _build_environment() -> void:
	var sky_mat := ProceduralSkyMaterial.new()
	sky_mat.sky_top_color = Color(0.38, 0.58, 0.9)
	sky_mat.sky_horizon_color = Color(0.98, 0.82, 0.62)
	sky_mat.ground_horizon_color = Color(0.85, 0.72, 0.55)
	sky_mat.ground_bottom_color = Color(0.35, 0.3, 0.25)
	sky_mat.sun_angle_max = 20.0
	sky_mat.sky_curve = 0.12
	var sky := Sky.new()
	sky.sky_material = sky_mat
	var env := Environment.new()
	env.background_mode = Environment.BG_SKY
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.ambient_light_energy = 0.7
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.tonemap_exposure = 1.05
	env.fog_enabled = true
	env.fog_density = 0.0016
	env.fog_light_color = Color(0.98, 0.84, 0.66)
	env.adjustment_enabled = true
	env.adjustment_saturation = 1.1
	env.adjustment_contrast = 1.04
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)

	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-24, -120, 0)
	sun.light_color = Color(1.0, 0.86, 0.68)
	sun.light_energy = 1.25
	sun.shadow_enabled = true
	sun.directional_shadow_max_distance = 120.0
	add_child(sun)


func _add_smoke() -> void:
	var loco := train.cars[0]
	_smoke = CPUParticles3D.new()
	_smoke.name = "ChimneySmoke"
	_smoke.position = Vector3(0, Train.FLOOR_HEIGHT + 3.7, -4.0)
	_smoke.amount = 28
	_smoke.lifetime = 4.5
	_smoke.preprocess = 4.0
	_smoke.direction = Vector3(0.15, 1, 0.35)
	_smoke.spread = 12.0
	_smoke.initial_velocity_min = 1.4
	_smoke.initial_velocity_max = 2.0
	_smoke.gravity = Vector3(0.35, 0.25, 0.5)
	_smoke.damping_min = 0.3
	_smoke.damping_max = 0.6
	_smoke.scale_amount_min = 0.6
	_smoke.scale_amount_max = 0.9
	var curve := Curve.new()
	curve.add_point(Vector2(0.0, 0.35))
	curve.add_point(Vector2(0.4, 1.2))
	curve.add_point(Vector2(1.0, 2.4))
	_smoke.scale_amount_curve = curve
	var ramp := Gradient.new()
	ramp.set_color(0, Color(0.9, 0.88, 0.86, 0.7))
	ramp.set_color(1, Color(0.9, 0.88, 0.86, 0.0))
	ramp.add_point(0.15, Color(0.88, 0.86, 0.84, 0.6))
	_smoke.color_ramp = ramp
	var mesh := SphereMesh.new()
	mesh.radius = 0.5
	mesh.height = 1.0
	mesh.radial_segments = 12
	mesh.rings = 6
	var mat := StandardMaterial3D.new()
	mat.vertex_color_use_as_albedo = true
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_PER_VERTEX
	mat.roughness = 1.0
	mesh.material = mat
	_smoke.mesh = mesh
	loco.add_child(_smoke)
