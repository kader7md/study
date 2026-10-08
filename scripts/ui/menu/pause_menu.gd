class_name PauseMenu
extends CanvasLayer
## Esc menu in game: Resume, Restart from last station (solo / host), Settings, Back to menu, Quit. Offline it pauses the tree (the train stops);
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


static func instantiate() -> PauseMenu:
	return (load(SCENE) as PackedScene).instantiate() as PauseMenu


func _ready() -> void:
	layer = 60
	process_mode = Node.PROCESS_MODE_ALWAYS
	_root = Control.new()
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(_root)

	var dim := ColorRect.new()
	dim.color = Color(UiTheme.INK, 0.5)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.add_child(dim)

	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.add_child(center)
	_card = PanelContainer.new()
	_card.theme_type_variation = &"WoodPanel"
	_card.custom_minimum_size = Vector2(440, 0)
	center.add_child(_card)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 14)
	_card.add_child(col)
	col.add_child(UiTheme.title_label("PAUSED", 56))
	_subtitle = Label.new()
	_subtitle.theme_type_variation = &"HudSmall"
	_subtitle.add_theme_font_size_override("font_size", 18)
	_subtitle.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(_subtitle)
	_resume_btn = _button(col, "Resume", &"AccentButton", close)
	_restart_btn = _button(col, "Restart from last station", &"BigButton", _ask_restart)
	_button(col, "Settings", &"BigButton", _open_settings)
	_button(col, "Back to menu", &"BigButton", _back_to_menu)
	_button(col, "Quit game", &"BigButton", _quit)

	_settings = SettingsMenu.instantiate()
	_settings.hide()
	_settings.closed.connect(func() -> void: _card.show())
	_root.add_child(_settings)
	_root.hide()


func _button(parent: Control, text: String, variation: StringName, action: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.theme_type_variation = variation
	b.custom_minimum_size = Vector2(360, 0)
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
