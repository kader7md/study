class_name EndScreen
extends CanvasLayer
## "CHAPTER 1 COMPLETE": shown a moment after the train stops at station 5 (the port). A warm cream card with
## a short story line and the run stats (read from Game.stats; in multiplayer the host's stats are synced),
## then "Back to main menu" (Game.return_to_menu) or "Keep exploring" (closes the card).
## Styled with UiTheme (scripts/ui/menu/ui_theme.gd) when it exists, with the same palette as a fallback.

const UI_THEME_PATH := "res://scripts/ui/menu/ui_theme.gd"
const STORY := "The tracker's signal leads past the last pier of the port and out over the water.\nShe is out there somewhere. The train has done its part."
const NEXT := "Chapter 2: The Sea"

## Fallback palette (matches the planned UiTheme: cream and wood panels, ink outline, rust and teal accents).
var cream := Color(0.98, 0.93, 0.82)
var wood := Color(0.55, 0.34, 0.18)
var ink := Color(0.17, 0.12, 0.09)
var rust := Color(0.78, 0.33, 0.16)
var teal := Color(0.16, 0.5, 0.5)

var _backdrop: ColorRect
var _card: PanelContainer
var _values := {}      # stat key -> Label
var _targets := {}     # stat key -> float
var _menu_button: Button
var _explore_button: Button
var _count_t := 0.0


func _ready() -> void:
	layer = 20
	process_mode = Node.PROCESS_MODE_ALWAYS
	name = "EndScreen"
	visible = false
	var ui_theme: Script = load(UI_THEME_PATH) if ResourceLoader.exists(UI_THEME_PATH) else null
	if ui_theme:
		var consts := ui_theme.get_script_constant_map()
		cream = consts.get("CREAM", cream)
		wood = consts.get("WOOD", wood)
		ink = consts.get("INK", ink)
		rust = consts.get("RUST", rust)
		teal = consts.get("TEAL", teal)
	_build(ui_theme)


func _build(ui_theme: Script) -> void:
	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	if ui_theme and ui_theme.has_method("build"):
		root.theme = ui_theme.call("build")
	add_child(root)

	_backdrop = ColorRect.new()
	_backdrop.color = Color(ink.r, ink.g, ink.b, 0.6)
	_backdrop.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.add_child(_backdrop)

	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.add_child(center)

	_card = PanelContainer.new()
	_card.custom_minimum_size = Vector2(760, 0)
	_card.add_theme_stylebox_override("panel", _panel(cream, wood, 6, 22, 14))
	center.add_child(_card)
	var pad := MarginContainer.new()
	for side in ["left", "right"]:
		pad.add_theme_constant_override("margin_" + side, 40)
	pad.add_theme_constant_override("margin_top", 26)
	pad.add_theme_constant_override("margin_bottom", 30)
	_card.add_child(pad)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 10)
	pad.add_child(box)

	var kicker := _label(box, "TRUST ISSUES  ·  THE TRAIN CHASE", 18, rust)
	kicker.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	var title := _label(box, "CHAPTER 1 COMPLETE", 60, ink, 3, Color(1, 1, 1, 0.0))
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_color_override("font_shadow_color", Color(wood.r, wood.g, wood.b, 0.45))
	title.add_theme_constant_override("shadow_offset_x", 0)
	title.add_theme_constant_override("shadow_offset_y", 4)
	var story := _label(box, STORY, 19, ink.lerp(wood, 0.35))
	story.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	story.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	story.custom_minimum_size = Vector2(660, 0)
	var next := _label(box, NEXT, 22, teal)
	next.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER

	var rule := ColorRect.new()
	rule.color = Color(wood.r, wood.g, wood.b, 0.35)
	rule.custom_minimum_size = Vector2(0, 3)
	box.add_child(rule)

	var grid := GridContainer.new()
	grid.columns = 4
	grid.add_theme_constant_override("h_separation", 12)
	grid.add_theme_constant_override("v_separation", 12)
	box.add_child(grid)
	for entry: Array in [["time", "Run time", ""], ["distance", "Distance", ""], ["repairs", "Track rebuilt", "rail"],
			["panels", "Panels refitted", "panel"], ["wheels_lost", "Wheels lost", "wheel"], ["gates", "Gates opened", "key"],
			["gold_found", "Gold found", "gold"]]:
		_stat_card(grid, entry[0], entry[1], entry[2])

	var buttons := HBoxContainer.new()
	buttons.alignment = BoxContainer.ALIGNMENT_CENTER
	buttons.add_theme_constant_override("separation", 18)
	box.add_child(buttons)
	_explore_button = _button(buttons, "Keep exploring", teal)
	_explore_button.pressed.connect(close)
	_menu_button = _button(buttons, "Back to main menu", rust)
	_menu_button.pressed.connect(_on_menu)


