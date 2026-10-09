extends Node
## Headless checks for the menus workstream:
##   godot --headless --path . res://tests/TestMenu.tscn
## Settings load/save/rebind/reset (on a separate test file), audio and graphics apply, the main menu
## (120 frames, no Game.track/train), and the pause menu stopping the train in solo play.

const TEST_PATH := Game.TEST_SAVE_DIR + "TestMenu/menu_settings.cfg"

var failures := 0


func _ready() -> void:
	Game.use_save_dir(Game.TEST_SAVE_DIR + "TestMenu/")  # never the player's own saves and settings
	Settings.path = TEST_PATH
	DirAccess.remove_absolute(ProjectSettings.globalize_path(TEST_PATH))
	Settings.load_settings()
	DirAccess.remove_absolute(ProjectSettings.globalize_path(Game.save_path("solo")))
	await _settings_checks()
	await _hint_checks()
	await _menu_checks()
	await _pause_checks()
	await _continue_checks()
	await _flow_checks()
	DirAccess.remove_absolute(ProjectSettings.globalize_path(Game.save_path("solo")))
	DirAccess.remove_absolute(ProjectSettings.globalize_path(TEST_PATH))
	Settings.path = Game.save_dir + Settings.FILE
	Settings.load_settings()
	print("\n%s: %d failure(s)" % ["PASSED" if failures == 0 else "FAILED", failures])
	get_tree().quit(1 if failures > 0 else 0)


func check(ok: bool, what: String) -> void:
	print(("  ok   " if ok else "  FAIL ") + what)
	if not ok:
		failures += 1


func _frames(n: int) -> void:
	for i in n:
		await get_tree().process_frame


func _has_key(action: String, key: Key) -> bool:
	for ev in InputMap.action_get_events(action):
		if ev is InputEventKey and (ev as InputEventKey).physical_keycode == key:
			return true
	return false


func _settings_checks() -> void:
	print("Settings")
	check(InputMap.has_action("pause") and _has_key("pause", KEY_ESCAPE), "pause action is registered on Esc")
	check(InputMap.has_action("push_to_talk") and _has_key("push_to_talk", KEY_V), "push_to_talk action is registered on V")
	check(is_equal_approx(Settings.mouse_sensitivity, 0.0025) and is_equal_approx(Settings.fov, 80.0), "defaults: sensitivity 0.0025, FOV 80")
	check(get_tree().root.theme != null, "root viewport has the UiTheme")

	# Rebind jump to J: works at once and survives a reload
	var j := InputEventKey.new()
	j.physical_keycode = KEY_J
	Settings.rebind("jump", j)
	check(_has_key("jump", KEY_J) and not _has_key("jump", KEY_SPACE), "jump rebound to J at once")
	Settings.save()
	var cfg := ConfigFile.new()
	check(cfg.load(TEST_PATH) == OK and cfg.has_section_key("controls", "bind_jump"), "binding saved in the settings file")
	InputMap.action_erase_events("jump")
	Settings.load_settings()
	check(_has_key("jump", KEY_J), "jump is still J after reloading the file")
	check(Settings.binding_text("jump") != "" and Settings.binding_text("jump") != "Unbound", "binding text: %s" % Settings.binding_text("jump"))
	Settings.reset_controls()
	check(_has_key("jump", KEY_SPACE) and not _has_key("jump", KEY_J), "reset to defaults restores Space")
	var attack := InputMap.action_get_events("attack")
	check(attack.size() == 1 and attack[0] is InputEventMouseButton, "attack is back on the left mouse button")
	var m := InputEventMouseButton.new()
	m.button_index = MOUSE_BUTTON_MIDDLE
	Settings.rebind("interact_alt", m)
	check(Settings.binding_text("interact_alt") == "Mouse Middle", "mouse buttons can be bound")
	Settings.reset_controls()

	# Audio buses
	Settings.set_value("audio", "Music", 0.5)
	var music := AudioServer.get_bus_index("Music")
	check(music >= 0 and absf(AudioServer.get_bus_volume_db(music) - linear_to_db(0.5)) < 0.01, "Music slider sets the bus volume")
	Settings.set_value("audio", "SFX", 0.0)
	check(AudioServer.is_bus_mute(AudioServer.get_bus_index("SFX")), "SFX at 0 mutes the bus")
	Settings.set_value("audio", "SFX", 0.8)
	check(not AudioServer.is_bus_mute(AudioServer.get_bus_index("SFX")), "SFX back up unmutes")
	check(AudioServer.is_bus_mute(AudioServer.get_bus_index("Mic")), "Mic bus is muted (no echo)")

	# Graphics
	Settings.set_value("graphics", "render_scale", 0.75)
	check(is_equal_approx(get_tree().root.scaling_3d_scale, 0.75), "resolution scale applies to the viewport")
	Settings.set_value("graphics", "max_fps", 60)
	check(Engine.max_fps == 60, "max FPS applies")
	Settings.set_value("graphics", "aa", 3)
	check(get_tree().root.msaa_3d == Viewport.MSAA_4X, "MSAA 4x applies")
	Settings.save()
	cfg = ConfigFile.new()
	cfg.load(TEST_PATH)
	check(is_equal_approx(float(cfg.get_value("graphics", "render_scale", 0.0)), 0.75) and float(cfg.get_value("audio", "Music", 0.0)) == 0.5, "graphics and audio persist")
	Settings.reset_section("graphics")
	Settings.reset_section("audio")
	check(is_equal_approx(get_tree().root.scaling_3d_scale, 1.0) and Engine.max_fps == 0, "graphics reset")

	# A file with wrong types and out-of-range values falls back to defaults / clamps (no engine parse error in
	# the log; the unparsable-file case is opt-in: pass "corrupt" after "--")
	var f := FileAccess.open(TEST_PATH, FileAccess.WRITE)
	f.store_string("[controls]\nmouse_sensitivity=\"fast\"\n[graphics]\nfov=9999.0\nwindow_mode=-3\n")
	f.close()
	Settings.load_settings()
	check(is_equal_approx(Settings.mouse_sensitivity, 0.0025) and _has_key("jump", KEY_SPACE), "bad values -> defaults")
	check(is_equal_approx(Settings.fov, 110.0) and int(Settings.get_value("graphics", "window_mode")) == 0, "out of range values are clamped")
	if OS.get_cmdline_user_args().has("corrupt"):
		print("  (an engine 'ConfigFile parse error' follows: expected, this case writes a corrupt file)")
		f = FileAccess.open(TEST_PATH, FileAccess.WRITE)
		f.store_string("[controls\nthis is = = not a config }{")
		f.close()
		Settings.load_settings()
		check(is_equal_approx(Settings.mouse_sensitivity, 0.0025) and _has_key("jump", KEY_SPACE), "corrupt file -> defaults")
	Settings.reset_section("graphics")
	Settings.cfg.set_value("graphics", "fov", "banana")
	Settings._validate()
	check(is_equal_approx(Settings.fov, 80.0), "wrong value types are dropped")
	await _frames(2)


