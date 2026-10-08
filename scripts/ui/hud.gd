class_name HUD
extends CanvasLayer
## In-game HUD in the shared UiTheme (cream and wood cards, ink outlines, chunky bars):
##  top centre   train card: green body bar, six yellow wheel squares, red engine and blue chassis bars,
##               plus the journey strip (stations 0-5, train marker, locked gates, next station and metres)
##  top left     inventory chips, then corner widgets (HUD.add_corner_widget, e.g. the player list)
##  top right    speed / lever / fuel card and the objective note (Game.objective)
##  right        toasts (Game.message) · centre: crosshair, prompt pill, hold bar · banner plate (Game.banner)
##  bottom       health and frost (left), tool hotbar + help (centre), impostor sabotage panel (right)
## Also the station shop window and the Esc pause menu.

const HELP := """WASD move · Shift sprint · Space jump · E use / place · Q alt · G put item back · Esc pause
Tools: 1 hammer · 2 wrench · 3 nail gun · 4 welder (station torch) · 5 come-along · LMB use
Broken track: planks (nail on ground, NAIL GUN over water) → rails → bolt · tilt over 8° tips the train!
F1 help · F2 play as impostor ([Tab] sabotage) · F3 world sabotage · F5 last checkpoint · F6 new game"""
const HELP_AUTO_HIDE := 30.0
const MAX_TOASTS := 5
const ITEM_ORDER := ["gold", "coal", "wood", "scrap", "nails", "wheel", "engine_oil", "medkit", "come_along", "nail_gun", "grappler"]

var player: Player

var _root: Control
# train card
var _body_bar: ProgressBar
var _wheel_pips: Array[WheelPip] = []
var _engine_bar: ProgressBar
var _chassis_bar: ProgressBar
var _journey: JourneyStrip
var _journey_label: Label
var _loose_label: Label
# status card
var _speed_label: Label
var _lever_chip: PanelContainer
var _lever_label: Label
var _fuel_bar: ProgressBar
var _wind_row: Control
# objective
var _note_holder: Control
var _note_label: Label
var _objective_text := ""
# inventory and corner widgets
var _inventory_grid: GridContainer
var _inventory_rows := {}      # item -> Label
var _corner: VBoxContainer
# player
var _health_bar: ProgressBar
var _frost_bar: ProgressBar
var _prompt_pill: PanelContainer
var _prompt: Label
var _hold_bar: ProgressBar
var _crosshair: Control
# messages
var _toasts: VBoxContainer
var _banner: PanelContainer
var _banner_label: Label
var _banner_tween: Tween
# bottom
var _sabotage_panel: PanelContainer
var _sabotage_label: Label
var _hotbar: Label
var _tool_slots := {}          # tool id -> PanelContainer
var _help: PanelContainer
var _help_hint: Label
var _help_timer := HELP_AUTO_HIDE
# shop
var _shop: PanelContainer
var _shop_list: GridContainer
var _shop_title: Label
var _shop_gold: Label
var _shop_opened_frame := -1
var pause_menu: PauseMenu

static var _icons := {}


func _ready() -> void:
	_root = Control.new()
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_root)

	_build_train_card()
	_build_left_column()
	_build_status_column()
	_build_player_card()
	_build_centre()
	_build_bottom()
	_build_messages()
	_build_shop()

	pause_menu = PauseMenu.instantiate()
	add_child(pause_menu)

	Game.message.connect(_add_message)
	Game.banner.connect(_show_banner)
	Game.inventory_changed.connect(_refresh_inventory)
	if Game.has_signal("objective_changed"):
		Game.connect("objective_changed", _on_objective_changed)
	var obj: Variant = Game.get("objective")
	if obj is String:
		_on_objective_changed(obj)
	_refresh_inventory()


## Multiplayer and other systems put small widgets (player list, speaking icons) under the inventory.
func add_corner_widget(node: Control) -> void:
	_corner.add_child(node)


# --- Layout -----------------------------------------------------------------------------------

