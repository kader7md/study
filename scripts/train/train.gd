class_name Train
extends Node3D
## The coal train (Blender models in assets/models/train). It follows the track by distance
## (no free physics, which keeps it stable online).
## Systems: furnace fuel, 3-way lever, speed (slower uphill), body health shown by the cars' cover
## (panels, roofs, doors break off and are refitted by hand), 6 locomotive wheels that fall off and are
## refitted by hand, crashes at broken rails,
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
const CRASH_SPEED := 4.0
## Crash damage = (speed - CRASH_SPEED) * CRASH_PER_MS + CRASH_BASE (a locked gate: half of it).
const CRASH_PER_MS := 3.5
const CRASH_BASE := 4.0
## With fewer than MIN_WHEELS_TO_MOVE wheels (or a wrecked train) it still crawls at this speed.
const LIMP_SPEED := 1.6

## Train health = 100: BODY (cover pieces) 50 + MECHANICS 50 (wheels 6 x 2.5, engine 20, chassis 15).
const BODY_MAX := 50.0
## A wheel falls off when its wear reaches 2.5 (= 5 % of the mechanics bar). Tighten it with the wrench before that.
const WHEEL_LIMIT := 2.5
const ENGINE_MAX := 20.0     # damaged mostly by water (crashing into a river at a broken bridge); fixed with engine oil
const CHASSIS_MAX := 15.0    # never falls off, only a value; welded at a station
const MECH_MAX := WHEEL_LIMIT * 6 + ENGINE_MAX + CHASSIS_MAX
const OIL_REPAIR := 10.0
## Track built with this much tilt (degrees) shakes the wheels loose; this much TIPS the train over sideways.
const BUMP_ROLL := 4.0
const TIP_ROLL := 8.0
const TIP_ANGLE := 65.0
## Degrees the train comes back up per crank of the come-along.
const CRANK_STEP := 5.0
const WRENCH_REPAIR := 0.6

## Things the crew carries out of the cargo car and what each costs from the inventory.
const CARRY_COST := {"plank": {"wood": 1}, "rail": {"scrap": 2}, "wheel": {"wheel": 1}, "panel": {"scrap": 2}}

var track: Track
var distance := 0.0
var speed := 0.0
var lever := 0
var fuel := 60.0
## Total health 0..100 (body + mechanics), read only.
var health: float:
	get: return body_health + mech_health()
var body_health := BODY_MAX
var engine_damage := 0.0
var chassis_damage := 0.0
var wheel_wear: Array[float] = []
var wheels := MAX_WHEELS
var current_station := -1
## Tipped over on badly built track: can't move until pulled back up with the come-along.
var tipped := false
var tip_angle := 0.0          # current lean in degrees (+ = towards the right side)
var tip_target := 0.0
var hook: HookSpot
var anchor: AnchorSpot
var _chain: WelderCable
var _anchors: Array[Node] = []
var _last_piece := -1
var cars: Array[AnimatableBody3D] = []
var total_length := 0.0

var _furnace: Node3D
var _wheel_nodes: Array[Node3D] = []
var _wheel_home: Array[Vector3] = []
var _wheel_state: Array[int] = []   # 0 ok, 1 missing, 2 placed but not bolted
var _wheel_slots: Array[Interactable] = []
## Breakable cover pieces of all cars (see BodyPart).
var parts: Array[BodyPart] = []
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
	_chain = WelderCable.new()
	add_child(_chain)
	_chain.visible = false
	_place_cars()


func save_state() -> Dictionary:
	return {"body": body_health, "engine": engine_damage, "chassis": chassis_damage, "wear": wheel_wear.duplicate(),
		"wheels": wheels, "fuel": fuel}


func load_state(state: Dictionary) -> void:
	body_health = state.get("body", body_health)
	engine_damage = state.get("engine", engine_damage)
	chassis_damage = state.get("chassis", chassis_damage)
	fuel = state.get("fuel", fuel)
	var wear: Array = state.get("wear", [])
	for i in mini(wear.size(), wheel_wear.size()):
		wheel_wear[i] = wear[i]
	var target := int(state.get("wheels", wheels))
	while wheels > target:
		lose_wheel(false)
	_sync_parts(false)


# --- Simulation -------------------------------------------------------------

