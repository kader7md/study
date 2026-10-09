class_name MountainLayout
extends RefCounted
## The shape of "The Mountain" (quest map, GDD 7), in the map's local space (metres, +Y up, the map centre at 0,0):
## a big island peak about 305 m tall. Polar layout: angle th = atan2(x, z), so th = 0 is the SOUTH face (+Z),
## where the beach camp is and the direct climbing line runs straight up.
##
##   shore    r 380-412  y 0-3     beach camp (start), palms
##   forest   r 280-380  y 3-44    a walkable slope with pines and oaks
##   rock     ring 0-5   y 44-122  cliff bands (risers ~13 m) with ledges, a chimney, ramps on the side
##   jungle   ring 6-11  y 122-186 a gorge with a stone pillar and two rope bridges, an overhang, jungle trees
##   snow     ring 12-18 y 198-270 colder: max stamina sinks unless you warm up at a campfire
##   summit   ring 19-20 y 282-305 the last wall, the cairn and the KEY
##
## Terraces ("rings") step up towards the centre. Between two rings is a steep RISER (a climbable cliff). Most risers
## also have a RAMP somewhere on the ring below (a path cut up the side, a long walk around the mountain); some have
## none and must be climbed (rope anchors at the top, so the first climber can drop a rope ladder for the others).
## Everything here is deterministic (fixed seeds), so every peer builds the same mountain.

const CELL := 2.0
const HALF := 430.0                 # the heightmap covers -HALF..HALF on x and z
const SEA_R := 412.0
const BEACH_R := 380.0
const FOREST_R := 280.0
const RISER_W := 2.5                # horizontal width of a riser (steep blend between two rings)
const RAMP_ARC_PER_M := 2.1         # a ramp is this many metres long per metre of rise (~25 degrees)
const ANGLE_BINS := 2048
const WOBBLE := 6.0                 # how far the whole mountain outline wanders (m)
const RING_WOBBLE := 2.0            # how far each riser wanders on its own (m)
const NO_RAMP := 99.0
const RAMP_RISE_PART := 0.75        # the ramp rises over this part of its window, then a landing

## Rings, outside in: [inner radius, height at the outer edge, rise per metre inwards, ramp centre angle or NO_RAMP].
## The outer edge of ring 0 is FOREST_R. The last ring is the summit dome (inner radius 0).
const RINGS := [
	[268.0, 44.0, 0.0, 0.30],     # 0  camp 1 (rock band starts)
	[256.0, 57.0, 0.04, 0.62],    # 1
	[244.0, 70.0, 0.04, NO_RAMP], # 2  chimney on the direct line
	[232.0, 83.0, 0.04, 0.85],    # 3
	[221.0, 96.0, 0.04, 1.12],    # 4
	[214.0, 109.0, 0.04, NO_RAMP],# 5
	[180.0, 122.0, 0.0, 1.40],    # 6  camp 2 + the gorge (jungle starts)
	[170.0, 134.0, 0.04, 1.68],   # 7
	[160.0, 147.0, 0.04, NO_RAMP],# 8  overhang on the direct line
	[150.0, 160.0, 0.04, 1.98],   # 9
	[140.0, 173.0, 0.04, NO_RAMP],# 10
	[124.0, 186.0, 0.0, 2.30],    # 11 camp 3
	[114.0, 198.0, 0.06, 2.62],   # 12 snow starts
	[104.0, 210.0, 0.06, NO_RAMP],# 13
	[94.0, 222.0, 0.06, 2.95],    # 14
	[84.0, 234.0, 0.06, 3.30],    # 15
	[70.0, 246.0, 0.0, NO_RAMP],  # 16 camp 4
	[60.0, 258.0, 0.06, 3.75],    # 17
	[50.0, 270.0, 0.06, NO_RAMP], # 18
	[36.0, 282.0, 0.06, NO_RAMP], # 19 the summit wall
	[0.0, 294.0, 0.3, NO_RAMP],   # 20 summit dome
]
## Camps (campfire checkpoints): ring index, angle and how far in from the ring's outer edge. Camp 0 = the beach.
const CAMP_RINGS := [-1, 0, 6, 11, 16]
const CAMP_INSET := [0.0, 6.0, 4.0, 6.0, 6.0]
## The gorge on ring 6: radial band and half-angle (th centred on 0). Its floor rises on the +th side (a way out).
const GORGE_IN := 189.0
const GORGE_OUT := 205.0
const GORGE_HALF := 0.6
const GORGE_FLOOR := 100.0
const PILLAR_RP := 197.0
## Rope anchors: [riser index, angle]. Risers without a ramp get one on the direct line (th 0) and one where the
## walking route reaches them.
const ANCHORS := [[2, 0.0], [2, 0.72], [5, 0.0], [5, 1.22], [8, 0.07], [8, 1.8], [10, 0.0], [10, 2.12],
	[13, 0.0], [13, 2.78], [16, 0.0], [16, 3.52], [18, 0.0], [18, 4.0], [19, 0.0], [19, 4.06]]
