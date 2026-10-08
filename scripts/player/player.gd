class_name Player
extends CharacterBody3D
## First-person player (big cartoony hands; the hands, tools and carry poses live in Viewmodel):
## walk, sprint, jump, ride the train, use things ([E]/[Q], hold [E]),
## tools on keys 1-5: hammer (nails, bolts, wheels, fight), nail gun (if bought), welder (only while holding the
## torch taken from a STATION welder machine: hold LMB, the cable has a length limit).
## Carry repair items (plank, rail, wheel) in both hands; [G] puts them back.
## Debug impostor (F2): [Tab] opens the sabotage menu, then keys 1-4; meteor is aimed (LMB drop, RMB cancel).

const WALK := 4.5
const SPRINT := 7.5
const JUMP := 5.5
const MOUSE_SENS := 0.0025
const REACH := 3.5
const AIM_RANGE := 500.0
const HAMMER_DAMAGE := 20.0
const NAIL_GUN_DAMAGE := 8.0
const WARM_RADIUS := 7.0
const SKIN := Color(1.0, 0.76, 0.6)
const TOOLS := ["hammer", "wrench", "nail_gun", "welder", "come_along"]
const TOOL_NAMES := {"hammer": "Hammer", "wrench": "Wrench", "welder": "Welder", "nail_gun": "Nail gun", "come_along": "Come-along"}

var health := 100.0
var frost := 0.0
var downed := false
var camera: Camera3D
var focused: Interactable
var hold_progress := 0.0
var hold_needed := 0.0
var aiming_meteor := false
var current_tool := "hammer"
var carried_item := ""
var welder_source: WelderSource
var welding := false
var cable_tension := 0.0

var _ray: RayCast3D
var _gravity: float = ProjectSettings.get_setting("physics/3d/default_gravity")
var _tool_cd := 0.0
var _aim_marker: MeshInstance3D
var _aim_point := Vector3.INF
## First-person hands, tools, tool animations and carry poses (scripts/player/viewmodel.gd).
var viewmodel: Viewmodel
var _cable: WelderCable
## Riding the train: the car we stand on and its transform last frame (we move with it exactly).
var _ride_car: Node3D
var _ride_prev: Transform3D
var _ride_grace := 0.0
## Tests can force the aim point.
var _test_aim := Vector3.INF


func _ready() -> void:
	add_to_group("player")
	collision_layer = Build.LAYER_PLAYER
	collision_mask = Build.LAYER_WORLD | Build.LAYER_TRAIN | Build.LAYER_ENEMY
	floor_max_angle = deg_to_rad(50)
	# Train cars are carried by our own ride logic (exact, also on hills); other platforms the normal way
	platform_floor_layers = Build.LAYER_WORLD
	var shape := CapsuleShape3D.new()
	shape.radius = 0.28
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
	camera.near = 0.03
	camera.cull_mask &= ~2
	add_child(camera)
	camera.make_current()

	_ray = RayCast3D.new()
	_ray.target_position = Vector3(0, 0, -REACH)
	_ray.collide_with_areas = true
	_ray.collision_mask = Build.LAYER_WORLD | Build.LAYER_TRAIN | Build.LAYER_INTERACT | Build.LAYER_ENEMY
	_ray.add_exception(self)
	camera.add_child(_ray)

	viewmodel = Viewmodel.new()
	viewmodel.name = "Viewmodel"
	camera.add_child(viewmodel)
	viewmodel.setup(self, camera)

	_aim_marker = Build.cylinder(self, Meteor.RADIUS, 0.1, Vector3.ZERO, Color(1, 0, 0, 0.4))
	_aim_marker.top_level = true
	_aim_marker.visible = false

	_cable = WelderCable.new()
	add_child(_cable)
	_cable.visible = false

	if DisplayServer.get_name() != "headless":
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	Game.ui_changed.connect(_on_ui_changed)
	select_tool("hammer")


# --- Hands, tools, carrying --------------------------------------------------------

func available_tools() -> Array[String]:
	var list: Array[String] = ["hammer", "wrench"]
	if Game.has("nail_gun"):
		list.append("nail_gun")
	if is_instance_valid(welder_source):
		list.append("welder")
	if Game.has("come_along"):
		list.append("come_along")
	return list


## Takes the welding torch from a station welder machine (the only welders in the game).
func take_welder(source: WelderSource) -> void:
	if carried_item != "":
		Game.say("Hands full")
		return
	welder_source = source
	select_tool("welder")
	Game.say("Welding torch in hand (cable %d m). Switch tools or walk away to put it back." % int(source.cable_length))


