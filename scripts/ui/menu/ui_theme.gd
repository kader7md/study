class_name UiTheme
extends RefCounted
## The one warm, chunky UI theme for every menu, HUD bar and panel ("cosy workshop" look):
## cream paper and varnished wood panels with a dark ink outline, big rounded corners, a soft drop shadow,
## a bold outlined font and honey-coloured hover states. Built in code (no image files needed):
##   get_tree().root.theme = UiTheme.build()      (Settings does this at startup)
## Type variations: TitleLabel, HeaderLabel, HudLabel, HudSmall, NoteLabel, MutedLabel, BigButton, AccentButton,
## DangerButton, TabButton, WoodPanel, PaperPanel, DarkPanel, ChipPanel, NotePanel.

# --- Palette ----------------------------------------------------------------------------------
const CREAM := Color("f7ecd6")
const CREAM_DARK := Color("e9d6b1")
const PAPER := Color("fff6e0")
const WOOD := Color("9a6a42")
const WOOD_DARK := Color("6b4428")
const WOOD_LIGHT := Color("b98a5c")
const INK := Color("2a1c13")
const INK_SOFT := Color("5a4334")
const RUST := Color("cf5b2e")
const RUST_DARK := Color("a5431f")
const TEAL := Color("2e8c84")
const TEAL_DARK := Color("1f6660")
const HONEY := Color("ffd27a")
const HONEY_DARK := Color("f0b452")
const WARN := Color("e8a21f")
const DANGER := Color("c8382a")
## Train and journey colours (HUD bars). Keep them distinct: green / yellow / red / blue / orange.
const BODY_GREEN := Color("62b84a")
const WHEEL_YELLOW := Color("f5c62c")
const ENGINE_RED := Color("de4a33")
const CHASSIS_BLUE := Color("3f83d6")
const JOURNEY := Color("f08b2a")
const HEALTH := Color("e2574c")
const FROST := Color("8fd3f4")
const SHADOW := Color(0.12, 0.07, 0.03, 0.45)

const RADIUS := 16
const OUTLINE := 4

## Text uses the engine's built-in Open Sans (emboldened, very readable); the logo uses Kenney Rocket (CC0).
const FONT_LOGO_PATH := "res://assets/fonts/kenney_rocket.ttf"

static var _cache: Theme
static var _fonts := {}


## Builds (once) and returns the shared theme.
static func build() -> Theme:
	if _cache:
		return _cache
	var t := Theme.new()
	t.default_font = body_font()
	t.default_font_size = 22
	_labels(t)
	_panels(t)
	_buttons(t)
	_option_and_popup(t)
	_progress(t)
	_sliders(t)
	_checks(t)
	_tabs(t)
	_line_edit(t)
	_scrollbars(t)
	_misc(t)
	_cache = t
	return t


# --- Fonts ------------------------------------------------------------------------------------

## Chunky, readable body font (Open Sans SemiBold, emboldened) with a system fallback for symbols like ❄ ⚠.
static func body_font(bold := true) -> Font:
	return _font("", 0.55 if bold else 0.15, 0)


static func narrow_font() -> Font:
	return _font("", 0.3, 0)


## Heavy font for titles and headers (drawn with a thick ink outline).
static func title_font() -> Font:
	return _font("", 1.1, 1)


## Blocky display font for the TRUST ISSUES logo only (Kenney Rocket, CC0).
static func logo_font() -> Font:
	return _font(FONT_LOGO_PATH, 0.0, 3)


static func _font(path: String, embolden: float, spacing: int) -> Font:
	var key := "%s|%f|%d" % [path, embolden, spacing]
	if _fonts.has(key):
		return _fonts[key]
	var fv := FontVariation.new()
	var base: Font = null
	if path != "" and ResourceLoader.exists(path):
		base = load(path)
		var fallback := SystemFont.new()
		fallback.font_names = PackedStringArray(["Noto Sans Symbols 2", "Noto Sans Symbols", "DejaVu Sans", "sans-serif"])
		var fallbacks: Array[Font] = [ThemeDB.fallback_font, fallback]
		base.fallbacks = fallbacks
	else:
		base = ThemeDB.fallback_font
	fv.base_font = base
	fv.variation_embolden = embolden
	fv.spacing_glyph = spacing
	_fonts[key] = fv
	return fv


