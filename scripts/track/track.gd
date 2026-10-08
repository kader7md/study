class_name Track
extends Path3D
## The railway: one long curve with 6 stations (departure + 5 checkpoints).
## The rails are split into pieces of PIECE_LENGTH metres. Any piece can be broken
## (pre-placed gaps, meteors) and must be repaired before the train can pass.

signal piece_broken(index: int)
signal piece_repaired(index: int)

const PIECE_LENGTH := 4.0
## Prototype distance between stations. The real game will be much longer (Chapter 1 ≈ 10 h).
const SEGMENT_LENGTH := 420.0
const LEAD_IN := 60.0
const TAIL := 120.0
const STATION_LENGTH := 60.0
const POINT_STEP := 30.0
const GAUGE := 1.5
const REPAIR_COST := {"wood": 2, "nails": 2}

var station_distances: Array[float] = []
var piece_count := 0
var _broken := {}  # piece index -> repair spot (ActionSpot)
var _rails: MultiMesh
var _sleepers: MultiMesh


func build(rng: RandomNumberGenerator) -> void:
	_build_curve(rng)
	_build_visuals()


# --- Geometry ---------------------------------------------------------------

func _build_curve(rng: RandomNumberGenerator) -> void:
	var marks: Array[float] = []
	for i in Game.STATION_COUNT + 1:
		marks.append(LEAD_IN + i * SEGMENT_LENGTH)
	var total := marks[-1] + TAIL

	var points: Array[Vector3] = []
	var pos := Vector3.ZERO
	var heading := 0.0
	var d := 0.0
	while d <= total + 0.01:
		points.append(pos)
		var near_station := false
		for m in marks:
			if absf(d - m) < STATION_LENGTH:
				near_station = true
		if not near_station:
			heading = clampf(heading + rng.randf_range(-0.25, 0.25), -1.1, 1.1)
		pos += Vector3(sin(heading), 0.0, -cos(heading)) * POINT_STEP
		d += POINT_STEP

	var c := Curve3D.new()
	c.bake_interval = 0.5
	for i in points.size():
		var tangent := (points[mini(i + 1, points.size() - 1)] - points[maxi(i - 1, 0)]) / 6.0
		c.add_point(points[i], -tangent, tangent)
	curve = c

	station_distances.clear()
	for m in marks:
		station_distances.append(c.get_closest_offset(points[int(round(m / POINT_STEP))]))
	piece_count = int(c.get_baked_length() / PIECE_LENGTH)


func get_length() -> float:
	return curve.get_baked_length()


func point_at(d: float) -> Vector3:
	return global_transform * curve.sample_baked(clampf(d, 0.0, get_length()), true)


## Transform on the track: origin on the rails, -Z points forward along the track, +X to the right.
func transform_at(d: float) -> Transform3D:
	var length := get_length()
	d = clampf(d, 0.0, length)
	var ahead := point_at(minf(d + 0.5, length))
	var behind := point_at(maxf(d - 0.5, 0.0))
	return Transform3D(Basis.looking_at(ahead - behind, Vector3.UP), point_at(d))


## Transform for a train car whose front bogie is at front_d and back bogie at back_d.
func car_transform(front_d: float, back_d: float) -> Transform3D:
	var front := point_at(front_d)
	var back := point_at(back_d)
	var dir := front - back
	if dir.length_squared() < 0.0001:
		return transform_at(front_d)
	return Transform3D(Basis.looking_at(dir, Vector3.UP), (front + back) * 0.5)


## Distance along the track closest to a world position.
func closest_distance(world_pos: Vector3) -> float:
	return curve.get_closest_offset(global_transform.affine_inverse() * world_pos)


## Station index whose platform contains distance d, or -1.
func station_at(d: float) -> int:
	for i in station_distances.size():
		if absf(d - station_distances[i]) <= STATION_LENGTH * 0.5:
			return i
	return -1


# --- Rail pieces ------------------------------------------------------------

func piece_at(d: float) -> int:
	return clampi(int(floor(d / PIECE_LENGTH)), 0, piece_count - 1)


func piece_center(index: int) -> float:
	return (index + 0.5) * PIECE_LENGTH


func is_broken(index: int) -> bool:
	return _broken.has(index)


func broken_count() -> int:
	return _broken.size()


## Station platforms and the very start/end can't break, so the train can always stop at a station.
func is_protected(index: int) -> bool:
	var d := piece_center(index)
	return station_at(d) != -1 or d < LEAD_IN * 0.5 or d > get_length() - 10.0


