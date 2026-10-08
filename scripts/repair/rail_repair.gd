class_name RailRepair
extends Node3D
## A broken piece of track, rebuilt by hand together. Free building, no ghost slots:
##   1. Carry PLANKS and place them where you aim (they snap to the 4 sleeper positions).
##      - On solid ground a plank rests on the ground, so bumpy ground (meteor craters) TILTS it.
##        Nail it down with the hammer (2 nails); tap it with the hammer to level it.
##      - Over a river there is no ground: a plank needs a supported plank next to it (or the intact
##        track) and must be JOINED to it with the NAIL GUN. Planks build out into a platform.
##        A plank with nothing to rest on falls into the water.
##   2. Carry RAILS onto the planks (a rail needs at least 3 of the 4 planks under it).
##   3. Bolt the fishplates at both ends of each rail (hammer / nail gun).
## The finished track keeps the average TILT of its planks (+ sag for missing planks). A badly built piece shakes
## the train (wheel wear) or, above Train.TIP_ROLL degrees, tips it over sideways.

const SLOTS := [-1.5, -0.5, 0.5, 1.5]     # local z of the 4 sleepers in this 4 m piece
const GROUND_REACH := 0.7                 # ground this close under the sleepers holds a plank up
const LEVEL_STEP := 2.0                   # degrees levelled per hammer tap
const SAG_PER_MISSING := 4.0              # extra tilt for each missing plank under the rails

var track: Track
var index := 0
var cratered := false
var planks := {}                          # slot -> {node, roll, grounded, fixed}
var _bumps: Array[float] = [0.0, 0.0, 0.0, 0.0]
var _rail_slots: Array[PlaceSlot] = []
var _rails_placed := 0
var _bolts_left := 4
var _label: Label3D
var _area: BuildArea
var _ghost: MeshInstance3D
var _ghost_mat := StandardMaterial3D.new()


## Invisible box over the gap that the player aims at while carrying a plank.
class BuildArea extends Interactable:
	var repair: RailRepair

	func get_prompt(player: Node) -> String:
		return repair.area_prompt(player)

	func interact(player: Node) -> void:
		repair.area_interact(player)


func setup(t: Track, piece_index: int, is_cratered := false) -> void:
	track = t
	index = piece_index
	cratered = is_cratered


func _ready() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = index * 7919
	if cratered:
		for k in 4:
			_bumps[k] = rng.randf_range(-12.0, 12.0)
	_label = Build.label(self, "", Vector3(0, 2.0, 0), 40)
	_area = BuildArea.new()
	_area.repair = self
	Build.collider(_area, Vector3(3.2, 2.2, Track.PIECE_LENGTH), Vector3(0, -0.9, 0))
	add_child(_area)
	_ghost = MeshInstance3D.new()
	var gm := BoxMesh.new()
	gm.size = Vector3(2.4, 0.12, 0.3)
	_ghost.mesh = gm
	_ghost_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_ghost_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_ghost.material_override = _ghost_mat
	_ghost.visible = false
	add_child(_ghost)
	for side in 2:
		var x := (side - 0.5) * Track.GAUGE
		var slot := PlaceSlot.create(self, "rail", Vector3(x, Track.RAIL_Y, 0), Vector3(0.45, 0.45, Track.PIECE_LENGTH - 0.6), Props.instance("rail"))
		slot.enabled = false
		slot.hint = "A rail needs planks under it (at least 3 of 4, nailed or joined)"
		slot.placed.connect(_on_rail_placed.bind(x))
		_rail_slots.append(slot)
	_update()


# --- Planks ------------------------------------------------------------------------

func slot_distance(k: int) -> float:
	return track.piece_center(index) - SLOTS[k]  # local -Z points forward (bigger distance)


## Ground under sleeper k: {"has": bool, "roll": degrees}.
func ground_under(k: int) -> Dictionary:
	var d := slot_distance(k)
	var ty := track.point_at(d).y
	var left := track.ground_height(d, -1.2) - ty
	var right := track.ground_height(d, 1.2) - ty
	var has := maxf(left, right) > Track.SLEEPER_Y - 0.06 - GROUND_REACH
	var roll := rad_to_deg(atan2(right - left, 2.4)) + _bumps[k]
	return {"has": has, "roll": roll}


func is_supported(k: int) -> bool:
	if k < 0:
		return not track.is_broken(index - 1)
	if k > 3:
		return not track.is_broken(index + 1)
	return planks.has(k) and planks[k].fixed


func has_support_neighbour(k: int) -> bool:
	# slot 0 is at local z -1.5 (the forward end, next piece), slot 3 the back end (previous piece)
	var fwd := is_supported(k - 1) if k > 0 else not track.is_broken(index + 1)
	var back := is_supported(k + 1) if k < 3 else not track.is_broken(index - 1)
	return fwd or back


