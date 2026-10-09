class_name Player
extends CharacterBody3D
## First-person player (big cartoony hands; the hands, tools and carry poses live in Viewmodel):
## walk, sprint, jump, ride the train, use things ([E]/[Q], hold [E]).
## HOTBAR: keys 1-5 (or the mouse wheel) pick one of the five personal hotbar slots (Game.slots, first 5); whatever
## sits there is in the hand: a tool (hammer, wrench, nail gun, come-along: [LMB] to use) or food ([LMB] eats it).
## [Tab] opens the personal inventory (HUD) to arrange it. The welder torch taken from a STATION welder machine is
## held on top of the hotbar until you pick a slot again (hold LMB to weld, the cable has a length limit).
## Health only comes back by eating (or a medkit / a revive). Warmth drains in the cold (freezing wind, or a
## cold_zone set by a map); at 0 warmth you take damage. Hard hits make you bleed for a few seconds.
## Carry repair items (plank, rail, wheel) in both hands; [G] puts them back.
## Debug impostor (F2): [X] opens the sabotage menu, then keys 1-4; meteor is aimed (LMB drop, RMB cancel).
## NET: one Player per peer (Players/Player_<peer id>, spawned by Net). The local one moves itself and sends its
## position (InputSync); everything that changes game state goes through Net.request() so it runs on the host.
## Other players are shown with a third-person RemoteBody (the animated CharacterModel in their own look); their
## first-person arms and camera stay hidden. Our own CharacterModel is on render layer 2: hidden from our camera, seen in
## the train's mirror. `look` is the Appearance code (synced), `net_action` the last action clip (synced, "clip#n").

const WALK := 4.5
const SPRINT := 7.5
const JUMP := 5.5
const REACH := 3.5
const AIM_RANGE := 500.0
const HAMMER_DAMAGE := 20.0
const NAIL_GUN_DAMAGE := 8.0
const WARM_RADIUS := 7.0
## Warmth per second: lost in the cold, regained out of it (twice as fast by the furnace or in a station).
const WARMTH_DRAIN := 6.0
const WARMTH_RECOVER := 10.0
## Damage per second at 0 warmth, and while bleeding (a hit of BLEED_HIT or more bleeds for BLEED_TIME s).
const FREEZE_DAMAGE := 4.0
const BLEED_DAMAGE := 1.5
const BLEED_HIT := 8.0
const BLEED_TIME := 4.0
## Coffee: faster walking for this long.
const BOOST_SPEED := 1.25
const SKIN := Color(1.0, 0.76, 0.6)
const TOOL_NAMES := {"hammer": "Hammer", "wrench": "Wrench", "welder": "Welder", "nail_gun": "Nail gun", "come_along": "Come-along"}

var health := 100.0
## 100 = warm, 0 = freezing (damage). NET: host state.
var warmth := 100.0
## Old name, kept for other code: 0 = warm, 100 = freezing.
var frost: float:
	get:
		return 100.0 - warmth
	set(value):
		warmth = clampf(100.0 - value, 0.0, 100.0)
## A map can make a place cold on its own (0..1, e.g. a mountain top); the freezing wind counts as 1.
var cold_zone := 0.0
var bleeding := false
## Coffee kick: walking faster for a while. NET: host state.
var boosted := false
## Hotbar slot in the hand (0-4). Local to the owning peer; current_tool says what it holds.
var hotbar_index := 0
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