func _menu_checks() -> void:
	print("Main menu")
	var menu: Node = load("res://scenes/menu/MainMenu.tscn").instantiate()
	add_child(menu)
	await _frames(120)
	var bg: MenuBackground = menu.get("background")
	check(bg != null and bg.train != null and bg.train.cars.size() > 0, "background has the train")
	check(bg != null and bg.station != null and bg.terrain != null, "background has station 0 and terrain")
	check(Game.train == null and Game.track == null, "menu does not set Game.train / Game.track")
	check(get_tree().get_nodes_in_group("player").is_empty(), "no Player in the menu")
	var buttons: Array = menu.get("_buttons")
	var texts: Array = buttons.map(func(b: Button) -> String: return b.text)
	check(buttons.size() == 5 and texts.has("Play solo") and texts.has("Host game"), "menu buttons: Play solo, Host, Join, Settings, Quit (%s)" % ", ".join(texts))
	check(not texts.any(func(t: String) -> bool: return t.begins_with("Continue")), "no Continue without a save")
	# debug keys do nothing outside a run (F5 used to reload the menu)
	var ev := InputEventAction.new()
	ev.action = "restart_checkpoint"
	ev.pressed = true
	Input.parse_input_event(ev)
	await _frames(5)
	check(is_instance_valid(menu) and menu.is_inside_tree() and menu.get("_buttons").size() == 5, "F5 in the main menu does nothing")
	var settings: SettingsMenu = menu.get("_settings")
	settings.open()
	await _frames(3)
	check(settings.visible and settings.tabs.get_tab_count() == 4, "settings opens with 4 tabs")
	for i in settings.tabs.get_tab_count():
		settings.tabs.current_tab = i
		await _frames(2)
	settings.close()
	check(not settings.visible, "settings closes")
	menu.call("_open_join")
	await _frames(2)
	menu.call("_close_join")
	menu.queue_free()
	await _frames(2)