# --- Public helpers ---------------------------------------------------------------------------

## A rounded panel style with an ink outline and a soft drop shadow.
static func panel(color: Color = CREAM, radius: int = RADIUS, outline: int = OUTLINE, shadow := true) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = color
	sb.set_corner_radius_all(radius)
	sb.set_border_width_all(outline)
	sb.border_color = INK
	sb.corner_detail = 10
	sb.anti_aliasing = true
	if shadow:
		sb.shadow_color = SHADOW
		sb.shadow_size = 6
		sb.shadow_offset = Vector2(0, 5)
	sb.set_content_margin_all(radius + 2)
	return sb


## A big outlined title label (cream letters, ink outline, warm shadow).
static func title_label(text: String, size: int = 84) -> Label:
	var l := Label.new()
	l.text = text
	l.theme_type_variation = &"TitleLabel"
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_constant_override("outline_size", maxi(8, size / 6))
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	return l


## A small filled rounded box (bars, chips, pips). No outline unless asked.
static func flat(color: Color, radius := 8, outline := 0, outline_color: Color = INK) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = color
	sb.set_corner_radius_all(radius)
	sb.corner_detail = 8
	if outline > 0:
		sb.set_border_width_all(outline)
		sb.border_color = outline_color
	return sb


## Background + fill styles for a coloured HUD bar. The fill gets a lighter top edge for a glossy look.
static func style_bar(bar: ProgressBar, color: Color, radius := 9) -> void:
	var bg := flat(Color(INK, 0.88), radius, 3, INK)
	bg.set_content_margin_all(0)
	var fill := flat(color, radius - 2)
	fill.border_width_top = 4
	fill.border_color = color.lightened(0.35)
	fill.border_blend = true
	fill.expand_margin_left = -3
	fill.expand_margin_right = -3
	fill.expand_margin_top = -3
	fill.expand_margin_bottom = -3
	bar.add_theme_stylebox_override("background", bg)
	bar.add_theme_stylebox_override("fill", fill)
	bar.show_percentage = false


# --- Theme parts ------------------------------------------------------------------------------

static func _labels(t: Theme) -> void:
	t.set_color("font_color", "Label", INK)
	t.set_color("font_outline_color", "Label", Color(0, 0, 0, 0))
	t.set_constant("outline_size", "Label", 0)
	t.set_constant("line_spacing", "Label", 2)

	t.set_type_variation("TitleLabel", "Label")
	t.set_font("font", "TitleLabel", title_font())
	t.set_font_size("font_size", "TitleLabel", 84)
	t.set_color("font_color", "TitleLabel", CREAM)
	t.set_color("font_outline_color", "TitleLabel", INK)
	t.set_constant("outline_size", "TitleLabel", 16)
	t.set_color("font_shadow_color", "TitleLabel", Color(INK, 0.55))
	t.set_constant("shadow_offset_x", "TitleLabel", 0)
	t.set_constant("shadow_offset_y", "TitleLabel", 8)
	t.set_constant("shadow_outline_size", "TitleLabel", 16)

	t.set_type_variation("HeaderLabel", "Label")
	t.set_font_size("font_size", "HeaderLabel", 24)
	t.set_font("font", "HeaderLabel", _font("", 0.95, 1))
	t.set_color("font_color", "HeaderLabel", RUST_DARK)

	t.set_type_variation("MutedLabel", "Label")
	t.set_font_size("font_size", "MutedLabel", 18)
	t.set_color("font_color", "MutedLabel", INK_SOFT)
	t.set_font("font", "MutedLabel", body_font(false))

	# Labels drawn straight over the 3D world: cream with a thick ink outline
	t.set_type_variation("HudLabel", "Label")
	t.set_font_size("font_size", "HudLabel", 20)
	t.set_color("font_color", "HudLabel", CREAM)
	t.set_color("font_outline_color", "HudLabel", INK)
	t.set_constant("outline_size", "HudLabel", 8)
	t.set_color("font_shadow_color", "HudLabel", Color(0, 0, 0, 0.35))
	t.set_constant("shadow_offset_y", "HudLabel", 2)

	t.set_type_variation("HudSmall", "Label")
	t.set_font_size("font_size", "HudSmall", 16)
	t.set_color("font_color", "HudSmall", CREAM)
	t.set_color("font_outline_color", "HudSmall", INK)
	t.set_constant("outline_size", "HudSmall", 6)

	# Handwritten-ish note text (objective card)
	t.set_type_variation("NoteLabel", "Label")
	t.set_font("font", "NoteLabel", narrow_font())
	t.set_font_size("font_size", "NoteLabel", 20)
	t.set_color("font_color", "NoteLabel", INK)

	t.set_color("default_color", "RichTextLabel", INK)
	t.set_font("normal_font", "RichTextLabel", body_font(false))
	t.set_font("bold_font", "RichTextLabel", body_font(true))
	t.set_font_size("normal_font_size", "RichTextLabel", 20)
	t.set_font_size("bold_font_size", "RichTextLabel", 20)


