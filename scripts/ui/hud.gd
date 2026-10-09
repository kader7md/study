class_name HUD
extends CanvasLayer
## In-game HUD (HudStyle: white rounded outlines, soft shadows, striped bars, white line icons, Fredoka font).
## Minimal: nothing big covers the view.
##  top centre     TrainStatus: winch line (only while the come-along is in play), body bar, mechanics bar
##  top left of it SHARED TEAM resources: planks, rails, nails, bolts, oil, spare wheels, gold (icon + number)
##  top right      speed / lever / fuel readout, freezing-wind warning, toasts (Game.message) under it
##  top left       corner widgets (HUD.add_corner_widget, e.g. the crew list online)
##  centre         crosshair dot with the hold ring, interaction prompt with key caps, banners (Game.banner)
##  bottom left    status effect icons, health (striped), stamina (hidden until a map uses it), warmth
##  bottom centre  personal hotbar slots 1-5 (+ the station torch while held)
##  right          context key hints for the held tool / carried item, read from the current bindings
##  windows        [Tab] inventory, station shop, hold [H] help, Esc pause menu (PauseMenu)
## API for other systems: add_corner_widget(node), set_stamina(value, visible), show_intro(), open_shop(), toast().

const MAX_TOASTS := 4
## Team pool counters, in this order (two rows).
const TEAM_ORDER := ["wood", "rail", "nails", "bolts", "engine_oil", "wheel", "gold"]
const STATUS_ICONS := {
	"cold": ["snow", HudStyle.COLD], "freezing": ["snow", HudStyle.DANGER], "chilly": ["snow", HudStyle.SOFT],
	"bleeding": ["drop", HudStyle.DANGER], "boost": ["boost", HudStyle.GOLD], "heavy": ["heavy", HudStyle.SOFT],
	"warming": ["flame", HudStyle.WARM],
}

var player: Player
var pause_menu: PauseMenu
var inventory: InventoryWindow

var _root: Control
var _train: TrainStatus
var _team: TeamCounters
var _readout: TrainReadout
var _corner: VBoxContainer
var _toasts: VBoxContainer
var _crosshair: Crosshair
var _prompt: KeyText
var _banner: Control
var _banner_title: Label
var _banner_sub: Label
var _banner_tween: Tween
var _banner_active := false
var _intro_since := -1
var _objective: Label
var _objective_tween: Tween
var _objective_text := ""
var _player_box: VBoxContainer
var _hotbar_box: VBoxContainer
var _status_row: HBoxContainer
var _status_seen := ""
var _health: HudBar
var _stamina: HudBar
var _warmth: HudBar
var _hotbar: Array[ItemSlot] = []
var _torch: ItemSlot
var _cable_bar: HudBar
var _held_name: Label
var _held_name_tween: Tween
var _last_held := "-"
var _hints: KeyText
var _sabotage: KeyText
var _downed: VBoxContainer
var _help: PanelContainer
var _help_text: KeyText
var _help_objective: Label
var _announced_station := -1
var _tip_hist: Array[float] = []
var _pull_until := 0
# shop
var _shop_dim: ColorRect
var _shop: PanelContainer
var _shop_list: GridContainer
var _shop_title: Label
var _shop_gold: Label
var _shop_sell: Button
var _shop_opened_frame := -1
var _inv_opened_frame := -1

static var _icons := {}
static var _theme: Theme


func _ready() -> void:
	_root = Control.new()
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.theme = hud_theme()
	add_child(_root)

	_build_top()
	_build_centre()
	_build_player()
	_build_hotbar()
	_build_right()
	_build_downed()
	_build_help()
	_build_shop()
	inventory = InventoryWindow.new()
	inventory.player = player
	_root.add_child(inventory)

	pause_menu = PauseMenu.instantiate()
	add_child(pause_menu)

	Game.message.connect(toast)
	Game.banner.connect(_show_banner)
	Game.inventory_changed.connect(_refresh_team)
	Game.personal_changed.connect(func(_p: int) -> void: _refresh_hotbar())
	Game.objective_changed.connect(_on_objective_changed)
	Settings.changed.connect(_on_settings_changed)
	_refresh_team()
	_refresh_hotbar()


func _on_settings_changed(section: String, _key: String) -> void:
	if section == "controls":
		_help_text.text = help_keys()


## The help text with the player's current key bindings (debug keys only when they are enabled).
## Shown while [H] is held, and in the pause menu.
static func help_text() -> String:
	var k := func(action: String) -> String: return Settings.key_label(action)
	var move := "%s%s%s%s" % [k.call("move_forward"), k.call("move_left"), k.call("move_back"), k.call("move_right")]
	var lines := PackedStringArray([
		"%s move · %s sprint · %s jump · %s use / place · %s alt · %s put item back · %s pause" % [
			move, k.call("sprint"), k.call("jump"), k.call("interact"), k.call("interact_alt"), k.call("drop"), k.call("pause")],
		"Hotbar: %s-%s or mouse wheel · %s use tool / eat · %s inventory (drag items into the hotbar)" % [
			k.call("tool_1"), k.call("tool_5"), k.call("attack"), k.call("inventory")],
		"Broken track: planks (nail on ground, NAIL GUN over water) → rails → bolt · tilt over 8° tips the train!",
		"Eat to heal · stay warm by the furnace · %s push to talk · hold %s for this help" % [k.call("push_to_talk"), k.call("show_help")],
	])
	if Game.debug_keys_enabled():
		lines.append("Debug: %s impostor (%s sabotage) · %s world sabotage · %s last checkpoint · %s new game" % [
			k.call("toggle_role"), k.call("sabotage_menu"), k.call("toggle_world_sabotage"), k.call("restart_checkpoint"),
			k.call("new_game")])
	return "\n".join(lines)


