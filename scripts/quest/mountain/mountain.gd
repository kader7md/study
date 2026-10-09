class_name MountainMap
extends QuestMap
## "The Mountain" (GDD 7, quest map for the mountain pass gate): a ~305 m island peak to climb as a crew, from a beach
## camp through forest, cliff bands, a jungle gorge and snowfields to the summit, where the gate key waits.
## Shape and points of interest: MountainLayout. Built here: the heightmap ground (mesh chunks with the
## mountain_terrain shader + one HeightMapShape3D), the sea, Blender rocks with colliders (a chimney, an overhang,
## a stone pillar, cliff faces), two rope bridges, campfires, rope anchors, food and rope pickups, falling-ice
## hazards up high, icy patches, scattered trees and rocks, and the cairn with the key.
## Node names are fixed (Camp_<i>, Anchor_<n>, Rope_<n>, Snack_<n>, Coconut_<n>, Stew_<n>, SummitKey, LeaveSign), so
## requests from clients find the same nodes on the host.

const L := preload("res://scripts/quest/mountain/mountain_layout.gd")
const START_ROPES := 2
const CAMP_NAMES := ["the beach camp", "camp 1 (the cliffs)", "camp 2 (the gorge)", "camp 3 (the jungle top)", "camp 4 (the snowfield)"]
const KILL_Y := -1.5
const CHUNK := 43
const SEED := 6060
## [riser, angle] of the solid cliff faces (Blender cliff_wall.glb).
const CLIFF_FACES := [[0, -0.045], [3, 0.0], [7, 0.03], [12, 0.0], [14, -0.04], [1, 0.62 + 0.09], [4, 1.2]]
## Falling ice: [riser, angle, phase s].
const ROCKFALLS := [[13, 0.045, 0.0], [15, 0.0, 3.0], [17, 0.025, 5.5], [14, 2.88, 2.0], [18, 3.94, 6.5], [12, 2.7, 4.0]]
## Pickups: [name, kind, amount, camp index or -1, ring-space radius, angle] (camp items are placed around the fire).
const PICKUPS := [
	["Rope_0", "rope", 1, 0, 0.0, 0.0], ["Snack_0", "snack", 60, 0, 0.0, 0.0], ["Snack_1", "snack", 60, 0, 0.0, 0.0],
	["Coconut_0", "coconut", 45, -1, 392.0, 0.12], ["Coconut_1", "coconut", 45, -1, 395.0, -0.1],
	["Rope_1", "rope", 2, 1, 0.0, 0.0], ["Snack_2", "snack", 60, 1, 0.0, 0.0], ["Stew_0", "stew", 50, 1, 0.0, 0.0],
	["Rope_2", "rope", 2, 2, 0.0, 0.0], ["Snack_3", "snack", 60, 2, 0.0, 0.0], ["Snack_4", "snack", 60, 2, 0.0, 0.0],
	["Stew_1", "stew", 50, 2, 0.0, 0.0],
	["Rope_3", "rope", 2, 3, 0.0, 0.0], ["Snack_5", "snack", 60, 3, 0.0, 0.0], ["Coconut_2", "coconut", 45, 3, 0.0, 0.0],
	["Stew_2", "stew", 50, 3, 0.0, 0.0],
	["Rope_4", "rope", 2, 4, 0.0, 0.0], ["Snack_6", "snack", 60, 4, 0.0, 0.0], ["Snack_7", "snack", 60, 4, 0.0, 0.0],
	["Stew_3", "stew", 50, 4, 0.0, 0.0],
	["Snack_8", "snack", 60, -1, 237.0, 0.02], ["Snack_9", "snack", 60, -1, 154.0, 0.04],
	["Snack_10", "snack", 60, -1, 98.0, 0.03], ["Coconut_3", "coconut", 45, -1, 165.0, -0.03],
	["Snack_11", "snack", 60, -1, 263.0, 0.66], ["Snack_12", "snack", 60, -1, 145.0, 2.0], ["Snack_13", "snack", 60, -1, 55.0, 3.8],
]

var heights := PackedFloat32Array()
var grid := 0
var camps: Array[Campfire] = []
var anchors: Array[RopeAnchor] = []
var pickups: Array[QuestPickup] = []
var key: SummitKey
var build_ms := 0
var _chimneys: Array[Dictionary] = []
var _ice := FastNoiseLite.new()
var _rng := RandomNumberGenerator.new()


