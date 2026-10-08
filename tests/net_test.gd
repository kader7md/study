extends Node
## Two-process multiplayer test (Net, lobby, world sync, client requests, roles, disconnect). Run both with
##   tests/run_net_test.sh
## or by hand, in two terminals:
##   godot --headless --path . res://tests/NetTest.tscn -- host   [--port 24599]
##   godot --headless --path . res://tests/NetTest.tscn -- client [--port 24599]
## The host waits for the client in the lobby, starts the run, drives the train, breaks a rail piece in front of it and
## (after the client worked on it) finishes the repair and drives across. The client joins with an invite code,
## checks the world it sees, and does real work through requests: picks up a pickup, takes a plank from the cargo car,
## places it on the gap and nails it down. Each process prints PASSED / FAILED and exits 0 / 1.
## Screenshots (needs a display, e.g. xvfb-run, and --rendering-driver opengl3):
##   ... res://tests/NetTest.tscn -- shots <out_dir>                  lobby (host view with 3 players) + play card
##   ... -- host --shot <out_dir>  /  -- client --shot <out_dir>      each one looks at the other player in game

const TIMEOUT := 160.0

var mode := ""
var port := 24599
var failures := 0
var _flags := {}       # set by the other process through _tell()
var _disconnect_reason := ""
var shot_dir := ""
var _finished := false


func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	mode = "host" if args.has("host") else ("client" if args.has("client") else ("shots" if args.has("shots") else ""))
	var i := args.find("--port")
	if i >= 0 and i + 1 < args.size():
		port = args[i + 1].to_int()
	var s := args.find("--shot")
	if s >= 0 and s + 1 < args.size():
		shot_dir = args[s + 1]
	if mode == "":
		print("usage: -- host|client [--port N]")
		get_tree().quit(2)
		return
	# Stay alive when the run changes the scene to Main: a stand-in becomes the scene that gets replaced.
	await get_tree().process_frame
	var stand_in := Node.new()
	stand_in.name = "StandIn"
	get_tree().root.add_child(stand_in)
	get_tree().current_scene = stand_in
	if mode == "shots":
		shot_dir = args[args.find("shots") + 1] if args.find("shots") + 1 < args.size() else "user://"
		await _lobby_shots()
		get_tree().quit()
		return
	get_tree().create_timer(TIMEOUT, true, false, true).timeout.connect(func():
		check(false, "finished within %d s" % int(TIMEOUT))
		_finish())
	Net.disconnected.connect(func(reason: String): _disconnect_reason = reason)
	print("[%s] net test on port %d" % [mode, port])
	if mode == "host":
		await _host()
	else:
		await _client()
	_finish()


func _shot(file: String) -> void:
	if shot_dir == "":
		return
	await get_tree().create_timer(0.5).timeout
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png("%s/%s.png" % [shot_dir, file])
	print("saved ", file)


## Lobby screenshots: the host's room with three players (two of them made up locally), then the Play card.
func _lobby_shots() -> void:
	await get_tree().process_frame
	Net.local_name = "Kader"
	Net.host_game(port)
	Net.players[2] = {"name": "Ana", "ready": true, "color": Net.COLORS[1], "host": false}
	Net.players[3] = {"name": "Bo", "ready": false, "color": Net.COLORS[2], "host": false}
	get_tree().change_scene_to_file(Net.LOBBY_SCENE)
	await get_tree().create_timer(1.2).timeout
	Net.players_changed.emit()
	await _shot("lobby_host")
	Net.leave()
	Net.last_error = ""
	get_tree().change_scene_to_file(Net.LOBBY_SCENE)
	await get_tree().create_timer(1.0).timeout
	await _shot("lobby_play")


