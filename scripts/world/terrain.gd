class_name Terrain
extends Node3D
## The overworld around the railway: a big heightmap terrain over a corridor up to Landscape.R_OUT metres each side
## of the track, for the whole route. Heights come from Landscape.height (Track.land), so every peer builds the
## same world from Main.SEED.
##
## - Grid: one height per CELL metres (heights[]), drawn as CHUNK x CHUNK chunks of flat meshes that the terrain
##   shader displaces from a heightmap texture, with three levels of detail (visibility ranges) and skirts that hide
##   the cracks between them. Collision (HeightMapShape3D per chunk) only exists near players and enemies.
## - Ribbon: a fine strip along the rails (|u| <= R_RIB) with the exact embankments, cuttings and ballast, always
##   collidable. The grid is hidden under it (the shader discards it there, its colliders sit lower).
## - Water plane (lakes, rivers, the sea), nature scatter (MultiMesh per chunk and model, far trees as cheap
##   silhouettes), and the fenced quest sites beside the gates (Track.quest_zone).

const CELL := 5.0
const CHUNK := 32
const FIELD_CELL := 16.0
## The land continues this far before the start and after the end of the line.
const EXTEND := 320.0
const SAMPLE_STEP := 2.0
## The fine ribbon along the rails covers |u| <= R_RIB + RIB_OVERLAP; the grid is cut away inside RIB_CUT.
const R_RIB := 32.0
const RIB_OVERLAP := 4.0
const RIB_CUT := 30.0
const ROW_STEP := 4.0
const U_OFFSETS := [0.0, 2.0, 4.0, 6.0, 9.0, 12.0, 16.0, 20.0, 24.0, 28.0, 32.0, 36.0]
## Grid levels of detail: full detail up to LOD_END[0] m, half to LOD_END[1], quarter beyond.
const LOD_END := [420.0, 1150.0]
const SKIRT := 8.0
## Chunk colliders exist within this distance of a player or an enemy.
const COLLIDE_RADIUS := 170.0
const UNSET := 1.0e9
const NO_GROUND := -60.0
## Worker threads: the scatter gains from them; the height pass ran slower threaded (GDScript contention), so not.
const THREADS := false
const SCATTER_THREADS := true
## Beyond this distance from the track only every other vertex along x is computed (the rest are interpolated).
const FAR_INTERP := 420.0

var track: Track
var land: Landscape
## Tree and boulder positions near the track: anchor points for the come-along.
var anchor_points: Array[Vector3] = []
## World (x, z) of grid vertex (0, 0); the grid has gw x gh vertices.
var origin := Vector2.ZERO
var gw := 0
var gh := 0
var heights := PackedFloat32Array()
## Milliseconds spent on each build step (printed once, for performance checks).
var build_ms := {}
## Trails, hazards, caves, bridges, waterfalls, rockfalls (see WorldFeatures).
var features: WorldFeatures

var _fd := PackedFloat32Array()   # track distance of every grid vertex
var _fu := PackedFloat32Array()   # sideways offset of every grid vertex
var _cw := 0
var _ch := 0
var _chunk_on := PackedByteArray()
var _colliders := {}              # chunk index -> StaticBody3D
var _rock_shapes := {}            # chunk index -> Array of [Transform3D, Vector3 box size]
var _ts_pos := PackedVector3Array()
var _ts_fwd := PackedVector3Array()
var _ts_right := PackedVector3Array()
var _ts_d0 := 0.0
var _rng := RandomNumberGenerator.new()
var _visual := true
var _collide_timer := 0.0
var _hmap_tex: ImageTexture
var _biome_tex: ImageTexture
var _mat_grid: ShaderMaterial
var _mat_rib: ShaderMaterial
var _forest := FastNoiseLite.new()
var _cd := PackedFloat32Array()   # coarse field: track distance / sideways offset every FIELD_CELL metres
var _cu := PackedFloat32Array()
var _cfw := 0
var _cfh := 0
var _bands: Array = []
var _biome_bytes := PackedByteArray()
var _chunk_range := PackedFloat32Array()  # min / max height per chunk
var _avail := {}
var _rock_aabb := {}   # model bounds of the rocks that get colliders
var _reserved: Array[Vector3] = []
var _scatter_todo: Array[int] = []
var _scatter_out: Array = []


func build(t: Track, rng: RandomNumberGenerator) -> void:
	track = t
	land = t.land
	# one number from the shared generator: how much the terrain draws must not shift the pickups that follow
	_rng.seed = rng.randi()
	_visual = DisplayServer.get_name() != "headless"
	_forest.seed = int(_rng.seed % 100000)
	_forest.frequency = 0.0075
	_forest.fractal_octaves = 3
	var t0 := Time.get_ticks_msec()
	_sample_track()
	_build_field()
	_mark("field", t0)
	_build_heights()
	_mark("heights", t0)
	features = WorldFeatures.new()
	features.plan(self, int(_rng.seed % 1000003))
	_mark("features", t0)
	_build_textures()
	_build_grid_meshes()
	_mark("grid", t0)
	_build_ribbon()
	_mark("ribbon", t0)
	_build_water()
	if _visual:
		_build_backdrop()
	_build_scatter()
	_mark("scatter", t0)
	_build_quest_sites()
	add_child(features)
	features.spawn()
	_mark("total", t0)
	print("[terrain] %dx%d grid (%d m), %d chunks on, build ms %s" % [gw, gh, int(CELL), _chunk_on.count(1), build_ms])
	print("[terrain] %d trails, %d hazards, %d caves, %d rope bridges, %d waterfalls, %d rockfalls, %d logs, %d falling trees" % [
		features.trails.size(), features.hazards.size(), features.caves.size(), features.bridges.size(),
		features.waterfalls.size(), features.rockfalls.size(), features.logs.size(), features.falling_trees.size()])


func _mark(step: String, t0: int) -> void:
	build_ms[step] = Time.get_ticks_msec() - t0


# --- Track coordinates for every grid vertex ------------------------------------------------

func _sample_track() -> void:
	_ts_d0 = -EXTEND
	var n := int((track.get_length() + 2.0 * EXTEND) / SAMPLE_STEP) + 1
	_ts_pos.resize(n)
	_ts_fwd.resize(n)
	_ts_right.resize(n)
	for k in n:
		var d := _ts_d0 + k * SAMPLE_STEP
		_ts_pos[k] = track.point_at(d)
		var r := track.flat_right(d)
		_ts_right[k] = r
		_ts_fwd[k] = Vector3.UP.cross(r)


func _track_y(d: float) -> float:
	var f := clampf((d - _ts_d0) / SAMPLE_STEP, 0.0, _ts_pos.size() - 1.001)
	var k := int(f)
	return lerpf(_ts_pos[k].y, _ts_pos[k + 1].y, f - k)


## Exact (d, u) of world (x, z) near the track, starting from an estimate of d (two projection steps).
func _refine(x: float, z: float, d: float) -> Vector2:
	var u := 0.0
	var last := _ts_pos.size() - 1
	for it in 2:
		var k := clampi(int(round((d - _ts_d0) / SAMPLE_STEP)), 0, last)
		var p := _ts_pos[k]
		var dx := x - p.x
		var dz := z - p.z
		var f := _ts_fwd[k]
		var r := _ts_right[k]
		d = _ts_d0 + k * SAMPLE_STEP + dx * f.x + dz * f.z
		u = dx * r.x + dz * r.z
	return Vector2(d, u)


