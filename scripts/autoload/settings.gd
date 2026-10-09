extends Node
## Player settings (autoload "Settings", registered after Game): controls, graphics, audio, microphone and profile.
## Stored in user://settings.cfg (ConfigFile, sections [controls] [graphics] [audio] [mic] [profile]: name, look = the
## character Appearance code),
## applied at startup and whenever a value changes. A missing or corrupt file falls back to the defaults.
## Also applies the shared UiTheme to the whole game and gives every Button a click and hover sound.
##   Settings.set_value("audio", "music", 0.5)     # applies + saves
##   Settings.changed.connect(func(section, key): ...)

signal changed(section: String, key: String)

const FILE := "settings.cfg"
const PATH := "user://" + FILE
const BUSES := ["Master", "Music", "SFX", "Voice"]
const WINDOW_MODES := ["Windowed", "Borderless fullscreen", "Fullscreen"]
const SHADOW_LEVELS := ["Off", "Low", "Medium", "High"]
const FPS_LIMITS := [30, 60, 120, 144, 0]
const AA_MODES := ["Off", "FXAA", "MSAA 2x", "MSAA 4x"]

const DEFAULTS := {
	"controls": {"mouse_sensitivity": 0.0025, "invert_y": false},
	"graphics": {"window_mode": 0, "vsync": true, "render_scale": 1.0, "shadows": 2, "fov": 80.0, "max_fps": 0, "aa": 1},
	"audio": {"Master": 0.8, "Music": 0.7, "SFX": 0.8, "Voice": 1.0},
	"mic": {"device": "Default", "push_to_talk": true},
	"profile": {"name": "", "look": ""},
}

## Actions added on top of Game.INPUTS (Game registers attack/cancel itself).
const EXTRA_INPUTS := {"push_to_talk": [KEY_V], "pause": [KEY_ESCAPE], "emote": [KEY_B]}

## Default key names used in game texts -> the action they stand for (see hint()).
const HINT_ACTIONS := {
	"E": "interact", "Q": "interact_alt", "G": "drop", "Tab": "inventory", "X": "sabotage_menu", "R": "winch_release",
	"LMB": "attack", "RMB": "cancel", "Esc": "pause", "V": "push_to_talk", "H": "show_help", "B": "emote", "Space": "jump",
	"Shift": "sprint",
}

## Shadow quality presets: [sun shadows, directional atlas size, soft filter quality, max distance].
const SHADOW_PRESETS := [
	[false, 1024, RenderingServer.SHADOW_QUALITY_HARD, 60.0],
	[true, 2048, RenderingServer.SHADOW_QUALITY_SOFT_VERY_LOW, 90.0],
	[true, 4096, RenderingServer.SHADOW_QUALITY_SOFT_LOW, 150.0],
	[true, 8192, RenderingServer.SHADOW_QUALITY_SOFT_HIGH, 220.0],
]

var path := PATH
var cfg := ConfigFile.new()
## True when DisplayServer is headless (tests, servers): window and mouse calls are skipped.
var headless := false

var player_name: String:
	get:
		var n: String = str(get_value("profile", "name", ""))
		return n if n.strip_edges() != "" else "Player"  # = Net.DEFAULT_NAME
	set(value):
		set_value("profile", "name", value.strip_edges().left(Net.NAME_MAX))
var mouse_sensitivity: float:
	get:
		return float(get_value("controls", "mouse_sensitivity", 0.0025))
	set(value):
		set_value("controls", "mouse_sensitivity", value)
var invert_y: bool:
	get:
		return bool(get_value("controls", "invert_y", false))
	set(value):
		set_value("controls", "invert_y", value)
var fov: float:
	get:
		return float(get_value("graphics", "fov", 80.0))
	set(value):
		set_value("graphics", "fov", value)
var mic_device: String:
	get:
		return str(get_value("mic", "device", "Default"))
	set(value):
		set_value("mic", "device", value)