## The same help as key caps (for KeyText; not passed through Settings.hint, the labels are the bindings already).
static func help_keys() -> String:
	var k := func(action: String) -> String: return "[%s]" % Settings.key_label(action)
	var lines := PackedStringArray([
		"%s%s%s%s  move     %s  sprint     %s  jump     %s  pause" % [k.call("move_forward"), k.call("move_left"), k.call("move_back"),
			k.call("move_right"), k.call("sprint"), k.call("jump"), k.call("pause")],
		"%s  use / place     %s  alternative     %s  put item back     %s  release the come-along" % [k.call("interact"),
			k.call("interact_alt"), k.call("drop"), k.call("winch_release")],
		"%s-%s  hotbar     [Wheel]  switch     %s  use tool / eat     %s  inventory" % [k.call("tool_1"), k.call("tool_5"),
			k.call("attack"), k.call("inventory")],
		"%s  push to talk     %s  help (hold)" % [k.call("push_to_talk"), k.call("show_help")],
		"Broken track: planks (nail them; NAIL GUN over water) → rails → bolts · a tilt over 8° tips the train!",
		"Planks, rails, nails, bolts, oil, wheels and gold are shared · eat to heal · stay warm by the furnace",
	])
	if Game.debug_keys_enabled():
		lines.append("Debug:  %s  impostor (%s sabotage)   %s  world sabotage   %s  last checkpoint   %s  new game" % [
			k.call("toggle_role"), k.call("sabotage_menu"), k.call("toggle_world_sabotage"), k.call("restart_checkpoint"),
			k.call("new_game")])
	return "\n".join(lines)


## Multiplayer and other systems put small widgets (the crew list, speaking icons) in the top-left corner.
func add_corner_widget(node: Control) -> void:
	_corner.add_child(node)


## A stamina bar between health and warmth, for maps that need one (climbing). value 0..1 (or 0..100).
func set_stamina(value: float, show: bool) -> void:
	if value > 1.0:
		value /= 100.0
	_stamina.set_value(value)
	_stamina.visible = show


# --- Layout -----------------------------------------------------------------------------------

func _build_top() -> void:
	_train = TrainStatus.new()
	_root.add_child(_train)
	var tw := _train.custom_minimum_size.x
	_place(_train, 0.5, 0.0, Vector2(-tw * 0.5, 8), _train.custom_minimum_size)

	_team = TeamCounters.new()
	_root.add_child(_team)
	# just left of the train bars, level with them
	_place(_team, 0.5, 0.0, Vector2(-tw * 0.5 - TeamCounters.W + TrainStatus.SIDE - 14.0, 40), Vector2(TeamCounters.W, 64))

	_readout = TrainReadout.new()
	_root.add_child(_readout)
	_place(_readout, 1.0, 0.0, Vector2(-TrainReadout.W - 22, 18), Vector2(TrainReadout.W, 96))

	_corner = VBoxContainer.new()
	_corner.add_theme_constant_override("separation", 6)
	_corner.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(_corner)
	_place(_corner, 0.0, 0.0, Vector2(18, 16), Vector2(240, 0))

	_toasts = VBoxContainer.new()
	_toasts.add_theme_constant_override("separation", 6)
	_toasts.alignment = BoxContainer.ALIGNMENT_BEGIN
	_toasts.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(_toasts)
	_place(_toasts, 1.0, 0.0, Vector2(-442, 124), Vector2(420, 0))

	_objective = HudStyle.label("", 19, HudStyle.WHITE, 600)
	_objective.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_objective.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_objective.modulate.a = 0.0
	_root.add_child(_objective)
	_place(_objective, 0.5, 0.0, Vector2(-320, _train.custom_minimum_size.y + 18), Vector2(640, 0))


func _build_centre() -> void:
	_crosshair = Crosshair.new()
	_root.add_child(_crosshair)
	_place(_crosshair, 0.5, 0.5, Vector2(-20, -20), Vector2(40, 40))

	_prompt = KeyText.create("", 19)
	_root.add_child(_prompt)
	_place(_prompt, 0.5, 0.5, Vector2(-400, 30), Vector2(800, 40))

	_banner = VBoxContainer.new()
	(_banner as VBoxContainer).add_theme_constant_override("separation", 2)
	_banner.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(_banner)
	_place(_banner, 0.5, 0.0, Vector2(-450, 210), Vector2(900, 0))
	_banner_title = HudStyle.label("", 40, HudStyle.WHITE, 700)
	_banner_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_banner_title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_banner.add_child(_banner_title)
	var rule := Rule.new()
	rule.custom_minimum_size = Vector2(0, 10)
	_banner.add_child(rule)
	_banner_sub = HudStyle.label("", 21, HudStyle.SOFT, 500)
	_banner_sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_banner_sub.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_banner.add_child(_banner_sub)
	_banner.visible = false