func _stat_card(parent: Control, key: String, caption: String, icon_id: String) -> void:
	var card := PanelContainer.new()
	card.custom_minimum_size = Vector2(160, 92)
	card.add_theme_stylebox_override("panel", _panel(cream.darkened(0.06), Color(wood.r, wood.g, wood.b, 0.55), 3, 14, 0))
	parent.add_child(card)
	var v := VBoxContainer.new()
	v.alignment = BoxContainer.ALIGNMENT_CENTER
	v.add_theme_constant_override("separation", 0)
	card.add_child(v)
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 6)
	v.add_child(row)
	var tex: Texture2D = HUD.icon_for(icon_id) if icon_id != "" else null
	if tex:
		var icon := TextureRect.new()
		icon.texture = tex
		icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		icon.custom_minimum_size = Vector2(38, 38)
		row.add_child(icon)
	_values[key] = _label(row, "0", 34, ink)
	var cap := _label(v, caption, 16, ink.lerp(wood, 0.5))
	cap.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER


func _panel(bg: Color, border: Color, border_w: int, radius: int, shadow: int) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = bg
	sb.border_color = border
	sb.set_border_width_all(border_w)
	sb.set_corner_radius_all(radius)
	sb.shadow_color = Color(0, 0, 0, 0.35)
	sb.shadow_size = shadow
	sb.shadow_offset = Vector2(0, shadow * 0.5)
	sb.content_margin_left = 8
	sb.content_margin_right = 8
	sb.content_margin_top = 6
	sb.content_margin_bottom = 6
	return sb


func _label(parent: Control, text: String, size: int, color: Color, outline := 0, outline_color := Color.BLACK) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	if outline > 0:
		l.add_theme_constant_override("outline_size", outline)
		l.add_theme_color_override("font_outline_color", outline_color)
	parent.add_child(l)
	return l


func _button(parent: Control, text: String, color: Color) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(260, 60)
	b.add_theme_font_size_override("font_size", 24)
	b.add_theme_color_override("font_color", cream)
	b.add_theme_color_override("font_hover_color", Color.WHITE)
	b.add_theme_color_override("font_pressed_color", cream)
	var normal := _panel(color, ink, 3, 16, 6)
	var hover := _panel(color.lightened(0.12), ink, 3, 16, 8)
	var pressed := _panel(color.darkened(0.15), ink, 3, 16, 2)
	b.add_theme_stylebox_override("normal", normal)
	b.add_theme_stylebox_override("hover", hover)
	b.add_theme_stylebox_override("pressed", pressed)
	b.add_theme_stylebox_override("focus", hover)
	parent.add_child(b)
	return b


## Shows the card with the given stats (the numbers count up).
func open(stats: Dictionary) -> void:
	for key: String in _values:
		_targets[key] = float(stats.get(key, 0.0))
	_count_t = 0.0
	_set_values(0.0)
	visible = true
	Game.ui_open = true
	_backdrop.modulate.a = 0.0
	_card.pivot_offset = _card.size * 0.5
	_card.scale = Vector2(0.85, 0.85)
	_card.modulate.a = 0.0
	var tween := create_tween().set_parallel()
	tween.tween_property(_backdrop, "modulate:a", 1.0, 0.6)
	tween.tween_property(_card, "modulate:a", 1.0, 0.4).set_delay(0.2)
	tween.tween_property(_card, "scale", Vector2.ONE, 0.55).set_delay(0.2).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	_menu_button.grab_focus.call_deferred()


func is_open() -> bool:
	return visible


func close() -> void:
	visible = false
	Game.ui_open = false


func _on_menu() -> void:
	visible = false
	Game.return_to_menu()


func _process(delta: float) -> void:
	if not visible or _count_t >= 1.0:
		return
	_count_t = minf(_count_t + delta / 1.6, 1.0)
	_set_values(ease(_count_t, 0.4))


func _set_values(k: float) -> void:
	for key: String in _values:
		var v: float = float(_targets.get(key, 0.0)) * k
		var l: Label = _values[key]
		match key:
			"time":
				var secs := int(round(v))
				l.text = "%d:%02d" % [secs / 60, secs % 60]
			"distance":
				l.text = "%.1f km" % (v / 1000.0)
			"gates":
				l.text = "%d / %d" % [int(round(v)), Game.STATION_COUNT]
			_:
				l.text = str(int(round(v)))


static func format_time(seconds: float) -> String:
	var secs := int(round(seconds))
	return "%d:%02d" % [secs / 60, secs % 60]