func build() -> void:
	var t0 := Time.get_ticks_msec()
	title = "The Mountain"
	_rng.seed = SEED
	_ice.seed = 515
	_ice.frequency = 0.045
	var steps := [_build_ground, _build_sea, _build_rocks, _build_gorge, _build_vegetation, _build_camps, _build_anchors,
		_build_pickups, _build_summit, _build_hazards]
	var times := []
	for f: Callable in steps:
		var t := Time.get_ticks_msec()
		f.call()
		times.append("%s %d" % [f.get_method().trim_prefix("_build_"), Time.get_ticks_msec() - t])
	print("[quest] build steps (ms): ", ", ".join(times))
	build_ms = Time.get_ticks_msec() - t0
	print("[quest] The Mountain built in %d ms" % build_ms)


func intro_text() -> String:
	return "THE MOUNTAIN: the gate key waits on the summit. Hold %s on steep rock to climb (watch your stamina), drop rope ladders from the anchors, campfires are checkpoints." % Settings.key_hint("climb")


# --- Ground --------------------------------------------------------------------------------------

func _build_ground() -> void:
	grid = int(L.HALF * 2.0 / L.CELL) + 1
	heights.resize(grid * grid)
	L.wob(0.0)  # builds the shared tables before the worker threads read them
	# rows in parallel (pure, read-only maths): each row writes its own slice
	var rows: Array[PackedFloat32Array] = []
	rows.resize(grid)
	var task := WorkerThreadPool.add_group_task(func(j: int) -> void:
		var row := PackedFloat32Array()
		row.resize(grid)
		var z := -L.HALF + j * L.CELL
		for i in grid:
			row[i] = L.height(-L.HALF + i * L.CELL, z)
		rows[j] = row, grid, -1, true, "mountain heights")
	WorkerThreadPool.wait_for_group_task_completion(task)
	for j in grid:
		for i in grid:
			heights[j * grid + i] = rows[j][i]
	# collision: one heightmap (scaled uniformly by the cell size)
	var hm := HeightMapShape3D.new()
	hm.map_width = grid
	hm.map_depth = grid
	var data := PackedFloat32Array()
	data.resize(heights.size())
	for i in heights.size():
		data[i] = heights[i] / L.CELL
	hm.map_data = data
	var body := StaticBody3D.new()
	body.name = "Ground"
	body.collision_layer = Build.LAYER_WORLD
	var cs := CollisionShape3D.new()
	cs.shape = hm
	cs.scale = Vector3.ONE * L.CELL
	body.add_child(cs)
	add_child(body)
	# visual chunks
	var mat := ShaderMaterial.new()
	mat.shader = load("res://scenes/quest/mountain_terrain.gdshader")
	mat.set_shader_parameter("rock_tex", load("res://assets/textures/quest/rock_tile.png"))
	mat.set_shader_parameter("ground_tex", load("res://assets/textures/quest/ground_tile.png"))
	mat.set_shader_parameter("snow_tex", load("res://assets/textures/quest/snow_tile.png"))
	var cells := grid - 1
	var j0 := 0
	while j0 < cells:
		var i0 := 0
		while i0 < cells:
			_build_chunk(i0, j0, mini(i0 + CHUNK, cells), mini(j0 + CHUNK, cells), mat)
			i0 += CHUNK
		j0 += CHUNK


func _h(i: int, j: int) -> float:
	return heights[clampi(j, 0, grid - 1) * grid + clampi(i, 0, grid - 1)]


func _build_chunk(i0: int, j0: int, i1: int, j1: int, mat: Material) -> void:
	var w := i1 - i0 + 1
	var verts := PackedVector3Array()
	var normals := PackedVector3Array()
	var colors := PackedColorArray()
	var idx := PackedInt32Array()
	for j in range(j0, j1 + 1):
		for i in range(i0, i1 + 1):
			var p := Vector3(-L.HALF + i * L.CELL, _h(i, j), -L.HALF + j * L.CELL)
			var n := Vector3(_h(i - 1, j) - _h(i + 1, j), 2.0 * L.CELL, _h(i, j - 1) - _h(i, j + 1)).normalized()
			verts.append(p)
			normals.append(n)
			colors.append(_color_at(p, n))
	for j in j1 - j0:
		for i in w - 1:
			var a := j * w + i
			var b := a + 1
			var c := a + w
			var d := c + 1
			idx.append_array([a, b, c, b, d, c])
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_COLOR] = colors
	arrays[Mesh.ARRAY_INDEX] = idx
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	mesh.surface_set_material(0, mat)
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	add_child(mi)