const CHIMNEY := [2, -0.05]           # riser, angle
const OVERHANG := [8, 0.0]
## Biome heights.
const SNOW_Y := 192.0
const JUNGLE_Y := 122.0
const ROCK_Y := 44.0

static var _wob := PackedFloat32Array()
static var _ring_wob: Array[PackedFloat32Array] = []
static var _bumps: FastNoiseLite
static var _bnd := PackedFloat32Array()     # ring boundaries per angle bin: _bnd[bin * RINGS.size() + k]


static func _ensure() -> void:
	if not _wob.is_empty():
		return
	var n := FastNoiseLite.new()
	n.seed = 4471
	n.frequency = 1.0
	n.fractal_octaves = 3
	_wob.resize(ANGLE_BINS + 1)
	for i in ANGLE_BINS + 1:
		var a := TAU * i / ANGLE_BINS
		_wob[i] = n.get_noise_2d(cos(a) * 1.6, sin(a) * 1.6) * WOBBLE * 1.6
	for k in RINGS.size():
		var arr := PackedFloat32Array()
		arr.resize(ANGLE_BINS + 1)
		n.seed = 900 + k * 17
		for i in ANGLE_BINS + 1:
			var a := TAU * i / ANGLE_BINS
			arr[i] = n.get_noise_2d(cos(a) * 3.0, sin(a) * 3.0) * RING_WOBBLE * 1.6
		_ring_wob.append(arr)
	var nr := RINGS.size()
	_bnd.resize((ANGLE_BINS + 1) * nr)
	for i in ANGLE_BINS + 1:
		for k in nr:
			var r: float = RINGS[k][0]
			_bnd[i * nr + k] = 0.0 if r <= 0.0 else r + _ring_wob[k][i]
	_bumps = FastNoiseLite.new()
	_bumps.seed = 77
	_bumps.frequency = 0.06
	_bumps.fractal_octaves = 2


static func _lookup(arr: PackedFloat32Array, th: float) -> float:
	var f := fposmod(th, TAU) / TAU * ANGLE_BINS
	var i := int(f)
	return lerpf(arr[i], arr[mini(i + 1, ANGLE_BINS)], f - i)


## The whole outline's wobble at angle th (added to the radius before the rings are looked up).
static func wob(th: float) -> float:
	_ensure()
	return _lookup(_wob, th)


## Inner boundary of ring k at angle th, in "rp" (radius + wob) units.
static func boundary(k: int, th: float) -> float:
	_ensure()
	if k < 0:
		return FOREST_R
	return _bnd[_bin(th) * RINGS.size() + k]


static func _bin(th: float) -> int:
	return int(fposmod(th, TAU) / TAU * ANGLE_BINS + 0.5)


static func ring_outer(k: int, th: float) -> float:
	return boundary(k - 1, th)


## Half-width (rad) of ring k's ramp.
static func ramp_half(k: int) -> float:
	var rise := riser_rise(k)
	var mid := (float(RINGS[k][0]) + (FOREST_R if k == 0 else float(RINGS[k - 1][0]))) * 0.5
	return rise * RAMP_ARC_PER_M * 0.5 / mid / RAMP_RISE_PART


## Nominal rise of riser k (from ring k's inner edge up to ring k+1).
static func riser_rise(k: int) -> float:
	if k >= RINGS.size() - 1:
		return 0.0
	var outer := FOREST_R if k == 0 else float(RINGS[k - 1][0])
	var top_k: float = float(RINGS[k][1]) + (outer - float(RINGS[k][0])) * float(RINGS[k][2])
	return float(RINGS[k + 1][1]) - top_k


static func has_ramp(k: int) -> bool:
	return float(RINGS[k][3]) < NO_RAMP


## 0..1 along ring k's ramp at angle th (0 outside the ramp window).
static func ramp_s(k: int, th: float) -> float:
	if not has_ramp(k):
		return 0.0
	var w := ramp_half(k)
	var d := wrapf(th - float(RINGS[k][3]), -PI, PI)
	if absf(d) > w:
		return 0.0
	# the last part of the window is a level landing at the top
	return minf((d + w) / (2.0 * w * RAMP_RISE_PART), 1.0)


