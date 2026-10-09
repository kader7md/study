class_name Landscape
extends RefCounted
## The shape of the overworld: one deterministic height function for the whole corridor around the railway
## (several hundred metres each side, up to R_OUT). Track uses it for the ground near the rails (embankments,
## bridges, gate and key spots); Terrain samples it into a big heightmap grid for the open land.
##
## height() works in two coordinate systems at once: world x/z (noise) and track coordinates (d = distance along
## the track, u = sideways offset, + = right). Close to the track the land stays near rail height (gentle hills,
## embankments, cuttings); further out each segment's theme takes over: rolling hills, ridged mountains with cliff
## bands, snowy peaks, river gorges that cross the whole corridor, lakes and the sea. Flat plateaus are reserved
## beside every locked gate for the quest sites (quest_zones), and the ground levels out around the stations.
## Everything comes from the track's noise seed, so every peer computes the same land.

## Half-width of the playable corridor. Beyond R_OUT - EDGE_WALL the land climbs into high ridges that close it in.
const R_OUT := 900.0
const EDGE_WALL := 260.0
const PARAM_STEP := 8.0
## Quest sites: a flat SIZE x SIZE square beside each gate, its near edge ZONE_GAP metres from the rails.
const ZONE_SIZE := 80.0
const ZONE_GAP := 14.0
const ZONE_BLEND := 26.0

var track: Track
## Quest sites: [{center: Vector2 (x, z), forward: Vector2, right: Vector2, half: Vector2, height: float,
##   side: float, gate_index: int, d: float}]
var zones: Array[Dictionary] = []

var _hill := FastNoiseLite.new()
var _ridge := FastNoiseLite.new()
var _warp := FastNoiseLite.new()
var _detail := FastNoiseLite.new()
var _shore := FastNoiseLite.new()
# per-distance theme parameters, sampled every PARAM_STEP metres from _p0
var _p0 := 0.0
var _walls := PackedFloat32Array()
var _hills := PackedFloat32Array()
var _mtn := PackedFloat32Array()
var _mstart := PackedFloat32Array()
var _terrace := PackedFloat32Array()
var _snow := PackedFloat32Array()
var _dry := PackedFloat32Array()
var _forest := PackedFloat32Array()
var _rock := PackedFloat32Array()
var _sea := PackedFloat32Array()
var _rivers: Array[Vector4] = []   # (d, half width, meander phase, meander amplitude)
var _lakes: Array[Dictionary] = []  # {a, b, side, inner, outer}
var _stations: Array[float] = []
var _near_river := PackedInt32Array()
var _near_lake := PackedInt32Array()
var _near_station := PackedByteArray()
var _near_zone := PackedByteArray()
var _lk := PackedFloat32Array()


func setup(t: Track, noise_seed: int) -> void:
	track = t
	_hill.seed = noise_seed
	_hill.frequency = 0.006
	_hill.fractal_octaves = 3
	_ridge.seed = noise_seed + 101
	_ridge.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	_ridge.fractal_type = FastNoiseLite.FRACTAL_RIDGED
	_ridge.fractal_octaves = 5
	_ridge.frequency = 0.0016
	_warp.seed = noise_seed + 202
	_warp.frequency = 0.0011
	_warp.fractal_octaves = 2
	_detail.seed = noise_seed + 303
	_detail.frequency = 0.035
	_detail.fractal_octaves = 2
	_shore.seed = noise_seed + 404
	_shore.frequency = 0.006
	_shore.fractal_octaves = 2


