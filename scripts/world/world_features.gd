class_name WorldFeatures
extends Node3D
## Things to find and survive off the rails, laid out per landscape theme (all from the seed, so every peer
## builds the same ones; node names are deterministic):
## - Trails from the track up to viewpoints (a cairn and a flag), some blocked by a fallen log or a dead tree that
##   comes down when someone walks up.
## - Hazards: mud bogs and quicksand (slow you down), ice (slippery), thorn thickets (hurt), geysers (throw you up).
## - Landmarks: caves (shelter, supplies inside), rope bridges over the river gorges, waterfalls.
## - Rockfalls: boulders tumble down beside the track when the train passes some cliffs.
## - Out of bounds: walk too far from the line and you are warned, then put back on the train.
## Terrain calls plan() once the heights exist (it marks trails and keeps hazards clear of trees), then spawn().
## Hazards act on the LOCAL player only (each peer moves its own player); damage goes through Net.request.

const MUD_SLOW := 0.55        # share of each step the mud takes back
const ICE_GRIP := 1.4         # how quickly you get your footing back on ice (1/s)
const THORN_DAMAGE := 4.0     # per half second in the thorns
const GEYSER_PERIOD := 11.0
const GEYSER_BURST := 2.4
const GEYSER_LAUNCH := 15.0
const OUT_WARN := 90.0        # metres inside the corridor edge where the warning starts
const OUT_LIMIT := 35.0       # ... and where you are put back on the train

var terrain: Terrain
var track: Track
var land: Landscape
## Trail polylines (ground points every ~10 m) from beside the track to a viewpoint.
var trails: Array[PackedVector3Array] = []
var viewpoints: Array[Vector3] = []
## {kind: "mud" | "quicksand" | "ice" | "thorns" | "geyser", pos: Vector3, radius: float, name}
var hazards: Array[Dictionary] = []
## Cave origins (mouth along -Z of the transform).
var caves: Array[Transform3D] = []
## Rope bridges: [end a, end b].
var bridges: Array[Array] = []
## Waterfalls: [top, bottom].
var waterfalls: Array[Array] = []
## Rockfalls: {d, start: Vector3, stops: Array[Vector3], done}
var rockfalls: Array[Dictionary] = []
## Fallen logs across trails: Transform3D; falling trees: {pivot: Transform3D, trigger: Vector3, fallen}
var logs: Array[Transform3D] = []
var falling_trees: Array[Dictionary] = []
## Places worth walking to, where Main leaves supplies (caves, viewpoints).
var resource_spots: Array[Vector3] = []

var _rng := RandomNumberGenerator.new()
var _visual := true
var _state := {}            # player instance id -> {last: Vector3, slide: Vector3, hurt: float, warned: bool}
var _time := 0.0
var _geysers: Array[Dictionary] = []   # {pos, particles, phase}
var _rock_nodes: Array = []            # per rockfall: Array of MeshInstance3D
var _tree_nodes: Array[Node3D] = []
var _hint_cd := 0.0


# --- Planning (data only) ------------------------------------------------------------------

func plan(t: Terrain, seed_value: int) -> void:
	terrain = t
	track = t.track
	land = t.land
	_rng.seed = seed_value
	_visual = DisplayServer.get_name() != "headless"
	for seg in Track.THEMES.size():
		_plan_trails(seg)
	for seg in Track.THEMES.size():
		_plan_hazards(seg)
		_plan_caves(seg)
		_plan_rockfalls(seg)
	_plan_rivers()
	_stamp()


func _theme(seg: int) -> String:
	return Track.THEMES[seg].name


## A spot (d, u) is fine for something big if it is away from stations, gates, quest sites and bridges.
func _clear_of_track_things(d: float, u: float, pos: Vector3, margin: float) -> bool:
	if absf(u) < 22.0:
		return false
	for sd in track.station_distances:
		if absf(d - sd) < Track.STATION_LENGTH + 40.0 and absf(u) < 80.0:
			return false
	if land.in_zone(pos.x, pos.z, margin + 10.0):
		return false
	return true


func _ground(x: float, z: float) -> float:
	return terrain.ground_at(x, z)


func _world(d: float, u: float) -> Vector3:
	var p := track.point_at(d) + track.flat_right(d) * u
	p.y = _ground(p.x, p.z)
	return p


func _slope(p: Vector3) -> float:
	var hx := _ground(p.x + 2.0, p.z) - _ground(p.x - 2.0, p.z)
	var hz := _ground(p.x, p.z + 2.0) - _ground(p.x, p.z - 2.0)
	return Vector2(hx, hz).length() / 4.0


