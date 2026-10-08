class_name Train
extends Node3D
## The coal train (Blender models in assets/models/train). It follows the track by distance
## (no free physics, which keeps it stable online).
## Systems: furnace fuel, 3-way lever, speed (slower uphill), body health shown as cracks that are
## welded shut, 6 locomotive wheels that fall off and are refitted by hand, crashes at broken rails,
## stopping at stations (checkpoints), cargo car where repair materials are taken out.

signal damaged(amount: float)
signal wheel_lost(remaining: int)

const CARS := [
	{"type": "locomotive", "length": 10.0},
	{"type": "cargo", "length": 8.0},
	{"type": "utility", "length": 8.0},
	{"type": "container", "length": 8.0},
]
const CAR_GAP := 1.0
const FLOOR_HEIGHT := 1.35
const DOOR := 1.0                 # gap in the side walls at each car end, for climbing aboard
const MAX_SPEED := 14.0           # m/s (~50 km/h)
const ACCEL := 1.6
const BRAKE := 4.0
const FRICTION := 0.35
const MAX_FUEL := 100.0
const COAL_FUEL := 12.0
const MAX_WHEELS := 6
const MIN_WHEELS_TO_MOVE := 3
const WHEEL_BOLT_HITS := 3
const PATCH_LIMIT := 60.0         # the train's own welder can't weld the body above this; station welder can
const CRACK_HP := 10.0            # each crack is 10 % of body health
const CRASH_SPEED := 4.0
const OIL_BUFF_TIME := 120.0
const WELDER_CABLE := 35.0

## Things the crew carries out of the cargo car and what each costs from the inventory.
const CARRY_COST := {"plank": {"wood": 1}, "rail": {"scrap": 2}, "wheel": {"wheel": 1}}

var track: Track
var distance := 0.0
var speed := 0.0
var lever := 0
var fuel := 60.0
var health := 100.0
var wheels := MAX_WHEELS
var current_station := -1
var oil_buff := 0.0
var cars: Array[AnimatableBody3D] = []
var total_length := 0.0
var welder: WelderSource

var _furnace: Node3D
var _wheel_nodes: Array[Node3D] = []
var _wheel_home: Array[Vector3] = []
var _wheel_state: Array[int] = []   # 0 ok, 1 missing, 2 placed but not bolted
var _wheel_slots: Array[Interactable] = []
var _cracks: Array[Node3D] = []
var _smoke: MeshInstance3D
var _block_msg_cooldown := 0.0
var _rng := RandomNumberGenerator.new()


func setup(t: Track, front_distance: float) -> void:
	track = t
	distance = front_distance
	_rng.seed = 7
	total_length = 0.0
	for c in CARS:
		total_length += c.length + CAR_GAP
	total_length -= CAR_GAP
	for c in CARS:
		cars.append(_build_car(c.type, c.length))
	_place_cars()


func save_state() -> Dictionary:
	return {"health": health, "wheels": wheels, "fuel": fuel}


func load_state(state: Dictionary) -> void:
	health = state.get("health", health)
	fuel = state.get("fuel", fuel)
	var target := int(state.get("wheels", wheels))
	while wheels > target:
		lose_wheel(false)
	_sync_cracks()


# --- Simulation -------------------------------------------------------------

func max_speed_now() -> float:
	if wheels < MIN_WHEELS_TO_MOVE or health <= 0.0:
		return 0.0
	var s := MAX_SPEED
	s *= 0.5 + 0.5 * health / 100.0
	s *= 1.0 - 0.12 * (MAX_WHEELS - wheels)
	# uphill is slow, downhill a bit faster (in the direction of travel)
	var dir := 1.0 if lever >= 0 else -1.0
	s *= clampf(1.0 - track.grade_at(center_distance()) * dir * 8.0, 0.45, 1.25)
	if Game.wind_active:
		s *= 0.6
	if oil_buff > 0.0:
		s *= 1.2
	return s


func rear_distance() -> float:
	return distance - total_length


func center_distance() -> float:
	return distance - total_length * 0.5


