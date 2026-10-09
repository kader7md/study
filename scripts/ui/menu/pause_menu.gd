class_name PauseMenu
extends CanvasLayer
## Esc menu in game: Resume, Restart from last station (solo / host), Settings, Back to menu, Quit, and the controls
## help with the current objective beside them (HUD look: HudStyle). Offline it pauses the tree (the train stops);
## online the game keeps running for everyone else. While open, Game.ui_open frees the mouse.
## Esc closes Settings first; a shop window (Game.ui_open without us) is closed by its owner instead.

const SCENE := "res://scenes/menu/PauseMenu.tscn"

var is_open := false
var _root: Control
var _card: PanelContainer
var _subtitle: Label
var _settings: SettingsMenu
var _resume_btn: Button
var _restart_btn: Button
var _help: KeyText
var _objective: Label


static func instantiate() -> PauseMenu:
	return (load(SCENE) as PackedScene).instantiate() as PauseMenu


func _ready() -> void:
	layer = 60
	process_mode = Node.PROCESS_MODE_ALWAYS
	_root = Control.new()
	_root.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(_root)
	_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	var dim := ColorRect.new()
	dim.color = Color(0.02, 0.03, 0.06, 0.55)
	_root.add_child(dim)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	var center := CenterContainer.new()
	_root.add_child(center)
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	# the in-game look (HudStyle): dark glass card, white outline, rounded display font
	_card = PanelContainer.new()
	_card.theme = HUD.hud_theme()
	_card.add_theme_stylebox_override("panel", HudStyle.panel_box(22.0, 26.0))
	center.add_child(_card)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 30)
	_card.add_child(row)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 12)
	row.add_child(col)
	col.add_child(HudStyle.label("Paused", 48, HudStyle.WHITE, 700))
	_subtitle = HudStyle.label("", 17, HudStyle.SOFT, 500)
	col.add_child(_subtitle)
	_resume_btn = _button(col, "Resume", &"HudAccent", close)
	_restart_btn = _button(col, "Restart from last station", &"", _ask_restart)
	_button(col, "Settings", &"", _open_settings)
	_button(col, "Back to menu", &"", _back_to_menu)
	_button(col, "Quit game", &"", _quit)
	# help lives here (and while [H] is held in game)
	var help := VBoxContainer.new()
	help.add_theme_constant_override("separation", 10)
	help.custom_minimum_size = Vector2(520, 0)
	row.add_child(help)
	help.add_child(HudStyle.label("Controls", 26, HudStyle.WHITE, 650))
	_help = KeyText.create("", 16, HORIZONTAL_ALIGNMENT_LEFT)
	help.add_child(_help)
	_objective = HudStyle.label("", 17, HudStyle.GOLD, 600)
	_objective.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_objective.custom_minimum_size = Vector2(520, 0)
	help.add_child(_objective)

	_settings = SettingsMenu.instantiate()
	_settings.hide()
	_settings.closed.connect(func() -> void: _card.show())
	_root.add_child(_settings)
	_root.hide()


func _button(parent: Control, text: String, variation: StringName, action: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.theme_type_variation = variation
	b.custom_minimum_size = Vector2(320, 46)
	b.pressed.connect(action)
	parent.add_child(b)
	return b


func _unhandled_input(event: InputEvent) -> void:
	if not event.is_action_pressed("pause"):
		return
	if is_open:
		get_viewport().set_input_as_handled()
		if _settings.visible:
			_settings.close()
		else:
			close()
	elif not Game.ui_open:
		get_viewport().set_input_as_handled()
		open()


static func online() -> bool:
	return Net.is_online()


func open() -> void:
	if is_open:
		return
	is_open = true
	var on := online()
	_subtitle.text = "Online: the game keeps running" if on else "Solo: the game is paused"
	if not on:
		get_tree().paused = true
	Game.open_ui(&"pause")
	_restart_btn.visible = Game.is_host()  # online only the host restarts (for everyone)
	_restart_btn.text = "Restart from station %d" % int(Game.checkpoint.station) if not Game.checkpoint.is_empty() else "Restart the run"
	_help.text = HUD.help_keys()
	_objective.text = ("Objective: " + Game.objective) if Game.objective != "" else ""
	_settings.hide()
	_card.show()
	_root.show()
	_card.pivot_offset = _card.get_combined_minimum_size() * 0.5
	_card.scale = Vector2(0.9, 0.9)
	_card.modulate.a = 0.0
	var tw := create_tween().set_parallel().set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.tween_property(_card, "scale", Vector2.ONE, 0.22)
	tw.tween_property(_card, "modulate:a", 1.0, 0.15)


func close() -> void:
	if not is_open:
		return
	is_open = false
	_settings.hide()
	_root.hide()
	for c in _root.get_children():
		if c is ConfirmCard:
			c.queue_free()
	get_tree().paused = false
	Game.close_ui(&"pause")


func _open_settings() -> void:
	_card.hide()
	_settings.open()


## The host of an online run with friends in it: leaving ends the run for everyone.
static func _ends_run_for_others() -> bool:
	return Net.is_online() and Net.is_host() and Net.players.size() > 1


func _ask_restart() -> void:
	var where := "station %d" % int(Game.checkpoint.station) if not Game.checkpoint.is_empty() else "the departure station"
	var text := "Everything since %s is lost." % where
	if Net.is_online():
		text += " Everyone goes back with you."
	ConfirmCard.ask(_root, "Restart from %s?" % where, text, "Restart", _restart)


func _restart() -> void:
	close()
	Game.restart_from_checkpoint()


func _back_to_menu() -> void:
	if _ends_run_for_others():
		ConfirmCard.ask(_root, "End the run for everyone?", "You are the host: leaving ends the run for the whole crew. The last station is saved.",
			"End the run", _do_back_to_menu)
		return
	_do_back_to_menu()


func _do_back_to_menu() -> void:
	close()
	Game.return_to_menu()


func _quit() -> void:
	if _ends_run_for_others():
		ConfirmCard.ask(_root, "Quit the game?", "You are the host: quitting ends the run for the whole crew. The last station is saved.",
			"Quit", _do_quit)
		return
	_do_quit()


func _do_quit() -> void:
	get_tree().quit()