func _build_train_card() -> void:
	var card := PanelContainer.new()
	var sb := UiTheme.panel(UiTheme.CREAM, 18, 4)
	sb.content_margin_left = 16
	sb.content_margin_right = 16
	sb.content_margin_top = 12
	sb.content_margin_bottom = 10
	card.add_theme_stylebox_override("panel", sb)
	card.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(card)
	_place(card, 0.5, 0.0, Vector2(-320, 10), Vector2(640, 0))
	card.grow_horizontal = Control.GROW_DIRECTION_BOTH
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 8)
	card.add_child(col)

	# Row 1: body (green)
	var r1 := HBoxContainer.new()
	r1.add_theme_constant_override("separation", 10)
	col.add_child(r1)
	r1.add_child(UiIcon.create("body", 30))
	_body_bar = _bar(r1, UiTheme.BODY_GREEN, Vector2(0, 28), "Body")
	_body_bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL

	# Row 2: wheels (yellow squares), engine (red), chassis (blue)
	var r2 := HBoxContainer.new()
	r2.add_theme_constant_override("separation", 8)
	col.add_child(r2)
	r2.add_child(UiIcon.create("wheel", 28))
	var pips := HBoxContainer.new()
	pips.add_theme_constant_override("separation", 4)
	r2.add_child(pips)
	for i in Train.MAX_WHEELS:
		var p := WheelPip.new()
		p.custom_minimum_size = Vector2(26, 28)
		pips.add_child(p)
		_wheel_pips.append(p)
	var gap := Control.new()
	gap.custom_minimum_size.x = 6
	r2.add_child(gap)
	r2.add_child(UiIcon.create("engine", 28))
	_engine_bar = _bar(r2, UiTheme.ENGINE_RED, Vector2(0, 28), "Engine")
	_engine_bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	r2.add_child(UiIcon.create("chassis", 28))
	_chassis_bar = _bar(r2, UiTheme.CHASSIS_BLUE, Vector2(0, 28), "Chassis")
	_chassis_bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL

	_loose_label = Label.new()
	_loose_label.add_theme_color_override("font_color", UiTheme.RUST_DARK)
	_loose_label.add_theme_font_size_override("font_size", 16)
	_loose_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_loose_label.visible = false
	col.add_child(_loose_label)

	# Journey strip
	_journey = JourneyStrip.new()
	_journey.custom_minimum_size = Vector2(0, 50)
	col.add_child(_journey)
	_journey_label = Label.new()
	_journey_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_journey_label.add_theme_font_size_override("font_size", 18)
	col.add_child(_journey_label)


func _build_left_column() -> void:
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 10)
	col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(col)
	_place(col, 0.0, 0.0, Vector2(14, 12), Vector2(300, 0))
	_inventory_grid = GridContainer.new()
	_inventory_grid.columns = 2
	_inventory_grid.add_theme_constant_override("h_separation", 6)
	_inventory_grid.add_theme_constant_override("v_separation", 6)
	col.add_child(_inventory_grid)
	_corner = VBoxContainer.new()
	_corner.add_theme_constant_override("separation", 6)
	col.add_child(_corner)


func _build_status_column() -> void:
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 14)
	col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(col)
	_place(col, 1.0, 0.0, Vector2(-314, 10), Vector2(300, 0))

	var card := PanelContainer.new()
	var sb := UiTheme.panel(UiTheme.CREAM, 16, 4)
	sb.set_content_margin_all(12)
	card.add_theme_stylebox_override("panel", sb)
	col.add_child(card)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 8)
	card.add_child(v)
	var r1 := HBoxContainer.new()
	v.add_child(r1)
	r1.add_child(UiIcon.create("gauge", 30))
	_speed_label = Label.new()
	_speed_label.add_theme_font_size_override("font_size", 24)
	_speed_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	r1.add_child(_speed_label)
	_lever_chip = PanelContainer.new()
	_lever_label = Label.new()
	_lever_label.add_theme_font_size_override("font_size", 16)
	_lever_label.add_theme_color_override("font_color", UiTheme.CREAM)
	_lever_chip.add_child(_lever_label)
	_lever_chip.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	r1.add_child(_lever_chip)
	var r2 := HBoxContainer.new()
	v.add_child(r2)
	r2.add_child(UiIcon.create("flame", 30))
	_fuel_bar = _bar(r2, UiTheme.JOURNEY.lerp(UiTheme.WHEEL_YELLOW, 0.35), Vector2(0, 24), "Fuel")
	_fuel_bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var r3 := HBoxContainer.new()
	r3.visible = false
	v.add_child(r3)
	r3.add_child(UiIcon.create("snow", 26))
	var wl := Label.new()
	wl.text = "Freezing wind! Stay warm"
	wl.add_theme_color_override("font_color", UiTheme.CHASSIS_BLUE.darkened(0.3))
	wl.add_theme_font_size_override("font_size", 18)
	r3.add_child(wl)
	_wind_row = r3

	# Objective: a pinned paper note, slightly crooked
	_note_holder = Control.new()
	_note_holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_note_holder.custom_minimum_size = Vector2(300, 100)
	col.add_child(_note_holder)
	var note := PanelContainer.new()
	note.theme_type_variation = &"NotePanel"
	note.custom_minimum_size = Vector2(292, 0)
	note.position = Vector2(4, 6)
	note.rotation_degrees = -1.6
	_note_holder.add_child(note)
	var nv := VBoxContainer.new()
	nv.add_theme_constant_override("separation", 2)
	note.add_child(nv)
	var nh := Label.new()
	nh.text = "OBJECTIVE"
	nh.add_theme_color_override("font_color", UiTheme.RUST_DARK)
	nh.add_theme_font_size_override("font_size", 15)
	nv.add_child(nh)
	_note_label = Label.new()
	_note_label.theme_type_variation = &"NoteLabel"
	_note_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_note_label.custom_minimum_size = Vector2(258, 0)
	nv.add_child(_note_label)
	var pin := UiIcon.create("pin", 22)
	pin.position = Vector2(140, -2)
	_note_holder.add_child(pin)
	note.resized.connect(func() -> void: _note_holder.custom_minimum_size.y = note.size.y + 10)