func _plan_trails(seg: int) -> void:
	var s0 := track.station_distances[seg]
	for k in 2:
		for attempt in 30:
			var d0 := s0 + Track.SEGMENT_LENGTH * (0.22 + 0.42 * k) + _rng.randf_range(-80.0, 80.0)
			var side := -1.0 if _rng.randf() < 0.5 else 1.0
			if absf(d0 - track.gate_distance(seg)) < 140.0 or track.is_bridge_at(d0):
				continue
			var start := _world(d0, side * 14.0)
			if start.y < Track.WATER_LEVEL + 1.0:
				continue
			# the goal: a high point that is still a fair climb
			var goal := Vector3.INF
			var best := -INF
			for c in 40:
				var p := _world(d0 + _rng.randf_range(-320.0, 320.0), side * _rng.randf_range(180.0, 620.0))
				var rise := p.y - start.y
				if p.y < Track.WATER_LEVEL + 3.0 or rise > 240.0 or land.in_zone(p.x, p.z, 20.0):
					continue
				var score := rise - 0.05 * Vector2(p.x - start.x, p.z - start.z).length()
				if score > best:
					best = score
					goal = p
			if goal == Vector3.INF or best < 12.0:
				continue
			var path := _walk(start, goal)
			if path.size() < 8:
				continue
			trails.append(path)
			var top := path[path.size() - 1]
			viewpoints.append(top)
			resource_spots.append(top + Vector3(2.5, 0.0, 1.5))
			# something across the trail half way up: a fallen log, or (in the woods) a dead tree waiting to fall
			var mid := path.size() / 2
			var a := path[mid]
			var dir := (path[mid + 1] - path[mid - 1])
			dir.y = 0.0
			dir = dir.normalized()
			var across := Basis.looking_at(dir.cross(Vector3.UP), Vector3.UP)
			if land.forest_at(d0) > 0.55 and k == 0:
				var base := a + dir.cross(Vector3.UP) * 3.2
				base.y = _ground(base.x, base.z)
				falling_trees.append({"pivot": Transform3D(Basis.looking_at(-dir.cross(Vector3.UP), Vector3.UP), base),
					"trigger": a - dir * 14.0, "fallen": false})
			else:
				logs.append(Transform3D(across.rotated(Vector3.UP, PI * 0.5), a))
			break


## A walkable line from `from` towards `to`: 10 m steps, each picking the heading closest to the goal whose
## slope stays climbable (zig-zagging up steep ground), stopping at the goal or after 120 steps.
func _walk(from: Vector3, to: Vector3) -> PackedVector3Array:
	var path := PackedVector3Array([from])
	var p := from
	var step := 10.0
	for i in 120:
		var want := Vector2(to.x - p.x, to.z - p.z)
		if want.length() < step:
			path.append(to)
			break
		var heading := want.angle()
		var chosen := Vector3.INF
		for off: float in [0.0, 0.35, -0.35, 0.7, -0.7, 1.05, -1.05, 1.4, -1.4]:
			var a := heading + off * (1.0 if i % 2 == 0 else -1.0)
			var q := Vector3(p.x + cos(a) * step, 0.0, p.z + sin(a) * step)
			q.y = _ground(q.x, q.z)
			var grade := absf(q.y - p.y) / step
			if grade < 0.55 and q.y > Track.WATER_LEVEL + 0.8 and absf(terrain.track_coords(q.x, q.z).y) < Landscape.R_OUT - OUT_WARN:
				chosen = q
				break
		if chosen == Vector3.INF:
			break
		p = chosen
		path.append(p)
	return path


const HAZARDS_BY_THEME := {
	"Forest hills": ["thorns", "thorns", "thorns", "thorns", "mud", "mud", "mud", "thorns"],
	"River valley": ["mud", "mud", "mud", "mud", "quicksand", "thorns", "thorns", "geyser"],
	"Mountain pass": ["ice", "ice", "ice", "ice", "ice", "geyser", "geyser", "geyser"],
	"The lake": ["geyser", "geyser", "mud", "mud", "thorns", "thorns", "ice"],
	"The coast": ["quicksand", "quicksand", "quicksand", "quicksand", "thorns", "thorns", "mud"],
}
const HAZARD_RADIUS := {"mud": [6.0, 10.0], "quicksand": [5.0, 8.0], "ice": [9.0, 15.0], "thorns": [2.5, 4.0], "geyser": [2.4, 2.4]}


func _plan_hazards(seg: int) -> void:
	var s0 := track.station_distances[seg]
	var kinds: Array = HAZARDS_BY_THEME.get(_theme(seg), [])
	var count := 0
	for kind: String in kinds:
		for attempt in 30:
			var d := s0 + _rng.randf_range(80.0, Track.SEGMENT_LENGTH - 80.0)
			# some close to the track (you meet them on the way to a key), most out in the land
			var u := (-1.0 if _rng.randf() < 0.5 else 1.0) * (_rng.randf_range(26.0, 90.0) if attempt % 3 == 0 else _rng.randf_range(40.0, 380.0))
			var p := _world(d, u)
			var r: Array = HAZARD_RADIUS[kind]
			var radius := _rng.randf_range(float(r[0]), float(r[1]))
			if not _clear_of_track_things(d, u, p, radius):
				continue
			if absf(u) < radius + 18.0:
				continue
			if _slope(p) > (0.35 if kind == "thorns" else 0.18):
				continue
			if p.y < Track.WATER_LEVEL + 0.6:
				continue
			if kind == "quicksand" and p.y > Track.WATER_LEVEL + 6.0 and attempt < 20:
				continue
			if kind == "ice" and p.y < land.snow_line_at(d) - 60.0 and attempt < 20:
				continue
			if _near_hazard(p, radius + 12.0) or _near_trail(p, radius + 4.0):
				continue
			hazards.append({"kind": kind, "pos": p, "radius": radius, "name": "Hazard_%d_%d" % [seg, count]})
			count += 1
			break