## Default bindings per action as event descriptors ("key:<physical keycode>" / "mouse:<button>").
var default_bindings: Dictionary = {}
var _hint_re: RegEx

var _save_queued := false
var _loading := false
var _click: AudioStreamPlayer
var _hover: AudioStreamPlayer
var _last_hover_ms := 0


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	headless = DisplayServer.get_name() == "headless"
	_register_actions()
	_collect_defaults()
	path = Game.save_dir + FILE  # user://test/ when started from a test scene (see Game.save_dir)
	load_settings()
	var theme := UiTheme.build()
	get_tree().root.theme = theme
	# Controls under a CanvasLayer (HUD, menus) don't inherit the window theme, so the default theme gets it too.
	ThemeDB.get_default_theme().merge_with(theme)
	ThemeDB.get_default_theme().default_font = theme.default_font
	ThemeDB.get_default_theme().default_font_size = theme.default_font_size
	_build_ui_sounds()
	set_mic_monitor(false)  # never echo the microphone unless the Settings test toggle asks for it
	get_tree().node_added.connect(_on_node_added)


## F11 toggles fullscreen anywhere (saved like the Graphics tab setting).
func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo and (event as InputEventKey).keycode == KEY_F11:
		var fs := int(get_value("graphics", "window_mode")) != 0
		set_value("graphics", "window_mode", 0 if fs else 1)
		get_viewport().set_input_as_handled()


# --- Public API ---------------------------------------------------------------------------------

func get_value(section: String, key: String, default: Variant = null) -> Variant:
	if cfg.has_section_key(section, key):
		return cfg.get_value(section, key)
	if default == null and DEFAULTS.has(section) and DEFAULTS[section].has(key):
		return DEFAULTS[section][key]
	return default


## Stores a value, applies it right away and saves (once per frame at most).
func set_value(section: String, key: String, value: Variant) -> void:
	cfg.set_value(section, key, value)
	_apply(section, key)
	changed.emit(section, key)
	_queue_save()


## Keeps settings.cfg in `dir` from now on (Game.use_save_dir) and loads it from there.
func use_dir(dir: String) -> void:
	if _save_queued:
		save()  # pending changes belong to the old file
	path = dir + FILE
	load_settings()


func save() -> void:
	_save_queued = false
	var err := cfg.save(path)
	if err != OK:
		push_warning("Settings: could not save %s (%s)" % [path, error_string(err)])


## Loads the file (or the defaults) and applies everything.
func load_settings() -> void:
	cfg = ConfigFile.new()
	if FileAccess.file_exists(path):
		var err := cfg.load(path)
		if err != OK:
			push_warning("Settings: %s is unreadable (%s), using defaults" % [path, error_string(err)])
			cfg = ConfigFile.new()
	_validate()
	_loading = true
	apply_all()
	_loading = false


func apply_all() -> void:
	for section: String in DEFAULTS:
		for key: String in DEFAULTS[section]:
			_apply(section, key)
	_apply_bindings()


## Restores every binding to the defaults (Game.INPUTS + attack/cancel + push_to_talk/pause).
func reset_controls() -> void:
	for key in _binding_keys():
		cfg.erase_section_key("controls", key)
	for action: String in default_bindings:
		_set_events(action, default_bindings[action])
	changed.emit("controls", "*")
	_queue_save()


func reset_section(section: String) -> void:
	if section == "controls":
		cfg.set_value("controls", "mouse_sensitivity", DEFAULTS.controls.mouse_sensitivity)
		cfg.set_value("controls", "invert_y", false)
		reset_controls()
	elif cfg.has_section(section):
		cfg.erase_section(section)
	for key: String in DEFAULTS.get(section, {}):
		_apply(section, key)
		changed.emit(section, key)
	_queue_save()


# --- Controls -----------------------------------------------------------------------------------