func max_speed_now() -> float:
	if tipped:
		return 0.0
	if wheels < MIN_WHEELS_TO_MOVE or health <= 0.0:
		# softlock guard: a wrecked train can always limp on (or back) to a station at walking pace
		return LIMP_SPEED
	var s := MAX_SPEED
	s *= float(wheels) / MAX_WHEELS                       # each lost wheel: -1/6 of the speed
	s *= 1.0 - 0.5 * engine_damage / ENGINE_MAX           # a hurt engine has less power
	s *= 1.0 - 0.3 * chassis_damage / CHASSIS_MAX         # a bent chassis drags
	# uphill is slow, downhill a bit faster (in the direction of travel)
	var dir := 1.0 if lever >= 0 else -1.0
	s *= clampf(1.0 - track.grade_at(center_distance()) * dir * 8.0, 0.45, 1.25)
	if Game.wind_active:
		s *= 0.6
	return s


## Mechanics health 0..MECH_MAX: wheels (worn or missing) + engine + chassis.
func mech_health() -> float:
	var h := ENGINE_MAX - engine_damage + CHASSIS_MAX - chassis_damage
	for i in _wheel_state.size():
		if _wheel_state[i] == 0:
			h += WHEEL_LIMIT - wheel_wear[i]
	return h


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
			_hit_gap(track.blocking_gate(distance, distance + step) >= 0 and track.locked_gate_ahead(gap, Track.GATE_STOP + 0.5) >= 0)
	elif step < 0.0:
		var gap := track.blocking_distance(rear_distance(), rear_distance() + step)
		if gap >= 0.0:
			new_front = gap + 0.01 + total_length
			_hit_gap(track.blocking_gate(rear_distance(), rear_distance() + step) >= 0)
	var limited := clampf(new_front, total_length + 1.0, track.get_length() - 1.0)
	if limited != new_front:
		speed = 0.0
	if limited > distance:
		Game.add_stat("distance", limited - distance)
	distance = limited

	_check_track_quality()
	tip_angle = move_toward(tip_angle, tip_target, 90.0 * delta)
	_place_cars()
	_update_station()
	_update_smoke(delta)
	if is_instance_valid(hook) and is_instance_valid(anchor):
		var to := anchor.global_position + Vector3.UP * 1.0
		_chain.update(hook.global_position, to, hook.global_position.distance_to(to) * 1.02)
	for i in _wheel_nodes.size():
		if _wheel_state[i] == 0:
			_wheel_nodes[i].rotation.x -= speed * delta / 0.45


static func crash_damage(v: float) -> float:
	return (v - CRASH_SPEED) * CRASH_PER_MS + CRASH_BASE if v > CRASH_SPEED else 0.0


func _hit_gap(gate := false) -> void:
	var v := absf(speed)
	speed = 0.0
	if gate:
		# a locked gate: a soft stop below CRASH_SPEED, half the crash damage above it
		if v > CRASH_SPEED:
			take_damage(crash_damage(v) * 0.5)
			Game.say("BANG! The train hit the locked gate! Find the key nearby")
		elif _block_msg_cooldown <= 0.0 and v > 0.05:
			Game.say("Train stopped at a LOCKED GATE. Find the key: it glows beside the track")
		_block_msg_cooldown = 3.0
		return
	if v > CRASH_SPEED:
		take_damage(crash_damage(v))
		Game.say("CRASH! The train hit a broken rail!")
		if track.is_bridge_at(distance + 2.0) or track.is_bridge_at(rear_distance() - 2.0):
			engine_damage = minf(engine_damage + 6.0 + v, ENGINE_MAX)
			Game.say("The engine dipped into the river! Engine damaged (fix it with engine oil)")
	elif _block_msg_cooldown <= 0.0 and v > 0.05:
		Game.say("Train stopped: broken track ahead. Rebuild it!")
	_block_msg_cooldown = 3.0


## Crossing a badly built piece: bumpy (wheel wear) or so tilted that the train tips over.
func _check_track_quality() -> void:
	if tipped or absf(speed) < 0.3:
		return
	var i := track.piece_at(distance - 1.0) if speed > 0.0 else track.piece_at(rear_distance() + 1.0)
	if i == _last_piece:
		return
	_last_piece = i
	var roll := track.piece_roll(i)
	if absf(roll) >= TIP_ROLL and absf(speed) > 1.5:
		# a positive roll lifts the right rail, so the train falls to the left
		tip_over(-signf(roll))
	elif absf(roll) >= BUMP_ROLL:
		var ok := _ok_wheels()
		if not ok.is_empty():
			add_wheel_wear(ok[_rng.randi() % ok.size()], 0.4)
		Game.say("Bumpy track! (tilt %.0f°) The wheels are shaking loose" % absf(roll))