## Moving from d_from to d_to: returns the edge of the first broken piece in the way, or -1.0 if clear.
## Forward: the start of the broken piece. Backward: its end.
func blocking_distance(d_from: float, d_to: float) -> float:
	if _broken.is_empty():
		return -1.0
	if d_to >= d_from:
		for i in range(piece_at(d_from), piece_at(d_to) + 1):
			if _broken.has(i):
				return maxf(i * PIECE_LENGTH, d_from)
	else:
		for i in range(piece_at(d_from), piece_at(d_to) - 1, -1):
			if _broken.has(i):
				return minf((i + 1) * PIECE_LENGTH, d_from)
	return -1.0


func break_piece(index: int) -> bool:
	if index < 0 or index >= piece_count or _broken.has(index) or is_protected(index):
		return false
	_set_piece_visible(index, false)
	var t := transform_at(piece_center(index))
	var prompt := func(_p): return "Broken rail: repair (%s)  [hold E]" % Game.cost_text(REPAIR_COST)
	var action := func(_p):
		if Game.pay(REPAIR_COST):
			repair_piece(index)
			Game.say("Rail repaired")
		else:
			Game.say("Need %s to repair the rail" % Game.cost_text(REPAIR_COST))
	var spot := ActionSpot.create(self, Vector3(3.0, 1.5, PIECE_LENGTH), Vector3.ZERO, prompt, action)
	spot.hold_fn = func(_p): return 1.0 if Game.has("nail_gun") else 2.0
	spot.global_transform = t
	Build.box(spot, Vector3(2.6, 0.08, PIECE_LENGTH - 0.3), Vector3(0, 0.02, 0), Color(1.0, 0.45, 0.1, 0.55))
	Build.label(spot, "BROKEN RAIL", Vector3(0, 1.6, 0), 48)
	_broken[index] = spot
	piece_broken.emit(index)
	return true


func repair_piece(index: int) -> void:
	if not _broken.has(index):
		return
	_broken[index].queue_free()
	_broken.erase(index)
	_set_piece_visible(index, true)
	piece_repaired.emit(index)


## Breaks every piece within `radius` of a world position, except pieces in [skip_from, skip_to]
## (used so a meteor that hits the train doesn't break the rails under it).
func break_around(world_pos: Vector3, radius: float, skip_from := -1.0, skip_to := -1.0) -> int:
	var center := closest_distance(world_pos)
	if point_at(center).distance_to(world_pos) > radius:
		return 0
	var broken := 0
	for i in range(piece_at(center - radius), piece_at(center + radius) + 1):
		var d := piece_center(i)
		if d >= skip_from and d <= skip_to:
			continue
		if point_at(d).distance_to(world_pos) <= radius and break_piece(i):
			broken += 1
	return broken


## Pre-placed gaps between stations: the crew has to stop and repair.
func place_initial_gaps(rng: RandomNumberGenerator, gaps_per_segment := 2) -> void:
	for s in station_distances.size() - 1:
		var from := station_distances[s] + STATION_LENGTH
		var to := station_distances[s + 1] - STATION_LENGTH
		for g in gaps_per_segment:
			var start := piece_at(rng.randf_range(from, to))
			for k in rng.randi_range(1, 3):
				break_piece(start + k)


# --- Visuals ------------------------------------------------------------------

func _build_visuals() -> void:
	var rail_mesh := BoxMesh.new()
	rail_mesh.size = Vector3(0.12, 0.15, PIECE_LENGTH)
	rail_mesh.material = Build.material(Color(0.42, 0.4, 0.4))
	_rails = _make_multimesh(rail_mesh, piece_count * 2)

	var sleeper_mesh := BoxMesh.new()
	sleeper_mesh.size = Vector3(2.4, 0.12, 0.3)
	sleeper_mesh.material = Build.material(Color(0.36, 0.24, 0.14))
	_sleepers = _make_multimesh(sleeper_mesh, piece_count * 2)

	for i in piece_count:
		_set_piece_visible(i, true)


func _make_multimesh(mesh: Mesh, count: int) -> MultiMesh:
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = mesh
	mm.instance_count = count
	var mmi := MultiMeshInstance3D.new()
	mmi.multimesh = mm
	add_child(mmi)
	return mm


func _set_piece_visible(index: int, visible_now: bool) -> void:
	var t := global_transform.affine_inverse() * transform_at(piece_center(index))
	var hide := Basis().scaled(Vector3.ZERO)
	for side in 2:
		var rail := t.translated_local(Vector3((side - 0.5) * GAUGE, 0.2, 0))
		if not visible_now:
			rail.basis = hide
		_rails.set_instance_transform(index * 2 + side, rail)
		var sleeper := t.translated_local(Vector3(0, 0.06, (side - 0.5) * PIECE_LENGTH * 0.5))
		if not visible_now:
			sleeper.basis = hide
		_sleepers.set_instance_transform(index * 2 + side, sleeper)
