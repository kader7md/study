class_name Train
extends Node3D
## The coal train. It follows the track by distance (no free physics, which keeps it stable online).
## Systems: furnace fuel, 3-way lever, speed, body health, wheels, crashes at broken rails,
## stopping at stations (checkpoints), on-track patching (station welding is in Station).

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
const MAX_SPEED := 14.0          # m/s (~50 km/h)
const ACCEL := 1.6
const BRAKE := 4.0
const FRICTION := 0.35
const MAX_FUEL := 100.0
const COAL_FUEL := 12.0          # fuel per shovelled coal
const MAX_WHEELS := 6
const MIN_WHEELS_TO_MOVE := 3
const PATCH_LIMIT := 60.0        # on-track patching can't go above this; welding at a station fixes the rest
const PATCH_COST := {"scrap": 2}
const PATCH_AMOUNT := 20.0
const CRASH_SPEED := 4.0         # hitting a gap faster than this damages the train
const OIL_BUFF_TIME := 120.0

var track: Track
var distance := 0.0              # front of the locomotive along the track
var speed := 0.0                 # m/s, negative = reverse
var lever := 0                   # -1 reverse, 0 stop (brake), 1 forward
var fuel := 60.0
var health := 100.0
var wheels := MAX_WHEELS
var current_station := -1        # station the train is standing in, or -1
var oil_buff := 0.0
var cars: Array[AnimatableBody3D] = []
var total_length := 0.0

var _furnace: Node3D
var _wheel_meshes: Array[MeshInstance3D] = []
var _smoke: MeshInstance3D
var _block_msg_cooldown := 0.0


func setup(t: Track, front_distance: float) -> void:
	track = t
	distance = front_distance
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
	wheels = int(state.get("wheels", wheels))
	fuel = state.get("fuel", fuel)
	_update_wheel_meshes()


# --- Simulation -------------------------------------------------------------

func max_speed_now() -> float:
	if wheels < MIN_WHEELS_TO_MOVE or health <= 0.0:
		return 0.0
	var s := MAX_SPEED
	s *= 0.5 + 0.5 * health / 100.0
	s *= 1.0 - 0.12 * (MAX_WHEELS - wheels)
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

	# Fuel
	var burn := (0.12 + 0.06 * absf(speed)) * (1.6 if Game.wind_active else 1.0)
	fuel = maxf(fuel - burn * delta, 0.0)

	# Speed
	var top := max_speed_now()
	if lever != 0 and fuel > 0.0 and top > 0.0:
		var rate := BRAKE if speed * lever < 0.0 else ACCEL
		speed = move_toward(speed, lever * top, rate * delta)
	else:
		speed = move_toward(speed, 0.0, (BRAKE if lever == 0 else FRICTION) * delta)

	# Move, stopping at broken rails
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


func _hit_gap() -> void:
	var v := absf(speed)
	speed = 0.0
	if v > CRASH_SPEED:
		take_damage((v - CRASH_SPEED) * 6.0 + 5.0)
		if randf() < 0.5:
			lose_wheel()
		Game.say("CRASH! The train hit a broken rail!")
	elif _block_msg_cooldown <= 0.0 and v > 0.05:
		Game.say("Train stopped: broken rail ahead. Repair it!")
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
	if health <= 0.0:
		Game.say("The train is wrecked! Patch it with scrap to move again.")


func lose_wheel() -> void:
	if wheels <= 0:
		return
	wheels -= 1
	_update_wheel_meshes()
	wheel_lost.emit(wheels)
	Game.say("A wheel fell off! (%d/%d left; new wheels are fitted at stations)" % [wheels, MAX_WHEELS])


func add_coal() -> bool:
	if fuel >= MAX_FUEL - 1.0:
		Game.say("The furnace is full")
		return false
	if not Game.take("coal"):
		Game.say("No coal! Collect coal along the track or buy it at a station.")
		return false
	fuel = minf(fuel + COAL_FUEL, MAX_FUEL)
	return true


func patch() -> void:
	if health >= PATCH_LIMIT:
		Game.say("Heavy damage can only be welded at a station")
		return
	if not Game.pay(PATCH_COST):
		Game.say("Need %s to patch the train" % Game.cost_text(PATCH_COST))
		return
	health = minf(health + PATCH_AMOUNT, PATCH_LIMIT)
	Game.say("Train patched (%d%%)" % int(health))


