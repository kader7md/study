class_name SettingsMenu
extends Control
## Settings overlay used by the main menu and the pause menu. Tabs: Controls, Graphics, Audio, Microphone.
## Every change goes through Settings.set_value (applied at once, saved to user://settings.cfg).

signal closed

const SCENE := "res://scenes/menu/SettingsMenu.tscn"

## Friendly names, grouped. Actions not listed here land in "Other".
const GROUPS := [
	["Movement", ["move_forward", "move_back", "move_left", "move_right", "jump", "sprint"]],
	["Hands & hotbar", ["attack", "cancel", "interact", "interact_alt", "drop", "winch_release", "tool_1", "tool_2", "tool_3", "tool_4", "tool_5", "inventory"]],
	["Game", ["pause", "push_to_talk", "show_help", "emote"]],
	["Impostor", ["sabotage_menu", "sabotage_1", "sabotage_2", "sabotage_3", "sabotage_4"]],
	["Debug", ["toggle_role", "toggle_world_sabotage", "restart_checkpoint", "new_game"]],
]
const NAMES := {
	"move_forward": "Walk forward", "move_back": "Walk back", "move_left": "Step left", "move_right": "Step right",
	"jump": "Jump", "sprint": "Sprint", "attack": "Use tool / hit", "cancel": "Cancel / aim off",
	"interact": "Use / place", "interact_alt": "Alternative use", "drop": "Put item back",
	"tool_1": "Hotbar slot 1", "tool_2": "Hotbar slot 2", "tool_3": "Hotbar slot 3", "tool_4": "Hotbar slot 4",
	"tool_5": "Hotbar slot 5", "inventory": "Inventory", "winch_release": "Release the come-along",
	"pause": "Pause menu", "push_to_talk": "Push to talk", "show_help": "Show help (hold)", "emote": "Wave (emote)",
	"sabotage_menu": "Sabotage menu", "sabotage_1": "Sabotage 1", "sabotage_2": "Sabotage 2",
	"sabotage_3": "Sabotage 3", "sabotage_4": "Sabotage 4",
	"toggle_role": "Switch role (debug)", "toggle_world_sabotage": "World sabotage (debug)",
	"restart_checkpoint": "Last checkpoint (debug)", "new_game": "New game (debug)",
}
## Pairs that share a key on purpose (only one of them works at a time).
const SHARED_OK := [["tool_1", "sabotage_1"], ["tool_2", "sabotage_2"], ["tool_3", "sabotage_3"], ["tool_4", "sabotage_4"]]

var tabs: TabContainer
var _rebind_buttons: Array[KeyRebindButton] = []
var _conflict_labels := {}   # action -> Label
var _mic_meter: MicMeter
var _mic_tab: Control
var _mic_monitor: CheckButton
var _mic_status: Label
var _mic_device: OptionButton
var _ptt_light: Panel
var _sync := []              # Callables that refresh the widgets from Settings


static func instantiate() -> SettingsMenu:
	return (load(SCENE) as PackedScene).instantiate() as SettingsMenu


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP

	var dim := ColorRect.new()
	dim.color = Color(UiTheme.INK, 0.55)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(dim)

	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(center)
	var frame := PanelContainer.new()
	frame.theme_type_variation = &"WoodPanel"
	frame.custom_minimum_size = Vector2(980, 0)
	center.add_child(frame)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 12)
	frame.add_child(col)

	var head := HBoxContainer.new()
	col.add_child(head)
	var title := UiTheme.title_label("SETTINGS", 46)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(title)
	var close_btn := Button.new()
	close_btn.text = "Back"
	close_btn.theme_type_variation = &"AccentButton"
	close_btn.add_theme_font_size_override("font_size", 24)
	close_btn.pressed.connect(close)
	close_btn.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	head.add_child(close_btn)

	tabs = TabContainer.new()
	tabs.custom_minimum_size = Vector2(940, 560)
	col.add_child(tabs)
	_build_controls_tab()
	_build_graphics_tab()
	_build_audio_tab()
	_build_mic_tab()
	tabs.tab_changed.connect(func(_i: int) -> void: _update_mic_running())
	visibility_changed.connect(_update_mic_running)
	Settings.changed.connect(_on_settings_changed)
	_refresh_all()


func open() -> void:
	_refresh_all()
	show()
	_update_mic_running()


func close() -> void:
	if not visible:
		return
	hide()
	_update_mic_running()
	closed.emit()


func _unhandled_input(event: InputEvent) -> void:
	if visible and (event.is_action_pressed("pause") or event.is_action_pressed("ui_cancel")):
		get_viewport().set_input_as_handled()
		close()


