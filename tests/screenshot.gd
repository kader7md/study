extends Node
## Saves preview screenshots (needs a real or virtual display, not --headless):
##   godot --path . res://tests/Screenshot.tscn -- <output_dir> [repair|train|menu|hud|gate|end|tools]
## menu: title screen, settings tabs, join dialog. hud: in-game HUD (1600x900 and 1280x720), shop, pause menu.
## station: station 1 (canopy, name board, shop kiosk) from the track and from the platform.
## gate: locked gate and key. end: Chapter 1 end screen. tools: tool animations and carry poses.
## world: the overworld (aerial view per theme, the whole route, quest sites by the gates, ground-level views) and
## an FPS measurement; add "aerial", "quest" or "ground" to take only that group.

## Each run first deletes the old PNGs of its own mode in <output_dir> (so a run that times out leaves no stale
## pictures that look fresh) and prints "DONE n shots" when it finishes. Run the modes one after another:
## on software rendering each takes several minutes, and parallel runs starve each other.

var main: Node3D
var out := "user://"
var free_cam: Camera3D
var shot_count := 0

## File name prefixes each mode writes (the default run writes the numbered landscape / repair / train shots).
const MODE_PREFIXES := {
	"menu": ["menu_"], "hud": ["hud_"], "gate": ["gate_"], "end": ["end_"], "tools": ["tool_", "carry_"],
	"station": ["station_"], "repair": ["6_", "7_"], "train": ["8_", "9_"], "world": ["world_"],
}


func _ready() -> void:
	if OS.get_cmdline_user_args().size() > 0:
		out = OS.get_cmdline_user_args()[0]
	_clear_old(OS.get_cmdline_user_args())
	tree_exiting.connect(func() -> void: print("DONE %d shots" % shot_count))
	if OS.get_cmdline_user_args().has("menu"):
		await _menu_shots()
		get_tree().quit()
		return
	Game.new_game(false)
	Game.world_sabotage = false
	main = load("res://scenes/main/Main.tscn").instantiate()
	add_child(main)
	await get_tree().create_timer(1.5).timeout
	var track := Game.track
	var train := Game.train
	var player: Player = main.player

	var args := OS.get_cmdline_user_args()
	if args.has("hud"):
		await _hud_shots(track, train, player)
		get_tree().quit()
		return
	# gameplay modes: the locked gate and its key, the Chapter 1 end screen, tool animations and carry poses
	if args.has("world"):
		await _world_shots(track, player, args)
		get_tree().quit()
		return
	if args.has("station"):
		await _station_shots(main.get_node("Station1") as Station)
		get_tree().quit()
		return
	if args.has("gate") or args.has("end") or args.has("tools"):
		if args.has("gate"):
			await _gate_shots(track, train, player)
		if args.has("tools"):
			await _tools_shots(track, train, player)
		if args.has("end"):
			await _end_shots(track, train, player)
		get_tree().quit()
		return
	if not args.has("repair") and not args.has("train"):
		await _landscape_shots(track, train, player)
	if not args.has("train"):
		await _repair_shots(track, train, player)
	await _train_shots(track, train, player)
	get_tree().quit()


func _landscape_shots(track: Track, train: Train, player: Player) -> void:
	# 1. Train at the departure station, seen from the platform
	_view_player(player, track.transform_at(train.distance + 7.0).origin + track.transform_at(train.distance).basis.x * 4.5 + Vector3.UP * 1.3,
		train.cars[1].global_position + Vector3.UP * 1.0)
	await _shot("1_station")

	# 2. Free camera views of the landscape: river bridge, mountain pass, lake
	free_cam = Camera3D.new()
	free_cam.far = 3000.0
	main.add_child(free_cam)
	free_cam.make_current()
	main.hud.visible = false
	for spot in [["2_river_bridge", 1, 0.5], ["3_mountain_pass", 2, 0.5], ["4_lake", 3, 0.76]]:
		var d: float = track.station_distances[spot[1]] + spot[2] * Track.SEGMENT_LENGTH
		var p := track.point_at(d)
		var r := track.flat_right(d)
		free_cam.global_position = p + r * 70.0 - track.flat_forward(d) * 60.0 + Vector3.UP * 28.0
		free_cam.look_at(p + Vector3.UP * 2.0, Vector3.UP)
		await _shot(spot[0])

	# 5. Train side view in the hills
	var tt := track.transform_at(train.center_distance())
	free_cam.global_position = tt.origin + tt.basis.x * 14.0 + Vector3.UP * 4.0 - tt.basis.z * 4.0
	free_cam.look_at(train.cars[1].global_position + Vector3.UP * 1.5, Vector3.UP)
	await _shot("5_train_side")


