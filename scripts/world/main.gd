class_name Main
extends Node3D
## Builds the Chapter 1 level: sky, track with 6 stations over hills, rivers, a mountain pass,
## a lake and the coast; a locked gate (with its key beside it) in every segment; terrain, train (Blender models),
## pickups, sabotage, player and HUD. The RunDirector runs objectives, softlock guards and the ending.
## Everything is built from SEED, so every peer builds the same world (deterministic node names:
## Repair_<piece>, Gate_<seg>, Key_<seg>, Pickup_<n>, Station<i>).

const SEED := 20261008
const PICKUP_SPACING := 34.0
## Food pickups (apples, beans, chocolate, a sandwich, coffee) about this far apart along the line.
const FOOD_SPACING := 120.0
const GOLD_ROCKS_PER_SEGMENT := 3
## Supplies left beside every pre-placed gap (balance table in docs/GDD.md). Per broken piece:
## WOOD_PER_PIECE wood in 2-3 piles, RAILS_PER_PIECE rails, NAILS_PER_PIECE nails and BOLTS_PER_PIECE bolts in crates.
const WOOD_PER_PIECE := 4
const RAILS_PER_PIECE := 2
const BOLTS_PER_PIECE := 4
const NAILS_PER_PIECE := 8
const GAP_SUPPLY_RADIUS := 22.0

var track: Track
var train: Train
var player: Player
var hud: HUD
var director: RunDirector
var _env: Environment
var _rng := RandomNumberGenerator.new()
var _pickups: Node3D
var _pickup_count := 0


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
	# Gates behind the checkpoint (and any opened before) are open and have no key
	for s in start_station:
		if not s in Game.opened_gates:
			Game.opened_gates.append(s)
	track.spawn_gates(Game.opened_gates)

	for i in track.station_distances.size():
		var st := Station.new()
		add_child(st)
		st.setup(track, i)
		st.shop_requested.connect(_on_shop_requested)

	var terrain := Terrain.new()
	terrain.name = "Terrain"
	add_child(terrain)
	terrain.build(track, _rng)
	Game.terrain = terrain
	_spawn_pickups()

	# quest maps: a portal beside each quest gate; the maps themselves are built when the crew enters
	var quest := QuestManager.new()
	quest.name = "Quest"
	add_child(quest)
	quest.setup(self)

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

	# Start on the station platform next to the locomotive, looking at it
	var t := track.transform_at(train.distance - 4.0)
	var spawn_pos := t.origin + t.basis.x * 3.5 + Vector3.UP * 1.4
	var look := train.cars[0].global_position + Vector3.UP * 1.5 - spawn_pos
	var spawn_xform := Transform3D(Basis.looking_at(Vector3(look.x, 0.0, look.z), Vector3.UP), spawn_pos)
	# NET: one Player per peer under Main/Players (offline: just ours, right away). On a client `player` is set a
	# moment later, when the host spawns it (Net sets main.player and hud.player then).
	player = Net.spawn_players(self, spawn_xform)

	hud = HUD.new()
	hud.player = player
	add_child(hud)

	director = RunDirector.new()
	director.name = "RunDirector"
	director.main = self
	add_child(director)

	Game.wind_changed.connect(_on_wind_changed)
	if start_station == 0:
		print("[banner] TRUST ISSUES (intro)")
		hud.show_intro("TRUST ISSUES", "She was taken. Follow the tracker: 5 stations to go.")
	else:
		Game.show_banner("Back at Station %d" % start_station)


## [E] on a station shop. NET: when a client pressed it (the action runs on the host), open the shop on their screen.
func _on_shop_requested(s: Station) -> void:
	if Net.remote_actor() != 0:
		Net.open_shop_for(Net.remote_actor(), s.index)
		return
	hud.open_shop(s)


func _build_environment() -> void:
	var sky_mat := ProceduralSkyMaterial.new()
	sky_mat.sky_top_color = Color(0.3, 0.52, 0.85)
	sky_mat.sky_horizon_color = Color(0.68, 0.77, 0.86)
	sky_mat.ground_horizon_color = Color(0.5, 0.56, 0.48)
	sky_mat.ground_bottom_color = Color(0.25, 0.28, 0.22)
	sky_mat.sky_energy_multiplier = 0.9
	var sky := Sky.new()
	sky.sky_material = sky_mat
	_env = Environment.new()
	_env.background_mode = Environment.BG_SKY
	_env.sky = sky
	_env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	_env.ambient_light_energy = 0.45
	_env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	_env.tonemap_exposure = 0.92
	_env.tonemap_white = 6.0
	_env.adjustment_enabled = true
	_env.adjustment_saturation = 1.0
	_env.fog_enabled = true
	_env.fog_density = 0.0008
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
	tween.tween_property(_env, "fog_density", 0.02 if active else 0.0008, 2.0)
	tween.parallel().tween_property(_env, "fog_light_color", Color(0.85, 0.92, 1.0) if active else Color(0.75, 0.82, 0.9), 2.0)