## Call once the track curve and the stations exist: samples the theme parameters along the whole line.
func build_params() -> void:
	_stations = track.station_distances.duplicate()
	var length := track.get_length()
	_p0 = -R_OUT - 300.0
	var count := int((length + 2.0 * (R_OUT + 300.0)) / PARAM_STEP) + 2
	for arr: PackedFloat32Array in [_walls, _hills, _mtn, _mstart, _terrace, _snow, _dry, _forest, _rock, _sea]:
		arr.resize(count)
	var keys := ["walls", "hills", "mountains", "mstart", "terrace", "snow", "dry", "forest", "rock"]
	for i in count:
		var d := _p0 + i * PARAM_STEP
		# blend between neighbouring themes over ±BLEND metres around each station
		var seg := clampi(track.segment_at(clampf(d, 0.0, length)), 0, Track.THEMES.size() - 1)
		var a: Dictionary = Track.THEMES[seg]
		var b := a
		var k := 0.0
		const BLEND := 220.0
		if seg + 1 < Track.THEMES.size() and d > _stations[seg + 1] - BLEND:
			b = Track.THEMES[seg + 1]
			k = smoothstep(_stations[seg + 1] - BLEND, _stations[seg + 1] + BLEND, d)
		elif seg > 0 and d < _stations[seg] + BLEND:
			b = Track.THEMES[seg - 1]
			k = 1.0 - smoothstep(_stations[seg] - BLEND, _stations[seg] + BLEND, d)
		var vals: Array[float] = []
		for key: String in keys:
			vals.append(lerpf(float(a[key]), float(b[key]), k))
		_walls[i] = vals[0]
		_hills[i] = vals[1]
		_mtn[i] = vals[2]
		_mstart[i] = vals[3]
		_terrace[i] = vals[4]
		_snow[i] = vals[5]
		_dry[i] = vals[6]
		_forest[i] = vals[7]
		_rock[i] = vals[8]
	# rivers (crossing the whole corridor) and lakes, in absolute track distances
	_rivers.clear()
	_lakes.clear()
	for s in Track.THEMES.size():
		var theme: Dictionary = Track.THEMES[s]
		var start := _stations[s]
		for r: Array in theme.rivers:
			_rivers.append(Vector4(start + float(r[0]) * Track.SEGMENT_LENGTH, float(r[1]) * 0.5, float(s) * 1.7, 70.0))
		if theme.has("lake"):
			var lk: Array = theme.lake
			_lakes.append({"a": start + float(lk[0]) * Track.SEGMENT_LENGTH, "b": start + float(lk[1]) * Track.SEGMENT_LENGTH,
				"side": float(lk[2]), "inner": float(lk[3]), "outer": float(lk[4]) if lk.size() > 4 else 99999.0})
	for i in count:
		var d := _p0 + i * PARAM_STEP
		var sea := 0.0
		for lk in _lakes:
			if float(lk.outer) > 9000.0:
				var w := smoothstep(float(lk.a) - 300.0, float(lk.a), d) * (1.0 - smoothstep(float(lk.b), float(lk.b) + 300.0, d))
				if w > absf(sea):
					sea = w * float(lk.side)
		_sea[i] = sea
	# which river / lake / station can reach each stretch (most of the land has none: skip their loops)
	_near_river.resize(count)
	_near_lake.resize(count)
	_near_station.resize(count)
	_lk = PackedFloat32Array()
	for lk in _lakes:
		_lk.append_array([float(lk.a), float(lk.b), float(lk.side), float(lk.inner), float(lk.outer)])
	for i in count:
		var d := _p0 + i * PARAM_STEP
		_near_river[i] = -1
		for r in _rivers.size():
			var rv := _rivers[r]
			if absf(d - rv.x) < rv.w + rv.y * 1.3 + 30.0 + 0.55 * 700.0 + PARAM_STEP:
				_near_river[i] = r
		_near_lake[i] = -1
		for l in _lakes.size():
			if d > _lk[l * 5] - 70.0 and d < _lk[l * 5 + 1] + 70.0:
				_near_lake[i] = l
		_near_station[i] = 0
		for sd in _stations:
			if absf(d - sd) < Track.STATION_LENGTH + 70.0 + PARAM_STEP:
				_near_station[i] = 1
	zones_changed()


## Call after changing `zones`.
func zones_changed() -> void:
	_near_zone.resize(_walls.size())
	_near_zone.fill(0)
	for zn in zones:
		var dz: float = zn.d
		for i in _walls.size():
			if absf(_p0 + i * PARAM_STEP - dz) < ZONE_SIZE + ZONE_BLEND + 60.0:
				_near_zone[i] = 1


