class_name Track
extends Path3D
## The railway: one long curve with 6 stations (departure + 5 checkpoints) over a landscape of
## hills, rivers, a mountain pass, a lake and the coast. Each segment between stations has a theme.
## The rails are split into pieces of PIECE_LENGTH metres. Any piece can be broken (pre-placed gaps,
## meteors) and must be rebuilt by hand (see RailRepair) before the train can pass.

signal piece_broken(index: int)
signal piece_repaired(index: int)

const PIECE_LENGTH := 4.0
## Distance between stations. The full game will be longer still (Chapter 1 ≈ 10 h).
const SEGMENT_LENGTH := 1500.0
const LEAD_IN := 80.0
const TAIL := 160.0
const STATION_LENGTH := 60.0
const POINT_STEP := 30.0
## Distance between the two rails (matches the train's wheels at x = ±0.85).
const GAUGE := 1.7
## Rail and sleeper heights relative to the track line (rail TOP is at +0.05, where the wheels touch).
const RAIL_Y := -0.025
const SLEEPER_Y := -0.16
const WATER_LEVEL := -4.0
## A piece is a bridge when the natural ground under it is this far below the rails.
const BRIDGE_DEPTH := 2.5

## Segment themes (segment i runs from station i to station i+1).
## heights: track height keypoints as (fraction of segment, metres). Station heights are in STATION_HEIGHTS.
## rivers: crossings as (fraction, width m). lake: (from, to, side, inner u) where side +1 = right of the track.
## walls: how high the land rises far from the track (valley walls / mountains).
const STATION_HEIGHTS := [0.0, 8.0, 4.0, 46.0, 6.0, 2.0]
const THEMES := [
	{"name": "Forest hills", "heights": [[0.25, 7.0], [0.55, 2.0], [0.78, 11.0]], "rivers": [[0.55, 26.0]], "walls": 18.0},
	{"name": "River valley", "heights": [[0.3, 3.0], [0.5, 2.0], [0.72, 7.0]], "rivers": [[0.5, 70.0]], "walls": 30.0},
	{"name": "Mountain pass", "heights": [[0.25, 15.0], [0.5, 27.0], [0.75, 39.0]], "rivers": [[0.5, 46.0]], "walls": 85.0},
	{"name": "The lake", "heights": [[0.3, 30.0], [0.55, 10.0], [0.76, 3.0]], "rivers": [[0.76, 90.0]],
		"lake": [0.6, 0.97, 1, 22.0], "walls": 25.0},
	{"name": "The coast", "heights": [[0.4, 8.0], [0.7, 4.0]], "rivers": [],
		"lake": [0.55, 1.2, -1, 24.0], "walls": 15.0},
]

var station_distances: Array[float] = []
var piece_count := 0
var _broken := {}  # piece index -> RailRepair
var _bridge := PackedByteArray()  # 1 = piece is a bridge
var _deck_shapes := {}  # bridge piece index -> deck collider (disabled while the piece is broken)
var _roll := {}         # rebuilt piece index -> tilt in degrees (how well the crew built it)
var _rails: MultiMesh
var _sleepers: MultiMesh
var _noise := FastNoiseLite.new()
var _height_keys: Array[Vector2] = []  # (distance, height) keypoints of the track profile


func build(rng: RandomNumberGenerator) -> void:
	_noise.seed = rng.randi()
	_noise.frequency = 0.006
	_noise.fractal_octaves = 3
	_build_curve(rng)
	_build_bridge_flags()
	_build_visuals()


# --- Geometry ---------------------------------------------------------------

func _build_curve(rng: RandomNumberGenerator) -> void:
	var marks: Array[float] = []
	for i in Game.STATION_COUNT + 1:
		marks.append(LEAD_IN + i * SEGMENT_LENGTH)
	var total := marks[-1] + TAIL
	_build_height_keys(marks)

	var points: Array[Vector3] = []
	var pos := Vector3.ZERO
	var heading := 0.0
	var d := 0.0
	while d <= total + 0.01:
		points.append(Vector3(pos.x, _profile(d), pos.z))
		var near_station := false
		for m in marks:
			if absf(d - m) < STATION_LENGTH:
				near_station = true
		if not near_station:
			# Gentle curves (radius ≥ ~350 m) so the landscape around the track stays clean
			heading = clampf(heading + rng.randf_range(-0.08, 0.08), -0.9, 0.9)
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


