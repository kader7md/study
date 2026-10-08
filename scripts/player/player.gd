class_name Player
extends CharacterBody3D
## First-person player (big cartoony hands, RV There Yet style):
## walk, sprint, jump, ride the train, use things ([E]/[Q], hold [E]),
## tools on keys 1-3: hammer (nails, bolts, wheels, fight), nail gun (if bought), welder (only while holding the
## torch taken from a STATION welder machine: hold LMB, the cable has a length limit).
## Carry repair items (plank, rail, wheel) in both hands; [G] puts them back.
## Debug impostor (F2): [Tab] opens the sabotage menu, then keys 1-4; meteor is aimed (LMB drop, RMB cancel).
## NET: one Player per peer (Players/Player_<peer id>, spawned by Net). The local one moves itself and sends its
## position (InputSync); everything that changes game state goes through Net.request() so it runs on the host.
## Other players are shown with a third-person RemoteBody; their first-person arms and camera stay hidden.

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
var _right: Node3D          # right arm pivot (holds the tool)
var _left: Node3D           # left arm pivot (shows when carrying)
var _tool_models := {}
var _carry_model: Node3D
var _sparks: CPUParticles3D
var _weld_light: OmniLight3D
var _cable: WelderCable
var _right_rest := Vector3(0.36, -0.36, -0.62)
## Riding the train: the car we stand on and its transform last frame (we move with it exactly).
var _ride_car: Node3D
var _ride_prev: Transform3D
var _ride_grace := 0.0
## Tests can force the aim point.
var _test_aim := Vector3.INF

# NET: identity and replicated state (see scripts/net/player_sync.gd)
var peer_id := 1
var display_name := ""
var color := Color(0.85, 0.55, 0.3)
## Position (local to the ridden train car when net_car >= 0), yaw and camera pitch, written by the owning peer.
var net_pos := Vector3.ZERO
var net_yaw := 0.0
var net_pitch := 0.0
var net_car := -1
## Host-owned: the station welder this player holds the torch of (a node path, "" = none).
var welder_path := ""
## Host: where a client was aiming when it sent the request being run.
var net_aim := Vector3.INF
var _remote_body: RemoteBody
var _shown_carry := ""
var _seen_welder_path := ""
var _weld_acc := 0.0
var _last_net_pos := Vector3.ZERO
var _remote_car := -1
var _remote_local := Vector3.ZERO


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
	if is_local():
		var body := Build.box(self, Vector3(0.7, 1.4, 0.45), Vector3(0, 0.8, 0), Color(0.85, 0.55, 0.3))
		body.layers = 2
	else:
		# NET: another peer's player: a third-person body with a name tag
		_remote_body = RemoteBody.new()
		_remote_body.name = "Body"
		add_child(_remote_body)
		_remote_body.setup(display_name if display_name != "" else String(name), color)

	camera = Camera3D.new()
	camera.position.y = 1.6
	camera.fov = 80
	camera.near = 0.03
	camera.cull_mask &= ~2
	add_child(camera)
	if is_local():
		camera.make_current()
	else:
		camera.visible = false  # NET: hides the first-person arms and tools of other players
		camera.clear_current(false)

	_ray = RayCast3D.new()
	_ray.target_position = Vector3(0, 0, -REACH)
	_ray.collide_with_areas = true
	_ray.collision_mask = Build.LAYER_WORLD | Build.LAYER_TRAIN | Build.LAYER_INTERACT | Build.LAYER_ENEMY
	_ray.add_exception(self)
	camera.add_child(_ray)

	_build_hands()

	_aim_marker = Build.cylinder(self, Meteor.RADIUS, 0.1, Vector3.ZERO, Color(1, 0, 0, 0.4))
	_aim_marker.top_level = true
	_aim_marker.visible = false

	_cable = WelderCable.new()
	add_child(_cable)
	_cable.visible = false

	if is_local():
		if DisplayServer.get_name() != "headless":
			Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
		Game.ui_changed.connect(_on_ui_changed)
	select_tool("hammer")


