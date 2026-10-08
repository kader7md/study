extends Node
## Title screen (run/main_scene): TRUST ISSUES over a slow camera at the departure station.
## Continue (station N) -> solo run from the checkpoint on disk (only when there is one),
## Play solo -> Net.start_solo() (no network socket), Host game -> Net.host_game() -> Lobby,
## Join game -> invite code / IP:port dialog -> Net.join_game(); the dialog stays open while connecting and shows
## why a join failed; once the host lets us in -> Lobby. Settings, Quit.

const MAIN_SCENE := "res://scenes/main/Main.tscn"
const LOBBY_SCENE := "res://scenes/net/Lobby.tscn"
const TAGLINES := [
	"Fix the rails. Feed the fire. Trust no one.",
	"Five stations. One train. One liar.",
	"Somebody on this crew is not helping.",
]

var background: MenuBackground
var ui: CanvasLayer
var _root: Control
var _column: VBoxContainer
var _buttons: Array[Button] = []
var _settings: SettingsMenu
var _join: Control
var _join_code: LineEdit
var _join_status: Label
var _name_edit: LineEdit
var _toast: Label
var _fade: ColorRect
var _busy := false
var _settings_button: Button
var _joining := false


func _ready() -> void:
	get_tree().paused = false
	Game.ui_open = false
	if DisplayServer.get_name() != "headless":
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	_build_ui()
	background = MenuBackground.new()
	background.name = "Background"
	add_child(background)
	move_child(background, 0)
	var music := MenuMusic.new()
	music.name = "Music"
	add_child(music)
	_intro.call_deferred()
	Net.connection_failed.connect(_on_connection_failed)
	Net.joined.connect(_on_joined)


# --- UI -----------------------------------------------------------------------------------------

func _build_ui() -> void:
	ui = CanvasLayer.new()
	ui.layer = 10
	add_child(ui)
	_root = Control.new()
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ui.add_child(_root)

	# Warm shade on the left so the title and buttons read well over any background
	var shade := TextureRect.new()
	var grad := Gradient.new()
	grad.set_color(0, Color(UiTheme.INK, 0.72))
	grad.set_color(1, Color(UiTheme.INK, 0.0))
	grad.add_point(0.45, Color(UiTheme.INK, 0.45))
	var gt := GradientTexture2D.new()
	gt.gradient = grad
	gt.width = 256
	gt.height = 8
	shade.texture = gt
	shade.stretch_mode = TextureRect.STRETCH_SCALE
	shade.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	shade.anchor_bottom = 1.0
	shade.anchor_right = 0.62
	shade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(shade)

	_column = VBoxContainer.new()
	_column.add_theme_constant_override("separation", 14)
	_column.anchor_top = 0.5
	_column.anchor_bottom = 0.5
	_column.offset_left = 96
	_column.offset_top = -380
	_column.offset_right = 96 + 560
	_root.add_child(_column)

	var title_box := VBoxContainer.new()
	title_box.add_theme_constant_override("separation", -26)
	_column.add_child(title_box)
	for word in ["TRUST", "ISSUES"]:
		var t := UiTheme.title_label(word, 112)  # the same rounded display face as every other title
		t.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
		title_box.add_child(t)
	(title_box.get_child(1) as Label).add_theme_color_override("font_color", UiTheme.HONEY)

	# Tagline on a little wooden plank
	var plank := PanelContainer.new()
	plank.theme_type_variation = &"WoodPanel"
	var pstyle := UiTheme.panel(UiTheme.WOOD, 10, 3)
	pstyle.content_margin_top = 6
	pstyle.content_margin_bottom = 8
	pstyle.content_margin_left = 16
	pstyle.content_margin_right = 16
	plank.add_theme_stylebox_override("panel", pstyle)
	plank.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	var tag := Label.new()
	tag.text = TAGLINES[randi() % TAGLINES.size()]
	tag.theme_type_variation = &"HudSmall"
	tag.add_theme_font_size_override("font_size", 19)
	plank.add_child(tag)
	_column.add_child(plank)

	var gap := Control.new()
	gap.custom_minimum_size.y = 18
	_column.add_child(gap)

	var saved := Game.saved_station()
	if saved >= 0:
		_add_button("Continue  (station %d)" % saved, &"AccentButton", _on_continue)
	_add_button("Play solo", &"AccentButton" if saved < 0 else &"BigButton", _on_solo)
	_add_button("Host game", &"BigButton", _on_host)
	_add_button("Join game", &"BigButton", _open_join)
	_settings_button = _add_button("Settings", &"BigButton", _open_settings)
	_add_button("Quit", &"BigButton", _on_quit)

	# Bottom left: build info. Bottom right: your name card.
	var info := Label.new()
	info.text = "Chapter 1: The Train Chase  ·  prototype build  ·  F11 fullscreen"
	info.add_theme_font_size_override("font_size", 17)
	info.theme_type_variation = &"HudSmall"
	info.anchor_top = 1.0
	info.anchor_bottom = 1.0
	info.offset_left = 24
	info.offset_top = -40
	info.offset_right = 900
	_root.add_child(info)

	var card := PanelContainer.new()
	card.anchor_left = 1.0
	card.anchor_right = 1.0
	card.anchor_top = 1.0
	card.anchor_bottom = 1.0
	card.offset_left = -360
	card.offset_top = -110
	card.offset_right = -24
	card.offset_bottom = -24
	card.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	card.grow_vertical = Control.GROW_DIRECTION_BEGIN
	var cstyle := UiTheme.panel(UiTheme.CREAM, 14, 3)
	cstyle.set_content_margin_all(12)
	card.add_theme_stylebox_override("panel", cstyle)
	_root.add_child(card)
	var crow := HBoxContainer.new()
	card.add_child(crow)
	crow.add_child(UiIcon.create("crown", 30))
	var cv := VBoxContainer.new()
	cv.add_theme_constant_override("separation", 2)
	cv.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	crow.add_child(cv)
	var cl := Label.new()
	cl.text = "Your name"
	cl.theme_type_variation = &"MutedLabel"
	cl.add_theme_font_size_override("font_size", 15)
	cv.add_child(cl)
	_name_edit = LineEdit.new()
	_name_edit.max_length = Net.NAME_MAX
	_name_edit.placeholder_text = Net.DEFAULT_NAME
	_name_edit.text = str(Settings.get_value("profile", "name", ""))
	_name_edit.text_changed.connect(func(t: String) -> void: Settings.set_value("profile", "name", t.strip_edges().left(Net.NAME_MAX)))
	cv.add_child(_name_edit)

	_toast = Label.new()
	_toast.theme_type_variation = &"HudLabel"
	_toast.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_toast.anchor_left = 0.5
	_toast.anchor_right = 0.5
	_toast.anchor_top = 1.0
	_toast.anchor_bottom = 1.0
	_toast.offset_left = -400
	_toast.offset_right = 400
	_toast.offset_top = -100
	_toast.modulate.a = 0.0
	_root.add_child(_toast)

	_build_join_dialog()

	_settings = SettingsMenu.instantiate()
	_settings.hide()
	_settings.closed.connect(_on_overlay_closed)
	_root.add_child(_settings)

	_fade = ColorRect.new()
	_fade.color = UiTheme.INK
	_fade.set_anchors_preset(Control.PRESET_FULL_RECT)
	_fade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(_fade)


