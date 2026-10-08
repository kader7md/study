extends Node
## Saves preview screenshots (needs a real or virtual display, not --headless):
##   godot --path . res://tests/Screenshot.tscn -- <output_dir> [repair|train|gate|end|tools]

var main: Node3D
var out := "user://"
var free_cam: Camera3D


func _ready() -> void:
	if OS.get_cmdline_user_args().size() > 0:
		out = OS.get_cmdline_user_args()[0]
	Game.new_game(false)
	Game.world_sabotage = false
	main = load("res://scenes/main/Main.tscn").instantiate()
	add_child(main)
	await get_tree().create_timer(1.5).timeout
	var track := Game.track
	var train := Game.train
	var player: Player = main.player

	var args := OS.get_cmdline_user_args()
	# gameplay modes: the locked gate and its key, the Chapter 1 end screen, tool animations and carry poses
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
	main.hud._banner.text = ""
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
	print("saved ", name)