func _build_player_card() -> void:
	var card := PanelContainer.new()
	var sb := UiTheme.panel(UiTheme.CREAM, 16, 4)
	sb.set_content_margin_all(10)
	card.add_theme_stylebox_override("panel", sb)
	_root.add_child(card)
	_place(card, 0.0, 1.0, Vector2(14, -104), Vector2(300, 0))
	card.grow_vertical = Control.GROW_DIRECTION_BEGIN
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 6)
	card.add_child(v)
	var r1 := HBoxContainer.new()
	v.add_child(r1)
	r1.add_child(UiIcon.create("heart", 30))
	_health_bar = _bar(r1, UiTheme.HEALTH, Vector2(0, 26), "Health")
	_health_bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var r2 := HBoxContainer.new()
	v.add_child(r2)
	r2.add_child(UiIcon.create("snow", 30))
	_frost_bar = _bar(r2, UiTheme.FROST, Vector2(0, 22), "Frost")
	_frost_bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL


func _build_centre() -> void:
	_crosshair = Crosshair.new()
	_root.add_child(_crosshair)
	_place(_crosshair, 0.5, 0.5, Vector2(-12, -12), Vector2(24, 24))

	_prompt_pill = PanelContainer.new()
	_prompt_pill.theme_type_variation = &"DarkPanel"
	_prompt_pill.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(_prompt_pill)
	_place(_prompt_pill, 0.5, 0.5, Vector2(-300, 34), Vector2(600, 0))
	_prompt_pill.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_prompt = Label.new()
	_prompt.theme_type_variation = &"HudLabel"
	_prompt.add_theme_constant_override("outline_size", 6)
	_prompt.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_prompt.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_prompt_pill.add_child(_prompt)
	_prompt_pill.visible = false

	_hold_bar = _bar(_root, UiTheme.HONEY, Vector2(220, 18), "")
	_place(_hold_bar, 0.5, 0.5, Vector2(-110, 112), Vector2(220, 18))

	_banner = PanelContainer.new()
	_banner.theme_type_variation = &"WoodPanel"
	_banner.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(_banner)
	_place(_banner, 0.5, 0.0, Vector2(-380, 226), Vector2(760, 0))
	_banner.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_banner_label = Label.new()
	_banner_label.theme_type_variation = &"HudLabel"
	_banner_label.add_theme_font_size_override("font_size", 28)
	_banner_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_banner_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_banner.add_child(_banner_label)
	_banner.visible = false


func _build_bottom() -> void:
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 8)
	col.alignment = BoxContainer.ALIGNMENT_END
	col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(col)
	_place(col, 0.5, 1.0, Vector2(-470, -12), Vector2(940, 0))
	col.grow_vertical = Control.GROW_DIRECTION_BEGIN
	col.grow_horizontal = Control.GROW_DIRECTION_BOTH

	_hotbar = Label.new()
	_hotbar.theme_type_variation = &"HudLabel"
	_hotbar.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(_hotbar)

	var bar := HBoxContainer.new()
	bar.add_theme_constant_override("separation", 10)
	bar.alignment = BoxContainer.ALIGNMENT_CENTER
	col.add_child(bar)
	for i in Player.TOOLS.size():
		var id: String = Player.TOOLS[i]
		var slot := PanelContainer.new()
		slot.add_theme_stylebox_override("panel", _slot_style(false))
		slot.custom_minimum_size = Vector2(68, 68)
		var icon := TextureRect.new()
		icon.texture = icon_for(id)
		icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		icon.custom_minimum_size = Vector2(56, 56)
		slot.add_child(icon)
		var badge := PanelContainer.new()
		var bsb := UiTheme.flat(UiTheme.INK, 7)
		bsb.content_margin_left = 6
		bsb.content_margin_right = 6
		badge.add_theme_stylebox_override("panel", bsb)
		badge.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
		badge.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
		var key := Label.new()
		key.text = str(i + 1)
		key.add_theme_color_override("font_color", UiTheme.CREAM)
		key.add_theme_font_size_override("font_size", 14)
		badge.add_child(key)
		slot.add_child(badge)
		bar.add_child(slot)
		_tool_slots[id] = slot

	_help = PanelContainer.new()
	_help.theme_type_variation = &"DarkPanel"
	col.add_child(_help)
	var hl := Label.new()
	hl.text = HELP
	hl.theme_type_variation = &"HudSmall"
	hl.add_theme_font_size_override("font_size", 16)
	hl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_help.add_child(hl)
	_help_hint = Label.new()
	_help_hint.text = "[F1] help   ·   [Esc] pause"
	_help_hint.theme_type_variation = &"HudSmall"
	_help_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_help_hint.visible = false
	col.add_child(_help_hint)

	_sabotage_panel = PanelContainer.new()
	_sabotage_panel.theme_type_variation = &"DarkPanel"
	_root.add_child(_sabotage_panel)
	_place(_sabotage_panel, 1.0, 1.0, Vector2(-354, -16), Vector2(340, 0))
	_sabotage_panel.grow_vertical = Control.GROW_DIRECTION_BEGIN
	_sabotage_label = Label.new()
	_sabotage_label.theme_type_variation = &"HudSmall"
	_sabotage_label.add_theme_font_size_override("font_size", 18)
	_sabotage_label.add_theme_color_override("font_color", Color("ff9a86"))
	_sabotage_panel.add_child(_sabotage_label)
	_sabotage_panel.visible = false


