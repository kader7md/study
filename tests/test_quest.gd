extends Node
## Quest map test (headless, ~1 min):
##   godot --headless --path . res://tests/TestQuest.tscn
## Loads Main, checks the mountain-pass gate has a quest portal instead of a key beside the track, enters The Mountain
## through the portal, then checks: the collision ground matches the mountain's shape; both routes from the beach
## camp to the summit are possible (walk legs have ground and walkable slopes, every climb fits in one stamina bar
## even fully cold, the bridges carry you over the gorge); a real climb up a cliff with the climb key held drains
## stamina and mantles onto the ledge; standing recovers it; out of stamina you hang and can be pulled up; a rope
## ladder costs no stamina; the chimney costs less; falls hurt; dying sends you back to the last campfire; snacks
## restore stamina; reaching a camp moves the checkpoint; the cold lowers max stamina; taking the summit key gives
## the crew the key and brings everyone back to the portal, and the key opens the gate. Exit code 0 = all passed.

const L := preload("res://scripts/quest/mountain/mountain_layout.gd")
const SEG := 2

var main: Node3D
var player: Player
var quest: QuestManager
var map: MountainMap
var failures := 0


func _ready() -> void:
	var t0 := Time.get_ticks_msec()
	Game.new_game(false)
	Game.world_sabotage = false
	main = load("res://scenes/main/Main.tscn").instantiate()
	add_child(main)
	await _frames(5)
	player = main.player
	quest = Game.quest
	await _run()
	Input.action_release("climb")
	Input.action_release("move_forward")
	print("\n(test took %d s)" % ((Time.get_ticks_msec() - t0) / 1000))
	print("\n%s: %d failure(s)" % ["PASSED" if failures == 0 else "FAILED", failures])
	get_tree().quit(1 if failures > 0 else 0)


func check(ok: bool, what: String) -> void:
	print(("  ok   " if ok else "  FAIL ") + what)
	if not ok:
		failures += 1


func _frames(n: int) -> void:
	for i in n:
		await get_tree().physics_frame


func _seconds(s: float) -> void:
	await _frames(int(s * Engine.physics_ticks_per_second))


func _run() -> void:
	print("Overworld: the mountain-pass gate")
	var track := Game.track
	check(quest != null and QuestManager.has_map(SEG), "Main/Quest exists and segment %d has a quest map" % SEG)
	var portal := quest.get_node_or_null("Portal_%d" % SEG) as QuestPortal
	check(portal != null, "Portal_%d stands in the overworld" % SEG)
	check(main.find_child("Key_%d" % SEG, true, false) == null, "no key lies beside the track at gate %d" % SEG)
	check(main.find_child("Key_0", true, false) != null, "gates without a quest map keep their key beside the track")
	if portal == null:
		return
	var gd := track.gate_distance(SEG)
	var gp := track.point_at(gd)
	check(portal.global_position.distance_to(gp) < 60.0, "the portal is %.0f m from the gate" % portal.global_position.distance_to(gp))
	var lock := main.find_child("Gate_%d" % SEG, true, false).get_node("Lock") as Interactable
	check(lock.get_prompt(player).contains("The Mountain"), "the locked gate points to The Mountain")
	check(portal.get_prompt(player).begins_with("Enter The Mountain"), "portal prompt: '%s'" % portal.get_prompt(player))

	print("Entering The Mountain")
	player.global_position = portal.global_position + portal.global_basis.z * 2.0
	await _frames(2)
	portal.interact(player)
	await _frames(3)
	map = quest.map as MountainMap
	check(quest.active and map != null, "the crew is in the quest map (built in %d ms)" % (map.build_ms if map else -1))
	if map == null:
		return
	check(map.global_position.distance_to(gp) > 3000.0, "the map is far from the line (%.0f m)" % map.global_position.distance_to(gp))
	var beach := map.to_global(L.camp_position(0))
	check(player.global_position.distance_to(beach) < 8.0, "the player starts at the beach camp")
	check(player.climber.enabled, "climbing is on inside the quest map")
	check(main.director.compute_objective().begins_with("Climb The Mountain"), "objective: '%s'" % main.director.compute_objective())
	var top := L.summit()
	check(top.y > 290.0, "the summit is %.0f m above the sea" % top.y)
	var biomes := {}
	for c in L.camp_count():
		biomes[L.biome(L.camp_position(c).y)] = true
	biomes[L.biome(top.y)] = true
	biomes[L.biome(20.0)] = true
	biomes[L.biome(230.0)] = true
	check(biomes.size() >= 6, "biomes on the way up: %s" % ", ".join(biomes.keys()))
	_check_ground_shape()
	_check_route("direct")
	_check_route("long")
	await _check_climb()
	await _check_ladder()
	await _check_falls_and_respawn()
	await _check_camp_and_snack()
	await _check_win()


