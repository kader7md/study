class_name Player
extends CharacterBody3D
## First-person player: walk, sprint, jump, ride the train, use things ([E]/[Q], hold [E]),
## hit enemies with the shovel (left mouse), freeze in the cold.
## Debug impostor (F2): keys 1-4 trigger sabotage; the meteor is aimed with the mouse (LMB fire, RMB cancel).

const WALK := 4.5
const SPRINT := 7.5
const JUMP := 5.5
const MOUSE_SENS := 0.0025
const REACH := 3.5
const AIM_RANGE := 400.0
const SHOVEL_DAMAGE := 15.0
const ATTACK_COOLDOWN := 0.5
const WARM_RADIUS := 7.0

var health := 100.0
var frost := 0.0
var downed := false
var camera: Camera3D
var focused: Interactable
var hold_progress := 0.0
var hold_needed := 0.0
var aiming_meteor := false

var _ray: RayCast3D
var _gravity: float = ProjectSettings.get_setting("physics/3d/default_gravity")
var _attack_cd := 0.0
var _aim_marker: MeshInstance3D
var _aim_point := Vector3.INF
var _shovel: MeshInstance3D


func _ready() -> void:
	add_to_group("player")
	collision_layer = Build.LAYER_PLAYER
	collision_mask = Build.LAYER_WORLD | Build.LAYER_TRAIN | Build.LAYER_ENEMY
	floor_max_angle = deg_to_rad(50)
	var shape := CapsuleShape3D.new()
	shape.radius = 0.35
	shape.height = 1.8
	var cs := CollisionShape3D.new()
	cs.shape = shape
	cs.position.y = 0.9
	add_child(cs)

	# Body for other players to see (hidden from our own camera via render layer 2)
	var body := Build.box(self, Vector3(0.7, 1.4, 0.45), Vector3(0, 0.8, 0), Color(0.85, 0.55, 0.3))
	body.layers = 2

	camera = Camera3D.new()
	camera.position.y = 1.6
	camera.fov = 80
	camera.cull_mask &= ~2
	add_child(camera)
	camera.make_current()

	_ray = RayCast3D.new()
	_ray.target_position = Vector3(0, 0, -REACH)
	_ray.collide_with_areas = true
	_ray.collision_mask = Build.LAYER_WORLD | Build.LAYER_TRAIN | Build.LAYER_INTERACT | Build.LAYER_ENEMY
	_ray.add_exception(self)
	camera.add_child(_ray)

	# Placeholder shovel in hand
	_shovel = Build.box(camera, Vector3(0.08, 0.08, 0.9), Vector3(0.35, -0.35, -0.6), Color(0.45, 0.3, 0.15))
	Build.box(_shovel, Vector3(0.3, 0.04, 0.3), Vector3(0, 0, -0.5), Color(0.5, 0.5, 0.55))

	_aim_marker = Build.cylinder(self, Meteor.RADIUS, 0.1, Vector3.ZERO, Color(1, 0, 0, 0.4))
	_aim_marker.top_level = true
	_aim_marker.visible = false

	if not Engine.is_editor_hint() and DisplayServer.get_name() != "headless":
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	Game.ui_changed.connect(_on_ui_changed)


func _on_ui_changed(open: bool) -> void:
	if DisplayServer.get_name() == "headless":
		return
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE if open else Input.MOUSE_MODE_CAPTURED


func _unhandled_input(event: InputEvent) -> void:
	if Game.ui_open:
		return
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		rotate_y(-event.relative.x * MOUSE_SENS)
		camera.rotate_x(-event.relative.y * MOUSE_SENS)
		camera.rotation.x = clampf(camera.rotation.x, -1.45, 1.45)
	elif event is InputEventMouseButton and event.pressed and Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("ui_cancel"):
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	elif downed:
		return
	elif Game.role == "impostor" and _handle_sabotage_input(event):
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("attack"):
		_attack()
	elif event.is_action_pressed("interact") and focused and focused.get_hold_time(self) <= 0.0:
		focused.interact(self)
	elif event.is_action_pressed("interact_alt") and focused:
		focused.interact_alt(self)