func _pi(d: float) -> int:
	return clampi(int((d - _p0) / PARAM_STEP + 0.5), 0, _walls.size() - 1)


## Theme values at distance d (for colouring and scattering).
func forest_at(d: float) -> float:
	return _forest[_pi(d)]


func snow_line_at(d: float) -> float:
	return _snow[_pi(d)]


func dryness_at(d: float) -> float:
	return _dry[_pi(d)]


func rock_at(d: float) -> float:
	return _rock[_pi(d)]


## Which side the sea lies on at d (+1 right, -1 left, 0 none): the edge walls stay down there.
func sea_side_at(d: float) -> float:
	return _sea[_pi(d)]


static func _terrace_shape(h: float, step: float, amount: float) -> float:
	if amount <= 0.0 or h <= 0.0:
		return h
	var f := h / step
	var base := floorf(f)
	var t := f - base
	# most of each band is a gentle shelf; the last part is a steep cliff step
	var shaped := smoothstep(0.55, 0.95, t) * 0.85 + t * 0.15
	return lerpf(h, (base + shaped) * step, amount)


## Natural ground height (before the railway embankment) at world (x, z), which lies at track distance d and
## sideways offset u; ty = height of the rails at d.
func height(x: float, z: float, d: float, u: float, ty: float) -> float:
	var au := absf(u)
	var i := _pi(d)
	var n := _hill.get_noise_2d(x, z)
	# near the track: what the railway was built through (small hills, the valley walls of the theme)
	var amp := lerpf(1.0, 10.0, smoothstep(8.0, 120.0, au)) + (_hills[i] - 10.0) * smoothstep(120.0, 480.0, au)
	var h := ty - 0.4 + n * amp
	h += _walls[i] * smoothstep(30.0, 170.0, au) * (0.6 + 0.4 * (n + 1.0))
	# mountains: warped ridged noise, rising from mstart metres away from the track, cut into cliff bands
	var m_mask := smoothstep(_mstart[i], _mstart[i] + 280.0, au)
	var sea := _sea[i]
	# towards the sea the mountains and the edge walls give way (smoothly along the line)
	var land_k := 1.0 - (absf(sea) * smoothstep(0.0, 60.0, u * signf(sea)) if sea != 0.0 else 0.0)
	if m_mask > 0.0 and land_k > 0.0:
		var wx := _warp.get_noise_2d(x, z) * 160.0
		var wz := _warp.get_noise_2d(z + 517.0, x - 211.0) * 160.0
		var r := clampf((_ridge.get_noise_2d(x + wx, z + wz) + 0.6) / 1.6, 0.0, 1.0)
		var m := _mtn[i] * r * r * m_mask * land_k
		m = _terrace_shape(m, 13.0, _terrace[i])
		h += m
	# the corridor is closed in by high ridges (not towards the sea)
	if au > R_OUT - EDGE_WALL and land_k > 0.0:
		h += land_k * 160.0 * smoothstep(R_OUT - EDGE_WALL, R_OUT + 40.0, au) * (0.75 + 0.25 * n)
	# small bumps and rocks away from the rails
	h += _detail.get_noise_2d(x, z) * 1.4 * smoothstep(20.0, 90.0, au)

	# rivers: meandering gorges across the whole corridor, straight where the bridge crosses
	var ri := _near_river[i]
	if ri >= 0:
		var r := _rivers[ri]
		var dc := r.x + r.w * sin(u / 150.0 + r.z) * smoothstep(40.0, 260.0, au)
		var dist := absf(d - dc)
		var half := r.y * (1.0 + 0.25 * smoothstep(100.0, 600.0, au))
		var bank := 30.0 + 0.55 * maxf(h - Track.WATER_LEVEL, 0.0) * smoothstep(20.0, 140.0, au)
		if dist < half + bank:
			h = lerpf(h, Track.WATER_LEVEL - 4.0, 1.0 - smoothstep(half, half + bank, dist))
	# lakes and the sea
	var li := _near_lake[i]
	if li >= 0:
		var a := _lk[li * 5]
		var b := _lk[li * 5 + 1]
		var su := u * _lk[li * 5 + 2]
		var inner := _lk[li * 5 + 3]
		var outer := _lk[li * 5 + 4]
		var shore := _shore.get_noise_2d(x, z)
		var wobble := shore * 18.0 * smoothstep(inner, inner + 60.0, su)
		# the ends of the lake curve and wander instead of running straight across
		var dw := d + shore * 70.0 * smoothstep(inner + 20.0, inner + 120.0, su) - (su - inner) * 0.25
		var kd := smoothstep(a - 40.0, a + 20.0, dw) * (1.0 - smoothstep(b - 20.0, b + 40.0, dw + (su - inner) * 0.5))
		var ku := smoothstep(inner - 15.0, inner + 15.0, su + wobble) * (1.0 - smoothstep(outer - 80.0, outer, su + wobble))
		if kd * ku > 0.0:
			var depth := Track.WATER_LEVEL - 5.0 - 6.0 * smoothstep(inner + 30.0, inner + 200.0, su)
			h = lerpf(h, depth, kd * ku)
	# level ground around the stations (platforms, buildings)
	if au < 70.0 and _near_station[i] == 1:
		for sd in _stations:
			var dd := absf(d - sd)
			if dd < Track.STATION_LENGTH + 70.0:
				var k := (1.0 - smoothstep(Track.STATION_LENGTH * 0.5 + 10.0, Track.STATION_LENGTH + 70.0, dd)) * (1.0 - smoothstep(22.0, 70.0, au))
				h = lerpf(h, ty - 0.4, k)
	# quest sites: flat plateaus at rail height beside the gates
	if au < 200.0 and _near_zone[i] == 1:
		for zn: Dictionary in zones:
			var c: Vector2 = zn.center
			var reach := ZONE_SIZE + ZONE_BLEND
			if absf(x - c.x) > reach or absf(z - c.y) > reach:
				continue
			var w := zone_weight(zn, x, z)
			if w > 0.0:
				h = lerpf(h, float(zn.height), w)
	return h