func _build_messages() -> void:
	_toasts = VBoxContainer.new()
	_toasts.add_theme_constant_override("separation", 6)
	_toasts.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(_toasts)
	_place(_toasts, 1.0, 0.5, Vector2(-454, -40), Vector2(440, 0))


func _slot_style(active: bool) -> StyleBoxFlat:
	var sb := UiTheme.panel(UiTheme.HONEY if active else Color(UiTheme.CREAM, 0.92), 14, 4 if active else 3, true)
	sb.border_color = UiTheme.INK if active else Color(UiTheme.INK, 0.8)
	sb.set_content_margin_all(5)
	if active:
		sb.expand_margin_top = 6
		sb.shadow_offset = Vector2(0, 8)
	return sb


# --- Per frame ------------------------------------------------------------------------------------

func _process(delta: float) -> void:
	if Input.is_action_just_pressed("toggle_help"):
		_set_help(not _help.visible)
	if _help.visible and _help_timer > 0.0:
		_help_timer -= delta
		if _help_timer <= 0.0:
			_set_help(false)
	var shop_just_opened := Engine.get_process_frames() == _shop_opened_frame
	if _shop.visible and not shop_just_opened and (Input.is_action_just_pressed("pause") or Input.is_action_just_pressed("interact")):
		close_shop()

	var train := Game.train
	var track := Game.track
	if train and track:
		_update_train(train, track)
	_update_player()
	_update_sabotage()


func _update_train(train: Train, track: Track) -> void:
	var body := train.body_health / Train.BODY_MAX * 100.0
	_set_bar(_body_bar, body, "Body %d%%" % int(body))
	var worst := 0.0
	for i in _wheel_pips.size():
		var state := train.wheel_state(i)
		var wear: float = train.wheel_wear[i] / Train.WHEEL_LIMIT if i < train.wheel_wear.size() else 0.0
		_wheel_pips[i].set_state(state, 1.0 - wear)
		if state == 0:
			worst = maxf(worst, wear)
	var engine := 100.0 - train.engine_damage / Train.ENGINE_MAX * 100.0
	var chassis := 100.0 - train.chassis_damage / Train.CHASSIS_MAX * 100.0
	_set_bar(_engine_bar, engine, "%d%%" % int(engine))
	_set_bar(_chassis_bar, chassis, "%d%%" % int(chassis))
	_loose_label.visible = worst > 0.25
	if _loose_label.visible:
		_loose_label.text = "A wheel is %d%% loose: tighten it with the wrench" % int(worst * 100.0)

	# Journey: stations 0..5 equally spaced, the train marker between them
	var sd := track.station_distances
	var center := train.center_distance()
	_journey.station_count = sd.size()
	_journey.next_station = Game.next_station
	_journey.train_frac = _route_frac(sd, center)
	var gates: Array = []
	if track.has_method("gate_distance") and track.has_method("is_gate_locked"):
		for seg in sd.size() - 1:
			var gd: float = float(track.call("gate_distance", seg))
			if gd >= 0.0:
				gates.append([_route_frac(sd, gd), bool(track.call("is_gate_locked", seg))])
	_journey.gates = gates
	_journey.queue_redraw()
	if Game.next_station > Game.STATION_COUNT:
		_journey_label.text = "Final station reached!"
	else:
		var next := mini(Game.next_station, sd.size() - 1)
		var theme_name := ""
		if next - 1 < Track.THEMES.size():
			theme_name = str(Track.THEMES[next - 1].get("name", ""))
		var stop := "The Port" if next == Game.STATION_COUNT else "Station %d" % next
		_journey_label.text = "Next: %s  ·  %s  ·  %d m" % [stop, theme_name, maxi(int(sd[next] - center), 0)]

	_speed_label.text = "%d km/h" % int(absf(train.speed) * 3.6)
	var lever := train.lever_text()
	_lever_label.text = lever
	var lever_col := UiTheme.BODY_GREEN.darkened(0.15) if train.lever > 0 else (UiTheme.TEAL if train.lever < 0 else UiTheme.INK_SOFT)
	var lsb := UiTheme.flat(lever_col, 8, 2)
	lsb.content_margin_left = 8
	lsb.content_margin_right = 8
	lsb.content_margin_top = 2
	lsb.content_margin_bottom = 2
	_lever_chip.add_theme_stylebox_override("panel", lsb)
	_set_bar(_fuel_bar, train.fuel / Train.MAX_FUEL * 100.0, "Fuel %d%%" % int(train.fuel / Train.MAX_FUEL * 100.0))
	_wind_row.visible = Game.wind_active
	if _objective_text == "" and not Game.has_signal("objective_changed"):
		_set_objective_label(_fallback_objective(train))


