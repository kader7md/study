class_name TrainStatus
extends Control
## Top-centre train status, drawn in one control:
##   winch line (only while the come-along is in play): hook — train — anchor, red padlocks where it is not attached,
##     chevrons crawling towards the train while it is being pulled up
##   bar 1  body (green, a shield in the middle)
##   bar 2  mechanics, three striped segments: wheels (yellow, one cell per wheel), engine (red), chassis (blue),
##          their icons underneath, and a skull at the end while the train is in a critical state.

const BAR_W := 520.0
const SIDE := 40.0
const WINCH_H := 30.0
const BODY_H := 20.0
const MECH_H := 24.0
const ICON := 18.0
## Mechanics bar split: wheels / engine / chassis.
const SPLIT := [0.4, 0.3, 0.3]

var body := 1.0
var engine := 1.0
var chassis := 1.0
## Per wheel: [state (0 ok, 1 missing, 2 placed but not bolted), tightness 0..1]
var wheels: Array = []
var critical := false
var winch_visible := false
var hooked := false
var anchored := false
var pulling := false
var _t := 0.0
var _body_ghost := 1.0


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	custom_minimum_size = Vector2(BAR_W + SIDE * 2.0, WINCH_H + 6.0 + BODY_H + 8.0 + MECH_H + 6.0 + ICON)


func _process(delta: float) -> void:
	_t += delta
	if _body_ghost > body:
		_body_ghost = maxf(body, _body_ghost - delta * (0.06 + (_body_ghost - body)))
	else:
		_body_ghost = body
	if not HudStyle.headless:
		queue_redraw()


func _draw() -> void:
	var x0 := SIDE
	var y := 0.0
	if winch_visible:
		_draw_winch(Rect2(x0 + BAR_W * 0.25, 0, BAR_W * 0.5, WINCH_H))
	y += WINCH_H + 6.0
	# body
	var br := Rect2(x0, y, BAR_W, BODY_H)
	HudStyle.draw_bar(self, br, body, HudStyle.BODY, _body_ghost, 0.0, _warn_line(body))
	HudStyle.draw_icon(self, "shield", Rect2(br.get_center() - Vector2(9, 9), Vector2(18, 18)), HudStyle.WHITE)
	y += BODY_H + 8.0
	# mechanics
	var mr := Rect2(x0, y, BAR_W, MECH_H)
	HudStyle.draw_frame(self, mr, MECH_H * 0.5, 2.0, HudStyle.GLASS, HudStyle.WHITE)
	var inner := mr.grow(-3.5)
	var gap := 4.0
	var seg_x := inner.position.x
	var avail := inner.size.x - gap * 2.0
	var segs: Array[Rect2] = []
	for k in 3:
		var w: float = avail * SPLIT[k]
		segs.append(Rect2(seg_x, inner.position.y, w, inner.size.y))
		seg_x += w + gap
	_draw_wheels(segs[0])
	_draw_segment(segs[1], engine, HudStyle.ENGINE)
	_draw_segment(segs[2], chassis, HudStyle.CHASSIS)
	# icons under the segments, in the segment's colour
	var iy := y + MECH_H + 5.0
	var kinds := ["wheel", "engine", "chassis"]
	var cols := [HudStyle.WHEELS, HudStyle.ENGINE, HudStyle.CHASSIS]
	for k in 3:
		var c := segs[k].get_center().x
		HudStyle.draw_icon(self, kinds[k], Rect2(c - ICON * 0.5, iy, ICON, ICON), cols[k])
	# skull at the end while critical
	if critical:
		var pulse := 1.0 + 0.12 * sin(_t * 6.0)
		var s := 26.0 * pulse
		HudStyle.draw_icon(self, "skull", Rect2(mr.end.x + 10.0, mr.get_center().y - s * 0.5, s, s), HudStyle.WHITE)


func _warn_line(v: float) -> Color:
	if v > 0.25:
		return HudStyle.WHITE
	return HudStyle.WHITE.lerp(HudStyle.DANGER, 0.5 + 0.5 * sin(_t * 7.0))


func _draw_segment(r: Rect2, v: float, col: Color) -> void:
	var rad := r.size.y * 0.5
	var f := r
	f.size.x = r.size.x * clampf(v, 0.0, 1.0)
	if f.size.x >= 2.0:
		f.size.x = maxf(f.size.x, r.size.y * 0.6)
		HudStyle.draw_striped(self, f, minf(rad, f.size.x * 0.5), col)