## Track distance and sideways offset of every grid vertex: splat lines across the track into a coarse field
## (keeping the nearest), then interpolate and refine per vertex. Also decides which chunks exist.
func _build_field() -> void:
	var reach := Landscape.R_OUT + 120.0
	var lo := Vector2(INF, INF)
	var hi := Vector2(-INF, -INF)
	for p in _ts_pos:
		lo = lo.min(Vector2(p.x, p.z))
		hi = hi.max(Vector2(p.x, p.z))
	lo -= Vector2(reach, reach)
	hi += Vector2(reach, reach)
	var span := CHUNK * CELL
	origin = Vector2(floorf(lo.x / span) * span, floorf(lo.y / span) * span)
	_cw = int(ceilf((hi.x - origin.x) / span))
	_ch = int(ceilf((hi.y - origin.y) / span))
	gw = _cw * CHUNK + 1
	gh = _ch * CHUNK + 1

	# coarse field
	var fw := int(ceilf((gw - 1) * CELL / FIELD_CELL)) + 2
	var fh := int(ceilf((gh - 1) * CELL / FIELD_CELL)) + 2
	var cd := PackedFloat32Array()
	var cu := PackedFloat32Array()
	cd.resize(fw * fh)
	cu.resize(fw * fh)
	cu.fill(UNSET)
	var step_u := FIELD_CELL * 0.5
	var steps := int(reach / step_u)
	for k in range(0, _ts_pos.size(), 2):
		var p := _ts_pos[k]
		var r := _ts_right[k]
		var f := _ts_fwd[k]
		var d := _ts_d0 + k * SAMPLE_STEP
		for s in range(-steps, steps + 1):
			var u := s * step_u
			var qx := p.x + r.x * u
			var qz := p.z + r.z * u
			var ci := int(round((qx - origin.x) / FIELD_CELL))
			var cj := int(round((qz - origin.y) / FIELD_CELL))
			if ci < 0 or cj < 0 or ci >= fw or cj >= fh:
				continue
			var idx := cj * fw + ci
			if absf(u) < absf(cu[idx]):
				# correct to the field point's own position
				var ex := origin.x + ci * FIELD_CELL - qx
				var ez := origin.y + cj * FIELD_CELL - qz
				cd[idx] = d + ex * f.x + ez * f.z
				cu[idx] = u + ex * r.x + ez * r.z
	# fill small holes (outside of tight curves) from their neighbours
	for _round in 2:
		var src := cu.duplicate()
		for j in range(1, fh - 1):
			for i in range(1, fw - 1):
				var idx := j * fw + i
				if src[idx] != UNSET:
					continue
				for o in [-1, 1, -fw, fw]:
					if src[idx + o] != UNSET:
						cu[idx] = src[idx + o]
						cd[idx] = cd[idx + o]
						break

	# chunks that touch the corridor
	_chunk_on.resize(_cw * _ch)
	_chunk_on.fill(0)
	var per_chunk := span / FIELD_CELL
	for j in fh:
		for i in fw:
			if absf(cu[j * fw + i]) < Landscape.R_OUT + 40.0:
				var a := clampi(int(i / per_chunk), 0, _cw - 1)
				var b := clampi(int(j / per_chunk), 0, _ch - 1)
				_chunk_on[b * _cw + a] = 1

	_cd = cd
	_cu = cu
	_cfw = fw
	_cfh = fh


## Track coordinates, height and biome bytes of every grid vertex in the chunks that exist, one band of chunk
## rows per worker thread. Every value depends only on the vertex, so the result is the same on every machine.
func _build_heights() -> void:
	_bands.resize(_ch)
	if THREADS:
		var task := WorkerThreadPool.add_group_task(_compute_band, _ch, -1, true, "terrain heights")
		WorkerThreadPool.wait_for_group_task_completion(task)
	else:
		for b in _ch:
			_compute_band(b)
	heights = PackedFloat32Array()
	_fd = PackedFloat32Array()
	_fu = PackedFloat32Array()
	_biome_bytes = PackedByteArray()
	_chunk_range.resize(_cw * _ch * 2)
	for b in _ch:
		var band: Array = _bands[b]
		heights.append_array(band[0])
		_fd.append_array(band[1])
		_fu.append_array(band[2])
		_biome_bytes.append_array(band[3])
		var rng_: PackedFloat32Array = band[4]
		for a in _cw:
			_chunk_range[(b * _cw + a) * 2] = rng_[a * 2]
			_chunk_range[(b * _cw + a) * 2 + 1] = rng_[a * 2 + 1]
	_bands.clear()


## Chunk columns that exist in chunk row b.
func _band_columns(b: int) -> Array[int]:
	var out: Array[int] = []
	if b < 0 or b >= _ch:
		return out
	for a in _cw:
		if _chunk_on[b * _cw + a] == 1:
			out.append(a)
	return out


func _vertex_on(i: int, j: int) -> bool:
	for b in [j / CHUNK, (j - 1) / CHUNK]:
		if b < 0 or b >= _ch or (j - 1 < 0 and b != j / CHUNK):
			continue
		for a in [i / CHUNK, (i - 1) / CHUNK]:
			if a < 0 or a >= _cw or (i - 1 < 0 and a != i / CHUNK):
				continue
			if _chunk_on[b * _cw + a] == 1:
				return true
	return false


