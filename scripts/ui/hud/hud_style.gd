class_name HudStyle
extends RefCounted
## The in-game HUD look: minimal and clean. White rounded outlines with a soft drop shadow over a faint dark
## glass fill, diagonal-striped bar fills, small white line icons drawn in code, and a playful rounded display
## font (Fredoka, SIL OFL, assets/fonts). No heavy panels over the view.
## Everything here is static: widgets call HudStyle.draw_* from their own _draw().

const FONT_PATH := "res://assets/fonts/Fredoka-Variable.ttf"

const WHITE := Color(1.0, 1.0, 1.0, 0.97)
const SOFT := Color(1.0, 1.0, 1.0, 0.72)
const DIM := Color(1.0, 1.0, 1.0, 0.45)
const SHADOW := Color(0.02, 0.03, 0.06, 0.42)
## The empty part of bars and slots: a faint dark glass so white lines read on snow and sky alike.
const GLASS := Color(0.06, 0.08, 0.12, 0.30)
const GLASS_STRONG := Color(0.06, 0.08, 0.12, 0.62)

const BODY := Color("40c35a")
const WHEELS := Color("f7c531")
const ENGINE := Color("f2705f")
const CHASSIS := Color("3f9ff0")
const HEALTH := Color("f27a6c")
const WARM := Color("ffb44a")
const COLD := Color("7fd3f7")
const STAMINA := Color("b9e24f")
const GOLD := Color("ffd76a")
const DANGER := Color("ff4f4a")
const GOOD := Color("7be37d")

static var _fonts := {}
## Headless runs (tests, servers) draw nothing: widgets skip their per-frame redraws.
static var headless := DisplayServer.get_name() == "headless"


# --- Fonts and labels ---------------------------------------------------------------------------

## The rounded display font at a weight (300 light .. 700 bold).
static func font(weight := 600) -> Font:
	if _fonts.has(weight):
		return _fonts[weight]
	var fv := FontVariation.new()
	if ResourceLoader.exists(FONT_PATH):
		var base: Font = load(FONT_PATH)
		fv.base_font = base
		fv.variation_opentype = {TextServerManager.get_primary_interface().name_to_tag("wght"): weight}
	else:
		fv.base_font = ThemeDB.fallback_font
	var fallback := SystemFont.new()
	fallback.font_names = PackedStringArray(["Noto Sans Symbols 2", "DejaVu Sans", "sans-serif"])
	fv.fallbacks = [ThemeDB.fallback_font, fallback]
	_fonts[weight] = fv
	return fv


## A HUD label: white rounded letters with a thin dark outline and a soft shadow.
static func label(text: String, size := 18, color := WHITE, weight := 600) -> Label:
	var l := Label.new()
	l.text = text
	style_label(l, size, color, weight)
	return l


static func style_label(l: Label, size := 18, color := WHITE, weight := 600) -> void:
	l.add_theme_font_override("font", font(weight))
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	l.add_theme_color_override("font_outline_color", Color(0.02, 0.03, 0.06, 0.55))
	l.add_theme_constant_override("outline_size", maxi(3, size / 6))
	l.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.35))
	l.add_theme_constant_override("shadow_offset_x", 0)
	l.add_theme_constant_override("shadow_offset_y", 2)
	l.add_theme_constant_override("shadow_outline_size", maxi(3, size / 6))
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE


## Text drawn straight into a CanvasItem, with the same outline + shadow as label().
static func draw_text(ci: CanvasItem, pos: Vector2, text: String, size := 18, color := WHITE, weight := 600,
		align := HORIZONTAL_ALIGNMENT_LEFT, width := -1.0) -> void:
	var f := font(weight)
	var o := maxi(3, size / 6)
	ci.draw_string_outline(f, pos + Vector2(0, 2), text, align, width, size, o, Color(0, 0, 0, 0.3 * color.a))
	ci.draw_string_outline(f, pos, text, align, width, size, o, Color(0.02, 0.03, 0.06, 0.55 * color.a))
	ci.draw_string(f, pos, text, align, width, size, color)


static func text_width(text: String, size := 18, weight := 600) -> float:
	return font(weight).get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x


# --- Frames, bars and stripes ---------------------------------------------------------------------