func select_tool(tool: String) -> void:
	if not tool in available_tools():
		if tool == "nail_gun":
			Game.say("No nail gun yet (buy one at a station shop)")
		elif tool == "welder":
			Game.say("Welding torches are only at stations: take one from the station welder")
		return
	current_tool = tool
	viewmodel.select_tool(tool)
	if tool != "welder":
		_unplug(false)


func carry(item: String) -> void:
	carried_item = item
	_unplug(false)
	viewmodel.carry(item)
	select_tool(current_tool)


## The carried item was placed (or put back): the hands lower it out of view.
func consume_carried() -> void:
	carried_item = ""
	viewmodel.drop_carry()
	select_tool(current_tool)


## [G]: put the carried item back (refunds it to the crew inventory).
func put_back() -> void:
	if carried_item == "":
		return
	var cost: Dictionary = Train.CARRY_COST[carried_item]
	for item: String in cost:
		Game.add(item, cost[item])
	Game.say("Put the %s back" % carried_item)
	consume_carried()


# --- Input ------------------------------------------------------------------------

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
		return
	if event is InputEventMouseButton and event.pressed and Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
		get_viewport().set_input_as_handled()
		return
	if event.is_action_pressed("ui_cancel"):
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
		return
	if downed:
		return
	if Game.role == "impostor" and _handle_sabotage_input(event):
		get_viewport().set_input_as_handled()
		return
	if event is InputEventMouseButton and event.pressed and carried_item == "":
		if event.button_index == MOUSE_BUTTON_WHEEL_UP or event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			var tools := available_tools()
			var step := 1 if event.button_index == MOUSE_BUTTON_WHEEL_DOWN else -1
			select_tool(tools[(tools.find(current_tool) + step + tools.size()) % tools.size()])
			return
	for i in TOOLS.size():
		if event.is_action_pressed("tool_%d" % (i + 1)):
			select_tool(TOOLS[i])
			return
	if event.is_action_pressed("attack"):
		use_tool()
	elif event.is_action_pressed("drop"):
		put_back()
	elif event.is_action_pressed("interact") and focused and focused.get_hold_time(self) <= 0.0:
		focused.interact(self)
	elif event.is_action_pressed("interact_alt") and focused:
		focused.interact_alt(self)


func _handle_sabotage_input(event: InputEvent) -> bool:
	var sab := Game.sabotage
	if event.is_action_pressed("sabotage_menu"):
		Game.sabotage_menu_open = not Game.sabotage_menu_open
		aiming_meteor = false
		return true
	if aiming_meteor:
		if event.is_action_pressed("attack"):
			if _aim_point != Vector3.INF and sab.use("meteor", _aim_point):
				aiming_meteor = false
			return true
		if event.is_action_pressed("cancel"):
			aiming_meteor = false
			return true
		return false
	if not Game.sabotage_menu_open:
		return false
	for id: String in SabotageManager.ABILITIES:
		if event.is_action_pressed("sabotage_%d" % SabotageManager.ABILITIES[id].key):
			if not sab.can_use(id):
				Game.say("%s is not ready" % SabotageManager.ABILITIES[id].label)
			elif id == "meteor":
				aiming_meteor = true
				Game.sabotage_menu_open = false
				Game.say("Aim the meteor: [LMB] drop, [RMB] cancel")
			else:
				sab.use(id)
			return true
	return false


## Left mouse with the hammer or nail gun.
func use_tool() -> void:
	if carried_item != "" or _tool_cd > 0.0 or current_tool == "welder":
		return
	var hit := _ray.get_collider() if _ray.is_colliding() else null
	if current_tool == "hammer":
		_tool_cd = 0.45
		viewmodel.play("hammer")
		if hit is Interactable and hit.on_tool_hit("hammer", self):
			return
		if hit and hit.has_method("take_hit"):
			hit.take_hit(HAMMER_DAMAGE)
	elif current_tool == "wrench":
		_tool_cd = 0.5
		viewmodel.play("wrench")
		if hit is Interactable and hit.on_tool_hit("wrench", self):
			return
		if hit and hit.has_method("take_hit"):
			hit.take_hit(HAMMER_DAMAGE * 0.75)
	elif current_tool == "come_along":
		_tool_cd = 0.45
		viewmodel.play("come_along")
		var train := Game.train
		if hit is HookSpot:
			train.attach_hook(hit)
		elif hit is AnchorSpot:
			train.attach_anchor(hit)
		elif train and train.tipped and is_instance_valid(train.hook) and global_position.distance_to(train.hook.global_position) < 8.0:
			train.crank()
		elif train and train.tipped:
			Game.say("Stand near the come-along on the train to crank it")
	elif current_tool == "nail_gun":
		_tool_cd = 0.25
		viewmodel.play("nail_gun")
		if hit is Interactable and hit.on_tool_hit("nail_gun", self):
			return
		if hit and hit.has_method("take_hit"):
			hit.take_hit(NAIL_GUN_DAMAGE)


