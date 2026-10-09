class_name KeyText
extends Control
## Text with key caps: every "[E]", "[LMB]", "[Tab]"... in it (already turned into the player's bindings by
## Settings.hint) is drawn as a little key cap or mouse icon. Several lines (\n) and left / centre / right alignment.

var text := "":
	set(v):
		if v != text:
			text = v
			_layout()
var font_size := 18:
	set(v):
		font_size = v
		_layout()
var align := HORIZONTAL_ALIGNMENT_CENTER
var color := HudStyle.WHITE
var weight := 600
var _lines: Array = []      # each: {"parts": [[is_key, str, width]], "w": float}
var _re: RegEx


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE


static func create(t := "", fs := 18, al := HORIZONTAL_ALIGNMENT_CENTER) -> KeyText:
	var k := KeyText.new()
	k.font_size = fs
	k.align = al
	k.text = t
	return k


func _cap_h() -> float:
	return font_size * 1.3


func _layout() -> void:
	if _re == null:
		_re = RegEx.create_from_string("\\[([^\\[\\]]{1,14})\\]")
	_lines.clear()
	var maxw := 0.0
	for raw in text.split("\n"):
		var parts := []
		var last := 0
		for m in _re.search_all(raw):
			if m.get_start() > last:
				var t := raw.substr(last, m.get_start() - last)
				parts.append([false, t, HudStyle.text_width(t, font_size, weight)])
			var keys := m.get_string(1).split(" / ")
			for i in keys.size():
				var k := keys[i].strip_edges()
				parts.append([true, k, HudStyle.keycap_width(k, _cap_h() - 4.0)])
				if i < keys.size() - 1:
					parts.append([false, " / ", HudStyle.text_width(" / ", font_size, weight)])
			last = m.get_end()
		if last < raw.length():
			var t2 := raw.substr(last)
			parts.append([false, t2, HudStyle.text_width(t2, font_size, weight)])
		var w := 0.0
		for p: Array in parts:
			w += float(p[2]) + (4.0 if p[0] else 0.0)
		_lines.append({"parts": parts, "w": w})
		maxw = maxf(maxw, w)
	custom_minimum_size = Vector2(maxw, _lines.size() * (_cap_h() + 6.0))
	update_minimum_size()
	queue_redraw()


func _draw() -> void:
	var y := 0.0
	var lh := _cap_h() + 6.0
	for line: Dictionary in _lines:
		var x := 0.0
		match align:
			HORIZONTAL_ALIGNMENT_CENTER:
				x = (size.x - float(line.w)) * 0.5
			HORIZONTAL_ALIGNMENT_RIGHT:
				x = size.x - float(line.w)
		for p: Array in line.parts:
			if p[0]:
				HudStyle.draw_keycap(self, Vector2(x + 2.0, y + 5.0), str(p[1]), _cap_h() - 4.0, color)
				x += float(p[2]) + 4.0
			else:
				HudStyle.draw_text(self, Vector2(x, y + lh * 0.5 + font_size * 0.36), str(p[1]), font_size, color, weight)
				x += float(p[2])
		y += lh