# NET: identity and replicated state (see scripts/net/player_sync.gd)
var peer_id := 1
var display_name := ""
var color := Color(0.85, 0.55, 0.3)
## Appearance code (scripts/character/appearance.gd), written by the owning peer (InputSync), "" = default look.
var look := ""
## The last one-shot animation this player played ("hammer#3"), written by the owning peer (InputSync).
var net_action := ""
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
var _revive_spot: ReviveSpot
var _was_downed := false
## Our own body (render layer 2: the mirror sees it, our camera doesn't).
var body: CharacterModel
var _action_n := 0
var _seen_action := ""
var _shown_look := "-"
var _last_net_y := 0.0
var _bleed_t := 0.0
var _boost_t := 0.0


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

	# Our own body: on render layer 2, hidden from our own camera, seen in the mirror
	if is_local():
		if look == "":
			look = Appearance.saved_code() if Appearance.saved_code() != "" else Appearance.for_color(color).encode()
		body = CharacterModel.new()
		body.name = "Body"
		add_child(body)
		body.set_render_layers(2)
		_shown_look = ""
	else:
		# NET: another peer's player: a third-person body with a name tag
		_remote_body = RemoteBody.new()
		_remote_body.name = "Body"
		add_child(_remote_body)
		_remote_body.setup(display_name if display_name != "" else String(name), color)
		_seen_action = net_action  # an action from before we saw this player is not replayed

	camera = Camera3D.new()
	camera.position.y = 1.6
	camera.fov = Settings.fov
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

	# a crewmate aims at a downed player (lying on the ground) and presses [E] with a medkit
	_revive_spot = ReviveSpot.new()
	_revive_spot.name = "Revive"
	_revive_spot.target = self
	Build.collider(_revive_spot, Vector3(1.2, 1.0, 1.8), Vector3(0, 0.5, 0))
	add_child(_revive_spot)
	_update_revive_spot()

	if is_local():
		if DisplayServer.get_name() != "headless":
			Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
		Game.ui_changed.connect(_on_ui_changed)
		Settings.changed.connect(_on_settings_changed)
	else:
		viewmodel.visible = false  # NET: other players' first-person hands stay hidden
		viewmodel.set_process(false)
	if is_local():
		_apply_held()


## NET: true for the player this peer controls (always true offline).
func is_local() -> bool:
	return is_multiplayer_authority()


# --- Hands, tools, carrying --------------------------------------------------------

## Tools in the hotbar (plus the welder while holding a station torch).
func available_tools() -> Array[String]:
	var list: Array[String] = []
	for i in Game.HOTBAR_SIZE:
		var id := Game.slot_item(peer_id, i)
		if Game.item_kind(id) == "tool" and not id in list:
			list.append(id)
	if is_instance_valid(welder_source):
		list.append("welder")
	return list


## What the selected hotbar slot holds ("" = empty hands).
func held_item() -> String:
	return Game.slot_item(peer_id, hotbar_index)


## Takes the welding torch from a station welder machine (the only welders in the game).
func take_welder(source: WelderSource) -> void:
	if carried_item != "":
		Game.say("Hands full")
		return
	welder_source = source
	welder_path = str(source.get_path())  # NET: the owner's client picks the torch up from this
	_apply_held()
	Game.say("Welding torch in hand (cable %d m). Pick a hotbar slot or walk away to put it back." % int(source.cable_length))


## Picks hotbar slot i (0-4). Holding the station torch, it goes back to its welder.
func select_slot(i: int) -> void:
	hotbar_index = clampi(i, 0, Game.HOTBAR_SIZE - 1)
	if is_instance_valid(welder_source):
		_unplug(false)
	_apply_held()


## Puts what the hand should hold in it (the torch, else the selected slot), e.g. after the inventory changed.
func _apply_held() -> void:
	var id := "welder" if is_instance_valid(welder_source) else held_item()
	current_tool = id
	if viewmodel:
		viewmodel.select_tool(id)


## Picks the hotbar slot holding `tool` ("welder": the station torch in hand). Tests and old code use it.
func select_tool(tool: String) -> void:
	if tool == "welder":
		if is_instance_valid(welder_source):
			_apply_held()
		else:
			Game.say("Welding torches are only at stations: take one from the station welder")
		return
	for i in Game.HOTBAR_SIZE:
		if Game.slot_item(peer_id, i) == tool:
			select_slot(i)
			return
	if Game.count_in(peer_id, tool) > 0:
		Game.say("Put the %s in your hotbar first ([Tab] inventory)" % Game.item_name(tool).to_lower())
	elif tool == "nail_gun":
		Game.say("No nail gun yet (buy one at a station shop)")


func carry(item: String) -> void:
	carried_item = item
	_unplug(false)
	_show_carry(item)