func _repair_shots(track: Track, train: Train, player: Player) -> void:

	# 6. Rebuilding broken track: a plank placed and nailed, holding the welder
	player.camera.make_current()
	main.hud.visible = true
	var idx := track.piece_at(track.station_distances[0] + 120.0)
	for i in range(idx - 2, idx + 3):
		track.repair_piece(i)
	track.break_piece(idx)
	var repair := track.repair_at(idx)
	train.distance = track.piece_center(idx) - 3.0
	await get_tree().physics_frame
	if repair == null:
		push_error("could not break piece %d" % idx)
		get_tree().quit(1)
		return
	await get_tree().process_frame
	player.carry("plank")
	repair.place_plank(1, player)
	await get_tree().process_frame
	for n in repair.find_children("*", "NailSpot", true, false).slice(0, 1):
		for k in 3:
			n.on_tool_hit("hammer", player)
	player.select_tool("welder")
	var rt := track.transform_at(track.piece_center(idx))
	_view_player(player, rt.origin - rt.basis.z * 3.5 + rt.basis.x * 1.6, rt.origin + Vector3.UP * 0.1)
	await get_tree().create_timer(0.3).timeout
	await _shot("6_repair")

	# 7. Carrying a rail
	player.select_tool("hammer")
	player.carry("rail")
	await get_tree().create_timer(0.2).timeout
	await _shot("7_carry_rail")


func _train_shots(track: Track, train: Train, player: Player) -> void:
	if free_cam == null:
		free_cam = Camera3D.new()
		free_cam.far = 3000.0
		main.add_child(free_cam)
	free_cam.make_current()
	main.hud.visible = false
	var tt := track.transform_at(train.center_distance())
	free_cam.global_position = tt.origin - tt.basis.x * 13.0 + Vector3.UP * 5.0 - tt.basis.z * 6.0
	free_cam.look_at(train.cars[1].global_position + Vector3.UP * 1.8, Vector3.UP)
	await _shot("8_train_covered")
	train.take_damage(55.0)
	await get_tree().create_timer(1.2).timeout
	await _shot("9_train_damaged")


func _menu_shots() -> void:
	var menu: Node = load("res://scenes/menu/MainMenu.tscn").instantiate()
	add_child(menu)
	await get_tree().create_timer(3.5).timeout
	await _shot("menu_1_title")
	await get_tree().create_timer(4.0).timeout
	await _shot("menu_2_title_later")
	var settings: SettingsMenu = menu.get("_settings")
	settings.open()
	for i in settings.tabs.get_tab_count():
		settings.tabs.current_tab = i
		await get_tree().create_timer(0.3).timeout
		await _shot("menu_3_settings_%d_%s" % [i, settings.tabs.get_tab_title(i).to_lower()])
	settings.close()
	menu.call("_open_join")
	await _shot("menu_4_join")


func _hud_shots(track: Track, train: Train, player: Player) -> void:
	main.hud.visible = true
	player.camera.make_current()
	_view_player(player, track.transform_at(train.distance + 7.0).origin + track.transform_at(train.distance).basis.x * 4.5 + Vector3.UP * 1.3,
		train.cars[1].global_position + Vector3.UP * 1.0)
	# Some wear and tear so every bar shows something
	train.take_damage(30.0)
	train.lose_wheel(false)
	train.lever = 1
	train.speed = 6.0
	Game.add("nail_gun")
	player.health = 72.0
	player.frost = 35.0
	Game.say("A wheel came off! (5/6, speed -16%) New wheels are sold at stations.")
	Game.say("Bought Nails x10")
	await get_tree().create_timer(0.6).timeout
	await _shot("hud_1_play")
	Game.show_banner("Station 1 / 5 reached!\nCheckpoint saved. Repair, shop, rest.")
	await get_tree().create_timer(0.8).timeout
	await _shot("hud_2_banner")
	var st := main.get_node_or_null("Station0") as Station
	if st:
		main.hud.open_shop(st)
		await get_tree().create_timer(0.4).timeout
		await _shot("hud_3_shop")
		main.hud.close_shop()
	main.hud.pause_menu.open()
	await get_tree().create_timer(0.5).timeout
	await _shot("hud_4_pause")
	main.hud.pause_menu.close()
	# The UI uses the canvas_items stretch mode, so a 1280x720 window shows exactly this frame scaled by 0.8
	await get_tree().create_timer(0.3).timeout
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	img.resize(1280, 720, Image.INTERPOLATE_LANCZOS)
	img.save_png("%s/hud_5_play_1280x720.png" % out)
	shot_count += 1
	print("saved hud_5_play_1280x720")