## Position along the whole route as 0..1, with the stations equally spaced.
static func _route_frac(sd: Array[float], d: float) -> float:
	var n := sd.size() - 1
	if n <= 0:
		return 0.0
	if d <= sd[0]:
		return 0.0
	for i in n:
		if d <= sd[i + 1]:
			return (i + (d - sd[i]) / maxf(sd[i + 1] - sd[i], 1.0)) / n
	return 1.0


func _fallback_objective(train: Train) -> String:
	if Game.next_station > Game.STATION_COUNT:
		return "You made it to the port. Chapter 1 complete!"
	if Game.track and Game.track.broken_count() > 0 and train.is_stopped() and train.lever != 0:
		return "Broken track ahead: rebuild it (planks, nails, rails, bolts)."
	if train.fuel < 15.0:
		return "The furnace is almost out: shovel coal into it."
	return "Get the train to %s. Keep the furnace fed and the rails whole." % (
		"the port" if Game.next_station == Game.STATION_COUNT else "Station %d" % Game.next_station)


func _update_player() -> void:
	if player == null:
		return
	_set_bar(_health_bar, player.health, "%d" % int(player.health))
	_set_bar(_frost_bar, player.frost, "Frost %d%%" % int(player.frost) if player.frost > 1.0 else "Warm")
	var prompt := player.focused.get_prompt(player) if player.focused else ""
	if player.aiming_meteor:
		prompt = "Aiming meteor: [LMB] drop · [RMB] cancel"
	_prompt.text = prompt
	_prompt_pill.visible = prompt != ""
	_hold_bar.visible = player.hold_needed > 0.0 and player.hold_progress > 0.0
	if _hold_bar.visible:
		_hold_bar.value = player.hold_progress / player.hold_needed * 100.0
	var tools := player.available_tools()
	for id: String in _tool_slots:
		var slot: PanelContainer = _tool_slots[id]
		slot.visible = id in tools
		var active: bool = id == player.current_tool and player.carried_item == ""
		var was_active: bool = slot.has_meta("active") and bool(slot.get_meta("active"))
		if was_active != active:
			slot.set_meta("active", active)
			slot.add_theme_stylebox_override("panel", _slot_style(active))
		slot.modulate = Color.WHITE if active else Color(1, 1, 1, 0.85)
	var line: String = Player.TOOL_NAMES.get(player.current_tool, "")
	if player.carried_item != "":
		line = "Carrying: %s   ([E] place · [G] put back)" % player.carried_item.replace("_", " ").to_upper()
	elif player.current_tool == "welder":
		if is_instance_valid(player.welder_source):
			line += "   ·   cable %d%%%s" % [int(player.cable_tension * 100.0), "  ⚠ LIMIT" if player.cable_tension > 0.95 else ""]
		else:
			line += "   ·   no torch: take one from a station welder"
	_hotbar.text = line
	_crosshair.visible = not Game.ui_open


func _update_sabotage() -> void:
	_sabotage_panel.visible = Game.role == "impostor"
	if _sabotage_panel.visible and Game.sabotage:
		var lines := PackedStringArray(["IMPOSTOR (secret)  ·  [Tab] %s" % ("close" if Game.sabotage_menu_open else "sabotage menu")])
		for id: String in SabotageManager.ABILITIES:
			if not Game.sabotage_menu_open:
				break
			var info: Dictionary = SabotageManager.ABILITIES[id]
			var cd: float = Game.sabotage.cooldowns[id]
			var state := "unavailable" if Game.sabotage.locked else ("ready" if cd <= 0.0 else "%ds" % int(cd))
			lines.append("%d  %s  [%s]" % [info.key, info.label, state])
		_sabotage_label.text = "\n".join(lines)


func _set_help(on: bool) -> void:
	_help.visible = on
	_help_hint.visible = not on
	_help_timer = 0.0


# --- Inventory --------------------------------------------------------------------------------------

func _refresh_inventory() -> void:
	if _inventory_grid == null:
		return
	var items: Array[String] = []
	for it: String in ITEM_ORDER:
		items.append(it)
	for it: String in Game.inventory:
		if not it in items:
			items.append(it)
	for item in items:
		var n: int = Game.count(item)
		if not _inventory_rows.has(item):
			if n <= 0:
				continue
			var chip := PanelContainer.new()
			chip.theme_type_variation = &"ChipPanel"
			chip.custom_minimum_size = Vector2(140, 0)
			chip.tooltip_text = item.replace("_", " ").capitalize()
			var row := HBoxContainer.new()
			row.add_theme_constant_override("separation", 4)
			chip.add_child(row)
			var ic := TextureRect.new()
			ic.texture = icon_for(item)
			ic.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
			ic.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
			ic.custom_minimum_size = Vector2(34, 34)
			row.add_child(ic)
			var nm := Label.new()
			nm.text = _short_name(item)
			nm.add_theme_font_size_override("font_size", 15)
			nm.add_theme_color_override("font_color", UiTheme.INK_SOFT)
			nm.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			nm.clip_text = true
			row.add_child(nm)
			var lbl := Label.new()
			lbl.add_theme_font_size_override("font_size", 20)
			row.add_child(lbl)
			_inventory_grid.add_child(chip)
			_inventory_rows[item] = lbl
		var count_label: Label = _inventory_rows[item]
		var old := count_label.text
		count_label.text = str(n)
		var chip_node := count_label.get_parent().get_parent() as Control
		chip_node.visible = n > 0
		if old != "" and old != count_label.text and chip_node.visible:
			_pop(chip_node, int(old) < n)


