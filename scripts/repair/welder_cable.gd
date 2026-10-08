class_name WelderCable
extends MeshInstance3D
## The welder cable from the machine to the torch: ONE continuous tube mesh, rebuilt every frame
## along a sagging curve. Sags when there's slack, goes straight and turns red near its length limit.

const POINTS := 32       # points along the cable
const SIDES := 8         # tube roundness
const RADIUS := 0.025

var _mat := StandardMaterial3D.new()
var _imesh := ImmediateMesh.new()


func _ready() -> void:
	top_level = true
	mesh = _imesh
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_mat.albedo_color = Color(0.08, 0.08, 0.09)
	_mat.roughness = 0.6
	material_override = _mat


func update(from: Vector3, to: Vector3, max_length: float) -> void:
	global_transform = Transform3D.IDENTITY
	var dist := from.distance_to(to)
	var tension := clampf(dist / max_length, 0.0, 1.0)
	var sag := clampf((max_length - dist) * 0.12, 0.0, 2.5)
	_mat.albedo_color = Color(0.08, 0.08, 0.09).lerp(Color(0.85, 0.1, 0.08), smoothstep(0.85, 1.0, tension))

	# centre line of the cable: straight line plus a parabolic sag
	var pts := PackedVector3Array()
	for i in POINTS + 1:
		var t := float(i) / POINTS
		pts.append(from.lerp(to, t) + Vector3.DOWN * sag * 4.0 * t * (1.0 - t))

	# rings of vertices around the centre line, each facing along the cable
	var rings: Array[PackedVector3Array] = []
	var normals: Array[PackedVector3Array] = []
	var up_ref := Vector3.UP
	for i in pts.size():
		var tangent := (pts[mini(i + 1, pts.size() - 1)] - pts[maxi(i - 1, 0)]).normalized()
		if tangent.length_squared() < 0.0001:
			tangent = Vector3.FORWARD
		if absf(tangent.dot(up_ref)) > 0.95:
			up_ref = Vector3.RIGHT
		var side := tangent.cross(up_ref).normalized()
		var up := side.cross(tangent).normalized()
		var ring := PackedVector3Array()
		var nring := PackedVector3Array()
		for k in SIDES:
			var a := TAU * k / SIDES
			var n := side * cos(a) + up * sin(a)
			ring.append(pts[i] + n * RADIUS)
			nring.append(n)
		rings.append(ring)
		normals.append(nring)

	_imesh.clear_surfaces()
	_imesh.surface_begin(Mesh.PRIMITIVE_TRIANGLES)
	for i in rings.size() - 1:
		for k in SIDES:
			var k2 := (k + 1) % SIDES
			for idx in [[i, k], [i + 1, k], [i, k2], [i, k2], [i + 1, k], [i + 1, k2]]:
				_imesh.surface_set_normal(normals[idx[0]][idx[1]])
				_imesh.surface_add_vertex(rings[idx[0]][idx[1]])
	_imesh.surface_end()