func _gate_shots(track: Track, train: Train, player: Player) -> void:
	var seg := 0
	var g := track.gate_distance(seg)
	for i in track.piece_count:
		if track.is_broken(i) and track.piece_center(i) < g:
			track.repair_piece(i)
	# the train stopped in front of the gate; look out of the cab (front door open) towards the gate and the key
	train.distance = g - Track.GATE_STOP - 0.01
	train.speed = 0.0
	train.lever = 0
	for k in 3:
		await get_tree().physics_frame
	var loco := train.cars[0]
	for p in train.parts:
		if p.is_door and p.car == loco and p.node.get_aabb().size.x > p.node.get_aabb().size.z:
			p.toggle_door()
	var key := main.find_child("Key_%d" % seg, true, false) as Node3D
	player.set_physics_process(false)
	# just out of the cab front door on the key's side, on the running board beside the boiler, looking ahead
	var eye := loco.to_global(Vector3(1.15 * signf(track.key_spots[seg].y), Train.FLOOR_HEIGHT + 0.1, -1.4))
	_view_player(player, eye, (key.global_position + track.point_at(g)) * 0.5 + Vector3.UP * 0.6)
	main.hud._banner.visible = false
	await get_tree().create_timer(0.8).timeout
	await _shot("gate_1_cab")
	# from the trackside: the gate, its padlock, the key and the waiting train
	free_cam = Camera3D.new()
	free_cam.far = 3000.0
	main.add_child(free_cam)
	free_cam.make_current()
	main.hud.visible = false
	var t := track.transform_at(g)
	var side := signf(track.key_spots[seg].y)
	free_cam.global_position = t.origin + t.basis.x * side * 11.0 - t.basis.z * 7.0 + Vector3.UP * 3.0
	free_cam.look_at((t.origin + key.global_position) * 0.5 + Vector3.UP * 0.6, Vector3.UP)
	await _shot("gate_2_side")
	free_cam.global_position = t.origin + t.basis.z * 2.6 + t.basis.x * 3.9 + Vector3.UP * 1.3
	free_cam.look_at(t.origin + t.basis.x * 1.8 + t.basis.z * 0.3 + Vector3.UP * 0.7, Vector3.UP)
	await _shot("gate_3_padlock")
	# the signal post 120 m before the gate
	var s := track.transform_at(g - Track.GATE_SIGNAL)
	free_cam.global_position = s.origin + s.basis.z * 14.0 - s.basis.x * 1.0 + Vector3.UP * 2.6
	free_cam.look_at(s.origin + s.basis.x * 2.9 + Vector3.UP * 2.4, Vector3.UP)
	await _shot("gate_4_signal")
	# unlock it: the padlock drops, the boom swings up, the lamps turn green
	Game.add("key")
	(main.find_child("Gate_%d" % seg, true, false).get_node("Lock") as Interactable).interact(player)
	free_cam.global_position = t.origin + t.basis.x * side * 11.0 - t.basis.z * 7.0 + Vector3.UP * 3.0
	free_cam.look_at(t.origin + Vector3.UP * 1.5, Vector3.UP)
	await get_tree().create_timer(2.5).timeout
	await _shot("gate_5_open")


func _end_shots(_track: Track, _train: Train, player: Player) -> void:
	Game.stats = {"time": 2843.0, "distance": 7512.0, "repairs": 21.0, "panels": 6.0, "wheels_lost": 2.0, "gates": 5.0, "gold_found": 38.0}
	player.set_physics_process(false)
	main.director.show_end_screen()
	await get_tree().create_timer(2.4).timeout
	await _shot("end_1_complete")