func _compute_band(b: int) -> void:
	var j0 := b * CHUNK
	var j1 := (b + 1) * CHUNK if b < _ch - 1 else gh  # exclusive
	var n := (j1 - j0) * gw
	var hs := PackedFloat32Array()
	var ds := PackedFloat32Array()
	var us := PackedFloat32Array()
	var bytes := PackedByteArray()
	hs.resize(n)
	ds.resize(n)
	us.resize(n)
	bytes.resize(n * 4)
	hs.fill(NO_GROUND)
	us.fill(UNSET)
	var ranges := PackedFloat32Array()
	ranges.resize(_cw * 2)
	for a in _cw:
		ranges[a * 2] = INF
		ranges[a * 2 + 1] = -INF
	var ratio := CELL / FIELD_CELL
	var fw := _cfw
	for k in n:
		bytes[k * 4] = 255
	var cols := _band_columns(b)
	var cols_first := _band_columns(b - 1)
	for c in cols:
		if not c in cols_first:
			cols_first.append(c)
	for j in range(j0, j1):
		var pending := PackedInt32Array()
		for a: int in (cols_first if j == j0 else cols):
			var i_end := mini((a + 1) * CHUNK, gw - 1)
			for i in range(a * CHUNK, i_end + 1):
				var k := (j - j0) * gw + i
				if us[k] != UNSET:
					continue
				var gx := i * ratio
				var gz := j * ratio
				var i0 := mini(int(gx), fw - 2)
				var jj0 := mini(int(gz), _cfh - 2)
				var tx := gx - i0
				var tz := gz - jj0
				var c00 := jj0 * fw + i0
				var u00 := _cu[c00]
				var u10 := _cu[c00 + 1]
				var u01 := _cu[c00 + fw]
				var u11 := _cu[c00 + fw + 1]
				var d := 0.0
				var u := 0.0
				if u00 == UNSET or u10 == UNSET or u01 == UNSET or u11 == UNSET:
					# corridor edge: take the nearest known corner
					var best := UNSET
					for c in [c00, c00 + 1, c00 + fw, c00 + fw + 1]:
						if _cu[c] != UNSET and absf(_cu[c]) < best:
							best = absf(_cu[c])
							d = _cd[c]
							u = _cu[c]
					if best == UNSET:
						u = Landscape.R_OUT + 200.0
				else:
					d = lerpf(lerpf(_cd[c00], _cd[c00 + 1], tx), lerpf(_cd[c00 + fw], _cd[c00 + fw + 1], tx), tz)
					u = lerpf(lerpf(u00, u10, tx), lerpf(u01, u11, tx), tz)
				var x := origin.x + i * CELL
				var z := origin.y + j * CELL
				if absf(u) < 220.0:
					var du := _refine(x, z, d)
					d = du.x
					u = du.y
				var h := 0.0
				if i % 2 == 1 and absf(u) > FAR_INTERP:
					pending.append(k)  # far out: every other vertex is the mean of its neighbours (filled below)
				else:
					h = land.height(x, z, d, u, _track_y(d))
				hs[k] = h
				ds[k] = d
				us[k] = u
				var au := absf(u)
				bytes[k * 4] = clampi(int(au / 64.0 * 255.0), 0, 255)
				bytes[k * 4 + 1] = clampi(int(land.dryness_at(d) * 255.0), 0, 255)
				bytes[k * 4 + 2] = clampi(int(land.snow_line_at(d) * 0.5), 0, 255)
				if au < 140.0 and land.in_zone(x, z, 0.0):
					bytes[k * 4 + 3] = 255
				var ca := mini(i / CHUNK, _cw - 1)
				ranges[ca * 2] = minf(ranges[ca * 2], h)
				ranges[ca * 2 + 1] = maxf(ranges[ca * 2 + 1], h)
				if i % CHUNK == 0 and ca > 0:
					ranges[(ca - 1) * 2] = minf(ranges[(ca - 1) * 2], h)
					ranges[(ca - 1) * 2 + 1] = maxf(ranges[(ca - 1) * 2 + 1], h)
		for k in pending:
			var h := (hs[k - 1] + hs[k + 1]) * 0.5
			hs[k] = h
			var ca := mini((k % gw) / CHUNK, _cw - 1)
			ranges[ca * 2] = minf(ranges[ca * 2], h)
			ranges[ca * 2 + 1] = maxf(ranges[ca * 2 + 1], h)
	_bands[b] = [hs, ds, us, bytes, ranges]


## Height map (one float per vertex, read exactly by the shaders) and biome map (r: distance to the track,
## g: dryness, b: snow line, a: quest site), both one texel per grid vertex.
func _build_textures() -> void:
	var img := Image.create_from_data(gw, gh, false, Image.FORMAT_RF, heights.to_byte_array())
	_hmap_tex = ImageTexture.create_from_image(img)
	_biome_tex = ImageTexture.create_from_image(Image.create_from_data(gw, gh, false, Image.FORMAT_RGBA8, _biome_bytes))

	var shader: Shader = load("res://scripts/world/shaders/terrain.gdshader")
	var grain := detail_texture()
	var patches := patch_texture()
	_mat_grid = ShaderMaterial.new()
	_mat_grid.shader = shader
	for m: ShaderMaterial in [_mat_grid]:
		m.set_shader_parameter("hmap", _hmap_tex)
		m.set_shader_parameter("biome", _biome_tex)
		m.set_shader_parameter("grain", grain)
		m.set_shader_parameter("patches", patches)
		m.set_shader_parameter("grid_origin", origin)
		m.set_shader_parameter("grid_size", Vector2(gw, gh))
		m.set_shader_parameter("cell", CELL)
		m.set_shader_parameter("water_level", Track.WATER_LEVEL)
		m.set_shader_parameter("skirt", SKIRT)
		m.set_shader_parameter("ribbon_cut", RIB_CUT)
	_mat_rib = _mat_grid.duplicate()
	_mat_rib.set_shader_parameter("is_grid", false)
	_mat_grid.set_shader_parameter("is_grid", true)


# --- Grid chunks ------------------------------------------------------------------------------

## A flat CHUNK x CHUNK patch with vertices every `step` cells, plus a skirt (UV2.x = 1: pushed down by the shader).
static func _grid_mesh(step: int) -> ArrayMesh:
	var n := CHUNK / step
	var verts := PackedVector3Array()
	var normals := PackedVector3Array()
	var uv2 := PackedVector2Array()
	var idx := PackedInt32Array()
	for j in n + 1:
		for i in n + 1:
			verts.append(Vector3(i * step * CELL, 0.0, j * step * CELL))
			normals.append(Vector3.UP)
			uv2.append(Vector2.ZERO)
	for j in n:
		for i in n:
			var a := j * (n + 1) + i
			var b := a + 1
			var c := a + n + 1
			var dd := c + 1
			idx.append_array([a, b, c, b, dd, c])
	# skirt: the border ring again, dropped down, joined to the border (both windings)
	var ring: Array[int] = []
	for i in n + 1:
		ring.append(i)
	for j in range(1, n + 1):
		ring.append(j * (n + 1) + n)
	for i in range(n - 1, -1, -1):
		ring.append(n * (n + 1) + i)
	for j in range(n - 1, 0, -1):
		ring.append(j * (n + 1))
	var base := verts.size()
	for k in ring.size():
		verts.append(verts[ring[k]])
		normals.append(Vector3.UP)
		uv2.append(Vector2(1.0, 0.0))
	for k in ring.size():
		var k2 := (k + 1) % ring.size()
		var a := ring[k]
		var b := ring[k2]
		var a2 := base + k
		var b2 := base + k2
		idx.append_array([a, b, a2, b, b2, a2, a, a2, b, b, a2, b2])
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_TEX_UV2] = uv2
	arrays[Mesh.ARRAY_INDEX] = idx
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh


func _build_grid_meshes() -> void:
	var lods: Array[ArrayMesh] = [_grid_mesh(1), _grid_mesh(2), _grid_mesh(4)]
	var span := CHUNK * CELL
	for b in _ch:
		for a in _cw:
			if _chunk_on[b * _cw + a] == 0:
				continue
			var lo := _chunk_range[(b * _cw + a) * 2] - 25.0
			var hi := _chunk_range[(b * _cw + a) * 2 + 1] + 25.0
			var aabb := AABB(Vector3(0.0, lo - SKIRT - 1.0, 0.0), Vector3(span, hi - lo + SKIRT + 2.0, span))
			for l in 3:
				var mi := MeshInstance3D.new()
				mi.mesh = lods[l]
				mi.material_override = _mat_grid
				mi.custom_aabb = aabb
				mi.position = Vector3(origin.x + a * span, 0.0, origin.y + b * span)
				if l > 0:
					mi.visibility_range_begin = LOD_END[l - 1]
				if l < 2:
					mi.visibility_range_end = LOD_END[l]
				# the ground does not cast shadows: the coarse levels would shade the fine one in stripes
				mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
				add_child(mi)