func _near_hazard(p: Vector3, dist: float) -> bool:
	for h in hazards:
		if Vector2((h.pos as Vector3).x - p.x, (h.pos as Vector3).z - p.z).length() < dist + float(h.radius):
			return true
	return false


func _near_trail(p: Vector3, dist: float) -> bool:
	for path in trails:
		for q in path:
			if Vector2(q.x - p.x, q.z - p.z).length() < dist:
				return true
	return false


func _plan_caves(seg: int) -> void:
	var wanted := {"Forest hills": 1, "River valley": 2, "Mountain pass": 2, "The lake": 1, "The coast": 1}
	var n: int = wanted.get(_theme(seg), 0)
	var s0 := track.station_distances[seg]
	var made := 0
	for attempt in 120:
		if made >= n:
			break
		var d := s0 + _rng.randf_range(100.0, Track.SEGMENT_LENGTH - 100.0)
		var u := (-1.0 if _rng.randf() < 0.5 else 1.0) * _rng.randf_range(70.0, 420.0)
		var p := _world(d, u)
		if not _clear_of_track_things(d, u, p, 25.0) or p.y < Track.WATER_LEVEL + 2.0:
			continue
		# a flat floor at least 20 m across
		var ok := true
		for k in 8:
			var a := k * TAU / 8.0
			var q := Vector3(p.x + cos(a) * 11.0, 0.0, p.z + sin(a) * 11.0)
			if absf(_ground(q.x, q.z) - p.y) > 3.2:
				ok = false
				break
		if not ok or _near_hazard(p, 25.0) or _near_trail(p, 14.0):
			continue
		# the mouth faces the track
		var to_track := track.point_at(d) - p
		to_track.y = 0.0
		var t := Transform3D(Basis.looking_at(-to_track.normalized(), Vector3.UP), p - Vector3.UP * 0.6)
		caves.append(t)
		resource_spots.append(p + t.basis.z * -1.0 + Vector3.UP * 0.3)
		hazards.append({"kind": "cave", "pos": p, "radius": 13.0, "name": ""})  # keeps trees out
		made += 1


func _plan_rockfalls(seg: int) -> void:
	var theme := _theme(seg)
	if theme == "Forest hills":
		return
	var s0 := track.station_distances[seg]
	var made := 0
	for attempt in 120:
		if made >= 2:
			break
		var d := s0 + _rng.randf_range(150.0, Track.SEGMENT_LENGTH - 150.0)
		if absf(d - track.gate_distance(seg)) < 160.0 or track.is_bridge_at(d) or track.station_at(d) != -1:
			continue
		var side := -1.0 if _rng.randf() < 0.5 else 1.0
		var top := _world(d, side * _rng.randf_range(60.0, 140.0))
		var ty := track.point_at(d).y
		if top.y - ty < 14.0 or land.in_zone(top.x, top.z, 20.0):
			continue
		var stops: Array[Vector3] = []
		for k in 3:
			stops.append(track.ground_point(d + (k - 1) * 7.0 + _rng.randf_range(-2.0, 2.0), side * _rng.randf_range(7.0, 11.0)))
		rockfalls.append({"d": d, "start": top, "stops": stops, "done": false})
		made += 1


## Rope bridges over each river gorge, and waterfalls down its steepest walls.
func _plan_rivers() -> void:
	for r: Vector4 in land._rivers:
		for side: float in [-1.0, 1.0]:
			# a rope bridge 160-320 m from the track
			for attempt in 8:
				var u := side * _rng.randf_range(160.0, 320.0)
				var dc := r.x + r.w * sin(u / 150.0 + r.z) * smoothstep(40.0, 260.0, absf(u))
				var a := _bank(dc, u, -1.0, r.y)
				var b := _bank(dc, u, 1.0, r.y)
				if a == Vector3.INF or b == Vector3.INF:
					continue
				var span := a.distance_to(b)
				if span < 20.0 or span > 130.0 or absf(a.y - b.y) > 12.0:
					continue
				bridges.append([a, b])
				break
			# a waterfall further out, where the gorge wall is high
			for attempt in 8:
				var u := side * _rng.randf_range(330.0, 700.0)
				var dc := r.x + r.w * sin(u / 150.0 + r.z) * smoothstep(40.0, 260.0, absf(u))
				var dir := -1.0 if _rng.randf() < 0.5 else 1.0
				var bottom := _world(dc + dir * (r.y * 0.9), u)
				var top := Vector3.INF
				for k in range(4, 40):
					var q := _world(dc + dir * (r.y * 0.9 + k * 3.0), u)
					if q.y - Track.WATER_LEVEL > 22.0:
						top = q
						break
				if top == Vector3.INF or bottom.y > Track.WATER_LEVEL + 1.0:
					continue
				bottom.y = Track.WATER_LEVEL
				waterfalls.append([top, bottom])
				break


## The first dry point on one bank of the river at sideways offset u (searching away from its centre dc).
func _bank(dc: float, u: float, dir: float, half: float) -> Vector3:
	for k in range(0, 40):
		var p := _world(dc + dir * (half * 0.8 + k * 3.0), u)
		if p.y > Track.WATER_LEVEL + 4.0:
			return p
	return Vector3.INF