static func _panels(t: Theme) -> void:
	t.set_stylebox("panel", "PanelContainer", panel(CREAM))
	t.set_stylebox("panel", "Panel", panel(CREAM))

	t.set_type_variation("WoodPanel", "PanelContainer")
	var wood := panel(WOOD)
	wood.border_width_top = 5
	t.set_stylebox("panel", "WoodPanel", wood)

	t.set_type_variation("PaperPanel", "PanelContainer")
	var paper := panel(PAPER, 10, 3)
	paper.set_content_margin_all(14)
	t.set_stylebox("panel", "PaperPanel", paper)

	t.set_type_variation("DarkPanel", "PanelContainer")
	var dark := panel(Color(INK, 0.78), 14, 3, false)
	dark.border_color = Color(WOOD_DARK, 0.9)
	dark.set_content_margin_all(10)
	t.set_stylebox("panel", "DarkPanel", dark)

	# Small rounded chips (inventory counts, tool slots)
	t.set_type_variation("ChipPanel", "PanelContainer")
	var chip := panel(CREAM, 12, 3, false)
	chip.shadow_color = Color(0, 0, 0, 0.3)
	chip.shadow_size = 3
	chip.shadow_offset = Vector2(0, 3)
	chip.content_margin_left = 6
	chip.content_margin_right = 12
	chip.content_margin_top = 4
	chip.content_margin_bottom = 4
	t.set_stylebox("panel", "ChipPanel", chip)

	# Pinned paper note (objective)
	t.set_type_variation("NotePanel", "PanelContainer")
	var note := panel(Color("fff3c4"), 6, 3)
	note.content_margin_left = 16
	note.content_margin_right = 16
	note.content_margin_top = 20
	note.content_margin_bottom = 12
	t.set_stylebox("panel", "NotePanel", note)


static func _button_box(bg: Color, lip: int, shift: int = 0) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = bg
	sb.set_corner_radius_all(14)
	sb.corner_detail = 10
	sb.set_border_width_all(3)
	sb.border_width_bottom = lip
	sb.border_color = INK
	sb.content_margin_left = 22
	sb.content_margin_right = 22
	sb.content_margin_top = 8 + shift
	sb.content_margin_bottom = 8 - shift
	return sb