func _build_height_keys(marks: Array[float]) -> void:
	_height_keys.clear()
	for s in marks.size():
		var h: float = STATION_HEIGHTS[s]
		# flat through the station
		_height_keys.append(Vector2(marks[s] - STATION_LENGTH, h))
		_height_keys.append(Vector2(marks[s] + STATION_LENGTH, h))
		if s < THEMES.size():
			for k: Array in THEMES[s].heights:
				_height_keys.append(Vector2(marks[s] + k[0] * SEGMENT_LENGTH, k[1]))
	_height_keys.sort_custom(func(a: Vector2, b: Vector2): return a.x < b.x)


## Track height at distance d (smooth between keypoints).
func _profile(d: float) -> float:
	if d <= _height_keys[0].x:
		return _height_keys[0].y
	for i in range(1, _height_keys.size()):
		var b := _height_keys[i]
		if d <= b.x:
			var a := _height_keys[i - 1]
			return lerpf(a.y, b.y, smoothstep(a.x, b.x, d))
	return _height_keys[-1].y


func get_length() -> float:
	return curve.get_baked_length()


## Point on the rails. Distances outside the track continue straight (used by the terrain edges).
func point_at(d: float) -> Vector3:
	var length := get_length()
	if d < 0.0:
		return point_at(0.0) + flat_forward(0.0) * d
	if d > length:
		return point_at(length) + flat_forward(length) * (d - length)
	return global_transform * curve.sample_baked(d, true)


## Horizontal forward direction of the track.
func flat_forward(d: float) -> Vector3:
	var length := get_length()
	var a := global_transform * curve.sample_baked(clampf(d + 1.0, 0.0, length), true)
	var b := global_transform * curve.sample_baked(clampf(d - 1.0, 0.0, length), true)
	var f := Vector3(a.x - b.x, 0.0, a.z - b.z)
	return f.normalized() if f.length_squared() > 0.0001 else Vector3.FORWARD


## Horizontal right direction of the track.
func flat_right(d: float) -> Vector3:
	return flat_forward(d).cross(Vector3.UP)


## Uphill grade at d (+0.03 = 3 % uphill going forward).
func grade_at(d: float) -> float:
	return (point_at(d + 2.0).y - point_at(d - 2.0).y) / 4.0


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


## Segment (0..4) that distance d belongs to.
func segment_at(d: float) -> int:
	for i in range(1, station_distances.size()):
		if d < station_distances[i]:
			return i - 1
	return station_distances.size() - 2


func theme_at(d: float) -> Dictionary:
	return THEMES[clampi(segment_at(d), 0, THEMES.size() - 1)]


# --- Landscape --------------------------------------------------------------------

## Natural ground height at track distance d and sideways offset u (metres, + = right),
## before the railway embankment is added. Rivers, lakes and valley walls come from THEMES.
func natural_height(d: float, u: float) -> float:
	var ty := point_at(d).y
	var au := absf(u)
	var theme := theme_at(d)
	var p := point_at(d) + flat_right(d) * u
	var hills := _noise.get_noise_2d(p.x, p.z)
	var h := ty - 0.4 + hills * lerpf(1.0, 10.0, smoothstep(8.0, 120.0, au))
	h += float(theme.walls) * smoothstep(30.0, 170.0, au) * (0.6 + 0.4 * (hills + 1.0))
	var seg := segment_at(d)
	var seg_start := station_distances[seg]
	for r: Array in theme.rivers:
		var rd: float = seg_start + r[0] * SEGMENT_LENGTH
		var k := 1.0 - smoothstep(r[1] * 0.5, r[1] * 0.5 + 30.0, absf(d - rd))
		h = lerpf(h, WATER_LEVEL - 4.0, k)
	if theme.has("lake"):
		var lk: Array = theme.lake
		var a: float = seg_start + lk[0] * SEGMENT_LENGTH
		var b: float = seg_start + lk[1] * SEGMENT_LENGTH
		var kd := smoothstep(a - 40.0, a + 20.0, d) * (1.0 - smoothstep(b - 20.0, b + 40.0, d))
		var ku := smoothstep(lk[3] - 15.0, lk[3] + 15.0, u * float(lk[2]))
		h = lerpf(h, WATER_LEVEL - 5.0, kd * ku)
	return h