## NET: true for the player this peer controls (always true offline).
func is_local() -> bool:
	return is_multiplayer_authority()


# --- Hands, tools, carrying --------------------------------------------------------

func _build_hands() -> void:
	_right = Node3D.new()
	_right.position = _right_rest
	camera.add_child(_right)
	_arm(_right)
	_left = Node3D.new()
	_left.position = Vector3(-0.36, -0.36, -0.62)
	camera.add_child(_left)
	_arm(_left)
	_left.visible = false

	var hammer := Props.instance("hammer")
	hammer.rotation = Vector3(-0.35, 0.25, 0.2)
	hammer.position = Vector3(0, 0.02, -0.03)
	hammer.scale = Vector3.ONE * 0.65
	var welder := Props.instance("welder")
	welder.position = Vector3(0, 0.02, -0.06)
	welder.scale = Vector3.ONE * 0.8
	var gun := Props.instance("nail_gun")
	gun.position = Vector3(0, 0.0, -0.04)
	var wrench := Props.instance("wrench")
	wrench.rotation = Vector3(-0.3, 0.2, 0.15)
	wrench.scale = Vector3.ONE * 0.8
	var winch := Props.instance("come_along")
	winch.rotation = Vector3(-0.2, 0.3, 0.0)
	for pair in [["hammer", hammer], ["wrench", wrench], ["welder", welder], ["nail_gun", gun], ["come_along", winch]]:
		_right.add_child(pair[1])
		_tool_models[pair[0]] = pair[1]

	_sparks = CPUParticles3D.new()
	_sparks.emitting = false
	_sparks.amount = 40
	_sparks.lifetime = 0.35
	_sparks.direction = Vector3(0, 1, 0)
	_sparks.spread = 70.0
	_sparks.initial_velocity_min = 1.5
	_sparks.initial_velocity_max = 3.5
	_sparks.gravity = Vector3(0, -9.8, 0)
	_sparks.scale_amount_min = 0.02
	_sparks.scale_amount_max = 0.04
	var spark_mesh := SphereMesh.new()
	spark_mesh.radius = 0.5
	spark_mesh.height = 1.0
	var spark_mat := StandardMaterial3D.new()
	spark_mat.albedo_color = Color(1.0, 0.75, 0.3)
	spark_mat.emission_enabled = true
	spark_mat.emission = Color(1.0, 0.6, 0.2)
	spark_mat.emission_energy_multiplier = 4.0
	spark_mesh.material = spark_mat
	_sparks.mesh = spark_mesh
	_sparks.position = Vector3(0, 0.05, -0.42)
	welder.add_child(_sparks)
	_weld_light = OmniLight3D.new()
	_weld_light.light_color = Color(0.6, 0.8, 1.0)
	_weld_light.omni_range = 4.0
	_weld_light.light_energy = 0.0
	_weld_light.position = Vector3(0, 0.05, -0.42)
	welder.add_child(_weld_light)


func _arm(pivot: Node3D) -> void:
	Build.box(pivot, Vector3(0.11, 0.11, 0.4), Vector3(0, -0.04, 0.22), SKIN)
	Build.sphere(pivot, 0.07, Vector3(0, 0, 0), SKIN)  # chunky hand
	Build.box(pivot, Vector3(0.13, 0.13, 0.12), Vector3(0, -0.04, 0.42), Color(0.85, 0.55, 0.3))  # sleeve


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
	welder_path = str(source.get_path())  # NET: the owner's client picks the torch up from this
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
	for id: String in _tool_models:
		_tool_models[id].visible = id == tool and carried_item == ""
	if tool != "welder":
		_unplug(false)


func carry(item: String) -> void:
	carried_item = item
	_unplug(false)
	_show_carry(item)