func _process(_delta: float) -> void:
	if _ptt_light and _mic_meter and _mic_meter.running:
		var on := Input.is_action_pressed("push_to_talk") or not bool(Settings.get_value("mic", "push_to_talk"))
		_ptt_light.modulate = Color.WHITE if on else Color(1, 1, 1, 0.25)


# --- Layout helpers -----------------------------------------------------------------------------

func _page(tab_name: String) -> VBoxContainer:
	var scroll := ScrollContainer.new()
	scroll.name = tab_name
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	tabs.add_child(scroll)
	var margin := MarginContainer.new()
	margin.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	margin.add_theme_constant_override("margin_left", 8)
	margin.add_theme_constant_override("margin_right", 22)
	margin.add_theme_constant_override("margin_top", 4)
	margin.add_theme_constant_override("margin_bottom", 8)
	scroll.add_child(margin)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 8)
	margin.add_child(box)
	return box


func _header(parent: Control, text: String) -> void:
	var l := Label.new()
	l.text = text
	l.theme_type_variation = &"HeaderLabel"
	parent.add_child(l)


## A labelled row: name on the left, the widget(s) on the right.
func _row(parent: Control, label_text: String, hint := "") -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 14)
	row.custom_minimum_size.y = 44
	parent.add_child(row)
	var name_box := VBoxContainer.new()
	name_box.add_theme_constant_override("separation", 0)
	name_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name_box.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_child(name_box)
	var l := Label.new()
	l.text = label_text
	name_box.add_child(l)
	if hint != "":
		var h := Label.new()
		h.text = hint
		h.theme_type_variation = &"MutedLabel"
		h.add_theme_font_size_override("font_size", 15)
		name_box.add_child(h)
	return row


func _slider(row: HBoxContainer, min_v: float, max_v: float, step: float, fmt: Callable, getter: Callable, setter: Callable) -> HSlider:
	var s := HSlider.new()
	s.min_value = min_v
	s.max_value = max_v
	s.step = step
	s.custom_minimum_size = Vector2(300, 32)
	s.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(s)
	var val := Label.new()
	val.custom_minimum_size = Vector2(96, 0)
	val.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	row.add_child(val)
	var sync := func() -> void:
		s.set_value_no_signal(getter.call())
		val.text = fmt.call(s.value)
	s.value_changed.connect(func(v: float) -> void:
		val.text = fmt.call(v)
		setter.call(v))
	_sync.append(sync)
	return s


## A dropdown for Settings[section][key]. The setting stores the item index, or with `values` the value at that index.
func _option(row: HBoxContainer, items: Array, section: String, key: String, values: Array = []) -> OptionButton:
	var o := OptionButton.new()
	o.custom_minimum_size = Vector2(300, 42)
	o.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	for it: Variant in items:
		o.add_item(str(it))
	row.add_child(o)
	if values.is_empty():
		_sync.append(func() -> void: o.select(clampi(int(Settings.get_value(section, key)), 0, items.size() - 1)))
		o.item_selected.connect(func(i: int) -> void: Settings.set_value(section, key, i))
	else:
		_sync.append(func() -> void: o.select(maxi(values.find(type_convert(Settings.get_value(section, key), typeof(values[0]))), 0)))
		o.item_selected.connect(func(i: int) -> void: Settings.set_value(section, key, values[i]))
	return o


func _toggle(row: HBoxContainer, section: String, key: String, on_text := "On", off_text := "Off") -> CheckButton:
	var c := CheckButton.new()
	c.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	c.custom_minimum_size = Vector2(110, 0)
	row.add_child(c)
	var sync := func() -> void:
		c.set_pressed_no_signal(bool(Settings.get_value(section, key)))
		c.text = on_text if c.button_pressed else off_text
	c.toggled.connect(func(on: bool) -> void:
		c.text = on_text if on else off_text
		Settings.set_value(section, key, on))
	_sync.append(sync)
	return c


func _footer(parent: Control, text: String, action: Callable) -> void:
	parent.add_child(HSeparator.new())
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_END
	parent.add_child(row)
	var b := Button.new()
	b.text = text
	b.theme_type_variation = &"DangerButton"
	b.pressed.connect(func() -> void:
		action.call()
		_refresh_all())
	row.add_child(b)


# --- Controls ---------------------------------------------------------------------------------