## Grid height at world (x, z), interpolated over the same triangles the meshes use. NO_GROUND outside.
func height_at(x: float, z: float) -> float:
	var fx := (x - origin.x) / CELL
	var fz := (z - origin.y) / CELL
	if fx < 0.0 or fz < 0.0 or fx >= gw - 1 or fz >= gh - 1:
		return NO_GROUND
	var i := int(fx)
	var j := int(fz)
	var tx := fx - i
	var tz := fz - j
	var a := heights[j * gw + i]
	var b := heights[j * gw + i + 1]
	var c := heights[(j + 1) * gw + i]
	if tx + tz <= 1.0:
		return a + (b - a) * tx + (c - a) * tz
	var dd := heights[(j + 1) * gw + i + 1]
	return dd + (c - dd) * (1.0 - tx) + (b - dd) * (1.0 - tz)


## Track coordinates (d, u) of grid vertex vi, as used for its height.
func vertex_coords(vi: int) -> Vector2:
	return Vector2(_fd[vi], _fu[vi])


## Track coordinates (d, u) of world (x, z): x = distance along the track, y = sideways offset (UNSET if outside).
func track_coords(x: float, z: float) -> Vector2:
	var i := clampi(int(round((x - origin.x) / CELL)), 0, gw - 1)
	var j := clampi(int(round((z - origin.y) / CELL)), 0, gh - 1)
	var vi := j * gw + i
	if _fu[vi] == UNSET:
		return Vector2(0.0, UNSET)
	if absf(_fu[vi]) > 240.0:
		return Vector2(_fd[vi], _fu[vi])
	return _refine(x, z, _fd[vi])


## Ground height anywhere: the exact rail-side ground (embankments, ballast) near the track, the grid elsewhere.
func ground_at(x: float, z: float) -> float:
	var du := track_coords(x, z)
	if absf(du.y) <= R_RIB:
		return track.ground_height(du.x, du.y)
	return height_at(x, z)


## Track.ground_height without touching nodes (safe on worker threads): natural ground plus the embankment.
func _ground_du(x: float, z: float, d: float, u: float) -> float:
	var ty := _track_y(d)
	var natural := land.height(x, z, d, u, ty)
	if track.is_bridge_at(d):
		return natural
	return lerpf(natural, ty - 0.35, 1.0 - smoothstep(4.0, 16.0, absf(u)))


## Marks grid vertex (i, j) in the biome map's alpha: 64 = keep clear (no scatter), 128 = trail. Quest sites (255)
## stay as they are.
func mark(i: int, j: int, value: int) -> void:
	var k := (j * gw + i) * 4 + 3
	if _biome_bytes[k] < value and _biome_bytes[k] != 255:
		_biome_bytes[k] = value


func _slope_at(i: int, j: int) -> float:
	i = clampi(i, 1, gw - 2)
	j = clampi(j, 1, gh - 2)
	var sx := (heights[j * gw + i + 1] - heights[j * gw + i - 1]) / (2.0 * CELL)
	var sz := (heights[(j + 1) * gw + i] - heights[(j - 1) * gw + i]) / (2.0 * CELL)
	return Vector3(-sx, 1.0, -sz).normalized().y


# --- Collision near players ---------------------------------------------------------------------

func _physics_process(delta: float) -> void:
	_collide_timer -= delta
	if _collide_timer > 0.0 or gw == 0:
		return
	_collide_timer = 0.25
	update_collision()


## Creates chunk colliders around every player and enemy; parks the ones nobody is near.
func update_collision(extra: Array[Vector3] = []) -> void:
	var points: Array[Vector3] = extra.duplicate()
	for group in ["player", "enemy"]:
		for n in get_tree().get_nodes_in_group(group):
			if n is Node3D and (n as Node3D).is_inside_tree():
				points.append((n as Node3D).global_position)
	var span := CHUNK * CELL
	var want := {}
	for p in points:
		var a0 := int(floorf((p.x - COLLIDE_RADIUS - origin.x) / span))
		var a1 := int(floorf((p.x + COLLIDE_RADIUS - origin.x) / span))
		var b0 := int(floorf((p.z - COLLIDE_RADIUS - origin.y) / span))
		var b1 := int(floorf((p.z + COLLIDE_RADIUS - origin.y) / span))
		for b in range(maxi(b0, 0), mini(b1, _ch - 1) + 1):
			for a in range(maxi(a0, 0), mini(a1, _cw - 1) + 1):
				if _chunk_on[b * _cw + a] == 1:
					want[b * _cw + a] = true
	for ci: int in want:
		if not _colliders.has(ci):
			_colliders[ci] = _make_collider(ci)
		var body: StaticBody3D = _colliders[ci]
		if body.process_mode == Node.PROCESS_MODE_DISABLED:
			body.process_mode = Node.PROCESS_MODE_INHERIT
	for ci: int in _colliders:
		if not want.has(ci):
			(_colliders[ci] as StaticBody3D).process_mode = Node.PROCESS_MODE_DISABLED


## True if chunk collision is active at world position p (for tests).
func has_collision_at(p: Vector3) -> bool:
	var span := CHUNK * CELL
	var a := int(floorf((p.x - origin.x) / span))
	var b := int(floorf((p.z - origin.y) / span))
	var ci := b * _cw + a
	return _colliders.has(ci) and (_colliders[ci] as StaticBody3D).process_mode != Node.PROCESS_MODE_DISABLED


func _make_collider(ci: int) -> StaticBody3D:
	var a := ci % _cw
	var b := ci / _cw
	var data := PackedFloat32Array()
	data.resize((CHUNK + 1) * (CHUNK + 1))
	var k := 0
	for j in range(b * CHUNK, (b + 1) * CHUNK + 1):
		for i in range(a * CHUNK, (a + 1) * CHUNK + 1):
			var vi := j * gw + i
			var h := heights[vi]
			if absf(_fu[vi]) < R_RIB - 6.0:
				h -= 4.0  # the ribbon's own collider is the ground here
			data[k] = h / CELL
			k += 1
	var shape := HeightMapShape3D.new()
	shape.map_width = CHUNK + 1
	shape.map_depth = CHUNK + 1
	shape.map_data = data
	var body := StaticBody3D.new()
	body.name = "Ground_%d" % ci
	body.collision_layer = Build.LAYER_WORLD
	var cs := CollisionShape3D.new()
	cs.shape = shape
	cs.scale = Vector3.ONE * CELL
	body.add_child(cs)
	var half := CHUNK * CELL * 0.5
	body.position = Vector3(origin.x + a * CHUNK * CELL + half, 0.0, origin.y + b * CHUNK * CELL + half)
	# big rocks and cliffs in this chunk are solid too
	for rs: Array in _rock_shapes.get(ci, []):
		var box := BoxShape3D.new()
		box.size = rs[1]
		var rc := CollisionShape3D.new()
		rc.shape = box
		rc.transform = Transform3D(Basis(), -body.position) * (rs[0] as Transform3D)
		body.add_child(rc)
	add_child(body)
	return body


# --- Ribbon along the rails ------------------------------------------------------------------

func _build_ribbon() -> void:
	var us: Array[float] = []
	for k in range(U_OFFSETS.size() - 1, 0, -1):
		us.append(-float(U_OFFSETS[k]))
	for k in U_OFFSETS:
		us.append(float(k))
	var rows_per_chunk := 40
	var d := -EXTEND
	var end := track.get_length() + EXTEND
	while d < end:
		_ribbon_chunk(d, minf(d + rows_per_chunk * ROW_STEP, end), us)
		d += rows_per_chunk * ROW_STEP