func _add_button(text: String, variation: StringName, action: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.theme_type_variation = variation
	b.custom_minimum_size = Vector2(360, 0)
	b.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	b.alignment = HORIZONTAL_ALIGNMENT_LEFT
	b.pressed.connect(action)
	b.mouse_entered.connect(_nudge.bind(b, 14.0))
	b.mouse_exited.connect(_nudge.bind(b, 0.0))
	b.modulate.a = 0.0
	_column.add_child(b)
	_buttons.append(b)
	return b


func _nudge(b: Button, x: float) -> void:
	if b.has_meta("tween"):
		var old: Tween = b.get_meta("tween")
		if old and old.is_valid():
			old.kill()
	var tw := b.create_tween().set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.tween_property(b, "position:x", x, 0.18)
	b.set_meta("tween", tw)


## Fade in from ink, then slide the title and buttons in one after another.
func _intro() -> void:
	await get_tree().process_frame
	var fade := create_tween()
	fade.tween_property(_fade, "color:a", 0.0, 1.2).set_delay(0.15)
	fade.tween_callback(_fade.hide)
	for i in _column.get_child_count():
		var c := _column.get_child(i) as Control
		if c is Button:
			continue
		c.modulate.a = 0.0
		var t := create_tween().set_parallel()
		t.tween_property(c, "modulate:a", 1.0, 0.6).set_delay(0.3 + i * 0.12)
	for i in _buttons.size():
		var b := _buttons[i]
		b.position.x = -60.0
		var t := create_tween().set_parallel().set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
		t.tween_property(b, "position:x", 0.0, 0.5).set_delay(0.7 + i * 0.09)
		t.tween_property(b, "modulate:a", 1.0, 0.35).set_delay(0.7 + i * 0.09)


func _build_join_dialog() -> void:
	_join = Control.new()
	_join.set_anchors_preset(Control.PRESET_FULL_RECT)
	_join.hide()
	_root.add_child(_join)
	var dim := ColorRect.new()
	dim.color = Color(UiTheme.INK, 0.55)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	_join.add_child(dim)
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	_join.add_child(center)
	var card := PanelContainer.new()
	card.theme_type_variation = &"WoodPanel"
	card.custom_minimum_size = Vector2(560, 0)
	center.add_child(card)
	var inner := PanelContainer.new()
	card.add_child(inner)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 10)
	inner.add_child(col)
	var title := UiTheme.title_label("JOIN A GAME", 44)
	title.add_theme_color_override("font_color", UiTheme.HONEY)
	col.add_child(title)
	var l1 := Label.new()
	l1.text = "Invite code or IP:port"
	col.add_child(l1)
	_join_code = LineEdit.new()
	_join_code.placeholder_text = "7K2QF-9XM4A   or   192.168.1.20:24565"
	_join_code.text_submitted.connect(func(_t: String) -> void: _on_join())
	col.add_child(_join_code)
	var l2 := Label.new()
	l2.theme_type_variation = &"MutedLabel"
	l2.add_theme_font_size_override("font_size", 16)
	l2.text = "You join as the name in the card at the bottom right."
	col.add_child(l2)
	_join_status = Label.new()
	_join_status.theme_type_variation = &"MutedLabel"
	_join_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_join_status.custom_minimum_size = Vector2(480, 0)
	col.add_child(_join_status)
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_END
	row.add_theme_constant_override("separation", 12)
	col.add_child(row)
	var cancel := Button.new()
	cancel.text = "Cancel"
	cancel.pressed.connect(_cancel_join)
	row.add_child(cancel)
	var join := Button.new()
	join.text = "Join"
	join.theme_type_variation = &"AccentButton"
	join.pressed.connect(_on_join)
	row.add_child(join)


