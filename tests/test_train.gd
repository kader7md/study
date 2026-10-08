extends Node
## Automated playthrough of the train core loop (runs headless):
##   godot --headless --path . res://tests/TestTrain.tscn
## Exit code 0 = all checks passed.

var main: Node3D
var train: Train
var track: Track
var player: Player
var failures := 0


func _ready() -> void:
	Game.new_game(false)
	Game.world_sabotage = false
	main = load("res://scenes/main/Main.tscn").instantiate()
	add_child(main)
	await _frames(5)
	train = Game.train
	track = Game.track
	player = main.player
	await _run()
	print("\n%s: %d failure(s)" % ["PASSED" if failures == 0 else "FAILED", failures])
	get_tree().quit(1 if failures > 0 else 0)


func check(ok: bool, what: String) -> void:
	print(("  ok   " if ok else "  FAIL ") + what)
	if not ok:
		failures += 1


func _frames(n: int) -> void:
	for i in n:
		await get_tree().physics_frame


func _wait(seconds: float) -> void:
	await get_tree().create_timer(seconds, true, true).timeout


func _wait_until(cond: Callable, timeout: float) -> bool:
	var t := 0.0
	while t < timeout:
		if cond.call():
			return true
		await get_tree().physics_frame
		t += get_physics_process_delta_time()
	return cond.call()


func _clear_gaps(from_d: float, to_d: float) -> void:
	for i in range(track.piece_at(from_d), track.piece_at(to_d) + 1):
		track.repair_piece(i)


func _place_train(front: float) -> void:
	train.lever = 0
	train.speed = 0.0
	train.distance = front


