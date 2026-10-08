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


## Big mountains beyond the edge of the ribbon; tall and snowy in the mountain pass.
func _build_mountains(rng: RandomNumberGenerator) -> void:
	var rock := CylinderMesh.new()
	rock.top_radius = 0.0
	rock.bottom_radius = 1.0
	rock.height = 1.0
	rock.radial_segments = 7
	rock.material = Build.material(Color(0.33, 0.34, 0.31))
	var snow := CylinderMesh.new()
	snow.top_radius = 0.0
	snow.bottom_radius = 1.0
	snow.height = 1.0
	snow.radial_segments = 7
	snow.material = Build.material(SNOW)
	var rocks: Array[Transform3D] = []
	var caps: Array[Transform3D] = []
	var d := 0.0
	while d < track.get_length():
		var walls: float = track.theme_at(d).walls
		for side in [-1.0, 1.0]:
			if track.theme_at(d).has("lake") and side == float(track.theme_at(d).lake[2]):
				continue
			var height := walls * rng.randf_range(0.8, 1.7) + rng.randf_range(10.0, 30.0)
			var radius := height * rng.randf_range(0.7, 1.0)
			# keep the whole mountain beyond the ribbon so it never hangs over the track
			var u: float = side * (190.0 + radius * 0.9 + rng.randf_range(0.0, 80.0))
			var base: Vector3 = track.point_at(d) + track.flat_right(d) * u
			base.y = track.natural_height(d, signf(u) * 175.0) - 5.0
			rocks.append(Transform3D(Basis().scaled(Vector3(radius, height, radius)), base + Vector3.UP * height * 0.5))
			if height > 70.0:
				var cap_h := height * 0.3
				caps.append(Transform3D(Basis().scaled(Vector3(radius * 0.31, cap_h, radius * 0.31)),
					base + Vector3.UP * (height - cap_h * 0.5 + 0.2)))
		d += rng.randf_range(60.0, 110.0)
	for pair in [[rock, rocks], [snow, caps]]:
		var list: Array[Transform3D] = pair[1]
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.mesh = pair[0]
		mm.instance_count = list.size()
		for i in list.size():
			mm.set_instance_transform(i, list[i])
		var mmi := MultiMeshInstance3D.new()
		mmi.multimesh = mm
		add_child(mmi)


func _build_trees(rng: RandomNumberGenerator) -> void:
	var trunk := CylinderMesh.new()
	trunk.top_radius = 0.25
	trunk.bottom_radius = 0.32
	trunk.height = 2.0
	trunk.material = Build.material(Color(0.4, 0.27, 0.15))
	var crown := CylinderMesh.new()
	crown.top_radius = 0.0
	crown.bottom_radius = 1.9
	crown.height = 4.8
	crown.radial_segments = 8
	crown.material = Build.material(Color(0.18, 0.46, 0.24))
	var transforms: Array[Transform3D] = []
	var count := int(track.get_length() / 3.0)
	for i in count:
		var d := rng.randf_range(0.0, track.get_length())
		var u := (1.0 if rng.randf() < 0.5 else -1.0) * rng.randf_range(10.0, 160.0)
		var p := track.ground_point(d, u)
		if p.y < Track.WATER_LEVEL + 1.0 or p.y > 65.0 or track.station_at(d) != -1 and absf(u) < 20.0:
			continue
		var s := rng.randf_range(0.8, 1.7)
		transforms.append(Transform3D(Basis().scaled(Vector3.ONE * s), p))
	for part in [[trunk, 1.0], [crown, 4.3]]:
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.mesh = part[0]
		mm.instance_count = transforms.size()
		for i in transforms.size():
			var tr := transforms[i]
			mm.set_instance_transform(i, tr.translated(Vector3.UP * part[1] * tr.basis.get_scale().y))
		var mmi := MultiMeshInstance3D.new()
		mmi.multimesh = mm
		add_child(mmi)
