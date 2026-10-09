class_name ItemSlot
extends Control
## One inventory / hotbar slot: a rounded square with a white outline, the item's picture, its stack count and
## (hotbar) the key number. In the inventory window it can be dragged onto another slot, clicked (pick up, click
## another slot to put down) and right-clicked (eat / use). The tooltip shows the item's name and what it does.

signal clicked(index: int)
signal used(index: int)
signal dropped(from: int, to: int)

var index := 0
var item := ""
var amount := 0
var key := ""
var selected := false
var picked := false
## Interactive: drag & drop, clicks and tooltips (the inventory window); the HUD's hotbar is display only.
var interactive := false
var _hover := false
var _pop := 0.0


static func create(slot_index: int, px := 64.0, is_interactive := false) -> ItemSlot:
	var s := ItemSlot.new()
	s.index = slot_index
	s.custom_minimum_size = Vector2(px, px)
	s.interactive = is_interactive
	s.mouse_filter = Control.MOUSE_FILTER_STOP if is_interactive else Control.MOUSE_FILTER_IGNORE
	return s


func set_item(id: String, n: int) -> void:
	if id != item or n != amount:
		if id == item and n > amount:
			_pop = 1.0
		item = id
		amount = n
		tooltip_text = Game.item_name(id) if id != "" else ""
		queue_redraw()


func _ready() -> void:
	mouse_entered.connect(func() -> void:
		_hover = true
		queue_redraw())
	mouse_exited.connect(func() -> void:
		_hover = false
		queue_redraw())


func _process(delta: float) -> void:
	if _pop > 0.0:
		_pop = maxf(_pop - delta * 3.0, 0.0)
		queue_redraw()


func _draw() -> void:
	var r := Rect2(Vector2.ZERO, size)
	var grow := 0.0
	if selected:
		grow = 3.0
	r = r.grow(grow)
	var bg := HudStyle.GLASS
	var line := Color(1, 1, 1, 0.75)
	var border := 2.0
	if selected:
		bg = Color(1, 1, 1, 0.22)
		line = HudStyle.WHITE
		border = 3.5
	if picked:
		line = HudStyle.GOLD
		border = 3.5
	if _hover and interactive:
		bg = Color(1, 1, 1, 0.16)
	HudStyle.draw_frame(self, r, 12.0, border, bg, line)
	if item != "":
		var tex := HUD.icon_for(item)
		var pad := size.x * 0.12
		var ir := Rect2(r.position + Vector2(pad, pad), r.size - Vector2(pad, pad) * 2.0)
		if _pop > 0.0:
			ir = ir.grow(_pop * 4.0)
		if tex:
			draw_texture_rect(tex, ir, false)
		else:
			HudStyle.draw_icon(self, HudStyle.item_icon_kind(item), ir.grow(-ir.size.x * 0.12), HudStyle.WHITE)
		if amount > 1:
			var fs := int(size.y * 0.26)
			HudStyle.draw_text(self, Vector2(r.position.x, r.end.y - 5.0), str(amount), fs, HudStyle.WHITE, 700,
				HORIZONTAL_ALIGNMENT_RIGHT, r.size.x - 7.0)
	if key != "":
		var ks := int(size.y * 0.22)
		HudStyle.draw_text(self, r.position + Vector2(7, ks + 3), key, ks, HudStyle.WHITE if selected else HudStyle.SOFT, 700)


# --- Inventory window: drag & drop, clicks, tooltip ----------------------------------------------

func _gui_input(event: InputEvent) -> void:
	if not interactive:
		return
	if event is InputEventMouseButton and event.pressed:
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_LEFT and not mb.double_click:
			clicked.emit(index)
			accept_event()
		elif mb.button_index == MOUSE_BUTTON_RIGHT or (mb.button_index == MOUSE_BUTTON_LEFT and mb.double_click):
			used.emit(index)
			accept_event()


func _get_drag_data(_at: Vector2) -> Variant:
	if not interactive or item == "":
		return null
	var preview := ItemSlot.create(index, size.x * 0.9)
	preview.set_item(item, amount)
	preview.modulate.a = 0.85
	var holder := Control.new()
	holder.add_child(preview)
	preview.position = -preview.custom_minimum_size * 0.5
	set_drag_preview(holder)
	return {"slot": index}


func _can_drop_data(_at: Vector2, data: Variant) -> bool:
	return interactive and data is Dictionary and (data as Dictionary).has("slot")


func _drop_data(_at: Vector2, data: Variant) -> void:
	dropped.emit(int(data.slot), index)


func _make_custom_tooltip(_for_text: String) -> Object:
	if item == "":
		return null
	var box := PanelContainer.new()
	box.add_theme_stylebox_override("panel", HudStyle.panel_box(10.0, 10.0))
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 2)
	box.add_child(v)
	v.add_child(HudStyle.label(Game.item_name(item), 18, HudStyle.WHITE, 650))
	var info: Dictionary = Game.ITEMS.get(item, {})
	var desc := str(info.get("desc", ""))
	if desc != "":
		var d := HudStyle.label(Settings.hint(desc), 14, HudStyle.SOFT, 500)
		d.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		d.custom_minimum_size.x = 220
		v.add_child(d)
	if Game.item_kind(item) == "food":
		var bits := PackedStringArray()
		if float(info.get("heal", 0.0)) > 0.0:
			bits.append("+%d health" % int(info.heal))
		if float(info.get("warm", 0.0)) > 0.0:
			bits.append("+%d warmth" % int(info.warm))
		if float(info.get("boost", 0.0)) > 0.0:
			bits.append("faster for %ds" % int(info.boost))
		v.add_child(HudStyle.label("  ·  ".join(bits) + "   (right-click to eat)", 14, HudStyle.GOOD, 600))
	return box