func _ribbon_chunk(d0: float, d1: float, us: Array[float]) -> void:
	var cols := us.size()
	var verts := PackedVector3Array()
	var colors := PackedColorArray()
	var rows := 0
	var d := d0
	while d <= d1 + 0.01:
		var k := clampi(int(round((d - _ts_d0) / SAMPLE_STEP)), 0, _ts_pos.size() - 1)
		var p := _ts_pos[k]
		var right := _ts_right[k]
		var bridge := track.is_bridge_at(d)
		for u in us:
			var v := p + right * u
			var au := absf(u)
			v.y = _ground_du(v.x, v.z, d, u)
			if au > R_RIB + 0.1:
				v.y -= 0.7  # the outer edge tucks under the grid
			verts.append(v)
			var ballast := 0.0 if bridge else 1.0 - smoothstep(2.6, 3.6, au)
			colors.append(Color(ballast, 0.0, 0.0))
		rows += 1
		d += ROW_STEP
	var idx := PackedInt32Array()
	for r in rows - 1:
		for c in cols - 1:
			var a := r * cols + c
			var b := a + 1
			var cc := a + cols
			var dd := cc + 1
			idx.append_array([a, cc, b, b, cc, dd])
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for k in verts.size():
		st.set_color(colors[k])
		st.add_vertex(verts[k])
	for k in idx:
		st.add_index(k)
	st.generate_normals()
	var mesh := st.commit()
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = _mat_rib
	mi.visibility_range_end = 2200.0
	add_child(mi)
	var body := StaticBody3D.new()
	body.collision_layer = Build.LAYER_WORLD
	var cs := CollisionShape3D.new()
	var faces := PackedVector3Array()
	for k in idx:
		faces.append(verts[k])
	var shape := ConcavePolygonShape3D.new()
	shape.set_faces(faces)
	cs.shape = shape
	body.add_child(cs)
	add_child(body)


# --- Backdrop -----------------------------------------------------------------------------------

## Far land beyond the playable corridor (up to BACKDROP metres further): the same landscape at 40 m resolution
## in a few plain meshes without collision, tucked under the real terrain at the corridor's edge. Only seen from
## mountain tops and from far away; skipped headless.
const BACKDROP := 2600.0
const BACKDROP_CELL := 40.0

func _build_backdrop() -> void:
	var fcell := 64.0
	var lo := origin - Vector2(BACKDROP, BACKDROP)
	var hi := origin + Vector2((gw - 1) * CELL, (gh - 1) * CELL) + Vector2(BACKDROP, BACKDROP)
	var fw := int((hi.x - lo.x) / fcell) + 2
	var fh := int((hi.y - lo.y) / fcell) + 2
	var bd := PackedFloat32Array()
	var bu := PackedFloat32Array()
	bd.resize(fw * fh)
	bu.resize(fw * fh)
	bu.fill(UNSET)
	var reach := Landscape.R_OUT + BACKDROP + 600.0
	for k in range(0, _ts_pos.size(), 8):
		var p := _ts_pos[k]
		var r := _ts_right[k]
		var d := _ts_d0 + k * SAMPLE_STEP
		var u := -reach
		while u <= reach:
			var ci := int(round((p.x + r.x * u - lo.x) / fcell))
			var cj := int(round((p.z + r.z * u - lo.y) / fcell))
			if ci >= 0 and cj >= 0 and ci < fw and cj < fh:
				var idx := cj * fw + ci
				if absf(u) < absf(bu[idx]):
					bu[idx] = u
					bd[idx] = d
			u += 32.0
	for _round in 4:
		var src := bu.duplicate()
		for j in range(1, fh - 1):
			for i in range(1, fw - 1):
				var idx := j * fw + i
				if src[idx] == UNSET:
					for o in [-1, 1, -fw, fw]:
						if src[idx + o] != UNSET:
							bu[idx] = src[idx + o] + signf(src[idx + o]) * fcell
							bd[idx] = bd[idx + o]
							break
	var nx := int((hi.x - lo.x) / BACKDROP_CELL) + 1
	var nz := int((hi.y - lo.y) / BACKDROP_CELL) + 1
	var verts := PackedVector3Array()
	var inside := PackedByteArray()
	verts.resize(nx * nz)
	inside.resize(nx * nz)
	for j in nz:
		for i in nx:
			var x := lo.x + i * BACKDROP_CELL
			var z := lo.y + j * BACKDROP_CELL
			var ci := clampi(int(round((x - lo.x) / fcell)), 0, fw - 1)
			var cj := clampi(int(round((z - lo.y) / fcell)), 0, fh - 1)
			var u := bu[cj * fw + ci]
			var d := bd[cj * fw + ci]
			if u == UNSET:
				u = reach
			var au := absf(u)
			var ty := _track_y(d)
			var h := land.height(x, z, d, u, ty)
			var k := smoothstep(Landscape.R_OUT + 60.0, Landscape.R_OUT + 500.0, au)
			if k > 0.0:
				h = lerpf(h, land.far_height(x, z, d, u, ty), k)
			if au < Landscape.R_OUT + 80.0:
				h -= 30.0  # under the real terrain
			verts[j * nx + i] = Vector3(x, h, z)
			inside[j * nx + i] = 1 if au < Landscape.R_OUT - 200.0 else 0
	# a few pieces, so the camera can cull most of it
	var pieces := 4
	for py in pieces:
		var st := SurfaceTool.new()
		st.begin(Mesh.PRIMITIVE_TRIANGLES)
		var j0 := py * (nz - 1) / pieces
		var j1 := (py + 1) * (nz - 1) / pieces
		var any := false
		for j in range(j0, j1):
			for i in nx - 1:
				var a := j * nx + i
				var b := a + 1
				var c := a + nx
				var e := c + 1
				if inside[a] == 1 and inside[b] == 1 and inside[c] == 1 and inside[e] == 1:
					continue
				for v in [a, b, c, b, e, c]:
					st.set_color(Color.BLACK)
					st.add_vertex(verts[v])
				any = true
		if not any:
			continue
		st.generate_normals()
		var mi := MeshInstance3D.new()
		mi.mesh = st.commit()
		mi.material_override = _mat_rib
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		mi.name = "Backdrop_%d" % py
		add_child(mi)


# --- Water --------------------------------------------------------------------------------------

func _build_water() -> void:
	var mi := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2((gw - 1) * CELL, (gh - 1) * CELL) + Vector2(2 * BACKDROP + 2000.0, 2 * BACKDROP + 2000.0)
	mi.mesh = plane
	var mat := ShaderMaterial.new()
	mat.shader = load("res://scripts/world/shaders/water.gdshader")
	mat.set_shader_parameter("hmap", _hmap_tex)
	mat.set_shader_parameter("grid_origin", origin)
	mat.set_shader_parameter("grid_size", Vector2(gw, gh))
	mat.set_shader_parameter("cell", CELL)
	mi.material_override = mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.position = Vector3(origin.x + (gw - 1) * CELL * 0.5, Track.WATER_LEVEL, origin.y + (gh - 1) * CELL * 0.5)
	mi.name = "Water"
	add_child(mi)


