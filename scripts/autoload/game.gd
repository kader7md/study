extends Node
## Global game state (autoload "Game").
## Host-authoritative design: in multiplayer (M1) only the host changes this state and syncs it to clients.

signal inventory_changed
signal message(text: String)
signal banner(text: String)
signal station_reached(index: int)
signal chapter_completed
signal crew_lost
signal wind_changed(active: bool)
signal ui_changed(open: bool)
## The current goal for the crew ("Reach station 2", "Gate locked: find the key"...), shown by the HUD.
signal objective_changed(text: String)
## Station 5 reached: the run is over. `run_stats` is a copy of `stats`.
signal run_finished(run_stats: Dictionary)

## Checkpoint stations after the departure station (index 0). Station 5 is the last one (the port).
const STATION_COUNT := 5
## Solo and hosted runs keep separate saves, so an online session never overwrites the solo run (and back).
const SAVE_PATH := "user://checkpoint_solo.json"
const HOST_SAVE_PATH := "user://checkpoint_host.json"
## Saves from before the split (read as the solo save when there is no solo save yet).
const LEGACY_SAVE_PATH := "user://checkpoint.json"
const MENU_SCENE := "res://scenes/menu/MainMenu.tscn"
const MAIN_SCENE := "res://scenes/main/Main.tscn"

## Balance (see the balance table in docs/GDD.md). One gap piece on solid ground costs about
## 4 wood (planks), 4 scrap (2 rails) and 8 nails (2 per plank; the fishplate bolts come with the rails).
const START_INVENTORY := {"coal": 12, "wood": 10, "scrap": 10, "gold": 15, "nails": 30, "wheel": 1, "engine_oil": 1, "come_along": 1}

## Station shop. "gives" is added to the crew inventory. Wood and scrap are the softlock fallback.
const SHOP := {
	"nails": {"label": "Nails x10", "price": 4, "gives": {"nails": 10}},
	"wood": {"label": "Planks (wood x5)", "price": 3, "gives": {"wood": 5}},
	"scrap": {"label": "Scrap metal x5", "price": 3, "gives": {"scrap": 5}},
	"coal": {"label": "Coal x5", "price": 2, "gives": {"coal": 5}},
	"wheel": {"label": "Train wheel", "price": 8, "gives": {"wheel": 1}},
	"engine_oil": {"label": "Engine oil (repairs the engine)", "price": 6, "gives": {"engine_oil": 1}},
	"nail_gun": {"label": "Nail gun (faster rail repair, joins planks over water)", "price": 15, "gives": {"nail_gun": 1}},
	"medkit": {"label": "Medkit (saves you when you go down, or [E] revives a downed crewmate)", "price": 7, "gives": {"medkit": 1}},
	"come_along": {"label": "Come-along (hand winch: pulls a tipped train back up)", "price": 10, "gives": {"come_along": 1}},
}
## Health a player gets back when revived (medkit, or the crew reaching a station).
const REVIVE_HEALTH := 60.0

## Run statistics shown on the Chapter 1 end screen (and saved in the checkpoint).
const STAT_KEYS := ["time", "distance", "repairs", "panels", "wheels_lost", "gates", "gold_found"]

const INPUTS := {
	"move_forward": [KEY_W], "move_back": [KEY_S], "move_left": [KEY_A], "move_right": [KEY_D],
	"jump": [KEY_SPACE], "sprint": [KEY_SHIFT], "interact": [KEY_E], "interact_alt": [KEY_Q],
	"tool_1": [KEY_1], "tool_2": [KEY_2], "tool_3": [KEY_3], "tool_4": [KEY_4], "tool_5": [KEY_5], "drop": [KEY_G],
	"sabotage_menu": [KEY_TAB],
	"sabotage_1": [KEY_1], "sabotage_2": [KEY_2], "sabotage_3": [KEY_3], "sabotage_4": [KEY_4],
	"toggle_role": [KEY_F2], "toggle_world_sabotage": [KEY_F3],
	"restart_checkpoint": [KEY_F5], "new_game": [KEY_F6], "toggle_help": [KEY_F1],
}

## Shared crew inventory (prototype: pickups go straight in; a carry system comes later).
var inventory: Dictionary = {}
## Next checkpoint station the train must stop at.
var next_station := 1
## Last saved checkpoint ({} = new game).
var checkpoint: Dictionary = {}
## This peer's role: "crew" or "impostor" ([Tab] menu, keys 1-4). NET: set per peer by Net at the start of a run
## (only the impostor's own peer is told); offline, F2 toggles it for testing.
var role := "crew"
var sabotage_menu_open := false
var world_sabotage := true
var wind_active := false:
	set(value):
		if wind_active != value:
			wind_active = value
			wind_changed.emit(value)