## Puts `me` a few metres in front of `other` and looks at them.
func _look_at_player(me: Player, other: Player) -> void:
	var fwd := -other.global_basis.z
	var pos := other.global_position + fwd * 3.2 + other.global_basis.x * 0.6
	me.global_position = pos
	me.velocity = Vector3.ZERO
	var target := other.global_position + Vector3.UP * 1.2
	me.look_at(Vector3(target.x, pos.y, target.z), Vector3.UP)
	me.rotation.x = 0.0
	me.rotation.z = 0.0
	me.camera.rotation.x = -0.12


func _finish() -> void:
	if _finished:
		return
	_finished = true
	print("\n%s %s: %d failure(s)" % [mode.to_upper(), "PASSED" if failures == 0 else "FAILED", failures])
	if Net.backend:
		Net.leave()
	get_tree().quit(1 if failures > 0 else 0)


func check(ok: bool, what: String) -> void:
	print(("  ok   " if ok else "  FAIL ") + "[%s] %s" % [mode, what])
	if not ok:
		failures += 1


func _wait(seconds: float) -> void:
	await get_tree().create_timer(seconds).timeout


func _wait_until(cond: Callable, timeout: float) -> bool:
	var t := 0.0
	while t < timeout:
		if cond.call():
			return true
		await get_tree().process_frame
		t += get_process_delta_time()
	return cond.call()


func _main() -> Node:
	var scene := get_tree().current_scene
	return scene if scene and scene.name == "Main" else null


@rpc("any_peer", "call_remote", "reliable")
func _tell(flag: String, value: Variant) -> void:
	_flags[flag] = value


# --- Host ---------------------------------------------------------------------------------