## Shows what the hands hold for `item` ("" = nothing). NET: also runs when carried_item arrives from the host.
func _show_carry(item: String) -> void:
	_shown_carry = item
	if _remote_body:
		return  # another player: RemoteBody shows it
	if item == "":
		viewmodel.drop_carry()
	else:
		viewmodel.carry(item)


## The carried item was placed (or put back): the hands lower it out of view.
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


## Live settings: field of view (mouse sensitivity and invert Y are read on every mouse move).
func _on_settings_changed(_section: String, key: String) -> void:
	if key == "fov" and camera:
		camera.fov = Settings.fov


func _unhandled_input(event: InputEvent) -> void:
	if Game.ui_open or not is_local():
		return
	Net.run_as(peer_id, _handle_input, [event])  # NET: feedback from our own input stays on our screen


func _handle_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		var sens := Settings.mouse_sensitivity
		rotate_y(-event.relative.x * sens)
		camera.rotate_x(-event.relative.y * sens * (-1.0 if Settings.invert_y else 1.0))
		camera.rotation.x = clampf(camera.rotation.x, -1.45, 1.45)
		return
	if event is InputEventMouseButton and event.pressed and Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
		get_viewport().set_input_as_handled()
		return
	if downed:
		return
	if Game.role == "impostor" and _handle_sabotage_input(event):
		get_viewport().set_input_as_handled()
		return
	if event is InputEventMouseButton and event.pressed and carried_item == "":
		if event.button_index == MOUSE_BUTTON_WHEEL_UP or event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			var step := 1 if event.button_index == MOUSE_BUTTON_WHEEL_DOWN else -1
			select_slot((hotbar_index + step + Game.HOTBAR_SIZE) % Game.HOTBAR_SIZE)
			return
	for i in Game.HOTBAR_SIZE:
		if event.is_action_pressed("tool_%d" % (i + 1)):
			select_slot(i)
			return
	if event.is_action_pressed("winch_release") and current_tool == "come_along":
		Net.request(self, &"winch_release")
	elif event.is_action_pressed("attack"):
		use_tool()
	elif event.is_action_pressed("drop"):
		Net.request(self, &"put_back")  # NET: state changes run on the host
	elif event.is_action_pressed("interact") and focused and focused.get_hold_time(self) <= 0.0:
		_send_action(interact_clip(focused))
		if focused.has_method("interact_local"):
			focused.call("interact_local", self)  # opens something on this screen only (the mirror)
		else:
			Net.request(focused, &"interact", [self])
	elif event.is_action_pressed("emote") and carried_item == "":
		_send_action("wave")
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


## Left mouse: use the tool in hand, or eat what's in the hand.
func use_tool() -> void:
	if carried_item != "" or _tool_cd > 0.0 or current_tool == "welder":
		return
	if Game.item_kind(current_tool) == "food":
		_tool_cd = 0.6
		Net.request(self, &"eat_slot", [hotbar_index])  # NET: runs on the host
		return
	var hit := _ray.get_collider() if _ray.is_colliding() else null
	_send_action(CharacterAnimator.action_clip(current_tool))
	if current_tool == "hammer":
		_tool_cd = 0.45
		viewmodel.play("hammer")
		if hit:
			Net.request(self, &"tool_hit", [hit, "hammer", HAMMER_DAMAGE])  # NET: runs on the host
	elif current_tool == "wrench":
		_tool_cd = 0.5
		viewmodel.play("wrench")
		if hit:
			Net.request(self, &"tool_hit", [hit, "wrench", HAMMER_DAMAGE * 0.75])
	elif current_tool == "come_along":
		_tool_cd = 0.45
		viewmodel.play("come_along")
		var train := Game.train
		var cranking := not (hit is HookSpot or hit is AnchorSpot) and train != null and train.tipped \
			and is_instance_valid(train.hook) and global_position.distance_to(train.hook.global_position) < 8.0
		if hit is HookSpot or hit is AnchorSpot or cranking:
			Net.request(self, &"come_along_hit", [hit])  # NET: runs on the host
		elif train and train.tipped:
			Game.say("Stand near the come-along on the train to crank it")
	elif current_tool == "nail_gun":
		_tool_cd = 0.25
		viewmodel.play("nail_gun")
		if hit:
			Net.request(self, &"tool_hit", [hit, "nail_gun", NAIL_GUN_DAMAGE])


