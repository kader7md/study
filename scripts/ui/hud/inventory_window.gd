class_name InventoryWindow
extends Control
## [Tab]: the player's own inventory. A 5x5 grid for everything else (coal, scrap, nuggets, food, keys...) and the
## hotbar row (keys 1-5) under it. Drag a slot onto another (or click one, then another) to move / swap / stack;
## right-click (or double-click) food to eat it. Beside it, the crew's SHARED team supplies, for reference.
## The mouse is free while it is open (Game.open_ui).

var player: Player
var is_open := false
var _slots: Array[ItemSlot] = []
var _card: PanelContainer
var _team_rows := {}     # item -> Label
var _picked := -1
var _hint: KeyText
var _detail: Label


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	var dim := ColorRect.new()
	dim.color = Color(0.02, 0.03, 0.06, 0.45)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_STOP
	dim.gui_input.connect(func(e: InputEvent) -> void:
		if e is InputEventMouseButton and e.pressed:
			_picked = -1
			refresh())
	add_child(dim)
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(center)
	_card = PanelContainer.new()
	_card.add_theme_stylebox_override("panel", HudStyle.panel_box(22.0, 24.0))
	center.add_child(_card)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 28)
	_card.add_child(row)

	# left: title, grid, hotbar
	var left := VBoxContainer.new()
	left.add_theme_constant_override("separation", 10)
	row.add_child(left)
	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 10)
	left.add_child(head)
	head.add_child(_icon_box("bag", 28))
	head.add_child(HudStyle.label("Inventory", 30, HudStyle.WHITE, 650))
	var grid := GridContainer.new()
	grid.columns = 5
	grid.add_theme_constant_override("h_separation", 8)
	grid.add_theme_constant_override("v_separation", 8)
	left.add_child(grid)
	for i in Game.SLOT_COUNT:
		_slots.append(_make_slot(i))
	for i in range(Game.HOTBAR_SIZE, Game.SLOT_COUNT):
		grid.add_child(_slots[i])
	var hb_label := HudStyle.label("Hotbar", 18, HudStyle.SOFT, 600)
	left.add_child(_spacer(4))
	left.add_child(hb_label)
	var hotbar := HBoxContainer.new()
	hotbar.add_theme_constant_override("separation", 8)
	left.add_child(hotbar)
	for i in Game.HOTBAR_SIZE:
		hotbar.add_child(_slots[i])

	# right: details, team supplies, how-to
	var right := VBoxContainer.new()
	right.add_theme_constant_override("separation", 10)
	right.custom_minimum_size = Vector2(250, 0)
	row.add_child(right)
	var th := HBoxContainer.new()
	th.add_theme_constant_override("separation", 8)
	right.add_child(th)
	th.add_child(_icon_box("team", 26))
	th.add_child(HudStyle.label("Team supplies", 22, HudStyle.WHITE, 650))
	var note := HudStyle.label("Shared by the whole crew: every repair\nuses these. Gold buys from station shops.", 14, HudStyle.SOFT, 500)
	right.add_child(note)
	var tg := GridContainer.new()
	tg.columns = 3
	tg.add_theme_constant_override("h_separation", 10)
	tg.add_theme_constant_override("v_separation", 6)
	right.add_child(tg)
	for item: String in Game.TEAM_ITEMS:
		tg.add_child(_icon_box(HudStyle.item_icon_kind(item), 22, HudStyle.GOLD if item == "gold" else HudStyle.WHITE))
		tg.add_child(HudStyle.label(Game.item_name(item), 16, HudStyle.SOFT, 500))
		var n := HudStyle.label("0", 18, HudStyle.WHITE, 700)
		n.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		n.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		tg.add_child(n)
		_team_rows[item] = n
	right.add_child(_spacer(6))
	_detail = HudStyle.label("", 15, HudStyle.WHITE, 500)
	_detail.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_detail.custom_minimum_size = Vector2(250, 60)
	right.add_child(_detail)
	var fill := Control.new()
	fill.size_flags_vertical = Control.SIZE_EXPAND_FILL
	right.add_child(fill)
	_hint = KeyText.create("", 15, HORIZONTAL_ALIGNMENT_LEFT)
	right.add_child(_hint)

	Game.personal_changed.connect(func(_peer: int) -> void: refresh())
	Game.inventory_changed.connect(refresh)
	Settings.changed.connect(func(_s: String, _k: String) -> void: _update_hint())
	visible = false


