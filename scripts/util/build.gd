class_name Build
## Grey-box helpers: simple meshes and colliders made in code.
## These get replaced by real models (Tripo3D → Blender → .glb) later.

const LAYER_WORLD := 1
const LAYER_PLAYER := 2
const LAYER_TRAIN := 4
const LAYER_INTERACT := 8
const LAYER_ENEMY := 16

static var _materials := {}


static func material(color: Color) -> StandardMaterial3D:
	if not _materials.has(color):
		var m := StandardMaterial3D.new()
		m.albedo_color = color
		m.roughness = 0.85
		if color.a < 1.0:
			m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		_materials[color] = m
	return _materials[color]


static func box(parent: Node, size: Vector3, pos: Vector3, color: Color) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var mesh := BoxMesh.new()
	mesh.size = size
	mi.mesh = mesh
	mi.material_override = material(color)
	mi.position = pos
	parent.add_child(mi)
	return mi


static func cylinder(parent: Node, radius: float, height: float, pos: Vector3, color: Color) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var mesh := CylinderMesh.new()
	mesh.top_radius = radius
	mesh.bottom_radius = radius
	mesh.height = height
	mi.mesh = mesh
	mi.material_override = material(color)
	mi.position = pos
	parent.add_child(mi)
	return mi


static func sphere(parent: Node, radius: float, pos: Vector3, color: Color) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var mesh := SphereMesh.new()
	mesh.radius = radius
	mesh.height = radius * 2.0
	mi.mesh = mesh
	mi.material_override = material(color)
	mi.position = pos
	parent.add_child(mi)
	return mi


## Adds a box collision shape to a physics body.
static func collider(body: CollisionObject3D, size: Vector3, pos: Vector3) -> CollisionShape3D:
	var cs := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = size
	cs.shape = shape
	cs.position = pos
	body.add_child(cs)
	return cs


## Solid box: mesh + StaticBody3D collider.
static func solid_box(parent: Node, size: Vector3, pos: Vector3, color: Color) -> StaticBody3D:
	var body := StaticBody3D.new()
	body.collision_layer = LAYER_WORLD
	body.position = pos
	parent.add_child(body)
	box(body, size, Vector3.ZERO, color)
	collider(body, size, Vector3.ZERO)
	return body


static func label(parent: Node, text: String, pos: Vector3, size := 64) -> Label3D:
	var l := Label3D.new()
	l.text = text
	l.position = pos
	l.font_size = size
	l.outline_size = 12
	l.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	l.no_depth_test = false
	parent.add_child(l)
	return l