## A tool hits `hit`: repair work first (nails, bolts, wheels...), otherwise damage (zombies, eagles).
## NET: runs on the host (directly offline). Returns true if the hit did something.
func tool_hit(hit: Node, tool: String, damage: float) -> bool:
	if Net.remote_actor() != 0:
		damage = tool_damage(tool)  # NET: the host decides the damage, not the client
	if hit is Interactable and hit.on_tool_hit(tool, self):
		return true
	if hit and hit.has_method("take_hit"):
		hit.take_hit(damage)
		return true
	return false


## Damage a tool does to zombies and eagles.
static func tool_damage(tool: String) -> float:
	match tool:
		"hammer": return HAMMER_DAMAGE
		"wrench": return HAMMER_DAMAGE * 0.75
		"nail_gun": return NAIL_GUN_DAMAGE
	return 0.0


## Host: eats (or uses the medkit) from hotbar slot `index`: health back, warmth back, bleeding stops (medkit), coffee
## gives a speed kick. Returns true if something was eaten.
func eat_slot(index: int) -> bool:
	var item := Game.slot_item(peer_id, index)
	if Game.item_kind(item) != "food" or downed:
		return false
	var info: Dictionary = Game.ITEMS[item]
	var heal := float(info.get("heal", 0.0))
	var warm := float(info.get("warm", 0.0))
	var boost := float(info.get("boost", 0.0))
	var useful := health < 99.5 or (warm > 0.0 and warmth < 99.0) or boost > 0.0 or (item == "medkit" and bleeding)
	if not useful:
		Net.run_as(peer_id, Game.say, ["You're not hungry"])
		return false
	Game.take_slot(peer_id, index)
	health = minf(health + heal, 100.0)
	warmth = minf(warmth + warm, 100.0)
	if item == "medkit":
		bleeding = false
		_bleed_t = 0.0
	if boost > 0.0:
		boosted = true
		_boost_t = boost
	var what := "Patched up" if item == "medkit" else "Ate the %s" % Game.item_name(item).to_lower()
	if item in ["coffee", "soup"]:
		what = "Drank the %s" % Game.item_name(item).to_lower()
	Net.run_as(peer_id, Game.say, ["%s (+%d health%s)" % [what, int(heal), ", warmer" if warm > 0.0 else ""]])
	return true


## Host: [R] with the come-along unhooks it from the train.
func winch_release() -> bool:
	return Game.train != null and Game.train.release_come_along()


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


# --- Character animation (our own body and what other players see) ----------------

## Plays a one-shot action on our own body and tells the other peers (net_action, synced on change).
func _send_action(clip: String) -> void:
	if clip == "":
		return
	_action_n += 1
	net_action = "%s#%d" % [clip, _action_n]
	if body:
		body.play_action(clip)
	if clip in ["interact", "shovel", "lever", "wave"]:
		viewmodel.play(clip)  # the tool clips are played by use_tool()


## The action clip pressing [E] on `target` plays: shovelling at the furnace, hauling the lever, else a reach.
func interact_clip(target: Node) -> String:
	if target == null:
		return ""
	if target.has_meta("anim"):
		return str(target.get_meta("anim"))
	var prompt: String = target.call("get_prompt", self) if target.has_method("get_prompt") else ""
	if prompt.begins_with("Furnace"):
		return "shovel"
	if prompt.begins_with("Lever"):
		return "lever"
	return "interact"


## Changes this player's look (local player: saved by the customise menu; synced to the others through `look`).
func set_look(code: String) -> void:
	look = code


## Our own body follows what we do (the mirror shows it).
func _update_char_model(_delta: float) -> void:
	if body == null:
		return
	if look != _shown_look:
		_shown_look = look
		var a := Appearance.decode(look)
		body.apply_look(a)
		viewmodel.set_look(a)
	var s := body.anim.state
	s.speed = Vector2(velocity.x, velocity.z).length()
	s.on_floor = is_on_floor()
	s.vertical = velocity.y
	s.welding = welding
	body.set_tool(current_tool)
	body.set_carried(carried_item)
	body.set_pitch(camera.rotation.x)