func _build_controls_tab() -> void:
	var page := _page("Controls")
	_header(page, "Mouse")
	_slider(_row(page, "Mouse sensitivity"), 0.2, 3.0, 0.05,
		func(v: float) -> String: return "%.2fx" % v,
		func() -> float: return Settings.mouse_sensitivity / 0.0025,
		func(v: float) -> void: Settings.mouse_sensitivity = v * 0.0025)
	_toggle(_row(page, "Invert mouse Y"), "controls", "invert_y")

	var listed := {}
	for group: Array in GROUPS:
		var actions: Array = group[1]
		var present: Array[String] = []
		for a: String in actions:
			if InputMap.has_action(a):
				present.append(a)
				listed[a] = true
		if not present.is_empty():
			_header(page, group[0])
			for a in present:
				_bind_row(page, a)
	var others: Array[String] = []
	for a in Settings.rebindable_actions():
		if not listed.has(a):
			others.append(a)
	if not others.is_empty():
		_header(page, "Other")
		for a in others:
			_bind_row(page, a)
	_footer(page, "Reset controls to defaults", func() -> void: Settings.reset_section("controls"))


func _bind_row(page: Control, action: String) -> void:
	var row := _row(page, NAMES.get(action, action.capitalize()))
	var warn := Label.new()
	warn.add_theme_color_override("font_color", UiTheme.RUST_DARK)
	warn.add_theme_font_size_override("font_size", 16)
	warn.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	row.add_child(warn)
	_conflict_labels[action] = warn
	var b := KeyRebindButton.create(action)
	row.add_child(b)
	_rebind_buttons.append(b)


func _refresh_conflicts() -> void:
	for action: String in _conflict_labels:
		var warn: Label = _conflict_labels[action]
		var clash: Array[String] = []
		for other in Settings.conflicts(action):
			if not _shared_ok(action, other):
				clash.append(NAMES.get(other, other))
		warn.text = ("⚠ also " + ", ".join(clash)) if not clash.is_empty() else ""
		for b in _rebind_buttons:
			if b.action == action:
				if clash.is_empty():
					b.remove_theme_color_override("font_color")
				else:
					b.add_theme_color_override("font_color", UiTheme.DANGER)


func _shared_ok(a: String, b: String) -> bool:
	for pair: Array in SHARED_OK:
		if (pair[0] == a and pair[1] == b) or (pair[0] == b and pair[1] == a):
			return true
	return false


# --- Graphics ---------------------------------------------------------------------------------

func _build_graphics_tab() -> void:
	var page := _page("Graphics")
	_header(page, "Display")
	_option(_row(page, "Window mode"), Settings.WINDOW_MODES, "graphics", "window_mode")
	_toggle(_row(page, "V-Sync", "Stops tearing; caps FPS to the monitor"), "graphics", "vsync")
	var fps_names: Array[String] = []
	for f: int in Settings.FPS_LIMITS:
		fps_names.append("Unlimited" if f == 0 else "%d FPS" % f)
	# max_fps stores the FPS value, not the index
	_option(_row(page, "Max FPS"), fps_names, "graphics", "max_fps", Settings.FPS_LIMITS)

	_header(page, "Quality")
	_slider(_row(page, "Resolution scale", "Lower = faster, softer 3D"), 50, 100, 5,
		func(v: float) -> String: return "%d%%" % int(v),
		func() -> float: return float(Settings.get_value("graphics", "render_scale")) * 100.0,
		func(v: float) -> void: Settings.set_value("graphics", "render_scale", v / 100.0))
	_option(_row(page, "Shadows"), Settings.SHADOW_LEVELS, "graphics", "shadows")
	_option(_row(page, "Anti-aliasing"), Settings.AA_MODES, "graphics", "aa")
	_slider(_row(page, "Field of view"), 60, 110, 1,
		func(v: float) -> String: return "%d°" % int(v),
		func() -> float: return Settings.fov,
		func(v: float) -> void: Settings.fov = v)
	_footer(page, "Reset graphics", func() -> void: Settings.reset_section("graphics"))


# --- Audio ------------------------------------------------------------------------------------

func _build_audio_tab() -> void:
	var page := _page("Audio")
	_header(page, "Volume")
	var hints := {"Master": "Everything", "Music": "Menu and travel music", "SFX": "Train, tools, menus", "Voice": "Other players"}
	for bus: String in Settings.BUSES:
		var row := _row(page, bus if bus != "SFX" else "Sound effects", hints[bus])
		_slider(row, 0, 100, 1,
			func(v: float) -> String: return "Muted" if v <= 0.0 else "%d%%" % int(v),
			func() -> float: return float(Settings.get_value("audio", bus)) * 100.0,
			func(v: float) -> void: Settings.set_value("audio", bus, v / 100.0))
		var test := Button.new()
		test.text = "Test"
		test.theme_type_variation = &"KeyButton"
		test.set_meta("no_ui_sound", true)
		test.pressed.connect(_play_test.bind(bus))
		row.add_child(test)
	_footer(page, "Reset audio", func() -> void: Settings.reset_section("audio"))


