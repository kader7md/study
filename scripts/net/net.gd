extends Node
## Multiplayer front door (autoload "Net", registered after Settings). Godot high-level multiplayer, host-authoritative.
##
## - Offline by default: the root multiplayer peer is an OfflineMultiplayerPeer (peer id 1, is_server() true), so solo
##   play and the tests run exactly as before. Solo = hosting with no clients (start_run() then drops the server).
## - host_game(port) / join_game(code_or_ip) open a connection through a NetBackend (EnetBackend now, SteamBackend
##   later). Joining sends the player's name; the host keeps `players` (peer id -> {name, ready, color, host}) and
##   sends it to everyone. The lobby (scenes/net/Lobby.tscn) shows it.
## - start_run() (host) changes every peer to Main. Each peer builds the same world from Main.SEED, then clients
##   report "world ready"; only then does the host show them the players and send the world state (WorldSync).
## - The host simulates everything. Clients send requests with request(target, method, args): the host checks them
##   (allowed method, the sender's own Player, in reach) and runs them with that peer's Player.
## - With 3-5 players the host picks one secret impostor and tells only that peer.
## See docs/NETWORK.md.

signal players_changed
signal connection_failed(reason: String)
## Client: the host accepted us into the lobby.
signal joined
signal run_started
signal disconnected(reason: String)
## This peer's secret role for the run ("crew" or "impostor"), only ever sent to that peer.
signal role_assigned(role: String)
## Host: a client finished loading Main and now gets the world.
signal peer_world_ready(id: int)
signal local_player_spawned(player: Player)
signal upnp_finished(ok: bool, text: String)
## Host: the public (internet) address is known, changed or given up on (see public_ip / public_ip_status).
signal public_ip_changed

const DEFAULT_PORT := 24565
## host_game() with the default port tries this many ports in a row when one is busy.
const PORT_TRIES := 10
const MAX_PLAYERS := 5
## Bumped whenever the RPC layout changes; the host refuses other versions.
const PROTOCOL := 1
const IMPOSTOR_MIN_PLAYERS := 3
const JOIN_TIMEOUT := 10.0
## How far (m) a client's player may be from what it asks the host to use. Generous: latency and big colliders.
const MAX_REACH := 9.0
## How far (m) from a station's centre a client may buy from its shop (the platform is about 60 m long).
const SHOP_REACH := 45.0
const MAIN_SCENE := "res://scenes/main/Main.tscn"
const LOBBY_SCENE := "res://scenes/net/Lobby.tscn"
const MENU_SCENE := "res://scenes/menu/MainMenu.tscn"
## Player colours (jackets, name tags, lobby cards), in join order.
const COLORS: Array[Color] = [
	Color(0.86, 0.42, 0.18), Color(0.16, 0.56, 0.56), Color(0.93, 0.74, 0.18), Color(0.55, 0.36, 0.7), Color(0.36, 0.62, 0.27),
]
## Methods a client may ask the host to run, and the kind of node they may target.
const ALLOWED := {
	"interact": "Interactable", "interact_alt": "Interactable",
	"tool_hit": "Player", "come_along_hit": "Player", "weld_tick": "Player", "put_back": "Player",
	"unplug_welder": "Player", "take_damage": "Player",
	"buy": "Game", "use": "SabotageManager",
}

var backend: NetBackend
## peer id -> {"name": String, "ready": bool, "color": Color, "host": bool}
var players: Dictionary = {}
var port := DEFAULT_PORT
var run_active := false
var run_seed := 0
## Debug: pick an impostor even with fewer than 3 players.
var debug_force_impostor := false
## Overrides the Settings name (tests, command line).
var local_name := ""
var last_error := ""
## The address / code this client joined with (shown in its lobby).
var joined_address := ""
var upnp_status := ""
## Host: the public IP from a successful UPnP mapping.
var external_ip := ""
## Host: this network's public IP as the internet sees it (UPnP query or an HTTPS lookup, or typed by the host).
var public_ip := ""
## "", "Looking up…", or why the lookup failed.
var public_ip_status := ""
## Typed by the host in the lobby (e.g. after forwarding the port by hand): wins over the looked-up address.
var manual_public_ip := ""
## Looks up the public IP when hosting (off in headless runs: tests and servers make no outside requests).
var auto_public_ip := DisplayServer.get_name() != "headless"
const PUBLIC_IP_URL := "https://api.ipify.org"

var _ready_peers := {}          # host: peer id -> true once their Main is loaded
var _run_roster := {}           # host: name -> {"color": Color, "impostor": bool} of everyone who started the run
var _world_cp: Dictionary = {}  # the checkpoint the current world was built from (a rejoining player builds the same)
var _host_world_ready := false
var _impostor := 0              # host only. Never printed or sent to anyone but that peer.
var _actor := 0                 # host: peer whose request is running (0 = the world)
var _kick_reason := ""
var _joining := false
var _join_time := 0.0
var _pending_role := ""
var _main: Node
var _players_root: Node3D
var _spawner: MultiplayerSpawner
var _world_sync: WorldSync
var _overlay: NetOverlay
var _voice: Node
var _threads: Array[Thread] = []
var _upnp_busy := false
var _ip_request: HTTPRequest


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	multiplayer.peer_connected.connect(_on_peer_connected)
	multiplayer.peer_disconnected.connect(_on_peer_disconnected)
	multiplayer.connected_to_server.connect(_on_connected_to_server)
	multiplayer.connection_failed.connect(_on_connection_failed)
	multiplayer.server_disconnected.connect(_on_server_disconnected)
	_overlay = NetOverlay.new()
	_overlay.name = "Overlay"
	add_child(_overlay)
	_voice = Voice.new()
	_voice.name = "Voice"
	add_child(_voice)


