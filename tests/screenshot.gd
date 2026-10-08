extends Node
## Saves preview screenshots (needs a real or virtual display, not --headless):
##   godot --path . res://tests/Screenshot.tscn -- <output_dir>

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

	var only_repair := OS.get_cmdline_user_args().has("repair")
	if not only_repair:
		await _landscape_shots(track, train, player)
	await _repair_shots(track, train, player)
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
	var slots := repair.find_children("*", "PlaceSlot", true, false)
	slots[0].interact(player)
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


func _view_player(player: Player, pos: Vector3, look: Vector3) -> void:
	player.global_position = pos
	player.velocity = Vector3.ZERO
	var flat := Vector3(look.x, pos.y, look.z)
	player.look_at(flat, Vector3.UP)
	player.rotation.x = 0.0
	player.rotation.z = 0.0
	var eye := pos + Vector3.UP * 1.6
	player.camera.rotation.x = atan2(look.y - eye.y, Vector2(look.x - eye.x, look.z - eye.z).length())


func _shot(name: String) -> void:
	await get_tree().create_timer(0.4).timeout
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png("%s/%s.png" % [out, name])
	print("saved ", name)