func tip_over(side: float) -> void:
	tipped = true
	tip_target = TIP_ANGLE * side
	speed = 0.0
	lever = 0
	take_damage(12.0)
	Game.say("THE TRAIN TIPPED OVER! Hook the come-along to the lifting eye, chain it to a tree on the high side and crank")
	_spawn_anchors(side)


## Trees and rocks on the high side (opposite to the fall) become anchor points.
func _spawn_anchors(side: float) -> void:
	for a in _anchors:
		if is_instance_valid(a):
			a.queue_free()
	_anchors.clear()
	var center := cars[0].global_position
	var d := center_distance()
	var right := track.flat_right(d)
	var found: Array[Vector3] = []
	if Game.terrain:
		for p: Vector3 in Game.terrain.anchor_points:
			if p.distance_to(center) < 35.0 and (p - center).dot(right) * side < -3.0:
				found.append(p)
	found.sort_custom(func(a: Vector3, b: Vector3): return a.distance_to(center) < b.distance_to(center))
	found = found.slice(0, 6)
	if found.size() < 2:
		# no trees nearby: big rocks to anchor to
		for k in 2:
			found.append(track.ground_point(d + (k - 0.5) * 8.0, -side * 12.0))
	for p in found:
		var a := AnchorSpot.new()
		a.train = self
		get_parent().add_child(a)
		a.global_position = p
		_anchors.append(a)


func attach_hook(h: HookSpot) -> bool:
	if not tipped:
		return false
	hook = h
	Game.say("Come-along hooked to the train. Now chain it to a tree or rock on the high side")
	return true


func attach_anchor(a: AnchorSpot) -> bool:
	if not tipped or hook == null:
		Game.say("First hook the come-along to the train's lifting eye")
		return false
	anchor = a
	_chain.visible = true
	Game.say("Chain anchored. Crank the come-along [LMB] to pull the train back up!")
	return true


## One pump of the come-along handle. Several players can crank together.
func crank() -> bool:
	if not tipped or not is_instance_valid(hook) or not is_instance_valid(anchor):
		return false
	tip_target = move_toward(tip_target, 0.0, CRANK_STEP)
	if absf(tip_target) < 1.0:
		tipped = false
		tip_target = 0.0
		hook = null
		anchor = null
		_chain.visible = false
		for a in _anchors:
			if is_instance_valid(a):
				a.queue_free()
		_anchors.clear()
		Game.say("Back on the rails!")
	return true


func _update_station() -> void:
	var s := track.station_at(center_distance())
	if s == -1:
		if current_station != -1:
			Game.on_train_left_station(current_station)
		current_station = -1
	elif is_stopped() and current_station != s:
		current_station = s
		Game.on_train_stopped_at_station(s)


## Damage is split: half to the body (pieces fly off), half to the mechanics
## (two random wheels wear, the chassis bends, the engine suffers).
func take_damage(amount: float) -> void:
	body_health = maxf(body_health - amount * 0.5, 0.0)
	var mech := amount * 0.5
	chassis_damage = minf(chassis_damage + mech * 0.4, CHASSIS_MAX)
	engine_damage = minf(engine_damage + mech * 0.4, ENGINE_MAX)
	var ok := _ok_wheels()
	for k in mini(2, ok.size()):
		add_wheel_wear(ok.pop_at(_rng.randi() % ok.size()), mech * 0.1)
	damaged.emit(amount)
	_sync_parts(true)
	if health <= 0.0:
		Game.say("The train is wrecked!")


func _ok_wheels() -> Array[int]:
	var ok: Array[int] = []
	for i in _wheel_state.size():
		if _wheel_state[i] == 0:
			ok.append(i)
	return ok


## Wears a wheel; at WHEEL_LIMIT it comes off and drops to the ground.
func add_wheel_wear(i: int, amount: float) -> void:
	if _wheel_state[i] != 0:
		return
	wheel_wear[i] = minf(wheel_wear[i] + amount, WHEEL_LIMIT)
	if wheel_wear[i] >= WHEEL_LIMIT:
		_detach_wheel(i, true)


## Wrench on a worn wheel: tightens it (less wear).
func tighten_wheel(i: int) -> bool:
	if _wheel_state[i] != 0 or wheel_wear[i] <= 0.0:
		return false
	wheel_wear[i] = maxf(wheel_wear[i] - WRENCH_REPAIR, 0.0)
	if wheel_wear[i] <= 0.0:
		Game.say("Wheel tightened")
	return true