func _build_player() -> void:
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 8)
	col.alignment = BoxContainer.ALIGNMENT_END
	col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(col)
	_player_box = col
	_place(col, 0.0, 1.0, Vector2(26, -24), Vector2(330, 0))
	col.grow_vertical = Control.GROW_DIRECTION_BEGIN
	_status_row = HBoxContainer.new()
	_status_row.add_theme_constant_override("separation", 10)
	_status_row.custom_minimum_size = Vector2(0, 26)
	_status_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.add_child(_status_row)
	_health = HudBar.create("heart", HudStyle.HEALTH, Vector2(330, 24))
	col.add_child(_health)
	_stamina = HudBar.create("boost", HudStyle.STAMINA, Vector2(300, 13))
	_stamina.low = 0.15
	_stamina.visible = false
	col.add_child(_stamina)
	_warmth = HudBar.create("flame", HudStyle.WARM, Vector2(300, 13))
	_warmth.low = 0.2
	col.add_child(_warmth)


func _build_hotbar() -> void:
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 6)
	col.alignment = BoxContainer.ALIGNMENT_END
	col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(col)
	_hotbar_box = col
	_place(col, 0.5, 1.0, Vector2(-260, -20), Vector2(520, 0))
	col.grow_vertical = Control.GROW_DIRECTION_BEGIN
	col.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_held_name = HudStyle.label("", 18, HudStyle.WHITE, 600)
	_held_name.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_held_name.modulate.a = 0.0
	col.add_child(_held_name)
	_cable_bar = HudBar.create("", HudStyle.WARM, Vector2(160, 10))
	_cable_bar.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	_cable_bar.visible = false
	col.add_child(_cable_bar)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.add_child(row)
	for i in Game.HOTBAR_SIZE:
		var s := ItemSlot.create(i, 62.0)
		s.key = str(i + 1)
		row.add_child(s)
		_hotbar.append(s)
	_torch = ItemSlot.create(-1, 62.0)
	_torch.set_item("welder", 1)
	_torch.visible = false
	row.add_child(_torch)


func _build_right() -> void:
	_hints = KeyText.create("", 17, HORIZONTAL_ALIGNMENT_LEFT)
	_root.add_child(_hints)
	_place(_hints, 1.0, 0.5, Vector2(-300, 60), Vector2(280, 0))

	_sabotage = KeyText.create("", 16, HORIZONTAL_ALIGNMENT_LEFT)
	_sabotage.color = Color("ff9a8c")
	_root.add_child(_sabotage)
	_place(_sabotage, 1.0, 1.0, Vector2(-330, -190), Vector2(310, 0))
	_sabotage.visible = false


## "You are down" in the middle of the screen while the local player is downed.
func _build_downed() -> void:
	_downed = VBoxContainer.new()
	_downed.add_theme_constant_override("separation", 4)
	_downed.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(_downed)
	_place(_downed, 0.5, 0.5, Vector2(-360, -150), Vector2(720, 0))
	var t := HudStyle.label("You are down", 46, Color("ff9a8c"), 700)
	t.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_downed.add_child(t)
	var l := HudStyle.label("A crewmate can revive you with a medkit,\nor you get back up when the train reaches the next station.", 20, HudStyle.SOFT, 500)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_downed.add_child(l)
	_downed.visible = false


## Hold [H]: the controls and the current objective, in a light glass card.
func _build_help() -> void:
	_help = PanelContainer.new()
	_help.add_theme_stylebox_override("panel", HudStyle.panel_box(18.0, 20.0))
	_help.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(_help)
	_place(_help, 0.5, 0.5, Vector2(-440, -170), Vector2(880, 0))
	_help.grow_horizontal = Control.GROW_DIRECTION_BOTH
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 10)
	_help.add_child(v)
	v.add_child(HudStyle.label("Controls", 26, HudStyle.WHITE, 650))
	_help_text = KeyText.create(help_keys(), 17, HORIZONTAL_ALIGNMENT_LEFT)
	v.add_child(_help_text)
	_help_objective = HudStyle.label("", 18, HudStyle.GOLD, 600)
	_help_objective.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	v.add_child(_help_objective)
	_help.visible = false


# --- Per frame ------------------------------------------------------------------------------------

func _process(_delta: float) -> void:
	var modal := Game.ui_open
	_toasts.visible = not modal
	_banner.visible = _banner_active and not modal
	_end_intro_on_move()
	_downed.visible = player != null and player.downed and not modal
	_handle_windows()
	var help_on := Input.is_action_pressed("show_help") and not modal
	if help_on and not _help.visible:
		_help_text.text = help_keys()
		_help_objective.text = ("Objective: " + _objective_text) if _objective_text != "" else ""
	_help.visible = help_on
	_toasts.visible = _toasts.visible and not help_on
	if inventory.player != player:
		inventory.player = player

	var train := Game.train
	if train and Game.track:
		_update_train(train)
	_update_player()
	_update_hints()
	_update_sabotage()
	# behind the shop and the pause menu only the windows show; the inventory has its own hotbar row
	var windowed := Game.is_ui_open(&"shop") or Game.is_ui_open(&"pause")
	for c: CanvasItem in [_train, _team, _readout, _player_box, _corner]:
		c.visible = not windowed
	_hotbar_box.visible = not windowed and not inventory.is_open
	_hints.visible = not modal
	_objective.visible = not modal


## [Tab] opens / closes the inventory, Esc or [E] closes it (and the shop).
func _handle_windows() -> void:
	var frame := Engine.get_process_frames()
	if _shop.visible and frame != _shop_opened_frame and (Input.is_action_just_pressed("pause") or Input.is_action_just_pressed("interact")):
		close_shop()
		return
	if inventory.is_open:
		if frame != _inv_opened_frame and (Input.is_action_just_pressed("inventory") or Input.is_action_just_pressed("pause")):
			close_inventory()
		return
	if Input.is_action_just_pressed("inventory") and not Game.ui_open and player != null and not player.downed:
		open_inventory()