# --- Textures -------------------------------------------------------------------------------------

## Grey-white grain multiplied over the ground colours (clumps of grass, pebbles), tiling in world space.
static func detail_texture() -> Texture2D:
	var noise := FastNoiseLite.new()
	noise.noise_type = FastNoiseLite.TYPE_CELLULAR
	noise.frequency = 0.06
	noise.fractal_type = FastNoiseLite.FRACTAL_FBM
	noise.fractal_octaves = 3
	var tex := NoiseTexture2D.new()
	tex.noise = noise
	tex.seamless = true
	tex.width = 256
	tex.height = 256
	var ramp := Gradient.new()
	ramp.set_color(0, Color(0.72, 0.72, 0.72))
	ramp.set_color(1, Color(1.0, 1.0, 1.0))
	tex.color_ramp = ramp
	tex.generate_mipmaps = true
	return tex


## Smooth 0-1 noise for large colour patches (meadows, dry grass, rock strata).
static func patch_texture() -> Texture2D:
	var noise := FastNoiseLite.new()
	noise.frequency = 0.012
	noise.fractal_octaves = 4
	var tex := NoiseTexture2D.new()
	tex.noise = noise
	tex.seamless = true
	tex.normalize = true
	tex.width = 512
	tex.height = 512
	tex.generate_mipmaps = true
	return tex


# --- Nature ------------------------------------------------------------------------------------

## Mesh of a Blender nature model (assets/models/nature/<id>.glb), for MultiMesh scattering.
static func nature_mesh(id: String) -> Mesh:
	var scene: Node = load("res://assets/models/nature/%s.glb" % id).instantiate()
	var mi: MeshInstance3D = scene.find_children("*", "MeshInstance3D", true, false)[0]
	var mesh := mi.mesh
	scene.free()
	return mesh


static func has_nature(id: String) -> bool:
	return ResourceLoader.exists("res://assets/models/nature/%s.glb" % id)


## Per model: how far it stays visible, whether it casts shadows, its far silhouette (or "").
const SCATTER := {
	"pine": [300.0, true, "conifer"], "pine_snow": [300.0, true, "conifer_snow"], "oak": [260.0, true, "broadleaf"],
	"birch": [260.0, true, "broadleaf_light"], "dead_tree": [220.0, true, ""], "bush": [160.0, false, ""],
	"rock_small": [130.0, false, ""], "boulder": [700.0, true, ""], "cliff": [2600.0, true, ""],
	"rock_spire": [2600.0, true, ""], "cliff_big": [2600.0, true, ""], "log": [140.0, false, ""],
	"grass_clump": [70.0, false, ""], "flowers": [70.0, false, ""], "fern": [80.0, false, ""],
}


## Trees, bushes, rocks, cliffs and grass over the whole land, chosen per theme, height and slope.
## One MultiMesh per chunk and model, so each chunk can fade out on its own; trees far away become simple
## silhouettes. Nothing grows on the quest sites, by the gates and keys, in water or on the ballast.
func _build_scatter() -> void:
	_reserved = track.reserved_spots()
	var span := CHUNK * CELL
	for id: String in SCATTER:
		_avail[id] = has_nature(id)
	for id: String in ["boulder", "cliff", "cliff_big", "rock_spire"]:
		if _avail[id]:
			_rock_aabb[id] = nature_mesh(id).get_aabb()
	# headless (tests, a server): only the chunks along the rails, where the come-along anchors grow
	var todo: Array[int] = []
	for ci in _cw * _ch:
		if _chunk_on[ci] == 1 and (_visual or _chunk_min_u(ci) < 60.0):
			todo.append(ci)
	_scatter_todo = todo
	_scatter_out.resize(todo.size())
	if SCATTER_THREADS:
		var task := WorkerThreadPool.add_group_task(_scatter_task, todo.size(), -1, true, "terrain scatter")
		WorkerThreadPool.wait_for_group_task_completion(task)
	else:
		for k in todo.size():
			_scatter_task(k)
	var meshes := {}
	var far_meshes := {}
	for k in todo.size():
		var ci := todo[k]
		var res: Dictionary = _scatter_out[k]
		var a := ci % _cw
		var b := ci / _cw
		for p: Vector3 in res.anchors:
			anchor_points.append(p)
		if not (res.rocks as Array).is_empty():
			_rock_shapes[ci] = res.rocks
		var center := Vector3(origin.x + (a + 0.5) * span, 0.0, origin.y + (b + 0.5) * span)
		var lists: Dictionary = res.lists
		for id: String in lists:
			var list: Array = lists[id]
			if list.is_empty():
				continue
			var spec: Array = SCATTER[id]
			if not _visual and float(spec[0]) < 200.0:
				continue  # headless: small things nobody sees are skipped (anchor trees stay)
			if not meshes.has(id):
				meshes[id] = nature_mesh(id)
			_add_multimesh(meshes[id], list, center, 0.0, float(spec[0]), bool(spec[1]))
			var far: String = spec[2]
			if far != "" and _visual:
				if not far_meshes.has(far):
					far_meshes[far] = _far_mesh(far)
				_add_multimesh(far_meshes[far], list, center, float(spec[0]) - 30.0, 3200.0, false)
	_scatter_out.clear()


func _chunk_min_u(ci: int) -> float:
	var a := ci % _cw
	var b := ci / _cw
	var best := INF
	for j in range(b * CHUNK, (b + 1) * CHUNK + 1, 4):
		for i in range(a * CHUNK, (a + 1) * CHUNK + 1, 4):
			best = minf(best, absf(_fu[j * gw + i]))
	return best


func _scatter_task(k: int) -> void:
	var ci := _scatter_todo[k]
	var res := {"lists": {}, "anchors": [], "rocks": []}
	_scatter_chunk(ci % _cw, ci / _cw, res, ci)
	_scatter_out[k] = res


func _add_multimesh(mesh: Mesh, list: Array, center: Vector3, begin: float, end: float, shadows: bool) -> void:
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = mesh
	mm.instance_count = list.size()
	var buf := PackedFloat32Array()
	buf.resize(list.size() * 12)
	var k := 0
	for t: Transform3D in list:
		var bs := t.basis
		var o := t.origin - center
		buf[k] = bs.x.x; buf[k + 1] = bs.y.x; buf[k + 2] = bs.z.x; buf[k + 3] = o.x
		buf[k + 4] = bs.x.y; buf[k + 5] = bs.y.y; buf[k + 6] = bs.z.y; buf[k + 7] = o.y
		buf[k + 8] = bs.x.z; buf[k + 9] = bs.y.z; buf[k + 10] = bs.z.z; buf[k + 11] = o.z
		k += 12
	mm.buffer = buf
	var mmi := MultiMeshInstance3D.new()
	mmi.multimesh = mm
	mmi.position = center
	if begin > 0.0:
		mmi.visibility_range_begin = begin
		mmi.visibility_range_begin_margin = 30.0
	mmi.visibility_range_end = end
	mmi.visibility_range_end_margin = 30.0
	if not shadows:
		mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mmi)


func _put(lists: Dictionary, id: String, t: Transform3D) -> void:
	if not lists.has(id):
		var empty: Array[Transform3D] = []
		lists[id] = empty
	lists[id].append(t)