func _host() -> void:
	Net.local_name = "Host"
	Net.debug_force_impostor = true
	print("Lobby")
	check(Net.host_game(port) == OK and Net.is_online() and Net.is_host(), "hosting on port %d" % port)
	check(Net.invite_code().length() == 11, "has an invite code (%s)" % Net.invite_code())
	var joined := await _wait_until(func(): return Net.players.size() == 2, 30.0)
	check(joined, "the client joined the lobby")
	if not joined:
		return
	var cid := 0
	for id: int in Net.players:
		if id != 1:
			cid = id
	check(Net.player_name(cid) == "Client", "the client's name arrived (%s)" % Net.player_name(cid))
	check(not Net.can_start(), "can't start before everyone is ready")
	check(await _wait_until(func(): return Net.players.has(cid) and Net.players[cid].ready, 15.0), "the client is ready")
	check(Net.can_start(), "now the host can start")

	print("Start the run")
	Net.start_run()
	var loaded := await _wait_until(func(): return _main() != null and Game.train != null and Net.is_peer_ready(cid), 60.0)
	check(loaded, "both loaded the world (the client reported ready)")
	if not loaded:
		return
	await _wait(1.0)
	var main := _main()
	var me: Player = main.player
	var them := main.get_node_or_null("Players/Player_%d" % cid) as Player
	check(me != null and me.name == "Player_1" and me.is_local(), "the host plays Player_1")
	check(them != null and not them.is_local(), "the client's player exists on the host (remote)")
	if them:
		check(them.get_node_or_null("Body") != null and not them.camera.visible, "remote player: a body, no first-person arms")
	if shot_dir != "" and them:
		me.carry("plank")
		await _wait(5.0)  # the client looks at us, then steps aside
		_look_at_player(me, them)
		await _wait(0.8)
		print("host at %s looks at the client at %s" % [me.global_position, them.global_position])
		await _shot("host_sees_client")
		me.consume_carried()

	print("Train")
	var train := Game.train
	var track := Game.track
	Game.world_sabotage = false
	for i in range(track.piece_at(train.rear_distance()), track.piece_at(train.distance + 600.0)):
		track.repair_piece(i)
	train.fuel = 100.0
	var start := train.distance
	train.lever = 1
	check(await _wait_until(func(): return train.distance > start + 35.0, 40.0), "the train drives (%.0f m)" % (train.distance - start))
	train.lever = 0
	await _wait_until(func(): return train.is_stopped(), 20.0)
	await _wait(0.5)
	var gap := track.piece_at(train.distance + 14.0)
	check(track.break_piece(gap), "a rail piece breaks in front of the train (%d)" % gap)
	_tell.rpc_id(cid, "work", gap)

	print("The client works on the gap")
	var worked := await _wait_until(func(): return _flags.has("client_worked"), 60.0)
	check(worked, "the client says it is done")
	var repair := track.repair_at(gap)
	check(repair != null and repair.planks.has(1) and repair.planks[1].fixed, "the client's plank lies in slot 1, nailed down (on the host)")
	if them:
		check(them.carried_item == "", "the client's hands are empty again")
	var pickup_name: String = _flags.get("pickup", "")
	check(pickup_name != "" and main.get_node_or_null(pickup_name) == null, "the pickup the client took is gone on the host")

	print("The host finishes the repair")
	var gold := Game.count("gold")
	if repair:
		repair.finish_instantly()
	Game.add("gold", 7)
	check(Game.count("gold") == gold + 7, "inventory changed on the host")
	train.lever = 1
	var passed := await _wait_until(func(): return train.rear_distance() > (gap + 1) * Track.PIECE_LENGTH + 2.0, 40.0)
	check(passed, "the train crosses the rebuilt piece")
	train.lever = 0
	await _wait_until(func(): return train.is_stopped(), 20.0)
	_tell.rpc_id(cid, "host_done", true)

	print("World events: sabotage, damage, cover pieces")
	var sab := Game.sabotage
	for id: String in sab.cooldowns:
		sab.cooldowns[id] = 0.0
	check(sab.use("zombies") and sab.use("eagles"), "zombies and eagles attack")
	var ahead := track.point_at(train.distance + 90.0)
	check(sab.use("meteor", ahead), "a meteor falls on the track ahead")
	train.weld_full()
	train.take_damage(36.0)
	var attached := train.attached_count()
	check(attached < train.parts.size(), "damage knocks cover pieces off (%d/%d left)" % [attached, train.parts.size()])
	_tell.rpc_id(cid, "events", attached)
	check(await _wait_until(func(): return _flags.has("enemies_seen"), 30.0), "the client saw the attack")
	for e in get_tree().get_nodes_in_group("enemy"):
		e.queue_free()
	await _wait(Meteor.FALL_TIME + 0.5)
	_tell.rpc_id(cid, "cleared", track.broken_count())
	var refit := await _wait_until(func(): return _flags.has("refit"), 60.0)
	check(refit, "the client says it refitted a panel")
	if refit:
		var part := train.parts[int(_flags.refit)]
		check(part.attached, "the client's panel is back on, on the host (%s)" % part.name)

	print("Roles and sabotage")
	var got_role := await _wait_until(func(): return _flags.has("role"), 30.0)
	check(got_role, "the client reports its role (test only)")
	var impostors := (1 if Game.role == "impostor" else 0) + (1 if _flags.get("role", "") == "impostor" else 0)
	check(impostors == 1, "exactly one impostor (debug_force_impostor with 2 players)")
	# the client asks to use the freezing wind: only allowed if it is the impostor
	await _wait_until(func(): return _flags.has("sabotage_sent"), 20.0)
	await _wait(1.0)
	var client_is_impostor: bool = _flags.get("role", "") == "impostor"
	check(Game.wind_active == client_is_impostor, "a client's sabotage request runs only if it is the impostor (wind %s)" % Game.wind_active)
	_tell.rpc_id(cid, "wind_checked", Game.wind_active)
	await _wait_until(func(): return _flags.has("client_checked"), 30.0)

	print("Host leaves")
	await _wait(0.5)
	Net.leave_to_menu()
	await _wait(2.0)
	check(not Net.is_online(), "the host is offline again")


# --- Client -------------------------------------------------------------------------------