## Actions the player may rebind (everything except Godot's built-in ui_* actions).
func rebindable_actions() -> Array[String]:
	var list: Array[String] = []
	for a: StringName in InputMap.get_actions():
		if not String(a).begins_with("ui_"):
			list.append(String(a))
	return list


## Replaces the action's bindings with one event and saves it.
func rebind(action: String, event: InputEvent) -> void:
	var desc := event_to_desc(event)
	if desc == "":
		return
	_set_events(action, [desc])
	cfg.set_value("controls", "bind_" + action, [desc])
	changed.emit("controls", action)
	_queue_save()


## Other actions that share this event (only a real conflict when both are used in the same context).
func conflicts(action: String) -> Array[String]:
	var out: Array[String] = []
	var mine := action_descs(action)
	for other in rebindable_actions():
		if other == action:
			continue
		for d in action_descs(other):
			if d in mine:
				out.append(other)
				break
	return out


func action_descs(action: String) -> PackedStringArray:
	var out := PackedStringArray()
	if InputMap.has_action(action):
		for ev in InputMap.action_get_events(action):
			var d := event_to_desc(ev)
			if d != "":
				out.append(d)
	return out


## Readable name of the action's first binding, e.g. "Space", "E", "Mouse Left".
func binding_text(action: String) -> String:
	var descs := action_descs(action)
	if descs.is_empty():
		return "Unbound"
	return desc_to_text(descs[0])


## Short label of the action's current key for on-screen hints: "E", "LMB", "Esc", "Tab"...
func key_label(action: String) -> String:
	var descs := action_descs(action)
	if descs.is_empty():
		return "unbound"
	var t := desc_to_text(descs[0])
	match t:
		"Mouse Left": return "LMB"
		"Mouse Right": return "RMB"
		"Mouse Middle": return "MMB"
		"Escape": return "Esc"
	return t


## Hints in game texts are written with the default keys ("[E]", "[Q]", "[Tab]", "[LMB]", "[E / Esc]").
## This puts the player's current bindings in their place.
func hint(text: String) -> String:
	if not "[" in text:
		return text
	if _hint_re == null:
		_hint_re = RegEx.create_from_string("\\[([^\\[\\]]{1,12})\\]")
	var out := ""
	var last := 0
	for m in _hint_re.search_all(text):
		var parts := m.get_string(1).split(" / ")
		var changed_any := false
		for i in parts.size():
			var action: String = HINT_ACTIONS.get(parts[i].strip_edges(), "")
			if action != "":
				parts[i] = key_label(action)
				changed_any = true
		if changed_any:
			out += text.substr(last, m.get_start() - last) + "[" + " / ".join(parts) + "]"
			last = m.get_end()
	return out + text.substr(last)


static func event_to_desc(ev: InputEvent) -> String:
	if ev is InputEventKey:
		var k := ev as InputEventKey
		var code := k.physical_keycode if k.physical_keycode != KEY_NONE else k.keycode
		return "key:%d" % code if code != KEY_NONE else ""
	if ev is InputEventMouseButton:
		return "mouse:%d" % (ev as InputEventMouseButton).button_index
	return ""


static func desc_to_event(desc: String) -> InputEvent:
	var parts := desc.split(":")
	if parts.size() != 2 or not parts[1].is_valid_int():
		return null
	if parts[0] == "key":
		var k := InputEventKey.new()
		k.physical_keycode = int(parts[1]) as Key
		return k
	if parts[0] == "mouse":
		var m := InputEventMouseButton.new()
		m.button_index = int(parts[1]) as MouseButton
		return m
	return null


