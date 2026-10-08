extends Node
## Tester helper: lobby screenshots (host alone, host with a crew, offline play card, connecting, join failure).
##   godot --path . res://tests/ScreenshotLobby.tscn -- <out_dir>

var out := "user://"


func _ready() -> void:
	if OS.get_cmdline_user_args().size() > 0:
		out = OS.get_cmdline_user_args()[0]
	Net.local_name = "Kader"
	var err := Net.host_game(24611)
	print("host_game: ", error_string(err))
	var lobby: Node = load("res://scenes/net/Lobby.tscn").instantiate()
	add_child(lobby)
	await get_tree().create_timer(2.5).timeout
	await _shot("lobby_1_host_alone")
	Net.players[7] = {"name": "Mara", "ready": true, "color": Net.COLORS[1], "host": false}
	Net.players[8] = {"name": "Big Joe the Stoker", "ready": false, "color": Net.COLORS[2], "host": false}
	Net.players[9] = {"name": "Wren", "ready": true, "color": Net.COLORS[3], "host": false}
	Net.players_changed.emit()
	await get_tree().create_timer(1.0).timeout
	await _shot("lobby_2_host_crew")
	Net.leave()
	await get_tree().create_timer(1.0).timeout
	await _shot("lobby_3_offline_play")
	Net.join_game("127.0.0.1:24619")
	await get_tree().create_timer(1.0).timeout
	await _shot("lobby_4_connecting")
	await get_tree().create_timer(11.0).timeout
	await _shot("lobby_5_join_failed")
	get_tree().quit()


func _shot(n: String) -> void:
	await get_tree().create_timer(0.3).timeout
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png("%s/%s.png" % [out, n])
	print("saved ", n)