func _client() -> void:
	Net.local_name = "Client"
	print("Lobby")
	await _wait(1.0)
	var code := InviteCode.encode("127.0.0.1", port)
	var info := InviteCode.decode(code, 0)
	check(info.ok and info.ip == "127.0.0.1" and info.port == port, "invite code %s decodes to 127.0.0.1:%d" % [code, port])
	check(Net.join_game(code) == OK, "joining with the invite code")
	var joined := await _wait_until(func(): return Net.players.has(Net.local_id()), 20.0)
	for retry in 3:
		if joined:
			break
		await _wait(2.0)  # the host may still be starting up
		Net.join_game(code)
		joined = await _wait_until(func(): return Net.players.has(Net.local_id()), 20.0)
	check(joined, "joined the lobby")
	if not joined:
		return
	check(Net.players.size() == 2 and Net.player_name(1) == "Host", "sees the host in the lobby")
	check(not Net.is_host() and Net.is_online(), "is a client")
	Net.set_ready(true)

	print("Start the run")
	var loaded := await _wait_until(func(): return _main() != null and Game.train != null and _main().player != null, 60.0)
	check(loaded, "loaded Main and got its own player from the host")
	if not loaded:
		return
	var main := _main()
	var me: Player = main.player
	var host_player := main.get_node_or_null("Players/Player_1") as Player
	check(me.name == "Player_%d" % Net.local_id() and me.is_local(), "main.player is our own Player_%d" % Net.local_id())
	check(main.get_node("Players").get_children().filter(func(n): return n is Player).size() == 2, "2 players in the world")
	check(host_player != null and not host_player.is_local(), "Player_1 (the host) is remote here")
	if host_player:
		check(host_player.get_node_or_null("Body") != null and not host_player.camera.visible, "the host's body shows, without floating arms")
		check(host_player.display_name == "Host", "with the host's name")
	check(main.get_node_or_null("WorldSync") != null, "world sync is running")
	if shot_dir != "" and host_player:
		_look_at_player(me, host_player)
		await _wait(1.5)
		await _shot("client_sees_host")
		# step back onto the platform, facing the train, holding the wrench
		var t := Game.track.transform_at(Game.train.distance - 10.0)
		_teleport(me, t.origin + t.basis.x * 3.5 + Vector3.UP * 1.2)
		me.select_tool("wrench")

	print("Train")
	var train := Game.train
	var track := Game.track
	await _wait(0.5)
	var start := train.distance
	var moved := await _wait_until(func(): return train.distance > start + 20.0, 40.0)
	check(moved, "the train moves on the client too (%.0f m)" % (train.distance - start))
	check(await _wait_until(func(): return _flags.has("work"), 40.0), "the host broke a piece for us")
	var gap: int = _flags.get("work", -1)
	check(await _wait_until(func(): return track.is_broken(gap), 5.0), "the broken piece shows on the client")
	await _wait(0.5)

	print("Pick up something")
	var pickup: Pickup = null
	var best := INF
	for p in main.get_node("Pickups").get_children():
		if p is Pickup and p.item != "gold":
			var d: float = p.global_position.distance_to(train.cars[1].global_position)
			if d < best:
				best = d
				pickup = p
	check(pickup != null, "found a pickup near the train (%.0f m)" % best)
	if pickup:
		var item := pickup.item
		var before := Game.count(item)
		var pickup_name := String(main.get_path_to(pickup))
		_teleport(me, pickup.global_position + Vector3(0.8, 1.0, 0.0))
		await _wait(0.4)
		Net.request(pickup, &"interact", [me])
		var gone := await _wait_until(func(): return not is_instance_valid(pickup) or pickup.is_queued_for_deletion(), 5.0)
		check(gone, "the pickup disappears on the client")
		check(await _wait_until(func(): return Game.count(item) > before, 5.0), "the shared inventory grew (%s %d -> %d)" % [item, before, Game.count(item)])
		_tell.rpc_id(1, "pickup", pickup_name)

	print("Take a plank, place it, nail it")
	var cargo := train.cars[1]
	var spot: Interactable = null
	for s in cargo.find_children("*", "ActionSpot", true, false):
		if (s as ActionSpot).get_prompt(me).contains("plank"):
			spot = s
	check(spot != null, "found the plank spot in the cargo car")
	if spot:
		_teleport(me, spot.global_position + cargo.global_basis.x * 1.8 + Vector3.UP * 0.3)
		await _wait(0.4)
		var wood := Game.count("wood")
		Net.request(spot, &"interact", [me])
		check(await _wait_until(func(): return me.carried_item == "plank", 5.0), "carrying a plank (the host said so)")
		check(await _wait_until(func(): return Game.count("wood") == wood - 1, 5.0), "it cost 1 wood")
	var repair := track.repair_at(gap)
	check(repair != null and repair.name == "Repair_%d" % gap, "the gap has the same repair node as on the host")
	if repair:
		_teleport(me, repair.global_position + repair.global_basis.x * 2.5 + Vector3.UP * 0.8)
		await _wait(0.4)
		me._test_aim = repair.to_global(Vector3(0, Track.SLEEPER_Y, RailRepair.SLOTS[1]))
		Net.request(repair.get_node("Area"), &"interact", [me])
		check(await _wait_until(func(): return repair.planks.has(1), 5.0), "the plank appears in slot 1")
		check(await _wait_until(func(): return me.carried_item == "", 5.0), "hands empty after placing")
		me._test_aim = Vector3.INF
		await _wait(0.3)
		for nail_name in ["Plank1/Nail0", "Plank1/Nail1"]:
			var nail := repair.get_node_or_null(nail_name)
			check(nail != null, "%s exists on the client" % nail_name)
			for k in NailSpot.HAMMER_HITS:
				if nail:
					Net.request(me, &"tool_hit", [nail, "hammer", Player.HAMMER_DAMAGE])
				await _wait(0.15)
		check(await _wait_until(func(): return repair.planks.has(1) and repair.planks[1].fixed, 5.0), "the plank is nailed down (seen on the client)")
		var nail0 := repair.get_node_or_null("Plank1/Nail0") as NailSpot
		check(nail0 != null and nail0.finished, "the nails went in")
	_tell.rpc_id(1, "client_worked", true)

	print("The host finishes the repair")
	var gold := Game.count("gold")
	check(await _wait_until(func(): return _flags.has("host_done"), 60.0), "the host finished")
	check(not track.is_broken(gap), "the repaired piece is whole on the client")
	check(Game.count("gold") >= gold + 7, "the inventory change arrived (gold %d -> %d)" % [gold, Game.count("gold")])
	check(train.rear_distance() > (gap + 1) * Track.PIECE_LENGTH, "the train crossed it on the client too")

	print("World events: sabotage, damage, cover pieces")
	check(await _wait_until(func(): return _flags.has("events"), 30.0), "the host started the attack")
	var named := func(prefix: String) -> int:
		return main.get_children().filter(func(n): return String(n.name).begins_with(prefix)).size()
	check(await _wait_until(func(): return named.call("Zombie_") >= 5, 5.0), "5 zombies run at the train here too (%d)" % named.call("Zombie_"))
	check(await _wait_until(func(): return named.call("Eagle_") >= 2, 5.0), "2 eagles dive at the cargo")
	check(await _wait_until(func(): return named.call("Meteor_") >= 1, 5.0), "the meteor falls here too")
	var zombie := main.get_children().filter(func(n): return String(n.name).begins_with("Zombie_"))[0] as Node3D
	var z_from := zombie.global_position
	check(await _wait_until(func(): return is_instance_valid(zombie) and zombie.global_position.distance_to(z_from) > 1.0, 5.0), "zombie puppets follow the host's zombies")
	var host_attached: int = _flags.events
	check(await _wait_until(func(): return train.attached_count() == host_attached, 5.0), "the same cover pieces are off (%d/%d)" % [train.attached_count(), train.parts.size()])
	check(await _wait_until(func(): return named.call("Fallen_") > 0, 5.0), "broken pieces lie around (%d)" % named.call("Fallen_"))
	_tell.rpc_id(1, "enemies_seen", true)
	check(await _wait_until(func(): return _flags.has("cleared"), 30.0), "the host cleared the attackers")
	check(await _wait_until(func(): return named.call("Zombie_") == 0 and named.call("Eagle_") == 0, 5.0), "and they are gone here too")
	var host_broken: int = _flags.cleared
	check(await _wait_until(func(): return track.broken_count() == host_broken, 5.0), "the meteor's damage to the track matches (%d broken pieces)" % track.broken_count())
	# refit one wooden panel: take a new panel from the cargo car, place it, nail it
	var wpart: BodyPart = null
	for p in train.parts:
		if not p.attached and p.material == "wood" and p.slot() != null and wpart == null:
			wpart = p
	check(wpart != null, "a wooden piece is missing")
	if wpart:
		var slot := wpart.slot()
		check(slot.name == "Slot_%s" % wpart.name, "its slot has the host's name (%s)" % slot.name)
		var panel_spot: Interactable = null
		for s in cargo.find_children("*", "ActionSpot", true, false):
			if (s as ActionSpot).get_prompt(me).contains("panel"):
				panel_spot = s
		_teleport(me, panel_spot.global_position + cargo.global_basis.x * 1.8 + Vector3.UP * 0.3)
		await _wait(0.4)
		Net.request(panel_spot, &"interact", [me])
		check(await _wait_until(func(): return me.carried_item == "panel", 5.0), "carrying a new panel")
		_teleport(me, slot.global_position + Vector3.UP * 0.5 + (slot.global_position - wpart.car.global_position).normalized() * 1.5)
		await _wait(0.4)
		Net.request(slot, &"interact", [me])
		check(await _wait_until(func(): return wpart.is_pending(), 5.0), "the panel is in place, waiting for nails")
		var fixes := wpart.car.get_children().filter(func(n): return String(n.name).begins_with("Fix_%s_" % wpart.name))
		check(fixes.size() == 2, "2 nails to drive (%d)" % fixes.size())
		for f in fixes:
			for k in NailSpot.HAMMER_HITS:
				Net.request(me, &"tool_hit", [f, "hammer", Player.HAMMER_DAMAGE])
				await _wait(0.12)
		check(await _wait_until(func(): return wpart.attached, 5.0), "nailed on: the piece is back (on the client)")
		_tell.rpc_id(1, "refit", train.parts.find(wpart))

	print("Roles and sabotage")
	check(Game.role == "crew" or Game.role == "impostor", "got a role (%s)" % Game.role)
	_tell.rpc_id(1, "role", Game.role)
	Net.request(Game.sabotage, &"use", ["freezing_wind"])
	_tell.rpc_id(1, "sabotage_sent", true)
	check(await _wait_until(func(): return _flags.has("wind_checked"), 30.0), "the host checked the sabotage")
	var wind: bool = _flags.get("wind_checked", false)
	check(await _wait_until(func(): return Game.wind_active == wind, 5.0), "the wind state matches the host's (%s)" % wind)
	_tell.rpc_id(1, "client_checked", true)

	print("The host leaves")
	var dropped := await _wait_until(func(): return _disconnect_reason != "", 30.0)
	check(dropped and _disconnect_reason == "Host left the game", "told: '%s'" % _disconnect_reason)
	await _wait(1.0)
	check(_main() == null and not Net.is_online(), "back at the menu, offline")


func _teleport(p: Player, pos: Vector3) -> void:
	p.global_position = pos
	p.velocity = Vector3.ZERO