## A rounded frame: faint glass inside, a white outline, a soft drop shadow.
static func frame_box(radius := 10.0, border := 2.0, bg := GLASS, line := WHITE, shadow := true) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = bg
	sb.set_corner_radius_all(int(radius))
	sb.set_border_width_all(int(round(border)))
	sb.border_color = line
	sb.corner_detail = 8
	sb.anti_aliasing = true
	if shadow:
		sb.shadow_color = Color(0, 0, 0, 0.28)
		sb.shadow_size = 6
		sb.shadow_offset = Vector2(0, 2)
	return sb


static func draw_frame(ci: CanvasItem, rect: Rect2, radius := 10.0, border := 2.0, bg := GLASS, line := WHITE,
		shadow := true) -> void:
	ci.draw_style_box(frame_box(radius, border, bg, line, shadow), rect)


## A panel for windows (inventory, shop, help): darker glass, a white outline, a big soft shadow.
static func panel_box(radius := 18.0, pad := 18.0) -> StyleBoxFlat:
	var sb := frame_box(radius, 2.5, Color(0.07, 0.09, 0.13, 0.82), Color(1, 1, 1, 0.9))
	sb.shadow_size = 18
	sb.shadow_offset = Vector2(0, 6)
	sb.shadow_color = Color(0, 0, 0, 0.35)
	sb.set_content_margin_all(pad)
	return sb


## Rounded rectangle outline as polygon points.
static func rounded_points(rect: Rect2, radius: float, seg := 6) -> PackedVector2Array:
	var r := minf(radius, minf(rect.size.x, rect.size.y) * 0.5)
	var pts := PackedVector2Array()
	if r <= 0.5:
		return PackedVector2Array([rect.position, Vector2(rect.end.x, rect.position.y), rect.end, Vector2(rect.position.x, rect.end.y)])
	var corners := [
		[Vector2(rect.end.x - r, rect.position.y + r), -PI * 0.5],
		[Vector2(rect.end.x - r, rect.end.y - r), 0.0],
		[Vector2(rect.position.x + r, rect.end.y - r), PI * 0.5],
		[Vector2(rect.position.x + r, rect.position.y + r), PI],
	]
	for c: Array in corners:
		for k in seg + 1:
			var a: float = c[1] + PI * 0.5 * k / seg
			var q: Vector2 = c[0] + Vector2(cos(a), sin(a)) * r
			# no duplicate points where two corners meet (a bar as short as it is high)
			if pts.is_empty() or pts[pts.size() - 1].distance_to(q) > 0.05:
				pts.append(q)
	if pts.size() > 1 and pts[0].distance_to(pts[pts.size() - 1]) <= 0.05:
		pts.remove_at(pts.size() - 1)
	return pts


## A diagonal-striped fill (the bars' signature look): `color` with lighter stripes, clipped to a rounded rect.
## `scroll` slides the stripes (pass a time for a slow crawl).
static func draw_striped(ci: CanvasItem, rect: Rect2, radius: float, color: Color, scroll := 0.0, stripes := true) -> void:
	if rect.size.x < 1.0 or rect.size.y < 1.0:
		return
	var shape := rounded_points(rect, radius)
	ci.draw_colored_polygon(shape, color)
	if stripes:
		var light := color.lightened(0.38)
		light.a = color.a
		var h := rect.size.y
		var w := maxf(h * 0.42, 4.0)
		var step := w * 2.0
		var x := rect.position.x - h - fposmod(scroll * 18.0, step)
		while x < rect.end.x:
			var band := PackedVector2Array([
				Vector2(x + h, rect.position.y), Vector2(x + h + w, rect.position.y),
				Vector2(x + w, rect.end.y), Vector2(x, rect.end.y)])
			for poly in Geometry2D.intersect_polygons(shape, band):
				if poly.size() >= 3 and _area(poly) > 0.5:
					ci.draw_colored_polygon(poly, light)
			x += step
	# a soft highlight along the top edge
	var top := Rect2(rect.position + Vector2(radius * 0.5, 1.5), Vector2(maxf(rect.size.x - radius, 0.0), maxf(rect.size.y * 0.18, 1.5)))
	if top.size.x > 2.0:
		ci.draw_rect(top, Color(1, 1, 1, 0.18 * color.a))