# --- Actions ------------------------------------------------------------------------------------

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("pause") or event.is_action_pressed("ui_cancel"):
		if _join.visible:
			get_viewport().set_input_as_handled()
			_cancel_join()


func _on_solo() -> void:
	if _busy:
		return
	_save_name(_name_edit.text)
	var saved := Game.saved_station("solo")
	if saved > 0:
		ConfirmCard.ask(_root, "Start a new run?", "Your solo save at station %d is replaced once the new run reaches station 1. Continue keeps it." % saved,
			"New run", func() -> void: _go(MAIN_SCENE), false)
		return
	_go(MAIN_SCENE)


## Solo run from the checkpoint on disk.
func _on_continue() -> void:
	if _busy:
		return
	_save_name(_name_edit.text)
	_go(MAIN_SCENE, true)


func _on_host() -> void:
	if _busy:
		return
	_save_name(_name_edit.text)
	if Net.host_game() != OK:
		_say("Could not host: %s\nPlay solo still works." % Net.last_error)
		return
	_go(LOBBY_SCENE)


func _open_join() -> void:
	_join_status.text = ""
	_join.show()
	_join_code.grab_focus()


func _close_join() -> void:
	_join.hide()


## Cancel (or Esc) in the join dialog: stops a join that is still connecting.
func _cancel_join() -> void:
	if _joining:
		_joining = false
		Net.leave()
	_close_join()


func _on_join() -> void:
	if _busy or _joining:
		return
	var code := _join_code.text.strip_edges()
	if code == "":
		_join_status.text = "Paste the invite code your host gave you (or their IP:port)."
		_join_code.grab_focus()
		return
	_save_name(_name_edit.text)
	if Net.join_game(code) != OK:
		_join_status.text = Net.last_error  # connection_failed is ignored while the dialog shows it
		return
	_joining = true
	_join_status.text = "Connecting to %s…" % Net.joined_address


## The host let us into its lobby.
func _on_joined() -> void:
	if _joining and not Net.run_active:
		_joining = false
		_go(LOBBY_SCENE)


## A join failed: the reason goes in the join dialog's status line (or a toast when the dialog is closed).
func _on_connection_failed(reason: Variant = "") -> void:
	_busy = false
	_joining = false
	if _join.visible:
		_join_status.text = str(reason)
	else:
		_say(str(reason))


func _open_settings() -> void:
	_settings.open()


func _on_overlay_closed() -> void:
	if DisplayServer.get_name() != "headless":
		_settings_button.grab_focus()


func _on_quit() -> void:
	get_tree().quit()


func _save_name(n: String) -> void:
	var clean := n.strip_edges().left(Net.NAME_MAX)
	if clean != "":
		Settings.set_value("profile", "name", clean)
		_name_edit.text = clean


func _go(scene: String, from_save := false) -> void:
	_busy = true
	Settings.save()
	_fade.show()
	_fade.color.a = 0.0
	var t := create_tween()
	t.tween_property(_fade, "color:a", 1.0, 0.35)
	var music := get_node_or_null("Music") as AudioStreamPlayer
	if music:
		t.parallel().tween_property(music, "volume_db", -40.0, 0.35)
	await t.finished
	if not is_inside_tree() or (scene == LOBBY_SCENE and Net.run_active):
		return  # a rejoining player goes straight into the running world
	if scene == MAIN_SCENE:
		Net.start_solo(from_save)  # offline: no socket, no firewall prompt
	else:
		get_tree().change_scene_to_file(scene)


func _say(text: String) -> void:
	_toast.text = text
	var t := create_tween()
	t.tween_property(_toast, "modulate:a", 1.0, 0.2)
	t.tween_interval(3.0)
	t.tween_property(_toast, "modulate:a", 0.0, 0.6)