# --- Update -------------------------------------------------------------------------

func _physics_process(delta: float) -> void:
	if not is_local():
		_remote_update(delta)  # NET: another peer moves this player
		return
	Net.run_as(peer_id, _local_physics, [delta])  # NET: our own feedback stays on our screen


func _local_physics(delta: float) -> void:
	_tool_cd = maxf(_tool_cd - delta, 0.0)
	if Game.is_host():
		_update_body(delta)  # NET: health, warmth, bleeding are host state
	if current_tool != ("welder" if is_instance_valid(welder_source) else held_item()):
		_apply_held()  # the slot changed (eaten up, moved in the inventory, a tool bought)

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
	if warmth < 50.0:
		speed *= 0.7
	if boosted:
		speed *= BOOST_SPEED
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
	_update_char_model(delta)


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
		Net.run_as(peer_id, _update_body, [delta])  # "you died" goes to that player
		# the torch cable is pulled out if they walked off with it
		if is_instance_valid(welder_source):
			var plug := welder_source.plug_position()
			if Vector2(global_position.x - plug.x, global_position.z - plug.z).length() > welder_source.cable_length + 6.0:
				_unplug(false)
	if _remote_body:
		var flat := Vector2(net_pos.x - _last_net_pos.x, net_pos.z - _last_net_pos.z)
		var walk := flat.length() / maxf(delta, 0.001)
		var vy := (net_pos.y - _last_net_pos.y) / maxf(delta, 0.001)
		_last_net_pos = net_pos
		_remote_body.set_look(look)
		_remote_body.set_pitch(net_pitch)
		_remote_body.set_held("hammer" if current_tool == "welder" and welder_path == "" else current_tool, carried_item)
		_remote_body.set_welding(welding)
		if net_action != _seen_action:
			_seen_action = net_action
			_remote_body.play_action(net_action.get_slice("#", 0))
		_remote_body.animate(delta, walk if walk < 20.0 else 0.0, vy if absf(vy) < 30.0 else 0.0)


func _process(_delta: float) -> void:
	if downed != _was_downed:
		_was_downed = downed  # NET: downed is host state (StateSync); show it the same way everywhere
		_update_revive_spot()
		_show_downed(downed)
	# NET: carried items and the welder torch can change on the host; refresh the hands here
	if carried_item != _shown_carry:
		_show_carry(carried_item)
	if welder_path != _seen_welder_path:
		_seen_welder_path = welder_path
		if is_local() and not Game.is_host():
			welder_source = get_node_or_null(welder_path) as WelderSource if welder_path != "" else null
			_apply_held()


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
			_send_action(interact_clip(focused))
			Net.request(focused, &"interact", [self])
	else:
		hold_progress = 0.0


## Welder (torch from a station machine): keep the player inside the cable length,
## weld whatever the torch points at while LMB is held.
func _update_welder(delta: float) -> void:
	welding = false
	if current_tool == "welder" and not is_instance_valid(welder_source):
		_apply_held()
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
		_apply_held()
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


## Downed: the camera drops to the ground and tilts (local player), the body lies down (others).
func _show_downed(on: bool) -> void:
	if is_local():
		var tw := create_tween().set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
		tw.tween_property(camera, "position:y", 0.35 if on else 1.6, 0.6)
		tw.parallel().tween_property(camera, "rotation:z", 0.5 if on else 0.0, 0.6)
		viewmodel.visible = not on
	if _remote_body:
		_remote_body.set_downed(on)
	if body:
		body.anim.state.downed = on


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
	if Net.remote_actor() != 0:
		delta = clampf(delta, 0.0, 0.2)  # NET: a client sends about 0.1 s of welding per request
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


## True near the furnace (while it burns) or in a station with the train stopped: warmth comes back fast.
func is_warm_spot() -> bool:
	var train := Game.train
	if train == null:
		return false
	if train.fuel > 0.0 and global_position.distance_to(train.furnace_position()) < WARM_RADIUS:
		return true
	# a station's shelter, with the train stopped there
	return train.current_station >= 0 and train.is_stopped() \
		and global_position.distance_to(train.cars[mini(1, train.cars.size() - 1)].global_position) < 40.0