func _run() -> void:
	Engine.time_scale = 4.0
	print("Track, landscape & stations")
	check(track.station_distances.size() == 6, "6 stations (departure + 5 checkpoints)")
	check(track.station_distances[1] - track.station_distances[0] > 1400.0, "stations are far apart (%d m)" % int(track.station_distances[1] - track.station_distances[0]))
	var h0 := track.point_at(track.station_distances[0]).y
	var h3 := track.point_at(track.station_distances[3]).y
	check(h3 - h0 > 30.0, "track climbs into the mountains (station 3 is %d m higher)" % int(h3 - h0))
	check(track.bridge_count() > 10, "bridges over rivers and the lake (%d bridge pieces)" % track.bridge_count())
	var d_test := track.station_distances[0] + 300.0
	check(not track.is_bridge_at(d_test) and absf(track.ground_height(d_test, 0.0) - track.point_at(d_test).y) < 1.0, "ground meets the rails on an embankment")
	check(track.broken_count() > 0, "pre-placed broken track exists (%d pieces)" % track.broken_count())
	check(train.current_station == 0 and train.cars.size() == 4, "train with 4 cars starts in the departure station")
	check(train.cars[0].find_child("Wheel_0", true, false) != null, "locomotive uses the Blender model (has Wheel_0)")

	print("Fuel, lever & hills")
	var coal := Game.count("coal")
	var fuel := train.fuel
	train.add_coal()
	check(Game.count("coal") == coal - 1 and train.fuel > fuel, "shovelling coal uses 1 coal and adds fuel")
	train.fuel = 100.0
	_clear_gaps(train.distance, track.station_distances[1])
	var gap_piece := track.piece_at(train.distance + 60.0)
	check(track.break_piece(gap_piece), "can break a rail piece 60 m ahead")
	train.lever = 1
	await _wait(2.0)
	check(train.speed > 1.0, "lever forward + fuel → train accelerates (%.1f m/s)" % train.speed)

	print("Broken track blocks the train")
	var stopped := await _wait_until(func(): return train.is_stopped() and train.distance > gap_piece * Track.PIECE_LENGTH - 2.0, 30.0)
	check(stopped and train.distance <= gap_piece * Track.PIECE_LENGTH, "train stops at the broken track and doesn't pass it")
	train.lever = 0

	print("Rebuilding the track by hand")
	var repair := track.repair_at(gap_piece)
	check(repair != null and repair.step() == 1, "broken piece starts at step 1 (planks)")
	var wood := Game.count("wood")
	check(train.take_item(player, "plank") and player.carried_item == "plank", "take a plank from the cargo car")
	check(Game.count("wood") == wood - 1, "a plank costs 1 wood")
	check(not train.take_item(player, "plank"), "can't carry two things")
	var plank_slots := repair.find_children("*", "PlaceSlot", true, false).filter(func(s): return s.item == "plank")
	plank_slots[0].interact(player)
	check(player.carried_item == "" and repair._planks_placed == 1, "place the plank")
	train.take_item(player, "plank")
	plank_slots[1].interact(player)
	await _frames(2)
	check(repair.step() == 2, "both planks placed → step 2 (nails)")
	var nails_before := Game.count("nails")
	var nail_spots := repair.find_children("*", "NailSpot", true, false)
	check(nail_spots.size() == 4, "4 nails to drive in")
	for n in nail_spots:
		for k in NailSpot.HAMMER_HITS:
			n.on_tool_hit("hammer", player)
	check(Game.count("nails") == nails_before - 4, "each nail uses 1 nail")
	check(repair.step() == 3, "all nailed → step 3 (rails)")
	var scrap := Game.count("scrap")
	var rail_slots := repair.find_children("*", "PlaceSlot", true, false).filter(func(s): return s.item == "rail" and not s.is_queued_for_deletion())
	for s in rail_slots:
		train.take_item(player, "rail")
		s.interact(player)
	await _frames(2)
	check(Game.count("scrap") == scrap - 4, "two rails cost 4 scrap")
	check(repair.step() == 4, "rails placed → step 4 (bolting the joints)")
	var bolts := repair.find_children("*", "NailSpot", true, false).filter(func(n): return n.style == "bolt")
	check(bolts.size() == 4, "4 rail joints to bolt with fishplates")
	player.select_tool("welder")
	check(player.current_tool == "hammer", "no welder on the track (welders are only at stations)")
	for b in bolts:
		for k in NailSpot.HAMMER_HITS:
			b.on_tool_hit("hammer", player)
	await _frames(3)
	check(not track.is_broken(gap_piece), "all joints bolted → track rebuilt")
	train.lever = 1
	await _wait(2.0)
	check(train.speed > 0.5, "train moves on after the repair")
	train.lever = 0
	await _wait_until(func(): return train.is_stopped(), 10.0)

	print("Wheels: fall off, lift in, bolt on")
	var wheels_before := train.wheels
	var states_before: Array[int] = []
	for i in Train.MAX_WHEELS:
		states_before.append(train.wheel_state(i))
	train.lose_wheel()
	var missing := -1
	for i in Train.MAX_WHEELS:
		if train.wheel_state(i) == 1 and states_before[i] == 0:
			missing = i
	check(train.wheels == wheels_before - 1 and missing >= 0, "a wheel fell off")
	Game.add("wheel", 1)
	train.take_item(player, "wheel")
	var slot := train.wheel_slot(missing)
	slot.interact(player)
	check(train.wheel_state(missing) == 2 and train.wheels == wheels_before - 1, "wheel lifted into place (not bolted yet)")
	for k in Train.WHEEL_BOLT_HITS:
		slot.on_tool_hit("hammer", player)
	check(train.wheel_state(missing) == 0 and train.wheels == wheels_before, "3 hammer hits bolt it on")

	print("Damage model: body bar + mechanics bar")
	train.full_repair()
	check(is_equal_approx(train.health, 100.0) and is_equal_approx(train.body_health, 50.0) and is_equal_approx(train.mech_health(), 50.0), "health = body 50 + mechanics 50")
	train.take_damage(20.0)
	check(is_equal_approx(train.body_health, 40.0), "half the damage hits the body (%.1f)" % train.body_health)
	check(is_equal_approx(train.mech_health(), 40.0) and train.engine_damage > 0.0 and train.chassis_damage > 0.0, "the other half hits wheels, engine and chassis (mech %.1f)" % train.mech_health())
	train.full_repair()
	var w0 := -1
	for i in Train.MAX_WHEELS:
		if train.wheel_state(i) == 0 and w0 == -1:
			w0 = i
	train.add_wheel_wear(w0, 2.0)
	check(train.wheel_state(w0) == 0, "a worn wheel stays on below its limit")
	var wear0: float = train.wheel_wear[w0]
	train.wheel_slot(w0).on_tool_hit("wrench", player)
	check(train.wheel_wear[w0] < wear0, "the wrench tightens a loose wheel (%.1f → %.1f)" % [wear0, train.wheel_wear[w0]])
	var top_all := train.max_speed_now()
	var n_before := train.wheels
	train.add_wheel_wear(w0, Train.WHEEL_LIMIT)
	check(train.wheel_state(w0) == 1 and train.wheels == n_before - 1, "at 2.5 wear (5 % of the mechanics bar) the wheel comes off")
	check(absf(train.max_speed_now() / top_all - float(train.wheels) / n_before) < 0.02, "each lost wheel takes 1/%d of the speed" % n_before)
	await _frames(2)
	check(main.find_children("*", "RigidBody3D", true, false).size() > 0, "the lost wheel drops to the ground")
	Game.add("wheel", 1)
	train.take_item(player, "wheel")
	train.wheel_slot(w0).interact(player)
	for k in Train.WHEEL_BOLT_HITS:
		train.wheel_slot(w0).on_tool_hit("hammer", player)
	check(train.wheel_state(w0) == 0 and player.carried_item == "", "new wheel fitted and bolted")
	train.engine_damage = 15.0
	Game.add("engine_oil", 1)
	var top_hurt := train.max_speed_now()
	check(train.oil_engine() and is_equal_approx(train.engine_damage, 5.0) and train.max_speed_now() > top_hurt, "engine oil repairs the engine and gives power back")
	train.full_repair()

	print("Sabotage")
	var sab := Game.sabotage
	var hp := train.health
	sab.use("meteor", train.cars[0].global_position)
	await _wait(Meteor.FALL_TIME + 0.5)
	check(train.health < hp, "meteor on the train damages it (%.0f → %.0f)" % [hp, train.health])
	check(train.attached_count() < train.parts.size(), "damage knocks panels off (%d/%d left)" % [train.attached_count(), train.parts.size()])
	await _frames(2)
	check(get_tree().get_nodes_in_group("enemy").size() >= 0 and main.find_children("*", "FallenPart", true, false).size() > 0, "broken panels fly off as pieces you can pick up")
	check(not sab.can_use("meteor"), "meteor goes on cooldown")
	var top := train.max_speed_now()
	sab.use("freezing_wind")
	check(Game.wind_active and train.max_speed_now() < top, "freezing wind slows the train")
	Game.wind_active = false
	var loot_before := Game.count("wood") + Game.count("scrap") + Game.count("coal")
	sab.use("eagles")
	await _wait(9.0)
	check(Game.count("wood") + Game.count("scrap") + Game.count("coal") < loot_before, "eagles steal cargo")
	sab.use("zombies")
	await _frames(2)
	check(get_tree().get_nodes_in_group("enemy").size() > 0, "zombies spawn")
	sab.locked = true
	check(not sab.can_use("zombies") and not sab.use("eagles"), "locked sabotage can't be used (vote lock)")
	sab.locked = false
	for e in get_tree().get_nodes_in_group("enemy"):
		e.queue_free()

	print("Train cover: panels and doors")
	check(train.parts.size() >= 20, "train is covered by %d breakable pieces" % train.parts.size())
	var door: BodyPart = null
	for p in train.parts:
		if p.is_door and p.attached:
			door = p
	if door:
		door.toggle_door()
		check(door.door_open, "doors open with E")
		door.toggle_door()
	# cab front doors (one each side of the boiler) swing FORWARD so you can see ahead and walk to the front
	var front_doors := train.parts.filter(func(p): return p.is_door and p.car == train.cars[0] and p.node.get_aabb().size.x > p.node.get_aabb().size.z)
	check(front_doors.size() == 2, "the cab has 2 front doors")
	if front_doors.size() > 0:
		var fd: BodyPart = front_doors[0]
		var before := fd.node.transform * fd.node.get_aabb().get_center()
		fd.toggle_door()
		await _wait(0.5)
		var after := fd.node.transform * fd.node.get_aabb().get_center()
		check(after.z < before.z - 0.1, "the front door swings forward (towards the front of the engine)")
		fd.toggle_door()
	# Refit a wooden panel: pick up a fallen one, place it, nail it
	train.weld_full()
	train.take_damage(train.parts[0].value() * 3.0)
	var wpanel: BodyPart = null
	var metal: BodyPart = null
	for p in train.parts:
		if not p.attached and p.material == "wood" and p.slot() != null and wpanel == null:
			wpanel = p
		if not p.attached and p.material == "metal" and p.slot() != null and metal == null:
			metal = p
	while wpanel == null or metal == null:
		wpanel = null
		metal = null
		train.weld_full()
		train.take_damage(train.parts[0].value() * 6.0)
		for p in train.parts:
			if not p.attached and p.material == "wood" and p.slot() != null and wpanel == null:
				wpanel = p
			if not p.attached and p.material == "metal" and p.slot() != null and metal == null:
				metal = p
	var hp_before := train.health
	var fallen: Array = main.find_children("*", "FallenPart", true, false)
	check(fallen.size() > 0, "fallen pieces lie around")
	fallen[0]._pick_up(player)
	check(player.carried_item == "panel", "pick up a fallen panel (free)")
	wpanel.slot().interact(player)
	await _frames(2)
	check(wpanel.is_pending(), "panel placed, needs nails")
	var nails := train.find_children("*", "NailSpot", true, false).filter(func(n): return n.has_meta("part") and n.get_meta("part") == wpanel)
	check(nails.size() == 2, "a wooden panel takes 2 nails")
	for n in nails:
		for k in NailSpot.HAMMER_HITS:
			n.on_tool_hit("hammer", player)
	check(wpanel.attached and train.health > hp_before, "nailed on → panel fixed, health %.0f → %.0f" % [hp_before, train.health])
	# A metal panel can be put in place anywhere, but welding needs a station welder
	Game.add("scrap", 20)
	var scrap2 := Game.count("scrap")
	train.take_item(player, "panel")
	check(Game.count("scrap") == scrap2 - 2, "a new panel from the cargo car costs 2 scrap")
	metal.slot().interact(player)
	await _frames(2)
	var seams2 := train.find_children("*", "WeldSeam", true, false).filter(func(n): return n.has_meta("part") and n.get_meta("part") == metal)
	check(seams2.size() == 2, "a metal panel takes 2 welds")
	check(not player.weld_tick(seams2[0], 0.5), "no welding away from a station")

	print("Station checkpoint + station welder")
	_clear_gaps(track.station_distances[1] - 200.0, track.station_distances[1] + 40.0)
	_place_train(track.station_distances[1] - 5.0 + train.total_length * 0.5)
	train.speed = 2.0
	var arrived := await _wait_until(func(): return Game.next_station == 2, 10.0)
	check(arrived and Game.checkpoint.get("station", -1) == 1, "stopping in station 1 saves a checkpoint")
	var station_welder: WelderSource = main.get_node("Station1").find_children("*", "WelderSource", true, false)[0]
	# weld the metal panel we placed before
	player.global_position = station_welder.global_position + Vector3.UP
	station_welder.get_node("TakeTorch").interact(player)
	check(player.current_tool == "welder" and player.welder_source == station_welder, "take the welding torch from the station welder")
	for seam in seams2:
		player.weld_tick(seam, WeldSeam.WELD_TIME + 0.1)
	check(metal.attached, "welded on at the station → metal panel fixed")
	# cable limit
	var plug := station_welder.plug_position()
	var away := Vector3(1, 0, 0)
	player.global_position = Vector3(plug.x, player.global_position.y, plug.z) + away * (station_welder.cable_length + 2.0)
	await _frames(3)
	var flat := Vector3(player.global_position.x - plug.x, 0, player.global_position.z - plug.z).length()
	check(flat <= station_welder.cable_length + 0.1 and player.current_tool == "welder", "the cable stops you at its length (%.1f m)" % flat)
	player.global_position = Vector3(plug.x, player.global_position.y, plug.z) + away * (station_welder.cable_length + 10.0)
	await _frames(3)
	check(not is_instance_valid(player.welder_source) and player.current_tool == "hammer", "walking too far pulls the cable out")
	train.weld_full()
	train.take_damage(40.0)
	var high: BodyPart = null
	for p in train.parts:
		if not p.attached and p.material == "metal" and p.slot() != null and high == null:
			high = p
	if high == null:
		train.take_damage(30.0)
		for p in train.parts:
			if not p.attached and p.material == "metal" and p.slot() != null and high == null:
				high = p
	var hp_station := train.health
	Game.add("scrap", 10)
	train.take_item(player, "panel")
	high.slot().interact(player)
	await _frames(2)
	player.global_position = station_welder.global_position + Vector3.UP
	await _frames(2)
	station_welder.get_node("TakeTorch").interact(player)
	for seam in train.find_children("*", "WeldSeam", true, false).filter(func(n): return n.has_meta("part") and n.get_meta("part") == high):
		player.weld_tick(seam, WeldSeam.WELD_TIME + 0.1)
	check(high.attached and train.health > hp_station, "another metal panel welded at the station")
	train.chassis_damage = 10.0
	var chassis: Array = train.cars[0].find_children("*", "ChassisSpot", true, false)
	check(chassis.size() == 2, "the chassis has weld points")
	for k in 10:
		player.weld_tick(chassis[0], 1.0)
	check(train.chassis_damage == 0.0, "the chassis is welded at the station")
	var gold := Game.count("gold")
	Game.buy("nails")
	check(Game.count("gold") == gold - Game.SHOP.nails.price, "shop takes gold")
	player.select_tool("hammer")

	print("Hills")
	var climb := track.station_distances[2] + 0.25 * Track.SEGMENT_LENGTH
	train.distance = climb
	train.lever = 1
	var uphill := train.max_speed_now()
	train.lever = -1
	var reverse_downhill := train.max_speed_now()
	check(track.grade_at(climb - train.total_length * 0.5) > 0.005 and uphill < reverse_downhill, "uphill is slower than downhill (%.1f vs %.1f m/s)" % [uphill, reverse_downhill])
	train.lever = 0

	print("Crash at speed")
	_place_train(track.station_distances[1] + 60.0)
	await _frames(2)
	_clear_gaps(train.distance, train.distance + 200.0)
	track.break_piece(track.piece_at(train.distance + 120.0))
	train.fuel = 100.0
	train.weld_full()
	train.lever = 1
	await _wait_until(func(): return train.speed > 9.0, 20.0)
	await _wait_until(func(): return train.is_stopped(), 20.0)
	check(train.health < 100.0, "hitting broken track at speed damages the train (%.0f)" % train.health)

	print("Player rides the moving train")
	train.lever = 0
	await _wait_until(func(): return train.is_stopped(), 20.0)
	_clear_gaps(train.distance, train.distance + 300.0)
	train.full_repair()
	train.fuel = 100.0
	var car := train.cars[2]
	player.global_position = car.global_position + car.global_basis.y * (Train.FLOOR_HEIGHT + 0.3) - car.global_basis.x * 0.3
	player.velocity = Vector3.ZERO
	await _wait(1.0)
	var local_before := car.to_local(player.global_position)
	train.lever = 1
	await _wait(6.0)
	var local_after := car.to_local(player.global_position)
	if local_before.distance_to(local_after) >= 1.5:
		for i in player.get_slide_collision_count():
			var c := player.get_slide_collision(i).get_collider()
			print("    debug collider: ", c.get_path() if c else null)
		print("    debug: ", local_before, " -> ", local_after, " floor=", player.is_on_floor(), " wheels=", train.wheels)
	check(train.speed > 5.0, "train is moving fast (%.1f m/s)" % train.speed)
	check(local_before.distance_to(local_after) < 1.5, "player stays in place on the moving car (drift %.2f m)" % local_before.distance_to(local_after))

	print("Walk from the cab to the front of the engine")
	train.lever = 0
	await _wait_until(func(): return train.is_stopped(), 20.0)
	train.weld_full()
	var loco := train.cars[0]
	var front_door: BodyPart = null
	for p in train.parts:
		if p.is_door and p.car == loco and p.node.get_aabb().size.x > p.node.get_aabb().size.z and p._home.origin.x > 0:
			front_door = p
	front_door.toggle_door()
	await _wait(0.5)
	player.global_position = loco.to_global(Vector3(1.15, Train.FLOOR_HEIGHT + 0.1, 1.3))
	player.velocity = Vector3.ZERO
	player.global_basis = Basis.looking_at(-loco.global_basis.z, Vector3.UP)
	await _wait(0.3)
	Engine.time_scale = 1.0
	Input.action_press("move_forward")
	await _wait(1.1)
	Input.action_release("move_forward")
	Engine.time_scale = 4.0
	var where := loco.to_local(player.global_position)
	check(where.z < -1.5 and where.y > Train.FLOOR_HEIGHT - 0.2, "walk through the cab front door along the running board (now at %.1f m)" % -where.z)

	print("Final station")
	train.lever = 0
	Game.next_station = Game.STATION_COUNT
	var last := track.station_distances[Game.STATION_COUNT]
	_clear_gaps(last - 200.0, last + 40.0)
	_place_train(last - 5.0 + train.total_length * 0.5)
	train.speed = 1.5
	var done := await _wait_until(func(): return Game.next_station > Game.STATION_COUNT, 10.0)
	check(done, "reaching station 5 completes the chapter")
	Engine.time_scale = 1.0
