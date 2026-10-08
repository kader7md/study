class_name Terrain
extends Node3D
## Landscape built as a wide ribbon that follows the track: rows of vertices every ROW_STEP metres,
## spread sideways from -U_MAX to +U_MAX. Heights come from Track.ground_height (hills, embankment,
## rivers, lake, coast). Coloured by height and slope: sand near water, grass, rock on steep ground,
## snow up high. Plus a water plane, backdrop mountains and trees.

const ROW_STEP := 4.0
const ROWS_PER_CHUNK := 25
const EXTEND := 220.0  # ribbon continues this far before the start and after the end
## Sideways vertex offsets (denser near the track).
const U_OFFSETS := [0.0, 2.0, 4.0, 6.0, 9.0, 12.0, 16.0, 21.0, 27.0, 35.0, 45.0, 58.0, 74.0, 94.0, 118.0, 145.0, 175.0]

const GRASS := Color(0.36, 0.56, 0.24)
const GRASS_DARK := Color(0.28, 0.46, 0.2)
const DIRT := Color(0.5, 0.38, 0.24)
const SAND := Color(0.84, 0.76, 0.52)
const ROCK := Color(0.47, 0.45, 0.43)
const SNOW := Color(0.93, 0.95, 0.97)

var track: Track
## Tree and boulder positions near the track: anchor points for the come-along.
var anchor_points: Array[Vector3] = []
var _us: Array[float] = []


func build(t: Track, rng: RandomNumberGenerator) -> void:
	track = t
	for k in range(U_OFFSETS.size() - 1, 0, -1):
		_us.append(-float(U_OFFSETS[k]))
	for k in U_OFFSETS:
		_us.append(float(k))
	var mat := StandardMaterial3D.new()
	mat.vertex_color_use_as_albedo = true
	mat.roughness = 0.95
	var d := -EXTEND
	var end := track.get_length() + EXTEND
	while d < end:
		_build_chunk(d, minf(d + ROWS_PER_CHUNK * ROW_STEP, end), mat)
		d += ROWS_PER_CHUNK * ROW_STEP
	_build_water()
	_build_mountains(rng)
	_build_trees(rng)


func _build_chunk(d0: float, d1: float, mat: Material) -> void:
	var rows: Array[PackedVector3Array] = []
	var d := d0
	while d <= d1 + 0.01:
		var row := PackedVector3Array()
		var p := track.point_at(d)
		var right := track.flat_right(d)
		for u in _us:
			var v := p + right * u
			v.y = track.ground_height(d, u)
			row.append(v)
		rows.append(row)
		d += ROW_STEP
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var cols := _us.size()
	for r in rows.size() - 1:
		for c in cols - 1:
			var a := rows[r][c]
			var b := rows[r][c + 1]
			var cc := rows[r + 1][c]
			var dd := rows[r + 1][c + 1]
			# Two triangles, wound so they face up (rows go forward, columns go right)
			for v in [a, cc, b, b, cc, dd]:
				st.set_color(_color_at(v, a, b, cc))
				st.add_vertex(v)
	st.generate_normals()
	var mesh := st.commit()
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = mat
	add_child(mi)
	var body := StaticBody3D.new()
	body.collision_layer = Build.LAYER_WORLD
	var cs := CollisionShape3D.new()
	cs.shape = mesh.create_trimesh_shape()
	body.add_child(cs)
	add_child(body)


func _color_at(v: Vector3, a: Vector3, b: Vector3, c: Vector3) -> Color:
	var n := (c - a).cross(b - a).normalized()
	var slope := 1.0 - absf(n.y)
	var h := v.y
	if h < Track.WATER_LEVEL + 1.2:
		return SAND
	if h > 70.0:
		return SNOW
	if slope > 0.45:
		return ROCK
	var noise := fmod(absf(v.x * 0.37 + v.z * 0.23), 1.0)
	var col := GRASS.lerp(GRASS_DARK, noise * 0.6)
	if slope > 0.25:
		col = col.lerp(DIRT, 0.6)
	return col


func _build_water() -> void:
	var lo := Vector2(INF, INF)
	var hi := Vector2(-INF, -INF)
	var d := 0.0
	while d <= track.get_length():
		var p := track.point_at(d)
		lo = Vector2(minf(lo.x, p.x), minf(lo.y, p.z))
		hi = Vector2(maxf(hi.x, p.x), maxf(hi.y, p.z))
		d += 50.0
	var size := hi - lo + Vector2(800, 800)
	var mi := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = size
	mi.mesh = plane
	var water := StandardMaterial3D.new()
	water.albedo_color = Color(0.2, 0.5, 0.75, 0.78)
	water.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	water.roughness = 0.1
	water.metallic = 0.2
	mi.material_override = water
	mi.position = Vector3((lo.x + hi.x) * 0.5, Track.WATER_LEVEL, (lo.y + hi.y) * 0.5)
	add_child(mi)