static func desc_to_text(desc: String) -> String:
	var ev := desc_to_event(desc)
	if ev is InputEventKey:
		var code := (ev as InputEventKey).physical_keycode
		var name := OS.get_keycode_string(code)
		if DisplayServer.get_name() != "headless":
			var local := DisplayServer.keyboard_get_keycode_from_physical(code)
			if local != KEY_NONE:
				name = OS.get_keycode_string(local)
		return name if name != "" else "Key %d" % code
	if ev is InputEventMouseButton:
		match (ev as InputEventMouseButton).button_index:
			MOUSE_BUTTON_LEFT: return "Mouse Left"
			MOUSE_BUTTON_RIGHT: return "Mouse Right"
			MOUSE_BUTTON_MIDDLE: return "Mouse Middle"
			MOUSE_BUTTON_WHEEL_UP: return "Wheel Up"
			MOUSE_BUTTON_WHEEL_DOWN: return "Wheel Down"
			MOUSE_BUTTON_XBUTTON1: return "Mouse 4"
			MOUSE_BUTTON_XBUTTON2: return "Mouse 5"
		return "Mouse %d" % (ev as InputEventMouseButton).button_index
	return "?"


func _register_actions() -> void:
	for action: String in EXTRA_INPUTS:
		if InputMap.has_action(action):
			continue
		InputMap.add_action(action)
		for key: Key in EXTRA_INPUTS[action]:
			var ev := InputEventKey.new()
			ev.physical_keycode = key
			InputMap.action_add_event(action, ev)


func _collect_defaults() -> void:
	default_bindings.clear()
	for action: String in Game.INPUTS:
		var list: Array[String] = []
		for key: Key in Game.INPUTS[action]:
			list.append("key:%d" % key)
		default_bindings[action] = list
	default_bindings["attack"] = ["mouse:%d" % MOUSE_BUTTON_LEFT]
	default_bindings["cancel"] = ["mouse:%d" % MOUSE_BUTTON_RIGHT]
	default_bindings["climb"] = ["mouse:%d" % MOUSE_BUTTON_RIGHT]
	for action: String in EXTRA_INPUTS:
		var list: Array[String] = []
		for key: Key in EXTRA_INPUTS[action]:
			list.append("key:%d" % key)
		default_bindings[action] = list
	# Actions added later by other systems keep whatever they registered as their default
	for action in rebindable_actions():
		if not default_bindings.has(action):
			var list: Array[String] = []
			for d in action_descs(action):
				list.append(d)
			default_bindings[action] = list


func _binding_keys() -> Array[String]:
	var out: Array[String] = []
	if cfg.has_section("controls"):
		for key in cfg.get_section_keys("controls"):
			if key.begins_with("bind_"):
				out.append(key)
	return out


func _apply_bindings() -> void:
	for key in _binding_keys():
		var action := key.trim_prefix("bind_")
		var value: Variant = cfg.get_value("controls", key)
		if not InputMap.has_action(action) or not (value is Array):
			continue
		# Tab used to open the sabotage menu; it is the inventory now (the sabotage menu moved to X)
		if action == "sabotage_menu" and (value as Array).has("key:%d" % KEY_TAB):
			cfg.erase_section_key("controls", key)
			continue
		var descs: Array[String] = []
		for d: Variant in value:
			if d is String and desc_to_event(d) != null:
				descs.append(d)
		if not descs.is_empty():
			_set_events(action, descs)


func _set_events(action: String, descs: Array) -> void:
	if not InputMap.has_action(action):
		InputMap.add_action(action)
	InputMap.action_erase_events(action)
	for d: Variant in descs:
		var ev := desc_to_event(str(d))
		if ev:
			InputMap.action_add_event(action, ev)


# --- Applying values ----------------------------------------------------------------------------