## Builds what the hands hold for `item` ("" = nothing). NET: also runs when carried_item arrives from the host.
func _show_carry(item: String) -> void:
	_shown_carry = item
	if _carry_model:
		_carry_model.queue_free()
		_carry_model = null
	if _remote_body:
		return  # another player: RemoteBody shows it
	if item == "":
		_left.visible = false
		_right.position = _right_rest
		select_tool(current_tool)
		return
	_carry_model = Props.instance(item)
	match item:
		"plank":
			_carry_model.position = Vector3(0, -0.38, -0.85)
			_carry_model.scale = Vector3.ONE * 0.55
		"rail":
			_carry_model.position = Vector3(0.05, -0.4, -1.1)
			_carry_model.rotation = Vector3(0, 0.15, 0)
			_carry_model.scale = Vector3.ONE * 0.45
		"panel":
			_carry_model.position = Vector3(0, -0.3, -0.85)
			_carry_model.scale = Vector3.ONE * 0.6
		"wheel":
			_carry_model.position = Vector3(0, -0.35, -0.8)
			_carry_model.rotation = Vector3(0, PI * 0.5, 0)
			_carry_model.scale = Vector3.ONE * 0.7
	camera.add_child(_carry_model)
	_left.visible = true
	_right.position = Vector3(0.3, -0.35, -0.6)
	_left.position = Vector3(-0.3, -0.35, -0.6)
	select_tool(current_tool)


func consume_carried() -> void:
	carried_item = ""
	_show_carry("")


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
	if Game.ui_open or not is_local():
		return
	Net.run_as(peer_id, _handle_input, [event])  # NET: feedback from our own input stays on our screen


func _handle_input(event: InputEvent) -> void:
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
		Net.request(self, &"put_back")  # NET: state changes run on the host
	elif event.is_action_pressed("interact") and focused and focused.get_hold_time(self) <= 0.0:
		Net.request(focused, &"interact", [self])
	elif event.is_action_pressed("interact_alt") and focused:
		Net.request(focused, &"interact_alt", [self])


func _handle_sabotage_input(event: InputEvent) -> bool:
	var sab := Game.sabotage
	if event.is_action_pressed("sabotage_menu"):
		Game.sabotage_menu_open = not Game.sabotage_menu_open
		aiming_meteor = false
		return true
	if aiming_meteor:
		if event.is_action_pressed("attack"):
			# NET: the host runs the sabotage (online it answers later, so stop aiming right away)
			if _aim_point != Vector3.INF and Net.request(sab, &"use", ["meteor", _aim_point]) != false:
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
				Net.request(sab, &"use", [id])
			return true
	return false


## Left mouse with the hammer or nail gun.
func use_tool() -> void:
	if carried_item != "" or _tool_cd > 0.0 or current_tool == "welder":
		return
	var hit := _ray.get_collider() if _ray.is_colliding() else null
	if current_tool == "hammer":
		_tool_cd = 0.45
		var tween := create_tween()
		tween.tween_property(_right, "rotation:x", -1.1, 0.08).set_ease(Tween.EASE_IN)
		tween.tween_property(_right, "rotation:x", 0.0, 0.2).set_ease(Tween.EASE_OUT)
		if hit:
			Net.request(self, &"tool_hit", [hit, "hammer", HAMMER_DAMAGE])  # NET: runs on the host
	elif current_tool == "wrench":
		_tool_cd = 0.35
		var tween := create_tween()
		tween.tween_property(_right, "rotation:z", -0.9, 0.12)
		tween.tween_property(_right, "rotation:z", 0.0, 0.18)
		if hit:
			Net.request(self, &"tool_hit", [hit, "wrench", HAMMER_DAMAGE * 0.75])
	elif current_tool == "come_along":
		_tool_cd = 0.3
		var train := Game.train
		var cranking := not (hit is HookSpot or hit is AnchorSpot) and train != null and train.tipped \
			and is_instance_valid(train.hook) and global_position.distance_to(train.hook.global_position) < 8.0
		if hit is HookSpot or hit is AnchorSpot or cranking:
			# NET: runs on the host; a client pumps the handle as long as the chain is anchored
			var result: Variant = Net.request(self, &"come_along_hit", [hit])
			if cranking and (result == true or (result == null and is_instance_valid(train.anchor))):
				# pump the ratchet handle
				var tween := create_tween()
				tween.tween_property(_right, "rotation:x", 0.9, 0.12)
				tween.tween_property(_right, "rotation:x", -0.2, 0.15)
				tween.tween_property(_right, "rotation:x", 0.0, 0.05)
		elif train and train.tipped:
			Game.say("Stand near the come-along on the train to crank it")
	elif current_tool == "nail_gun":
		_tool_cd = 0.25
		var tween := create_tween()
		tween.tween_property(_right, "position:z", _right.position.z + 0.08, 0.04)
		tween.tween_property(_right, "position:z", _right.position.z, 0.1)
		if hit:
			Net.request(self, &"tool_hit", [hit, "nail_gun", NAIL_GUN_DAMAGE])


