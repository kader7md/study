class_name QuestProps
## Models of the quest maps (made by blender/scripts/build_mountain.py, in assets/models/quest/).
## A missing model (not built yet) shows as a grey box instead of breaking the map.

const DIR := "res://assets/models/quest/%s.glb"

static var _scenes := {}
static var _meshes := {}
static var _shapes := {}


static func _scene(id: String) -> PackedScene:
	if not _scenes.has(id):
		var path := DIR % id
		_scenes[id] = load(path) if ResourceLoader.exists(path) else null
		if _scenes[id] == null:
			push_warning("missing quest model %s (run blender/scripts/build_mountain.py)" % id)
	return _scenes[id]


static func instance(id: String) -> Node3D:
	var scene := _scene(id)
	if scene == null:
		var n := Node3D.new()
		Build.box(n, Vector3(1, 1, 1), Vector3(0, 0.5, 0), Color(0.5, 0.48, 0.45))
		return n
	return scene.instantiate()


## The model's mesh (each quest model is one mesh), for MultiMesh scattering and colliders.
static func mesh(id: String) -> Mesh:
	if not _meshes.has(id):
		var scene := _scene(id)
		if scene == null:
			var box := BoxMesh.new()
			box.material = Build.material(Color(0.5, 0.48, 0.45))
			_meshes[id] = box
		else:
			var node := scene.instantiate()
			var mi: MeshInstance3D = node.find_children("*", "MeshInstance3D", true, false)[0]
			_meshes[id] = mi.mesh
			node.free()
	return _meshes[id]


## A solid copy of the model: mesh + trimesh collider (world layer) at `xform` under `parent`.
static func solid(parent: Node, id: String, xform: Transform3D, node_name := "") -> StaticBody3D:
	var body := StaticBody3D.new()
	body.collision_layer = Build.LAYER_WORLD
	if node_name != "":
		body.name = node_name
	body.transform = xform
	var mi := MeshInstance3D.new()
	mi.mesh = mesh(id)
	body.add_child(mi)
	if not _shapes.has(id):
		_shapes[id] = mesh(id).create_trimesh_shape()
	var cs := CollisionShape3D.new()
	cs.shape = _shapes[id]
	body.add_child(cs)
	parent.add_child(body)
	return body