static func _button_set(t: Theme, type: String, base: Color, hover: Color, pressed: Color, text: Color, hover_text: Color) -> void:
	t.set_stylebox("normal", type, _button_box(base, 8))
	t.set_stylebox("hover", type, _button_box(hover, 8))
	t.set_stylebox("pressed", type, _button_box(pressed, 4, 3))
	t.set_stylebox("hover_pressed", type, _button_box(pressed, 4, 3))
	var dis := _button_box(Color(base, 0.45), 5)
	dis.border_color = Color(INK, 0.4)
	t.set_stylebox("disabled", type, dis)
	var focus := StyleBoxFlat.new()
	focus.draw_center = false
	focus.set_corner_radius_all(18)
	focus.set_border_width_all(3)
	focus.border_color = TEAL
	focus.expand_margin_left = 5
	focus.expand_margin_right = 5
	focus.expand_margin_top = 5
	focus.expand_margin_bottom = 5
	t.set_stylebox("focus", type, focus)
	t.set_color("font_color", type, text)
	t.set_color("font_hover_color", type, hover_text)
	t.set_color("font_pressed_color", type, hover_text)
	t.set_color("font_hover_pressed_color", type, hover_text)
	t.set_color("font_focus_color", type, text)
	t.set_color("font_disabled_color", type, Color(text, 0.45))
	t.set_color("icon_normal_color", type, Color.WHITE)
	t.set_constant("h_separation", type, 10)
	t.set_constant("outline_size", type, 0)


static func _buttons(t: Theme) -> void:
	_button_set(t, "Button", CREAM, HONEY, HONEY_DARK, INK, INK)
	t.set_font_size("font_size", "Button", 22)
	t.set_font("font", "Button", _font("", 0.75, 0))

	t.set_type_variation("BigButton", "Button")
	t.set_font_size("font_size", "BigButton", 30)
	t.set_font("font", "BigButton", _font("", 1.0, 1))
	for state in ["normal", "hover", "pressed", "hover_pressed", "disabled"]:
		var sb: StyleBoxFlat = t.get_stylebox(state, "Button").duplicate()
		sb.content_margin_top += 6
		sb.content_margin_bottom += 6
		sb.content_margin_left = 30
		sb.content_margin_right = 30
		sb.set_corner_radius_all(18)
		t.set_stylebox(state, "BigButton", sb)

	t.set_type_variation("AccentButton", "Button")
	_button_set(t, "AccentButton", RUST, Color("e87a45"), RUST_DARK, CREAM, PAPER)
	t.set_color("font_outline_color", "AccentButton", INK)
	t.set_constant("outline_size", "AccentButton", 6)
	t.set_font_size("font_size", "AccentButton", 30)
	t.set_font("font", "AccentButton", _font("", 1.0, 1))
	for state in ["normal", "hover", "pressed", "hover_pressed", "disabled"]:
		var sb: StyleBoxFlat = t.get_stylebox(state, "AccentButton")
		sb.content_margin_top += 6
		sb.content_margin_bottom += 6
		sb.content_margin_left = 30
		sb.content_margin_right = 30
		sb.set_corner_radius_all(18)

	t.set_type_variation("DangerButton", "Button")
	_button_set(t, "DangerButton", Color("e9c7a8"), Color("f08a6e"), DANGER, INK, PAPER)

	# Small flat button used for key binds and toggles in rows
	t.set_type_variation("KeyButton", "Button")
	_button_set(t, "KeyButton", PAPER, HONEY, HONEY_DARK, INK, INK)
	t.set_font_size("font_size", "KeyButton", 19)
	for state in ["normal", "hover", "pressed", "hover_pressed", "disabled"]:
		var sb: StyleBoxFlat = t.get_stylebox(state, "KeyButton")
		sb.content_margin_left = 12
		sb.content_margin_right = 12
		sb.content_margin_top = 4 + (2 if state.contains("pressed") else 0)
		sb.content_margin_bottom = 4
		sb.set_corner_radius_all(10)

	t.set_stylebox("normal", "LinkButton", StyleBoxEmpty.new())
	t.set_color("font_color", "LinkButton", TEAL_DARK)