## One cell per wheel: full = tight, shrinking as it wears loose, an empty cell with an x when lost,
## a blinking outline when it is placed but not bolted yet.
func _draw_wheels(r: Rect2) -> void:
	var n := maxi(wheels.size(), 1)
	var gap := 2.0
	var cw := (r.size.x - gap * (n - 1)) / n
	for i in n:
		var c := Rect2(r.position.x + i * (cw + gap), r.position.y, cw, r.size.y)
		var st: int = 0
		var amt := 1.0
		if i < wheels.size():
			st = int(wheels[i][0])
			amt = float(wheels[i][1])
		var rad := minf(5.0, c.size.y * 0.5)
		if i == 0:
			rad = c.size.y * 0.5
		match st:
			1:
				var m := c.get_center()
				var d := minf(c.size.x, c.size.y) * 0.22
				draw_line(m - Vector2(d, d), m + Vector2(d, d), HudStyle.DIM, 2.0, true)
				draw_line(m + Vector2(-d, d), m + Vector2(d, -d), HudStyle.DIM, 2.0, true)
			2:
				var a := 0.35 + 0.35 * sin(_t * 8.0)
				HudStyle.draw_striped(self, c, rad, Color(HudStyle.WHEELS, a))
			_:
				var col := HudStyle.WHEELS if amt > 0.35 else HudStyle.WHEELS.lerp(HudStyle.DANGER, 0.55)
				var f := c
				f.size.y = c.size.y * clampf(amt, 0.15, 1.0)
				f.position.y = c.end.y - f.size.y
				HudStyle.draw_striped(self, f, minf(rad, f.size.y * 0.5), col)


func _draw_winch(r: Rect2) -> void:
	var cy := r.get_center().y
	var isz := 22.0
	var left := Vector2(r.position.x + isz * 0.5, cy)
	var right := Vector2(r.end.x - isz * 0.5, cy)
	var mid := Vector2(r.get_center().x, cy)
	# the two cable segments: hook -> train and train -> anchor
	for k in 2:
		var a := left if k == 0 else mid
		var b := mid if k == 0 else right
		var on := hooked if k == 0 else anchored
		var from := a + Vector2(isz * 0.7, 0)
		var to := b - Vector2(isz * 0.9 if k == 0 else isz * 0.7, 0)
		if k == 1:
			from = a + Vector2(isz * 0.9, 0)
		if on:
			draw_line(from + Vector2(0, 1.5), to + Vector2(0, 1.5), HudStyle.SHADOW, 4.0, true)
			draw_line(from, to, HudStyle.WHITE, 3.0, true)
		else:
			var x := from.x
			while x < to.x:
				draw_line(Vector2(x, cy), Vector2(minf(x + 6.0, to.x), cy), HudStyle.DIM, 2.0, true)
				x += 11.0
			var lk := 18.0
			HudStyle.draw_icon(self, "lock", Rect2((from + to) * 0.5 - Vector2(lk, lk) * 0.5 - Vector2(0, 1), Vector2(lk, lk)), HudStyle.DANGER)
		if on and pulling:
			# chevrons crawl towards the train
			var dir := 1.0 if k == 1 else -1.0
			for c in 3:
				var f := fposmod(_t * 0.9 + c / 3.0, 1.0)
				var px := lerpf(to.x if k == 1 else from.x, from.x if k == 1 else to.x, f)
				var cs := 12.0
				var alpha := sin(f * PI)
				var rect := Rect2(Vector2(px - cs * 0.5, cy - cs - 6.0), Vector2(cs, cs))
				if dir > 0.0:
					# pointing left (towards the train in the middle): mirror by drawing a "<"
					_draw_chev(rect, true, Color(HudStyle.GOOD, alpha))
				else:
					_draw_chev(rect, false, Color(HudStyle.GOOD, alpha))
	HudStyle.draw_icon(self, "hook", Rect2(left - Vector2(isz, isz) * 0.5, Vector2(isz, isz)), HudStyle.WHITE)
	HudStyle.draw_icon(self, "train", Rect2(mid - Vector2(isz * 0.75, isz * 0.6), Vector2(isz * 1.5, isz * 1.2)), HudStyle.WHITE)
	HudStyle.draw_icon(self, "hook", Rect2(right - Vector2(isz, isz) * 0.5, Vector2(isz, isz)), HudStyle.WHITE)


func _draw_chev(r: Rect2, point_left: bool, col: Color) -> void:
	var a := Vector2(r.end.x, r.position.y) if point_left else r.position
	var tip := Vector2(r.position.x, r.get_center().y) if point_left else Vector2(r.end.x, r.get_center().y)
	var b := r.end if point_left else Vector2(r.position.x, r.end.y)
	draw_polyline(PackedVector2Array([a, tip, b]), col, 3.0, true)