## Biome colour of the ground (rgb) and snow cover (a).
func _color_at(p: Vector3, n: Vector3) -> Color:
	var y := p.y
	var r := Vector2(p.x, p.z).length()
	var var_n := _ice.get_noise_2d(p.x * 2.3, p.z * 2.3) * 0.5 + 0.5
	if y < 3.8 and r > 330.0:
		return Color(0.82, 0.74, 0.55, 0.0).lerp(Color(0.7, 0.62, 0.45, 0.0), clampf(1.0 - y / 2.0, 0.0, 1.0) * 0.6)
	var col: Color
	if y < L.ROCK_Y - 1.0:
		col = Color(0.3, 0.44, 0.19).lerp(Color(0.2, 0.33, 0.14), var_n)
		if y < 7.0:
			col = col.lerp(Color(0.62, 0.58, 0.4), clampf((7.0 - y) / 3.5, 0.0, 1.0))
	elif y < L.JUNGLE_Y - 1.0:
		col = Color(0.47, 0.44, 0.3).lerp(Color(0.36, 0.4, 0.22), var_n)
	elif y < L.SNOW_Y - 4.0:
		col = Color(0.15, 0.36, 0.1).lerp(Color(0.24, 0.42, 0.13), var_n)
	else:
		col = Color(0.55, 0.55, 0.55)
	var snow := smoothstep(L.SNOW_Y - 8.0, L.SNOW_Y + 2.0, y)
	if snow > 0.0 and is_icy(p):
		col = Color(0.62, 0.78, 0.95)
		snow *= 0.35
	if n.y < 0.5:
		snow *= 0.6
	return Color(col.r, col.g, col.b, snow)


## Icy patches on the flat snow (slippery: see Climber).
func is_icy(p: Vector3) -> bool:
	return p.y > L.SNOW_Y + 3.0 and _ice.get_noise_2d(p.x, p.z) > 0.32


func _build_sea() -> void:
	var mi := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(3200, 3200)
	mi.mesh = plane
	var water := StandardMaterial3D.new()
	water.albedo_color = Color(0.13, 0.42, 0.62, 0.86)
	water.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	water.roughness = 0.08
	water.metallic = 0.25
	mi.material_override = water
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.position.y = 0.0
	add_child(mi)


# --- Rocks with colliders -------------------------------------------------------------------------

## Basis at angle th: x along the cliff (to the right seen from outside), z outwards.
static func frame(th: float) -> Basis:
	return Basis(Vector3(cos(th), 0.0, -sin(th)), Vector3.UP, L.outward(th))


func _riser_heights(k: int, th: float) -> Vector2:
	var b := L.boundary(k, th)
	var foot := L.at(b + L.RISER_W + 0.5, th).y
	var top := L.surface(k + 1, b, th)
	return Vector2(foot, top)


func _build_rocks() -> void:
	# cliff faces with real collision on the routes
	var i := 0
	for cf: Array in CLIFF_FACES:
		var k: int = cf[0]
		var th: float = cf[1]
		var hts := _riser_heights(k, th)
		var b := L.boundary(k, th)
		var pos := L.at(b + 1.2, th)
		pos.y = hts.x - 0.6
		var sy := (hts.y - hts.x + 0.9) / 14.0
		QuestProps.solid(self, "cliff_wall", Transform3D(frame(th).scaled(Vector3(1.0, sy, 1.0)), pos), "Cliff_%d" % i)
		i += 1
	# the chimney: two rock fins standing out from riser 2, 1.6 m apart; climbing between them is much easier
	var ck: int = L.CHIMNEY[0]
	var cth: float = L.CHIMNEY[1]
	var ch := _riser_heights(ck, cth)
	var cb := L.boundary(ck, cth)
	var f := frame(cth)
	var center := L.at(cb + 2.2, cth)
	center.y = ch.x - 0.8
	for s in [-1.0, 1.0]:
		var p: Vector3 = center + f.x * s * 1.4
		QuestProps.solid(self, "chimney_wall", Transform3D(f.scaled(Vector3(1.0, (ch.y - ch.x + 2.0) / 15.0, 1.0)), p), "Chimney_%d" % (0 if s < 0 else 1))
	_chimneys.append({"center": center, "x": f.x, "z": f.z, "y0": ch.x - 1.0, "y1": ch.y + 0.5})
	var sign := Build.label(self, "CHIMNEY\nbrace between the walls: climbing costs less", center + f.z * 3.0 + Vector3.UP * 2.6, 34)
	sign.modulate = Color(0.9, 0.95, 1.0)
	# the overhang: a rock roof sticking out over riser 8 on the direct line
	var ok: int = L.OVERHANG[0]
	var oth: float = L.OVERHANG[1]
	var oh := _riser_heights(ok, oth)
	var opos := L.at(L.boundary(ok, oth) - 0.4, oth)
	opos.y = oh.y + 0.15
	QuestProps.solid(self, "overhang", Transform3D(frame(oth).scaled(Vector3(1.0, 1.0, 1.15)), opos), "Overhang")
	# rock clusters along the cliff feet (decoration, no collision)
	var list: Array[Transform3D] = []
	var snowy: Array[Transform3D] = []
	for k in L.RINGS.size() - 1:
		var count := int(14 + (L.RINGS[k][0] as float) * 0.08)
		for c in count:
			var th := _rng.randf() * TAU
			var p := L.at(L.boundary(k, th) + L.RISER_W + _rng.randf_range(0.6, 2.0), th, -0.3)
			if absf(wrapf(th, -PI, PI)) < 0.06:
				continue
			var tr := Transform3D(Basis(Vector3.UP, _rng.randf() * TAU).scaled(Vector3.ONE * _rng.randf_range(0.5, 1.1)), p)
			if p.y > L.SNOW_Y:
				snowy.append(tr)
			else:
				list.append(tr)
	_scatter(QuestProps.mesh("rock_cluster"), list)
	_scatter(QuestProps.mesh("rock_snow"), snowy)