static func _short_name(item: String) -> String:
	match item:
		"engine_oil": return "Oil"
		"come_along": return "Winch"
		"nail_gun": return "Nail gun"
		"grappler": return "Hook"
	return item.replace("_", " ").capitalize()


func _pop(c: Control, gained: bool) -> void:
	c.pivot_offset = c.size * 0.5
	c.modulate = Color(0.75, 1.0, 0.7) if gained else Color(1.0, 0.75, 0.7)
	var t := c.create_tween().set_parallel()
	t.tween_property(c, "modulate", Color.WHITE, 0.5)


# --- Objective ----------------------------------------------------------------------------------------

func _on_objective_changed(text: Variant = "") -> void:
	_objective_text = str(text)
	_set_objective_label(_objective_text)
	if _objective_text != "":
		_note_holder.pivot_offset = Vector2(150, 0)
		_note_holder.scale = Vector2(1.06, 1.06)
		_note_holder.create_tween().tween_property(_note_holder, "scale", Vector2.ONE, 0.3).set_trans(Tween.TRANS_BACK)


func _set_objective_label(text: String) -> void:
	if _note_label.text != text:
		_note_label.text = text
	_note_holder.visible = text != ""


# --- Shop ---------------------------------------------------------------------------------------------

func _build_shop() -> void:
	_shop = PanelContainer.new()
	_shop.theme_type_variation = &"WoodPanel"
	_shop.visible = false
	_root.add_child(_shop)
	_place(_shop, 0.5, 0.5, Vector2(-390, -300), Vector2(780, 0))
	_shop.grow_horizontal = Control.GROW_DIRECTION_BOTH
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 12)
	_shop.add_child(box)
	var head := HBoxContainer.new()
	box.add_child(head)
	_shop_title = UiTheme.title_label("SHOP", 38)
	_shop_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	_shop_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(_shop_title)
	var gold_chip := PanelContainer.new()
	gold_chip.theme_type_variation = &"ChipPanel"
	gold_chip.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	head.add_child(gold_chip)
	var gr := HBoxContainer.new()
	gold_chip.add_child(gr)
	var gi := TextureRect.new()
	gi.texture = icon_for("gold")
	gi.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	gi.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	gi.custom_minimum_size = Vector2(34, 34)
	gr.add_child(gi)
	_shop_gold = Label.new()
	_shop_gold.add_theme_font_size_override("font_size", 22)
	gr.add_child(_shop_gold)

	var inner := PanelContainer.new()
	box.add_child(inner)
	_shop_list = GridContainer.new()
	_shop_list.columns = 2
	_shop_list.add_theme_constant_override("h_separation", 10)
	_shop_list.add_theme_constant_override("v_separation", 10)
	inner.add_child(_shop_list)

	var foot := HBoxContainer.new()
	foot.alignment = BoxContainer.ALIGNMENT_END
	box.add_child(foot)
	var close := Button.new()
	close.text = "Close  [E / Esc]"
	close.pressed.connect(close_shop)
	foot.add_child(close)
	Game.inventory_changed.connect(_refresh_shop)


func open_shop(station: Station) -> void:
	_shop_title.text = station.display_name().to_upper()
	for c in _shop_list.get_children():
		c.queue_free()
	for id: String in Game.SHOP:
		_shop_list.add_child(_shop_card(id))
	_refresh_shop()
	_shop.visible = true
	_shop.modulate.a = 0.0
	_shop.create_tween().tween_property(_shop, "modulate:a", 1.0, 0.15)
	_shop_opened_frame = Engine.get_process_frames()
	Game.ui_open = true


func _shop_card(id: String) -> Control:
	var entry: Dictionary = Game.SHOP[id]
	var label := str(entry.label)
	var title := label
	var desc := ""
	var paren := label.find(" (")
	if paren > 0:
		title = label.left(paren)
		desc = label.substr(paren + 2).trim_suffix(")")
	var card := PanelContainer.new()
	card.theme_type_variation = &"PaperPanel"
	card.custom_minimum_size = Vector2(340, 0)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	card.add_child(row)
	var ic := TextureRect.new()
	var gives: Dictionary = entry.gives
	ic.texture = icon_for(str(gives.keys()[0]))
	ic.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	ic.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	ic.custom_minimum_size = Vector2(52, 52)
	row.add_child(ic)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 0)
	v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	v.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_child(v)
	var t := Label.new()
	t.text = title
	t.add_theme_font_size_override("font_size", 19)
	v.add_child(t)
	if desc != "":
		var d := Label.new()
		d.text = desc
		d.theme_type_variation = &"MutedLabel"
		d.add_theme_font_size_override("font_size", 14)
		d.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		d.custom_minimum_size = Vector2(150, 0)
		v.add_child(d)
	var buy := Button.new()
	buy.text = "%d" % int(entry.price)
	buy.icon = icon_for("gold")
	buy.expand_icon = false
	buy.add_theme_constant_override("icon_max_width", 26)
	buy.theme_type_variation = &"KeyButton"
	buy.custom_minimum_size = Vector2(84, 44)
	buy.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	buy.tooltip_text = "Buy %s" % title
	buy.set_meta("price", int(entry.price))
	buy.pressed.connect(func() -> void: Game.buy(id))
	row.add_child(buy)
	return card