## Marks trails (biome alpha 128: drawn as a dirt path) and keep-clear spots (64) so nothing grows there.
func _stamp() -> void:
	for path in trails:
		for k in path.size() - 1:
			_stamp_segment(path[k], path[k + 1], 3.2, 128)
	for h in hazards:
		_stamp_disc(h.pos, float(h.radius) + 2.0, 64)
	for c in caves:
		_stamp_disc(c.origin, 14.0, 64)
	for b in bridges:
		_stamp_disc(b[0], 6.0, 64)
		_stamp_disc(b[1], 6.0, 64)
	for v in viewpoints:
		_stamp_disc(v, 6.0, 64)
	for rf in rockfalls:
		for s: Vector3 in rf.stops:
			_stamp_segment(rf.start, s, 4.0, 64)
	for t in logs:
		_stamp_disc(t.origin, 4.0, 128)
	for ft in falling_trees:
		_stamp_disc((ft.pivot as Transform3D).origin, 3.0, 64)


func _stamp_segment(a: Vector3, b: Vector3, width: float, value: int) -> void:
	var lo := Vector2(minf(a.x, b.x), minf(a.z, b.z)) - Vector2(width, width)
	var hi := Vector2(maxf(a.x, b.x), maxf(a.z, b.z)) + Vector2(width, width)
	var a2 := Vector2(a.x, a.z)
	var b2 := Vector2(b.x, b.z)
	for j in range(int(floorf((lo.y - terrain.origin.y) / Terrain.CELL)), int(ceilf((hi.y - terrain.origin.y) / Terrain.CELL)) + 1):
		for i in range(int(floorf((lo.x - terrain.origin.x) / Terrain.CELL)), int(ceilf((hi.x - terrain.origin.x) / Terrain.CELL)) + 1):
			if i < 0 or j < 0 or i >= terrain.gw or j >= terrain.gh:
				continue
			var p := Vector2(terrain.origin.x + i * Terrain.CELL, terrain.origin.y + j * Terrain.CELL)
			if Geometry2D.get_closest_point_to_segment(p, a2, b2).distance_to(p) <= width:
				terrain.mark(i, j, value)


func _stamp_disc(c: Vector3, radius: float, value: int) -> void:
	_stamp_segment(c, c, radius, value)


# --- Building ---------------------------------------------------------------------------

func spawn() -> void:
	name = "Features"
	for k in viewpoints.size():
		_build_viewpoint(k, viewpoints[k])
	for k in hazards.size():
		if hazards[k].kind != "cave":
			_build_hazard(hazards[k])
	for k in caves.size():
		_build_cave(k, caves[k])
	for k in bridges.size():
		_build_bridge(k, bridges[k][0], bridges[k][1])
	if _visual:
		for k in waterfalls.size():
			_build_waterfall(k, waterfalls[k][0], waterfalls[k][1])
	for k in logs.size():
		_build_log(k, logs[k])
	for k in falling_trees.size():
		_build_falling_tree(k, falling_trees[k])
	for k in rockfalls.size():
		_build_rockfall(k, rockfalls[k])
	process_physics_priority = 100  # after the players moved


func _mesh_node(parent: Node, id: String, xform: Transform3D, shadows := true) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	if Terrain.has_nature(id):
		mi.mesh = Terrain.nature_mesh(id)
	else:
		var box := BoxMesh.new()
		box.size = Vector3(2, 1, 2)
		mi.mesh = box
	mi.transform = xform
	if not shadows:
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(mi)
	return mi


func _solid(parent: Node, size: Vector3, xform: Transform3D) -> StaticBody3D:
	var body := StaticBody3D.new()
	body.collision_layer = Build.LAYER_WORLD
	var cs := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = size
	cs.shape = box
	body.add_child(cs)
	body.transform = xform
	parent.add_child(body)
	return body


func _build_viewpoint(k: int, p: Vector3) -> void:
	var node := Node3D.new()
	node.name = "Viewpoint_%d" % k
	node.position = p
	add_child(node)
	# a cairn of stacked stones and a pole with a pennant
	for i in 4:
		var s := 1.4 - i * 0.28
		_mesh_node(node, "rock_small", Transform3D(Basis(Vector3.UP, i * 1.3).scaled(Vector3(s, s * 0.8, s)), Vector3(0, i * 0.42 * 1.0, 0)))
	Build.box(node, Vector3(0.08, 3.2, 0.08), Vector3(0.9, 1.6, 0.4), Color(0.4, 0.28, 0.16))
	var flag := Build.box(node, Vector3(0.03, 0.5, 0.8), Vector3(0.9, 2.9, 0.82), Color(0.9, 0.75, 0.15))
	flag.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF


