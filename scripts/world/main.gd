extends Node3D
## Builds the Chapter 1 prototype level: sky, ground, track with 6 stations, train, pickups,
## trees, sabotage, player and HUD. Everything is grey-box for now.

const SEED := 20261008
const PICKUP_SPACING := 22.0
const GOLD_ROCKS_PER_SEGMENT := 3
const TREES := 1200

var track: Track
var train: Train
var player: Player
var hud: HUD
var _env: Environment
var _rng := RandomNumberGenerator.new()


func _ready() -> void:
	_rng.seed = SEED
	_build_environment()
	_build_ground()

	track = Track.new()
	track.name = "Track"
	add_child(track)
	track.build(_rng)
	Game.track = track

	var start_station := int(Game.checkpoint.get("station", 0))
	track.place_initial_gaps(_rng)
	# Gaps behind the checkpoint are already fixed
	for i in track.piece_count:
		if track.piece_center(i) < track.station_distances[start_station] and track.is_broken(i):
			track.repair_piece(i)

	for i in track.station_distances.size():
		var st := Station.new()
		add_child(st)
		st.setup(track, i)
		st.shop_requested.connect(func(s: Station): hud.open_shop(s))

	_spawn_pickups()
	_spawn_trees()

	train = Train.new()
	train.name = "Train"
	add_child(train)
	train.setup(track, track.station_distances[start_station] + 18.0)
	train.current_station = start_station  # standing in the start station; don't re-trigger it
	if Game.checkpoint.has("train"):
		train.load_state(Game.checkpoint.train)
	Game.train = train

	var sab := SabotageManager.new()
	sab.name = "Sabotage"
	add_child(sab)
	Game.sabotage = sab

	player = Player.new()
	player.name = "Player"
	add_child(player)
	# Start on the station platform next to the locomotive
	var t := track.transform_at(train.distance - 4.0)
	player.global_position = t.origin + t.basis.x * 3.5 + Vector3.UP * 1.3
	player.look_at(train.cars[0].global_position + Vector3.UP * 1.5, Vector3.UP)
	player.rotation.x = 0.0
	player.rotation.z = 0.0

	hud = HUD.new()
	hud.player = player
	add_child(hud)

	Game.wind_changed.connect(_on_wind_changed)
	if start_station == 0:
		Game.show_banner("TRUST ISSUES\nShe was taken. Follow the tracker: 5 stations to go.\nShovel coal, push the lever, repair the rails.")
	else:
		Game.show_banner("Back at Station %d" % start_station)


func _build_environment() -> void:
	var sky_mat := ProceduralSkyMaterial.new()
	sky_mat.sky_top_color = Color(0.35, 0.6, 0.95)
	sky_mat.sky_horizon_color = Color(0.75, 0.85, 0.95)
	sky_mat.ground_horizon_color = Color(0.6, 0.7, 0.55)
	var sky := Sky.new()
	sky.sky_material = sky_mat
	_env = Environment.new()
	_env.background_mode = Environment.BG_SKY
	_env.sky = sky
	_env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	_env.ambient_light_energy = 0.6
	_env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	_env.fog_enabled = true
	_env.fog_density = 0.002
	_env.fog_light_color = Color(0.75, 0.82, 0.9)
	var we := WorldEnvironment.new()
	we.environment = _env
	add_child(we)

	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-50, -35, 0)
	sun.light_energy = 1.0
	sun.shadow_enabled = true
	sun.directional_shadow_max_distance = 120.0
	add_child(sun)


func _on_wind_changed(active: bool) -> void:
	var tween := create_tween()
	tween.tween_property(_env, "fog_density", 0.02 if active else 0.002, 2.0)
	tween.parallel().tween_property(_env, "fog_light_color", Color(0.85, 0.92, 1.0) if active else Color(0.75, 0.82, 0.9), 2.0)


func _build_ground() -> void:
	var ground := StaticBody3D.new()
	ground.name = "Ground"
	ground.collision_layer = Build.LAYER_WORLD
	var cs := CollisionShape3D.new()
	cs.shape = WorldBoundaryShape3D.new()
	ground.add_child(cs)
	var mi := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(6000, 6000)
	mi.mesh = plane
	mi.material_override = Build.material(Color(0.36, 0.52, 0.24))
	mi.position = Vector3(0, -0.01, -1200)
	ground.add_child(mi)
	add_child(ground)


func _spawn_pickups() -> void:
	var pickups := Node3D.new()
	pickups.name = "Pickups"
	add_child(pickups)
	var items := ["coal", "coal", "wood", "wood", "scrap"]
	var d := Track.LEAD_IN + Track.STATION_LENGTH
	while d < track.get_length() - 20.0:
		var t := track.transform_at(d)
		var side := -1.0 if _rng.randf() < 0.5 else 1.0
		var item: String = items[_rng.randi() % items.size()]
		var amount := _rng.randi_range(2, 4) if item == "coal" else _rng.randi_range(1, 3)
		Pickup.create(pickups, item, amount, t.origin + t.basis.x * side * _rng.randf_range(2.5, 7.0))
		d += PICKUP_SPACING * _rng.randf_range(0.6, 1.4)
	for s in track.station_distances.size() - 1:
		for g in GOLD_ROCKS_PER_SEGMENT:
			var t := track.transform_at(_rng.randf_range(track.station_distances[s] + 50.0, track.station_distances[s + 1] - 50.0))
			var side := -1.0 if _rng.randf() < 0.5 else 1.0
			Pickup.create_gold_rock(pickups, t.origin + t.basis.x * side * _rng.randf_range(6.0, 14.0))


func _spawn_trees() -> void:
	var trunk := CylinderMesh.new()
	trunk.top_radius = 0.25
	trunk.bottom_radius = 0.3
	trunk.height = 2.0
	trunk.material = Build.material(Color(0.4, 0.27, 0.15))
	var crown := CylinderMesh.new()
	crown.top_radius = 0.0
	crown.bottom_radius = 1.8
	crown.height = 4.5
	crown.material = Build.material(Color(0.2, 0.5, 0.25))
	var transforms: Array[Transform3D] = []
	while transforms.size() < TREES:
		var t := track.transform_at(_rng.randf_range(0.0, track.get_length()))
		var side := -1.0 if _rng.randf() < 0.5 else 1.0
		var pos := t.origin + t.basis.x * side * _rng.randf_range(12.0, 120.0)
		pos += t.basis.z * _rng.randf_range(-15.0, 15.0)
		var close := track.point_at(track.closest_distance(pos)).distance_to(pos)
		if close < 10.0:
			continue
		var s := _rng.randf_range(0.8, 1.6)
		transforms.append(Transform3D(Basis().scaled(Vector3.ONE * s), pos))
	for part in [[trunk, 1.0], [crown, 4.2]]:
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.mesh = part[0]
		mm.instance_count = transforms.size()
		for i in transforms.size():
			var tr := transforms[i]
			mm.set_instance_transform(i, tr.translated(Vector3.UP * part[1] * tr.basis.get_scale().y))
		var mmi := MultiMeshInstance3D.new()
		mmi.multimesh = mm
		add_child(mmi)
