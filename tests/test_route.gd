extends Node
## Automated full run of Chapter 1 (runs headless, a few minutes):
##   godot --headless --path . res://tests/TestRoute.tscn
## A new game with world sabotage off. For every segment: keep the furnace fed, drive with the lever (braking
## softly for every block like a careful driver), rebuild each gap with RailRepair.finish_instantly(), and at the
## locked gate walk to Key_<seg>, pick it up, walk to the gate and unlock it. Asserts the world layout (gates, keys,
## gaps, signal posts), the per-segment resource budget, every checkpoint, the Chapter 1 ending with its stats,
## and a restart from the station 3 checkpoint. Exit code 0 = all checks passed.

const TIME_SCALE := 12.0
const SEGMENT_TIMEOUT := 900.0      # game seconds per segment before the test gives up
## Idle furnace time per segment a real crew spends repairing (for the coal budget).
const IDLE_ALLOWANCE := 480.0
const NEEDS_PER_PIECE := {"wood": Main.WOOD_PER_PIECE, "scrap": Main.SCRAP_PER_PIECE, "nails": 8}

var main: Node3D
var train: Train
var track: Track
var player: Player
var failures := 0
var reached: Array[int] = []
var chapter_done := false
var finished_stats: Dictionary = {}
var repairs_done := 0
var checkpoint3: Dictionary = {}
var coal_used: Array[float] = [0.0, 0.0, 0.0, 0.0, 0.0]
var collected: Array[Dictionary] = [{}, {}, {}, {}, {}]


func _ready() -> void:
	var t0 := Time.get_ticks_msec()
	Game.new_game(false)
	Game.world_sabotage = false
	Game.station_reached.connect(func(i: int): reached.append(i))
	Game.chapter_completed.connect(func(): chapter_done = true)
	Game.run_finished.connect(func(s: Dictionary): finished_stats = s)
	await _load_main()
	await _run()
	Engine.time_scale = 1.0
	print("\n(test took %d s)" % ((Time.get_ticks_msec() - t0) / 1000))
	print("\n%s: %d failure(s)" % ["PASSED" if failures == 0 else "FAILED", failures])
	get_tree().quit(1 if failures > 0 else 0)


func _load_main() -> void:
	main = load("res://scenes/main/Main.tscn").instantiate()
	add_child(main)
	await _frames(5)
	train = Game.train
	track = Game.track
	player = main.player
	# the player is parked and teleported for interactions (no falling through the ground at high time scale)
	player.set_physics_process(false)


func check(ok: bool, what: String) -> void:
	print(("  ok   " if ok else "  FAIL ") + what)
	if not ok:
		failures += 1


func _frames(n: int) -> void:
	for i in n:
		await get_tree().physics_frame


func _wait(seconds: float) -> void:
	await get_tree().create_timer(seconds, true, true).timeout


func _run() -> void:
	_check_layout()
	_check_world()
	_check_budget()
	await _check_viewmodel()
	Engine.time_scale = TIME_SCALE
	for seg in Game.STATION_COUNT:
		var ok := await _drive_segment(seg)
		if not ok:
			check(false, "segment %d finished (gave up)" % (seg + 1))
			return
	await _check_ending()
	await _check_restart_from_station_3()


# --- World layout -------------------------------------------------------------------------