func open_inventory() -> void:
	inventory.player = player
	inventory.open()
	_inv_opened_frame = Engine.get_process_frames()


func close_inventory() -> void:
	inventory.close()


func _update_train(train: Train) -> void:
	_train.body = train.body_health / Train.BODY_MAX
	_train.engine = 1.0 - train.engine_damage / Train.ENGINE_MAX
	_train.chassis = 1.0 - train.chassis_damage / Train.CHASSIS_MAX
	var wheels: Array = []
	for i in Train.MAX_WHEELS:
		var wear: float = train.wheel_wear[i] / Train.WHEEL_LIMIT if i < train.wheel_wear.size() else 0.0
		wheels.append([train.wheel_state(i), 1.0 - wear])
	_train.wheels = wheels
	_train.critical = _train.body < 0.25 or _train.engine < 0.25 or _train.chassis < 0.25 \
		or train.wheels < Train.MIN_WHEELS_TO_MOVE or train.tipped
	# the winch line: while the train lies tipped or the come-along is hooked on
	var hooked := is_instance_valid(train.hook)
	var anchored := is_instance_valid(train.anchor)
	_train.winch_visible = train.tipped or hooked or anchored
	_train.hooked = hooked
	_train.anchored = anchored
	_tip_hist.append(absf(train.tip_angle))
	if _tip_hist.size() > 20:
		_tip_hist.pop_front()
	# pulling: the lean got smaller lately (clients see it too); the chevrons stay on a moment after each pump
	if hooked and anchored and _tip_hist.size() > 2 and _tip_hist[0] - _tip_hist[-1] > 0.05:
		_pull_until = Time.get_ticks_msec() + 1200
	_train.pulling = hooked and anchored and Time.get_ticks_msec() < _pull_until

	_readout.speed = absf(train.speed) * 3.6
	_readout.lever = train.lever
	_readout.fuel = train.fuel / Train.MAX_FUEL
	_readout.wind = Game.wind_active

	# a short banner when the next station comes into reach
	var sd := Game.track.station_distances
	var next := Game.next_station
	if next < sd.size() and next != _announced_station:
		var ahead := sd[next] - train.center_distance()
		if ahead > 0.0 and ahead < 260.0:
			_announced_station = next
			var stop := "The Port" if next == Game.STATION_COUNT else "Station %d" % next
			_flash_objective("%s ahead · %d m · stop at the platform" % [stop, int(ahead)])


func _update_player() -> void:
	if player == null:
		return
	_health.set_value(player.health / 100.0)
	_warmth.set_value(player.warmth / 100.0)
	_warmth.icon = "flame" if player.warmth >= 50.0 else "snow"
	_warmth.color = HudStyle.WARM.lerp(HudStyle.COLD, clampf((70.0 - player.warmth) / 50.0, 0.0, 1.0))
	_warmth.icon_color = HudStyle.WHITE if player.warmth > 20.0 else HudStyle.COLD
	_warmth.crawl = player.is_warm_spot() and player.warmth < 100.0
	# status effects above the health bar
	var effects := player.status_effects()
	var key := ",".join(effects)
	if key != _status_seen:
		_status_seen = key
		for c in _status_row.get_children():
			c.queue_free()
		for e: String in effects:
			var ic := InventoryWindow.IconBox.new()
			ic.kind = STATUS_ICONS[e][0]
			ic.color = STATUS_ICONS[e][1]
			ic.custom_minimum_size = Vector2(24, 24)
			ic.tooltip_text = e
			_status_row.add_child(ic)
	# prompt under the crosshair
	var prompt := player.focused.get_prompt(player) if player.focused and not player.downed else ""
	if player.aiming_meteor:
		prompt = "Aiming meteor: [LMB] drop · [RMB] cancel"
	_prompt.text = Settings.hint(prompt)
	_prompt.visible = prompt != "" and not Game.ui_open
	_crosshair.visible = not Game.ui_open
	_crosshair.active = player.focused != null and prompt != ""
	_crosshair.hold = player.hold_progress / player.hold_needed if player.hold_needed > 0.0 else 0.0
	_crosshair.queue_redraw()
	# hotbar: selection, the torch, the name of what's in hand
	for i in _hotbar.size():
		var sel := i == player.hotbar_index and not is_instance_valid(player.welder_source) and player.carried_item == ""
		if _hotbar[i].selected != sel:
			_hotbar[i].selected = sel
			_hotbar[i].queue_redraw()
	var torch := is_instance_valid(player.welder_source)
	_torch.visible = torch
	_torch.selected = torch
	_cable_bar.visible = torch
	if torch:
		_cable_bar.set_value(1.0 - player.cable_tension)
		_cable_bar.low = 0.1
	var held := "carry:" + player.carried_item if player.carried_item != "" else player.current_tool
	if held != _last_held:
		_last_held = held
		var nm := ""
		if player.carried_item != "":
			nm = "Carrying a %s" % player.carried_item.replace("_", " ")
		elif player.current_tool == "welder":
			nm = "Welding torch"
		elif player.current_tool != "":
			nm = Game.item_name(player.current_tool)
		_show_held_name(nm)


func _show_held_name(text: String) -> void:
	_held_name.text = text
	if _held_name_tween and _held_name_tween.is_valid():
		_held_name_tween.kill()
	_held_name.modulate.a = 1.0 if text != "" else 0.0
	if text == "":
		return
	_held_name_tween = _held_name.create_tween()
	_held_name_tween.tween_interval(1.6)
	_held_name_tween.tween_property(_held_name, "modulate:a", 0.0, 0.6)