## Engine oil (furnace [Q]) repairs the engine.
func oil_engine() -> bool:
	if engine_damage <= 0.0:
		Game.say("The engine is fine")
		return false
	if not Game.take("engine_oil"):
		Game.say("No engine oil (buy it at a station shop)")
		return false
	engine_damage = maxf(engine_damage - OIL_REPAIR, 0.0)
	Game.say("Engine oiled (engine %d%%)" % int(100.0 - engine_damage / ENGINE_MAX * 100.0))
	return true


## Station welder on the chassis weld points.
func weld_chassis(amount: float) -> void:
	chassis_damage = maxf(chassis_damage - amount, 0.0)


## Everything back to new (debug / tests).
func full_repair() -> void:
	weld_full()
	engine_damage = 0.0
	chassis_damage = 0.0
	for i in wheel_wear.size():
		wheel_wear[i] = 0.0
		if _wheel_state[i] != 0:
			_wheel_state[i] = 0
			_wheel_nodes[i].visible = true
			_wheel_nodes[i].position = _wheel_home[i]
	wheels = MAX_WHEELS


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

## A random good wheel comes off (used by checkpoint loading and tests).
func lose_wheel(announce := true) -> void:
	var ok := _ok_wheels()
	if not ok.is_empty():
		_detach_wheel(ok[_rng.randi() % ok.size()], announce)


func _detach_wheel(i: int, announce: bool) -> void:
	_wheel_state[i] = 1
	wheel_wear[i] = 0.0
	wheels -= 1
	_wheel_nodes[i].visible = false
	if announce:
		_drop_wheel(i)
		Game.add_stat("wheels_lost")
		wheel_lost.emit(wheels)
		Game.say("A wheel came off! (%d/%d, speed -%d%%) New wheels are sold at stations." % [wheels, MAX_WHEELS, int(100.0 / MAX_WHEELS)])


## The broken wheel drops off the train and rolls away (physics debris, not reusable).
func _drop_wheel(i: int) -> void:
	var from := _wheel_nodes[i].global_transform
	var body := RigidBody3D.new()
	body.collision_layer = Build.LAYER_DEBRIS
	body.collision_mask = Build.LAYER_WORLD | Build.LAYER_DEBRIS
	body.mass = 60.0
	get_parent().add_child(body)
	body.global_transform = from
	body.add_child(Props.instance("wheel"))
	var shape := CylinderShape3D.new()
	shape.radius = 0.45
	shape.height = 0.14
	var cs := CollisionShape3D.new()
	cs.shape = shape
	cs.rotation.z = PI * 0.5
	body.add_child(cs)
	var out := cars[0].global_basis.x * signf(_wheel_home[i].x)
	body.linear_velocity = out * 2.0 + Vector3.UP * 2.0 - cars[0].global_basis.z * speed * 0.6
	body.angular_velocity = cars[0].global_basis.x * speed
	get_tree().create_timer(60.0).timeout.connect(body.queue_free)


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
	wheel_wear[i] = 0.0
	wheels += 1
	Game.say("Wheel bolted on (%d/%d)" % [wheels, MAX_WHEELS])


func _make_wheel_slot(car: Node3D, i: int) -> void:
	var slot := WheelSlot.new()
	slot.train = self
	slot.index = i
	slot.position = _wheel_home[i]
	Build.collider(slot, Vector3(0.6, 1.1, 1.1), Vector3.ZERO)
	car.add_child(slot)
	_wheel_slots.append(slot)


# --- Body cover: panels, roofs, doors break off and get refitted ---------------------

func attached_count() -> int:
	return parts.filter(func(p: BodyPart): return p.attached).size()


## Breaks pieces off until the number still attached matches the body health.
func _sync_parts(fly := true) -> void:
	if parts.is_empty():
		return
	var want := clampi(int(ceil(body_health / (BODY_MAX / parts.size()) - 0.001)), 0, parts.size())
	var attached: Array[BodyPart] = []
	for p in parts:
		if p.attached:
			attached.append(p)
	while attached.size() > want:
		var p: BodyPart = attached.pop_at(_rng.randi() % attached.size())
		p.detach(fly)


## A piece was put back and nailed / welded on.
func on_part_refitted(part: BodyPart) -> void:
	body_health = minf(body_health + part.value(), BODY_MAX)
	Game.add_stat("panels")
	Game.say("Panel fixed (body %d%%)" % int(body_health / BODY_MAX * 100.0))