static func _option_and_popup(t: Theme) -> void:
	_button_set(t, "OptionButton", PAPER, HONEY, HONEY_DARK, INK, INK)
	for state in ["normal", "hover", "pressed", "hover_pressed", "disabled"]:
		var sb: StyleBoxFlat = t.get_stylebox(state, "OptionButton")
		sb.content_margin_left = 14
		sb.content_margin_right = 40
		sb.content_margin_top = 5 + (2 if state.contains("pressed") else 0)
		sb.content_margin_bottom = 5
		sb.set_corner_radius_all(10)
	t.set_icon("arrow", "OptionButton", _arrow_texture(18, INK))
	t.set_constant("arrow_margin", "OptionButton", 12)
	t.set_font_size("font_size", "OptionButton", 20)

	var pop := panel(PAPER, 12, 3)
	pop.set_content_margin_all(8)
	t.set_stylebox("panel", "PopupMenu", pop)
	var hov := flat(HONEY, 8)
	hov.set_content_margin_all(4)
	t.set_stylebox("hover", "PopupMenu", hov)
	t.set_color("font_color", "PopupMenu", INK)
	t.set_color("font_hover_color", "PopupMenu", INK)
	t.set_color("font_disabled_color", "PopupMenu", Color(INK, 0.4))
	t.set_font_size("font_size", "PopupMenu", 20)
	t.set_constant("v_separation", "PopupMenu", 10)
	t.set_constant("item_start_padding", "PopupMenu", 10)
	t.set_constant("item_end_padding", "PopupMenu", 10)
	var check := _check_texture(22, false, false)
	var checked := _check_texture(22, true, false)
	t.set_icon("radio_unchecked", "PopupMenu", _check_texture(22, false, true))
	t.set_icon("radio_checked", "PopupMenu", _check_texture(22, true, true))
	t.set_icon("unchecked", "PopupMenu", check)
	t.set_icon("checked", "PopupMenu", checked)

	t.set_stylebox("panel", "TooltipPanel", panel(PAPER, 10, 3, false))
	t.set_color("font_color", "TooltipLabel", INK)
	t.set_font_size("font_size", "TooltipLabel", 18)


static func _progress(t: Theme) -> void:
	var bg := flat(Color(INK, 0.85), 9, 3, INK)
	var fill := flat(TEAL, 7)
	fill.expand_margin_left = -3
	fill.expand_margin_right = -3
	fill.expand_margin_top = -3
	fill.expand_margin_bottom = -3
	t.set_stylebox("background", "ProgressBar", bg)
	t.set_stylebox("fill", "ProgressBar", fill)
	t.set_color("font_color", "ProgressBar", CREAM)
	t.set_color("font_outline_color", "ProgressBar", INK)
	t.set_constant("outline_size", "ProgressBar", 4)


static func _sliders(t: Theme) -> void:
	var track := flat(WOOD_DARK, 8, 3, INK)
	track.content_margin_top = 6
	track.content_margin_bottom = 6
	var area := flat(RUST, 8, 3, INK)
	area.content_margin_top = 6
	area.content_margin_bottom = 6
	var area_hi := flat(Color("e87a45"), 8, 3, INK)
	area_hi.content_margin_top = 6
	area_hi.content_margin_bottom = 6
	t.set_stylebox("slider", "HSlider", track)
	t.set_stylebox("grabber_area", "HSlider", area)
	t.set_stylebox("grabber_area_highlight", "HSlider", area_hi)
	t.set_icon("grabber", "HSlider", _knob_texture(30, CREAM))
	t.set_icon("grabber_highlight", "HSlider", _knob_texture(30, HONEY))
	t.set_icon("grabber_disabled", "HSlider", _knob_texture(30, CREAM_DARK))
	t.set_icon("tick", "HSlider", _knob_texture(6, INK))
	t.set_constant("center_grabber", "HSlider", 0)
	t.set_stylebox("slider", "VSlider", track)
	t.set_stylebox("grabber_area", "VSlider", area)
	t.set_icon("grabber", "VSlider", _knob_texture(30, CREAM))