# --- Ground and routes -----------------------------------------------------------------------------

## Physics ground under local point p: a ray from `above` metres over the mountain's own height there.
func _ground(p: Vector3, above := 2.5, below := 6.0) -> Dictionary:
	var start := maxf(p.y, L.height(p.x, p.z)) + above
	var from := map.to_global(Vector3(p.x, start, p.z))
	var to := map.to_global(Vector3(p.x, minf(p.y, L.height(p.x, p.z)) - below, p.z))
	var q := PhysicsRayQueryParameters3D.create(from, to, Build.LAYER_WORLD)
	return map.get_world_3d().direct_space_state.intersect_ray(q)


func _check_ground_shape() -> void:
	var worst := 0.0
	var at := Vector3.ZERO
	var rng := RandomNumberGenerator.new()
	rng.seed = 5
	var n := 0
	while n < 300:
		var lp := Vector3(rng.randf_range(-400, 400), 0, rng.randf_range(-400, 400))
		var want := L.height(lp.x, lp.z)
		var grad := 0.0
		for o: Vector2 in [Vector2(3, 0), Vector2(-3, 0), Vector2(0, 3), Vector2(0, -3)]:
			grad = maxf(grad, absf(L.height(lp.x + o.x, lp.z + o.y) - want))
		if grad > 1.0:
			continue
		n += 1
		lp.y = want
		var hit := _ground(lp, 20.0, 20.0)
		var e := INF if hit.is_empty() else absf(map.to_local(hit.position).y - want)
		if e > worst:
			worst = e
			at = lp
	check(worst < 0.6, "the collision ground matches the mountain's shape (worst %.2f m at %s)" % [worst, str(at.snapped(Vector3.ONE))])


func _check_route(kind: String) -> void:
	print("Route: %s" % kind)
	var legs := L.route(kind)
	var walk := 0.0
	var climbs := 0
	var max_climb := 0.0
	var worst_slope := 0.0
	var bad := []
	var cold_max := Climber.MAX_STAMINA - Climber.COLD_LOSS
	for leg in legs:
		var a: Vector3 = leg.from
		var b: Vector3 = leg.to
		match String(leg.kind):
			"walk", "bridge":
				var flat := Vector2(b.x - a.x, b.z - a.z).length()
				walk += flat
				var n := maxi(int(flat / 0.8), 1)
				var prev := -INF
				for s in n + 1:
					var p := a.lerp(b, float(s) / n)
					var hit := _ground(p) if leg.kind == "walk" else _ground(p, 1.5, 4.0)
					if hit.is_empty():
						bad.append("no ground at %s (%s)" % [str(p.snapped(Vector3.ONE * 0.1)), leg.kind])
						break
					var y: float = map.to_local(hit.position).y
					if y < 0.3:
						bad.append("under water at %s" % str(p.snapped(Vector3.ONE)))
						break
					if prev > -INF:
						var slope := (y - prev) / (flat / n)
						worst_slope = maxf(worst_slope, slope)
						if slope > tan(deg_to_rad(46.0)):
							bad.append("too steep to walk (%.0f deg) at %s" % [rad_to_deg(atan(slope)), str(p.snapped(Vector3.ONE))])
							break
					prev = y
			"climb":
				climbs += 1
				var rise := b.y - a.y
				max_climb = maxf(max_climb, rise)
				var cost := rise / Climber.CLIMB_SPEED * Climber.DRAIN_MOVE
				var cap := cold_max if b.y > L.SNOW_Y - 2.0 else Climber.MAX_STAMINA
				if cost > cap - 4.0:
					bad.append("climb of %.1f m at riser %d needs %.0f stamina (max %.0f)" % [rise, int(leg.get("riser", -1)), cost, cap])
				if _ground(b, 1.5, 3.0).is_empty():
					bad.append("no ledge on top of riser %d" % int(leg.get("riser", -1)))
	check(bad.is_empty(), "%s route: %d legs, %.0f m walking, %d climbs (highest %.1f m), steepest walk %.0f deg%s" % [
		kind, legs.size(), walk, climbs, max_climb, rad_to_deg(atan(worst_slope)), "" if bad.is_empty() else "\n      " + "\n      ".join(bad.slice(0, 8))])
	check((legs[-1].to as Vector3).distance_to(L.summit()) < 1.0, "%s route ends on the summit" % kind)