func _process(delta: float) -> void:
	if _joining:
		_join_time += delta
		if _join_time > JOIN_TIMEOUT:
			_fail_join("No answer from the host (%s). Check the code, and that the host's port %d (UDP) is open." % [joined_address, port])
	for t in _threads.duplicate():
		if not t.is_alive():
			t.wait_to_finish()
			_threads.erase(t)


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST or what == NOTIFICATION_PREDELETE:
		# Closing the window: tell the others right away instead of letting them time out.
		if backend:
			backend.close()
			backend = null


# --- State ---------------------------------------------------------------------

func is_online() -> bool:
	var peer := multiplayer.multiplayer_peer
	return backend != null and peer != null and not (peer is OfflineMultiplayerPeer) \
		and peer.get_connection_status() == MultiplayerPeer.CONNECTION_CONNECTED


## True offline, and on the host. Only the host changes game state.
func is_host() -> bool:
	return multiplayer.multiplayer_peer == null or multiplayer.is_server()


func is_connecting() -> bool:
	return _joining


func local_id() -> int:
	return multiplayer.get_unique_id()


func backend_name() -> String:
	return backend.backend_name() if backend else "Offline"


## Host: peers that loaded the world and receive world state.
func ready_peers() -> Array[int]:
	var list: Array[int] = []
	for id: int in _ready_peers:
		if players.has(id):
			list.append(id)
	return list


func is_peer_ready(id: int) -> bool:
	return _ready_peers.has(id)


func player_name(id: int) -> String:
	return players[id].name if players.has(id) else "Player"


func player_color(id: int) -> Color:
	return players[id].color if players.has(id) else COLORS[0]


func all_ready() -> bool:
	for id: int in players:
		if not players[id].host and not players[id].ready:
			return false
	return true


func can_start() -> bool:
	return is_host() and (not is_online() or players.size() <= 1 or all_ready())


## The Player node of a peer in the running world (or null).
func player_node(id: int) -> Player:
	if not is_instance_valid(_players_root):
		return null
	return _players_root.get_node_or_null("Player_%d" % id) as Player


func local_player() -> Player:
	return player_node(local_id())


## This player's name: the override, else Settings.player_name, else "Player".
func my_name() -> String:
	var n := local_name
	if n.strip_edges().is_empty():
		var settings := get_node_or_null(^"/root/Settings")
		if settings and "player_name" in settings:
			n = str(settings.get("player_name"))
	return clean_name(n)


## Default player name and the longest name allowed (the same in Settings, the menu and the lobby).
const DEFAULT_NAME := "Player"
const NAME_MAX := 20


static func clean_name(n: String) -> String:
	var s := n.strip_edges().replace("[", "(").replace("]", ")").replace("\n", " ")
	if s.is_empty():
		s = DEFAULT_NAME
	return s.substr(0, NAME_MAX)


func set_local_name(n: String) -> void:
	local_name = clean_name(n)
	if not is_online():
		return
	if is_host():
		if players.has(1):
			players[1].name = _unique_name(local_name, 1)
			_broadcast_players()
	else:
		_rpc_set_name.rpc_id(1, local_name)


# --- Host, join, leave ---------------------------------------------------------------

## Opens a lobby on port `p`. With the default port, a busy port falls back to the next free one
## (DEFAULT_PORT + 1 .. + PORT_TRIES - 1); the invite code carries the port.
func host_game(p := DEFAULT_PORT) -> Error:
	leave()
	var tries := PORT_TRIES if p == DEFAULT_PORT else 1
	var err: Error = FAILED
	for k in tries:
		backend = EnetBackend.new()
		err = backend.host(p + k, MAX_PLAYERS)
		if err == OK:
			p += k
			break
		backend = null
	if err != OK:
		backend = null
		last_error = "Could not host on port %d (%s). Is another game using it?" % [p, error_string(err)]
		connection_failed.emit(last_error)
		return err
	port = p
	multiplayer.multiplayer_peer = backend.get_peer()
	players = {1: _entry(my_name(), 0, true)}
	players[1].ready = true
	last_error = ""
	print("[net] hosting on port %d" % p)
	players_changed.emit()
	if auto_public_ip:
		lookup_public_ip()
	return OK