## Context key hints on the right: what the keys do with what's in hand right now (current bindings).
func _update_hints() -> void:
	var rows := PackedStringArray()
	var k := func(action: String, what: String) -> void: rows.append("[%s]  %s" % [Settings.key_label(action), what])
	if player and not player.downed and not Game.ui_open:
		var train := Game.train
		if player.carried_item != "":
			k.call("interact", "Place the %s" % player.carried_item)
			k.call("drop", "Put it back")
		else:
			match player.current_tool:
				"hammer":
					k.call("attack", "Hit · nail · bolt")
				"wrench":
					k.call("attack", "Tighten a wheel")
				"nail_gun":
					k.call("attack", "Shoot a nail")
				"welder":
					k.call("attack", "Hold to weld")
					rows.append("Cable %d%%" % int((1.0 - player.cable_tension) * 100.0))
				"come_along":
					var hooked := train != null and is_instance_valid(train.hook)
					var anchored := train != null and is_instance_valid(train.anchor)
					if train != null and train.tipped and hooked and anchored:
						k.call("attack", "Pull")
					elif train != null and train.tipped and hooked:
						k.call("attack", "Chain to a tree")
					else:
						k.call("attack", "Hook the lifting eye")
					if hooked or anchored:
						k.call("winch_release", "Release")
				_:
					if Game.item_kind(player.current_tool) == "food":
						var info: Dictionary = Game.ITEMS[player.current_tool]
						k.call("attack", "Eat (+%d)" % int(info.get("heal", 0.0)))
			if player.focused and player.focused.get_prompt(player) != "":
				k.call("interact", "Use")
		if Game.role == "impostor":
			k.call("sabotage_menu", "Sabotage")
		k.call("inventory", "Inventory")
		k.call("show_help", "Help")
	_hints.text = Settings.hint("\n".join(rows))


func _update_sabotage() -> void:
	_sabotage.visible = Game.role == "impostor" and Game.sabotage != null and not Game.ui_open
	if not _sabotage.visible:
		return
	var lines := PackedStringArray(["Impostor (secret)  ·  [X] %s" % ("close" if Game.sabotage_menu_open else "sabotage menu")])
	if Game.sabotage_menu_open:
		for id: String in SabotageManager.ABILITIES:
			var info: Dictionary = SabotageManager.ABILITIES[id]
			var cd: float = Game.sabotage.cooldowns[id]
			var state := "unavailable" if Game.sabotage.locked else ("ready" if cd <= 0.0 else "%ds" % int(cd))
			lines.append("[%d]  %s  (%s)" % [info.key, info.label, state])
	_sabotage.text = Settings.hint("\n".join(lines))


# --- Team pool and hotbar ----------------------------------------------------------------------------

func _refresh_team() -> void:
	if _team == null:
		return
	for item: String in TEAM_ORDER:
		_team.set_count(item, Game.count(item))
	if _shop_gold:
		_refresh_shop()


func _refresh_hotbar() -> void:
	if _hotbar.is_empty():
		return
	var a := Game.slots()
	for i in _hotbar.size():
		var s: Dictionary = a[i]
		_hotbar[i].set_item(str(s.get("id", "")), int(s.get("n", 0)))
	if _shop_gold:
		_refresh_shop()


# --- Objective ----------------------------------------------------------------------------------------

func _on_objective_changed(text: Variant = "") -> void:
	var t := str(text)
	if t == _objective_text:
		return
	_objective_text = t
	if t != "":
		_flash_objective(t)


## A short line under the train bars (the objective changed, a station is near), then it fades.
func _flash_objective(text: String) -> void:
	_objective.text = text
	if _objective_tween and _objective_tween.is_valid():
		_objective_tween.kill()
	_objective_tween = _objective.create_tween()
	_objective_tween.tween_property(_objective, "modulate:a", 1.0, 0.25)
	_objective_tween.tween_interval(5.0)
	_objective_tween.tween_property(_objective, "modulate:a", 0.0, 0.8)


# --- Shop ---------------------------------------------------------------------------------------------

func _build_shop() -> void:
	_shop_dim = ColorRect.new()
	_shop_dim.color = Color(0.02, 0.03, 0.06, 0.5)
	_shop_dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	_shop_dim.mouse_filter = Control.MOUSE_FILTER_STOP
	_shop_dim.visible = false
	_root.add_child(_shop_dim)
	_shop = PanelContainer.new()
	_shop.add_theme_stylebox_override("panel", HudStyle.panel_box(22.0, 22.0))
	_shop.visible = false
	_root.add_child(_shop)
	_place(_shop, 0.5, 0.5, Vector2(-500, -330), Vector2(1000, 0))
	_shop.grow_horizontal = Control.GROW_DIRECTION_BOTH
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 14)
	_shop.add_child(box)
	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 12)
	box.add_child(head)
	_shop_title = HudStyle.label("Shop", 32, HudStyle.WHITE, 700)
	_shop_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(_shop_title)
	var coin := InventoryWindow.IconBox.new()
	coin.kind = "coin"
	coin.color = HudStyle.GOLD
	coin.custom_minimum_size = Vector2(28, 28)
	coin.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	head.add_child(coin)
	_shop_gold = HudStyle.label("0", 28, HudStyle.WHITE, 700)
	head.add_child(_shop_gold)
	var sub := HudStyle.label("Paid with the crew's gold. TEAM items go to the shared supplies, YOU items into your own inventory.", 15, HudStyle.SOFT, 500)
	box.add_child(sub)
	_shop_list = GridContainer.new()
	_shop_list.columns = 3
	_shop_list.add_theme_constant_override("h_separation", 10)
	_shop_list.add_theme_constant_override("v_separation", 10)
	box.add_child(_shop_list)
	var foot := HBoxContainer.new()
	foot.add_theme_constant_override("separation", 12)
	box.add_child(foot)
	_shop_sell = Button.new()
	_shop_sell.pressed.connect(func() -> void: Game.sell_nuggets())
	foot.add_child(_shop_sell)
	var gap := Control.new()
	gap.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	foot.add_child(gap)
	var close := Button.new()
	close.text = Settings.hint("Close  [E / Esc]")
	close.set_meta("hint", "Close  [E / Esc]")
	close.pressed.connect(close_shop)
	foot.add_child(close)