func _build_gorge() -> void:
	# a stone pillar in the gorge and two rope bridges: rim -> pillar -> inner ledge
	var pillar := L.at(L.PILLAR_RP, 0.0)
	var top_y: float = float(L.RINGS[6][1]) + 0.25
	var base_y := pillar.y - 1.5
	var s := Vector3(0.62, (top_y - base_y) / 28.6, 0.62)
	QuestProps.solid(self, "rock_pillar", Transform3D(Basis.IDENTITY.scaled(s), Vector3(pillar.x, base_y, pillar.z)), "Pillar")
	var rim := L.at(L.GORGE_OUT + 1.2, 0.0, 0.05)
	var inner := L.at(L.GORGE_IN - 1.2, 0.0, 0.05)
	var pa := Vector3(pillar.x, top_y + 0.05, pillar.z) + L.outward(0.0) * 1.3
	var pb := Vector3(pillar.x, top_y + 0.05, pillar.z) - L.outward(0.0) * 1.3
	var b1 := RopeBridge.new()
	b1.name = "Bridge_0"
	add_child(b1)
	b1.build(rim, pa)
	var b2 := RopeBridge.new()
	b2.name = "Bridge_1"
	add_child(b2)
	b2.build(pb, inner)
	var sign := Build.label(self, "THE GORGE\nrope bridges, or walk round by the east end", rim + L.outward(0.0) * 2.0 + Vector3.UP * 2.8, 34)
	sign.modulate = Color(1.0, 0.9, 0.7)


# --- Vegetation ------------------------------------------------------------------------------------

func _scatter(mesh: Mesh, transforms: Array[Transform3D], shadows := true) -> void:
	if transforms.is_empty():
		return
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = mesh
	mm.instance_count = transforms.size()
	for i in transforms.size():
		mm.set_instance_transform(i, transforms[i])
	var mmi := MultiMeshInstance3D.new()
	mmi.multimesh = mm
	if not shadows:
		mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mmi)


## A random flat spot between ring-space radii lo..hi: its position, or INF when the ground there is too steep.
func _flat_spot(lo: float, hi: float, max_grad := 0.45) -> Vector3:
	var th := _rng.randf() * TAU
	var rp := _rng.randf_range(lo, hi)
	var p := L.at(rp, th)
	var gx := L.height(p.x + 1.0, p.z) - L.height(p.x - 1.0, p.z)
	var gz := L.height(p.x, p.z + 1.0) - L.height(p.x, p.z - 1.0)
	if Vector2(gx, gz).length() * 0.5 > max_grad:
		return Vector3.INF
	# keep the camps and the direct line's landing spots clear
	for c in L.camp_count():
		if Vector2(p.x, p.z).distance_to(Vector2(L.camp_position(c).x, L.camp_position(c).z)) < 9.0:
			return Vector3.INF
	return p


