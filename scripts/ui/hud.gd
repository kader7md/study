class_name HUD
extends CanvasLayer
## Grey-box HUD in the RV There Yet layout:
## top centre train health + progress to the next station, top left inventory, top right train status,
## bottom left player health/frost, centre crosshair + prompt + hold bar, right side messages,
## bottom right the impostor's sabotage panel, plus the station shop window.

const HELP := """[F1] help   WASD move · Shift sprint · Space jump · E use / place · Q alt · G put item back
Tools: 1 hammer · 2 welder (hold LMB, plug in near a welder machine) · 3 nail gun · LMB use tool
Broken track: take planks → place → nail → take rails → place → weld · Lever: E forward / Q back
F2 play as impostor ([Tab] sabotage menu) · F3 world sabotage on/off · F5 last checkpoint · F6 new game"""

var player: Player

var _train_bar: ProgressBar
var _progress_bar: ProgressBar
var _progress_label: Label
var _status_label: Label
var _inventory_label: Label
var _health_bar: ProgressBar
var _frost_bar: ProgressBar
var _prompt: Label
var _hold_bar: ProgressBar
var _messages: VBoxContainer
var _banner: Label
var _sabotage_label: Label
var _hotbar: Label
var _help: Label
var _shop: PanelContainer
var _shop_list: VBoxContainer
var _shop_title: Label
var _shop_opened_frame := -1


func _ready() -> void:
	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(root)

	# Top centre: train health + journey progress
	var top := VBoxContainer.new()
	root.add_child(top)
	_place(top, 0.5, 0.0, Vector2(-260, 12), Vector2(520, 0))
	_train_bar = _bar(top, Color(0.2, 0.75, 0.3), Vector2(520, 22))
	_progress_bar = _bar(top, Color(0.25, 0.55, 0.95), Vector2(520, 14))
	_progress_label = _label(top, "", 18)
	_progress_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER

	# Top left: inventory
	_inventory_label = _label(root, "", 18)
	_inventory_label.position = Vector2(16, 12)

	# Top right: train status
	_status_label = _label(root, "", 18)
	_place(_status_label, 1.0, 0.0, Vector2(-430, 12), Vector2(410, 0))
	_status_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT

	# Bottom left: player
	var bl := VBoxContainer.new()
	root.add_child(bl)
	_place(bl, 0.0, 1.0, Vector2(16, -80), Vector2(260, 0))
	_health_bar = _bar(bl, Color(0.85, 0.2, 0.2), Vector2(260, 18))
	_frost_bar = _bar(bl, Color(0.6, 0.85, 1.0), Vector2(260, 12))
	_label(bl, "Health / Frost", 14)

	# Centre: crosshair, prompt, hold progress
	var cross := _label(root, "+", 28)
	_place(cross, 0.5, 0.5, Vector2(-8, -20), Vector2(16, 0))
	_prompt = _label(root, "", 20)
	_place(_prompt, 0.5, 0.5, Vector2(-400, 30), Vector2(800, 0))
	_prompt.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_hold_bar = _bar(root, Color(1.0, 0.8, 0.2), Vector2(200, 10))
	_place(_hold_bar, 0.5, 0.5, Vector2(-100, 100), Vector2(200, 10))

	# Right: messages
	_messages = VBoxContainer.new()
	root.add_child(_messages)
	_place(_messages, 1.0, 0.5, Vector2(-480, -60), Vector2(460, 0))

	# Banner
	_banner = _label(root, "", 34)
	_place(_banner, 0.5, 0.0, Vector2(-500, 150), Vector2(1000, 0))
	_banner.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER

	# Bottom right: sabotage panel (impostor only)
	_sabotage_label = _label(root, "", 18)
	_place(_sabotage_label, 1.0, 1.0, Vector2(-330, -150), Vector2(310, 0))
	_sabotage_label.add_theme_color_override("font_color", Color(1, 0.45, 0.45))

	# Bottom centre: tool hotbar + carried item
	_hotbar = _label(root, "", 20)
	_place(_hotbar, 0.5, 1.0, Vector2(-450, -150), Vector2(900, 0))
	_hotbar.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER

	# Bottom centre: help
	_help = _label(root, HELP, 15)
	_place(_help, 0.5, 1.0, Vector2(-450, -100), Vector2(900, 0))
	_help.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER

	_build_shop(root)

	Game.message.connect(_add_message)
	Game.banner.connect(_show_banner)