func open_shop(station: Station) -> void:
	if inventory.is_open:
		inventory.close()
	_shop_title.text = station.display_name()
	for c in _shop_list.get_children():
		c.queue_free()
	for id: String in Game.SHOP:
		_shop_list.add_child(_shop_card(id))
	_refresh_shop()
	_shop.visible = true
	_shop_dim.visible = true
	for b in _shop.find_children("*", "Button", true, false):
		if b.has_meta("hint"):
			(b as Button).text = Settings.hint(str(b.get_meta("hint")))
	_shop.modulate.a = 0.0
	_shop.create_tween().tween_property(_shop, "modulate:a", 1.0, 0.15)
	_shop_opened_frame = Engine.get_process_frames()
	Game.open_ui(&"shop")


func _shop_card(id: String) -> Control:
	var entry: Dictionary = Game.SHOP[id]
	var label := str(entry.label)
	var title := Game.short_label(entry)
	var desc := label.substr(title.length() + 2).trim_suffix(")") if label.length() > title.length() else ""
	var gives: Dictionary = entry.gives
	var item := str(gives.keys()[0])
	var card := PanelContainer.new()
	var sb := HudStyle.frame_box(14.0, 1.5, Color(1, 1, 1, 0.06), Color(1, 1, 1, 0.35), false)
	sb.set_content_margin_all(10)
	card.add_theme_stylebox_override("panel", sb)
	card.custom_minimum_size = Vector2(312, 74)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	card.add_child(row)
	var slot := ItemSlot.create(-1, 52.0)
	slot.set_item(item, int(gives[item]))
	slot.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(slot)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 0)
	v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	v.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_child(v)
	var th := HBoxContainer.new()
	th.add_theme_constant_override("separation", 6)
	v.add_child(th)
	th.add_child(HudStyle.label(title, 17, HudStyle.WHITE, 650))
	var team := Game.is_team_item(item)
	th.add_child(HudStyle.label("TEAM" if team else "YOU", 12, HudStyle.GOOD if team else HudStyle.GOLD, 700))
	if desc != "":
		var d := HudStyle.label(Settings.hint(desc), 13, HudStyle.SOFT, 500)
		d.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		d.custom_minimum_size = Vector2(150, 0)
		v.add_child(d)
	var buy := Button.new()
	buy.text = "%d" % int(entry.price)
	buy.icon = _coin_texture()
	buy.add_theme_constant_override("icon_max_width", 20)
	buy.custom_minimum_size = Vector2(72, 40)
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
	var n := Game.count("gold_nugget")
	_shop_sell.text = "Sell %d gold nugget%s  (+%d gold)" % [n, "" if n == 1 else "s", n * Game.NUGGET_PRICE]
	_shop_sell.disabled = n <= 0


func close_shop() -> void:
	_shop.visible = false
	_shop_dim.visible = false
	Game.close_ui(&"shop")


static var _coin: Texture2D


## A small gold coin picture for the price buttons (drawn once).
static func _coin_texture() -> Texture2D:
	if _coin == null:
		var img := Image.create(32, 32, false, Image.FORMAT_RGBA8)
		for y in 32:
			for x in 32:
				var d := Vector2(x + 0.5, y + 0.5).distance_to(Vector2(16, 16))
				var a := clampf(14.5 - d, 0.0, 1.0)
				var c := HudStyle.GOLD if d < 11.0 or d > 12.5 else HudStyle.GOLD.darkened(0.25)
				img.set_pixel(x, y, Color(c, a))
		_coin = ImageTexture.create_from_image(img)
	return _coin


# --- Messages -----------------------------------------------------------------------------------------

## A small toast at the top right (Game.message): white text on a faint glass pill, gone after a few seconds.
func toast(text: String) -> void:
	var holder := Control.new()
	holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var pill := PanelContainer.new()
	var sb := HudStyle.frame_box(12.0, 1.5, HudStyle.GLASS_STRONG, Color(1, 1, 1, 0.35), true)
	sb.content_margin_left = 12
	sb.content_margin_right = 12
	sb.content_margin_top = 5
	sb.content_margin_bottom = 6
	pill.add_theme_stylebox_override("panel", sb)
	var l := HudStyle.label(Settings.hint(text), 16, HudStyle.WHITE, 500)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.custom_minimum_size = Vector2(0, 0)
	var w := minf(HudStyle.text_width(l.text, 16, 500) + 4.0, 396.0)
	l.custom_minimum_size.x = w
	pill.add_child(l)
	holder.add_child(pill)
	_toasts.add_child(holder)
	while _toasts.get_child_count() > MAX_TOASTS:
		_toasts.get_child(0).free()
	var sz := pill.get_combined_minimum_size()
	holder.custom_minimum_size = Vector2(420, sz.y)
	pill.position = Vector2(420 - sz.x + 60, 0)
	pill.modulate.a = 0.0
	var tw := pill.create_tween()
	tw.set_parallel()
	tw.tween_property(pill, "position:x", 420 - sz.x, 0.25).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.tween_property(pill, "modulate:a", 1.0, 0.2)
	tw.chain().tween_interval(4.5)
	tw.chain().tween_property(pill, "modulate:a", 0.0, 0.7)
	tw.chain().tween_property(holder, "custom_minimum_size:y", 0.0, 0.2)
	tw.chain().tween_callback(holder.queue_free)


