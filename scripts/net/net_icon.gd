class_name NetIcon
extends Control
## Small icons drawn in code for the lobby and the crew list (no font glyphs needed):
## "crown" (host), "tick" (ready), "cross" (kick / not ready), "speaker" (talking), "copy", "plug" (port), "person".

const INK := Color("2a1c13")

var kind := "crown"
var color := Color("ffd27a")
var outline := INK


static func create(icon_kind: String, size_px: float, fill: Color = Color("ffd27a")) -> NetIcon:
	var i := NetIcon.new()
	i.kind = icon_kind
	i.color = fill
	i.custom_minimum_size = Vector2(size_px, size_px)
	i.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return i


func set_kind(icon_kind: String, fill: Color) -> void:
	kind = icon_kind
	color = fill
	queue_redraw()


func _draw() -> void:
	var s := minf(size.x, size.y)
	var o := Vector2((size.x - s) * 0.5, (size.y - s) * 0.5)
	var w := maxf(2.0, s * 0.09)
	match kind:
		"crown":
			var pts := PackedVector2Array([
				Vector2(0.1, 0.78), Vector2(0.1, 0.3), Vector2(0.32, 0.52), Vector2(0.5, 0.2),
				Vector2(0.68, 0.52), Vector2(0.9, 0.3), Vector2(0.9, 0.78)])
			_poly(pts, s, o, w)
			for p in [Vector2(0.1, 0.27), Vector2(0.5, 0.17), Vector2(0.9, 0.27)]:
				draw_circle(o + p * s, s * 0.08, outline)
				draw_circle(o + p * s, s * 0.05, color)
		"tick":
			draw_circle(o + Vector2(0.5, 0.5) * s, s * 0.48, outline)
			draw_circle(o + Vector2(0.5, 0.5) * s, s * 0.48 - w, color)
			var t := PackedVector2Array([o + Vector2(0.27, 0.52) * s, o + Vector2(0.43, 0.68) * s, o + Vector2(0.74, 0.34) * s])
			draw_polyline(t, Color("fff6e0"), s * 0.12, true)
		"cross":
			draw_circle(o + Vector2(0.5, 0.5) * s, s * 0.48, outline)
			draw_circle(o + Vector2(0.5, 0.5) * s, s * 0.48 - w, color)
			draw_line(o + Vector2(0.32, 0.32) * s, o + Vector2(0.68, 0.68) * s, Color("fff6e0"), s * 0.11, true)
			draw_line(o + Vector2(0.68, 0.32) * s, o + Vector2(0.32, 0.68) * s, Color("fff6e0"), s * 0.11, true)
		"speaker":
			_poly(PackedVector2Array([Vector2(0.12, 0.38), Vector2(0.3, 0.38), Vector2(0.52, 0.18), Vector2(0.52, 0.82),
				Vector2(0.3, 0.62), Vector2(0.12, 0.62)]), s, o, w)
			draw_arc(o + Vector2(0.5, 0.5) * s, s * 0.22, -0.9, 0.9, 12, outline, w, true)
			draw_arc(o + Vector2(0.5, 0.5) * s, s * 0.38, -0.9, 0.9, 12, outline, w, true)
		"copy":
			draw_rect(Rect2(o + Vector2(0.3, 0.1) * s, Vector2(0.56, 0.6) * s), color, true)
			draw_rect(Rect2(o + Vector2(0.3, 0.1) * s, Vector2(0.56, 0.6) * s), outline, false, w)
			draw_rect(Rect2(o + Vector2(0.12, 0.3) * s, Vector2(0.56, 0.6) * s), color.lightened(0.2), true)
			draw_rect(Rect2(o + Vector2(0.12, 0.3) * s, Vector2(0.56, 0.6) * s), outline, false, w)
		"plug":
			draw_rect(Rect2(o + Vector2(0.25, 0.35) * s, Vector2(0.5, 0.35) * s), color, true)
			draw_rect(Rect2(o + Vector2(0.25, 0.35) * s, Vector2(0.5, 0.35) * s), outline, false, w)
			draw_line(o + Vector2(0.38, 0.35) * s, o + Vector2(0.38, 0.12) * s, outline, w * 1.4)
			draw_line(o + Vector2(0.62, 0.35) * s, o + Vector2(0.62, 0.12) * s, outline, w * 1.4)
			draw_line(o + Vector2(0.5, 0.7) * s, o + Vector2(0.5, 0.92) * s, outline, w * 1.4)
		"person":
			draw_circle(o + Vector2(0.5, 0.32) * s, s * 0.2, outline)
			draw_circle(o + Vector2(0.5, 0.32) * s, s * 0.2 - w, color)
			_poly(PackedVector2Array([Vector2(0.14, 0.92), Vector2(0.2, 0.66), Vector2(0.5, 0.56),
				Vector2(0.8, 0.66), Vector2(0.86, 0.92)]), s, o, w)


func _poly(pts: PackedVector2Array, s: float, o: Vector2, w: float) -> void:
	var p := PackedVector2Array()
	for v in pts:
		p.append(o + v * s)
	draw_colored_polygon(p, color)
	var closed := p.duplicate()
	closed.append(p[0])
	draw_polyline(closed, outline, w, true)