## Joins by invite code ("ABCDE-12345"), "ip" or "ip:port". Watch `joined` / `connection_failed`.
func join_game(code_or_ip: String) -> Error:
	var info := InviteCode.decode(code_or_ip, DEFAULT_PORT)
	if not info.ok:
		last_error = info.error
		connection_failed.emit(last_error)
		return ERR_INVALID_PARAMETER
	leave()
	backend = EnetBackend.new()
	var err := backend.join(info.ip, info.port)
	if err != OK:
		backend = null
		last_error = "Could not start connecting (%s)" % error_string(err)
		connection_failed.emit(last_error)
		return err
	port = info.port
	joined_address = "%s:%d" % [info.ip, info.port]
	multiplayer.multiplayer_peer = backend.get_peer()
	_joining = true
	_join_time = 0.0
	_kick_reason = ""
	last_error = ""
	print("[net] joining %s" % joined_address)
	return OK


## Closes the connection and goes back to offline (does not change the scene).
func leave() -> void:
	if backend:
		if backend is EnetBackend and (backend as EnetBackend).has_upnp_mapping():
			_run_thread((backend as EnetBackend).close_upnp)
		backend.close()
	backend = null
	multiplayer.multiplayer_peer = OfflineMultiplayerPeer.new()
	players.clear()
	run_active = false
	_ready_peers.clear()
	_host_world_ready = false
	_impostor = 0
	_run_roster.clear()
	_world_cp = {}
	_actor = 0
	_joining = false
	_pending_role = ""
	external_ip = ""
	upnp_status = ""
	public_ip = ""
	public_ip_status = ""
	if is_instance_valid(_ip_request):
		_ip_request.queue_free()
	_ip_request = null
	Game.role = "crew"
	Game.world_sabotage = true  # 1-2 player rule until a run with an impostor says otherwise (GDD 2)
	Game.save_slot = "solo"
	players_changed.emit()


## Leaves and shows the main menu (or the lobby if the menu scene is missing).
func leave_to_menu() -> void:
	leave()
	go_to_menu()


## Host: tells every client why the session ends (`reason` shows on their main menu), then leaves.
## A client just leaves.
func end_session(reason: String) -> void:
	if is_online() and is_host() and players.size() > 1:
		_rpc_rejected.rpc(reason)
		# give the message a moment to go out before the connection closes (nothing else runs meanwhile)
		run_active = false
		var b := backend
		get_tree().create_timer(0.3, true, false, true).timeout.connect(func():
			if backend == b:
				leave())
		return
	leave()


func go_to_menu() -> void:
	get_tree().paused = false
	Game.ui_open = false
	_overlay.hide_wait()
	get_tree().change_scene_to_file(MENU_SCENE if ResourceLoader.exists(MENU_SCENE) else LOBBY_SCENE)


## Host: removes a player from the lobby.
func kick(id: int, reason := "The host removed you from the lobby") -> void:
	if is_host() and id != 1 and players.has(id):
		_reject(id, reason)


func set_ready(on: bool) -> void:
	if not is_online():
		return
	if players.has(local_id()):
		players[local_id()].ready = on
		players_changed.emit()
	if not is_host():
		_rpc_set_ready.rpc_id(1, on)


# --- Invite code, LAN addresses, UPnP --------------------------------------------------

## The code to share: the internet code when the public IP is known, else the same-Wi-Fi code, else "" (no network:
## a loopback code is never offered). A client shares the address it joined with.
func invite_code() -> String:
	if not is_online() and not is_host():
		return ""
	if not is_host():
		var info := InviteCode.decode(joined_address, DEFAULT_PORT)
		return InviteCode.encode(info.ip, info.port) if info.ok else ""
	var net_code := internet_code()
	return net_code if net_code != "" else lan_code()


## Host: the code for friends on the same Wi-Fi / LAN (the PC's LAN address), or "" when there is no network.
func lan_code() -> String:
	var lan := lan_addresses()
	return InviteCode.encode(lan[0], port) if not lan.is_empty() else ""


## Host: the code for friends over the internet (the public IP; it only works once UDP `port` is forwarded to this
## PC, by UPnP or by hand), or "" while the public IP is unknown.
func internet_code() -> String:
	var ip := current_public_ip()
	return InviteCode.encode(ip, port) if ip != "" else ""


## The best known public IP: typed by the host, from UPnP, or looked up.
func current_public_ip() -> String:
	for ip in [manual_public_ip, external_ip, public_ip]:
		if _usable_public(ip):
			return ip
	return ""


static func _usable_public(ip: String) -> bool:
	return ip.is_valid_ip_address() and not ip.contains(":") and not InviteCode.is_lan(ip) \
		and not ip.begins_with("127.") and not ip.begins_with("0.")


## Host: the address typed in the lobby ("" clears it). Returns false when it is not a public IPv4 address.
func set_manual_public_ip(ip: String) -> bool:
	var clean := ip.strip_edges()
	if clean != "" and not _usable_public(clean):
		return false
	manual_public_ip = clean
	public_ip_changed.emit()
	players_changed.emit()
	return true