# --- Climbing --------------------------------------------------------------------------------------

## Moves the player to local point `local` (onto the physics ground there when `snap`), looking at `look_at_local`.
func _put(local: Vector3, look_at_local := Vector3.INF, snap := true) -> void:
	if snap:
		var hit := _ground(local, 3.0, 3.0)
		if not hit.is_empty():
			local.y = map.to_local(hit.position).y + 0.15
	var x := Transform3D(Basis.IDENTITY, map.to_global(local))
	if look_at_local != Vector3.INF:
		var d := map.to_global(look_at_local) - x.origin
		x.basis = Basis.looking_at(Vector3(d.x, 0.0, d.z).normalized(), Vector3.UP)
	player.teleport(x)


func _check_climb() -> void:
	print("Climbing")
	var k := 0
	var th := -0.25
	var foot := L.riser_foot(k, th, 0.3)
	var top_y := L.surface(k + 1, L.boundary(k, th), th)
	_put(foot + Vector3.UP * 0.3, L.at(L.boundary(k, th) - 3.0, th))
	await _seconds(0.5)
	player.stamina = Climber.MAX_STAMINA
	Input.action_press("climb")
	Input.action_press("move_forward")
	var min_stamina := player.stamina
	var was_climbing := false
	var t := 0.0
	while t < 20.0:
		await get_tree().physics_frame
		t += get_physics_process_delta_time()
		min_stamina = minf(min_stamina, player.stamina)
		was_climbing = was_climbing or player.is_climbing
		if map.to_local(player.global_position).y > top_y - 0.3 and not player.is_climbing and player.is_on_floor():
			break
	Input.action_release("move_forward")
	Input.action_release("climb")
	var y := map.to_local(player.global_position).y
	check(was_climbing, "holding climb against the cliff grabs it (is_climbing)")
	check(y > top_y - 0.5, "climbed the %.1f m cliff onto the ledge in %.1f s (at %.1f m, ledge %.1f m)" % [top_y - foot.y, t, y, top_y])
	check(min_stamina < Climber.MAX_STAMINA - 25.0, "climbing drained stamina (down to %.0f)" % min_stamina)
	await _seconds(0.5)
	var before := player.stamina
	await _seconds(3.0)
	check(player.stamina > before + 30.0 or player.stamina >= player.max_stamina - 0.1, "standing recovers stamina (%.0f -> %.0f)" % [before, player.stamina])
	# out of stamina on a wall: hanging, and a crewmate can pull you up
	_put(foot + Vector3.UP * 0.3, L.at(L.boundary(k, th) - 3.0, th))
	await _seconds(0.3)
	Input.action_press("climb")
	Input.action_press("move_forward")
	await _seconds(1.5)
	Input.action_release("move_forward")
	player.stamina = 0.5
	await _seconds(0.3)
	check(player.is_hanging, "out of stamina on the wall: hanging (a crewmate can pull you up)")
	var helper := L.riser_top(k, th, 1.5)
	player.climber.receive_help("pull", map.to_global(helper))
	await _seconds(3.0)
	Input.action_release("climb")
	check(not player.is_hanging and map.to_local(player.global_position).y > top_y - 0.6, "pulled up onto the ledge")
	var cc: Vector3 = map._chimneys[0].center
	check(is_equal_approx(map.drain_factor(cc + Vector3.UP * 3.0), Climber.CHIMNEY_FACTOR), "climbing in the chimney costs %.0f%% stamina" % (Climber.CHIMNEY_FACTOR * 100.0))