## A bar: frame + striped fill up to `value` (0..1). `ghost` (>= value) shows recent loss as a pale trail.
static func draw_bar(ci: CanvasItem, rect: Rect2, value: float, color: Color, ghost := -1.0, scroll := 0.0,
		line := WHITE) -> void:
	var radius := rect.size.y * 0.5
	draw_frame(ci, rect, radius, 2.0, GLASS, line)
	var inner := rect.grow(-3.5)
	var ir := inner.size.y * 0.5
	if ghost > value:
		var g := inner
		g.size.x = maxf(inner.size.x * clampf(ghost, 0.0, 1.0), inner.size.y)
		ci.draw_colored_polygon(rounded_points(g, ir), Color(1, 1, 1, 0.45))
	var v := clampf(value, 0.0, 1.0)
	if v > 0.001:
		var f := inner
		f.size.x = maxf(inner.size.x * v, inner.size.y)
		draw_striped(ci, f, ir, color, scroll)


# --- Key caps -------------------------------------------------------------------------------------

## Width a key glyph needs for this key label ("E", "LMB", "Space"...).
static func keycap_width(key: String, height := 24.0) -> float:
	if key in ["LMB", "RMB", "MMB", "Wheel"]:
		return height * 0.78
	return maxf(height, text_width(key, int(height * 0.58), 700) + height * 0.5)


## A key cap (rounded white outline, the key's name inside) or a little mouse with the button lit.
static func draw_keycap(ci: CanvasItem, pos: Vector2, key: String, height := 24.0, color := WHITE) -> void:
	var w := keycap_width(key, height)
	var r := Rect2(pos, Vector2(w, height))
	if key in ["LMB", "RMB", "MMB", "Wheel"]:
		draw_icon(ci, {"LMB": "mouse_l", "RMB": "mouse_r", "MMB": "mouse_m", "Wheel": "mouse_m"}[key], r, color)
		return
	draw_frame(ci, r, 6.0, 2.0, Color(0.06, 0.08, 0.12, 0.45), color)
	var fs := int(height * 0.58)
	draw_text(ci, Vector2(r.position.x, r.position.y + height * 0.5 + fs * 0.36), key, fs, color, 700, HORIZONTAL_ALIGNMENT_CENTER, w)


# --- Line icons -----------------------------------------------------------------------------------

## A small white line icon (kinds: shield wheel engine chassis skull hook train lock chevron plank rail nails bolt
## oil coin heart snow flame drop boost heavy gauge mouse_l mouse_r mouse_m team cross check food item bag star),
## with a soft shadow under it so it reads on any background.
static func draw_icon(ci: CanvasItem, kind: String, r: Rect2, color := WHITE, shadow := true) -> void:
	if shadow:
		_icon(ci, kind, Rect2(r.position + Vector2(0, 1.5), r.size), Color(0, 0, 0, 0.35 * color.a), true)
	_icon(ci, kind, r, color, false)