# --- Pickups (balance: see the table in docs/GDD.md) -----------------------------------------

func _spawn_pickups() -> void:
	_pickups = Node3D.new()
	_pickups.name = "Pickups"
	add_child(_pickups)
	# 1. Scattered along the whole line, a few metres beside the rails
	var items := ["coal", "coal", "coal", "wood", "scrap"]
	var d := Track.LEAD_IN + Track.STATION_LENGTH
	while d < track.get_length() - 20.0:
		var side := -1.0 if _rng.randf() < 0.5 else 1.0
		var item: String = items[_rng.randi() % items.size()]
		var amount := _rng.randi_range(2, 4) if item == "coal" else _rng.randi_range(1, 3)
		var p := track.ground_point(d, side * _rng.randf_range(2.5, 7.0))
		if _good_spot(d, p):
			add_pickup(item, amount, p)
		d += PICKUP_SPACING * _rng.randf_range(0.6, 1.4)
	# 2. A supply cache beside every pre-placed gap: wood, scrap and nails for that gap, plus coal;
	#    a gold rock at every other gap
	for g in track.initial_gaps.size():
		var gap: Dictionary = track.initial_gaps[g]
		var n := int(gap.count)
		var center := track.piece_center(int(gap.first)) + (n - 1) * Track.PIECE_LENGTH * 0.5
		var wood_piles: Array = [3, 2] if n == 1 else [3, 3, 3]
		for w: int in wood_piles:
			_cache(center, "wood", w)
		_cache(center, "rail", RAILS_PER_PIECE * n)
		_cache(center, "bolts", BOLTS_PER_PIECE * n)
		_cache(center, "nails", NAILS_PER_PIECE * n)
		_cache(center, "coal", _rng.randi_range(3, 4))
		if g % 2 == 0:
			_cache(center, "gold", 0)
	# 3. Beside every gate: a coal pile and a gold rock (the crew stops here anyway)
	for s in track.gate_count():
		var gd := track.gate_distance(s) - 6.0
		_cache(gd, "coal", 4)
		_cache(gd, "gold", 0)
	# 4. A few more gold rocks further from the track
	for s in track.station_distances.size() - 1:
		for g in GOLD_ROCKS_PER_SEGMENT:
			var d2 := _rng.randf_range(track.station_distances[s] + 50.0, track.station_distances[s + 1] - 50.0)
			var side := -1.0 if _rng.randf() < 0.5 else 1.0
			var p := track.ground_point(d2, side * _rng.randf_range(6.0, 14.0))
			if p.y > Track.WATER_LEVEL + 0.5:
				add_pickup("gold", 0, p)
	# 5. Food along the line (its own random stream, so the pickups above stay where they were)
	var frng := RandomNumberGenerator.new()
	frng.seed = SEED + 77
	var foods := ["apple", "apple", "beans", "chocolate", "sandwich", "coffee"]
	var fd := Track.LEAD_IN + Track.STATION_LENGTH + 40.0
	while fd < track.get_length() - 40.0:
		var side := -1.0 if frng.randf() < 0.5 else 1.0
		var food: String = foods[frng.randi() % foods.size()]
		var fp := track.ground_point(fd, side * frng.randf_range(2.5, 5.5))
		if _good_spot(fd, fp):
			add_pickup(food, 2 if food == "apple" else 1, fp)
		fd += FOOD_SPACING * frng.randf_range(0.6, 1.4)


## Adds a pickup named Pickup_<n> (n = spawn order, the same on every peer). item "gold" = a gold rock.
func add_pickup(item: String, amount: int, pos: Vector3) -> Pickup:
	var p: Pickup
	if item == "gold":
		p = Pickup.create_gold_rock(_pickups, pos)
	else:
		p = Pickup.create(_pickups, item, amount, pos)
	p.name = "Pickup_%d" % _pickup_count
	_pickup_count += 1
	return p


## A pickup on solid ground within GAP_SUPPLY_RADIUS of distance `center` (not on the gap itself).
func _cache(center: float, item: String, amount: int) -> void:
	for attempt in 16:
		var along := _rng.randf_range(6.0, GAP_SUPPLY_RADIUS - 6.0) * (-1.0 if _rng.randf() < 0.6 else 1.0)
		var side := -1.0 if _rng.randf() < 0.5 else 1.0
		var u := side * _rng.randf_range(3.0, 6.0 if item != "gold" else 7.5)
		var d := center + along
		var p := track.ground_point(d, u)
		if _good_spot(d, p):
			add_pickup(item, amount, p)
			return
	# fallback: right beside the track, just before the gap
	add_pickup(item, amount, track.ground_point(center - 8.0, 3.0))


func _good_spot(d: float, p: Vector3) -> bool:
	return p.y > Track.WATER_LEVEL + 0.5 and not track.is_bridge_at(d) and absf(p.y - track.point_at(d).y) < 2.5