static func _checks(t: Theme) -> void:
	for type in ["CheckBox", "CheckButton"]:
		var empty := StyleBoxEmpty.new()
		empty.content_margin_left = 4
		empty.content_margin_right = 4
		empty.content_margin_top = 4
		empty.content_margin_bottom = 4
		var hover := flat(Color(HONEY, 0.55), 10)
		hover.set_content_margin_all(4)
		for state in ["normal", "pressed", "disabled", "focus"]:
			t.set_stylebox(state, type, empty)
		t.set_stylebox("hover", type, hover)
		t.set_stylebox("hover_pressed", type, hover)
		t.set_color("font_color", type, INK)
		t.set_color("font_hover_color", type, INK)
		t.set_color("font_pressed_color", type, INK)
		t.set_color("font_hover_pressed_color", type, INK)
		t.set_color("font_focus_color", type, INK)
		t.set_constant("h_separation", type, 12)
		t.set_font_size("font_size", type, 20)
	t.set_icon("checked", "CheckBox", _check_texture(30, true, false))
	t.set_icon("unchecked", "CheckBox", _check_texture(30, false, false))
	t.set_icon("radio_checked", "CheckBox", _check_texture(30, true, true))
	t.set_icon("radio_unchecked", "CheckBox", _check_texture(30, false, true))
	t.set_icon("checked_disabled", "CheckBox", _check_texture(30, true, false))
	t.set_icon("unchecked_disabled", "CheckBox", _check_texture(30, false, false))
	for suffix in ["", "_mirrored"]:
		t.set_icon("checked" + suffix, "CheckButton", _toggle_texture(true))
		t.set_icon("unchecked" + suffix, "CheckButton", _toggle_texture(false))
		t.set_icon("checked_disabled" + suffix, "CheckButton", _toggle_texture(true))
		t.set_icon("unchecked_disabled" + suffix, "CheckButton", _toggle_texture(false))


static func _tabs(t: Theme) -> void:
	var sel := StyleBoxFlat.new()
	sel.bg_color = CREAM
	sel.corner_radius_top_left = 14
	sel.corner_radius_top_right = 14
	sel.set_border_width_all(OUTLINE)
	sel.border_width_bottom = 0
	sel.border_color = INK
	sel.content_margin_left = 22
	sel.content_margin_right = 22
	sel.content_margin_top = 10
	sel.content_margin_bottom = 10
	var unsel: StyleBoxFlat = sel.duplicate()
	unsel.bg_color = WOOD
	unsel.content_margin_top = 8
	unsel.expand_margin_bottom = 0
	var hov: StyleBoxFlat = unsel.duplicate()
	hov.bg_color = WOOD_LIGHT
	for type in ["TabContainer", "TabBar"]:
		t.set_stylebox("tab_selected", type, sel)
		t.set_stylebox("tab_unselected", type, unsel)
		t.set_stylebox("tab_hovered", type, hov)
		t.set_stylebox("tab_focus", type, StyleBoxEmpty.new())
		t.set_stylebox("tab_disabled", type, unsel)
		t.set_color("font_selected_color", type, INK)
		t.set_color("font_unselected_color", type, CREAM)
		t.set_color("font_hovered_color", type, PAPER)
		t.set_color("font_outline_color", type, INK)
		t.set_constant("outline_size", type, 0)
		t.set_font_size("font_size", type, 22)
		t.set_font("font", type, _font("", 0.85, 0))
		t.set_constant("h_separation", type, 6)
	var pnl := panel(CREAM, RADIUS)
	pnl.corner_radius_top_left = 0
	t.set_stylebox("panel", "TabContainer", pnl)
	t.set_stylebox("tabbar_background", "TabContainer", StyleBoxEmpty.new())
	t.set_constant("side_margin", "TabContainer", 0)