static func _icon(ci: CanvasItem, kind: String, r: Rect2, col: Color, is_shadow: bool) -> void:
	var s := minf(r.size.x, r.size.y)
	var o := r.position + (r.size - Vector2(s, s)) * 0.5
	var w := maxf(1.6, s * 0.1)
	if is_shadow:
		w += 1.2
	var p := func(x: float, y: float) -> Vector2: return o + Vector2(x, y) * s
	var line := func(pts: Array, closed := false) -> void:
		var arr := PackedVector2Array()
		for q: Vector2 in pts:
			arr.append(q)
		if closed:
			arr.append(pts[0])
		ci.draw_polyline(arr, col, w, true)
	var hole := Color(0.08, 0.09, 0.12, 0.9) if not is_shadow else col
	match kind:
		"shield":
			var pts := [p.call(0.5, 0.08), p.call(0.86, 0.2), p.call(0.82, 0.55), p.call(0.5, 0.92), p.call(0.18, 0.55), p.call(0.14, 0.2)]
			var poly := PackedVector2Array()
			for q: Vector2 in pts:
				poly.append(q)
			ci.draw_colored_polygon(poly, Color(col, col.a * 0.9))
			if not is_shadow:
				ci.draw_polyline(PackedVector2Array([p.call(0.34, 0.5), p.call(0.46, 0.62), p.call(0.68, 0.38)]), Color(0.15, 0.55, 0.25, 0.9), w, true)
		"wheel":
			var c: Vector2 = p.call(0.5, 0.5)
			ci.draw_arc(c, s * 0.4, 0, TAU, 28, col, w, true)
			ci.draw_circle(c, s * 0.09, col)
			for k in 6:
				var a := TAU * k / 6.0
				ci.draw_line(c + Vector2(cos(a), sin(a)) * s * 0.12, c + Vector2(cos(a), sin(a)) * s * 0.36, col, w * 0.7, true)
		"engine":
			var c: Vector2 = p.call(0.5, 0.5)
			var pts := []
			for i in 32:
				var a := TAU * i / 32.0
				var rr := 0.44 if (i % 4) in [0, 1] else 0.33
				pts.append(c + Vector2(cos(a + 0.2), sin(a + 0.2)) * s * rr)
			line.call(pts, true)
			ci.draw_arc(c, s * 0.13, 0, TAU, 16, col, w, true)
		"chassis":
			line.call([p.call(0.2, 0.1), p.call(0.2, 0.9)])
			line.call([p.call(0.8, 0.1), p.call(0.8, 0.9)])
			for y in [0.25, 0.5, 0.75]:
				line.call([p.call(0.2, y), p.call(0.8, y)])
		"skull":
			ci.draw_circle(p.call(0.5, 0.44), s * 0.36, col)
			ci.draw_rect(Rect2(p.call(0.3, 0.58), Vector2(0.4, 0.28) * s), col)
			if not is_shadow:
				ci.draw_circle(p.call(0.36, 0.46), s * 0.1, hole)
				ci.draw_circle(p.call(0.64, 0.46), s * 0.1, hole)
				ci.draw_colored_polygon(PackedVector2Array([p.call(0.5, 0.58), p.call(0.45, 0.68), p.call(0.55, 0.68)]), hole)
				for x in [0.4, 0.5, 0.6]:
					ci.draw_line(p.call(x, 0.74), p.call(x, 0.86), hole, maxf(1.2, s * 0.05))
		"hook":
			ci.draw_arc(p.call(0.5, 0.17), s * 0.11, 0, TAU, 14, col, w, true)
			line.call([p.call(0.5, 0.28), p.call(0.5, 0.58)])
			ci.draw_arc(p.call(0.4, 0.6), s * 0.22, 0.0, PI * 1.05, 16, col, w, true)
			line.call([p.call(0.18, 0.58), p.call(0.26, 0.5)])
		"train":
			line.call([p.call(0.06, 0.72), p.call(0.06, 0.26), p.call(0.36, 0.26), p.call(0.36, 0.42), p.call(0.9, 0.42), p.call(0.94, 0.72)], true)
			line.call([p.call(0.7, 0.42), p.call(0.7, 0.2), p.call(0.82, 0.2), p.call(0.82, 0.42)])
			for x in [0.22, 0.5, 0.76]:
				ci.draw_circle(p.call(x, 0.8), s * 0.09, col)
		"lock":
			ci.draw_arc(p.call(0.5, 0.42), s * 0.2, PI, TAU, 14, col, w, true)
			ci.draw_line(p.call(0.3, 0.42), p.call(0.3, 0.5), col, w)
			ci.draw_line(p.call(0.7, 0.42), p.call(0.7, 0.5), col, w)
			ci.draw_style_box(_box(col, s * 0.1), Rect2(p.call(0.2, 0.48), Vector2(0.6, 0.42) * s))
			if not is_shadow:
				ci.draw_circle(p.call(0.5, 0.66), s * 0.07, hole)
		"chevron":
			line.call([p.call(0.3, 0.15), p.call(0.7, 0.5), p.call(0.3, 0.85)])
		"plank":
			for k in 2:
				var y := 0.22 + k * 0.32
				line.call([p.call(0.1, y + 0.14), p.call(0.82, y - 0.06), p.call(0.9, y + 0.08), p.call(0.18, y + 0.28)], true)
		"rail":
			line.call([p.call(0.3, 0.18), p.call(0.7, 0.18), p.call(0.7, 0.3), p.call(0.57, 0.36), p.call(0.57, 0.66),
				p.call(0.82, 0.74), p.call(0.82, 0.86), p.call(0.18, 0.86), p.call(0.18, 0.74), p.call(0.43, 0.66),
				p.call(0.43, 0.36), p.call(0.3, 0.3)], true)
		"nails":
			for k in 2:
				var x := 0.34 + k * 0.32
				line.call([p.call(x - 0.15, 0.16), p.call(x + 0.15, 0.16)])
				line.call([p.call(x, 0.16), p.call(x, 0.74)])
				line.call([p.call(x - 0.06, 0.74), p.call(x, 0.9), p.call(x + 0.06, 0.74)])
		"bolt":
			var c: Vector2 = p.call(0.5, 0.5)
			var pts := []
			for i in 6:
				var a := TAU * i / 6.0 + PI / 6.0
				pts.append(c + Vector2(cos(a), sin(a)) * s * 0.4)
			line.call(pts, true)
			ci.draw_arc(c, s * 0.15, 0, TAU, 14, col, w, true)
		"oil":
			line.call([p.call(0.18, 0.4), p.call(0.66, 0.4), p.call(0.74, 0.88), p.call(0.12, 0.88)], true)
			line.call([p.call(0.66, 0.5), p.call(0.92, 0.3)])
			line.call([p.call(0.3, 0.4), p.call(0.3, 0.26), p.call(0.48, 0.26), p.call(0.48, 0.4)])
			ci.draw_circle(p.call(0.92, 0.48), s * 0.05, col)
		"coin":
			var c: Vector2 = p.call(0.5, 0.5)
			ci.draw_arc(c, s * 0.4, 0, TAU, 28, col, w, true)
			ci.draw_arc(c, s * 0.26, 0, TAU, 22, col, w * 0.7, true)
			ci.draw_line(p.call(0.5, 0.36), p.call(0.5, 0.64), col, w * 0.9, true)
		"heart":
			var pts := []
			for i in 32:
				var t := TAU * i / 32.0
				var x := 16.0 * pow(sin(t), 3)
				var y := 13.0 * cos(t) - 5.0 * cos(2 * t) - 2.0 * cos(3 * t) - cos(4 * t)
				pts.append(p.call(0.5 + x / 38.0, 0.47 - y / 38.0))
			line.call(pts, true)
		"snow":
			var c: Vector2 = p.call(0.5, 0.5)
			for k in 3:
				var a := PI / 3.0 * k + PI / 2.0
				var d := Vector2(cos(a), sin(a)) * s * 0.42
				ci.draw_line(c - d, c + d, col, w, true)
				for sgn: float in [-1.0, 1.0]:
					var tip := c + d * sgn * 0.6
					var side := d.normalized().orthogonal() * s * 0.11
					ci.draw_line(tip, tip + d * sgn * 0.25 + side, col, w * 0.8, true)
					ci.draw_line(tip, tip + d * sgn * 0.25 - side, col, w * 0.8, true)
		"flame":
			var pts := [p.call(0.52, 0.06), p.call(0.66, 0.24), p.call(0.8, 0.42), p.call(0.84, 0.62), p.call(0.76, 0.8),
				p.call(0.6, 0.92), p.call(0.4, 0.92), p.call(0.24, 0.8), p.call(0.17, 0.62), p.call(0.22, 0.44),
				p.call(0.34, 0.32), p.call(0.38, 0.5), p.call(0.48, 0.36)]
			line.call(pts, true)
			line.call([p.call(0.5, 0.86), p.call(0.38, 0.76), p.call(0.42, 0.62), p.call(0.52, 0.54), p.call(0.6, 0.66),
				p.call(0.62, 0.78), p.call(0.5, 0.86)])
		"drop":
			var pts := PackedVector2Array()
			for i in 24:
				var t := TAU * i / 24.0
				var q: Vector2 = p.call(0.5 + cos(t) * 0.27, 0.62 + sin(t) * 0.27)
				if sin(t) < -0.3:
					q = q.lerp(p.call(0.5, 0.08), clampf((-sin(t) - 0.3) * 1.4, 0.0, 1.0))
				pts.append(q)
			ci.draw_colored_polygon(pts, col)
		"boost":
			var pts := PackedVector2Array([p.call(0.58, 0.06), p.call(0.22, 0.56), p.call(0.48, 0.56), p.call(0.4, 0.94),
				p.call(0.8, 0.4), p.call(0.54, 0.4)])
			ci.draw_colored_polygon(pts, col)
		"heavy":
			ci.draw_arc(p.call(0.5, 0.26), s * 0.14, PI, TAU, 12, col, w, true)
			line.call([p.call(0.24, 0.4), p.call(0.76, 0.4), p.call(0.88, 0.88), p.call(0.12, 0.88)], true)
		"gauge":
			var c: Vector2 = p.call(0.5, 0.64)
			ci.draw_arc(c, s * 0.4, PI, TAU, 20, col, w, true)
			ci.draw_line(c, c + Vector2(cos(-0.75), sin(-0.75)) * s * 0.32, col, w, true)
			ci.draw_circle(c, s * 0.07, col)
		"mouse_l", "mouse_r", "mouse_m":
			var body := Rect2(p.call(0.12, 0.04), Vector2(0.76, 0.92) * s)
			ci.draw_style_box(_outline(col, s * 0.36, maxf(1.5, w * 0.8)), body)
			var mid: Vector2 = p.call(0.5, 0.42)
			ci.draw_line(Vector2(mid.x, body.position.y + 2.0), mid, col, maxf(1.2, w * 0.6))
			ci.draw_line(p.call(0.14, 0.42), p.call(0.86, 0.42), col, maxf(1.2, w * 0.6))
			if kind != "mouse_m":
				var left := kind == "mouse_l"
				var q := PackedVector2Array()
				var x0 := 0.17 if left else 0.53
				var x1 := 0.47 if left else 0.83
				q.append_array([p.call(x0, 0.4), p.call(x0, 0.2), p.call((x0 + x1) * 0.5, 0.09), p.call(x1, 0.08), p.call(x1, 0.4)])
				ci.draw_colored_polygon(q, col)
			else:
				ci.draw_style_box(_box(col, s * 0.05), Rect2(p.call(0.43, 0.14), Vector2(0.14, 0.22) * s))
		"team":
			for k in 2:
				var x := 0.34 + k * 0.32
				ci.draw_arc(p.call(x, 0.34), s * 0.13, 0, TAU, 14, col, w, true)
				ci.draw_arc(p.call(x, 0.92), s * 0.26, PI * 1.15, PI * 1.85, 12, col, w, true)
		"cross":
			line.call([p.call(0.22, 0.22), p.call(0.78, 0.78)])
			line.call([p.call(0.78, 0.22), p.call(0.22, 0.78)])
		"check":
			line.call([p.call(0.16, 0.52), p.call(0.4, 0.76), p.call(0.86, 0.26)])
		"food":
			ci.draw_arc(p.call(0.5, 0.58), s * 0.32, 0, TAU, 24, col, w, true)
			line.call([p.call(0.5, 0.28), p.call(0.56, 0.1)])
			line.call([p.call(0.56, 0.18), p.call(0.74, 0.12)])
		"bag":
			ci.draw_arc(p.call(0.5, 0.3), s * 0.15, PI, TAU, 12, col, w, true)
			ci.draw_style_box(_outline(col, s * 0.14, w), Rect2(p.call(0.16, 0.3), Vector2(0.68, 0.6) * s))
			line.call([p.call(0.3, 0.56), p.call(0.7, 0.56)])
		"star":
			var pts := []
			for i in 10:
				var a := -PI * 0.5 + TAU * i / 10.0
				var rr := 0.44 if i % 2 == 0 else 0.2
				pts.append(p.call(0.5, 0.54) + Vector2(cos(a), sin(a)) * rr * s)
			line.call(pts, true)
		"pin":
			ci.draw_arc(p.call(0.5, 0.38), s * 0.24, 0, TAU, 20, col, w, true)
			line.call([p.call(0.32, 0.54), p.call(0.5, 0.92), p.call(0.68, 0.54)])
		_:
			ci.draw_style_box(_outline(col, s * 0.18, w), Rect2(p.call(0.16, 0.16), Vector2(0.68, 0.68) * s))


static func _area(poly: PackedVector2Array) -> float:
	var a := 0.0
	for i in poly.size():
		var j := (i + 1) % poly.size()
		a += poly[i].x * poly[j].y - poly[j].x * poly[i].y
	return absf(a) * 0.5


static func _box(col: Color, radius: float) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = col
	sb.set_corner_radius_all(int(radius))
	sb.anti_aliasing = true
	return sb


static func _outline(col: Color, radius: float, w: float) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.draw_center = false
	sb.set_corner_radius_all(int(radius))
	sb.set_border_width_all(int(round(w)))
	sb.border_color = col
	sb.anti_aliasing = true
	return sb


## The line icon that stands for an item when it has no rendered picture.
static func item_icon_kind(item: String) -> String:
	match item:
		"wood": return "plank"
		"rail": return "rail"
		"nails": return "nails"
		"bolts": return "bolt"
		"engine_oil": return "oil"
		"wheel": return "wheel"
		"gold", "gold_nugget": return "coin"
		"key": return "lock"
		"medkit": return "heart"
	if Game.item_kind(item) == "food":
		return "food"
	return "item"