func _check_layout() -> void:
	print("Locked gates, keys and gaps")
	check(track.gate_count() == Game.STATION_COUNT, "one locked gate per segment (%d)" % track.gate_count())
	for s in track.gate_count():
		var g := track.gate_distance(s)
		var a := track.station_distances[s]
		var b := track.station_distances[s + 1]
		var gate := main.find_child("Gate_%d" % s, true, false) as TrackGate
		var key := main.find_child("Key_%d" % s, true, false) as GateKey
		check(gate != null and key != null and track.is_gate_locked(s), "Gate_%d and Key_%d exist, the gate is locked" % [s, s])
		check(g > a + Track.SEGMENT_LENGTH * 0.5 and g < b - Track.STATION_LENGTH * 0.5 - 30.0, "gate %d sits in the second half of its segment (%d m in), clear of the station" % [s, int(g - a)])
		var on_bridge := false
		for i in range(track.piece_at(g - 10.0), track.piece_at(g + 10.0) + 1):
			on_bridge = on_bridge or track.is_bridge(i)
		check(not on_bridge and track.natural_height(g, 0.0) > Track.WATER_LEVEL + 1.0, "gate %d stands on solid ground, not on a bridge or over water" % s)
		var nearest_gap := INF
		for gap: Dictionary in track.initial_gaps:
			var d0 := float(gap.first) * Track.PIECE_LENGTH
			var d1 := d0 + float(gap.count) * Track.PIECE_LENGTH
			nearest_gap = minf(nearest_gap, minf(absf(g - d0), absf(g - d1)))
		check(nearest_gap >= 30.0, "no gap within 30 m of gate %d (nearest %d m)" % [s, int(nearest_gap)])
		if key:
			var kd := track.closest_distance(key.global_position)
			var side := Vector2(key.global_position.x - track.point_at(kd).x, key.global_position.z - track.point_at(kd).z).length()
			check(side >= 4.0 - 0.3 and side <= 10.0 + 0.3 and absf(kd - g) <= 8.5, "key %d lies %.1f m beside the track, %.1f m from the gate" % [s, side, absf(kd - g)])
			check(key.global_position.y > Track.WATER_LEVEL + 1.0 and absf(key.global_position.y - track.point_at(kd).y) < 2.0, "key %d is on dry, reachable ground" % s)
		if gate:
			var sig := gate.get_node_or_null("Signal") as Node3D
			check(sig != null and absf(track.closest_distance(sig.global_position) - (g - Track.GATE_SIGNAL)) < 2.0, "a red signal post stands %d m before gate %d" % [int(Track.GATE_SIGNAL), s])
			var lock := gate.get_node("Lock") as Interactable
			check(lock.get_prompt(player).begins_with("Locked: find the key nearby"), "without a key the gate says 'Locked: find the key nearby'")
	for s in Game.STATION_COUNT:
		var want: int = Track.GAPS_PER_SEGMENT[s]
		var have := track.initial_gaps.filter(func(gp: Dictionary): return int(gp.segment) == s).size()
		check(have == want, "segment %d has %d pre-placed gaps (%d pieces)" % [s + 1, have, track.gap_pieces_in_segment(s)])
	var bad_gap := false
	for gap: Dictionary in track.initial_gaps:
		var d1 := (float(gap.first) + float(gap.count)) * Track.PIECE_LENGTH
		var g := track.gate_distance(int(gap.segment))
		if d1 <= g and g - d1 < Track.GATE_GAP_BEFORE:
			bad_gap = true
		for k in int(gap.count):
			bad_gap = bad_gap or track.is_bridge(int(gap.first) + k)
	check(not bad_gap, "no pre-placed gap on a bridge or within %d m before a gate" % int(Track.GATE_GAP_BEFORE))
	check(main.find_child("Pickup_0", true, false) != null and main.find_child("Repair_%d" % int(track.initial_gaps[0].first), true, false) != null, "deterministic names: Pickup_<n>, Repair_<piece>")