## Host: finds this network's public IP without opening any port: asks the router (UPnP query, on a thread), and
## if that fails, an HTTPS lookup (api.ipify.org). Watch `public_ip_changed`.
func lookup_public_ip() -> void:
	if not is_host() or backend == null:
		return
	public_ip_status = "Looking up your internet address…"
	public_ip_changed.emit()
	var b := backend
	if b is EnetBackend:
		_run_thread(func():
			var ip := EnetBackend.query_public_ip()
			_on_upnp_ip.call_deferred(ip, b))
	else:
		_http_public_ip()


func _on_upnp_ip(ip: String, b: NetBackend) -> void:
	if backend != b:
		return
	if _usable_public(ip):
		_set_public_ip(ip)
	else:
		_http_public_ip()


func _http_public_ip() -> void:
	if is_instance_valid(_ip_request):
		return
	_ip_request = HTTPRequest.new()
	_ip_request.timeout = 6.0
	add_child(_ip_request)
	_ip_request.request_completed.connect(func(result: int, code: int, _h: PackedStringArray, body: PackedByteArray):
		var ip := body.get_string_from_utf8().strip_edges()
		if is_instance_valid(_ip_request):
			_ip_request.queue_free()
		_ip_request = null
		if result == HTTPRequest.RESULT_SUCCESS and code == 200 and _usable_public(ip):
			_set_public_ip(ip)
		else:
			public_ip_status = "Could not find your internet address (offline?). Type it below if you know it."
			public_ip_changed.emit()
			players_changed.emit())
	if _ip_request.request(PUBLIC_IP_URL) != OK:
		_ip_request.queue_free()
		_ip_request = null
		public_ip_status = "Could not find your internet address. Type it below if you know it."
		public_ip_changed.emit()


func _set_public_ip(ip: String) -> void:
	if not is_host() or backend == null:
		return
	public_ip = ip
	public_ip_status = ""
	print("[net] public address found")
	public_ip_changed.emit()
	players_changed.emit()


func lan_addresses() -> PackedStringArray:
	return EnetBackend.lan_addresses()


static func encode_invite(ip: String, invite_port: int) -> String:
	return InviteCode.encode(ip, invite_port)


static func decode_invite(code: String) -> Dictionary:
	return InviteCode.decode(code, DEFAULT_PORT)


## Host: asks the router to forward the port (UPnP) on a thread. Watch `upnp_finished`.
func open_upnp() -> void:
	if not is_host() or not backend or not backend.supports_upnp() or _upnp_busy:
		return
	_upnp_busy = true
	upnp_status = "Asking the router to open port %d…" % port
	var b: EnetBackend = backend
	var p := port
	_run_thread(func():
		var result := b.open_upnp(p)
		_upnp_done.call_deferred(result))


func _upnp_done(result: Dictionary) -> void:
	_upnp_busy = false
	upnp_status = result.text
	if result.ok and backend:
		external_ip = result.external_ip
	upnp_finished.emit(result.ok, upnp_status)
	players_changed.emit()


func _run_thread(fn: Callable) -> void:
	var t := Thread.new()
	t.start(fn)
	_threads.append(t)


# --- Starting the run --------------------------------------------------------------------

## Host: everyone goes to Main. With only the host, the server closes and the run is plain offline solo.
## `from_save`: the run continues from the checkpoint on disk (the host's save; clients get it with the start).
func start_run(from_save := false) -> void:
	if not is_host():
		return
	if not is_online() or players.size() <= 1:
		start_solo(from_save)
		return
	if not all_ready():
		return
	run_seed = _main_seed()
	_assign_roles()
	_run_roster.clear()
	for id: int in players:
		_run_roster[str(players[id].name)] = {"color": players[id].color, "impostor": id == _impostor}
	Game.world_sabotage = _impostor == 0  # 1-2 players: the world sabotages (GDD 2)
	Game.save_slot = "host"
	var cp: Dictionary = Game.read_save("host") if from_save else {}
	_rpc_start_run.rpc(run_seed, cp)
	_send_roles()


## Offline solo run: exactly the old single-player game. `from_save`: continue from the checkpoint on disk.
func start_solo(from_save := false) -> void:
	if backend:
		leave()
	Game.save_slot = "solo"
	Game.world_sabotage = true  # solo: the world sabotages (GDD 2), whatever the last online run said
	if not (from_save and Game.continue_from_save("solo")):
		Game.new_game(false)
	Game.role = "crew"
	run_started.emit()
	get_tree().paused = false
	get_tree().change_scene_to_file(MAIN_SCENE)


## Host: reloads the world on every peer (back to the checkpoint, or a new game). Called by Game when online.
func reload_world() -> void:
	if not (is_host() and is_online() and run_active):
		return
	# Take the players out first, so no despawn reaches a client after it already left the old world.
	_clear_players()
	await get_tree().create_timer(0.25).timeout
	if is_online() and run_active:
		_rpc_reload.rpc(Game.checkpoint, Game.inventory, Game.next_station, Game.stats)


func _clear_players() -> void:
	if not is_instance_valid(_players_root):
		return
	_forget_local_player()
	for p in _players_root.get_children():
		if p is Player:
			p.queue_free()


## True once `peer` has loaded the world (the host marks it in `players`); clients only send their movement to those.
func in_world(peer: int) -> bool:
	return peer == 1 or (players.has(peer) and bool(players[peer].get("world", false)))