## The opening title: one title line and one small hint. It fades after a few seconds, or once the player walks.
func show_intro(title: String, hint: String) -> void:
	_show_banner("%s\n%s" % [title, hint], 3.5)
	_intro_since = Time.get_ticks_msec()


func _end_intro_on_move() -> void:
	if _intro_since < 0 or not _banner_active:
		return
	if Time.get_ticks_msec() - _intro_since > 1200 and player and player.velocity.length() > 1.5:
		_intro_since = -1
		if _banner_tween and _banner_tween.is_valid():
			_banner_tween.kill()
		_banner_tween = _banner.create_tween()
		_banner_tween.tween_property(_banner, "modulate:a", 0.0, 0.5)
		_banner_tween.tween_callback(func() -> void:
			_banner_active = false
			_banner.hide())


## A banner: a big rounded title, a thin white rule and a smaller line, floating over the view (no panel).
func _show_banner(text: String, hold := 4.0) -> void:
	_intro_since = -1
	var parts := Settings.hint(text).split("\n", true, 1)
	_banner_title.text = parts[0]
	_banner_sub.text = parts[1] if parts.size() > 1 else ""
	_banner_sub.visible = _banner_sub.text != ""
	_banner_active = true
	_banner.visible = not Game.ui_open
	if _banner_tween and _banner_tween.is_valid():
		_banner_tween.kill()
	_banner.modulate.a = 0.0
	_banner.pivot_offset = Vector2(450, 30)
	_banner.scale = Vector2(0.92, 0.92)
	_banner_tween = _banner.create_tween()
	_banner_tween.set_parallel()
	_banner_tween.tween_property(_banner, "modulate:a", 1.0, 0.25)
	_banner_tween.tween_property(_banner, "scale", Vector2.ONE, 0.35).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	_banner_tween.chain().tween_interval(hold)
	_banner_tween.chain().tween_property(_banner, "modulate:a", 0.0, 0.8)
	_banner_tween.chain().tween_callback(func() -> void:
		_banner_active = false
		_banner.hide())


# --- Helpers ----------------------------------------------------------------------------------------------

## Item / tool picture rendered in Blender (assets/icons/<id>.png), or null.
static func icon_for(id: String) -> Texture2D:
	if id == "gold_nugget":
		id = "gold"
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


## The HUD's theme: Fredoka everywhere, glass buttons with white outlines, styled tooltips.
static func hud_theme() -> Theme:
	if _theme:
		return _theme
	var t := Theme.new()
	t.default_font = HudStyle.font(600)
	t.default_font_size = 18
	t.set_color("font_color", "Label", HudStyle.WHITE)
	var states := {
		"normal": [Color(1, 1, 1, 0.08), Color(1, 1, 1, 0.75)],
		"hover": [Color(1, 1, 1, 0.22), HudStyle.WHITE],
		"pressed": [Color(1, 1, 1, 0.32), HudStyle.WHITE],
		"disabled": [Color(1, 1, 1, 0.03), Color(1, 1, 1, 0.25)],
		"focus": [Color(0, 0, 0, 0), Color(1, 1, 1, 0.0)],
	}
	for st: String in states:
		var sb := HudStyle.frame_box(12.0, 2.0, states[st][0], states[st][1], false)
		sb.content_margin_left = 14
		sb.content_margin_right = 14
		sb.content_margin_top = 6
		sb.content_margin_bottom = 7
		t.set_stylebox(st, "Button", sb)
	t.set_color("font_color", "Button", HudStyle.WHITE)
	t.set_color("font_hover_color", "Button", HudStyle.WHITE)
	t.set_color("font_pressed_color", "Button", HudStyle.WHITE)
	t.set_color("font_focus_color", "Button", HudStyle.WHITE)
	t.set_color("font_disabled_color", "Button", Color(1, 1, 1, 0.35))
	t.set_color("icon_disabled_color", "Button", Color(1, 1, 1, 0.35))
	t.set_font_size("font_size", "Button", 18)
	# the one button to press: filled white with dark letters
	t.set_type_variation("HudAccent", "Button")
	var acc := {"normal": 0.92, "hover": 1.0, "pressed": 0.8}
	for st: String in acc:
		var sb := HudStyle.frame_box(12.0, 2.0, Color(1, 1, 1, acc[st]), HudStyle.WHITE, false)
		sb.content_margin_left = 14
		sb.content_margin_right = 14
		sb.content_margin_top = 6
		sb.content_margin_bottom = 7
		t.set_stylebox(st, "HudAccent", sb)
	for c: String in ["font_color", "font_hover_color", "font_pressed_color", "font_focus_color"]:
		t.set_color(c, "HudAccent", Color("1d2433"))
	t.set_stylebox("panel", "TooltipPanel", HudStyle.panel_box(10.0, 8.0))
	t.set_color("font_color", "TooltipLabel", HudStyle.WHITE)
	t.set_font("font", "TooltipLabel", HudStyle.font(500))
	t.set_font_size("font_size", "TooltipLabel", 15)
	_theme = t
	return t