## The overworld: a big, non-flat terrain around the whole line, flat quest sites by the gates, the same land
## from the same seed, collision near players, things to find off the rails.
func _check_world() -> void:
	print("Overworld")
	var terrain: Terrain = Game.terrain
	var lo := INF
	var hi := -INF
	var far_points := 0
	for k in 4000:
		var d := float(k) / 4000.0 * track.get_length()
		var u := (Landscape.R_OUT - 60.0) * (1.0 if k % 2 == 0 else -1.0) * float(k % 7 + 1) / 7.0
		var p := track.point_at(d) + track.flat_right(d) * u
		var h := terrain.ground_at(p.x, p.z)
		if h > Terrain.NO_GROUND + 1.0:
			far_points += 1
			lo = minf(lo, h)
			hi = maxf(hi, h)
	check(far_points > 3900, "terrain covers %d m each side of the whole line (%d/4000 samples)" % [int(Landscape.R_OUT - 60.0), far_points])
	check(hi - lo > 250.0, "the land is not flat: %d m from the lowest to the highest point" % int(hi - lo))
	for s in track.gate_count():
		var q := track.quest_zone(s)
		var marker := main.find_child("QuestZone_%d" % s, true, false) as Node3D
		check(marker != null and marker.global_position.distance_to(q.center) < 0.1 and int(q.gate_index) == s, "QuestZone_%d marks the quest site beside gate %d" % [s, s])
		var c: Vector3 = q.center
		var f: Vector3 = q.forward
		var r := f.cross(Vector3.UP)
		var half: float = (q.size as Vector2).x * 0.5 - 2.0
		var zlo := INF
		var zhi := -INF
		for i in 11:
			for j in 11:
				var p := c + r * lerpf(-half, half, i / 10.0) + f * lerpf(-half, half, j / 10.0)
				var h := terrain.ground_at(p.x, p.z)
				zlo = minf(zlo, h)
				zhi = maxf(zhi, h)
		check((q.size as Vector2).x >= 80.0 and zhi - zlo < 0.6 and zlo > Track.WATER_LEVEL + 1.0, "quest site %d: %dx%d m, flat within %.2f m, dry" % [s, int(q.size.x), int(q.size.y), zhi - zlo])
		# reachable on foot from the gate: no step steeper than 1:2 on the way over
		var g := track.point_at(track.gate_distance(s))
		var steep := 0.0
		var prev := g
		for k in range(1, 31):
			var p := g.lerp(c, k / 30.0)
			p.y = terrain.ground_at(p.x, p.z)
			var run := Vector2(p.x - prev.x, p.z - prev.z).length()
			steep = maxf(steep, absf(p.y - prev.y) / maxf(run, 0.01))
			prev = p
		check(steep < 0.5, "quest site %d is a walk from gate %d (steepest grade %.2f)" % [s, s, steep])
		var clear := true
		for h: Dictionary in terrain.features.hazards:
			if track.land.in_zone((h.pos as Vector3).x, (h.pos as Vector3).z, float(h.radius)):
				clear = false
		check(clear, "quest site %d is clear of hazards and caves" % s)
	# the same seed gives the same land: a second track from Main.SEED computes the same heights
	var rng := RandomNumberGenerator.new()
	rng.seed = Main.SEED
	var twin := Track.new()
	add_child(twin)
	twin.build(rng)
	var same := true
	var pick := RandomNumberGenerator.new()
	pick.seed = 7
	var tested := 0
	while tested < 3000:
		var i := pick.randi_range(0, (terrain.gw - 1) / 2) * 2  # odd vertices far out are interpolated
		var j := pick.randi_range(0, terrain.gh - 1)
		var du := terrain.track_coords(terrain.origin.x + i * Terrain.CELL, terrain.origin.y + j * Terrain.CELL)
		if absf(du.y) > Landscape.R_OUT:
			continue
		tested += 1
		var vi := j * terrain.gw + i
		var x := terrain.origin.x + i * Terrain.CELL
		var z := terrain.origin.y + j * Terrain.CELL
		var d: float = terrain.vertex_coords(vi).x
		var u: float = terrain.vertex_coords(vi).y
		if absf(twin.land.height(x, z, d, u, twin.point_at(clampf(d, -Terrain.EXTEND, twin.get_length() + Terrain.EXTEND)).y) - terrain.heights[vi]) > 0.05:
			same = false
	var zones_same := true
	for s in track.gate_count():
		zones_same = zones_same and twin.quest_zone(s).center.distance_to(track.quest_zone(s).center) < 0.01
	check(same and zones_same, "the same seed builds the same land and quest sites (3000 grid heights compared)")
	print("    terrain checksum %d" % hash(terrain.heights))
	twin.queue_free()
	# collision only near players, and there when one walks out
	var far: Vector3 = track.quest_zone(2).center
	terrain.update_collision([far])
	check(terrain.has_collision_at(far), "walking out into the land: the ground under the player becomes solid")
	var f := terrain.features
	check(f.trails.size() >= 6 and f.caves.size() >= 4 and f.bridges.size() >= 2 and f.hazards.size() >= 25,
		"off the rails: %d trails to viewpoints, %d caves, %d rope bridges, %d waterfalls, %d hazards, %d rockfalls" % [
		f.trails.size(), f.caves.size(), f.bridges.size(), f.waterfalls.size(), f.hazards.size(), f.rockfalls.size()])