func _mark_world(id: int, on: bool) -> void:
	if players.has(id) and bool(players[id].get("world", false)) != on:
		players[id].world = on
		_broadcast_players()


func _main_seed() -> int:
	var script: Script = load("res://scripts/world/main.gd")
	return int(script.get_script_constant_map().get("SEED", 0))


func _assign_roles() -> void:
	_impostor = 0
	var ids: Array = players.keys()
	if ids.size() >= IMPOSTOR_MIN_PLAYERS or debug_force_impostor:
		var rng := RandomNumberGenerator.new()
		rng.randomize()
		_impostor = ids[rng.randi() % ids.size()]


## Each peer only ever learns its own role.
func _send_roles() -> void:
	var with_impostor := _impostor != 0
	for id: int in players:
		var role := "impostor" if id == _impostor else "crew"
		if id == local_id():
			_rpc_role(role, with_impostor)
		else:
			_rpc_role.rpc_id(id, role, with_impostor)


## Called by Main._ready (through main.gd's NET hook): creates Main/Players with its MultiplayerSpawner and, online,
## the WorldSync node. Returns the local Player right away offline and on the host; a client gets its Player a moment
## later from the host (main.player and the HUD are set then, see _set_local_player).
func spawn_players(main: Node, spawn_xform: Transform3D) -> Player:
	_main = main
	_players_root = Node3D.new()
	_players_root.name = "Players"
	_players_root.set_meta("spawn_xform", spawn_xform)
	main.add_child(_players_root)
	_spawner = MultiplayerSpawner.new()
	_spawner.name = "Spawner"
	_players_root.add_child(_spawner)
	_spawner.spawn_path = _spawner.get_path_to(_players_root)
	_spawner.spawn_function = _spawn_player
	_spawner.spawned.connect(_on_spawned)
	_spawner.despawned.connect(_on_despawned)
	if not is_online():
		var solo: Player = _spawn_player(_spawn_data(local_id(), 0, my_name()))
		_players_root.add_child(solo)
		return solo
	_world_sync = WorldSync.new()
	_world_sync.name = "WorldSync"
	main.add_child(_world_sync)
	_world_sync.setup(main)
	if is_host():
		_host_world_ready = true
		_mark_world(1, true)
		var ids: Array = players.keys()
		ids.sort()
		for i in ids.size():
			_spawner.spawn(_spawn_data(ids[i], i, player_name(ids[i])))
		for id: int in _ready_peers.keys():
			_on_peer_world_ready(id)
		var me := local_player()
		_set_local_player.call_deferred(me)
		return me
	_overlay.show_wait("Waiting for the host…")
	_send_world_ready.call_deferred()
	return null


func _spawn_data(id: int, index: int, n: String) -> Dictionary:
	var x: Transform3D = _players_root.get_meta("spawn_xform")
	x.origin += x.basis.z * 1.4 * index  # one behind the other on the platform
	return {"id": id, "name": n, "color": player_color(id) if players.has(id) else COLORS[0], "xform": x}


func _spawn_player(data: Variant) -> Node:
	var d: Dictionary = data
	var id: int = d["id"]
	var p := Player.new()
	p.name = "Player_%d" % id
	p.peer_id = id
	p.display_name = d["name"]
	p.color = d["color"]
	p.transform = d["xform"]
	p.net_pos = p.transform.origin
	p.net_yaw = p.rotation.y
	p.set_multiplayer_authority(id)
	PlayerSync.attach(p, id)
	return p


func _on_spawned(node: Node) -> void:
	if node is Player and (node as Player).peer_id == local_id():
		_set_local_player(node)


func _on_despawned(node: Node) -> void:
	if node is Player and (node as Player).peer_id == local_id():
		_forget_local_player()


## Main and the HUD let go of our player (it is about to be freed).
func _forget_local_player() -> void:
	if not is_instance_valid(_main):
		return
	_main.set("player", null)
	var hud: Node = _main.get("hud")
	if hud:
		hud.set("player", null)


func _set_local_player(p: Player) -> void:
	if not is_instance_valid(p) or not is_instance_valid(_main):
		return
	_main.set("player", p)
	var hud: Node = _main.get("hud")
	if hud:
		hud.set("player", p)
		_add_crew_widget(hud)
	_overlay.hide_wait()
	local_player_spawned.emit(p)
	if _pending_role != "":
		_show_role_banner.call_deferred(_pending_role)


func _add_crew_widget(hud: Node) -> void:
	if not is_online() or hud.has_node("CrewList"):
		return
	var w := CrewList.new()
	w.name = "CrewList"
	(hud as HUD).add_corner_widget(w)


func _show_role_banner(role: String) -> void:
	_pending_role = ""
	await get_tree().create_timer(1.5).timeout
	var text := "YOU ARE THE IMPOSTOR\nSecretly sabotage the crew: [Tab] opens your sabotage menu. Nobody else knows."
	if role != "impostor":
		text = "YOU ARE CREW\nOne of your friends is a secret impostor. Trust no one."
	print("[net] your role: ", role)
	Game.banner.emit(text)  # local only, never through the host