func _build_hazard(h: Dictionary) -> void:
	var node := Node3D.new()
	node.name = h.name
	node.position = h.pos
	add_child(node)
	var r: float = h.radius
	match String(h.kind):
		"mud", "quicksand", "ice":
			var col: Color = {"mud": Color(0.2, 0.14, 0.08), "quicksand": Color(0.62, 0.52, 0.32), "ice": Color(0.72, 0.85, 0.95)}[h.kind]
			var mi := MeshInstance3D.new()
			mi.mesh = _patch_mesh(h.pos, r)
			var m := StandardMaterial3D.new()
			m.albedo_color = col
			m.roughness = 0.08 if h.kind == "ice" else (0.25 if h.kind == "mud" else 0.9)
			m.metallic_specular = 0.8 if h.kind != "quicksand" else 0.3
			mi.material_override = m
			mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			node.add_child(mi)
			if h.kind == "mud" and _visual:
				for k in 5:
					var a := k * 1.7
					var q := Vector3(cos(a) * r * 0.5, 0.0, sin(a) * r * 0.5)
					q.y = _ground(h.pos.x + q.x, h.pos.z + q.z) - h.pos.y + 0.03
					var bubble := Build.sphere(node, 0.12, q, Color(0.15, 0.1, 0.06))
					bubble.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		"thorns":
			var rng := RandomNumberGenerator.new()
			rng.seed = hash(h.name)
			var n := int(r * 1.3) + 2
			for k in n:
				var a := rng.randf() * TAU
				var dist := rng.randf_range(0.0, r * 0.8)
				var q := Vector3(cos(a) * dist, 0.0, sin(a) * dist)
				q.y = _ground(h.pos.x + q.x, h.pos.z + q.z) - h.pos.y - 0.1
				var s := rng.randf_range(0.8, 1.3)
				_mesh_node(node, "thorn_bush" if Terrain.has_nature("thorn_bush") else "bush",
					Transform3D(Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3(s, s, s)), q))
		"geyser":
			# a crusted vent with a hot pool; it erupts every GEYSER_PERIOD seconds
			var rim := MeshInstance3D.new()
			var cyl := CylinderMesh.new()
			cyl.top_radius = 1.6
			cyl.bottom_radius = 2.6
			cyl.height = 0.7
			cyl.radial_segments = 12
			rim.mesh = cyl
			rim.material_override = Build.material(Color(0.72, 0.62, 0.45))
			rim.position.y = 0.1
			node.add_child(rim)
			var pool := MeshInstance3D.new()
			var disc := CylinderMesh.new()
			disc.top_radius = 1.2
			disc.bottom_radius = 1.2
			disc.height = 0.05
			pool.mesh = disc
			var pm := StandardMaterial3D.new()
			pm.albedo_color = Color(0.3, 0.75, 0.8)
			pm.roughness = 0.05
			pm.emission_enabled = true
			pm.emission = Color(0.1, 0.35, 0.4)
			pool.material_override = pm
			pool.position.y = 0.46
			node.add_child(pool)
			var g := {"pos": h.pos, "phase": float(hash(h.name) % 1000) / 1000.0 * GEYSER_PERIOD, "jet": null, "steam": null}
			if _visual:
				g.jet = _particles(node, Color(0.92, 0.96, 1.0, 0.8), 0.35, 14.0, 160, 1.4, Vector3(0, 0.5, 0))
				g.steam = _particles(node, Color(0.95, 0.95, 0.95, 0.25), 1.2, 1.5, 24, 4.0, Vector3(0, 0.6, 0))
				(g.steam as CPUParticles3D).emitting = true
			_geysers.append(g)


## A low patch that hugs the ground (mud, quicksand, ice): rings of vertices just above the terrain.
func _patch_mesh(c: Vector3, r: float) -> Mesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var rings := 4
	var seg := 18
	var pts: Array[Vector3] = [Vector3(0, _ground(c.x, c.z) - c.y + 0.06, 0)]
	for ri in range(1, rings + 1):
		for k in seg:
			var a := k * TAU / seg
			var rr := r * float(ri) / rings * (1.0 + 0.12 * sin(a * 3.0 + c.x))
			var q := Vector3(cos(a) * rr, 0.0, sin(a) * rr)
			q.y = _ground(c.x + q.x, c.z + q.z) - c.y + (0.06 if ri < rings else 0.02)
			pts.append(q)
	for ri in rings:
		for k in seg:
			var k2 := (k + 1) % seg
			if ri == 0:
				for v in [0, 1 + k2, 1 + k]:
					st.add_vertex(pts[v])
			else:
				var a0 := 1 + (ri - 1) * seg + k
				var a1 := 1 + (ri - 1) * seg + k2
				var b0 := 1 + ri * seg + k
				var b1 := 1 + ri * seg + k2
				for v in [a0, a1, b0, a1, b1, b0]:
					st.add_vertex(pts[v])
	st.generate_normals()
	return st.commit()


func _particles(parent: Node3D, color: Color, size: float, speed: float, amount: int, life: float, pos: Vector3) -> CPUParticles3D:
	var p := CPUParticles3D.new()
	p.amount = amount
	p.lifetime = life
	p.emitting = false
	p.position = pos
	p.direction = Vector3.UP
	p.spread = 8.0
	p.initial_velocity_min = speed * 0.7
	p.initial_velocity_max = speed
	p.gravity = Vector3(0, -6.0, 0)
	p.scale_amount_min = size * 0.6
	p.scale_amount_max = size
	var quad := QuadMesh.new()
	quad.size = Vector2(1, 1)
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	m.albedo_color = color
	m.albedo_texture = GateKey._radial_texture()
	quad.material = m
	p.mesh = quad
	parent.add_child(p)
	return p