static func _line_edit(t: Theme) -> void:
	var n := flat(PAPER, 10, 3, INK)
	n.content_margin_left = 14
	n.content_margin_right = 14
	n.content_margin_top = 8
	n.content_margin_bottom = 8
	var f := StyleBoxFlat.new()
	f.draw_center = false
	f.set_corner_radius_all(12)
	f.set_border_width_all(3)
	f.border_color = TEAL
	f.expand_margin_left = 3
	f.expand_margin_right = 3
	f.expand_margin_top = 3
	f.expand_margin_bottom = 3
	var ro: StyleBoxFlat = n.duplicate()
	ro.bg_color = CREAM_DARK
	t.set_stylebox("normal", "LineEdit", n)
	t.set_stylebox("focus", "LineEdit", f)
	t.set_stylebox("read_only", "LineEdit", ro)
	t.set_color("font_color", "LineEdit", INK)
	t.set_color("font_placeholder_color", "LineEdit", Color(INK, 0.4))
	t.set_color("caret_color", "LineEdit", RUST)
	t.set_color("selection_color", "LineEdit", Color(HONEY, 0.8))
	t.set_color("font_selected_color", "LineEdit", INK)
	t.set_font_size("font_size", "LineEdit", 22)
	t.set_constant("caret_width", "LineEdit", 3)


static func _scrollbars(t: Theme) -> void:
	for type in ["VScrollBar", "HScrollBar"]:
		var track := flat(Color(WOOD_DARK, 0.35), 8)
		track.set_content_margin_all(3)
		var grab := flat(WOOD, 8, 2, INK)
		grab.set_content_margin_all(5)
		var grab_hi := flat(RUST, 8, 2, INK)
		grab_hi.set_content_margin_all(5)
		t.set_stylebox("scroll", type, track)
		t.set_stylebox("scroll_focus", type, track)
		t.set_stylebox("grabber", type, grab)
		t.set_stylebox("grabber_highlight", type, grab_hi)
		t.set_stylebox("grabber_pressed", type, grab_hi)
		var e := ImageTexture.new()
		t.set_icon("increment", type, e)
		t.set_icon("decrement", type, e)
		t.set_icon("increment_highlight", type, e)
		t.set_icon("decrement_highlight", type, e)
	t.set_stylebox("panel", "ScrollContainer", StyleBoxEmpty.new())
	t.set_stylebox("focus", "ScrollContainer", StyleBoxEmpty.new())


static func _misc(t: Theme) -> void:
	var sep := StyleBoxLine.new()
	sep.color = Color(WOOD, 0.6)
	sep.thickness = 3
	t.set_stylebox("separator", "HSeparator", sep)
	t.set_constant("separation", "HSeparator", 14)
	var vsep := StyleBoxLine.new()
	vsep.color = Color(WOOD, 0.6)
	vsep.thickness = 3
	vsep.vertical = true
	t.set_stylebox("separator", "VSeparator", vsep)
	t.set_constant("separation", "VBoxContainer", 10)
	t.set_constant("separation", "HBoxContainer", 10)
	# Embedded windows / dialogs (AcceptDialog etc.)
	var win := panel(CREAM, RADIUS)
	win.expand_margin_top = 34
	t.set_stylebox("embedded_border", "Window", win)
	t.set_stylebox("embedded_unfocused_border", "Window", win)
	t.set_color("title_color", "Window", INK)
	t.set_font_size("title_font_size", "Window", 22)
	t.set_stylebox("panel", "AcceptDialog", StyleBoxEmpty.new())


# --- Generated textures -----------------------------------------------------------------------