## Modal windows that are open right now (shop, pause menu, end screen...): id -> true. While any is open the mouse
## is free. Use open_ui(id) / close_ui(id), so closing one window never releases another's lock.
var _ui_windows: Dictionary = {}
## True while any modal window is open. Setting it false closes every lock (scene changes, resets); setting it true
## opens an anonymous one (prefer open_ui).
var ui_open: bool:
	get:
		return not _ui_windows.is_empty()
	set(value):
		if value:
			open_ui(&"_other")
		elif not _ui_windows.is_empty():
			_ui_windows.clear()
			ui_changed.emit(false)
## Which save slot this run writes: "solo" (offline) or "host" (an online run, saved on the host).
var save_slot := "solo"

## Run statistics (see STAT_KEYS). Time runs from leaving station 0 and stops while the game is paused.
var stats: Dictionary = {}
## True between leaving the departure station and reaching the last station.
var run_timing := false
var run_complete := false
## Segments whose locked gate has been opened (gate state for the checkpoint).
var opened_gates: Array[int] = []
## Developer keys (F2 role, F3 world sabotage, F5 checkpoint, F6 new game): only in debug builds, or when
## Settings > developer > debug_keys is on. They only work inside a run (Main), and online only on the host.
var debug_keys := OS.is_debug_build()
var _run_gen := 0           # bumped by new_game / return_to_menu: stale crew-wipe timers do nothing
var objective := "":
	set(value):
		if objective != value:
			objective = value
			objective_changed.emit(value)

## Scene references, set by Main.
var track: Track
var train: Train
var sabotage: SabotageManager
var terrain: Terrain


func _ready() -> void:
	_setup_input()
	new_game(false)


## A modal window opens: the mouse is freed until every open window has closed again.
func open_ui(id: StringName) -> void:
	var was := ui_open
	_ui_windows[id] = true
	if not was:
		ui_changed.emit(true)


func close_ui(id: StringName) -> void:
	if not _ui_windows.has(id):
		return
	_ui_windows.erase(id)
	if _ui_windows.is_empty():
		ui_changed.emit(false)


func is_ui_open(id: StringName) -> bool:
	return _ui_windows.has(id)


func _setup_input() -> void:
	for action: String in INPUTS:
		if InputMap.has_action(action):
			continue
		InputMap.add_action(action)
		for key: Key in INPUTS[action]:
			var ev := InputEventKey.new()
			ev.physical_keycode = key
			InputMap.action_add_event(action, ev)
	for pair: Array in [["attack", MOUSE_BUTTON_LEFT], ["cancel", MOUSE_BUTTON_RIGHT]]:
		if not InputMap.has_action(pair[0]):
			InputMap.add_action(pair[0])
			var mb := InputEventMouseButton.new()
			mb.button_index = pair[1]
			InputMap.action_add_event(pair[0], mb)


func _process(delta: float) -> void:
	if run_timing and not run_complete:
		stats.time = float(stats.get("time", 0.0)) + delta


func debug_keys_enabled() -> bool:
	return debug_keys or bool(Settings.get_value("developer", "debug_keys", false))


func _unhandled_input(event: InputEvent) -> void:
	# NET: debug keys only offline or on the host (F2 offline only: online the roles come from Net),
	# only inside a run, and only in debug builds (or with the developer setting on)
	if not is_host() or not is_instance_valid(track) or not track.is_inside_tree() or not debug_keys_enabled():
		return
	if event.is_action_pressed("restart_checkpoint"):
		restart_from_checkpoint()
	elif event.is_action_pressed("new_game"):
		new_game(true)
	elif event.is_action_pressed("toggle_role") and not _net_online():
		role = "impostor" if role == "crew" else "crew"
		sabotage_menu_open = false
		say("Debug role: %s%s" % [role.to_upper(), " ([Tab] = sabotage menu)" if role == "impostor" else ""])
	elif event.is_action_pressed("toggle_world_sabotage"):
		world_sabotage = not world_sabotage
		say("World sabotage: %s" % ("ON" if world_sabotage else "OFF"))


# --- NET ---------------------------------------------------------------------

## NET: true offline and on the host: only the host changes game state (clients get it from Net / WorldSync).
func is_host() -> bool:
	return Net.is_host()


func _net_online() -> bool:
	return Net.is_online()


## NET: reloads the world: online the host reloads every peer, a client never does it on its own.
func _reload_world() -> void:
	if _net_online():
		if is_host():
			Net.reload_world.call_deferred()
		return
	get_tree().reload_current_scene.call_deferred()


# --- Inventory -------------------------------------------------------------

func count(item: String) -> int:
	return inventory.get(item, 0)