## Resources lying within 15 m of the track plus the starting inventory cover what the pre-placed gaps need,
## segment by segment; coal and gold too.
func _check_budget() -> void:
	print("Resource budget per segment")
	var near := []
	for s in Game.STATION_COUNT:
		near.append({"wood": 0, "scrap": 0, "nails": 0, "coal": 0, "gold": 0})
	for p: Pickup in main.get_node("Pickups").get_children():
		var d := track.closest_distance(p.global_position)
		var on := track.point_at(d)
		if Vector2(p.global_position.x - on.x, p.global_position.z - on.z).length() > 15.0:
			continue
		var seg := track.segment_at(d)
		var c := p.contents()
		for item: String in c:
			if near[seg].has(item):
				near[seg][item] += int(c[item])
	var have := {"wood": Game.count("wood"), "scrap": Game.count("scrap"), "nails": Game.count("nails")}
	for s in Game.STATION_COUNT:
		var pieces := track.gap_pieces_in_segment(s)
		var line := PackedStringArray()
		var ok := true
		for item: String in have:
			have[item] += int(near[s][item]) - int(NEEDS_PER_PIECE[item]) * pieces
			line.append("%s %+d" % [item, int(have[item])])
			ok = ok and int(have[item]) >= 0
		check(ok, "segment %d: %d gap pieces covered, spare after it: %s" % [s + 1, pieces, ", ".join(line)])
		check(int(near[s].gold) >= Game.SHOP.wheel.price + Game.SHOP.engine_oil.price, "segment %d: %d gold near the track (a wheel + oil = %d)" % [s + 1, int(near[s].gold), Game.SHOP.wheel.price + Game.SHOP.engine_oil.price])
	set_meta("near", near)


## Each tool's first-person animation and each carry pose moves the hands differently.
func _check_viewmodel() -> void:
	print("First-person tools and carry poses")
	var vm := player.viewmodel
	Game.add("nail_gun")
	var poses := {}
	for tool in ["hammer", "wrench", "nail_gun", "come_along"]:
		player.select_tool(tool)
		await _wait(0.5)
		var rest := vm.right.transform
		vm.play(tool)
		await _wait(0.12 if tool == "nail_gun" else 0.2)
		var mid := vm.right.transform
		var model := vm.right.get_child(vm.right.get_child_count() - 1)
		for c in vm.right.get_children():
			if c is Node3D and c.visible and c.get_child_count() > 0:
				model = c
		poses[tool] = [mid.origin, mid.basis.get_euler(), (model as Node3D).rotation]
		check(not mid.is_equal_approx(rest), "%s: the arm moves (%.2f m)" % [tool, mid.origin.distance_to(rest.origin)])
		await _wait(0.6)
	var distinct := true
	var tools := poses.keys()
	for i in tools.size():
		for j in range(i + 1, tools.size()):
			var a: Array = poses[tools[i]]
			var b: Array = poses[tools[j]]
			if (a[0] as Vector3).distance_to(b[0]) < 0.02 and (a[1] as Vector3).distance_to(b[1]) < 0.1 and (a[2] as Vector3).distance_to(b[2]) < 0.1:
				distinct = false
	check(distinct, "the hammer, wrench, nail gun and come-along animations all differ")
	player.select_tool("hammer")
	var holds := {}
	for item in ["plank", "rail", "wheel", "panel"]:
		player.carry(item)
		await _wait(0.2)
		holds[item] = [vm.right.position, vm.left.position]
		player.consume_carried()
		await _wait(0.5)
	var carry_distinct := true
	for a in holds:
		for b in holds:
			if a != b and (holds[a][0] as Vector3).distance_to(holds[b][0]) < 0.05 and (holds[a][1] as Vector3).distance_to(holds[b][1]) < 0.05:
				carry_distinct = false
	check(carry_distinct and vm.left.visible == false, "plank, rail, wheel and panel are held in four different poses")
	Game.take("nail_gun")