## The far land outside the corridor (only seen from afar): big, smooth mountain shapes instead of the detailed
## ones, so they do not alias into spikes at the backdrop's coarse resolution. Low towards the sea.
func far_height(x: float, z: float, d: float, u: float, ty: float) -> float:
	var i := _pi(d)
	var sea := _sea[i]
	var land_k := 1.0 - (absf(sea) * smoothstep(0.0, 60.0, u * signf(sea)) if sea != 0.0 else 0.0)
	var big := _warp.get_noise_2d(x * 0.6, z * 0.6) * 0.5 + 0.5
	var mid := _hill.get_noise_2d(x * 0.08, z * 0.08)
	var h := ty + _walls[i] + 160.0 + (_mtn[i] * 0.8 + 120.0) * big * big + mid * 40.0
	return lerpf(Track.WATER_LEVEL - 12.0, h, land_k)


## 1 inside a quest site's square, fading to 0 over ZONE_BLEND metres outside it.
static func zone_weight(zn: Dictionary, x: float, z: float) -> float:
	var c: Vector2 = zn.center
	var rel := Vector2(x - c.x, z - c.y)
	var half: Vector2 = zn.half
	var lx := absf(rel.dot(zn.right)) - half.x
	var lz := absf(rel.dot(zn.forward)) - half.y
	var out := Vector2(maxf(lx, 0.0), maxf(lz, 0.0)).length()
	return 1.0 - smoothstep(0.0, ZONE_BLEND, out)


## True if world (x, z) lies within `margin` metres of a quest site's square.
func in_zone(x: float, z: float, margin := 0.0) -> bool:
	for zn in zones:
		var c: Vector2 = zn.center
		var rel := Vector2(x - c.x, z - c.y)
		var half: Vector2 = zn.half
		if absf(rel.dot(zn.right)) < half.x + margin and absf(rel.dot(zn.forward)) < half.y + margin:
			return true
	return false