## Final ground height: natural ground plus the embankment the rails sit on (none on bridges).
func ground_height(d: float, u: float) -> float:
	var natural := natural_height(d, u)
	if is_bridge_at(d):
		return natural
	var c := 1.0 - smoothstep(4.0, 16.0, absf(u))
	return lerpf(natural, point_at(d).y - 0.35, c)


## Point on the ground at track distance d and sideways offset u.
func ground_point(d: float, u: float) -> Vector3:
	var p := point_at(d) + flat_right(d) * u
	p.y = ground_height(d, u)
	return p


func is_bridge(index: int) -> bool:
	return index >= 0 and index < _bridge.size() and _bridge[index] == 1


func is_bridge_at(d: float) -> bool:
	return is_bridge(piece_at(d))


func bridge_count() -> int:
	return _bridge.count(1)


func _build_bridge_flags() -> void:
	_bridge.resize(piece_count)
	for i in piece_count:
		var d := piece_center(i)
		_bridge[i] = 1 if natural_height(d, 0.0) < point_at(d).y - BRIDGE_DEPTH else 0
	# Bridges start and end on solid ground: extend each one by a piece on both ends
	var copy := _bridge.duplicate()
	for i in piece_count:
		if copy[i] == 1:
			if i > 0: _bridge[i - 1] = 1
			if i < piece_count - 1: _bridge[i + 1] = 1


# --- Rail pieces ------------------------------------------------------------

func piece_at(d: float) -> int:
	return clampi(int(floor(d / PIECE_LENGTH)), 0, piece_count - 1)


func piece_center(index: int) -> float:
	return (index + 0.5) * PIECE_LENGTH


func is_broken(index: int) -> bool:
	return _broken.has(index)


func broken_count() -> int:
	return _broken.size()


func repair_at(index: int) -> RailRepair:
	return _broken.get(index)


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


## Tilt (degrees, signed) of a rebuilt piece; 0 for original track.
func piece_roll(index: int) -> float:
	return _roll.get(index, 0.0)


func break_piece(index: int, cratered := false) -> bool:
	if index < 0 or index >= piece_count or _broken.has(index) or is_protected(index):
		return false
	_roll.erase(index)
	_set_piece_visible(index, false)
	if _deck_shapes.has(index):
		_deck_shapes[index].set_deferred("disabled", true)
	var repair := RailRepair.new()
	repair.setup(self, index, cratered)
	add_child(repair)
	repair.global_transform = transform_at(piece_center(index))
	_broken[index] = repair
	piece_broken.emit(index)
	return true


func repair_piece(index: int, roll := 0.0) -> void:
	if not _broken.has(index):
		return
	_broken[index].queue_free()
	_broken.erase(index)
	if absf(roll) > 0.01:
		_roll[index] = roll
	_set_piece_visible(index, true)
	if _deck_shapes.has(index):
		_deck_shapes[index].set_deferred("disabled", false)
	piece_repaired.emit(index)


## Breaks every piece within `radius` of a world position, except pieces in [skip_from, skip_to]
## (used so a meteor that hits the train doesn't break the rails under it).
func break_around(world_pos: Vector3, radius: float, skip_from := -1.0, skip_to := -1.0) -> int:
	var center := closest_distance(world_pos)
	if point_at(center).distance_to(world_pos) > radius + 2.0:
		return 0
	var broken := 0
	for i in range(piece_at(center - radius), piece_at(center + radius) + 1):
		var d := piece_center(i)
		if d >= skip_from and d <= skip_to:
			continue
		if point_at(d).distance_to(world_pos) <= radius + 1.0 and break_piece(i, true):
			broken += 1
	return broken