func _icon_box(kind: String, px: float, col := HudStyle.WHITE) -> Control:
	var c := IconBox.new()
	c.kind = kind
	c.color = col
	c.custom_minimum_size = Vector2(px, px)
	return c


func _spacer(h: float) -> Control:
	var c := Control.new()
	c.custom_minimum_size.y = h
	c.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return c


func _make_slot(i: int) -> ItemSlot:
	var s := ItemSlot.create(i, 62.0, true)
	if i < Game.HOTBAR_SIZE:
		s.key = str(i + 1)
	s.clicked.connect(_on_click)
	s.used.connect(_on_use)
	s.dropped.connect(_on_drop)
	s.mouse_entered.connect(func() -> void: _show_detail(i))
	return s


func _update_hint() -> void:
	_hint.text = Settings.hint("Drag or click to move\n[RMB] eat / use\n[Tab] / [Esc] close")


func open() -> void:
	if is_open:
		return
	is_open = true
	_picked = -1
	_update_hint()
	refresh()
	visible = true
	_card.pivot_offset = _card.size * 0.5
	_card.scale = Vector2(0.94, 0.94)
	_card.modulate.a = 0.0
	var tw := create_tween().set_parallel().set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.tween_property(_card, "scale", Vector2.ONE, 0.2)
	tw.tween_property(_card, "modulate:a", 1.0, 0.12)
	Game.open_ui(&"inventory")


func close() -> void:
	if not is_open:
		return
	is_open = false
	_picked = -1
	visible = false
	Game.close_ui(&"inventory")


func toggle() -> void:
	if is_open:
		close()
	else:
		open()


func refresh() -> void:
	if not is_inside_tree():
		return
	var a := Game.slots()
	for i in _slots.size():
		var s: Dictionary = a[i] if i < a.size() else {}
		_slots[i].set_item(str(s.get("id", "")), int(s.get("n", 0)))
		_slots[i].picked = i == _picked
		_slots[i].selected = player != null and i == player.hotbar_index
		_slots[i].queue_redraw()
	for item: String in _team_rows:
		(_team_rows[item] as Label).text = str(Game.count(item))


func _show_detail(i: int) -> void:
	var id := Game.slot_item(Net.local_id(), i)
	if id == "":
		_detail.text = ""
		return
	var info: Dictionary = Game.ITEMS.get(id, {})
	_detail.text = "%s\n%s" % [Game.item_name(id), Settings.hint(str(info.get("desc", "")))]


func _on_click(i: int) -> void:
	if _picked < 0:
		if Game.slot_item(Net.local_id(), i) != "":
			_picked = i
	else:
		if _picked != i:
			Game.move_slot(_picked, i)
		_picked = -1
	refresh()


func _on_drop(from: int, to: int) -> void:
	_picked = -1
	Game.move_slot(from, to)
	refresh()


func _on_use(i: int) -> void:
	_picked = -1
	var id := Game.slot_item(Net.local_id(), i)
	if Game.item_kind(id) == "food" and player:
		Net.request(player, &"eat_slot", [i])
	elif id != "":
		Game.say("Put the %s in your hotbar to use it" % Game.item_name(id).to_lower())
	refresh()


## A line icon as a control.
class IconBox extends Control:
	var kind := "item"
	var color := HudStyle.WHITE

	func _init() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func _draw() -> void:
		HudStyle.draw_icon(self, kind, Rect2(Vector2.ZERO, size), color)