func _process(_delta: float) -> void:
	if Input.is_action_just_pressed("toggle_help"):
		_help.visible = not _help.visible
	var shop_just_opened := Engine.get_process_frames() == _shop_opened_frame
	if _shop.visible and not shop_just_opened and (Input.is_action_just_pressed("ui_cancel") or Input.is_action_just_pressed("interact")):
		close_shop()

	var train := Game.train
	var track := Game.track
	if train and track:
		_train_bar.value = train.health
		var next := mini(Game.next_station, Game.STATION_COUNT)
		var from := track.station_distances[next - 1]
		var to := track.station_distances[next]
		var center := train.center_distance()
		_progress_bar.value = clampf((center - from) / (to - from) * 100.0, 0.0, 100.0)
		if Game.next_station > Game.STATION_COUNT:
			_progress_label.text = "Final station reached!"
		else:
			_progress_label.text = "Next: Station %d / %d · %d m" % [next, Game.STATION_COUNT, maxi(int(to - center), 0)]
		var wind := "\n❄ FREEZING WIND" if Game.wind_active else ""
		var oil := "\nEngine oiled %ds" % int(train.oil_buff) if train.oil_buff > 0.0 else ""
		_status_label.text = "Speed %d km/h · Lever %s\nFuel %d%% · Wheels %d/%d%s%s" % [
			int(absf(train.speed) * 3.6), train.lever_text(), int(train.fuel), train.wheels, Train.MAX_WHEELS, wind, oil]

	var inv := PackedStringArray()
	for item: String in Game.inventory:
		if Game.inventory[item] > 0:
			inv.append("%s: %d" % [item.replace("_", " ").capitalize(), Game.inventory[item]])
	_inventory_label.text = "\n".join(inv)

	if player:
		_health_bar.value = player.health
		_frost_bar.value = player.frost
		_prompt.text = player.focused.get_prompt(player) if player.focused else ""
		if player.aiming_meteor:
			_prompt.text = "Aiming meteor: [LMB] drop · [RMB] cancel"
		_hold_bar.visible = player.hold_needed > 0.0 and player.hold_progress > 0.0
		if _hold_bar.visible:
			_hold_bar.value = player.hold_progress / player.hold_needed * 100.0
		var slots := PackedStringArray()
		var tools := player.available_tools()
		for i in Player.TOOLS.size():
			var id: String = Player.TOOLS[i]
			if id in tools:
				var name: String = Player.TOOL_NAMES[id]
				slots.append(("[ %d %s ]" if id == player.current_tool and player.carried_item == "" else "%d %s") % [i + 1, name])
		var line := "   ".join(slots)
		if player.carried_item != "":
			line = "Carrying: %s   ([E] place · [G] put back)" % player.carried_item.to_upper()
		elif player.current_tool == "welder":
			if is_instance_valid(player.welder_source):
				line += "\nCable %d%%%s" % [int(player.cable_tension * 100.0), "  ⚠ LIMIT" if player.cable_tension > 0.95 else ""]
			else:
				line += "\nWelder not plugged in: go near a welder machine (train utility car or station)"
		_hotbar.text = line

	_sabotage_label.visible = Game.role == "impostor"
	if _sabotage_label.visible and Game.sabotage:
		var lines := PackedStringArray(["IMPOSTOR (secret) · [Tab] %s" % ("close" if Game.sabotage_menu_open else "sabotage menu")])
		for id: String in SabotageManager.ABILITIES:
			if not Game.sabotage_menu_open:
				break
			var info: Dictionary = SabotageManager.ABILITIES[id]
			var cd: float = Game.sabotage.cooldowns[id]
			var state := "unavailable" if Game.sabotage.locked else ("ready" if cd <= 0.0 else "%ds" % int(cd))
			lines.append("%d  %s  [%s]" % [info.key, info.label, state])
		_sabotage_label.text = "\n".join(lines)


# --- Shop ---------------------------------------------------------------------

func _build_shop(root: Control) -> void:
	_shop = PanelContainer.new()
	_shop.visible = false
	root.add_child(_shop)
	_place(_shop, 0.5, 0.5, Vector2(-220, -220), Vector2(440, 0))
	var box := VBoxContainer.new()
	_shop.add_child(box)
	_shop_title = _label(box, "Shop", 24)
	_shop_list = VBoxContainer.new()
	box.add_child(_shop_list)
	var close := Button.new()
	close.text = "Close [E / Esc]"
	close.pressed.connect(close_shop)
	box.add_child(close)


func open_shop(station: Station) -> void:
	_shop_title.text = "%s: Shop" % station.display_name()
	for c in _shop_list.get_children():
		c.queue_free()
	for id: String in Game.SHOP:
		var b := Button.new()
		b.text = "%s: %d gold" % [Game.SHOP[id].label, Game.SHOP[id].price]
		b.pressed.connect(Game.buy.bind(id))
		_shop_list.add_child(b)
	_shop.visible = true
	_shop_opened_frame = Engine.get_process_frames()
	Game.ui_open = true


func close_shop() -> void:
	_shop.visible = false
	Game.ui_open = false


# --- Messages -----------------------------------------------------------------

func _add_message(text: String) -> void:
	var l := _label(_messages, text, 18)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.custom_minimum_size = Vector2(460, 0)
	while _messages.get_child_count() > 6:
		_messages.get_child(0).free()
	var tween := l.create_tween()
	tween.tween_interval(5.0)
	tween.tween_property(l, "modulate:a", 0.0, 1.0)
	tween.tween_callback(l.queue_free)


func _show_banner(text: String) -> void:
	_banner.text = text
	_banner.modulate.a = 1.0
	var tween := _banner.create_tween()
	tween.tween_interval(4.0)
	tween.tween_property(_banner, "modulate:a", 0.0, 1.0)


# --- Helpers ----------------------------------------------------------------------

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


func _label(parent: Control, text: String, size: int) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_outline_color", Color.BLACK)
	l.add_theme_constant_override("outline_size", 6)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(l)
	return l


func _bar(parent: Control, color: Color, size: Vector2) -> ProgressBar:
	var bar := ProgressBar.new()
	bar.custom_minimum_size = size
	bar.show_percentage = false
	bar.max_value = 100.0
	bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var fill := StyleBoxFlat.new()
	fill.bg_color = color
	fill.set_corner_radius_all(6)
	var bg := StyleBoxFlat.new()
	bg.bg_color = Color(0, 0, 0, 0.45)
	bg.set_corner_radius_all(6)
	bar.add_theme_stylebox_override("fill", fill)
	bar.add_theme_stylebox_override("background", bg)
	parent.add_child(bar)
	return bar
