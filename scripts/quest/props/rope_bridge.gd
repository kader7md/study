class_name RopeBridge
extends Node3D
## A sagging plank-and-rope bridge from `a` to `b` (local to this node's parent): Blender planks (bridge_plank.glb),
## handrail ropes on posts (no collision: you can fall off), and a walkable deck collider in short segments that
## follow the sag.

const PLANK_STEP := 0.42
const SAG := 0.45
const WIDTH := 1.8


func build(a: Vector3, b: Vector3) -> void:
	var span := b - a
	var fwd := Vector3(span.x, 0.0, span.z).normalized()
	var side := Vector3.UP.cross(fwd).normalized()
	var n := maxi(int(span.length() / PLANK_STEP), 2)
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = QuestProps.mesh("bridge_plank")
	mm.instance_count = n + 1
	var pts: Array[Vector3] = []
	for i in n + 1:
		var t := float(i) / n
		var p := a + span * t + Vector3.DOWN * SAG * 4.0 * t * (1.0 - t)
		pts.append(p)
		# the board's 2 m length (model X) across the bridge
		mm.set_instance_transform(i, Transform3D(Basis(side, Vector3.UP, side.cross(Vector3.UP)).scaled(Vector3(WIDTH / 2.0, 1, 1)), p))
	var mmi := MultiMeshInstance3D.new()
	mmi.multimesh = mm
	add_child(mmi)
	# deck collision, one box per few planks
	var body := StaticBody3D.new()
	body.name = "Deck"
	body.collision_layer = Build.LAYER_WORLD
	add_child(body)
	var seg := 3
	for i in range(0, n, seg):
		var p0 := pts[i]
		var p1 := pts[mini(i + seg, n)]
		var d := p1 - p0
		var cs := CollisionShape3D.new()
		var box := BoxShape3D.new()
		box.size = Vector3(WIDTH, 0.14, d.length() + 0.15)
		cs.shape = box
		var z := d.normalized()
		var x := Vector3.UP.cross(z).normalized()
		cs.transform = Transform3D(Basis(x, z.cross(x), z), (p0 + p1) * 0.5 + Vector3.DOWN * 0.04)
		body.add_child(cs)
	# posts and handrail ropes
	var rope := Color(0.6, 0.47, 0.28)
	for s in [-1.0, 1.0]:
		var pa: Vector3 = a + side * s * (WIDTH * 0.5 + 0.1)
		var pb: Vector3 = b + side * s * (WIDTH * 0.5 + 0.1)
		for p: Vector3 in [pa, pb]:
			Build.cylinder(self, 0.09, 1.5, p + Vector3.UP * 0.45, Color(0.32, 0.22, 0.13))
		var prev: Vector3 = pa + Vector3.UP * 1.1
		for i in range(1, 9):
			var t := i / 8.0
			var q: Vector3 = pa.lerp(pb, t) + Vector3.UP * 1.1 + Vector3.DOWN * SAG * 3.0 * t * (1.0 - t)
			_rod(prev, q, 0.03, rope)
			prev = q
		for i in range(2, n - 1, 5):
			var t := float(i) / n
			var top: Vector3 = pa.lerp(pb, t) + Vector3.UP * 1.1 + Vector3.DOWN * SAG * 3.0 * t * (1.0 - t)
			_rod(top, pts[i] + side * s * (WIDTH * 0.5), 0.015, rope)


func _rod(a: Vector3, b: Vector3, r: float, c: Color) -> void:
	var mi := MeshInstance3D.new()
	var cyl := CylinderMesh.new()
	cyl.top_radius = r
	cyl.bottom_radius = r
	cyl.height = a.distance_to(b)
	cyl.radial_segments = 6
	mi.mesh = cyl
	mi.material_override = Build.material(c)
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var d := (b - a).normalized()
	var x := d.cross(Vector3.FORWARD if absf(d.dot(Vector3.FORWARD)) < 0.9 else Vector3.RIGHT).normalized()
	mi.transform = Transform3D(Basis(x, d, x.cross(d)), (a + b) * 0.5)
	add_child(mi)