func _check_ladder() -> void:
	print("Rope ladder")
	var anchor := map.get_node("Anchor_0") as RopeAnchor
	var ropes := quest.ropes
	check(ropes >= 1, "the crew starts with %d ropes" % ropes)
	anchor.interact(player)
	await _frames(2)
	check(anchor.ladder != null and quest.ropes == ropes - 1 and "Anchor_0" in quest.placed, "a rope on Anchor_0 drops a ladder (ropes %d -> %d)" % [ropes, quest.ropes])
	if anchor.ladder == null:
		return
	var lad := anchor.ladder
	player.teleport(Transform3D(Basis.looking_at(-anchor.out), lad.bottom + lad.offset + Vector3.UP * 0.3))
	await _seconds(0.3)
	player.stamina = 50.0
	Input.action_press("move_forward")
	var t := 0.0
	var on_ladder := false
	while t < 15.0:
		await get_tree().physics_frame
		t += get_physics_process_delta_time()
		on_ladder = on_ladder or player.is_climbing
		if player.global_position.y > lad.top.y - 0.6 and player.is_on_floor():
			break
	Input.action_release("move_forward")
	check(on_ladder and player.global_position.y > lad.top.y - 0.8, "climbed the rope ladder to the top in %.1f s" % t)
	check(player.stamina >= 49.0, "the ladder cost no stamina (%.0f)" % player.stamina)


func _check_falls_and_respawn() -> void:
	print("Falls and campfires")
	var c1 := L.camp_position(1)
	_put(c1 + Vector3(4, 22, 0), Vector3.INF, false)
	player.health = 100.0
	await _seconds(3.0)
	check(player.health < 80.0, "a 22 m fall hurts (health %.0f)" % player.health)
	player.health = 100.0
	quest.camp = 1
	quest.broadcast()
	_put(L.camp_position(0) + Vector3(0, 0.5, -3))
	await _frames(2)
	player.take_fall(150.0)
	await _frames(3)
	var d := player.global_position.distance_to(map.to_global(c1))
	check(player.health >= 99.0 and not player.downed and d < 6.0, "dying on the mountain: back at camp 1 (%.1f m from the fire), not down" % d)
	_put(Vector3(0, -6, 430), Vector3.INF, false)
	await _frames(3)
	d = player.global_position.distance_to(map.to_global(c1))
	check(d < 6.0, "falling into the sea: back at the last campfire")


func _check_camp_and_snack() -> void:
	print("Camps and snacks")
	_put(L.camp_position(2) + Vector3(0, 0.4, 0))
	await _seconds(0.6)
	check(quest.camp == 2 and map.camps[2]._lit, "reaching camp 2 lights it and moves the checkpoint (camp %d)" % quest.camp)
	var snack := map.get_node("Snack_3") as QuestPickup
	player.stamina = 10.0
	snack.interact(player)
	await _frames(2)
	check(player.stamina >= 69.0 and "Snack_3" in quest.taken and not snack.visible, "an energy snack restores stamina (%.0f)" % player.stamina)
	var rope := map.get_node("Rope_2") as QuestPickup
	var r0 := quest.ropes
	rope.interact(player)
	check(quest.ropes == r0 + 2, "a rope coil gives the crew 2 ropes")
	# the cold up high lowers max stamina
	player.climber.cold = 0.0
	_put(L.at(110.0, 1.0, 0.4))
	await _seconds(3.0)
	check(player.climber.cold > 0.02 and player.max_stamina < Climber.MAX_STAMINA - 1.0, "the snow is cold: max stamina %.0f" % player.max_stamina)


func _check_win() -> void:
	print("The summit and the way back")
	_put(L.summit() + Vector3(1.5, 0.5, 0))
	await _frames(3)
	var key := map.key
	check(key != null and key.get_prompt(player).begins_with("Take the gate key"), "the KEY waits on the summit")
	var keys := Game.count("key")
	key.interact(player)
	await _frames(2)
	check(Game.count("key") == keys + 1 and quest.won, "taking it gives the crew the gate key")
	check(main.director.compute_objective().begins_with("The key is yours"), "objective: '%s'" % main.director.compute_objective())
	await quest.left
	await _frames(3)
	var portal := quest.get_node("Portal_%d" % SEG) as QuestPortal
	check(not quest.active and quest.map == null, "the quest map is gone")
	check(player.global_position.distance_to(portal.global_position) < 8.0, "everyone is back at the portal by the gate")
	check(not player.climber.enabled, "climbing is off again in the overworld")
	var gate := main.find_child("Gate_%d" % SEG, true, false) as TrackGate
	(gate.get_node("Lock") as Interactable).interact(player)
	check(not Game.track.is_gate_locked(SEG) and Game.count("key") == keys, "the key from the summit opens gate %d" % SEG)
	check(portal.get_prompt(player) == "", "the portal is closed once the gate is open")