func _build_cave(k: int, t: Transform3D) -> void:
	var node := Node3D.new()
	node.name = "Cave_%d" % k
	add_child(node)
	node.transform = t
	var mi := _mesh_node(node, "cave", Transform3D.IDENTITY)
	# the shell is solid; its floor is the ground
	var body := StaticBody3D.new()
	body.collision_layer = Build.LAYER_WORLD
	var cs := CollisionShape3D.new()
	cs.shape = mi.mesh.create_trimesh_shape()
	body.add_child(cs)
	node.add_child(body)
	# a lantern inside, so the mouth glows a little
	var lamp := OmniLight3D.new()
	lamp.light_color = Color(1.0, 0.7, 0.35)
	lamp.omni_range = 9.0
	lamp.light_energy = 1.3
	lamp.position = Vector3(0, 2.5, 1.5)
	node.add_child(lamp)
	Build.box(node, Vector3(0.25, 0.35, 0.25), Vector3(0, 0.75, 1.5), Color(0.9, 0.6, 0.2))


func _build_bridge(k: int, a: Vector3, b: Vector3) -> void:
	var node := Node3D.new()
	node.name = "RopeBridge_%d" % k
	add_child(node)
	var span := a.distance_to(b)
	var flat := Vector3(b.x - a.x, 0.0, b.z - a.z).normalized()
	var side := flat.cross(Vector3.UP)
	var n := int(span / 0.9)
	var sag := minf(span * 0.06, 4.0)
	var planks: Array[Transform3D] = []
	var deck_pts: Array[Vector3] = []
	for i in n + 1:
		var f := float(i) / n
		var p := a.lerp(b, f) + Vector3.UP * (0.5 - sag * 4.0 * f * (1.0 - f))
		deck_pts.append(p)
	for i in n:
		var p0 := deck_pts[i]
		var p1 := deck_pts[i + 1]
		var dir := p1 - p0
		var basis := Basis.looking_at(dir, Vector3.UP)
		planks.append(Transform3D(basis, (p0 + p1) * 0.5))
		# walkable: a thin box per plank
		_solid(node, Vector3(1.6, 0.12, dir.length() + 0.05), Transform3D(basis, (p0 + p1) * 0.5 - Vector3.UP * 0.05))
	var plank := BoxMesh.new()
	plank.size = Vector3(1.6, 0.08, 0.75)
	plank.material = Build.material(Color(0.42, 0.3, 0.17))
	var rope := BoxMesh.new()
	rope.size = Vector3(0.05, 0.05, 1.0)
	rope.material = Build.material(Color(0.7, 0.58, 0.36))
	var ropes: Array[Transform3D] = []
	for s: float in [-1.0, 1.0]:
		for i in n:
			var p0 := deck_pts[i] + side * s * 0.85 + Vector3.UP * 1.0
			var p1 := deck_pts[i + 1] + side * s * 0.85 + Vector3.UP * 1.0
			ropes.append(Transform3D(Basis.looking_at(p1 - p0, Vector3.UP).scaled(Vector3(1, 1, (p1 - p0).length())), (p0 + p1) * 0.5))
			if i % 3 == 0:
				var q := deck_pts[i] + side * s * 0.85
				ropes.append(Transform3D(Basis.looking_at(Vector3.UP, flat).scaled(Vector3(1, 1, 1.0)), q + Vector3.UP * 0.5))
	_multimesh(node, plank, planks)
	_multimesh(node, rope, ropes)
	for end: Vector3 in [a, b]:
		for s: float in [-1.0, 1.0]:
			Build.box(node, Vector3(0.22, 1.8, 0.22), end + side * s * 0.95 + Vector3.UP * 0.7, Color(0.35, 0.24, 0.13))
	# side rails stop people walking off (low walls of rope)
	for s: float in [-1.0, 1.0]:
		var mid := (a + b) * 0.5 + side * s * 0.9 + Vector3.UP * (1.0 - sag)
		_solid(node, Vector3(0.1, 1.2, span), Transform3D(Basis.looking_at(b - a, Vector3.UP), mid))


func _multimesh(parent: Node, mesh: Mesh, list: Array[Transform3D]) -> void:
	if list.is_empty():
		return
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = mesh
	mm.instance_count = list.size()
	for i in list.size():
		mm.set_instance_transform(i, list[i])
	var mmi := MultiMeshInstance3D.new()
	mmi.multimesh = mm
	parent.add_child(mmi)


static var _fall_shader: Shader