## Ring k's walking surface at (rp, th), without the riser blend.
static func surface(k: int, rp: float, th: float) -> float:
	var outer := ring_outer(k, th)
	var h: float = float(RINGS[k][1]) + maxf(outer - rp, 0.0) * float(RINGS[k][2])
	if k == RINGS.size() - 1:
		return minf(h, float(RINGS[k][1]) + 9.0)
	var s := ramp_s(k, th)
	if s > 0.0:
		var top := surface(k + 1, boundary(k, th), th)
		var base: float = float(RINGS[k][1]) + (outer - boundary(k, th)) * float(RINGS[k][2])
		h += (top - base) * s
	return h


## Which ring rp falls in at angle th (-1 = outside the rock rings).
static func ring_at(rp: float, th: float) -> int:
	if rp >= FOREST_R:
		return -1
	_ensure()
	var nr := RINGS.size()
	var base := _bin(th) * nr
	for k in nr:
		if rp >= _bnd[base + k]:
			return k
	return nr - 1


## Ground height at local (x, z).
static func height(x: float, z: float) -> float:
	_ensure()
	var r := sqrt(x * x + z * z)
	var th := atan2(x, z)
	var rp := r + _lookup(_wob, th)
	var h := _profile(rp, th)
	# the gorge on ring 6
	if rp > GORGE_IN - 0.5 and rp < GORGE_OUT + 0.5:
		var d := wrapf(th, -PI, PI)
		if d > -GORGE_HALF and d < GORGE_HALF:
			var radial := minf(smoothstep(GORGE_IN, GORGE_IN + 2.5, rp), 1.0 - smoothstep(GORGE_OUT - 2.5, GORGE_OUT, rp))
			var ang := smoothstep(-GORGE_HALF, -GORGE_HALF + 0.015, d)
			var floor_h := lerpf(GORGE_FLOOR, float(RINGS[6][1]), clampf((d - 0.1) / (GORGE_HALF - 0.1), 0.0, 1.0))
			h = lerpf(h, minf(h, floor_h), radial * ang)
	return h + _bumps.get_noise_2d(x, z) * _bump_amount(rp, th)


## Small bumps everywhere except on risers and ramps (so ledges stay level and edges stay sharp).
static func _bump_amount(rp: float, th: float) -> float:
	if rp >= BEACH_R:
		return 0.25
	if rp >= FOREST_R:
		return 1.2 * minf(smoothstep(FOREST_R, FOREST_R + 12.0, rp), 1.0 - smoothstep(BEACH_R - 15.0, BEACH_R, rp))
	var k := ring_at(rp, th)
	var to_riser := rp - boundary(k, th) - RISER_W
	var to_outer := ring_outer(k, th) - rp
	if ramp_s(k, th) > 0.0:
		return 0.0
	return 0.35 * clampf(minf(to_riser, to_outer) / 2.0, 0.0, 1.0)


static func _profile(rp: float, th: float) -> float:
	if rp >= SEA_R:
		return lerpf(0.4, -9.0, clampf((rp - SEA_R) / 30.0, 0.0, 1.0))
	if rp >= BEACH_R:
		var t := (rp - BEACH_R) / (SEA_R - BEACH_R)
		return lerpf(3.2, 0.4, t)
	if rp >= FOREST_R:
		var t := (BEACH_R - rp) / (BEACH_R - FOREST_R)
		var top: float = RINGS[0][1]
		return lerpf(3.2, top, t * t * (3.0 - 2.0 * t))
	var k := ring_at(rp, th)
	var h := surface(k, rp, th)
	if k < RINGS.size() - 1:
		var b := boundary(k, th)
		if rp < b + RISER_W:
			var top := surface(k + 1, b, th)
			var t := 1.0 - (rp - b) / RISER_W
			h = lerpf(h, top, t * t * (3.0 - 2.0 * t))
	return h


# --- Points of interest (local space) --------------------------------------------------------

## Local position at ring-space radius rp and angle th, on the ground.
static func at(rp: float, th: float, lift := 0.0) -> Vector3:
	var r := rp - wob(th)
	var p := Vector3(sin(th) * r, 0.0, cos(th) * r)
	p.y = height(p.x, p.z) + lift
	return p


## Outward horizontal direction at angle th.
static func outward(th: float) -> Vector3:
	return Vector3(sin(th), 0.0, cos(th))


## Camp i (0 = beach): where the campfire is.
static func camp_position(i: int) -> Vector3:
	if i == 0:
		return at(BEACH_R + 12.0, 0.0)
	var k: int = CAMP_RINGS[i]
	return at(ring_outer(k, 0.0) - float(CAMP_INSET[i]), 0.0)


static func camp_count() -> int:
	return CAMP_RINGS.size()