func furnace_position() -> Vector3:
	return _furnace.global_position if _furnace else global_position


func is_stopped() -> bool:
	return absf(speed) < 0.2


func _physics_process(delta: float) -> void:
	if track == null:
		return
	_block_msg_cooldown = maxf(_block_msg_cooldown - delta, 0.0)
	oil_buff = maxf(oil_buff - delta, 0.0)

	var uphill := maxf(track.grade_at(center_distance()) * signf(speed), 0.0)
	var burn := (0.12 + 0.06 * absf(speed)) * (1.6 if Game.wind_active else 1.0) * (1.0 + uphill * 15.0)
	fuel = maxf(fuel - burn * delta, 0.0)

	var top := max_speed_now()
	if lever != 0 and fuel > 0.0 and top > 0.0:
		var rate := BRAKE if speed * lever < 0.0 else ACCEL
		speed = move_toward(speed, lever * top, rate * delta)
	else:
		speed = move_toward(speed, 0.0, (BRAKE if lever == 0 else FRICTION) * delta)
		# Without power or brake the train rolls downhill
		if lever != 0:
			speed -= track.grade_at(center_distance()) * 9.8 * 0.5 * delta

	var step := speed * delta
	var new_front := distance + step
	if step > 0.0:
		var gap := track.blocking_distance(distance, distance + step)
		if gap >= 0.0:
			new_front = gap - 0.01
			_hit_gap()
	elif step < 0.0:
		var gap := track.blocking_distance(rear_distance(), rear_distance() + step)
		if gap >= 0.0:
			new_front = gap + 0.01 + total_length
			_hit_gap()
	var limited := clampf(new_front, total_length + 1.0, track.get_length() - 1.0)
	if limited != new_front:
		speed = 0.0
	distance = limited

	_place_cars()
	_update_station()
	_update_smoke(delta)
	for i in _wheel_nodes.size():
		if _wheel_state[i] == 0:
			_wheel_nodes[i].rotation.x -= speed * delta / 0.45


func _hit_gap() -> void:
	var v := absf(speed)
	speed = 0.0
	if v > CRASH_SPEED:
		take_damage((v - CRASH_SPEED) * 6.0 + 5.0)
		if randf() < 0.5:
			lose_wheel()
		Game.say("CRASH! The train hit a broken rail!")
	elif _block_msg_cooldown <= 0.0 and v > 0.05:
		Game.say("Train stopped: broken track ahead. Rebuild it!")
	_block_msg_cooldown = 3.0


func _update_station() -> void:
	var s := track.station_at(center_distance())
	if s == -1:
		current_station = -1
	elif is_stopped() and current_station != s:
		current_station = s
		Game.on_train_stopped_at_station(s)


func take_damage(amount: float) -> void:
	health = maxf(health - amount, 0.0)
	damaged.emit(amount)
	_sync_cracks()
	if health <= 0.0:
		Game.say("The train is wrecked! Weld the cracks to move again.")


func add_coal() -> bool:
	if fuel >= MAX_FUEL - 1.0:
		Game.say("The furnace is full")
		return false
	if not Game.take("coal"):
		Game.say("No coal! Collect coal along the track or buy it at a station.")
		return false
	fuel = minf(fuel + COAL_FUEL, MAX_FUEL)
	return true


func lever_text() -> String:
	return ["REVERSE", "STOP", "FORWARD"][lever + 1]


# --- Wheels: fall off, get carried back, placed and bolted ----------------------------

func lose_wheel(announce := true) -> void:
	var ok: Array[int] = []
	for i in _wheel_state.size():
		if _wheel_state[i] == 0:
			ok.append(i)
	if ok.is_empty():
		return
	var i := ok[_rng.randi() % ok.size()]
	_wheel_state[i] = 1
	wheels -= 1
	_wheel_nodes[i].visible = false
	_wheel_slots[i].collision_layer = Build.LAYER_INTERACT
	if announce:
		_drop_wheel_visual(_wheel_nodes[i].global_transform)
		wheel_lost.emit(wheels)
		Game.say("A wheel fell off! (%d/%d) New wheels are sold at stations." % [wheels, MAX_WHEELS])