func _pause_checks() -> void:
	print("Pause menu")
	Game.new_game(false)
	Game.world_sabotage = false
	var main: Node3D = load("res://scenes/main/Main.tscn").instantiate()
	add_child(main)
	await _frames(5)
	var hud: HUD = main.hud
	var train := Game.train
	check(hud.pause_menu != null, "HUD has a pause menu")
	var player: Player = main.player
	Settings.fov = 95.0
	check(is_equal_approx(player.camera.fov, 95.0), "FOV setting reaches the player camera")
	Settings.fov = 80.0
	# a medkit saves a player who would go down; the shop no longer sells items without a use
	Game.add("medkit")
	player.take_damage(500.0)
	check(not player.downed and player.health > 0.0 and not Game.has("medkit"), "a medkit saves the player (health %d)" % int(player.health))
	check(not Game.SHOP.has("grappler") and Game.SHOP.has("medkit"), "shop: medkit yes, grappling hook not yet")
	player.take_damage(-50.0)
	check(player.health <= Game.REVIVE_HEALTH, "negative damage does not heal")

	# Clear the track ahead and drive
	for i in range(Game.track.piece_at(train.distance), Game.track.piece_at(train.distance + 200.0)):
		Game.track.repair_piece(i)
	train.fuel = Train.MAX_FUEL
	train.lever = 1
	await get_tree().create_timer(1.5).timeout
	check(train.speed > 0.5, "train is moving before pausing")
	await _press_pause()
	check(hud.pause_menu.is_open and get_tree().paused and Game.ui_open, "Esc opens the pause menu and pauses solo play")
	var d0 := train.distance
	await get_tree().create_timer(0.6, true).timeout
	check(is_equal_approx(train.distance, d0), "the train does not move while paused")
	await _press_pause()
	check(not hud.pause_menu.is_open and not get_tree().paused and not Game.ui_open, "Esc again resumes")
	# Shop open: Esc closes the shop, not opening the pause menu
	hud.open_shop(main.get_node("Station0") as Station)
	await _frames(2)
	await _press_pause()
	check(not hud.pause_menu.is_open and not Game.ui_open, "Esc closes the shop first")
	main.queue_free()
	await _frames(3)


## Key hints follow the player's bindings: rebind "interact" to F and the prompts say [F].
func _hint_checks() -> void:
	print("Key hints")
	check(Settings.hint("Pick up the gate key  [E]") == "Pick up the gate key  [E]", "default binding: [E] stays")
	var f := InputEventKey.new()
	f.physical_keycode = KEY_F
	Settings.rebind("interact", f)
	check(Settings.hint("Pick up the gate key  [E]") == "Pick up the gate key  [F]", "interact on F: '%s'" % Settings.hint("Pick up the gate key  [E]"))
	check(Settings.hint("Close  [E / Esc]") == "Close  [F / Esc]", "combined hints: '%s'" % Settings.hint("Close  [E / Esc]"))
	check(Settings.hint("[LMB] drop · [RMB] cancel") == "[LMB] drop · [RMB] cancel", "mouse hints: LMB / RMB")
	check(HUD.help_text().contains("F use / place"), "the help panel shows the new key")
	check(Settings.key_label("inventory") == "Tab" and Settings.key_label("sabotage_menu") == "X", "Tab opens the inventory, X the impostor's sabotage menu")
	check(Settings.hint("[Tab] inventory · [X] sabotage") == "[Tab] inventory · [X] sabotage", "hints for Tab and X")
	var key := GateKey.new()
	check(Settings.hint(key.get_prompt(null)).ends_with("[F]"), "the gate key prompt shows [F] (%s)" % Settings.hint(key.get_prompt(null)))
	key.free()
	Settings.reset_controls()
	check(Settings.hint("Use [E]") == "Use [E]", "back to E after a reset")
	Game.debug_keys = false
	check(not HUD.help_text().contains("new game"), "no debug keys in the help of a release build")
	Game.debug_keys = OS.is_debug_build()
	await _frames(1)


