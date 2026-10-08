class_name Mirror
extends Interactable
## A full-length wooden mirror (in the utility wagon). It really reflects: a camera mirrored behind the glass renders
## the world (including your own crew member, render layer 2) into a texture while you are close.
## [E] opens the CustomizeMenu on your own screen only (Player calls interact_local, nothing goes to the host).
## Local space: the glass faces +Z, centred at the origin; the bottom of the frame stands at y = -HEIGHT / 2.

const WIDTH := 0.78
const HEIGHT := 1.72
const RES := Vector2i(300, 660)
## Only render the reflection while the local player is this close (metres).
const NEAR := 9.0
## Render layer of the glass itself and of the first-person arms: the mirror camera skips both.
const HIDDEN_LAYER := 1 << 18

var _viewport: SubViewport
var _cam: Camera3D
var _glass: MeshInstance3D
var _notifier: VisibleOnScreenNotifier3D


## Builds a mirror on `parent` at `pos`, facing along `facing` (a horizontal direction in the parent's space).
static func create(parent: Node3D, pos: Vector3, facing: Vector3) -> Mirror:
	var m := Mirror.new()
	m.name = "Mirror"
	parent.add_child(m)
	m.position = pos
	m.rotation.y = atan2(facing.x, facing.z)
	return m


func _ready() -> void:
	Build.collider(self, Vector3(WIDTH + 0.16, HEIGHT + 0.16, 0.2), Vector3.ZERO)
	_build_frame()
	_build_reflection()


func _build_frame() -> void:
	var wood := Color("7a4b2a")
	var dark := Color("4e2e18")
	var t := 0.08
	Build.box(self, Vector3(WIDTH + 2 * t, t, 0.08), Vector3(0, HEIGHT / 2 + t / 2, -0.02), wood)
	Build.box(self, Vector3(WIDTH + 2 * t, t, 0.08), Vector3(0, -HEIGHT / 2 - t / 2, -0.02), wood)
	Build.box(self, Vector3(t, HEIGHT, 0.08), Vector3(WIDTH / 2 + t / 2, 0, -0.02), wood)
	Build.box(self, Vector3(t, HEIGHT, 0.08), Vector3(-WIDTH / 2 - t / 2, 0, -0.02), wood)
	Build.box(self, Vector3(WIDTH, HEIGHT, 0.03), Vector3(0, 0, -0.05), dark)  # back board
	# a little crest on top and two feet
	var crest := Build.sphere(self, 0.09, Vector3(0, HEIGHT / 2 + t + 0.03, -0.02), Color("c08a3e"))
	crest.scale = Vector3(1.3, 0.8, 0.5)
	for s in [-1.0, 1.0]:
		Build.box(self, Vector3(0.12, 0.06, 0.32), Vector3(s * (WIDTH / 2 + t / 2), -HEIGHT / 2 - t - 0.03, 0.04), dark)
	var sign := Build.label(self, "MIRROR  [E]", Vector3(0, HEIGHT / 2 + t + 0.16, 0.0), 30)
	sign.modulate = Color("ffe9b8")
	sign.outline_size = 10


func _build_reflection() -> void:
	_viewport = SubViewport.new()
	_viewport.size = RES
	_viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
	_viewport.msaa_3d = Viewport.MSAA_DISABLED
	add_child(_viewport)
	_cam = Camera3D.new()
	_cam.projection = Camera3D.PROJECTION_FRUSTUM
	_cam.keep_aspect = Camera3D.KEEP_HEIGHT
	_cam.far = 200.0
	_cam.cull_mask = 0xFFFFF & ~HIDDEN_LAYER  # everything, also the local player's own body (layer 2)
	_viewport.add_child(_cam)
	_glass = MeshInstance3D.new()
	var quad := QuadMesh.new()
	quad.size = Vector2(WIDTH, HEIGHT)
	_glass.mesh = quad
	_glass.position.z = 0.005
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.albedo_texture = _viewport.get_texture()
	m.albedo_color = Color(1.18, 1.22, 1.28)  # brighter (the reflection renders a bit dark) with a faint cool glass tint
	m.uv1_scale = Vector3(-1, 1, 1)           # a mirror flips left and right
	m.uv1_offset = Vector3(1, 0, 0)
	_glass.material_override = m
	_glass.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_glass.layers = HIDDEN_LAYER
	add_child(_glass)
	_notifier = VisibleOnScreenNotifier3D.new()
	_notifier.aabb = AABB(Vector3(-WIDTH / 2, -HEIGHT / 2, -0.05), Vector3(WIDTH, HEIGHT, 0.1))
	add_child(_notifier)


func get_prompt(_player: Node) -> String:
	return "Mirror: change your look  [E]"


## [E] from the host's own path: only the local player gets the menu.
func interact(player: Node) -> void:
	if player is Player and (player as Player).is_local():
		interact_local(player)


## Opens the customise menu on this screen.
func interact_local(_player: Node) -> CustomizeMenu:
	var existing := get_tree().root.find_child("CustomizeMenu", true, false)
	if existing:
		return existing as CustomizeMenu
	return CustomizeMenu.open_on(get_tree().current_scene if get_tree().current_scene else get_tree().root)


func _process(_delta: float) -> void:
	var viewer := get_viewport().get_camera_3d()
	var near := viewer != null and viewer.global_position.distance_to(global_position) < NEAR
	var on := near and _notifier.is_on_screen() and DisplayServer.get_name() != "headless"
	_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS if on else SubViewport.UPDATE_DISABLED
	if not on:
		return
	# the viewer's eye mirrored behind the glass; an off-centre frustum through the glass rectangle
	var eye := global_transform.affine_inverse() * viewer.global_position
	if eye.z < 0.05:
		return
	var s := global_transform.basis.get_scale()
	var mirrored := Vector3(eye.x, eye.y, -eye.z)
	_cam.global_transform = global_transform * Transform3D(Basis(Vector3.UP, PI), mirrored)
	_cam.near = eye.z * s.z
	_cam.size = HEIGHT * s.y
	_cam.frustum_offset = Vector2(eye.x, -eye.y) * s.y