## Mesh of a Blender nature model (assets/models/nature/<id>.glb), for MultiMesh scattering.
static func nature_mesh(id: String) -> Mesh:
	var scene: Node = load("res://assets/models/nature/%s.glb" % id).instantiate()
	var mi: MeshInstance3D = scene.find_children("*", "MeshInstance3D", true, false)[0]
	var mesh := mi.mesh
	scene.free()
	return mesh


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


func _place(p: Vector3, scale: float, rng: RandomNumberGenerator, squash := 1.0) -> Transform3D:
	var basis := Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3(scale, scale * squash, scale))
	return Transform3D(basis, p)


## Big rocky mountains beyond the edge of the ribbon (the boulder model scaled up), tall in the mountain pass.
func _build_mountains(rng: RandomNumberGenerator) -> void:
	var mesh := nature_mesh("boulder")
	var list: Array[Transform3D] = []
	var d := 0.0
	while d < track.get_length():
		var theme := track.theme_at(d)
		var walls: float = theme.walls
		for side in [-1.0, 1.0]:
			if theme.has("lake") and side == float(theme.lake[2]):
				continue
			var height := walls * rng.randf_range(0.8, 1.7) + rng.randf_range(15.0, 35.0)
			var radius := height * rng.randf_range(0.8, 1.2)
			var u: float = side * (190.0 + radius * 0.8 + rng.randf_range(0.0, 80.0))
			var base: Vector3 = track.point_at(d) + track.flat_right(d) * u
			base.y = track.natural_height(d, signf(u) * 175.0) - height * 0.15
			# boulder.glb is about 3.8 m wide and 2.4 m high
			var basis := Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3(radius / 1.9, height / 2.4, radius / 1.9))
			list.append(Transform3D(basis, base))
		d += rng.randf_range(70.0, 120.0)
	_scatter(mesh, list)


## Trees, bushes, rocks and cliffs from the Blender nature models, chosen per landscape theme.
func _build_trees(rng: RandomNumberGenerator) -> void:
	var ids := ["pine", "pine_snow", "oak", "birch", "dead_tree", "bush", "rock_small", "boulder", "cliff"]
	var lists := {}
	for id in ids:
		var empty: Array[Transform3D] = []
		lists[id] = empty
	var count := int(track.get_length() / 2.5)
	var reserved := track.reserved_spots()  # gates, signal posts and keys stay in the open
	for i in count:
		var d := rng.randf_range(0.0, track.get_length())
		var u := (1.0 if rng.randf() < 0.5 else -1.0) * rng.randf_range(9.0, 165.0)
		var p := track.ground_point(d, u)
		if p.y < Track.WATER_LEVEL + 1.0 or (track.station_at(d) != -1 and absf(u) < 20.0):
			continue
		if absf(u) < 20.0 and reserved.any(func(r: Vector3): return Vector2(r.x - p.x, r.z - p.z).length() < 7.0):
			continue
		var theme: String = track.theme_at(d).name
		var r := rng.randf()
		var id := "pine"
		if p.y > 45.0:
			id = "pine_snow" if r < 0.8 else "dead_tree"
		elif theme == "Mountain pass":
			id = "pine" if r < 0.6 else ("pine_snow" if r < 0.8 else ("dead_tree" if r < 0.9 else "boulder"))
		elif theme == "River valley" or theme == "The lake":
			id = "oak" if r < 0.35 else ("birch" if r < 0.6 else ("pine" if r < 0.8 else ("bush" if r < 0.93 else "rock_small")))
		elif theme == "The coast":
			id = "pine" if r < 0.4 else ("bush" if r < 0.7 else ("rock_small" if r < 0.85 else "boulder"))
		else:
			id = "pine" if r < 0.55 else ("oak" if r < 0.7 else ("bush" if r < 0.85 else ("rock_small" if r < 0.95 else "boulder")))
		var sc := rng.randf_range(0.75, 1.35)
		if id == "boulder":
			sc = rng.randf_range(0.5, 1.6)
		lists[id].append(_place(p - Vector3.UP * 0.1, sc, rng))
	# cliffs along the mountain pass and the coast, away from the track
	var d2 := 0.0
	while d2 < track.get_length():
		var theme2: String = track.theme_at(d2).name
		if theme2 == "Mountain pass" or theme2 == "The coast" or theme2 == "River valley":
			var u2 := (1.0 if rng.randf() < 0.5 else -1.0) * rng.randf_range(35.0, 120.0)
			var p2 := track.ground_point(d2, u2)
			if p2.y > Track.WATER_LEVEL + 0.5:
				lists["cliff"].append(_place(p2 - Vector3.UP * 1.0, rng.randf_range(1.0, 2.2), rng, rng.randf_range(0.8, 1.6)))
		d2 += rng.randf_range(25.0, 60.0)
	for id in ["pine", "pine_snow", "oak", "birch", "dead_tree", "boulder"]:
		for t: Transform3D in lists[id]:
			anchor_points.append(t.origin)
	for id in ids:
		_scatter(nature_mesh(id), lists[id], id != "bush" and id != "rock_small")