func _drop_wheel_visual(from: Transform3D) -> void:
	var w := Props.instance("wheel")
	get_parent().add_child(w)
	w.global_transform = from
	var tween := w.create_tween()
	tween.tween_property(w, "global_position", from.origin + from.basis.x * 3.0 + Vector3.DOWN * 0.3, 0.8)
	tween.parallel().tween_property(w, "rotation:z", 1.4, 0.8)
	tween.tween_interval(8.0)
	tween.tween_callback(w.queue_free)


func wheel_state(i: int) -> int:
	return _wheel_state[i]


func wheel_slot(i: int) -> Interactable:
	return _wheel_slots[i]


## Wheel carried to slot i: lift it in (animated), then it needs bolting with the hammer.
func place_wheel(i: int) -> void:
	_wheel_state[i] = 2
	var node := _wheel_nodes[i]
	node.visible = true
	var home := _wheel_home[i]
	var side := signf(home.x)
	node.position = home + Vector3(side * 1.2, 0.9, 0)
	node.rotation = Vector3(0, 0, side * 0.6)
	var tween := node.create_tween()
	tween.tween_property(node, "position", home + Vector3(side * 0.5, 0.15, 0), 0.35).set_ease(Tween.EASE_OUT)
	tween.parallel().tween_property(node, "rotation:z", 0.0, 0.35)
	tween.tween_property(node, "position", home, 0.2).set_trans(Tween.TRANS_BACK)


func bolt_wheel(i: int) -> void:
	_wheel_state[i] = 0
	wheels += 1
	_wheel_slots[i].collision_layer = 0
	Game.say("Wheel bolted on (%d/%d)" % [wheels, MAX_WHEELS])


func _make_wheel_slot(car: Node3D, i: int) -> void:
	var slot := WheelSlot.new()
	slot.train = self
	slot.index = i
	slot.position = _wheel_home[i]
	Build.collider(slot, Vector3(0.6, 1.1, 1.1), Vector3.ZERO)
	slot.collision_layer = 0
	car.add_child(slot)
	_wheel_slots.append(slot)


# --- Cracks: body damage you can see and weld -------------------------------------

func crack_count() -> int:
	return int(ceil((100.0 - health) / CRACK_HP - 0.001))


func _sync_cracks() -> void:
	var want := clampi(crack_count(), 0, 10)
	while _cracks.size() > want:
		_cracks.pop_back().queue_free()
	while _cracks.size() < want:
		var crack := Crack.new()
		crack.train = self
		var car := cars[_rng.randi() % cars.size()]
		var length: float = CARS[cars.find(car)].length
		var side := -1.0 if _rng.randf() < 0.5 else 1.0
		crack.position = Vector3(side * 1.5, FLOOR_HEIGHT + _rng.randf_range(0.15, 0.6), _rng.randf_range(-length * 0.35, length * 0.35))
		crack.rotation.y = PI * 0.5 * side
		car.add_child(crack)
		_cracks.append(crack)


## A crack welded shut. The train's own welder stops at PATCH_LIMIT.
func weld_crack(crack: Node3D, source: WelderSource) -> bool:
	if source.kind != "station" and health >= PATCH_LIMIT:
		Game.say("The train's welder is too weak above %d%%: use a station welder" % int(PATCH_LIMIT))
		return false
	var cap := 100.0 if source.kind == "station" else PATCH_LIMIT
	health = minf(health + CRACK_HP, cap)
	_cracks.erase(crack)
	crack.queue_free()
	_sync_cracks()
	Game.say("Crack welded (%d%%)" % int(health))
	return true


func weld_full() -> void:
	health = 100.0
	_sync_cracks()


# --- Cars --------------------------------------------------------------------------

func _place_cars() -> void:
	var d := distance
	for i in cars.size():
		var length: float = CARS[i].length
		cars[i].global_transform = track.car_transform(d, d - length)
		d -= length + CAR_GAP