# --- Small drawn widgets ------------------------------------------------------------------------------

## The shared team pool as white icon + number pairs (two rows), each number pops when it changes.
class TeamCounters extends Control:
	const W := 300.0
	const ROWS := [["wood", "rail", "nails", "bolts"], ["engine_oil", "wheel", "gold"]]
	var counts := {}
	var _flash := {}       # item -> [time left, gained]

	func _init() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func set_count(item: String, n: int) -> void:
		if counts.has(item) and int(counts[item]) != n:
			_flash[item] = [0.8, n > int(counts[item])]
		counts[item] = n
		queue_redraw()

	func _process(delta: float) -> void:
		if _flash.is_empty():
			return
		for k: String in _flash.keys():
			_flash[k][0] -= delta
			if _flash[k][0] <= 0.0:
				_flash.erase(k)
		queue_redraw()

	func _draw() -> void:
		var cell := 74.0
		for r in ROWS.size():
			var items: Array = ROWS[r]
			var y := 4.0 + r * 30.0
			var x := W - items.size() * cell
			for item: String in items:
				var col := HudStyle.WHITE
				var pop := 0.0
				if _flash.has(item):
					var f: float = _flash[item][0] / 0.8
					col = HudStyle.WHITE.lerp(HudStyle.GOOD if _flash[item][1] else HudStyle.DANGER, f)
					pop = f
				var icol := HudStyle.GOLD if item == "gold" else col
				var isz := 22.0 + pop * 4.0
				HudStyle.draw_icon(self, HudStyle.item_icon_kind(item), Rect2(Vector2(x + 2.0 - pop * 2.0, y + 1.0 - pop * 2.0), Vector2(isz, isz)), icol)
				HudStyle.draw_text(self, Vector2(x + 30.0, y + 19.0), str(counts.get(item, 0)), 19, col, 700)
				x += cell


## Top-right readout: speed and lever, fuel bar, freezing-wind warning. Text and icons only, no panel.
class TrainReadout extends Control:
	const W := 220.0
	var speed := 0.0
	var lever := 0
	var fuel := 1.0
	var wind := false
	var _t := 0.0

	func _init() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func _process(delta: float) -> void:
		_t += delta
		if not HudStyle.headless:
			queue_redraw()

	func _draw() -> void:
		var right := W
		# speed + lever
		var lever_text: String = ["Reverse", "Stop", "Forward"][clampi(lever + 1, 0, 2)]
		var lever_col := HudStyle.GOOD if lever > 0 else (HudStyle.COLD if lever < 0 else HudStyle.SOFT)
		var sp := "%d km/h" % int(speed)
		var tw := HudStyle.text_width(sp, 22, 700)
		HudStyle.draw_text(self, Vector2(right - tw, 24), sp, 22, HudStyle.WHITE, 700)
		HudStyle.draw_icon(self, "gauge", Rect2(right - tw - 30.0, 4, 24, 24))
		var lw := HudStyle.text_width(lever_text, 15, 600)
		HudStyle.draw_text(self, Vector2(right - lw, 44), lever_text, 15, lever_col, 600)
		# fuel
		var fr := Rect2(right - 150.0, 54, 150.0, 14)
		var fcol := HudStyle.WARM if fuel > 0.15 else HudStyle.DANGER
		HudStyle.draw_bar(self, fr, fuel, fcol, -1.0, 0.0, HudStyle.WHITE if fuel > 0.15 else HudStyle.WHITE.lerp(HudStyle.DANGER, 0.5 + 0.5 * sin(_t * 7.0)))
		HudStyle.draw_icon(self, "flame", Rect2(fr.position.x - 24.0, 51, 20, 20))
		if wind:
			var t := "Freezing wind"
			var ww := HudStyle.text_width(t, 15, 600)
			HudStyle.draw_text(self, Vector2(right - ww, 92), t, 15, HudStyle.COLD, 600)
			HudStyle.draw_icon(self, "snow", Rect2(right - ww - 24.0, 77, 20, 20), HudStyle.COLD)


## Crosshair: a small white dot (bigger when something can be used), with a ring that fills while holding [E].
class Crosshair extends Control:
	var active := false
	var hold := 0.0

	func _ready() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func _draw() -> void:
		var c := size * 0.5
		var r := 3.2 if active else 2.4
		draw_circle(c + Vector2(0, 1), r + 1.2, Color(0, 0, 0, 0.35))
		draw_circle(c, r, HudStyle.WHITE)
		if hold > 0.0:
			draw_arc(c, 13.0, 0, TAU, 32, Color(1, 1, 1, 0.25), 3.0, true)
			draw_arc(c, 13.0, -PI * 0.5, -PI * 0.5 + TAU * clampf(hold, 0.0, 1.0), 32, HudStyle.WHITE, 3.0, true)


## A thin white rule with soft ends (under banner titles).
class Rule extends Control:
	func _init() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func _draw() -> void:
		var y := size.y * 0.5
		var w := minf(260.0, size.x * 0.4)
		var cx := size.x * 0.5
		for i in 12:
			var f := float(i) / 12.0
			var a := (1.0 - f) * 0.9
			var x0 := w * f
			var x1 := w * (f + 1.0 / 12.0)
			draw_line(Vector2(cx - x1, y), Vector2(cx - x0, y), Color(1, 1, 1, a), 2.0)
			draw_line(Vector2(cx + x0, y), Vector2(cx + x1, y), Color(1, 1, 1, a), 2.0)