## Top edge of riser k at angle th (a step in from the edge, on the ring above) and its foot.
static func riser_top(k: int, th: float, inset := 0.6) -> Vector3:
	return at(boundary(k, th) - inset, th)


static func riser_foot(k: int, th: float, out := 0.6) -> Vector3:
	return at(boundary(k, th) + RISER_W + out, th)


static func summit() -> Vector3:
	return Vector3(0.0, height(0.0, 0.0), 0.0)


## Biome name at a local height.
static func biome(y: float) -> String:
	if y < 4.0:
		return "shore"
	if y < ROCK_Y - 1.0:
		return "forest"
	if y < JUNGLE_Y - 1.0:
		return "rock"
	if y < SNOW_Y:
		return "jungle"
	if y < 280.0:
		return "snow"
	return "summit"


## The two routes from the beach camp to the summit, as legs {from, to, kind} where kind is "walk", "climb", "bridge".
## direct = straight up the south face (climbs every riser, crosses the gorge on the bridges);
## long = the ramps around the mountain, climbing only the risers that have no ramp.
static func route(kind: String) -> Array[Dictionary]:
	var legs: Array[Dictionary] = []
	var cur := camp_position(0)
	var th := 0.0
	# up through the forest to camp 1
	var c1 := camp_position(1)
	legs.append({"from": cur, "to": c1, "kind": "walk"})
	cur = c1
	for k in RINGS.size() - 1:
		if kind == "direct":
			th = 0.0
			if k == 6:
				# the gorge: rim -> pillar -> inner ledge on the rope bridges
				var rim := at(GORGE_OUT + 1.5, 0.0)
				legs.append({"from": cur, "to": rim, "kind": "walk"})
				var inner := at(GORGE_IN - 1.5, 0.0)
				legs.append({"from": rim, "to": inner, "kind": "bridge"})
				cur = inner
			var sth := 0.0
			if k == int(OVERHANG[0]):
				sth = 0.07  # traverse past the overhang
			var foot := riser_foot(k, sth, 1.2)
			if cur.distance_to(foot) > 0.5:
				legs.append({"from": cur, "to": foot, "kind": "walk"})
			var top := riser_top(k, sth, 2.0)
			legs.append({"from": foot, "to": top, "kind": "climb", "riser": k})
			cur = top
			continue
		# long route
		if has_ramp(k):
			var w := ramp_half(k)
			var a0 := float(RINGS[k][3]) - w
			var a1 := float(RINGS[k][3]) + w
			var mid_r := (ring_outer(k, a0) + boundary(k, a0)) * 0.5 + 1.0
			# walk along the ring to the foot of the ramp (in steps, so the check follows the curve)
			var steps := maxi(int(absf(wrapf(a0 - th, -PI, PI)) * mid_r / 8.0), 1)
			var from_th := th
			for s in range(1, steps + 1):
				var a := from_th + wrapf(a0 - from_th, -PI, PI) * s / steps
				var p := at(mid_r, a, 0.0)
				legs.append({"from": cur, "to": p, "kind": "walk"})
				cur = p
			var land := a1 - (a1 - a0) * (1.0 - RAMP_RISE_PART) * 0.5   # the middle of the landing
			for s in range(1, 9):
				var a := a0 + (land - a0) * (s / 8.0)
				var p := at(mid_r, a)
				legs.append({"from": cur, "to": p, "kind": "walk"})
				cur = p
			th = land
			var onto := at(boundary(k, th) - 3.0, th)
			legs.append({"from": cur, "to": onto, "kind": "walk"})
			cur = onto
		else:
			var anchor_th := th
			for a: Array in ANCHORS:
				if int(a[0]) == k and float(a[1]) != 0.0:
					anchor_th = float(a[1])
			var mid_r := (ring_outer(k, th) + boundary(k, th)) * 0.5
			if ring_outer(k, th) - boundary(k, th) > 9.0:
				mid_r = boundary(k, th) + RISER_W + 3.0
			var steps := maxi(int(absf(wrapf(anchor_th - th, -PI, PI)) * mid_r / 8.0), 1)
			var from_th := th
			for s in range(1, steps + 1):
				var a := from_th + wrapf(anchor_th - from_th, -PI, PI) * s / steps
				var p := at(mid_r, a)
				legs.append({"from": cur, "to": p, "kind": "walk"})
				cur = p
			th = anchor_th
			var foot := riser_foot(k, th, 1.2)
			legs.append({"from": cur, "to": foot, "kind": "walk"})
			var top := riser_top(k, th, 2.0)
			legs.append({"from": foot, "to": top, "kind": "climb", "riser": k})
			cur = top
	legs.append({"from": cur, "to": summit(), "kind": "walk"})
	return legs