func _build_waterfall(k: int, top: Vector3, bottom: Vector3) -> void:
	var node := Node3D.new()
	node.name = "Waterfall_%d" % k
	add_child(node)
	# a ribbon of falling water from the lip down the face, a few metres out from the rock
	var out := Vector3(bottom.x - top.x, 0.0, bottom.z - top.z).normalized()
	var side := out.cross(Vector3.UP)
	var width := 7.0
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var rows := 12
	var pts: Array[Vector3] = []
	for i in rows + 1:
		var f := float(i) / rows
		var p := top.lerp(bottom, f)
		p.y = lerpf(top.y, bottom.y, f * f * 0.3 + f * 0.7)
		var g := _ground(p.x, p.z)
		p.y = maxf(p.y, g + 0.6) if i < rows else p.y
		pts.append(p + out * 1.2)
	for i in rows:
		var a0 := pts[i] - side * width * 0.5
		var a1 := pts[i] + side * width * 0.5
		var b0 := pts[i + 1] - side * width * 0.6
		var b1 := pts[i + 1] + side * width * 0.6
		var v0 := float(i) / rows
		var v1 := float(i + 1) / rows
		for vv in [[a0, Vector2(0, v0)], [a1, Vector2(1, v0)], [b0, Vector2(0, v1)], [a1, Vector2(1, v0)], [b1, Vector2(1, v1)], [b0, Vector2(0, v1)]]:
			st.set_uv(vv[1])
			st.add_vertex(vv[0])
	st.generate_normals()
	var mi := MeshInstance3D.new()
	mi.mesh = st.commit()
	if _fall_shader == null:
		_fall_shader = Shader.new()
		_fall_shader.code = """shader_type spatial;
render_mode blend_mix, cull_disabled, depth_draw_opaque, unshaded;
uniform sampler2D streaks : repeat_enable, filter_linear_mipmap;
void fragment() {
	float s = texture(streaks, vec2(UV.x * 2.0, UV.y * 1.5 - TIME * 1.3)).r;
	float s2 = texture(streaks, vec2(UV.x * 3.1 + 0.3, UV.y * 2.2 - TIME * 2.1)).r;
	float edge = smoothstep(0.0, 0.18, UV.x) * smoothstep(1.0, 0.82, UV.x);
	ALBEDO = mix(vec3(0.55, 0.7, 0.75), vec3(0.95, 0.98, 1.0), s * s2 * 1.6);
	ALPHA = clamp((0.35 + 0.6 * s * s2) * edge, 0.0, 0.92);
}
"""
	var m := ShaderMaterial.new()
	m.shader = _fall_shader
	m.set_shader_parameter("streaks", Terrain.patch_texture())
	mi.material_override = m
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	node.add_child(mi)
	var mist := _particles(node, Color(0.95, 0.97, 1.0, 0.35), 2.5, 2.0, 40, 3.0, pts[rows] + Vector3.UP * 0.5)
	mist.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
	mist.emission_box_extents = Vector3(width * 0.5, 0.3, width * 0.5)
	mist.emitting = true


func _build_log(k: int, t: Transform3D) -> void:
	var node := Node3D.new()
	node.name = "TrailLog_%d" % k
	add_child(node)
	var p := t.origin
	p.y = _ground(p.x, p.z) - 0.1
	node.transform = Transform3D(t.basis, p)
	_mesh_node(node, "log", Transform3D.IDENTITY)
	_solid(node, Vector3(5.2, 0.7, 0.75), Transform3D(Basis(), Vector3(0, 0.36, 0)))


func _build_falling_tree(k: int, ft: Dictionary) -> void:
	var pivot := Node3D.new()
	pivot.name = "FallingTree_%d" % k
	add_child(pivot)
	pivot.transform = ft.pivot
	_mesh_node(pivot, "dead_tree", Transform3D(Basis().scaled(Vector3.ONE * 1.25), Vector3.ZERO))
	_tree_nodes.append(pivot)


func _build_rockfall(k: int, rf: Dictionary) -> void:
	var rocks: Array = []
	for i in (rf.stops as Array).size():
		var mi := _mesh_node(self, "boulder", Transform3D(Basis().scaled(Vector3.ONE * 0.9), rf.start + Vector3(i * 2.0, 1.0, 0)))
		mi.name = "Rockfall_%d_%d" % [k, i]
		rocks.append(mi)
	_rock_nodes.append(rocks)


# --- Runtime --------------------------------------------------------------------------------

func _physics_process(delta: float) -> void:
	_time += delta
	_hint_cd = maxf(_hint_cd - delta, 0.0)
	_update_geysers()
	_update_rockfalls(delta)
	for p in get_tree().get_nodes_in_group("player"):
		var player := p as Player
		if player == null or not player.is_local() or not player.is_physics_processing():
			continue
		_affect(player, delta)


func _update_geysers() -> void:
	for g in _geysers:
		var t := fmod(_time + float(g.phase), GEYSER_PERIOD)
		var on := t > GEYSER_PERIOD - GEYSER_BURST
		g.active = on
		if g.jet:
			(g.jet as CPUParticles3D).emitting = on