# --- Driving --------------------------------------------------------------------------------

func _feed_furnace(seg: int) -> void:
	while train.fuel < Train.MAX_FUEL - Train.COAL_FUEL and Game.has("coal"):
		train.add_coal()
		coal_used[seg] += 1.0


## Whenever the train stops, the crew picks up what lies around it (and mines the gold rocks).
func _collect_near(seg: int, radius := 30.0) -> void:
	var at := train.cars[0].global_position
	for p in main.get_node("Pickups").get_children():
		if p is Pickup and not p.is_queued_for_deletion() and p.global_position.distance_to(at) < radius:
			var got: Dictionary = p.contents()
			for k in 10:
				if p.is_queued_for_deletion():
					break
				p.interact(player)
			for item: String in got:
				collected[seg][item] = int(collected[seg].get(item, 0)) + int(got[item])


## Drives from station `seg` to station `seg + 1` like a careful crew. Returns false if stuck.
func _drive_segment(seg: int) -> bool:
	var target := seg + 1
	print("Segment %d: station %d → station %d (%s)" % [target, seg, target, Track.THEMES[seg].name])
	var t := 0.0
	var gate_done := false
	var pieces_fixed := 0
	var hp := train.health
	while not target in reached:
		if t > SEGMENT_TIMEOUT:
			print("    stuck at %.0f m (speed %.1f, fuel %.0f, lever %d)" % [train.distance, train.speed, train.fuel, train.lever])
			return false
		_feed_furnace(seg)
		if train.fuel <= 0.0 and not Game.has("coal"):
			print("    out of coal at %.0f m" % train.distance)
			Game.add("coal", 20)  # keep the test going
			check(false, "segment %d: the coal picked up at the stops lasts" % target)
		var front := train.distance
		var block := track.blocking_distance(front, front + 120.0)
		if track.station_at(train.center_distance()) == target:
			train.lever = 0
		elif block >= 0.0:
			var gap := block - front
			if train.is_stopped() and gap < 1.0:
				_collect_near(seg)
				var gate_seg := track.blocking_gate(front, front + 1.0)
				if gate_seg >= 0:
					await _open_gate(gate_seg, seg)
					gate_done = true
				else:
					var piece := track.piece_at(block + 0.5)
					var repair := track.repair_at(piece)
					if repair:
						repair.finish_instantly()
						repairs_done += 1
						pieces_fixed += 1
				train.lever = 1
			else:
				# brake early enough to arrive below the crash speed
				var brake_d := train.speed * train.speed / (2.0 * Train.BRAKE) + 6.0
				train.lever = 0 if gap < brake_d and train.speed > 2.5 else 1
		else:
			train.lever = 1
		await get_tree().physics_frame
		t += get_physics_process_delta_time()
	check(Game.checkpoint.get("station", -1) == target, "station %d reached, checkpoint saved (%d s game time, %d pieces rebuilt)" % [target, int(t), pieces_fixed])
	# coal: what lies near the track in this segment covers ~1.5x the coal burnt (driving incl. climbs + idling
	# while a real crew repairs)
	var idle_coal := IDLE_ALLOWANCE * 0.12 / Train.COAL_FUEL
	var need := coal_used[seg] + idle_coal
	var near_coal := int(get_meta("near")[seg].coal)
	check(near_coal >= 1.5 * need, "segment %d coal: burnt %d (+%d idling), %d lies near the track (%.1fx), the crew picked up %d at its stops" % [
		target, int(coal_used[seg]), int(idle_coal), near_coal, near_coal / need, int(collected[seg].get("coal", 0))])
	var at_stops := int(collected[seg].get("coal", 0)) + (int(Game.START_INVENTORY.coal) if seg == 0 else 0)
	check(at_stops >= 1.2 * need, "segment %d: the coal beside the gaps and the gate alone covers the burn (%.1fx)" % [target, at_stops / need])
	_collect_near(seg)
	check(gate_done, "segment %d: the train stopped at the locked gate and it was opened" % target)
	check(is_equal_approx(train.health, hp), "segment %d: no crash damage when driving carefully" % target)
	if target == 3:
		checkpoint3 = Game.checkpoint.duplicate(true)
	return true