func weld_full() -> void:
	health = 100.0


func fit_wheel() -> void:
	wheels = mini(wheels + 1, MAX_WHEELS)
	_update_wheel_meshes()


func lever_text() -> String:
	return ["REVERSE", "STOP", "FORWARD"][lever + 1]


# --- Building the cars (grey-box) ----------------------------------------------

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

	var body_color: Color = {
		"locomotive": Color(0.25, 0.27, 0.3), "cargo": Color(0.55, 0.36, 0.2),
		"utility": Color(0.35, 0.45, 0.35), "container": Color(0.6, 0.25, 0.2),
	}[type]
	var w := 2.8
	var floor_y := FLOOR_HEIGHT
	# Floor (collider is a bit longer so players can walk across the gap between cars)
	Build.box(car, Vector3(w, 0.3, length), Vector3(0, floor_y - 0.15, 0), body_color.darkened(0.3))
	Build.collider(car, Vector3(w, 0.3, length + CAR_GAP), Vector3(0, floor_y - 0.15, 0))
	# Low side walls
	for side in [-1, 1]:
		Build.box(car, Vector3(0.12, 0.7, length), Vector3(side * w * 0.5, floor_y + 0.35, 0), body_color)
		Build.collider(car, Vector3(0.12, 0.9, length), Vector3(side * w * 0.5, floor_y + 0.45, 0))
	# Wheels (only the locomotive's are tracked for damage)
	for i in 3:
		for side in [-1, 1]:
			var z := -length * 0.35 + i * length * 0.35
			var wheel := Build.cylinder(car, 0.45, 0.2, Vector3(side * 0.85, 0.5, z), Color(0.12, 0.12, 0.12))
			wheel.rotation.z = PI * 0.5
			if type == "locomotive":
				_wheel_meshes.append(wheel)

	match type:
		"locomotive":
			_build_locomotive(car, length, floor_y)
		"cargo":
			_build_cargo(car, length, floor_y)
		"utility":
			_build_utility(car, length, floor_y)
		"container":
			_build_container(car, length, floor_y)
	return car


func _build_locomotive(car: Node3D, length: float, floor_y: float) -> void:
	# Boiler at the front, open cab behind it
	var boiler := Build.cylinder(car, 1.0, length * 0.5, Vector3(0, floor_y + 1.0, -length * 0.22), Color(0.18, 0.18, 0.2))
	boiler.rotation.x = PI * 0.5
	var boiler_body := StaticBody3D.new()
	boiler_body.collision_layer = Build.LAYER_TRAIN
	car.add_child(boiler_body)
	Build.collider(boiler_body, Vector3(2.0, 2.0, length * 0.5), Vector3(0, floor_y + 1.0, -length * 0.22))
	Build.cylinder(car, 0.3, 1.2, Vector3(0, floor_y + 2.4, -length * 0.4), Color(0.1, 0.1, 0.1))
	_smoke = Build.sphere(car, 0.6, Vector3(0, floor_y + 3.4, -length * 0.4), Color(0.8, 0.8, 0.8, 0.6))
	# Cab roof
	Build.box(car, Vector3(2.9, 0.15, length * 0.42), Vector3(0, floor_y + 2.6, length * 0.27), Color(0.5, 0.15, 0.12))

	# Furnace (shovel coal)
	_furnace = Build.box(car, Vector3(1.2, 1.0, 0.6), Vector3(0, floor_y + 0.5, 0.15), Color(0.35, 0.1, 0.05))
	var furnace_prompt := func(_p):
		var oil := "\n[Q] use engine oil (+20%% speed)" if Game.has("engine_oil") else ""
		return "Furnace %d%%: shovel coal (have %d)  [E]%s" % [int(fuel), Game.count("coal"), oil]
	var furnace_spot := ActionSpot.create(car, Vector3(1.4, 1.2, 0.9), Vector3(0, floor_y + 0.6, 0.2),
		furnace_prompt, func(_p): add_coal())
	furnace_spot.alt_fn = func(_p):
		if Game.take("engine_oil"):
			oil_buff = OIL_BUFF_TIME
			Game.say("Engine oiled: faster for %d s" % int(OIL_BUFF_TIME))

	# Lever
	var lever_mesh := Build.box(car, Vector3(0.12, 0.9, 0.12), Vector3(-0.9, floor_y + 0.6, 1.5), Color(0.8, 0.7, 0.2))
	var lever_spot := ActionSpot.create(car, Vector3(0.6, 1.2, 0.6), Vector3(-0.9, floor_y + 0.6, 1.5),
		func(_p): return "Lever: %s   [E] forward / [Q] back" % lever_text(),
		func(_p):
			lever = mini(lever + 1, 1)
			lever_mesh.rotation.x = -lever * 0.5)
	lever_spot.alt_fn = func(_p):
		lever = maxi(lever - 1, -1)
		lever_mesh.rotation.x = -lever * 0.5

	# Patch the body
	var patch_spot := ActionSpot.create(car, Vector3(0.6, 1.2, 0.6), Vector3(0.9, floor_y + 0.6, 1.5),
		func(_p):
			if health >= PATCH_LIMIT:
				return "Train body %d%%  (above %d%% needs welding at a station)" % [int(health), int(PATCH_LIMIT)]
			return "Patch train body %d%% (%s)  [hold E]" % [int(health), Game.cost_text(PATCH_COST)],
		func(_p): patch())
	patch_spot.hold_fn = func(_p): return 2.5
	Build.box(car, Vector3(0.5, 0.5, 0.5), Vector3(0.9, floor_y + 0.25, 1.5), Color(0.5, 0.5, 0.55))


