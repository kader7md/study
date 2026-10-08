class_name WelderCable
extends Node3D
## The welder cable drawn from the machine to the torch in the player's hand.
## Sags when there's slack, goes straight and turns red near its length limit.

const SEGMENTS := 18

var _segs: Array[MeshInstance3D] = []
var _mat := StandardMaterial3D.new()


func _ready() -> void:
	top_level = true
	_mat.albedo_color = Color(0.08, 0.08, 0.09)
	_mat.roughness = 0.7
	var mesh := CylinderMesh.new()
	mesh.top_radius = 0.025
	mesh.bottom_radius = 0.025
	mesh.height = 1.0
	mesh.radial_segments = 6
	mesh.material = _mat
	for i in SEGMENTS:
		var mi := MeshInstance3D.new()
		mi.mesh = mesh
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(mi)
		_segs.append(mi)


func update(from: Vector3, to: Vector3, max_length: float) -> void:
	var dist := from.distance_to(to)
	var tension := clampf(dist / max_length, 0.0, 1.0)
	var sag := clampf((max_length - dist) * 0.12, 0.0, 2.5)
	_mat.albedo_color = Color(0.08, 0.08, 0.09).lerp(Color(0.85, 0.1, 0.08), smoothstep(0.85, 1.0, tension))
	var prev := from
	for i in SEGMENTS:
		var t := float(i + 1) / SEGMENTS
		var p := from.lerp(to, t) + Vector3.DOWN * sag * 4.0 * t * (1.0 - t)
		var dir := p - prev
		var length := dir.length()
		if length > 0.001:
			var basis := Basis(Quaternion(Vector3.UP, dir / length)).scaled(Vector3(1.0, length, 1.0))
			_segs[i].global_transform = Transform3D(basis, (p + prev) * 0.5)
		prev = p
