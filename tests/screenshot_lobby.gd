extends Node
## Tester helper: lobby screenshots (host alone, host with a crew, offline play card, connecting, join failure).
##   godot --path . res://tests/ScreenshotLobby.tscn -- <out_dir>
## Clears old lobby_*.png in <out_dir> first and prints "DONE n shots" at the end. Uses random free ports, so
## several runs can share a machine.

var out := "user://"
var shots := 0


func _ready() -> void:
	if OS.get_cmdline_user_args().size() > 0:
		out = OS.get_cmdline_user_args()[0]
	_clear_old()
	Net.local_name = "Kader"
	Net.auto_public_ip = false  # no outside requests from a test
	var rng := RandomNumberGenerator.new()
	rng.randomize()
	var host_port := rng.randi_range(30000, 60000)
	var err := Net.host_game(host_port)
	print("host_game: ", error_string(err))
	var lobby: Node = load("res://scenes/net/Lobby.tscn").instantiate()
	add_child(lobby)
	await get_tree().create_timer(2.5).timeout
	await _shot("lobby_1_host_alone")
	Net.set_manual_public_ip("203.0.113.7")  # documentation address: shows the internet code
	Net.players[7] = {"name": "Mara", "ready": true, "color": Net.COLORS[1], "host": false}
	Net.players[8] = {"name": "Big Joe the Stoker", "ready": false, "color": Net.COLORS[2], "host": false}
	Net.players[9] = {"name": "Wren", "ready": true, "color": Net.COLORS[3], "host": false}
	Net.players_changed.emit()
	await get_tree().create_timer(1.0).timeout
	await _shot("lobby_2_host_crew")
	Net.leave()
	await get_tree().create_timer(1.0).timeout
	await _shot("lobby_3_offline_play")
	Net.join_game("127.0.0.1:%d" % (host_port + 7))  # nobody listens there
	await get_tree().create_timer(1.0).timeout
	await _shot("lobby_4_connecting")
	await get_tree().create_timer(11.0).timeout
	await _shot("lobby_5_join_failed")
	print("DONE %d shots" % shots)
	get_tree().quit()


func _clear_old() -> void:
	var dir := DirAccess.open(out)
	if dir == null:
		return
	for f in dir.get_files():
		if f.begins_with("lobby_") and f.ends_with(".png"):
			dir.remove(f)


func _shot(n: String) -> void:
	await get_tree().create_timer(0.3).timeout
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png("%s/%s.png" % [out, n])
	shots += 1
	print("saved ", n)