func _refresh_shop() -> void:
	if _shop_gold == null:
		return
	var gold := Game.count("gold")
	_shop_gold.text = str(gold)
	for card in _shop_list.get_children():
		for b in card.find_children("*", "Button", true, false):
			if b.has_meta("price"):
				(b as Button).disabled = gold < int(b.get_meta("price"))


func close_shop() -> void:
	_shop.visible = false
	Game.ui_open = false


# --- Messages -----------------------------------------------------------------------------------------

func _add_message(text: String) -> void:
	var holder := Control.new()
	holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	holder.clip_contents = false
	var toast := PanelContainer.new()
	var sb := UiTheme.panel(UiTheme.PAPER, 12, 3, true)
	sb.content_margin_left = 14
	sb.content_margin_right = 14
	sb.content_margin_top = 8
	sb.content_margin_bottom = 8
	toast.add_theme_stylebox_override("panel", sb)
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", 18)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.custom_minimum_size = Vector2(400, 0)
	toast.add_child(l)
	holder.add_child(toast)
	_toasts.add_child(holder)
	while _toasts.get_child_count() > MAX_TOASTS:
		_toasts.get_child(0).free()
	var h := toast.get_combined_minimum_size().y
	holder.custom_minimum_size = Vector2(440, h)
	toast.position = Vector2(80, 0)
	toast.modulate.a = 0.0
	var tw := toast.create_tween()
	tw.set_parallel()
	tw.tween_property(toast, "position:x", 0.0, 0.28).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.tween_property(toast, "modulate:a", 1.0, 0.2)
	tw.chain().tween_interval(5.0)
	tw.chain().tween_property(toast, "modulate:a", 0.0, 0.8)
	tw.chain().tween_property(holder, "custom_minimum_size:y", 0.0, 0.2)
	tw.chain().tween_callback(holder.queue_free)


func _show_banner(text: String) -> void:
	_banner_label.text = text
	_banner.visible = true
	if _banner_tween and _banner_tween.is_valid():
		_banner_tween.kill()
	_banner.modulate.a = 0.0
	_banner.pivot_offset = Vector2(380, 0)
	_banner.scale = Vector2(0.92, 0.92)
	_banner_tween = _banner.create_tween()
	_banner_tween.set_parallel()
	_banner_tween.tween_property(_banner, "modulate:a", 1.0, 0.25)
	_banner_tween.tween_property(_banner, "scale", Vector2.ONE, 0.35).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	_banner_tween.chain().tween_interval(4.0)
	_banner_tween.chain().tween_property(_banner, "modulate:a", 0.0, 0.8)
	_banner_tween.chain().tween_callback(_banner.hide)


# --- Helpers ----------------------------------------------------------------------------------------------

## Item / tool icon rendered in Blender (assets/icons/<id>.png), or null.
static func icon_for(id: String) -> Texture2D:
	if not _icons.has(id):
		var path := "res://assets/icons/%s.png" % id
		_icons[id] = load(path) if ResourceLoader.exists(path) else null
	return _icons[id]


## Pins a control to an anchor point of the screen (0..1), offset in pixels from it.
func _place(c: Control, ax: float, ay: float, offset: Vector2, size: Vector2) -> void:
	c.anchor_left = ax
	c.anchor_right = ax
	c.anchor_top = ay
	c.anchor_bottom = ay
	c.offset_left = offset.x
	c.offset_top = offset.y
	c.offset_right = offset.x + size.x
	c.offset_bottom = offset.y + size.y


## A themed bar with its value written on it (centred, cream with an ink outline).
func _bar(parent: Control, color: Color, min_size: Vector2, caption: String) -> ProgressBar:
	var bar := ProgressBar.new()
	bar.custom_minimum_size = min_size
	bar.max_value = 100.0
	bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	UiTheme.style_bar(bar, color)
	if caption != "" or min_size.y >= 20:
		var l := Label.new()
		l.name = "Value"
		l.text = caption
		l.theme_type_variation = &"HudSmall"
		l.add_theme_font_size_override("font_size", 15 if min_size.y < 26 else 17)
		l.add_theme_constant_override("outline_size", 5)
		l.set_anchors_preset(Control.PRESET_FULL_RECT)
		l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		l.mouse_filter = Control.MOUSE_FILTER_IGNORE
		bar.add_child(l)
	parent.add_child(bar)
	return bar


func _set_bar(bar: ProgressBar, value: float, caption: String) -> void:
	bar.value = value
	var l := bar.get_node_or_null("Value") as Label
	if l and l.text != caption:
		l.text = caption