func has(item: String, amount := 1) -> bool:
	return count(item) >= amount


func add(item: String, amount := 1) -> void:
	inventory[item] = count(item) + amount
	inventory_changed.emit()


## Takes `amount` of `item` if available. Returns false (and takes nothing) otherwise.
func take(item: String, amount := 1) -> bool:
	if not has(item, amount):
		return false
	inventory[item] = count(item) - amount
	inventory_changed.emit()
	return true


## Takes several items at once, all or nothing. cost = {"wood": 2, "nails": 2}
func pay(cost: Dictionary) -> bool:
	for item: String in cost:
		if not has(item, cost[item]):
			return false
	for item: String in cost:
		inventory[item] = count(item) - cost[item]
	inventory_changed.emit()
	return true


static func cost_text(cost: Dictionary) -> String:
	var parts: PackedStringArray = []
	for item: String in cost:
		parts.append("%d %s" % [cost[item], item.replace("_", " ")])
	return ", ".join(parts)


## Host / offline: buys item_id with the crew's gold (true when bought). On a client it only sends the request and
## returns null: the result (inventory, message) comes back from the host.
func buy(item_id: String) -> Variant:
	if not is_host():
		Net.request(self, &"buy", [item_id])  # NET: the host's inventory pays
		return null
	if not SHOP.has(item_id):
		return false
	var entry: Dictionary = SHOP[item_id]
	if not take("gold", entry.price):
		say("Not enough gold for %s (%d gold)" % [entry.label, entry.price])
		return false
	for item: String in entry.gives:
		add(item, entry.gives[item])
	say("Bought %s" % entry.label)
	return true


# --- Run stats ---------------------------------------------------------------

func add_stat(key: String, amount: float = 1.0) -> void:
	stats[key] = float(stats.get(key, 0.0)) + amount


func stat(key: String) -> float:
	return float(stats.get(key, 0.0))


static func empty_stats() -> Dictionary:
	var d := {}
	for k: String in STAT_KEYS:
		d[k] = 0.0
	return d


## The train left a station: the run clock starts (or resumes after a checkpoint restart).
func on_train_left_station(_index: int) -> void:
	if not run_complete:
		run_timing = true


func on_gate_opened(segment: int) -> void:
	if not segment in opened_gates:
		opened_gates.append(segment)
		add_stat("gates")


# --- Messages --------------------------------------------------------------

func say(text: String) -> void:
	print("[game] ", text)
	# NET: on the host, feedback to a client's request goes to that client only
	if Net.route_message(text):
		return
	message.emit(text)


func show_banner(text: String) -> void:
	print("[banner] ", text)
	Net.route_banner(text)  # NET: the host's banners show for everyone
	banner.emit(text)


# --- Stations, checkpoints, game over --------------------------------------

## Called by the train when it comes to a stop inside a station.
## A station further on than next_station counts too (the train rolled through the one before without stopping).
func on_train_stopped_at_station(index: int) -> void:
	if index < next_station:
		return
	next_station = index + 1
	revive_all()
	if index >= STATION_COUNT:
		run_timing = false
		run_complete = true
	save_checkpoint(index)
	station_reached.emit(index)
	if index >= STATION_COUNT:
		show_banner("FINAL STATION REACHED!\nThe helicopter landed at the port… (Chapter 2: the sea)")
		objective = "Chapter 1 complete!"
		chapter_completed.emit()
		run_finished.emit(stats.duplicate())
	else:
		show_banner("Station %d / %d reached!\nCheckpoint saved. Repair, shop, rest." % [index, STATION_COUNT])


func save_checkpoint(station_index: int) -> void:
	checkpoint = {
		"station": station_index,
		"inventory": inventory.duplicate(),
		"train": train.save_state() if train else {},
		"stats": stats.duplicate(),
		"gates": opened_gates.duplicate(),
		"complete": run_complete,
	}
	if not is_host():
		return  # NET: only the host keeps the run's save
	var f := FileAccess.open(save_path(save_slot), FileAccess.WRITE)
	if f:
		f.store_string(JSON.stringify(checkpoint))


## The file of a save slot ("solo" or "host").
static func save_path(slot: String) -> String:
	return HOST_SAVE_PATH if slot == "host" else SAVE_PATH