func _build_cargo(car: Node3D, length: float, floor_y: float) -> void:
	for i in 3:
		Build.box(car, Vector3(0.9, 0.7, 0.9), Vector3(-0.7 + (i % 2) * 1.2, floor_y + 0.35, -2.5 + i * 1.6), Color(0.6, 0.45, 0.25))
	ActionSpot.create(car, Vector3(2.4, 1.2, length * 0.8), Vector3(0, floor_y + 0.6, 0),
		func(_p):
			return "Cargo: coal %d · wood %d · scrap %d · gold %d · nails %d" % [
				Game.count("coal"), Game.count("wood"), Game.count("scrap"), Game.count("gold"), Game.count("nails")],
		func(_p): pass)


func _build_utility(car: Node3D, length: float, floor_y: float) -> void:
	Build.box(car, Vector3(1.4, 0.9, 0.9), Vector3(0, floor_y + 0.45, -2.5), Color(0.5, 0.35, 0.2))
	ActionSpot.create(car, Vector3(1.6, 1.2, 1.2), Vector3(0, floor_y + 0.6, -2.5),
		func(_p): return "Crafting table (spear, blueprints): coming in M7", func(_p): pass)
	Build.cylinder(car, 0.7, 0.8, Vector3(0, floor_y + 0.4, 0), Color(0.45, 0.3, 0.15))
	ActionSpot.create(car, Vector3(1.6, 1.2, 1.6), Vector3(0, floor_y + 0.6, 0),
		func(_p): return "Meeting table (vote): coming in M4", func(_p): pass)
	Build.box(car, Vector3(1.0, 0.6, 1.0), Vector3(0, floor_y + 0.3, 2.6), Color(0.7, 0.68, 0.62))
	ActionSpot.create(car, Vector3(1.2, 1.2, 1.2), Vector3(0, floor_y + 0.6, 2.6),
		func(_p): return "Sacrifice altar (goat revive): coming in M5", func(_p): pass)


func _build_container(car: Node3D, length: float, floor_y: float) -> void:
	Build.box(car, Vector3(2.5, 2.2, length * 0.8), Vector3(0, floor_y + 1.1, 0), Color(0.55, 0.2, 0.15))
	var body := StaticBody3D.new()
	body.collision_layer = Build.LAYER_TRAIN
	car.add_child(body)
	Build.collider(body, Vector3(2.5, 2.2, length * 0.8), Vector3(0, floor_y + 1.1, 0))
	ActionSpot.create(car, Vector3(2.7, 2.0, length * 0.85), Vector3(0, floor_y + 1.0, 0),
		func(_p): return "Locked container. What's inside…?", func(_p): Game.say("It's locked tight."))


func _update_wheel_meshes() -> void:
	for i in _wheel_meshes.size():
		_wheel_meshes[i].visible = i < wheels


func _update_smoke(delta: float) -> void:
	if _smoke:
		var puff := 0.6 + absf(speed) * 0.05 + sin(Time.get_ticks_msec() * 0.01) * 0.1
		_smoke.scale = Vector3.ONE * (puff if fuel > 0.0 else 0.01)
		_smoke.rotation.y += delta