## Save at station 2, leave, Continue: the run starts at station 2 with gates 0 and 1 open.
func _continue_checks() -> void:
	print("Continue from the save on disk")
	Game.new_game(false)
	Game.world_sabotage = false
	var main: Node3D = load("res://scenes/main/Main.tscn").instantiate()
	add_child(main)
	await _frames(3)
	Game.add("gold", 27)
	Game.add("soup", 2)
	var coal_saved := Game.count("coal")
	Game.track.open_gate(0)
	Game.track.open_gate(1)
	Game.next_station = 2
	Game.on_train_stopped_at_station(2)
	check(FileAccess.file_exists(Game.save_path("solo")), "station 2 saved the checkpoint to disk")
	main.queue_free()
	await _frames(3)
	Game.new_game(false)
	check(Game.saved_station() == 2, "the save says station 2")
	var menu: Node = load("res://scenes/menu/MainMenu.tscn").instantiate()
	add_child(menu)
	await _frames(3)
	var texts: Array = (menu.get("_buttons") as Array).map(func(b: Button) -> String: return b.text)
	check(texts.has("Continue  (station 2)"), "the main menu offers Continue (station 2)")
	# T3-01: with Continue there are six buttons; the last (Quit) must end well above the bottom of the screen
	# (stretch mode canvas_items + expand: a 16:9 window is always 1600x900 here, taller aspects only get more room)
	var old_size := get_tree().root.size
	get_tree().root.size = Vector2i(1600, 900)  # headless windows have no fixed shape: test the 16:9 one
	await _frames(3)
	var view := (menu.get("_root") as Control).get_viewport_rect().size
	var last: Button = (menu.get("_buttons") as Array).back()
	var bottom := (last.get_global_transform() * Vector2(0.0, last.size.y)).y
	check(last.text == "Quit" and bottom <= view.y - 50.0,
		"with a save, Quit ends %d px above the bottom of the %dx%d screen (>= 50)" % [int(view.y - bottom), int(view.x), int(view.y)])
	check(is_equal_approx(view.y, 900.0), "the check ran on a 900 px high screen (%d)" % int(view.y))
	get_tree().root.size = old_size
	menu.queue_free()
	await _frames(2)
	check(Game.continue_from_save(), "continue_from_save reads it")
	main = load("res://scenes/main/Main.tscn").instantiate()
	add_child(main)
	await _frames(3)
	check(Game.train.current_station == 2 and Game.next_station == 3, "the train starts at station 2 (next %d)" % Game.next_station)
	check(not Game.track.is_gate_locked(0) and not Game.track.is_gate_locked(1) and Game.track.is_gate_locked(2), "gates 0-1 open, gate 2 locked")
	check(main.get_node_or_null("Track/Key_2") != null and main.get_node_or_null("Track/Key_1") == null, "only the locked gate has its key")
	check(Game.count("gold") == Game.START_INVENTORY.gold + 27 and typeof(Game.inventory.gold) == TYPE_INT, "the inventory came back (gold %s)" % str(Game.inventory.gold))
	check(Game.stat("gates") >= 2.0, "and the run stats")
	check(Game.count("soup") == 2 and Game.count("coal") == coal_saved and Game.slot_item(Net.local_id(), 0) == "hammer",
		"the personal inventory came back too (soup %d, coal %d)" % [Game.count("soup"), Game.count("coal")])
	main.queue_free()
	await _frames(3)
	Game.new_game(false)


## Menu -> Play solo -> Main -> pause -> Back to menu.
func _flow_checks() -> void:
	print("Scene flow")
	# Keep this test node alive across scene changes: a dummy node becomes the "current scene"
	var dummy := Node.new()
	get_tree().root.add_child(dummy)
	get_tree().current_scene = dummy
	get_tree().change_scene_to_file("res://scenes/menu/MainMenu.tscn")
	await _frames(20)
	check(get_tree().current_scene != null and get_tree().current_scene.name == "MainMenu", "main menu loads as a scene")
	if true:
		var had_save := Game.saved_station("solo") > 0
		get_tree().current_scene.call("_on_solo")
		await _frames(2)
		var cards := get_tree().current_scene.find_children("*", "ConfirmCard", true, false)
		check(cards.size() == (1 if had_save else 0), "Play solo over a save asks first (save: %s, cards: %d)" % [had_save, cards.size()])
		for c in cards:
			(c as ConfirmCard).confirm()
		await get_tree().create_timer(1.2).timeout
		await _frames(5)
		var cur := get_tree().current_scene
		check(cur != null and cur.scene_file_path == "res://scenes/main/Main.tscn", "Play solo starts the game")
		check(not Net.is_online() and Net.backend == null, "solo opens no network socket")
		var hud: HUD = cur.get("hud") if cur else null
		if hud:
			hud.pause_menu.open()
			await _frames(2)
			hud.pause_menu.call("_back_to_menu")
			await _frames(20)
			cur = get_tree().current_scene
			check(cur != null and cur.name == "MainMenu" and not get_tree().paused, "Back to menu returns to the main menu, unpaused")
			check(not Game.ui_open, "UI flag cleared after leaving the game")


func _press_pause() -> void:
	var ev := InputEventAction.new()
	ev.action = "pause"
	ev.pressed = true
	Input.parse_input_event(ev)
	await _frames(2)
	var up := InputEventAction.new()
	up.action = "pause"
	up.pressed = false
	Input.parse_input_event(up)
	await _frames(2)