## The checkpoint saved on disk in `slot` ("solo" or "host"), or {} when there is none or it is unusable.
## Finished runs are not offered for Continue. The solo slot falls back to a save from before the split.
static func read_save(slot := "solo") -> Dictionary:
	var path := save_path(slot)
	if not FileAccess.file_exists(path) and slot == "solo":
		path = LEGACY_SAVE_PATH
	if not FileAccess.file_exists(path):
		return {}
	var text := FileAccess.get_file_as_string(path)
	var data: Variant = JSON.parse_string(text)
	if not data is Dictionary:
		return {}
	var d: Dictionary = data
	if not d.has("station") or not d.has("inventory") or not d.inventory is Dictionary:
		return {}
	if bool(d.get("complete", false)):
		return {}
	# JSON numbers come back as floats: inventory counts and gates are ints
	var inv := {}
	for k: String in d.inventory:
		inv[k] = int(d.inventory[k])
	d.inventory = inv
	d.station = int(d.station)
	var gates: Array = []
	for g: Variant in d.get("gates", []):
		gates.append(int(g))
	d.gates = gates
	return d


## Station number of the save on disk (for "Continue (station N)"), or -1 when there is none.
static func saved_station(slot := "solo") -> int:
	var d := read_save(slot)
	return int(d.station) if not d.is_empty() else -1


## Prepares the run state from the save on disk (Main then builds the world at that station). False if no save.
func continue_from_save(slot := "solo") -> bool:
	var d := read_save(slot)
	if d.is_empty():
		return false
	use_checkpoint(d)
	return true


## Takes `cp` as the current checkpoint and restores the run state from it ({} = a new game).
func use_checkpoint(cp: Dictionary) -> void:
	_run_gen += 1
	wind_active = false
	ui_open = false
	if cp.is_empty():
		new_game(false)
		return
	checkpoint = cp.duplicate(true)
	load_checkpoint_state()


func on_player_downed(_player: Node) -> void:
	check_crew_wipe()


## Host: when every player still in the run is down (someone went down, or the last one standing left the game),
## the crew is lost and the run goes back to the last checkpoint.
func check_crew_wipe() -> void:
	if not is_host() or not is_instance_valid(track) or not track.is_inside_tree():
		return
	var alive := 0
	var total := 0
	for p in get_tree().get_nodes_in_group("player"):
		if p.is_queued_for_deletion():
			continue
		total += 1
		if not p.downed:
			alive += 1
	if total == 0 or alive > 0:
		return
	# TODO(M4/M5): if only the impostor is alive, they choose: kill themself (crew loses) or revive everyone.
	show_banner("THE CREW IS DEAD\nBack to the last checkpoint…")
	crew_lost.emit()
	var gen := _run_gen
	get_tree().create_timer(3.0).timeout.connect(func():
		# not if the run was left (back to the menu) or restarted in the meantime
		if gen == _run_gen and is_instance_valid(track) and track.is_inside_tree():
			restart_from_checkpoint())


## Host: everyone who is down gets back up (the train reached a station). Until revives by carrying (M5).
func revive_all() -> void:
	if not is_host():
		return
	for p in get_tree().get_nodes_in_group("player"):
		if p.downed and p.has_method("revive"):
			p.revive(REVIVE_HEALTH)


func restart_from_checkpoint() -> void:
	_run_gen += 1
	wind_active = false
	ui_open = false
	if checkpoint.is_empty():
		new_game(true)
		return
	load_checkpoint_state()
	_reload_world()


## Restores the run state saved in the checkpoint (inventory, stats, opened gates) without reloading the scene.
func load_checkpoint_state() -> void:
	inventory = checkpoint.inventory.duplicate()
	inventory.erase("key")  # keys belong to their gate; gates behind the checkpoint load open
	next_station = int(checkpoint.station) + 1
	var saved_stats: Dictionary = checkpoint.get("stats", {})
	stats = empty_stats()
	stats.merge(saved_stats, true)
	opened_gates.clear()
	for seg in checkpoint.get("gates", []):
		opened_gates.append(int(seg))
	run_complete = bool(checkpoint.get("complete", false))
	run_timing = false
	objective = ""
	inventory_changed.emit()


func new_game(reload: bool) -> void:
	_run_gen += 1
	checkpoint = {}
	inventory = START_INVENTORY.duplicate()
	next_station = 1
	wind_active = false
	ui_open = false
	stats = empty_stats()
	run_timing = false
	run_complete = false
	opened_gates.clear()
	objective = ""
	inventory_changed.emit()
	if reload:
		_reload_world()


## Leaves the run: closes the network session (online, the host tells everyone it ended the run), then goes to the
## main menu. The checkpoint on disk stays, so the main menu offers Continue.
func return_to_menu() -> void:
	Net.end_session("The host ended the run")
	world_sabotage = true  # the next run decides again (Net.start_run turns it off with an impostor)
	save_slot = "solo"
	get_tree().paused = false
	Engine.time_scale = 1.0
	new_game(false)
	track = null
	train = null
	sabotage = null
	terrain = null
	get_tree().change_scene_to_file.call_deferred(MENU_SCENE)