func _handle_sabotage_input(event: InputEvent) -> bool:
	var sab := Game.sabotage
	if aiming_meteor:
		if event.is_action_pressed("attack"):
			if _aim_point != Vector3.INF and sab.use("meteor", _aim_point):
				aiming_meteor = false
			return true
		if event.is_action_pressed("cancel") or event.is_action_pressed("sabotage_1"):
			aiming_meteor = false
			return true
		return false
	for id: String in SabotageManager.ABILITIES:
		if event.is_action_pressed("sabotage_%d" % SabotageManager.ABILITIES[id].key):
			if not sab.can_use(id):
				Game.say("%s is not ready" % SabotageManager.ABILITIES[id].label)
			elif id == "meteor":
				aiming_meteor = true
				Game.say("Aim the meteor: [LMB] drop, [RMB] cancel")
			else:
				sab.use(id)
			return true
	return false


func _physics_process(delta: float) -> void:
	_attack_cd = maxf(_attack_cd - delta, 0.0)
	_update_cold(delta)

	if global_position.y < -30.0:
		respawn_on_train()

	var input := Vector2.ZERO
	if not Game.ui_open and not downed:
		input = Input.get_vector("move_left", "move_right", "move_forward", "move_back")
	var speed := SPRINT if Input.is_action_pressed("sprint") else WALK
	if frost > 50.0:
		speed *= 0.7
	var dir := (transform.basis * Vector3(input.x, 0, input.y)).normalized()
	velocity.x = dir.x * speed
	velocity.z = dir.z * speed
	if is_on_floor():
		if Input.is_action_just_pressed("jump") and not Game.ui_open and not downed:
			velocity.y = JUMP
	else:
		velocity.y -= _gravity * delta
	move_and_slide()

	_update_focus(delta)
	_update_aim()


func _update_focus(delta: float) -> void:
	var hit := _ray.get_collider() if _ray.is_colliding() else null
	var new_focus: Interactable = hit if hit is Interactable else null
	if new_focus != focused:
		focused = new_focus
		hold_progress = 0.0
	hold_needed = focused.get_hold_time(self) if focused else 0.0
	if focused and hold_needed > 0.0 and Input.is_action_pressed("interact") and not Game.ui_open and not downed:
		hold_progress += delta
		if hold_progress >= hold_needed:
			hold_progress = 0.0
			focused.interact(self)
	else:
		hold_progress = 0.0


func _update_aim() -> void:
	_aim_marker.visible = aiming_meteor
	if not aiming_meteor:
		return
	var from := camera.global_position
	var to := from - camera.global_basis.z * AIM_RANGE
	var query := PhysicsRayQueryParameters3D.create(from, to, Build.LAYER_WORLD | Build.LAYER_TRAIN)
	var result := get_world_3d().direct_space_state.intersect_ray(query)
	_aim_point = result.position if result else Vector3.INF
	_aim_marker.visible = result.size() > 0
	if result:
		_aim_marker.global_position = Vector3(_aim_point.x, 0.05, _aim_point.z)


func _attack() -> void:
	if _attack_cd > 0.0:
		return
	_attack_cd = ATTACK_COOLDOWN
	var tween := create_tween()
	tween.tween_property(_shovel, "rotation:x", -0.8, 0.1)
	tween.tween_property(_shovel, "rotation:x", 0.0, 0.2)
	var hit := _ray.get_collider() if _ray.is_colliding() else null
	if hit and hit.has_method("take_hit"):
		hit.take_hit(SHOVEL_DAMAGE)


func _update_cold(delta: float) -> void:
	var cold := 1.0 if Game.wind_active else 0.0
	var train := Game.train
	var warm := train != null and train.fuel > 0.0 and global_position.distance_to(train.furnace_position()) < WARM_RADIUS
	if cold > 0.0 and not warm:
		frost = minf(frost + 6.0 * cold * delta, 100.0)
	else:
		frost = maxf(frost - 12.0 * delta, 0.0)
	if frost >= 100.0:
		take_damage(4.0 * delta)


func take_damage(amount: float) -> void:
	if downed:
		return
	health = maxf(health - amount, 0.0)
	if health <= 0.0:
		downed = true
		Game.say("You died! (A friend must carry your body to be revived: M5)")
		Game.on_player_downed(self)


func respawn_on_train() -> void:
	velocity = Vector3.ZERO
	if Game.train:
		global_position = Game.train.cars[0].global_position + Vector3.UP * 2.0
