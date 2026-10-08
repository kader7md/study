extends Node3D
## Builds the Chapter 1 level: sky, track with 6 stations over hills, rivers, a mountain pass,
## a lake and the coast; terrain, train (Blender models), pickups, sabotage, player and HUD.

const SEED := 20261008
const PICKUP_SPACING := 22.0
const GOLD_ROCKS_PER_SEGMENT := 6

var track: Track
var train: Train
var player: Player
var hud: HUD
var _env: Environment
var _rng := RandomNumberGenerator.new()


func _ready() -> void:
	_rng.seed = SEED
	_build_environment()

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

	var terrain := Terrain.new()
	terrain.name = "Terrain"
	add_child(terrain)
	terrain.build(track, _rng)
	_spawn_pickups()

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
	player.global_position = t.origin + t.basis.x * 3.5 + Vector3.UP * 1.4
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
	_env.fog_density = 0.0012
	_env.fog_light_color = Color(0.75, 0.82, 0.9)
	var we := WorldEnvironment.new()
	we.environment = _env
	add_child(we)

	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-50, -35, 0)
	sun.light_energy = 1.0
	sun.shadow_enabled = true
	sun.directional_shadow_max_distance = 150.0
	add_child(sun)


func _on_wind_changed(active: bool) -> void:
	var tween := create_tween()
	tween.tween_property(_env, "fog_density", 0.02 if active else 0.0012, 2.0)
	tween.parallel().tween_property(_env, "fog_light_color", Color(0.85, 0.92, 1.0) if active else Color(0.75, 0.82, 0.9), 2.0)


func _spawn_pickups() -> void:
	var pickups := Node3D.new()
	pickups.name = "Pickups"
	add_child(pickups)
	var items := ["coal", "coal", "wood", "wood", "scrap"]
	var d := Track.LEAD_IN + Track.STATION_LENGTH
	while d < track.get_length() - 20.0:
		var side := -1.0 if _rng.randf() < 0.5 else 1.0
		var item: String = items[_rng.randi() % items.size()]
		var amount := _rng.randi_range(2, 4) if item == "coal" else _rng.randi_range(1, 3)
		var p := track.ground_point(d, side * _rng.randf_range(2.5, 7.0))
		if p.y > Track.WATER_LEVEL + 0.5 and not track.is_bridge_at(d):
			Pickup.create(pickups, item, amount, p)
		d += PICKUP_SPACING * _rng.randf_range(0.6, 1.4)
	for s in track.station_distances.size() - 1:
		for g in GOLD_ROCKS_PER_SEGMENT:
			var d2 := _rng.randf_range(track.station_distances[s] + 50.0, track.station_distances[s + 1] - 50.0)
			var side := -1.0 if _rng.randf() < 0.5 else 1.0
			var p := track.ground_point(d2, side * _rng.randf_range(6.0, 14.0))
			if p.y > Track.WATER_LEVEL + 0.5:
				Pickup.create_gold_rock(pickups, p)