## Which sleeper position the player is aiming at, or -1.
func slot_from_aim(player: Node) -> int:
	var hit: Vector3 = player.aim_point() if player.has_method("aim_point") else Vector3.INF
	if hit == Vector3.INF:
		return -1
	var z := to_local(hit).z
	var best := -1
	var best_d := INF
	for k in 4:
		var dz := absf(z - SLOTS[k])
		if not planks.has(k) and dz < best_d:
			best = k
			best_d = dz
	return best


## What happens if a plank is placed at k: "ground", "join" (needs nail gun) or "fall".
func placement_kind(k: int) -> String:
	if ground_under(k).has:
		return "ground"
	if has_support_neighbour(k):
		return "join"
	return "fall"


func place_plank(k: int, player: Node) -> String:
	if k < 0 or planks.has(k) or player == null or player.carried_item != "plank":
		return ""
	var kind := placement_kind(k)
	player.consume_carried()
	if kind == "fall":
		_drop_plank(k)
		Game.say("The plank fell into the river! Over water, join planks to a supported neighbour.")
		return kind
	var roll: float = ground_under(k).roll if kind == "ground" else randf_range(-1.5, 1.5)
	var node := Props.instance("plank")
	node.position = Vector3(0, Track.SLEEPER_Y, SLOTS[k])
	node.rotation.z = deg_to_rad(roll)
	add_child(node)
	var spot := PlankSpot.new()
	spot.repair = self
	spot.slot = k
	Build.collider(spot, Vector3(2.4, 0.25, 0.4), Vector3.ZERO)
	spot.collision_layer = 0  # only aimable once fixed (so hammer hits go to the nails first)
	node.add_child(spot)
	planks[k] = {"node": node, "roll": roll, "grounded": kind == "ground", "fixed": false, "left": 0, "spot": spot}
	if kind == "ground":
		planks[k].left = 2
		for x in [-0.95, 0.95]:
			var nail := NailSpot.new()
			nail.position = Vector3(x, 0.02, 0)
			node.add_child(nail)
			nail.done.connect(_on_fastened.bind(k))
	else:
		planks[k].left = 1
		var joint := NailSpot.new()
		joint.require_tool = "nail_gun"
		joint.position = Vector3(0.0, 0.02, -0.25 if not has_support_neighbour_back(k) else 0.25)
		node.add_child(joint)
		joint.done.connect(_on_fastened.bind(k))
		Game.say("Plank over the water: join it to its neighbour with the NAIL GUN")
	_update()
	return kind


func has_support_neighbour_back(k: int) -> bool:
	return is_supported(k + 1) if k < 3 else not track.is_broken(index - 1)


func _on_fastened(k: int) -> void:
	planks[k].left -= 1
	if planks[k].left <= 0:
		planks[k].fixed = true
		if planks[k].grounded:
			planks[k].spot.collision_layer = Build.LAYER_INTERACT
	_update()


## Hammer tap on a nailed grounded plank: levels it a bit.
func level_plank(k: int) -> bool:
	if not planks.has(k) or not planks[k].grounded:
		return false
	var roll: float = planks[k].roll
	if absf(roll) < 0.5:
		return false
	roll = move_toward(roll, 0.0, LEVEL_STEP)
	planks[k].roll = roll
	planks[k].node.rotation.z = deg_to_rad(roll)
	_update()
	return true


func _drop_plank(k: int) -> void:
	var body := RigidBody3D.new()
	body.collision_layer = Build.LAYER_DEBRIS
	body.collision_mask = Build.LAYER_WORLD | Build.LAYER_DEBRIS
	get_parent().add_child(body)
	body.global_transform = global_transform.translated_local(Vector3(0, Track.SLEEPER_Y, SLOTS[k]))
	body.add_child(Props.instance("plank"))
	Build.collider(body, Vector3(2.4, 0.12, 0.3), Vector3.ZERO)
	body.angular_velocity = Vector3(randf_range(-2, 2), 0, randf_range(-2, 2))
	get_tree().create_timer(20.0).timeout.connect(body.queue_free)


func fixed_count() -> int:
	var n := 0
	for k in planks:
		if planks[k].fixed:
			n += 1
	return n


## Average tilt of the supporting planks plus sag for missing ones (degrees, signed).
func build_roll() -> float:
	var total := 0.0
	var n := 0
	for k in planks:
		if planks[k].fixed:
			total += planks[k].roll
			n += 1
	var avg := total / n if n > 0 else 0.0
	return avg + signf(avg if avg != 0.0 else 1.0) * SAG_PER_MISSING * (4 - n)


# --- Rails and bolts -------------------------------------------------------------------

