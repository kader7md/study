class_name UiIcon
extends Control
## Small flat vector icons drawn in code (ink outline + one warm fill), sized to the control.
## kinds: heart, snow, body, wheel, engine, chassis, train, lock, unlock, flame, gauge, crown, pin, flag, mic, check, cross

@export var kind := "heart":
	set(v):
		kind = v
		queue_redraw()
@export var color := Color(0, 0, 0, 0):   # alpha 0 = the kind's default colour
	set(v):
		color = v
		queue_redraw()

const DEFAULT_COLORS := {
	"heart": UiTheme.HEALTH, "snow": UiTheme.FROST, "body": UiTheme.BODY_GREEN, "wheel": UiTheme.WHEEL_YELLOW,
	"engine": UiTheme.ENGINE_RED, "chassis": UiTheme.CHASSIS_BLUE, "train": UiTheme.JOURNEY, "lock": UiTheme.HONEY,
	"unlock": UiTheme.CREAM_DARK, "flame": UiTheme.JOURNEY, "gauge": UiTheme.CREAM, "crown": UiTheme.WHEEL_YELLOW,
	"pin": UiTheme.RUST, "flag": UiTheme.RUST, "mic": UiTheme.TEAL, "check": UiTheme.BODY_GREEN, "cross": UiTheme.DANGER,
}


static func create(icon_kind: String, px := 28, tint := Color(0, 0, 0, 0)) -> UiIcon:
	var i := UiIcon.new()
	i.kind = icon_kind
	i.color = tint
	i.custom_minimum_size = Vector2(px, px)
	i.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return i


func _draw() -> void:
	var s := minf(size.x, size.y)
	var o := (size - Vector2(s, s)) * 0.5
	var fill: Color = color if color.a > 0.0 else DEFAULT_COLORS.get(kind, UiTheme.CREAM)
	draw_icon(self, kind, Rect2(o, Vector2(s, s)), fill)