func _build_car(type: String, length: float) -> AnimatableBody3D:
	var car := AnimatableBody3D.new()
	car.name = type.capitalize()
	car.collision_layer = Build.LAYER_TRAIN
	car.collision_mask = 0
	car.sync_to_physics = true
	add_child(car)
	var model := Props.instance(type)
	car.add_child(model)

	# Floor (a bit longer than the car so players can walk across the gap) and side walls with door gaps
	Build.collider(car, Vector3(2.8, 0.3, length + CAR_GAP), Vector3(0, FLOOR_HEIGHT - 0.15, 0))
	var wall_len := length - 2.0 * DOOR
	var wall_z := 0.0
	if type == "locomotive":
		wall_len = 3.6
		wall_z = 2.1
	if type != "container":
		for side in [-1, 1]:
			Build.collider(car, Vector3(0.12, 0.9, wall_len), Vector3(side * 1.4, FLOOR_HEIGHT + 0.45, wall_z))

	match type:
		"locomotive":
			_build_locomotive(car, model, length)
		"cargo":
			_build_cargo(car, length)
		"utility":
			_build_utility(car, length)
		"container":
			_build_container(car, length)
	return car


func _build_locomotive(car: Node3D, model: Node3D, length: float) -> void:
	var f := FLOOR_HEIGHT
	var boiler := StaticBody3D.new()
	boiler.collision_layer = Build.LAYER_TRAIN
	car.add_child(boiler)
	Build.collider(boiler, Vector3(2.0, 2.0, 4.8), Vector3(0, f + 1.0, -2.3))
	_smoke = Build.sphere(car, 0.6, Vector3(0, f + 3.9, -4.0), Color(0.85, 0.85, 0.85, 0.6))

	for i in MAX_WHEELS:
		var node: Node3D = model.find_child("Wheel_%d" % i, true, false)
		_wheel_nodes.append(node)
		_wheel_home.append(node.position)
		_wheel_state.append(0)
		_make_wheel_slot(car, i)

	# Furnace door (shovel coal)
	_furnace = Build.box(car, Vector3(1.0, 0.8, 0.2), Vector3(0, f + 0.6, 0.45), Color(0.15, 0.15, 0.15))
	var glow := Build.box(_furnace, Vector3(0.6, 0.35, 0.05), Vector3(0, 0.05, 0.11), Color.WHITE)
	var glow_mat := StandardMaterial3D.new()
	glow_mat.albedo_color = Color(1.0, 0.5, 0.1)
	glow_mat.emission_enabled = true
	glow_mat.emission = Color(1.0, 0.4, 0.05)
	glow_mat.emission_energy_multiplier = 2.5
	glow.material_override = glow_mat
	var furnace_prompt := func(_p):
		var oil := "\n[Q] use engine oil (+20%% speed)" if Game.has("engine_oil") else ""
		return "Furnace %d%%: shovel coal (have %d)  [E]%s" % [int(fuel), Game.count("coal"), oil]
	var furnace_spot := ActionSpot.create(car, Vector3(1.4, 1.2, 0.9), Vector3(0, f + 0.6, 0.6),
		furnace_prompt, func(_p): add_coal())
	furnace_spot.alt_fn = func(_p):
		if Game.take("engine_oil"):
			oil_buff = OIL_BUFF_TIME
			Game.say("Engine oiled: faster for %d s" % int(OIL_BUFF_TIME))

	# Lever
	var lever_mesh := Build.box(car, Vector3(0.1, 0.9, 0.1), Vector3(-0.9, f + 0.55, 1.6), Color(0.95, 0.7, 0.2))
	Build.sphere(lever_mesh, 0.1, Vector3(0, 0.45, 0), Color(0.6, 0.1, 0.08))
	var lever_spot := ActionSpot.create(car, Vector3(0.6, 1.2, 0.6), Vector3(-0.9, f + 0.6, 1.6),
		func(_p): return "Lever: %s   [E] forward / [Q] back" % lever_text(),
		func(_p):
			lever = mini(lever + 1, 1)
			lever_mesh.rotation.x = -lever * 0.5)
	lever_spot.alt_fn = func(_p):
		lever = maxi(lever - 1, -1)
		lever_mesh.rotation.x = -lever * 0.5