## Instantly refits every piece (debug / tests).
func weld_full() -> void:
	body_health = BODY_MAX
	for p in parts:
		p.refit_instantly()


# --- Cars --------------------------------------------------------------------------

func _place_cars() -> void:
	var d := distance
	var lean := Transform3D.IDENTITY
	if absf(tip_angle) > 0.01:
		# rotate about the rail on the low side
		var pivot := Vector3(signf(tip_angle) * Track.GAUGE * 0.5, 0.0, 0.0)
		lean = Transform3D.IDENTITY.translated(pivot) * Transform3D(Basis(Vector3.BACK, -deg_to_rad(tip_angle)), Vector3.ZERO) * Transform3D.IDENTITY.translated(-pivot)
	for i in cars.size():
		var length: float = CARS[i].length
		cars[i].global_transform = track.car_transform(d, d - length) * lean
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

	# Floor (a bit longer than the car so players can walk across the gap). Walls come from the cover pieces.
	var floor_width := 3.2 if type == "locomotive" else 2.8  # the engine has wide running boards beside the boiler
	Build.collider(car, Vector3(floor_width, 0.3, length + CAR_GAP), Vector3(0, FLOOR_HEIGHT - 0.15, 0))
	for child in model.find_children("*", "MeshInstance3D", true, false):
		if child.name.begins_with("Panel_") or child.name.begins_with("Door_"):
			var part := BodyPart.new()
			part.name = "Part_" + child.name
			car.add_child(part)
			part.setup(self, car, child)
			parts.append(part)

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
	# narrow enough to leave a walkway on each side from the cab front doors to the front of the engine
	Build.collider(boiler, Vector3(1.66, 1.9, 4.6), Vector3(0, f + 1.0, -2.2))
	Build.collider(boiler, Vector3(1.4, 1.2, 0.9), Vector3(0, f + 0.2, -4.5))
	_smoke = Build.sphere(car, 0.6, Vector3(0, f + 3.9, -4.0), Color(0.85, 0.85, 0.85, 0.6))

	for i in MAX_WHEELS:
		var node: Node3D = model.find_child("Wheel_%d" % i, true, false)
		_wheel_nodes.append(node)
		_wheel_home.append(node.position)
		_wheel_state.append(0)
		wheel_wear.append(0.0)
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
		var oil := ""
		if engine_damage > 0.0:
			oil = "\nEngine %d%%: [Q] engine oil (have %d)" % [int(100.0 - engine_damage / ENGINE_MAX * 100.0), Game.count("engine_oil")]
		return "Furnace %d%%: shovel coal (have %d)  [E]%s" % [int(fuel), Game.count("coal"), oil]
	var furnace_spot := ActionSpot.create(car, Vector3(1.4, 1.2, 0.9), Vector3(0, f + 0.6, 0.6),
		furnace_prompt, func(_p): add_coal())
	furnace_spot.alt_fn = func(_p): oil_engine()
	# lifting eyes for the come-along (when the train tips over)
	for side in [-1.0, 1.0]:
		var eye := HookSpot.new()
		eye.train = self
		eye.position = Vector3(side * 1.62, f + 0.3, -1.0)
		car.add_child(eye)
	# chassis weld points under the cab, glowing while the chassis is damaged
	for side in [-1.0, 1.0]:
		var spot := ChassisSpot.new()
		spot.train = self
		spot.position = Vector3(side * 1.2, 0.95, 1.5)
		car.add_child(spot)

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
	var takes := [["plank", Vector3(-0.6, f + 0.5, -2.0)], ["rail", Vector3(0.6, f + 0.5, -1.0)],
		["wheel", Vector3(-0.5, f + 0.5, 1.2)], ["panel", Vector3(0.55, f + 0.5, 2.2)]]
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
	Build.collider(body, Vector3(2.3, 2.15, 6.2), Vector3(0, FLOOR_HEIGHT + 1.1, 0))
	ActionSpot.create(car, Vector3(2.2, 2.0, 6.0), Vector3(0, FLOOR_HEIGHT + 1.1, 0),
		func(_p): return "Locked container. What's inside…?", func(_p): Game.say("It's locked tight."))


func _update_smoke(delta: float) -> void:
	if _smoke:
		var puff := 0.6 + absf(speed) * 0.05 + sin(Time.get_ticks_msec() * 0.01) * 0.1
		_smoke.scale = Vector3.ONE * (puff if fuel > 0.0 else 0.01)
		_smoke.rotation.y += delta