func _plant(ids: Dictionary, lo: float, hi: float, count: int, y_lo := -INF, y_hi := INF, max_grad := 0.45) -> void:
	var lists := {}
	var keys := ids.keys()
	for i in count:
		var p := _flat_spot(lo, hi, max_grad)
		if p == Vector3.INF or p.y < y_lo or p.y > y_hi:
			continue
		var id: String = keys[_rng.randi() % keys.size()]
		var s: float = float(ids[id]) * _rng.randf_range(0.75, 1.25)
		if not lists.has(id):
			var arr: Array[Transform3D] = []
			lists[id] = arr
		(lists[id] as Array[Transform3D]).append(Transform3D(Basis(Vector3.UP, _rng.randf() * TAU).scaled(Vector3.ONE * s), p - Vector3.UP * 0.15))
	for id: String in lists:
		var mesh: Mesh = QuestProps.mesh(id) if id in ["palm", "jungle_tree", "fern", "rock_cluster", "rock_snow"] else Terrain.nature_mesh(id)
		_scatter(mesh, lists[id], not id in ["fern", "bush", "rock_small"])


func _build_vegetation() -> void:
	_plant({"palm": 1.0}, L.BEACH_R - 2.0, L.SEA_R - 8.0, 120, 1.0)
	_plant({"pine": 1.0, "oak": 1.1, "birch": 1.0, "bush": 1.3, "boulder": 0.9}, L.FOREST_R + 8.0, L.BEACH_R - 4.0, 700, 3.5)
	_plant({"pine": 0.9, "dead_tree": 1.0, "bush": 1.0, "rock_small": 1.5}, 214.0, 266.0, 260, -INF, L.JUNGLE_Y - 1.0, 0.25)
	_plant({"jungle_tree": 1.0, "fern": 1.6, "bush": 1.4}, 124.0, 212.0, 900, L.JUNGLE_Y - 0.5, L.SNOW_Y - 6.0, 0.25)
	_plant({"pine_snow": 0.9, "rock_snow": 0.7}, 50.0, 123.0, 220, L.SNOW_Y - 6.0, INF, 0.25)


# --- Camps, anchors, pickups, summit -----------------------------------------------------------------

func _build_camps() -> void:
	for i in L.camp_count():
		var c := Campfire.new()
		c.name = "Camp_%d" % i
		c.index = i
		c.title = "START" if i == 0 else "CAMP %d" % i
		c.position = L.camp_position(i)
		add_child(c)
		camps.append(c)
	# base camp: tents and the way back
	var beach := L.camp_position(0)
	var f := frame(0.0)
	for k in 3:
		var p := beach + f.x * (k - 1) * 4.5 + f.z * 6.0
		p.y = L.height(p.x, p.z)
		var tent := QuestProps.instance("tent")
		tent.transform = Transform3D(Basis(Vector3.UP, PI + (k - 1) * 0.3), p)
		add_child(tent)
	var sign := LeaveSign.new()
	sign.name = "LeaveSign"
	var sp := beach + f.z * 9.0 + f.x * 6.0
	sp.y = L.height(sp.x, sp.z)
	sign.position = sp
	add_child(sign)
	var title_label := Build.label(self, "THE MOUNTAIN\nthe key waits on the summit", beach - f.z * 5.0 + Vector3.UP * 4.0, 72)
	title_label.modulate = Color(1.0, 0.9, 0.7)


func _build_anchors() -> void:
	for i in L.ANCHORS.size():
		var k: int = L.ANCHORS[i][0]
		var th: float = L.ANCHORS[i][1]
		var a := RopeAnchor.new()
		a.name = "Anchor_%d" % i
		var b := L.boundary(k, th)
		var top_y := L.surface(k + 1, b, th)
		a.position = L.riser_top(k, th, 0.9)
		a.out = L.outward(th)
		a.top = L.at(b + 0.35, th)
		a.top.y = top_y + 0.35
		a.bottom = L.at(b + L.RISER_W + 1.4, th, 0.0)
		a.exit = L.riser_top(k, th, 1.8) + Vector3.UP * 0.1
		a.rotation.y = th
		add_child(a)
		anchors.append(a)


func _build_pickups() -> void:
	var per_camp := {}
	for e: Array in PICKUPS:
		var p := QuestPickup.new()
		p.name = e[0]
		p.kind = e[1]
		p.amount = float(e[2])
		var c: int = e[3]
		if c >= 0:
			var n: int = per_camp.get(c, 0)
			per_camp[c] = n + 1
			var f := frame(0.0)
			var at_p := L.camp_position(c) + f.x * (2.6 + n * 1.1) - f.z * 1.6
			at_p.y = L.height(at_p.x, at_p.z) + 0.05
			p.position = at_p
		else:
			p.position = L.at(float(e[4]), float(e[5]), 0.05)
		add_child(p)
		pickups.append(p)


