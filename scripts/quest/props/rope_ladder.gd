class_name RopeLadder
extends Node3D
## A rope ladder hanging from a RopeAnchor (group "quest_ladder"): two ropes and wooden rungs from `top` down to
## `bottom` (global). The Climber finds it with grab_distance() and climbs it without stamina.

const RUNG_STEP := 0.4

var bottom := Vector3.ZERO
var top := Vector3.ZERO
var offset := Vector3.ZERO   # where the player's feet are relative to the rope line
var exit := Vector3.ZERO


func setup(b: Vector3, t: Vector3, out: Vector3, ex: Vector3) -> void:
	add_to_group("quest_ladder")
	top_level = true
	global_transform = Transform3D.IDENTITY
	bottom = b
	top = t
	exit = ex
	offset = out * 0.6 + Vector3.DOWN * 0.4
	var axis := t - b
	var side := axis.cross(out).normalized()
	var rope := Color(0.6, 0.47, 0.28)
	for s in [-0.28, 0.28]:
		_rod(b + side * s + out * 0.12, t + side * s + out * 0.12, 0.025, rope)
	var n := int(axis.length() / RUNG_STEP)
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	var box := BoxMesh.new()
	box.size = Vector3(0.62, 0.05, 0.08)
	box.material = Build.material(Color(0.42, 0.28, 0.15))
	mm.mesh = box
	mm.instance_count = n
	var up := axis.normalized()
	var basis := Basis(side, up, side.cross(up)).orthonormalized()
	for i in n:
		mm.set_instance_transform(i, Transform3D(basis, b + axis * (float(i) + 0.5) / n + out * 0.12))
	var mmi := MultiMeshInstance3D.new()
	mmi.multimesh = mm
	add_child(mmi)


func _rod(a: Vector3, b: Vector3, r: float, c: Color) -> void:
	var mi := MeshInstance3D.new()
	var cyl := CylinderMesh.new()
	cyl.top_radius = r
	cyl.bottom_radius = r
	cyl.height = a.distance_to(b)
	cyl.radial_segments = 6
	mi.mesh = cyl
	mi.material_override = Build.material(c)
	var d := (b - a).normalized()
	var x := d.cross(Vector3.FORWARD if absf(d.dot(Vector3.FORWARD)) < 0.9 else Vector3.RIGHT).normalized()
	mi.transform = Transform3D(Basis(x, d, x.cross(d)), (a + b) * 0.5)
	add_child(mi)


## How far a player's feet at `p` are from the climbing line (INF above / below it).
func grab_distance(p: Vector3) -> float:
	var a := bottom + offset
	var axis := top - bottom
	var t := (p - a).dot(axis) / axis.length_squared()
	if t < -0.15 or t > 1.05:
		return INF
	return p.distance_to(a + axis * clampf(t, 0.0, 1.0))