## Pre-placed gaps between stations: the crew has to stop and rebuild the track.
func place_initial_gaps(rng: RandomNumberGenerator, gaps_per_segment := 3) -> void:
	for s in station_distances.size() - 1:
		var from := station_distances[s] + STATION_LENGTH
		var to := station_distances[s + 1] - STATION_LENGTH
		for g in gaps_per_segment:
			var start := piece_at(rng.randf_range(from, to))
			var rough := rng.randf() < 0.5
			for k in rng.randi_range(1, 2):
				break_piece(start + k, rough)


# --- Visuals ------------------------------------------------------------------

func _build_visuals() -> void:
	var rail_mesh := BoxMesh.new()
	rail_mesh.size = Vector3(0.12, 0.15, PIECE_LENGTH)
	rail_mesh.material = Build.material(Color(0.5, 0.5, 0.52))
	_rails = _make_multimesh(rail_mesh, piece_count * 2)

	var sleeper_mesh := BoxMesh.new()
	sleeper_mesh.size = Vector3(2.4, 0.12, 0.3)
	sleeper_mesh.material = Build.material(Color(0.42, 0.27, 0.14))
	_sleepers = _make_multimesh(sleeper_mesh, piece_count * 2)

	for i in piece_count:
		_set_piece_visible(i, true)
	_build_bridges()


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
	if _roll.has(index):
		t.basis = t.basis * Basis(Vector3.BACK, deg_to_rad(_roll[index]))
	var hide := Basis().scaled(Vector3.ZERO)
	for side in 2:
		var rail := t.translated_local(Vector3((side - 0.5) * GAUGE, RAIL_Y, 0))
		if not visible_now:
			rail.basis = hide
		_rails.set_instance_transform(index * 2 + side, rail)
		var sleeper := t.translated_local(Vector3(0, SLEEPER_Y, (side - 0.5) * PIECE_LENGTH * 0.5))
		if not visible_now:
			sleeper.basis = hide
		_sleepers.set_instance_transform(index * 2 + side, sleeper)


## Wooden trestles under bridge pieces: a deck beam on each side and posts down to the ground.
func _build_bridges() -> void:
	var beams: Array[Transform3D] = []
	var posts: Array[Transform3D] = []
	for i in piece_count:
		if not is_bridge(i):
			continue
		var d := piece_center(i)
		var t := global_transform.affine_inverse() * transform_at(d)
		for side in [-1.0, 1.0]:
			beams.append(t.translated_local(Vector3(side * 1.25, -0.37, 0)))
		if i % 2 == 0:
			var top := point_at(d).y - 0.52
			var bottom := natural_height(d, 0.0) - 1.0
			var height := maxf(top - bottom, 0.5)
			for side in [-1.0, 1.0]:
				var post := t.translated_local(Vector3(side * 1.1, -0.52 - height * 0.5, 0))
				post.basis = Basis().scaled(Vector3(1, height, 1))
				posts.append(post)
	var beam_mesh := BoxMesh.new()
	beam_mesh.size = Vector3(0.3, 0.3, PIECE_LENGTH)
	beam_mesh.material = Build.material(Color(0.36, 0.22, 0.12))
	var post_mesh := BoxMesh.new()
	post_mesh.size = Vector3(0.35, 1.0, 0.35)
	post_mesh.material = Build.material(Color(0.3, 0.19, 0.1))
	for pair in [[beam_mesh, beams], [post_mesh, posts]]:
		var list: Array[Transform3D] = pair[1]
		var mm := _make_multimesh(pair[0], list.size())
		for k in list.size():
			mm.set_instance_transform(k, list[k])
	# Walkable bridge deck (players can walk along a bridge; broken pieces leave holes)
	var deck := StaticBody3D.new()
	deck.collision_layer = Build.LAYER_WORLD
	add_child(deck)
	for i in piece_count:
		if is_bridge(i):
			var cs := Build.collider(deck, Vector3(2.8, 0.2, PIECE_LENGTH), Vector3.ZERO)
			cs.transform = global_transform.affine_inverse() * transform_at(piece_center(i)).translated_local(Vector3(0, -0.2, 0))
			cs.set_meta("piece", i)
			_deck_shapes[i] = cs