func _scatter_chunk(a: int, b: int, res: Dictionary, ci: int) -> void:
	var lists: Dictionary = res.lists
	var anchors: Array = res.anchors
	var available := _avail
	var reserved := _reserved
	var rng := RandomNumberGenerator.new()
	rng.seed = _rng.seed + ci * 7919
	# grass, flowers and ferns draw from their own generator: the same trees and rocks with or without them
	var deco := RandomNumberGenerator.new()
	deco.seed = _rng.seed + ci * 104729 + 17
	const STEP := 7.0
	var span := CHUNK * CELL
	var x0 := origin.x + a * span
	var z0 := origin.y + b * span
	var n := int(span / STEP)
	for jz in n:
		for ix in n:
			var x := x0 + (ix + rng.randf()) * STEP
			var z := z0 + (jz + rng.randf()) * STEP
			var r1 := rng.randf()
			var r2 := rng.randf()
			var r3 := rng.randf()
			var gi := int(round((x - origin.x) / CELL))
			var gj := int(round((z - origin.y) / CELL))
			var vi := gj * gw + gi
			var u := _fu[vi]
			if u == UNSET or absf(u) > Landscape.R_OUT + 30.0:
				continue
			var au := absf(u)
			var d := _fd[vi]
			if au < 9.0 or _biome_bytes[vi * 4 + 3] != 0:
				continue
			var y: float
			if au < R_RIB + 2.0:
				var du := _refine(x, z, d)
				if absf(du.y) < 9.0 or track.is_bridge_at(du.x):
					continue
				y = _ground_du(x, z, du.x, du.y)
				if track.station_at(du.x) != -1 and absf(du.y) < 25.0:
					continue
				if reserved.any(func(rp: Vector3): return Vector2(rp.x - x, rp.z - z).length() < 8.0):
					continue
			else:
				y = height_at(x, z)
			if y < Track.WATER_LEVEL + 0.9:
				continue
			if land.in_zone(x, z, 8.0):
				continue
			var up := _slope_at(gi, gj)
			var p := Vector3(x, y, z)
			var snow := land.snow_line_at(d)
			var forest := land.forest_at(d)
			var rocky := land.rock_at(d)
			var dry := land.dryness_at(d)
			var fn := _forest.get_noise_2d(x, z) * 0.5 + 0.5
			var density := clampf(forest * (fn * 1.7 - 0.25), 0.0, 1.0)
			# cliffs and crags on steep ground
			if up < 0.72:
				if r1 < 0.01 + rocky * 0.03:
					var id := "cliff"
					var sc := rng.randf_range(0.9, 1.4)
					if r2 < 0.45 and available.cliff_big:
						id = "cliff_big"
						sc = rng.randf_range(0.55, 1.0)
					elif r2 < 0.8 and available.rock_spire:
						id = "rock_spire"
						sc = rng.randf_range(0.5, 1.0)
					_put_rock(res, id, p - Vector3.UP * (3.0 * sc if id != "cliff" else 1.0), sc, rng)
				elif r1 < 0.07:
					_put_rock(res, "boulder", p - Vector3.UP * 0.4, rng.randf_range(0.8, 2.0), rng)
				continue
			if y > snow + 25.0:
				if r1 < 0.03:
					_put_rock(res, "boulder", p - Vector3.UP * 0.3, rng.randf_range(0.8, 2.2), rng)
				continue
			if r1 < density * 0.85 and up > 0.8:
				var id := _tree_kind(y, snow, r2, d)
				var sc := rng.randf_range(0.75, 1.4)
				var t := _place(p - Vector3.UP * 0.15, sc, rng)
				_put(lists, id, t)
				if au < 45.0 and id != "bush":
					anchors.append(p)
				# undergrowth in the forest
				if r3 < 0.35 and available.fern and _visual:
					_put(lists, "fern", _place(p + Vector3(deco.randf_range(-2.5, 2.5), 0.0, deco.randf_range(-2.5, 2.5)), deco.randf_range(0.7, 1.3), deco))
				continue
			# open ground: rocks, logs, bushes, grass and flowers
			if r1 < 0.012 + rocky * 0.03:
				var bsz := rng.randf_range(0.5, 1.8)
				var t := _put_rock(res, "boulder", p - Vector3.UP * 0.3, bsz, rng)
				if au < 45.0:
					anchors.append(t.origin)
			elif r1 < 0.06 + rocky * 0.05:
				_put(lists, "rock_small", _place(p - Vector3.UP * 0.05, rng.randf_range(0.6, 1.6), rng))
			elif r1 < 0.075 and available.log and density > 0.05:
				_put(lists, "log", _place(p, rng.randf_range(0.8, 1.2), rng))
			elif r1 < 0.12 + density * 0.2:
				_put(lists, "bush", _place(p - Vector3.UP * 0.1, rng.randf_range(0.7, 1.4), rng))
			if _visual and au < 320.0 and y < snow - 20.0:
				# meadow grass and flowers (dense near the track, thinner further out)
				var tufts := 3 if au < 120.0 else 1
				for k in tufts:
					var q := Vector3(x + deco.randf_range(-3.5, 3.5), y, z + deco.randf_range(-3.5, 3.5))
					var kind := "flowers" if deco.randf() < 0.18 * (1.0 - dry) else "grass_clump"
					if available[kind] and (au > R_RIB + 4.0 or not reserved.any(func(rp: Vector3): return Vector2(rp.x - q.x, rp.z - q.z).length() < 4.0)):
						_put(lists, kind, _place(q - Vector3.UP * 0.05, deco.randf_range(0.7, 1.3), deco))


## Tree species for a spot: theme, height above the snow line and chance.
func _tree_kind(y: float, snow: float, r: float, d: float) -> String:
	if y > snow - 30.0:
		return "pine_snow" if r < 0.85 else "dead_tree"
	if y > snow - 70.0:
		return "pine" if r < 0.75 else ("pine_snow" if r < 0.92 else "dead_tree")
	var theme: String = track.theme_at(clampf(d, 0.0, track.get_length())).name
	if theme == "Mountain pass":
		return "pine" if r < 0.8 else ("dead_tree" if r < 0.86 else "bush")
	if theme == "River valley" or theme == "The lake":
		return "oak" if r < 0.3 else ("birch" if r < 0.55 else ("pine" if r < 0.85 else "bush"))
	if theme == "The coast":
		return "pine" if r < 0.5 else ("oak" if r < 0.6 else "bush")
	return "pine" if r < 0.6 else ("oak" if r < 0.75 else ("birch" if r < 0.85 else "bush"))


func _place(p: Vector3, scale: float, rng: RandomNumberGenerator, squash := 1.0) -> Transform3D:
	var basis := Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3(scale, scale * squash, scale))
	return Transform3D(basis, p)


## A rock or cliff; the big ones become solid when their chunk gets collision.
func _put_rock(res: Dictionary, id: String, p: Vector3, scale: float, rng: RandomNumberGenerator) -> Transform3D:
	var lists: Dictionary = res.lists
	if not _avail.get(id, false):
		id = "boulder"
	var t := _place(p, scale, rng, rng.randf_range(0.85, 1.25))
	_put(lists, id, t)
	if (scale >= 1.4 or id != "boulder") and _rock_aabb.has(id):
		var aabb: AABB = _rock_aabb[id]
		var box := Transform3D(t.basis.orthonormalized(), t * aabb.get_center())
		(res.rocks as Array).append([box, aabb.size * t.basis.get_scale() * 0.8])
	return t