## Fixes wrong types or out-of-range values from a hand-edited file.
func _validate() -> void:
	for section: String in DEFAULTS:
		for key: String in DEFAULTS[section]:
			if not cfg.has_section_key(section, key):
				continue
			var def: Variant = DEFAULTS[section][key]
			var v: Variant = cfg.get_value(section, key)
			var ok := typeof(v) == typeof(def) or (typeof(def) == TYPE_FLOAT and typeof(v) == TYPE_INT)
			if not ok:
				cfg.erase_section_key(section, key)
	var g := "graphics"
	cfg.set_value(g, "window_mode", clampi(int(get_value(g, "window_mode")), 0, WINDOW_MODES.size() - 1))
	cfg.set_value(g, "shadows", clampi(int(get_value(g, "shadows")), 0, SHADOW_LEVELS.size() - 1))
	cfg.set_value(g, "aa", clampi(int(get_value(g, "aa")), 0, AA_MODES.size() - 1))
	cfg.set_value(g, "render_scale", clampf(float(get_value(g, "render_scale")), 0.5, 1.0))
	cfg.set_value(g, "fov", clampf(float(get_value(g, "fov")), 60.0, 110.0))
	cfg.set_value("controls", "mouse_sensitivity", clampf(mouse_sensitivity, 0.0003, 0.01))
	for bus: String in BUSES:
		cfg.set_value("audio", bus, clampf(float(get_value("audio", bus)), 0.0, 1.0))


func _apply(section: String, key: String) -> void:
	match section:
		"graphics":
			_apply_graphics(key)
		"audio":
			_apply_bus(key)
		"mic":
			if key == "device":
				_apply_mic_device()


func _apply_graphics(key: String) -> void:
	var v: Variant = get_value("graphics", key)
	var root := get_tree().root
	match key:
		"window_mode":
			if headless:
				return
			match int(v):
				0:
					DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
					DisplayServer.window_set_flag(DisplayServer.WINDOW_FLAG_BORDERLESS, false)
				1:
					DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN)
				2:
					DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_EXCLUSIVE_FULLSCREEN)
		"vsync":
			var mode := DisplayServer.VSYNC_ENABLED if bool(v) else DisplayServer.VSYNC_DISABLED
			# V-Sync is on by default (project setting), so startup only needs to act when it is off
			var startup_default := _loading and bool(v)
			if not headless and not startup_default and DisplayServer.window_get_vsync_mode() != mode:
				DisplayServer.window_set_vsync_mode(mode)
		"render_scale":
			root.scaling_3d_scale = clampf(float(v), 0.5, 1.0)
		"shadows":
			_apply_shadows()
		"max_fps":
			Engine.max_fps = int(v)
		"aa":
			var mode := int(v)
			# FXAA needs Forward+ / Mobile; the Compatibility renderer gets 2x MSAA instead
			if RenderingServer.get_current_rendering_method() == "gl_compatibility":
				mode = 2 if mode == 1 else mode
			else:
				root.screen_space_aa = Viewport.SCREEN_SPACE_AA_FXAA if mode == 1 else Viewport.SCREEN_SPACE_AA_DISABLED
			root.msaa_3d = [Viewport.MSAA_DISABLED, Viewport.MSAA_DISABLED, Viewport.MSAA_2X, Viewport.MSAA_4X][clampi(mode, 0, 3)]


func _apply_shadows() -> void:
	var level := clampi(int(get_value("graphics", "shadows")), 0, SHADOW_PRESETS.size() - 1)
	var preset: Array = SHADOW_PRESETS[level]
	RenderingServer.directional_shadow_atlas_set_size(int(preset[1]), true)
	RenderingServer.directional_soft_shadow_filter_set_quality(preset[2])
	RenderingServer.positional_soft_shadow_filter_set_quality(preset[2])
	get_tree().root.positional_shadow_atlas_size = int(preset[1]) / 2 if level > 0 else 0
	for light in get_tree().root.find_children("*", "DirectionalLight3D", true, false):
		_shadow_light(light as DirectionalLight3D)