func _on_peer_world_ready(id: int) -> void:
	if not is_instance_valid(_players_root):
		return
	_mark_world(id, true)
	if player_node(id) == null and run_active and players.has(id):
		_spawn_rejoined(id)
	for p: Node in _players_root.get_children():
		if p is Player:
			PlayerSync.show_to(p, id)
	if is_instance_valid(_world_sync):
		_world_sync.send_full_state(id)
	peer_world_ready.emit(id)


## Host: a player who rejoined mid-run appears on the train's middle car (every peer that is in the world sees them).
func _spawn_rejoined(id: int) -> void:
	var x: Transform3D = _players_root.get_meta("spawn_xform")
	var train := Game.train
	if train and train.cars.size() > 1:
		var car := train.cars[1]
		x = Transform3D(car.global_basis.orthonormalized(), car.global_position + Vector3.UP * (Train.FLOOR_HEIGHT + 0.3))
	_spawner.spawn({"id": id, "name": player_name(id), "color": player_color(id), "xform": x})
	var p := player_node(id)
	if p:
		for other: int in ready_peers():
			if other != id:
				PlayerSync.show_to(p, other)


func _send_world_ready() -> void:
	if is_online():
		_rpc_world_ready.rpc_id(1)


# --- Requests (client -> host) ---------------------------------------------------------

## Runs target.method(args) where the game state lives: right here offline and on the host (returns the result),
## or as a request to the host on a client (returns null; the result comes back through world sync).
## Node arguments are sent as paths. The host runs the call with the sender's own Player.
func request(target: Object, method: StringName, args: Array = []) -> Variant:
	if not is_online():
		return target.callv(method, args)
	if is_host():
		var prev := _actor
		_actor = 0 if target is SabotageManager else local_id()
		var result: Variant = target.callv(method, args)
		_actor = prev
		_after_action(target, args)
		return result
	var node := target as Node
	if node == null or not node.is_inside_tree() or not run_active:
		return null
	var me := local_player()
	var aim := me.aim_point() if me else Vector3.INF
	_rpc_request.rpc_id(1, str(node.get_path()), String(method), _encode(args), aim)
	return null


## Runs fn(args) on behalf of `peer`: on the host, Game.say messages it makes go to that player only.
func run_as(peer: int, fn: Callable, args: Array = []) -> Variant:
	if not is_online() or not is_host():
		return fn.callv(args)
	var prev := _actor
	_actor = peer
	var result: Variant = fn.callv(args)
	_actor = prev
	return result


## The remote peer whose request the host is running right now, or 0.
func remote_actor() -> int:
	return _actor if _actor != 0 and _actor != local_id() else 0


func _encode(args: Array) -> Array:
	var out := []
	for a: Variant in args:
		if a is Node:
			out.append({"$": str((a as Node).get_path())})
		else:
			out.append(a)
	return out


@rpc("any_peer", "call_remote", "reliable")
func _rpc_request(path: String, method: String, args: Array, aim: Vector3) -> void:
	var sender := multiplayer.get_remote_sender_id()
	if not is_host() or not run_active or not _ready_peers.has(sender) or not ALLOWED.has(method):
		return
	var target := get_node_or_null(NodePath(path))
	var player := player_node(sender)
	if target == null or player == null:
		return
	var kind: String = ALLOWED[method]
	match kind:
		"Interactable":
			if not target is Interactable:
				return
		"Player":
			if target != player:
				return
		"Game":
			if target != Game:
				return
		"SabotageManager":
			if not target is SabotageManager or sender != _impostor:
				return
	var decoded := []
	for a: Variant in args:
		if a is Dictionary and (a as Dictionary).has("$"):
			var n := get_node_or_null(NodePath(str(a["$"])))
			if n is Player and n != player:
				return  # nobody acts for another player
			decoded.append(n)
		else:
			decoded.append(a)
	if player.downed and method != "take_damage":
		return
	if not _in_reach(player, target, decoded):
		return
	if method == "buy" and not _near_shop(player):
		return
	if not target.has_method(method):
		return
	player.net_aim = aim
	_actor = 0 if target is SabotageManager else sender
	target.callv(method, decoded)
	_actor = 0
	player.net_aim = Vector3.INF
	_after_action(target, decoded)


func _in_reach(player: Player, target: Node, args: Array) -> bool:
	var subject: Node = target
	if target == player:
		subject = null
		for a: Variant in args:
			if a is Node3D:
				subject = a
				break
	if subject is Node3D:
		return player.global_position.distance_to((subject as Node3D).global_position) <= MAX_REACH
	return true


## Buying needs the train stopped at a station and the buyer on that station's platform (near its shop).
func _near_shop(player: Player) -> bool:
	var train := Game.train
	if train == null or train.current_station < 0 or not is_instance_valid(_main):
		return false
	var station := _main.get_node_or_null("Station%d" % train.current_station) as Node3D
	return station != null and player.global_position.distance_to(station.global_position) <= SHOP_REACH


func _after_action(target: Object, args: Array) -> void:
	if is_instance_valid(_world_sync):
		_world_sync.after_action(target, args)