## Tool animations caught mid-motion, then the four carry poses.
func _tools_shots(track: Track, train: Train, player: Player) -> void:
	player.set_physics_process(false)
	player.camera.make_current()
	main.hud.visible = false
	# on the platform beside the train, looking along it
	var t := track.transform_at(track.station_distances[train.current_station if train.current_station >= 0 else 0])
	_view_player(player, t.origin + t.basis.x * 3.5 + Vector3.UP * 1.4, t.origin + t.basis.x * 3.0 - t.basis.z * 20.0 + Vector3.UP * 1.0)
	player.camera.rotation.x = -0.15
	Game.add("nail_gun")
	var vm := player.viewmodel
	var shots := [["hammer", "hammer", 0.12, "tool_1_hammer_windup"], ["hammer", "hammer", 0.235, "tool_2_hammer_strike"],
		["wrench", "wrench", 0.36, "tool_3_wrench_twist"], ["nail_gun", "nail_gun", 0.035, "tool_4_nailgun_recoil"],
		["come_along", "come_along", 0.2, "tool_5_comealong_pump"]]
	for s: Array in shots:
		player.select_tool(s[0])
		await get_tree().create_timer(0.6).timeout
		Engine.time_scale = 1.0
		vm.play(s[1])
		await get_tree().create_timer(s[2]).timeout
		Engine.time_scale = 0.0
		await _shot(s[3], 0.0)
		Engine.time_scale = 1.0
		await get_tree().create_timer(0.6).timeout
	var src: WelderSource = main.get_node("Station0").find_children("*", "WelderSource", true, false)[0]
	player.take_welder(src)
	await get_tree().create_timer(0.6).timeout
	vm.set_welding(true)
	await get_tree().create_timer(0.3).timeout
	await _shot("tool_6_welder", 0.0)
	vm.set_welding(false)
	player.select_tool("hammer")
	for item in ["plank", "rail", "wheel", "panel"]:
		player.carry(item)
		await get_tree().create_timer(0.4).timeout
		await _shot("carry_%s" % item, 0.0)
		player.consume_carried()
		await get_tree().create_timer(0.5).timeout


func _station_shots(st: Station) -> void:
	main.hud.visible = false
	var cam := Camera3D.new()
	cam.far = 2000.0
	main.add_child(cam)
	cam.make_current()
	var views := [
		["station_1_track", Vector3(-6.0, 3.0, 30.0), Vector3(4.0, 2.5, 0.0)],
		["station_2_kiosk", Vector3(1.0, 2.6, Station.SHOP_Z - 6.0), Vector3(4.6, 2.4, Station.SHOP_Z)],
		["station_3_sign", Vector3(0.5, 2.8, Station.SIGN_Z + 7.0), Vector3(Station.SIGN_X, 3.6, Station.SIGN_Z)],
	]
	for v: Array in views:
		cam.global_position = st.to_global(v[1])
		cam.look_at(st.to_global(v[2]), Vector3.UP)
		await _shot(v[0], 0.6)
	main.hud.visible = true


func _world_cam() -> Camera3D:
	if free_cam == null:
		free_cam = Camera3D.new()
		free_cam.far = 6000.0
		main.add_child(free_cam)
	free_cam.make_current()
	main.hud.visible = false
	return free_cam