## A tool hits `hit`: repair work first (nails, bolts, wheels...), otherwise damage (zombies, eagles).
## NET: runs on the host (directly offline). Returns true if the hit did something.
func tool_hit(hit: Node, tool: String, damage: float) -> bool:
	if hit is Interactable and hit.on_tool_hit(tool, self):
		return true
	if hit and hit.has_method("take_hit"):
		hit.take_hit(damage)
		return true
	return false


## The come-along used on `hit`: hook it to the train, chain it to an anchor, or crank. NET: runs on the host.
func come_along_hit(hit: Node) -> bool:
	var train := Game.train
	if train == null:
		return false
	if hit is HookSpot:
		return train.attach_hook(hit)
	if hit is AnchorSpot:
		return train.attach_anchor(hit)
	if train.tipped and is_instance_valid(train.hook) and global_position.distance_to(train.hook.global_position) < 8.0:
		return train.crank()
	return false


# --- Update -------------------------------------------------------------------------

func _physics_process(delta: float) -> void:
	if not is_local():
		_remote_update(delta)  # NET: another peer moves this player
		return
	Net.run_as(peer_id, _local_physics, [delta])  # NET: our own feedback stays on our screen


func _local_physics(delta: float) -> void:
	_tool_cd = maxf(_tool_cd - delta, 0.0)
	if Game.is_host():
		_update_cold(delta)  # NET: health and frost are host state

	if global_position.y < Track.WATER_LEVEL - 1.2:
		Game.say("You fell in the water!")
		Net.request(self, &"take_damage", [20.0])
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
	_write_net_state()


# --- NET: replication helpers ---------------------------------------------------------

## Owner: what InputSync sends (position relative to the ridden car, so riders stay glued to it).
func _write_net_state() -> void:
	var train := Game.train
	net_car = train.cars.find(_ride_car) if train and is_instance_valid(_ride_car) else -1
	net_pos = train.cars[net_car].global_transform.affine_inverse() * global_position if net_car >= 0 else global_position
	net_yaw = rotation.y
	net_pitch = camera.rotation.x


## Another peer's player: glide to its synced position and look, keep its body up to date.
func _remote_update(delta: float) -> void:
	var train := Game.train
	var k := 1.0 - exp(-18.0 * delta)
	if net_car >= 0 and train and net_car < train.cars.size():
		# riding: smooth in the car's own space, so a fast train doesn't leave them sliding behind
		var car := train.cars[net_car].global_transform
		if _remote_car != net_car:
			_remote_car = net_car
			_remote_local = car.affine_inverse() * global_position
		_remote_local = net_pos if _remote_local.distance_to(net_pos) > 6.0 else _remote_local.lerp(net_pos, k)
		global_position = car * _remote_local
	else:
		_remote_car = -1
		global_position = net_pos if global_position.distance_to(net_pos) > 6.0 else global_position.lerp(net_pos, k)
	rotation.y = lerp_angle(rotation.y, net_yaw, k)
	camera.rotation.x = net_pitch
	if Game.is_host():
		Net.run_as(peer_id, _update_cold, [delta])  # "you died" goes to that player
		# the torch cable is pulled out if they walked off with it
		if is_instance_valid(welder_source):
			var plug := welder_source.plug_position()
			if Vector2(global_position.x - plug.x, global_position.z - plug.z).length() > welder_source.cable_length + 6.0:
				_unplug(false)
	if _remote_body:
		var walk := net_pos.distance_to(_last_net_pos) / maxf(delta, 0.001)
		_last_net_pos = net_pos
		_remote_body.set_pitch(net_pitch)
		_remote_body.set_held("hammer" if current_tool == "welder" and welder_path == "" else current_tool, carried_item)
		_remote_body.animate(delta, walk if walk < 20.0 else 0.0)


