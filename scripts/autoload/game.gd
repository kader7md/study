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

## Checkpoint stations after the departure station (index 0). Station 5 is the last one (the port).
const STATION_COUNT := 5
const SAVE_PATH := "user://checkpoint.json"

const START_INVENTORY := {"coal": 14, "wood": 10, "scrap": 10, "gold": 15, "nails": 20, "wheel": 1, "engine_oil": 1, "come_along": 1}

## Station shop. "gives" is added to the crew inventory.
const SHOP := {
	"nails": {"label": "Nails x10", "price": 5, "gives": {"nails": 10}},
	"wheel": {"label": "Train wheel", "price": 8, "gives": {"wheel": 1}},
	"engine_oil": {"label": "Engine oil (repairs the engine)", "price": 6, "gives": {"engine_oil": 1}},
	"nail_gun": {"label": "Nail gun (faster rail repair)", "price": 15, "gives": {"nail_gun": 1}},
	"medkit": {"label": "Medkit", "price": 7, "gives": {"medkit": 1}},
	"come_along": {"label": "Come-along (hand winch: pulls a tipped train back up)", "price": 10, "gives": {"come_along": 1}},
	"grappler": {"label": "Grappling hook", "price": 12, "gives": {"grappler": 1}},
	"coal": {"label": "Coal x5", "price": 3, "gives": {"coal": 5}},
}

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
## Debug role for solo testing: "crew" (world sabotage runs by itself) or "impostor" ([Tab] menu, keys 1-4).
var role := "crew"
var sabotage_menu_open := false
var world_sabotage := true
var wind_active := false:
	set(value):
		if wind_active != value:
			wind_active = value
			wind_changed.emit(value)
var ui_open := false:
	set(value):
		ui_open = value
		ui_changed.emit(value)

## Scene references, set by Main.
var track: Track
var train: Train
var sabotage: SabotageManager
var terrain: Terrain


func _ready() -> void:
	_setup_input()
	new_game(false)


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


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("restart_checkpoint"):
		restart_from_checkpoint()
	elif event.is_action_pressed("new_game"):
		new_game(true)
	elif event.is_action_pressed("toggle_role"):
		role = "impostor" if role == "crew" else "crew"
		sabotage_menu_open = false
		say("Debug role: %s%s" % [role.to_upper(), " ([Tab] = sabotage menu)" if role == "impostor" else ""])
	elif event.is_action_pressed("toggle_world_sabotage"):
		world_sabotage = not world_sabotage
		say("World sabotage: %s" % ("ON" if world_sabotage else "OFF"))


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


func buy(item_id: String) -> bool:
	var entry: Dictionary = SHOP[item_id]
	if not take("gold", entry.price):
		say("Not enough gold for %s (%d gold)" % [entry.label, entry.price])
		return false
	for item: String in entry.gives:
		add(item, entry.gives[item])
	say("Bought %s" % entry.label)
	return true


# --- Messages --------------------------------------------------------------

func say(text: String) -> void:
	print("[game] ", text)
	message.emit(text)


func show_banner(text: String) -> void:
	print("[banner] ", text)
	banner.emit(text)


# --- Stations, checkpoints, game over --------------------------------------

## Called by the train when it comes to a stop inside a station.
func on_train_stopped_at_station(index: int) -> void:
	if index != next_station:
		return
	next_station += 1
	save_checkpoint(index)
	station_reached.emit(index)
	if index >= STATION_COUNT:
		show_banner("FINAL STATION REACHED!\nThe helicopter landed at the port… (Chapter 2: the sea)")
		chapter_completed.emit()
	else:
		show_banner("Station %d / %d reached!\nCheckpoint saved. Repair, shop, rest." % [index, STATION_COUNT])


func save_checkpoint(station_index: int) -> void:
	checkpoint = {
		"station": station_index,
		"inventory": inventory.duplicate(),
		"train": train.save_state() if train else {},
	}
	var f := FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	if f:
		f.store_string(JSON.stringify(checkpoint))


func on_player_downed(_player: Node) -> void:
	for p in get_tree().get_nodes_in_group("player"):
		if not p.downed:
			return
	# TODO(M4/M5): if only the impostor is alive, they choose: kill themself (crew loses) or revive everyone.
	show_banner("THE CREW IS DEAD\nBack to the last checkpoint…")
	crew_lost.emit()
	get_tree().create_timer(3.0).timeout.connect(restart_from_checkpoint)


func restart_from_checkpoint() -> void:
	wind_active = false
	ui_open = false
	if checkpoint.is_empty():
		new_game(true)
		return
	inventory = checkpoint.inventory.duplicate()
	next_station = int(checkpoint.station) + 1
	inventory_changed.emit()
	get_tree().reload_current_scene.call_deferred()


func new_game(reload: bool) -> void:
	checkpoint = {}
	inventory = START_INVENTORY.duplicate()
	next_station = 1
	wind_active = false
	ui_open = false
	inventory_changed.emit()
	if reload:
		get_tree().reload_current_scene.call_deferred()