## Cheap far-away silhouettes for trees (a few triangles each), the same size as the models.
static func _far_mesh(kind: String) -> Mesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var green := Color(0.13, 0.24, 0.12)
	var trunk := CylinderMesh.new()
	trunk.top_radius = 0.18
	trunk.bottom_radius = 0.28
	trunk.height = 2.5
	trunk.radial_segments = 5
	trunk.rings = 1
	var crown: PrimitiveMesh
	var crown_y := 0.0
	match kind:
		"conifer", "conifer_snow":
			var c := CylinderMesh.new()
			c.top_radius = 0.0
			c.bottom_radius = 2.6
			c.height = 10.5
			c.radial_segments = 6
			c.rings = 1
			crown = c
			crown_y = 6.8
			if kind == "conifer_snow":
				green = Color(0.45, 0.52, 0.5)
		_:
			var sph := SphereMesh.new()
			sph.radius = 3.0
			sph.height = 5.0
			sph.radial_segments = 7
			sph.rings = 3
			crown = sph
			crown_y = 5.2
			green = Color(0.2, 0.3, 0.13) if kind == "broadleaf" else Color(0.32, 0.4, 0.18)
	var mat := StandardMaterial3D.new()
	mat.vertex_color_use_as_albedo = true
	mat.roughness = 1.0
	st.set_material(mat)
	st.set_color(Color(0.25, 0.18, 0.12))
	st.append_from(trunk, 0, Transform3D(Basis(), Vector3(0, 1.25, 0)))
	var crown_st := SurfaceTool.new()
	crown_st.create_from(crown, 0)
	var arrays := crown_st.commit_to_arrays()
	var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
	var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
	var base := 0
	for k in indices:
		st.set_color(green)
		st.set_normal(normals[k])
		st.add_vertex(verts[k] + Vector3(0, crown_y, 0))
		base += 1
	return st.commit()


## The quest site beside segment `seg`'s gate (see Track.quest_zone).
func quest_zone(seg: int) -> Dictionary:
	return track.quest_zone(seg)


# --- Quest sites -----------------------------------------------------------------------------

## A low fence of posts and rope around every quest site, open towards the track and the gate, with a
## "QUEST SITE" sign at the opening.
func _build_quest_sites() -> void:
	var posts: Array[Transform3D] = []
	var ropes: Array[Transform3D] = []
	var flags: Array[Transform3D] = []
	for s in track.quest_zone_count():
		var q := track.quest_zone(s)
		var c: Vector3 = q.center
		var f: Vector3 = q.forward
		var side: float = q.side
		var r := f.cross(Vector3.UP)
		var half: float = q.size.x * 0.5
		# perimeter, counter-clockwise from the near-track corner behind the gate
		var near := -side  # the edge nearest the track lies at local x = near * half
		var corners := [Vector2(near * half, -half), Vector2(near * half, half), Vector2(-near * half, half), Vector2(-near * half, -half)]
		var opening := Vector2(10.0 - 9.0, 10.0 + 9.0)  # along-track range of the gap on the near edge (gate side)
		var last := Vector3.INF
		for e in 4:
			var p0: Vector2 = corners[e]
			var p1: Vector2 = corners[(e + 1) % 4]
			var n := int(p0.distance_to(p1) / 8.0)
			for k in n:
				var l := p0.lerp(p1, float(k) / n)
				var in_gap := e == 0 and l.y > opening.x and l.y < opening.y
				var w := c + r * l.x + f * l.y
				w.y = ground_at(w.x, w.z)
				if in_gap:
					last = Vector3.INF
					continue
				var corner := k == 0
				posts.append(Transform3D(Basis().scaled(Vector3(1, 1.6 if corner else 1.0, 1)), w))
				if corner:
					flags.append(Transform3D(Basis.looking_at(f, Vector3.UP), w + Vector3.UP * 1.75))
				if last != Vector3.INF:
					var a := last + Vector3.UP * 0.85
					var bpt := w + Vector3.UP * 0.85
					var mid := (a + bpt) * 0.5
					var dir := bpt - a
					ropes.append(Transform3D(Basis.looking_at(dir, Vector3.UP).scaled(Vector3(1, 1, dir.length())), mid))
				last = w
		# sign at the opening, facing the track
		var sp := c + r * (near * (half + 1.5)) + f * (opening.y + 2.0)
		sp.y = ground_at(sp.x, sp.z)
		var sign := Node3D.new()
		sign.name = "QuestSign_%d" % s
		add_child(sign)
		sign.global_transform = Transform3D(Basis.looking_at(-r * near, Vector3.UP), sp)
		Build.box(sign, Vector3(0.16, 2.2, 0.16), Vector3(-1.0, 1.1, 0), Color(0.33, 0.22, 0.12))
		Build.box(sign, Vector3(0.16, 2.2, 0.16), Vector3(1.0, 1.1, 0), Color(0.33, 0.22, 0.12))
		Build.box(sign, Vector3(2.6, 0.9, 0.08), Vector3(0, 1.75, 0), Color(0.55, 0.4, 0.22))
		var label := Build.label(sign, "QUEST SITE", Vector3(0, 1.78, -0.06), 44)
		label.billboard = BaseMaterial3D.BILLBOARD_DISABLED
		label.rotation.y = PI
		label.modulate = Color(0.98, 0.92, 0.75)
		label.outline_modulate = Color(0.2, 0.1, 0.03)
		var back := Build.label(sign, "QUEST SITE", Vector3(0, 1.78, 0.06), 44)
		back.billboard = BaseMaterial3D.BILLBOARD_DISABLED
		back.modulate = label.modulate
		back.outline_modulate = label.outline_modulate
	var post_mesh := CylinderMesh.new()
	post_mesh.top_radius = 0.07
	post_mesh.bottom_radius = 0.09
	post_mesh.height = 1.1
	post_mesh.radial_segments = 6
	post_mesh.material = Build.material(Color(0.4, 0.28, 0.16))
	var rope_mesh := BoxMesh.new()
	rope_mesh.size = Vector3(0.04, 0.04, 1.0)
	rope_mesh.material = Build.material(Color(0.75, 0.62, 0.38))
	var flag_mesh := BoxMesh.new()
	flag_mesh.size = Vector3(0.02, 0.35, 0.55)
	flag_mesh.material = Build.material(Color(0.85, 0.3, 0.12))
	var shifted: Array[Transform3D] = []
	for t in posts:
		shifted.append(t.translated(Vector3.UP * 0.55 * t.basis.get_scale().y))
	for pair in [[post_mesh, shifted], [rope_mesh, ropes], [flag_mesh, flags]]:
		var list: Array[Transform3D] = pair[1]
		if list.is_empty():
			continue
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.mesh = pair[0]
		mm.instance_count = list.size()
		for k in list.size():
			mm.set_instance_transform(k, list[k])
		var mmi := MultiMeshInstance3D.new()
		mmi.multimesh = mm
		mmi.visibility_range_end = 600.0
		add_child(mmi)