## Each hazard the player stands in: mud and quicksand hold you back, ice keeps you sliding, thorns hurt,
## an erupting geyser throws you up. Too far from the line: a warning, then back to the train.
func _affect(player: Player, delta: float) -> void:
	var id := player.get_instance_id()
	var pos := player.global_position
	if not _state.has(id):
		_state[id] = {"last": pos, "slide": Vector3.ZERO, "hurt": 0.0, "warned": false}
	var st: Dictionary = _state[id]
	var last: Vector3 = st.last
	var moved := Vector3(pos.x - last.x, 0.0, pos.z - last.z)
	if moved.length() > 3.0:
		moved = Vector3.ZERO  # teleported (respawn, train ride)
	var on_ice := false
	for h in hazards:
		var hp: Vector3 = h.pos
		var r: float = h.radius
		if absf(pos.x - hp.x) > r or absf(pos.z - hp.z) > r:
			continue
		if Vector2(pos.x - hp.x, pos.z - hp.z).length() > r or absf(pos.y - hp.y) > 4.0:
			continue
		match String(h.kind):
			"mud", "quicksand":
				var hold := MUD_SLOW if h.kind == "mud" else 0.75
				player.move_and_collide(-moved * hold)
				if _hint_cd <= 0.0:
					Game.say("Stuck in the %s! Wade out slowly" % ("mud" if h.kind == "mud" else "quicksand"))
					_hint_cd = 8.0
			"ice":
				on_ice = true
			"thorns":
				st.hurt = float(st.hurt) + delta
				if float(st.hurt) >= 0.5:
					st.hurt = 0.0
					Net.request(player, &"take_damage", [THORN_DAMAGE])
					if _hint_cd <= 0.0:
						Game.say("Ouch, thorns!")
						_hint_cd = 6.0
	for g in _geysers:
		var gp: Vector3 = g.pos
		if g.get("active", false) and Vector2(pos.x - gp.x, pos.z - gp.z).length() < 2.4 and absf(pos.y - gp.y) < 3.0:
			player.velocity.y = GEYSER_LAUNCH
			if _hint_cd <= 0.0:
				Game.say("Whoa, a geyser!")
				_hint_cd = 6.0
	# ice: keep part of your speed, slowly turning towards where you want to go
	var v := moved / maxf(delta, 0.001)
	var slide: Vector3 = st.slide
	if on_ice:
		slide = slide.lerp(v, clampf(ICE_GRIP * delta, 0.0, 1.0))
		player.move_and_collide((slide - v) * delta)
		if _hint_cd <= 0.0 and slide.length() > 2.0:
			Game.say("Slippery ice!")
			_hint_cd = 8.0
	else:
		slide = v
	st.slide = slide
	_check_bounds(player, st)
	st.last = player.global_position


func _check_bounds(player: Player, st: Dictionary) -> void:
	var pos := player.global_position
	var du := terrain.track_coords(pos.x, pos.z)
	var past_end := du.x < -Terrain.EXTEND + 60.0 or du.x > track.get_length() + Terrain.EXTEND - 60.0
	var edge := Landscape.R_OUT - absf(du.y)
	if absf(du.y) >= Terrain.UNSET * 0.5 or edge < OUT_LIMIT or (past_end and absf(du.y) < Landscape.R_OUT):
		Game.say("Too far from the line: back to the train")
		player.respawn_on_train()
		st.warned = false
	elif edge < OUT_WARN:
		if not st.warned:
			Game.say("You are wandering too far from the railway. Turn back!")
			st.warned = true
	else:
		st.warned = false


func _update_rockfalls(delta: float) -> void:
	var train := Game.train
	for k in rockfalls.size():
		var rf := rockfalls[k]
		var rocks: Array = _rock_nodes[k]
		if not rf.done:
			if train and train.track == track and train.distance > float(rf.d) - 70.0 and train.distance < float(rf.d) + 20.0:
				rf.done = true
				rf.t = 0.0
				if _visual:
					Game.say("Rockfall!")
			continue
		var t: float = rf.get("t", 9.0)
		if t >= 4.0:
			continue
		t += delta
		rf.t = t
		for i in rocks.size():
			var mi: MeshInstance3D = rocks[i]
			var f := clampf((t - i * 0.35) / 3.0, 0.0, 1.0)
			var stop: Vector3 = rf.stops[i]
			var start: Vector3 = rf.start + Vector3(i * 2.0, 1.0, 0)
			var p := start.lerp(stop, f * f * (3.0 - 2.0 * f))
			p.y = maxf(_ground(p.x, p.z), lerpf(start.y, stop.y, f)) + 0.2 + absf(sin(f * 9.0)) * 1.2 * (1.0 - f)
			mi.global_position = p
			mi.rotate_x(delta * 6.0 * (1.0 - f))
			# anyone in the way gets hit (each peer checks its own player)
			if f > 0.0 and f < 1.0:
				for pl in get_tree().get_nodes_in_group("player"):
					var player := pl as Player
					if player and player.is_local() and player.global_position.distance_to(p) < 2.2:
						Net.request(player, &"take_damage", [15.0])
						player.velocity.y = 6.0
			if f >= 1.0 and not mi.has_meta("solid"):
				mi.set_meta("solid", true)
				_solid(self, Vector3(2.6, 1.8, 2.6), Transform3D(Basis(), p + Vector3.UP * 0.6))
	# falling trees: the first player who walks up brings it down across the trail
	for k in falling_trees.size():
		var ft := falling_trees[k]
		var pivot := _tree_nodes[k]
		if not ft.fallen:
			for pl in get_tree().get_nodes_in_group("player"):
				if (pl as Node3D).global_position.distance_to(ft.trigger) < 12.0:
					ft.fallen = true
					ft.t = 0.0
					Game.say("Timber! A dead tree came down")
			continue
		var t: float = ft.get("t", 9.0)
		if t >= 2.0:
			continue
		t += delta
		ft.t = t
		var f := clampf(t / 1.6, 0.0, 1.0)
		pivot.transform = (ft.pivot as Transform3D) * Transform3D(Basis(Vector3.RIGHT, -PI * 0.47 * f * f), Vector3.ZERO)
		if f >= 1.0:
			_solid(pivot, Vector3(0.9, 7.5, 0.9), Transform3D(Basis(), Vector3(0, 3.6, 0)))