## How cold it is where the player stands (0 = not cold, 1 = freezing wind).
func coldness() -> float:
	return maxf(1.0 if Game.wind_active else 0.0, cold_zone)


## Host: warmth, freezing, bleeding and the coffee kick. Health does not come back by itself: eat something.
func _update_body(delta: float) -> void:
	var cold := coldness()
	var warm := is_warm_spot()
	if cold > 0.0 and not warm:
		warmth = maxf(warmth - WARMTH_DRAIN * cold * delta, 0.0)
	else:
		warmth = minf(warmth + WARMTH_RECOVER * (2.0 if warm else 1.0) * delta, 100.0)
	if warmth <= 0.0:
		_lose_health(FREEZE_DAMAGE * delta)
	if bleeding:
		_bleed_t -= delta
		_lose_health(BLEED_DAMAGE * delta)
		if _bleed_t <= 0.0:
			bleeding = false
	if boosted:
		_boost_t -= delta
		if _boost_t <= 0.0:
			boosted = false


## Status effects for the HUD (small icons above the health bar).
func status_effects() -> Array[String]:
	var list: Array[String] = []
	if warmth <= 0.0:
		list.append("freezing")
	elif warmth < 50.0:
		list.append("cold")
	elif coldness() > 0.0 and not is_warm_spot():
		list.append("chilly")
	if bleeding:
		list.append("bleeding")
	if boosted:
		list.append("boost")
	if carried_item == "rail":
		list.append("heavy")
	if is_warm_spot() and warmth < 100.0:
		list.append("warming")
	return list


func take_damage(amount: float) -> void:
	if downed:
		return
	if Net.remote_actor() != 0:
		amount = clampf(amount, 0.0, 25.0)  # NET: never a negative (healing) or huge amount from a client
	amount = maxf(amount, 0.0)
	if amount >= BLEED_HIT:
		bleeding = true
		_bleed_t = BLEED_TIME
	_lose_health(amount)


func _lose_health(amount: float) -> void:
	if downed:
		return
	health = maxf(health - amount, 0.0)
	if health <= 0.0:
		if Game.take_from(peer_id, "medkit"):
			health = Game.REVIVE_HEALTH
			warmth = 100.0
			bleeding = false
			Net.run_as(peer_id, Game.say, ["A medkit saved you! (%d left)" % Game.count_in(peer_id, "medkit")])
			return
		downed = true
		bleeding = false
		_update_revive_spot()
		Net.run_as(peer_id, Game.say, ["You are down! A crewmate can revive you with a medkit [E], or reach the next station"])
		Game.on_player_downed(self)


## Host: back on their feet with `hp` health (a medkit, or the train reached a station).
func revive(hp: float) -> void:
	if not downed:
		return
	downed = false
	health = clampf(hp, 1.0, 100.0)
	warmth = 100.0
	bleeding = false
	_update_revive_spot()
	Net.run_as(peer_id, Game.say, ["You are back on your feet!"])


## The [E] target on a downed player: a crewmate with a medkit revives them.
class ReviveSpot extends Interactable:
	var target: Player

	func get_prompt(player: Node) -> String:
		if not target.downed or player == target:
			return ""
		if Game.has("medkit"):
			return "Revive %s with a medkit  [E]" % target.display_name
		return "%s is down: a medkit revives them (station shop)" % target.display_name

	func interact(player: Node) -> void:
		if not target.downed or player == target:
			return
		if not Game.take("medkit"):
			Game.say("You need a medkit to revive %s (station shop, 7 gold)" % target.display_name)
			return
		target.revive(Game.REVIVE_HEALTH)
		Game.say("You revived %s" % target.display_name)


func _update_revive_spot() -> void:
	if _revive_spot:
		_revive_spot.collision_layer = Build.LAYER_INTERACT if downed and not is_local() else 0


func respawn_on_train() -> void:
	velocity = Vector3.ZERO
	_ride_car = null
	if Game.train:
		global_position = Game.train.cars[0].global_position + Game.train.cars[0].global_basis.z * 3.0 + Vector3.UP * 2.0