func _open_gate(gate_seg: int, seg: int) -> void:
	check(gate_seg == seg, "the train stopped in front of gate %d (%.1f m before the boom)" % [gate_seg, track.gate_distance(gate_seg) - train.distance])
	var director: RunDirector = main.director
	check(director.compute_objective().begins_with("Gate locked: find the key"), "objective: 'Gate locked: find the key'")
	var key := main.find_child("Key_%d" % gate_seg, true, false) as GateKey
	check(key != null, "Key_%d lies beside the track" % gate_seg)
	if key == null:
		track.open_gate(gate_seg)
		return
	var cab := train.cars[0].global_position
	check(cab.distance_to(key.global_position) < 25.0, "the key is %.0f m from the locomotive" % cab.distance_to(key.global_position))
	player.global_position = key.global_position + Vector3(0, 0.2, 1.5)
	key.interact(player)
	await _frames(2)
	check(Game.count("key") == 1 and not is_instance_valid(key), "picked up the key")
	check(director.compute_objective().begins_with("Open the gate"), "objective: 'Open the gate'")
	var gate := main.find_child("Gate_%d" % gate_seg, true, false) as TrackGate
	player.global_position = gate.global_position + gate.global_basis.z * 2.0
	var lock := gate.get_node("Lock") as Interactable
	check(lock.get_prompt(player).begins_with("Unlock the gate"), "with the key the prompt says 'Unlock the gate'")
	var gates_before := Game.stat("gates")
	lock.interact(player)
	check(not track.is_gate_locked(gate_seg) and not gate.locked and Game.count("key") == 0, "the key opens gate %d (and is used up)" % gate_seg)
	check(Game.stat("gates") == gates_before + 1, "gates opened: %d" % int(Game.stat("gates")))
	await _wait(2.2)
	var boom := gate.find_child("Boom", true, false) as Node3D
	check(boom != null and boom.rotation.z > 1.2, "the boom swung up (%.0f°)" % (rad_to_deg(boom.rotation.z) if boom else 0.0))
	check(track.blocking_distance(train.distance, train.distance + 50.0) < 0.0 or track.blocking_gate(train.distance, train.distance + 50.0) < 0, "the gate no longer blocks the train")


# --- Ending and restart ------------------------------------------------------------------------

