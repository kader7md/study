extends Node
## Saves preview screenshots (needs a real or virtual display, not --headless):
##   godot --path . res://tests/Screenshot.tscn -- <output_dir>

func _ready() -> void:
	var out := OS.get_cmdline_user_args()[0] if OS.get_cmdline_user_args().size() > 0 else "user://"
	Game.new_game(false)
	Game.world_sabotage = false
	var main: Node3D = load("res://scenes/main/Main.tscn").instantiate()
	add_child(main)
	await get_tree().create_timer(1.5).timeout
	await _shot(out + "/shot_station.png")

	# Look at the locomotive from the platform
	var player: Player = main.player
	var train := Game.train
	player.global_position = Game.track.transform_at(train.distance + 6.0).origin + Game.track.transform_at(train.distance).basis.x * 4.5 + Vector3.UP * 1.3
	player.look_at(train.cars[1].global_position, Vector3.UP)
	player.rotation.x = 0
	player.camera.rotation.x = -0.15
	await get_tree().create_timer(0.5).timeout
	await _shot(out + "/shot_train.png")

	# Ride on the cargo car while moving, with a meteor coming down ahead
	player.global_position = train.cars[2].global_position + Vector3.UP * 1.8
	player.rotation = Vector3.ZERO
	player.look_at(train.cars[0].global_position + Vector3.UP * 1.6, Vector3.UP)
	player.rotation.x = 0
	player.camera.rotation.x = -0.05
	train.fuel = 100
	train.lever = 1
	await get_tree().create_timer(4.0).timeout
	Game.sabotage.use("meteor", Game.track.point_at(train.distance + 45.0))
	await get_tree().create_timer(1.8).timeout
	await _shot(out + "/shot_ride.png")
	get_tree().quit()


func _shot(path: String) -> void:
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(path)
	print("saved ", path)