func _process(_delta: float) -> void:
	# NET: carried items and the welder torch can change on the host; refresh the hands here
	if carried_item != _shown_carry:
		_show_carry(carried_item)
	if welder_path != _seen_welder_path:
		_seen_welder_path = welder_path
		if is_local() and not Game.is_host():
			welder_source = get_node_or_null(welder_path) as WelderSource if welder_path != "" else null
			if welder_source:
				select_tool("welder")
			elif current_tool == "welder":
				select_tool("hammer")


func set_speaking(on: bool) -> void:
	if _remote_body:
		_remote_body.set_speaking(on)


## Host: a client switched away from the torch (or walked too far).
func unplug_welder() -> void:
	_unplug(false)


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
			Net.request(focused, &"interact", [self])
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
	_cable.update(plug, _sparks.global_position, limit)

	if Input.is_action_pressed("attack") and not Game.ui_open:
		var hit := _ray.get_collider() if _ray.is_colliding() else null
		if hit is Interactable:
			if Game.is_host():
				welding = hit.on_weld(delta, self, welder_source)
			else:
				# NET: weld time goes to the host in small batches
				welding = true
				_weld_acc += delta
				if _weld_acc >= 0.1:
					Net.request(self, &"weld_tick", [hit, _weld_acc])
					_weld_acc = 0.0
	_set_weld_fx(welding)
	if welding:
		var t := Time.get_ticks_msec() * 0.02
		_right.position = _right_rest + Vector3(cos(t) * 0.015, sin(t * 1.3) * 0.015, 0)
		_right.rotation.z = sin(t * 0.7) * 0.08
	else:
		_right.position = _right_rest
		_right.rotation.z = 0.0


## Where the player is looking (within reach), or Vector3.INF.
func aim_point() -> Vector3:
	if _test_aim != Vector3.INF:
		return _test_aim
	if net_aim != Vector3.INF:
		return net_aim  # NET: the host uses the aim the client sent with its request
	return _ray.get_collision_point() if _ray.is_colliding() else Vector3.INF


func weld_tick(target: Interactable, delta: float) -> bool:
	## Test helper: weld `target` for `delta` seconds as if aiming at it with LMB held.
	if not is_instance_valid(welder_source):
		return false
	if not is_local():
		# NET: a client's torch only reaches as far as the cable
		var plug := welder_source.plug_position()
		if Vector2(global_position.x - plug.x, global_position.z - plug.z).length() > welder_source.cable_length + 6.0:
			_unplug(false)
			return false
	return target.on_weld(delta, self, welder_source)


func _unplug(announce: bool) -> void:
	if is_instance_valid(welder_source) and announce:
		Game.say("The welder cable pulled out: the torch is back at the station welder")
	if is_instance_valid(welder_source) and is_inside_tree() and is_local() and not Game.is_host():
		Net.request(self, &"unplug_welder")  # NET: the host holds the torch state
	welder_source = null
	if Game.is_host():
		welder_path = ""
	if _cable:
		_cable.visible = false
	_set_weld_fx(false)


func _set_weld_fx(on: bool) -> void:
	if _sparks:
		_sparks.emitting = on
		_weld_light.light_energy = randf_range(1.5, 3.0) if on else 0.0


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