# --- Small drawn widgets ------------------------------------------------------------------------------

## One wheel: a yellow square that empties as the wheel wears loose; a lost wheel is an empty slot with an X.
class WheelPip extends Control:
	var state := 0          # 0 ok, 1 missing, 2 placed but not bolted
	var amount := 1.0       # 1 = tight, 0 = about to fall off

	func set_state(s: int, a: float) -> void:
		if s != state or absf(a - amount) > 0.005:
			state = s
			amount = clampf(a, 0.0, 1.0)
			queue_redraw()

	func _draw() -> void:
		var r := Rect2(Vector2.ZERO, size)
		draw_style_box(UiTheme.flat(UiTheme.INK, 7), r)
		var inner := r.grow(-3.0)
		if state == 1:
			draw_style_box(UiTheme.flat(Color(UiTheme.INK_SOFT, 0.7), 5), inner)
			var a := inner.grow(-5.0)
			draw_line(a.position, a.end, UiTheme.ENGINE_RED.lightened(0.2), 3.0, true)
			draw_line(Vector2(a.end.x, a.position.y), Vector2(a.position.x, a.end.y), UiTheme.ENGINE_RED.lightened(0.2), 3.0, true)
			return
		var col := UiTheme.WHEEL_YELLOW
		if state == 2:
			col = Color(col, 0.5)
		elif amount < 0.35:
			col = col.lerp(UiTheme.JOURNEY, 0.6)
		var h := inner.size.y * (amount if state == 0 else 1.0)
		var fill := Rect2(inner.position.x, inner.end.y - h, inner.size.x, h)
		if h > 0.5:
			var sb := UiTheme.flat(col, 5)
			sb.border_width_top = 3
			sb.border_color = col.lightened(0.35)
			sb.border_blend = true
			draw_style_box(sb, fill)
		if state == 2:
			var f := UiTheme.body_font()
			draw_string(f, Vector2(0, size.y * 0.72), "!", HORIZONTAL_ALIGNMENT_CENTER, size.x, 18, UiTheme.INK)


## The route from the departure station (0) to the port (5): stations as pips, the train as a marker,
## locked gates as padlocks.
class JourneyStrip extends Control:
	var station_count := 6
	var next_station := 1
	var train_frac := 0.0
	var gates: Array = []     # [frac, locked]

	func _draw() -> void:
		var pad := 18.0
		var y := size.y * 0.62
		var x0 := pad
		var x1 := size.x - pad
		var font := UiTheme.body_font()
		# rail bed
		draw_line(Vector2(x0, y), Vector2(x1, y), UiTheme.INK, 14.0, true)
		draw_line(Vector2(x0, y), Vector2(x1, y), UiTheme.WOOD_DARK, 8.0, true)
		var tx := lerpf(x0, x1, clampf(train_frac, 0.0, 1.0))
		draw_line(Vector2(x0, y), Vector2(tx, y), UiTheme.JOURNEY, 8.0, true)
		# sleepers
		var n := int((x1 - x0) / 14.0)
		for i in n:
			var sx := x0 + 7.0 + i * 14.0
			if sx > tx:
				draw_line(Vector2(sx, y - 3.0), Vector2(sx, y + 3.0), Color(UiTheme.CREAM, 0.25), 2.0)
		# stations
		var count := maxi(station_count, 2)
		for i in count:
			var px := lerpf(x0, x1, float(i) / (count - 1))
			var reached := i < next_station
			var is_next := i == next_station
			var rad := 11.0 if is_next else 9.0
			draw_circle(Vector2(px, y), rad + 3.0, UiTheme.INK)
			var fill := UiTheme.JOURNEY if reached else (UiTheme.HONEY if is_next else UiTheme.CREAM)
			draw_circle(Vector2(px, y), rad, fill)
			var label := str(i)
			draw_string(font, Vector2(px - 10.0, y + 5.5), label, HORIZONTAL_ALIGNMENT_CENTER, 20.0, 15,
				UiTheme.CREAM if reached else UiTheme.INK)
		# locked gates
		for g: Array in gates:
			var gx := lerpf(x0, x1, float(g[0]))
			var locked: bool = g[1]
			UiIcon.draw_icon(self, "lock" if locked else "unlock", Rect2(gx - 9.0, y - 34.0, 18.0, 18.0),
				UiTheme.HONEY if locked else Color(UiTheme.CREAM_DARK, 0.8))
		# train marker
		UiIcon.draw_icon(self, "train", Rect2(tx - 15.0, y - 38.0, 30.0, 30.0), UiTheme.RUST)


## Crosshair: a small cream ring with an ink rim and a dot.
class Crosshair extends Control:
	func _ready() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func _draw() -> void:
		var c := size * 0.5
		draw_arc(c, 7.0, 0.0, TAU, 24, Color(UiTheme.INK, 0.8), 4.5, true)
		draw_arc(c, 7.0, 0.0, TAU, 24, Color(UiTheme.CREAM, 0.95), 2.0, true)
		draw_circle(c, 2.0, UiTheme.CREAM)