func _on_rail_placed(_player: Node, x: float) -> void:
	var rail := Props.instance("rail")
	rail.position = Vector3(x, Track.RAIL_Y + 0.4, 0)
	rail.rotation.z = deg_to_rad(build_roll())
	add_child(rail)
	create_tween().tween_property(rail, "position:y", Track.RAIL_Y + x * tan(deg_to_rad(build_roll())), 0.2).set_trans(Tween.TRANS_BOUNCE).set_ease(Tween.EASE_OUT)
	_rails_placed += 1
	for z in [-Track.PIECE_LENGTH * 0.5 + 0.25, Track.PIECE_LENGTH * 0.5 - 0.25]:
		var bolt := NailSpot.new()
		bolt.style = "bolt"
		bolt.position = Vector3(x + (0.06 if x > 0 else -0.06), Track.RAIL_Y, z)
		if x < 0:
			bolt.rotation.y = PI
		add_child(bolt)
		bolt.done.connect(_on_bolted)
	_update()


func _on_bolted() -> void:
	_bolts_left -= 1
	_update()
	if _bolts_left == 0:
		var roll := build_roll()
		var quality := "solid" if absf(roll) < Train.BUMP_ROLL else ("bumpy" if absf(roll) < Train.TIP_ROLL else "DANGEROUS (the train will tip over!)")
		Game.say("Track rebuilt: tilt %.1f° (%s)" % [absf(roll), quality])
		Game.add_stat("repairs")
		track.repair_piece.call_deferred(index, roll)


func step() -> int:
	if fixed_count() < 3:
		return 1
	if _rails_placed < 2:
		return 2
	return 3


func _update() -> void:
	var rails_ok := fixed_count() >= 3
	for slot in _rail_slots:
		if is_instance_valid(slot):
			slot.enabled = rails_ok
	var lines := ["BROKEN TRACK"]
	match step():
		1: lines.append("1/3 Planks: %d/4 fixed (need 3+)" % fixed_count())
		2: lines.append("2/3 Rails: %d/2   (tilt %.1f°)" % [_rails_placed, absf(build_roll())])
		3: lines.append("3/3 Bolt the joints (%d left)   (tilt %.1f°)" % [_bolts_left, absf(build_roll())])
	_label.text = "\n".join(lines)


# --- Aiming with a plank: prompt and ghost preview ---------------------------------------

func area_prompt(player: Node) -> String:
	if player and player.carried_item == "plank":
		var k := slot_from_aim(player)
		if k < 0:
			return "All 4 planks are placed"
		match placement_kind(k):
			"ground":
				return "Place plank on the ground (tilt %.0f°)  [E]" % absf(ground_under(k).roll)
			"join":
				return "Place plank over the water, then join it with the NAIL GUN  [E]"
			_:
				return "Nothing to hold this plank: it will FALL. Build out from a supported plank"
	if player and player.carried_item == "rail" and fixed_count() < 3:
		return "Rails need at least 3 planks under them first"
	return "Broken track: bring planks from the cargo car (%d/4 placed)" % planks.size()


func area_interact(player: Node) -> void:
	if player and player.carried_item == "plank":
		place_plank(slot_from_aim(player), player)


func _process(_delta: float) -> void:
	var show := false
	for p in get_tree().get_nodes_in_group("player"):
		if p.carried_item == "plank" and p.focused == _area:
			var k := slot_from_aim(p)
			if k >= 0:
				show = true
				var kind := placement_kind(k)
				_ghost.position = Vector3(0, Track.SLEEPER_Y, SLOTS[k])
				_ghost.rotation.z = deg_to_rad(ground_under(k).roll) if kind == "ground" else 0.0
				_ghost_mat.albedo_color = {"ground": Color(0.3, 1, 0.4, 0.45), "join": Color(1, 0.9, 0.2, 0.45), "fall": Color(1, 0.2, 0.15, 0.45)}[kind]
	_ghost.visible = show


## Debug/test helper: finishes the whole repair instantly (perfectly level). Counts as a rebuilt piece.
func finish_instantly() -> void:
	Game.add_stat("repairs")
	track.repair_piece(index, 0.0)


## A placed plank: hammer taps level it (once nailed).
class PlankSpot extends Interactable:
	var repair: RailRepair
	var slot := 0

	func get_prompt(_player: Node) -> String:
		var p: Dictionary = repair.planks[slot]
		if not p.fixed:
			return "Plank: %s" % ("nail it down (hammer on the nails)" if p.grounded else "join it with the NAIL GUN")
		if p.grounded and absf(p.roll) >= 0.5:
			return "Plank tilted %.0f°: tap it with the hammer [LMB] to level it" % absf(p.roll)
		return "Plank fixed (tilt %.0f°)" % absf(p.roll)

	func on_tool_hit(tool: String, _player: Node) -> bool:
		if tool == "hammer" and repair.planks[slot].fixed:
			return repair.level_plank(slot)
		return false
