extends Node
## Automated playthrough of the train core loop (runs headless):
##   godot --headless --path . res://tests/TestTrain.tscn
## Exit code 0 = all checks passed.

var main: Node3D
var train: Train
var track: Track
var failures := 0


func _ready() -> void:
	Game.new_game(false)
	Game.world_sabotage = false
	Engine.time_scale = 4.0
	main = load("res://scenes/main/Main.tscn").instantiate()
	add_child(main)
	await _frames(5)
	train = Game.train
	track = Game.track
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


func _run() -> void:
	print("Track & stations")
	check(track.station_distances.size() == 6, "6 stations (departure + 5 checkpoints)")
	check(track.broken_count() > 0, "pre-placed broken rails exist (%d)" % track.broken_count())
	check(train.current_station == 0, "train starts in the departure station")
	check(train.cars.size() == 4, "train has 4 cars")

	print("Fuel & lever")
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

	print("Broken rail blocks the train")
	var stopped := await _wait_until(func(): return train.is_stopped() and train.distance > gap_piece * Track.PIECE_LENGTH - 2.0, 30.0)
	check(stopped, "train stops at the broken rail")
	check(train.distance <= gap_piece * Track.PIECE_LENGTH, "train did not pass the gap (front %.1f, gap %.1f)" % [train.distance, gap_piece * Track.PIECE_LENGTH])

	print("Repair")
	var wood := Game.count("wood")
	var spot: ActionSpot = track._broken[gap_piece]
	spot.interact(null)
	check(not track.is_broken(gap_piece), "repairing the rail fixes it")
	check(Game.count("wood") == wood - 2, "repair costs 2 wood")
	await _wait(2.0)
	check(train.speed > 0.5, "train moves on after the repair")

	print("Sabotage")
	var sab := Game.sabotage
	var hp := train.health
	sab.use("meteor", train.cars[0].global_position)
	await _wait(Meteor.FALL_TIME + 0.5)
	check(train.health < hp, "meteor on the train damages it (%.0f → %.0f)" % [hp, train.health])
	check(not sab.can_use("meteor"), "meteor goes on cooldown")

	var top := train.max_speed_now()
	sab.use("freezing_wind")
	check(Game.wind_active and train.max_speed_now() < top, "freezing wind slows the train")

	train.lever = 0
	await _wait_until(func(): return train.is_stopped(), 10.0)
	Game.add("wood", 10)
	Game.add("scrap", 10)
	Game.add("coal", 10)
	var loot_before := Game.count("wood") + Game.count("scrap") + Game.count("coal")
	sab.use("eagles")
	await _wait(9.0)
	var loot_after := Game.count("wood") + Game.count("scrap") + Game.count("coal")
	check(loot_after < loot_before, "eagles steal cargo (%d → %d)" % [loot_before, loot_after])

	train.lever = 1
	await _wait(1.0)
	sab.use("zombies")
	await _frames(2)
	check(get_tree().get_nodes_in_group("enemy").size() > 0, "zombies spawn")
	sab.locked = true
	check(not sab.can_use("zombies") and not sab.use("eagles"), "locked sabotage can't be used (vote lock)")
	sab.locked = false

	print("Station checkpoint")
	Game.wind_active = false
	_clear_gaps(train.rear_distance(), track.station_distances[1] + 40.0)
	train.lever = 0
	train.speed = 0.0
	train.distance = track.station_distances[1] - 5.0 + train.total_length * 0.5
	train.speed = 2.0
	var arrived := await _wait_until(func(): return Game.next_station == 2, 10.0)
	check(arrived, "stopping in station 1 reaches the checkpoint")
	check(Game.checkpoint.get("station", -1) == 1, "checkpoint saved at station 1")

	print("Station-only repairs")
	train.health = 30.0
	train.patch()
	check(train.health == 50.0, "on-track patch adds 20%")
	train.patch()
	train.patch()
	check(train.health == Train.PATCH_LIMIT, "on-track patch stops at %d%%" % int(Train.PATCH_LIMIT))
	var station1: Station = main.get_node("Station1")
	Game.add("scrap", 10)
	Game.add("gold", 10)
	station1._weld()
	check(train.health == 100.0, "welding at the station restores 100%")
	train.wheels = 4
	Game.add("wheel", 1)
	station1._fit_wheel()
	check(train.wheels == 5, "wheel fitted at the station")
	var gold := Game.count("gold")
	Game.buy("nails")
	check(Game.count("gold") == gold - Game.SHOP.nails.price, "shop takes gold")

	print("Crash at speed")
	_clear_gaps(train.distance, train.distance + 200.0)
	var crash_piece := track.piece_at(train.distance + 120.0)
	track.break_piece(crash_piece)
	train.fuel = 100.0
	train.health = 100.0
	train.lever = 1
	await _wait_until(func(): return train.speed > 10.0, 20.0)
	await _wait_until(func(): return train.is_stopped(), 20.0)
	check(train.health < 100.0, "hitting a broken rail at speed damages the train (%.0f)" % train.health)

	print("Player rides the moving train")
	var player: Player = main.player
	player.downed = false
	player.health = 100.0
	train.lever = 0
	await _wait_until(func(): return train.is_stopped(), 20.0)
	_clear_gaps(train.distance, train.distance + 300.0)
	train.health = 100.0
	train.wheels = Train.MAX_WHEELS
	train.fuel = 100.0
	var car := train.cars[2]
	player.global_position = car.global_position + Vector3.UP * (Train.FLOOR_HEIGHT + 0.3)
	player.velocity = Vector3.ZERO
	await _wait(1.0)
	var local_before := car.to_local(player.global_position)
	train.lever = 1
	await _wait(6.0)
	var local_after := car.to_local(player.global_position)
	check(train.speed > 5.0, "train is moving fast (%.1f m/s)" % train.speed)
	check(local_before.distance_to(local_after) < 1.5, "player stays in place on the moving car (drift %.2f m)" % local_before.distance_to(local_after))
	check(player.global_position.y > car.global_position.y + 1.0, "player is still standing on the car")

	print("Final station")
	train.lever = 0
	Game.next_station = Game.STATION_COUNT
	var last := track.station_distances[Game.STATION_COUNT]
	_clear_gaps(last - 200.0, last + 40.0)
	train.speed = 0.0
	train.distance = last - 5.0 + train.total_length * 0.5
	train.speed = 1.5
	var done := await _wait_until(func(): return Game.next_station > Game.STATION_COUNT, 10.0)
	check(done, "reaching station 5 completes the chapter")
	Engine.time_scale = 1.0