# --- Update -------------------------------------------------------------------------

func _physics_process(delta: float) -> void:
	_tool_cd = maxf(_tool_cd - delta, 0.0)
	_update_cold(delta)

	if global_position.y < Track.WATER_LEVEL - 1.2:
		Game.say("You fell in the water!")
		take_damage(20.0)
		respawn_on_train()
	elif global_position.y < -80.0:
		respawn_on_train()

	_ride_train(delta)

	var input := Vector2.ZERO
	if not Game.ui_open and not downed:
		input = Input.get_vector("move_left", "move_right", "move_forward", "move_back")
	var speed := SPRINT if Input.is_action_pressed("sprint") and carried_item == "" else WALK
	if carried_item == "rail":
		speed *= 0.75
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
	_update_ride_car()

	_update_focus(delta)
	_update_welder(delta)
	_update_aim()


## Moves the player along with the train car they stand on (position and turning), before walking.
func _ride_train(delta: float) -> void:
	if not is_instance_valid(_ride_car):
		return
	var now := _ride_car.global_transform
	var moved := now * _ride_prev.affine_inverse()
	global_position = moved * global_position
	rotate_y(moved.basis.get_euler().y)
	_ride_prev = now
	_ride_grace -= delta
	if _ride_grace <= 0.0:
		_ride_car = null


## After moving: which train car are we standing on? (a short grace keeps us attached over small bumps)
func _update_ride_car() -> void:
	for i in get_slide_collision_count():
		var col := get_slide_collision(i)
		var body := col.get_collider()
		if col.get_normal().y > 0.6 and body is AnimatableBody3D and body.get_parent() is Train:
			if body != _ride_car:
				_ride_car = body
				_ride_prev = body.global_transform
			_ride_grace = 0.25
			return


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


## Welder (torch from a station machine): keep the player inside the cable length,
## weld whatever the torch points at while LMB is held.
func _update_welder(delta: float) -> void:
	welding = false
	if current_tool == "welder" and not is_instance_valid(welder_source):
		select_tool("hammer")
	var holding := current_tool == "welder" and carried_item == "" and not downed
	if not holding or not is_instance_valid(welder_source):
		_cable.visible = false
		_set_weld_fx(false)
		cable_tension = 0.0
		return
	var plug := welder_source.plug_position()
	var flat := Vector3(global_position.x - plug.x, 0.0, global_position.z - plug.z)
	var limit := welder_source.cable_length
	if flat.length() > limit + 4.0:
		_unplug(true)
		select_tool("hammer")
		return
	if flat.length() > limit:
		var back := plug + flat.normalized() * limit
		global_position = Vector3(back.x, global_position.y, back.z)
	cable_tension = flat.length() / limit
	_cable.visible = true
	_cable.update(plug, viewmodel.muzzle_position(), limit)

	if Input.is_action_pressed("attack") and not Game.ui_open:
		var hit := _ray.get_collider() if _ray.is_colliding() else null
		if hit is Interactable:
			welding = hit.on_weld(delta, self, welder_source)
	_set_weld_fx(welding)


## Where the player is looking (within reach), or Vector3.INF.
func aim_point() -> Vector3:
	if _test_aim != Vector3.INF:
		return _test_aim
	return _ray.get_collision_point() if _ray.is_colliding() else Vector3.INF


func weld_tick(target: Interactable, delta: float) -> bool:
	## Test helper: weld `target` for `delta` seconds as if aiming at it with LMB held.
	if not is_instance_valid(welder_source):
		return false
	return target.on_weld(delta, self, welder_source)


func _unplug(announce: bool) -> void:
	if is_instance_valid(welder_source) and announce:
		Game.say("The welder cable pulled out: the torch is back at the station welder")
	welder_source = null
	if _cable:
		_cable.visible = false
	_set_weld_fx(false)


func _set_weld_fx(on: bool) -> void:
	if viewmodel:
		viewmodel.set_welding(on)


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
		_aim_marker.global_position = _aim_point + Vector3.UP * 0.05


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
	_ride_car = null
	if Game.train:
		global_position = Game.train.cars[0].global_position + Game.train.cars[0].global_basis.z * 3.0 + Vector3.UP * 2.0