func _build_cargo(car: Node3D, length: float) -> void:
	var f := FLOOR_HEIGHT
	var takes := [["plank", Vector3(-0.6, f + 0.5, -2.0)], ["rail", Vector3(0.6, f + 0.5, -1.0)], ["wheel", Vector3(-0.5, f + 0.5, 1.2)]]
	for entry in takes:
		var item: String = entry[0]
		var prompt := func(p):
			if p and p.carried_item != "":
				return "Hands full ([G] put back)"
			return "Take a %s (%s)  [E]   · cargo: %s" % [item, Game.cost_text(CARRY_COST[item]), _cargo_summary()]
		ActionSpot.create(car, Vector3(1.0, 1.0, 1.0), entry[1], prompt, func(p): take_item(p, item))


func _cargo_summary() -> String:
	return "coal %d · wood %d · scrap %d · nails %d · wheels %d" % [
		Game.count("coal"), Game.count("wood"), Game.count("scrap"), Game.count("nails"), Game.count("wheel")]


## A player takes a repair item out of the cargo car (paid from the crew inventory).
func take_item(player: Node, item: String) -> bool:
	if player == null or player.carried_item != "":
		return false
	if not Game.pay(CARRY_COST[item]):
		Game.say("Not enough for a %s (needs %s)" % [item, Game.cost_text(CARRY_COST[item])])
		return false
	player.carry(item)
	return true


func _build_utility(car: Node3D, length: float) -> void:
	var f := FLOOR_HEIGHT
	welder = WelderSource.create(car, "train", WELDER_CABLE, Vector3(0.7, f, 2.4))
	ActionSpot.create(car, Vector3(1.2, 1.2, 1.0), Vector3(0.7, f + 0.5, 2.4),
		func(_p): return "Welder machine (cable %d m). Pick the welder [2] near it to plug in" % int(WELDER_CABLE),
		func(_p): pass)
	Build.box(car, Vector3(1.4, 0.9, 0.9), Vector3(-0.5, f + 0.45, -2.5), Color(0.5, 0.35, 0.2))
	ActionSpot.create(car, Vector3(1.6, 1.2, 1.2), Vector3(-0.5, f + 0.6, -2.5),
		func(_p): return "Crafting table (spear, blueprints): coming in M7", func(_p): pass)
	Build.cylinder(car, 0.6, 0.8, Vector3(-0.5, f + 0.4, 0), Color(0.45, 0.3, 0.15))
	ActionSpot.create(car, Vector3(1.4, 1.2, 1.4), Vector3(-0.5, f + 0.6, 0),
		func(_p): return "Meeting table (vote): coming in M4", func(_p): pass)
	Build.box(car, Vector3(0.9, 0.6, 0.9), Vector3(-0.6, f + 0.3, 2.6), Color(0.7, 0.68, 0.62))
	ActionSpot.create(car, Vector3(1.0, 1.2, 1.0), Vector3(-0.6, f + 0.6, 2.6),
		func(_p): return "Sacrifice altar (goat revive): coming in M5", func(_p): pass)


func _build_container(car: Node3D, length: float) -> void:
	var body := StaticBody3D.new()
	body.collision_layer = Build.LAYER_TRAIN
	car.add_child(body)
	Build.collider(body, Vector3(2.5, 2.3, 6.4), Vector3(0, FLOOR_HEIGHT + 1.15, 0))
	ActionSpot.create(car, Vector3(2.7, 2.2, 6.6), Vector3(0, FLOOR_HEIGHT + 1.1, 0),
		func(_p): return "Locked container. What's inside…?", func(_p): Game.say("It's locked tight."))


func _update_smoke(delta: float) -> void:
	if _smoke:
		var puff := 0.6 + absf(speed) * 0.05 + sin(Time.get_ticks_msec() * 0.01) * 0.1
		_smoke.scale = Vector3.ONE * (puff if fuel > 0.0 else 0.01)
		_smoke.rotation.y += delta