func _world_shots(track: Track, player: Player, args: PackedStringArray) -> void:
	var all := not (args.has("aerial") or args.has("quest") or args.has("ground"))
	var terrain: Terrain = Game.terrain
	player.set_physics_process(false)
	if all or args.has("aerial"):
		var cam := _world_cam()
		# the whole route from high above the departure end
		var mid := track.point_at(track.get_length() * 0.45)
		cam.global_position = track.point_at(0.0) + Vector3(-900.0, 1400.0, 900.0)
		cam.look_at(mid, Vector3.UP)
		var only_some := Array(args).any(func(a: String) -> bool: return a.begins_with("seg"))
		if not only_some:
			await _shot("world_0_route", 1.0)
		for seg in Track.THEMES.size():
			if only_some and not args.has("seg%d" % (seg + 1)):
				continue
			var d := track.station_distances[seg] + Track.SEGMENT_LENGTH * 0.45
			var p := track.point_at(d)
			var f := track.flat_forward(d)
			var r := track.flat_right(d)
			cam.global_position = p - f * 380.0 - r * 260.0 + Vector3.UP * 230.0
			cam.look_at(p + f * 250.0 + r * 60.0, Vector3.UP)
			await _shot("world_%d_aerial_%s" % [seg + 1, str(Track.THEMES[seg].name).to_lower().replace(" ", "_")], 1.0)
	if all or args.has("quest"):
		var cam := _world_cam()
		for seg in [0, 2, 3]:
			var q := track.quest_zone(seg)
			var c: Vector3 = q.center
			var side: float = q.side
			var r := (q.forward as Vector3).cross(Vector3.UP)
			var g := track.point_at(track.gate_distance(seg))
			cam.global_position = g - r * side * 45.0 - (q.forward as Vector3) * 60.0 + Vector3.UP * 38.0
			cam.look_at(c, Vector3.UP)
			await _shot("world_q%d_quest_site" % seg, 1.0)
		# from the track, by the gate
		var q0 := track.quest_zone(0)
		var g0 := track.transform_at(track.gate_distance(0) + 6.0)
		_view_player(player, g0.origin + g0.basis.x * q0.side * 3.0 + Vector3.UP * 0.2, q0.center + Vector3.UP * 1.0)
		player.camera.make_current()
		main.hud.visible = false
		await _shot("world_q_from_gate", 1.0)
	if all or args.has("ground"):
		var spots := [[0, 0.3, 120.0, "forest"], [1, 0.42, -150.0, "valley"], [2, 0.62, 140.0, "pass"], [3, 0.7, -90.0, "lake"], [4, 0.6, 80.0, "coast"]]
		for sp in spots:
			var d: float = track.station_distances[sp[0]] + Track.SEGMENT_LENGTH * float(sp[1])
			var u: float = sp[2]
			var on := track.point_at(d)
			var pos := on + track.flat_right(d) * u
			pos.y = terrain.ground_at(pos.x, pos.z) + 0.1
			var look := on + track.flat_forward(d) * 160.0 - track.flat_right(d) * u * 0.4
			look.y = pos.y + 8.0
			_view_player(player, pos, look)
			player.camera.make_current()
			main.hud.visible = false
			terrain.update_collision()
			await _shot("world_g_%s" % sp[3], 1.2)
		# frame rate at the last ground view
		var frames := Engine.get_frames_drawn()
		var t0 := Time.get_ticks_msec()
		await get_tree().create_timer(3.0).timeout
		var fps := (Engine.get_frames_drawn() - frames) * 1000.0 / maxf(Time.get_ticks_msec() - t0, 1.0)
		print("[fps] ground view: %.1f fps, %d draw calls, %d primitives" % [fps,
			RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_DRAW_CALLS_IN_FRAME),
			RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_PRIMITIVES_IN_FRAME)])


func _view_player(player: Player, pos: Vector3, look: Vector3) -> void:
	player.global_position = pos
	player.velocity = Vector3.ZERO
	var flat := Vector3(look.x, pos.y, look.z)
	player.look_at(flat, Vector3.UP)
	player.rotation.x = 0.0
	player.rotation.z = 0.0
	var eye := pos + Vector3.UP * 1.6
	player.camera.rotation.x = atan2(look.y - eye.y, Vector2(look.x - eye.x, look.z - eye.z).length())


func _shot(name: String, settle := 0.4) -> void:
	if settle > 0.0:
		await get_tree().create_timer(settle).timeout
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png("%s/%s.png" % [out, name])
	shot_count += 1
	print("saved ", name)


func _clear_old(args: PackedStringArray) -> void:
	var prefixes: Array = []
	for mode: String in MODE_PREFIXES:
		if args.has(mode):
			prefixes.append_array(MODE_PREFIXES[mode])
	if prefixes.is_empty():
		prefixes = ["1_", "2_", "3_", "4_", "5_", "6_", "7_", "8_", "9_"]
	var dir := DirAccess.open(out)
	if dir == null:
		return
	for f in dir.get_files():
		if f.ends_with(".png") and prefixes.any(func(p: String) -> bool: return f.begins_with(p)):
			dir.remove(f)
