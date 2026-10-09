class_name HudBar
extends Control
## One HUD bar: a line icon on the left, then a white-outlined rounded bar with a diagonal-striped fill.
## A pale "ghost" trail shows what was just lost; below `low` the outline pulses red.

var value := 1.0
var color := HudStyle.HEALTH
var icon := ""
var icon_color := HudStyle.WHITE
## Below this the bar warns (outline pulses).
var low := 0.25
## Stripes crawl slowly when true (e.g. warmth coming back).
var crawl := false
var _ghost := 1.0
var _t := 0.0


static func create(icon_kind: String, bar_color: Color, min_size: Vector2) -> HudBar:
	var b := HudBar.new()
	b.icon = icon_kind
	b.color = bar_color
	b.custom_minimum_size = min_size
	b.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return b


func set_value(v: float) -> void:
	v = clampf(v, 0.0, 1.0)
	if v > _ghost:
		_ghost = v
	value = v


func _process(delta: float) -> void:
	_t += delta
	if _ghost > value:
		_ghost = maxf(value, _ghost - delta * (0.08 + (_ghost - value) * 1.5))
	if not HudStyle.headless:
		queue_redraw()


func _draw() -> void:
	var h := size.y
	var x := 0.0
	if icon != "":
		var isz := h + 4.0
		HudStyle.draw_icon(self, icon, Rect2(Vector2(0, (h - isz) * 0.5), Vector2(isz, isz)), icon_color)
		x = isz + 6.0
	var r := Rect2(Vector2(x, 0), Vector2(size.x - x, h))
	var line := HudStyle.WHITE
	if value <= low:
		var k := 0.5 + 0.5 * sin(_t * 7.0)
		line = HudStyle.WHITE.lerp(HudStyle.DANGER, k)
	HudStyle.draw_bar(self, r, value, color, _ghost, _t if crawl else 0.0, line)