## Draws an icon into any CanvasItem (so other widgets can paint icons inline).
static func draw_icon(ci: CanvasItem, icon_kind: String, r: Rect2, fill: Color) -> void:
	var s := r.size.x
	var ink := UiTheme.INK
	var w := maxf(2.0, s * 0.09)       # outline width
	var p := func(x: float, y: float) -> Vector2: return r.position + Vector2(x, y) * s
	match icon_kind:
		"heart":
			var pts := PackedVector2Array()
			for i in 40:
				var t := TAU * i / 40.0
				var x := 16.0 * pow(sin(t), 3)
				var y := 13.0 * cos(t) - 5.0 * cos(2 * t) - 2.0 * cos(3 * t) - cos(4 * t)
				pts.append(p.call(0.5 + x / 38.0, 0.47 - y / 38.0))
			_poly(ci, pts, fill, ink, w)
			ci.draw_circle(p.call(0.36, 0.36), s * 0.06, Color(1, 1, 1, 0.55))
		"snow":
			for k in 3:
				var a := PI / 3.0 * k + PI / 2.0
				var d := Vector2(cos(a), sin(a)) * s * 0.42
				var c := r.position + Vector2(s, s) * 0.5
				ci.draw_line(c - d, c + d, ink, w * 2.0 + 2.0, true)
			for k in 3:
				var a := PI / 3.0 * k + PI / 2.0
				var d := Vector2(cos(a), sin(a)) * s * 0.42
				var c := r.position + Vector2(s, s) * 0.5
				ci.draw_line(c - d, c + d, fill, w * 1.2, true)
				for sgn: float in [-1.0, 1.0]:
					var tip := c + d * sgn * 0.62
					var side := d.normalized().orthogonal() * s * 0.12
					ci.draw_line(tip, tip + d * sgn * 0.25 + side, fill, w * 0.9, true)
					ci.draw_line(tip, tip + d * sgn * 0.25 - side, fill, w * 0.9, true)
		"body":
			# a boxcar: roof, body, two windows, wheels
			_rrect(ci, Rect2(p.call(0.1, 0.22), Vector2(0.8, 0.52) * s), s * 0.08, fill, ink, w)
			_rrect(ci, Rect2(p.call(0.04, 0.14), Vector2(0.92, 0.14) * s), s * 0.05, fill.darkened(0.25), ink, w)
			_rrect(ci, Rect2(p.call(0.2, 0.36), Vector2(0.22, 0.18) * s), s * 0.03, UiTheme.CREAM, ink, w * 0.6)
			_rrect(ci, Rect2(p.call(0.58, 0.36), Vector2(0.22, 0.18) * s), s * 0.03, UiTheme.CREAM, ink, w * 0.6)
			for x in [0.28, 0.72]:
				ci.draw_circle(p.call(x, 0.8), s * 0.12, ink)
				ci.draw_circle(p.call(x, 0.8), s * 0.05, UiTheme.CREAM_DARK)
		"wheel":
			var c: Vector2 = p.call(0.5, 0.5)
			ci.draw_circle(c, s * 0.46, ink)
			ci.draw_circle(c, s * 0.46 - w, fill)
			ci.draw_circle(c, s * 0.3, ink)
			ci.draw_circle(c, s * 0.3 - w * 0.7, fill.darkened(0.15))
			for k in 6:
				var a := TAU * k / 6.0
				ci.draw_line(c, c + Vector2(cos(a), sin(a)) * s * 0.3, ink, w * 0.8, true)
			ci.draw_circle(c, s * 0.09, ink)
		"engine":
			# a cog
			var c: Vector2 = p.call(0.5, 0.5)
			var pts := PackedVector2Array()
			var teeth := 8
			for i in teeth * 4:
				var a := TAU * i / (teeth * 4.0)
				var rr := 0.46 if (i % 4) in [0, 1] else 0.34
				pts.append(c + Vector2(cos(a + 0.2), sin(a + 0.2)) * s * rr)
			_poly(ci, pts, fill, ink, w)
			ci.draw_circle(c, s * 0.15, ink)
			ci.draw_circle(c, s * 0.15 - w * 0.6, UiTheme.CREAM)
		"chassis":
			# a ladder frame seen from above
			_rrect(ci, Rect2(p.call(0.12, 0.08), Vector2(0.18, 0.84) * s), s * 0.04, fill, ink, w)
			_rrect(ci, Rect2(p.call(0.7, 0.08), Vector2(0.18, 0.84) * s), s * 0.04, fill, ink, w)
			for y in [0.2, 0.46, 0.72]:
				_rrect(ci, Rect2(p.call(0.28, y), Vector2(0.44, 0.1) * s), 0.0, fill.lightened(0.2), ink, w * 0.7)
		"train":
			# little steam engine, facing right
			_rrect(ci, Rect2(p.call(0.08, 0.2), Vector2(0.32, 0.46) * s), s * 0.05, fill.darkened(0.15), ink, w)   # cab
			_rrect(ci, Rect2(p.call(0.36, 0.36), Vector2(0.5, 0.3) * s), s * 0.12, fill, ink, w)                  # boiler
			_rrect(ci, Rect2(p.call(0.66, 0.16), Vector2(0.12, 0.24) * s), s * 0.03, UiTheme.INK_SOFT, ink, w * 0.8) # chimney
			_rrect(ci, Rect2(p.call(0.14, 0.27), Vector2(0.16, 0.14) * s), s * 0.02, UiTheme.CREAM, ink, w * 0.5)   # window
			for x in [0.22, 0.5, 0.74]:
				ci.draw_circle(p.call(x, 0.76), s * 0.11, ink)
				ci.draw_circle(p.call(x, 0.76), s * 0.05, UiTheme.CREAM_DARK)
		"lock", "unlock":
			var open := icon_kind == "unlock"
			var sh_c: Vector2 = p.call(0.5, 0.42) + (Vector2(s * 0.14, -s * 0.08) if open else Vector2.ZERO)
			ci.draw_arc(sh_c, s * 0.2, PI, TAU, 16, ink, w * 2.2, true)
			ci.draw_arc(sh_c, s * 0.2, PI, TAU, 16, UiTheme.CREAM_DARK, w * 0.9, true)
			_rrect(ci, Rect2(p.call(0.18, 0.42), Vector2(0.64, 0.5) * s), s * 0.1, fill, ink, w)
			ci.draw_circle(p.call(0.5, 0.62), s * 0.07, ink)
			ci.draw_line(p.call(0.5, 0.64), p.call(0.5, 0.78), ink, w, true)
		"flame":
			var pts := PackedVector2Array()
			for i in 32:
				var t := TAU * i / 32.0
				var rr := 0.3 * (1.0 - 0.55 * pow(maxf(0.0, -sin(t)), 3.0))
				var x := 0.5 + cos(t) * rr * 0.95
				var y := 0.62 + sin(t) * rr - pow(maxf(0.0, -sin(t)), 6.0) * 0.32
				pts.append(p.call(x, y))
			_poly(ci, pts, fill, ink, w)
			ci.draw_circle(p.call(0.5, 0.7), s * 0.12, UiTheme.WHEEL_YELLOW)
		"gauge":
			var c: Vector2 = p.call(0.5, 0.62)
			ci.draw_circle(c, s * 0.44, ink)
			ci.draw_circle(c, s * 0.44 - w, fill)
			for k in 5:
				var a := PI + PI * k / 4.0
				var d := Vector2(cos(a), sin(a))
				ci.draw_line(c + d * s * 0.26, c + d * s * 0.36, ink, w * 0.7, true)
			ci.draw_line(c, c + Vector2(cos(-0.7), sin(-0.7)) * s * 0.3, UiTheme.RUST, w, true)
			ci.draw_circle(c, s * 0.07, ink)
		"crown":
			var pts := PackedVector2Array([p.call(0.1, 0.78), p.call(0.1, 0.3), p.call(0.3, 0.52), p.call(0.5, 0.2),
				p.call(0.7, 0.52), p.call(0.9, 0.3), p.call(0.9, 0.78)])
			_poly(ci, pts, fill, ink, w)
			for x in [0.1, 0.5, 0.9]:
				ci.draw_circle(p.call(x, 0.26 if x != 0.5 else 0.16), s * 0.07, ink)
		"pin":
			ci.draw_circle(p.call(0.5, 0.4), s * 0.3, ink)
			ci.draw_circle(p.call(0.5, 0.4), s * 0.3 - w, fill)
			ci.draw_circle(p.call(0.42, 0.32), s * 0.08, Color(1, 1, 1, 0.6))
		"flag":
			ci.draw_line(p.call(0.22, 0.08), p.call(0.22, 0.94), ink, w * 1.2, true)
			_poly(ci, PackedVector2Array([p.call(0.25, 0.1), p.call(0.88, 0.28), p.call(0.25, 0.48)]), fill, ink, w)
		"mic":
			_rrect(ci, Rect2(p.call(0.34, 0.08), Vector2(0.32, 0.52) * s), s * 0.16, fill, ink, w)
			ci.draw_arc(p.call(0.5, 0.42), s * 0.27, 0.0, PI, 16, ink, w, true)
			ci.draw_line(p.call(0.5, 0.7), p.call(0.5, 0.88), ink, w, true)
			ci.draw_line(p.call(0.32, 0.9), p.call(0.68, 0.9), ink, w, true)
		"check":
			ci.draw_polyline(PackedVector2Array([p.call(0.15, 0.52), p.call(0.4, 0.78), p.call(0.86, 0.24)]), ink, w * 2.6, true)
			ci.draw_polyline(PackedVector2Array([p.call(0.15, 0.52), p.call(0.4, 0.78), p.call(0.86, 0.24)]), fill, w * 1.3, true)
		"cross":
			for pair in [[p.call(0.2, 0.2), p.call(0.8, 0.8)], [p.call(0.8, 0.2), p.call(0.2, 0.8)]]:
				ci.draw_line(pair[0], pair[1], ink, w * 2.6, true)
			for pair in [[p.call(0.2, 0.2), p.call(0.8, 0.8)], [p.call(0.8, 0.2), p.call(0.2, 0.8)]]:
				ci.draw_line(pair[0], pair[1], fill, w * 1.3, true)
		_:
			ci.draw_circle(p.call(0.5, 0.5), s * 0.4, ink)
			ci.draw_circle(p.call(0.5, 0.5), s * 0.4 - w, fill)


static func _poly(ci: CanvasItem, pts: PackedVector2Array, fill: Color, ink: Color, w: float) -> void:
	ci.draw_colored_polygon(pts, fill)
	var closed := pts.duplicate()
	closed.append(pts[0])
	ci.draw_polyline(closed, ink, w, true)


static func _rrect(ci: CanvasItem, rect: Rect2, radius: float, fill: Color, ink: Color, w: float) -> void:
	var sb := StyleBoxFlat.new()
	sb.bg_color = fill
	sb.set_corner_radius_all(int(radius))
	sb.set_border_width_all(int(maxf(1.0, w)))
	sb.border_color = ink
	sb.anti_aliasing = true
	ci.draw_style_box(sb, rect)