static func _img(size: int) -> Image:
	var img := Image.create(size, size, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	return img


## Anti-aliased filled circle with an ink rim.
static func _knob_texture(size: int, fill: Color) -> Texture2D:
	var img := _img(size)
	var c := (size - 1) * 0.5
	var r := size * 0.5 - 0.5
	var rim := maxf(2.0, size * 0.12)
	for y in size:
		for x in size:
			var d := Vector2(x - c, y - c).length()
			var a := clampf(r - d + 0.5, 0.0, 1.0)
			if a <= 0.0:
				continue
			var col := INK if d > r - rim else fill
			if d <= r - rim and y < c - r * 0.25 and d < r * 0.55:
				col = fill.lightened(0.25)
			img.set_pixel(x, y, Color(col, a))
	return ImageTexture.create_from_image(img)


## Rounded check box (or a radio circle) with a teal tick when checked.
static func _check_texture(size: int, checked: bool, radio: bool) -> Texture2D:
	var img := _img(size)
	var rad := size * (0.5 if radio else 0.28)
	var rim := maxf(2.0, size * 0.11)
	var half := size * 0.5
	for y in size:
		for x in size:
			var p := Vector2(x + 0.5 - half, y + 0.5 - half)
			var q := Vector2(absf(p.x), absf(p.y)) - Vector2(half - rad, half - rad)
			var d := Vector2(maxf(q.x, 0.0), maxf(q.y, 0.0)).length() + minf(maxf(q.x, q.y), 0.0) - rad
			var a := clampf(0.5 - d, 0.0, 1.0)
			if a <= 0.0:
				continue
			var col := INK if d > -rim else (TEAL if checked else PAPER)
			img.set_pixel(x, y, Color(col, a))
	if checked:
		if radio:
			_disc(img, Vector2(half, half), size * 0.18, CREAM)
		else:
			_line(img, Vector2(size * 0.26, size * 0.52), Vector2(size * 0.43, size * 0.70), size * 0.09, CREAM)
			_line(img, Vector2(size * 0.43, size * 0.70), Vector2(size * 0.75, size * 0.32), size * 0.09, CREAM)
	return ImageTexture.create_from_image(img)


static func _toggle_texture(on: bool) -> Texture2D:
	var w := 56
	var h := 30
	var img := Image.create(w, h, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	var r := h * 0.5
	for y in h:
		for x in w:
			var px := clampf(x + 0.5, r, w - r)
			var d := Vector2(x + 0.5 - px, y + 0.5 - r).length() - (r - 0.5)
			var a := clampf(0.5 - d, 0.0, 1.0)
			if a > 0.0:
				img.set_pixel(x, y, Color(INK if d > -3.0 else (TEAL if on else WOOD_LIGHT), a))
	_disc(img, Vector2(w - r if on else r, r), r - 5.0, CREAM)
	return ImageTexture.create_from_image(img)


static func _arrow_texture(size: int, color: Color) -> Texture2D:
	var img := _img(size)
	var a := Vector2(size * 0.15, size * 0.32)
	var b := Vector2(size * 0.85, size * 0.32)
	var c := Vector2(size * 0.5, size * 0.75)
	for y in size:
		for x in size:
			var p := Vector2(x + 0.5, y + 0.5)
			if _in_triangle(p, a, b, c):
				img.set_pixel(x, y, color)
	return ImageTexture.create_from_image(img)


static func _in_triangle(p: Vector2, a: Vector2, b: Vector2, c: Vector2) -> bool:
	var d1 := (p - b).cross(a - b)
	var d2 := (p - c).cross(b - c)
	var d3 := (p - a).cross(c - a)
	var neg := d1 < 0 or d2 < 0 or d3 < 0
	var pos := d1 > 0 or d2 > 0 or d3 > 0
	return not (neg and pos)


static func _disc(img: Image, center: Vector2, radius: float, color: Color) -> void:
	for y in img.get_height():
		for x in img.get_width():
			var d := Vector2(x + 0.5, y + 0.5).distance_to(center)
			var a := clampf(radius - d + 0.5, 0.0, 1.0)
			if a > 0.0:
				img.set_pixel(x, y, img.get_pixel(x, y).blend(Color(color, a)))


static func _line(img: Image, from: Vector2, to: Vector2, width: float, color: Color) -> void:
	for y in img.get_height():
		for x in img.get_width():
			var p := Vector2(x + 0.5, y + 0.5)
			var t := clampf((p - from).dot(to - from) / (to - from).length_squared(), 0.0, 1.0)
			var d := p.distance_to(from + (to - from) * t)
			var a := clampf(width * 0.5 - d + 0.5, 0.0, 1.0)
			if a > 0.0:
				img.set_pixel(x, y, img.get_pixel(x, y).blend(Color(color, a)))