func _build_summit() -> void:
	var top := L.summit()
	var cairn := QuestProps.instance("cairn")
	cairn.position = top + Vector3(2.5, -0.2, -1.0)
	add_child(cairn)
	key = SummitKey.new()
	key.name = "SummitKey"
	key.segment = quest.segment if quest else 2
	key.position = top + Vector3(0, 0.1, 0)
	add_child(key)
	var l := Build.label(self, "SUMMIT  %d m" % int(top.y), top + Vector3(2.5, 6.5, -1.0), 64)
	l.modulate = Color(1.0, 0.95, 0.8)


func _build_hazards() -> void:
	for i in ROCKFALLS.size():
		var k: int = ROCKFALLS[i][0]
		var th: float = ROCKFALLS[i][1]
		var r := Rockfall.new()
		r.name = "Rockfall_%d" % i
		r.phase = float(ROCKFALLS[i][2])
		add_child(r)
		r.top = to_global(L.riser_top(k, th, 0.1) + Vector3.UP * 0.3)
		r.bottom = to_global(L.riser_foot(k, th, 1.5))


func key_node() -> Node:
	return key


# --- QuestMap -------------------------------------------------------------------------------------

func respawn_transform(c: int, index: int) -> Transform3D:
	c = clampi(c, 0, L.camp_count() - 1)
	var fire := L.camp_position(c)
	var a := PI + (index - 2) * 0.55   # fan out on the inner side of the fire, looking at it
	var f := frame(0.0)
	var dir := (f.z * cos(a) + f.x * sin(a)).normalized()
	var p := fire + dir * 2.6
	p.y = L.height(p.x, p.z) + 0.3
	var look := Basis.looking_at(Vector3(fire.x - p.x, 0.0, fire.z - p.z).normalized() if c > 0 else -f.z, Vector3.UP)
	return global_transform * Transform3D(look, p)


func camp_at(p: Vector3) -> int:
	var th := atan2(p.x, p.z)
	var rp := Vector2(p.x, p.z).length() + L.wob(th)
	for i in range(L.camp_count() - 1, 0, -1):
		var k: int = L.CAMP_RINGS[i]
		if p.y >= float(L.RINGS[k][1]) - 1.0 and rp <= L.ring_outer(k, th) + 0.5:
			return i
	return 0


func camp_name(c: int) -> String:
	return CAMP_NAMES[clampi(c, 0, CAMP_NAMES.size() - 1)]


func apply_state(q: QuestManager) -> void:
	for c in camps:
		c.set_lit(c.index <= q.camp)
	for a in anchors:
		a.set_placed(String(a.name) in q.placed)
	for p in pickups:
		p.set_taken(String(p.name) in q.taken)
	if key:
		key.set_taken(q.won)


func objective(q: QuestManager) -> String:
	if q.won:
		return "The key is yours! Heading back to the train..."
	match q.camp:
		0:
			return "Climb The Mountain: up through the forest to camp 1 (the cliffs)"
		1:
			return "Climb the cliff bands to camp 2 (the gorge). Ropes on the anchors help the crew"
		2:
			return "Cross the gorge (rope bridges) and climb the jungle ledges to camp 3"
		3:
			return "Up into the snow: warm up at campfires, mind the falling ice. Camp 4 is next"
	return "The summit is close: climb the last walls and take the KEY"


func drain_factor(p: Vector3) -> float:
	for c in _chimneys:
		var d: Vector3 = p - (c.center as Vector3)
		if absf(d.dot(c.x)) < 1.0 and absf(d.dot(c.z)) < 2.8 and p.y > float(c.y0) and p.y < float(c.y1):
			return Climber.CHIMNEY_FACTOR
	return 1.0


func cold_rate(p: Vector3) -> float:
	if p.y < L.SNOW_Y - 2.0:
		return -0.08
	for c in camps:
		if c.index <= quest.camp and p.distance_to(c.position) < Campfire.WARM_RADIUS:
			return -0.25
	return 0.012


func ice_at(p: Vector3) -> bool:
	return is_icy(p)


func is_out(p: Vector3) -> bool:
	return p.y < KILL_Y or Vector2(p.x, p.z).length() > L.HALF + 40.0