## Sun lights keep their own "wants shadows" flag; the quality level switches them on or off.
func _shadow_light(light: DirectionalLight3D) -> void:
	if not light.has_meta("settings_shadow"):
		light.set_meta("settings_shadow", light.shadow_enabled)
		light.set_meta("settings_shadow_distance", light.directional_shadow_max_distance)
	var level := clampi(int(get_value("graphics", "shadows")), 0, SHADOW_PRESETS.size() - 1)
	var preset: Array = SHADOW_PRESETS[level]
	light.shadow_enabled = bool(light.get_meta("settings_shadow")) and bool(preset[0])
	light.directional_shadow_max_distance = minf(float(light.get_meta("settings_shadow_distance")), float(preset[3]))


func _apply_bus(bus_name: String) -> void:
	var idx := AudioServer.get_bus_index(bus_name)
	if idx < 0:
		return
	var v := clampf(float(get_value("audio", bus_name, 0.8)), 0.0, 1.0)
	AudioServer.set_bus_mute(idx, v <= 0.001)
	AudioServer.set_bus_volume_db(idx, linear_to_db(maxf(v, 0.0001)))


func _apply_mic_device() -> void:
	var dev := mic_device
	if dev == "" or not dev in AudioServer.get_input_device_list():
		dev = "Default"
	if AudioServer.input_device != dev and dev in AudioServer.get_input_device_list():
		AudioServer.input_device = dev


## "Hear yourself": unmutes the Mic bus (it sends to Master). Off by default so there is no echo.
func set_mic_monitor(on: bool) -> void:
	var idx := AudioServer.get_bus_index("Mic")
	if idx >= 0:
		AudioServer.set_bus_mute(idx, not on)


func _on_node_added(node: Node) -> void:
	if node is DirectionalLight3D:
		_shadow_light.call_deferred(node)
	elif node is BaseButton:
		var b := node as BaseButton
		if not b.has_meta("no_ui_sound"):
			b.mouse_entered.connect(_on_button_hover.bind(b))
			b.pressed.connect(play_click)


func _queue_save() -> void:
	if not _save_queued:
		_save_queued = true
		save.call_deferred()


# --- UI sounds (generated, SFX bus) ----------------------------------------------------------

func play_click() -> void:
	if _click and _click.is_inside_tree():
		_click.play()


func play_hover() -> void:
	if _hover and _hover.is_inside_tree():
		_hover.play()


func _on_button_hover(b: BaseButton) -> void:
	if b.disabled:
		return
	var now := Time.get_ticks_msec()
	if now - _last_hover_ms > 60:
		_last_hover_ms = now
		play_hover()


func _build_ui_sounds() -> void:
	_click = AudioStreamPlayer.new()
	_click.stream = _tone([520.0, 780.0], 0.07, 0.5, 3.0)
	_click.bus = "SFX" if AudioServer.get_bus_index("SFX") >= 0 else "Master"
	add_child(_click)
	_hover = AudioStreamPlayer.new()
	_hover.stream = _tone([880.0], 0.035, 0.18, 6.0)
	_hover.bus = _click.bus
	add_child(_hover)


## A short wooden "tock": a couple of sine partials with a fast exponential decay and a tiny noise click.
static func _tone(freqs: Array, length: float, volume: float, decay: float) -> AudioStreamWAV:
	var rate := 22050
	var n := int(rate * length)
	var data := PackedByteArray()
	data.resize(n * 2)
	var rng := RandomNumberGenerator.new()
	rng.seed = 11
	for i in n:
		var t := float(i) / rate
		var env := exp(-t / length * decay) * minf(1.0, t * 2000.0)
		var s := 0.0
		for k in freqs.size():
			var f: float = freqs[k]
			s += sin(TAU * f * t) / (k + 1)
		if t < 0.004:
			s += rng.randf_range(-0.6, 0.6)
		var v := clampi(int(s * env * volume * 32767.0 * 0.6), -32768, 32767)
		data.encode_s16(i * 2, v)
	var wav := AudioStreamWAV.new()
	wav.format = AudioStreamWAV.FORMAT_16_BITS
	wav.mix_rate = rate
	wav.stereo = false
	wav.data = data
	return wav