func _play_test(bus: String) -> void:
	var p := AudioStreamPlayer.new()
	p.stream = Settings._tone([392.0, 523.25, 659.25], 0.45, 0.6, 5.0)
	p.bus = bus
	add_child(p)
	p.finished.connect(p.queue_free)
	p.play()


# --- Microphone -------------------------------------------------------------------------------

func _build_mic_tab() -> void:
	var page := _page("Microphone")
	_mic_tab = page.get_parent().get_parent()
	_header(page, "Input")
	var dev_row := _row(page, "Input device")
	_mic_device = OptionButton.new()
	_mic_device.custom_minimum_size = Vector2(360, 42)
	_mic_device.clip_text = true
	_mic_device.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	dev_row.add_child(_mic_device)
	_mic_device.item_selected.connect(func(i: int) -> void:
		Settings.mic_device = _mic_device.get_item_text(i))

	var lvl_row := _row(page, "Input level", "Speak: the bar should move")
	_mic_meter = MicMeter.new()
	_mic_meter.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	lvl_row.add_child(_mic_meter)
	_ptt_light = Panel.new()
	_ptt_light.custom_minimum_size = Vector2(26, 26)
	_ptt_light.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_ptt_light.add_theme_stylebox_override("panel", UiTheme.flat(UiTheme.BODY_GREEN, 13, 3))
	_ptt_light.tooltip_text = "Lit while you are sending your voice"
	lvl_row.add_child(_ptt_light)

	_mic_status = Label.new()
	_mic_status.theme_type_variation = &"MutedLabel"
	_mic_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	page.add_child(_mic_status)

	var mon_row := _row(page, "Test: hear yourself", "Plays your mic through your speakers (use headphones)")
	_mic_monitor = CheckButton.new()
	_mic_monitor.text = "Off"
	_mic_monitor.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_mic_monitor.toggled.connect(func(on: bool) -> void:
		_mic_monitor.text = "On" if on else "Off"
		Settings.set_mic_monitor(on and _mic_meter.running))
	mon_row.add_child(_mic_monitor)

	_header(page, "Voice chat")
	_toggle(_row(page, "Push to talk", "Off = open mic (always sending)"), "mic", "push_to_talk")
	var ptt_row := _row(page, "Push-to-talk key")
	var ptt := KeyRebindButton.create("push_to_talk")
	ptt_row.add_child(ptt)
	_rebind_buttons.append(ptt)
	var name_row := _row(page, "Your name", "Shown to other players")
	var name_edit := LineEdit.new()
	name_edit.custom_minimum_size = Vector2(300, 0)
	name_edit.max_length = 20
	name_edit.placeholder_text = "Player"
	name_row.add_child(name_edit)
	_sync.append(func() -> void:
		if not name_edit.has_focus():
			name_edit.text = str(Settings.get_value("profile", "name", "")))
	name_edit.text_changed.connect(func(t: String) -> void: Settings.set_value("profile", "name", t.strip_edges().left(20)))


func _fill_devices() -> void:
	_mic_device.clear()
	var devices := AudioServer.get_input_device_list() if MicMeter.has_input_device() else PackedStringArray()
	if devices.is_empty():
		_mic_device.add_item("No input device")
		_mic_device.disabled = true
		return
	_mic_device.disabled = false
	var current := Settings.mic_device
	var sel := 0
	for i in devices.size():
		_mic_device.add_item(devices[i])
		if devices[i] == current:
			sel = i
	_mic_device.select(sel)


func _update_mic_running() -> void:
	if _mic_meter == null:
		return
	var want := is_visible_in_tree() and tabs.get_current_tab_control() == _mic_tab
	if want and not _mic_meter.running:
		_fill_devices()
		if _mic_meter.start():
			_mic_status.text = "Listening on \"%s\". Nothing is sent to anyone from this screen." % AudioServer.input_device
		else:
			_mic_status.text = "No input device found. Plug in a microphone, then reopen this tab. (Voice chat stays off.)"
	elif not want and _mic_meter.running:
		_mic_meter.stop()
		_mic_monitor.set_pressed_no_signal(false)
		_mic_monitor.text = "Off"
		Settings.set_mic_monitor(false)
	if not _mic_meter.running:
		_mic_monitor.disabled = true
	else:
		_mic_monitor.disabled = false


# --- Sync ---------------------------------------------------------------------------------------

func _refresh_all() -> void:
	for f: Callable in _sync:
		f.call()
	for b in _rebind_buttons:
		if not b.listening:
			b.refresh()
	_refresh_conflicts()


func _on_settings_changed(section: String, _key: String) -> void:
	if section == "controls":
		_refresh_conflicts()
	if _key == "*" or _key == "":
		_refresh_all()


func _exit_tree() -> void:
	if _mic_meter and _mic_meter.running:
		_mic_meter.stop()
		Settings.set_mic_monitor(false)