# --- Messages (host -> the right players) -------------------------------------------------

## Called by Game.say on every peer. On the host, feedback to a remote player's request goes only to that player
## (returns true: not shown here); world events go to everyone (returns false: shown here too).
func route_message(text: String) -> bool:
	if not is_online() or not is_host() or not run_active:
		return false
	if _actor != 0 and _actor != local_id():
		if players.has(_actor) and _ready_peers.has(_actor):
			_rpc_message.rpc_id(_actor, text)
		return true
	if _actor == 0:
		for id in ready_peers():
			_rpc_message.rpc_id(id, text)
	return false


## Called by Game.show_banner: the host's banners go to everyone.
func route_banner(text: String) -> void:
	if not is_online() or not is_host() or not run_active:
		return
	for id in ready_peers():
		_rpc_banner.rpc_id(id, text)


## Host: a remote player pressed [E] on a station shop: open the shop on their screen.
func open_shop_for(id: int, station_index: int) -> void:
	_rpc_open_shop.rpc_id(id, station_index)


@rpc("authority", "call_remote", "reliable")
func _rpc_message(text: String) -> void:
	Game.say(text)


@rpc("authority", "call_remote", "reliable")
func _rpc_banner(text: String) -> void:
	Game.show_banner(text)


@rpc("authority", "call_remote", "reliable")
func _rpc_open_shop(station_index: int) -> void:
	if not is_instance_valid(_main):
		return
	var hud: Node = _main.get("hud")
	var station := _main.get_node_or_null("Station%d" % station_index)
	if hud and station and hud.has_method("open_shop"):
		hud.call("open_shop", station)


# --- Connection events --------------------------------------------------------------------

func _on_peer_connected(id: int) -> void:
	# a client says hello with _rpc_register once it is connected
	if backend and (is_host() or id == 1):
		backend.on_peer_connected(id)


func _on_peer_disconnected(id: int) -> void:
	if not is_host() or not players.has(id):
		return
	var who: String = players[id].name
	players.erase(id)
	_ready_peers.erase(id)
	if id == _impostor:
		_impostor = 0
	_broadcast_players()
	print("[net] %s left" % who)
	if run_active:
		var p := player_node(id)
		if p:
			p.queue_free()
		_actor = 0
		Game.say("%s left the game" % who)
		# without its impostor (or with too few players for one) the run falls back to world sabotage (GDD 2)
		if _impostor == 0 or players.size() < IMPOSTOR_MIN_PLAYERS:
			Game.world_sabotage = true
		# the last player standing may have left while everyone else is down
		Game.check_crew_wipe.call_deferred()


func _on_connected_to_server() -> void:
	if backend:
		backend.on_peer_connected(1)
	_rpc_register.rpc_id(1, PROTOCOL, my_name())


func _on_connection_failed() -> void:
	_fail_join("Could not reach the host at %s" % joined_address)


func _on_server_disconnected() -> void:
	var reason := _kick_reason if _kick_reason != "" else "Host left the game"
	_drop_to_menu.call_deferred(reason)


func _fail_join(reason: String) -> void:
	print("[net] ", reason)
	leave()
	last_error = reason
	connection_failed.emit(reason)


func _drop_to_menu(reason: String) -> void:
	print("[net] disconnected: ", reason)
	leave()
	last_error = reason
	Game.new_game(false)
	disconnected.emit(reason)
	_overlay.notice(reason)
	go_to_menu()


# --- Lobby RPCs ----------------------------------------------------------------------------

func _entry(n: String, color_index: int, host: bool) -> Dictionary:
	return {"name": n, "ready": false, "color": COLORS[color_index % COLORS.size()], "host": host}


func _free_color() -> int:
	for i in COLORS.size():
		var used := false
		for id: int in players:
			if players[id].color == COLORS[i]:
				used = true
		if not used:
			return i
	return players.size()


func _unique_name(n: String, id: int) -> String:
	var name_out := n
	var k := 2
	var taken := true
	while taken:
		taken = false
		for other: int in players:
			if other != id and players[other].name == name_out:
				taken = true
		if taken:
			name_out = "%s %d" % [n.substr(0, NAME_MAX - 3), k]
			k += 1
	return name_out


func _broadcast_players() -> void:
	if is_online():
		_rpc_players.rpc(players)
	players_changed.emit()


func _reject(id: int, reason: String) -> void:
	_rpc_rejected.rpc_id(id, reason)
	get_tree().create_timer(0.4).timeout.connect(func():
		if multiplayer.multiplayer_peer and multiplayer.is_server() and id in multiplayer.get_peers():
			multiplayer.multiplayer_peer.disconnect_peer(id))


@rpc("any_peer", "call_remote", "reliable")
func _rpc_register(protocol: int, n: String) -> void:
	if not is_host():
		return
	var id := multiplayer.get_remote_sender_id()
	if protocol != PROTOCOL:
		_reject(id, "The host runs a different version of the game")
	elif run_active and _can_rejoin(clean_name(n)):
		_rejoin(id, clean_name(n))
	elif run_active:
		_reject(id, "The run has already started. Only players who were in it can rejoin (with the same name)")
	elif players.size() >= MAX_PLAYERS:
		_reject(id, "The lobby is full (%d/%d)" % [MAX_PLAYERS, MAX_PLAYERS])
	else:
		players[id] = _entry(_unique_name(clean_name(n), id), _free_color(), false)
		print("[net] %s joined" % players[id].name)
		_broadcast_players()