func _check_ending() -> void:
	print("Chapter 1 complete")
	check(chapter_done and Game.run_complete, "station 5 completes the chapter")
	check(not finished_stats.is_empty(), "run_finished sent the stats")
	await _wait(RunDirector.END_DELAY + 0.6)
	var screen: EndScreen = main.director.end_screen
	check(screen != null and screen.is_open() and screen.get_parent() == main, "the EndScreen shows after about 2 s")
	check(Game.sabotage.locked, "sabotage stopped at the end")
	var st := Game.stats
	print("    stats: time %s, distance %.0f m, repairs %d, panels %d, wheels lost %d, gates %d, gold %d" % [
		EndScreen.format_time(st.time), st.distance, int(st.repairs), int(st.panels), int(st.wheels_lost), int(st.gates), int(st.gold_found)])
	check(float(st.distance) > 7000.0, "stats.distance > 7000 m (%.0f)" % st.distance)
	check(int(st.gates) == 5, "stats.gates == 5")
	check(float(st.time) > 0.0, "stats.time > 0 (%s)" % EndScreen.format_time(st.time))
	check(int(st.repairs) == repairs_done, "stats.repairs counts the rebuilt pieces (%d)" % repairs_done)
	var time_before := float(st.time)
	await _wait(1.0)
	check(is_equal_approx(float(Game.stats.time), time_before), "the run clock stopped at the port")
	check(Game.MENU_SCENE == "res://scenes/menu/MainMenu.tscn", "Back to main menu goes to MainMenu (or reloads Main if it is missing)")
	screen.close()
	check(not screen.is_open() and not Game.ui_open, "Keep exploring closes the card")


func _check_restart_from_station_3() -> void:
	print("Restart from the station 3 checkpoint")
	check(not checkpoint3.is_empty(), "the station 3 checkpoint was saved")
	if checkpoint3.is_empty():
		return
	Engine.time_scale = 1.0
	main.queue_free()
	await _frames(3)
	Game.checkpoint = checkpoint3
	Game.load_checkpoint_state()
	await _load_main()
	for s in 3:
		check(not track.is_gate_locked(s) and main.find_child("Key_%d" % s, true, false) == null, "gate %d is open and its key is gone" % s)
	for s in [3, 4]:
		check(track.is_gate_locked(s) and main.find_child("Key_%d" % s, true, false) != null, "gate %d is still locked with its key beside it" % s)
	var saved: Dictionary = checkpoint3.stats
	check(int(Game.stats.gates) == 3 and is_equal_approx(float(Game.stats.distance), float(saved.distance)), "stats carried over (gates %d, %.0f m)" % [int(Game.stats.gates), float(Game.stats.distance)])
	check(train.current_station == 3 and Game.next_station == 4 and not Game.run_complete, "the train waits in station 3, next stop station 4")
	check(Game.count("key") == 0, "no orphan keys in the inventory")
	await _check_softlock_guards()


func _check_softlock_guards() -> void:
	print("Softlock guards")
	var director: RunDirector = main.director
	var gap: Dictionary = track.initial_gaps.filter(func(gp: Dictionary): return int(gp.segment) == 3)[0]
	train.distance = float(gap.first) * Track.PIECE_LENGTH - 2.0
	train.speed = 0.0
	train.lever = 0
	for item in ["wood", "nails", "scrap", "gold"]:
		Game.take(item, Game.count(item))
	await _frames(2)
	director.guard()
	var crate := main.find_child("SupplyCrate_*", false, false) as Pickup
	check(crate != null, "stuck at a gap with no wood, nails or gold: a supply crate turns up beside it")
	if crate:
		crate.interact(player)
		check(Game.count("wood") >= 3 and Game.count("nails") >= 6, "the crate holds enough for a piece (%s)" % Game.cost_text({"wood": Game.count("wood"), "nails": Game.count("nails"), "scrap": Game.count("scrap")}))
	# a broke crew with two wheels left at a station gets one emergency wheel
	train.distance = track.station_distances[3] + 18.0
	train.current_station = 3
	Game.take("wheel", Game.count("wheel"))
	while train.wheels > 2:
		train.lose_wheel(false)
	check(train.max_speed_now() >= Train.LIMP_SPEED, "on two wheels the train still limps along (%.1f m/s)" % train.max_speed_now())
	director.guard()
	check(Game.count("wheel") == 1, "the station master hands out an emergency wheel")