## Host: `n` started this run, is not in it now, and there is room.
func _can_rejoin(n: String) -> bool:
	if not _run_roster.has(n) or players.size() >= MAX_PLAYERS:
		return false
	for other: int in players:
		if players[other].name == n:
			return false
	return true


## Host: a player who dropped out comes back: they load the world the host built (same seed and checkpoint), get
## the full world state when ready (WorldSync), and a new Player at the train (see _on_peer_world_ready).
func _rejoin(id: int, n: String) -> void:
	var info: Dictionary = _run_roster[n]
	players[id] = {"name": n, "ready": true, "color": info.color, "host": false, "world": false}
	if bool(info.impostor) and _impostor == 0:
		_impostor = id
		Game.world_sabotage = false
	print("[net] %s rejoined the run" % n)
	_broadcast_players()
	Game.say("%s is back" % n)
	_rpc_start_run.rpc_id(id, run_seed, _world_cp)
	_rpc_role.rpc_id(id, "impostor" if id == _impostor else "crew", _impostor != 0)


@rpc("any_peer", "call_remote", "reliable")
func _rpc_set_ready(on: bool) -> void:
	var id := multiplayer.get_remote_sender_id()
	if is_host() and players.has(id) and not run_active:
		players[id].ready = on
		_broadcast_players()


@rpc("any_peer", "call_remote", "reliable")
func _rpc_set_name(n: String) -> void:
	var id := multiplayer.get_remote_sender_id()
	if is_host() and players.has(id):
		players[id].name = _unique_name(clean_name(n), id)
		_broadcast_players()


@rpc("authority", "call_remote", "reliable")
func _rpc_players(list: Dictionary) -> void:
	var first := not players.has(local_id())
	players = list
	if first and players.has(local_id()):
		_joining = false
		print("[net] joined the lobby (%d players)" % players.size())
		joined.emit()
	# who has loaded the world may have changed: our movement goes only to them
	var me := local_player()
	if me and me.has_node("InputSync"):
		(me.get_node("InputSync") as MultiplayerSynchronizer).update_visibility()
	players_changed.emit()


@rpc("authority", "call_remote", "reliable")
func _rpc_rejected(reason: String) -> void:
	_kick_reason = reason
	if _joining:
		_joining = false
		_fail_join.call_deferred(reason)
	elif run_active:
		# the host ended the run: leave right away (no more packets for a world the host already closed)
		run_active = false
		_drop_to_menu.call_deferred(reason)


@rpc("authority", "call_local", "reliable")
func _rpc_start_run(new_seed: int, cp: Dictionary = {}) -> void:
	run_active = true
	run_seed = new_seed
	_host_world_ready = false
	if is_host():
		_ready_peers.clear()
		_reset_world_marks()
	_pending_role = ""
	_world_cp = cp.duplicate(true)
	Game.use_checkpoint(cp)  # {} = a new game
	Game.role = "crew"
	get_tree().paused = false
	print("[net] run started (%d players)" % players.size())
	run_started.emit()
	_overlay.show_wait("Loading the world…")
	get_tree().change_scene_to_file(MAIN_SCENE)


@rpc("authority", "call_remote", "reliable")
func _rpc_role(role: String, with_impostor: bool) -> void:
	Game.role = role
	Game.sabotage_menu_open = false
	_pending_role = role if with_impostor else ""
	role_assigned.emit(role)


@rpc("authority", "call_local", "reliable")
func _rpc_reload(checkpoint: Dictionary, inventory: Dictionary, next_station: int, stats: Dictionary = {}) -> void:
	_world_cp = checkpoint.duplicate(true)
	if not is_host():
		# mirror the host: the checkpoint's run state (opened gates, stats, run_complete) or a fresh game,
		# so gates opened after the checkpoint are locked again here too, with their keys
		Game.use_checkpoint(checkpoint)
		if not stats.is_empty():
			Game.stats = stats.duplicate()
	Game.inventory = inventory.duplicate()
	Game.next_station = next_station
	Game.wind_active = false
	Game.ui_open = false
	Game.inventory_changed.emit()
	_host_world_ready = false
	if is_host():
		_ready_peers.clear()
		_reset_world_marks()
	_overlay.show_wait("Back to the last checkpoint…")
	get_tree().change_scene_to_file(MAIN_SCENE)


func _reset_world_marks() -> void:
	for id: int in players:
		players[id].world = false
	_broadcast_players()


@rpc("any_peer", "call_remote", "reliable")
func _rpc_world_ready() -> void:
	var id := multiplayer.get_remote_sender_id()
	if not is_host() or not players.has(id):
		return
	_ready_peers[id] = true
	if _host_world_ready:
		_on_peer_world_ready(id)
