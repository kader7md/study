class_name Climber
extends Node
## Climbing, stamina and fall damage for a Player (child "Climber"). Only active while `enabled` (inside a quest map
## such as The Mountain): the overworld plays exactly as before.
##
## - Hold [climb] (RMB by default) facing a steep surface: you grab it and move on it with WASD. Climbing drains
##   stamina (holding still drains less); in a chimney (two close walls) much less; on a rope ladder nothing.
## - [Jump] while climbing: a lunge upwards (costs stamina), or with [S] held: push off the wall.
## - Reaching the top edge mantles you onto the ledge. In the air, hold [climb] near a wall to jump-grab it.
## - Out of stamina on a wall you HANG for a few seconds (a crewmate can pull you up [E]), then you fall.
## - Sprinting drains stamina too; standing on the ground recovers it. Cold (the snow up high) lowers max stamina.
## - Falling more than FALL_SAFE metres hurts (Player.take_fall, run on the host).
## The Player exposes is_climbing / is_hanging / stamina / max_stamina (synced to other peers for animations
## and the "pull up" prompt). Movement is client-side like all player movement; damage goes through Net.request.

const CLIMB_SPEED := 2.0
const SIDE_SPEED := 1.7
const LADDER_SPEED := 3.0
const MAX_STAMINA := 100.0
const DRAIN_MOVE := 8.0
const DRAIN_HOLD := 3.0
const DRAIN_SPRINT := 9.0
const REGEN := 24.0
const REGEN_DELAY := 0.6
const GRAB_COST := 4.0
const LUNGE_COST := 16.0
const LUNGE_SPEED := 6.5
const CHIMNEY_FACTOR := 0.35
const HANG_TIME := 4.0
const REGRAB_DELAY := 1.0
const REACH := 1.2
const MANTLE_SPEED := 6.0
## Steepest normal.y that still counts as a wall (about 44 degrees and steeper), and the most overhanging one.
const WALL_MAX_NY := 0.72
const WALL_MIN_NY := -0.45
const FALL_SAFE := 7.0
const FALL_DAMAGE_PER_M := 5.5
## Cold: max stamina loses up to this much in the snow.
const COLD_LOSS := 45.0

var player: Player
var enabled := false
var wall_normal := Vector3.ZERO
var cold := 0.0
## Standing on ice (from the quest map): slippery walking.
var ice := false
## Multiplier from the quest map at the player's spot (chimney 0.35, 1 elsewhere).
var drain_factor := 1.0

var _hang_left := 0.0
var _regrab := 0.0
var _lunge := 0.0
var _rest := 0.0
var _peak_y := -INF
var _was_floor := true
var _mantle_target := Vector3.INF
var _mantle_t := 0.0
var _ladder: Node3D
var _boost_grace := 0.0
var _query := PhysicsRayQueryParameters3D.new()


func setup(p: Player) -> void:
	player = p
	_query.collision_mask = Build.LAYER_WORLD
	_query.exclude = [p.get_rid()]


func set_enabled(on: bool) -> void:
	enabled = on
	reset()


func reset() -> void:
	_stop()
	_hang_left = 0.0
	_ladder = null
	_mantle_target = Vector3.INF
	cold = 0.0
	player.max_stamina = MAX_STAMINA
	player.stamina = MAX_STAMINA
	_peak_y = -INF


## Teleported (respawn, quest enter / leave): forget the fall height.
func on_teleport() -> void:
	_stop()
	_ladder = null
	_mantle_target = Vector3.INF
	_peak_y = -INF
	_was_floor = true


func _stop() -> void:
	if player:
		player.is_climbing = false
		player.is_hanging = false


## Called by the local Player before its normal walking code. Returns true when this frame's movement was done here.
func step(delta: float, input: Vector2, wants_jump: bool) -> bool:
	if not enabled:
		return false
	var p := player
	_regrab = maxf(_regrab - delta, 0.0)
	_boost_grace = maxf(_boost_grace - delta, 0.0)
	p.max_stamina = MAX_STAMINA - COLD_LOSS * cold
	p.stamina = minf(p.stamina, p.max_stamina)
	if _mantle_target != Vector3.INF:
		_do_mantle(delta)
		return true
	var holding := Input.is_action_pressed("climb") and not Game.ui_open and not p.downed and p.carried_item == ""
	# rope ladders: no stamina
	if _ladder == null and (holding or input.y < -0.1):
		_ladder = _find_ladder()
	if _ladder:
		return _ladder_step(delta, input, wants_jump)
	if _lunge > 0.0:
		_lunge -= delta
		return false  # flying up from a lunge: normal gravity, re-grab after
	if p.is_climbing:
		if not holding and not p.is_hanging:
			_stop()
			_regrab = 0.2
			return false
		return _climb_step(delta, input, wants_jump)
	if ice and not p.is_climbing and p.is_on_floor() and not holding:
		_ice_step(delta, input, wants_jump)
		return true
	# start climbing: facing a steep surface, holding the climb key, with some stamina
	if holding and _regrab <= 0.0 and p.stamina > GRAB_COST:
		var fwd := -p.global_basis.z
		fwd.y = 0.0
		var hit := _wall_probe(fwd.normalized(), 1.1)
		if hit.is_empty():
			hit = _wall_probe(fwd.normalized(), 0.5)
		if not hit.is_empty():
			p.is_climbing = true
			wall_normal = hit.normal
			_peak_y = -INF
			p.stamina -= GRAB_COST if not p.is_on_floor() else 0.0
			p.velocity = Vector3.ZERO
			return _climb_step(delta, input, false)
	return false


## Called after the Player moved (walking / falling): stamina for sprinting and resting, fall damage.
func post_move(delta: float, moving: bool, sprinting: bool) -> void:
	if not enabled:
		return
	var p := player
	var floor := p.is_on_floor()
	if p.is_climbing or _ladder:
		_peak_y = -INF
	elif not floor:
		_peak_y = maxf(_peak_y, p.global_position.y)
	elif not _was_floor and _peak_y > -INF:
		var drop := _peak_y - p.global_position.y
		_peak_y = -INF
		if drop > FALL_SAFE and _boost_grace <= 0.0:
			var dmg := (drop - FALL_SAFE) * FALL_DAMAGE_PER_M
			Game.say("Ouch! A %d m fall" % int(drop))
			Net.request(p, &"take_fall", [dmg])
	if floor:
		_peak_y = -INF
	_was_floor = floor
	if p.is_climbing or _ladder:
		return
	if sprinting and moving and floor:
		p.stamina = maxf(p.stamina - DRAIN_SPRINT * delta, 0.0)
		_rest = 0.0
	elif floor:
		_rest += delta
		if _rest >= REGEN_DELAY:
			p.stamina = minf(p.stamina + REGEN * delta, p.max_stamina)
	else:
		_rest = 0.0


## Walking on ice: slow to speed up and to stop, and the slope pulls you downhill.
func _ice_step(delta: float, input: Vector2, wants_jump: bool) -> void:
	var p := player
	var want := (p.transform.basis * Vector3(input.x, 0, input.y)).normalized() * Player.WALK
	var hv := Vector3(p.velocity.x, 0.0, p.velocity.z).lerp(want, clampf(1.6 * delta, 0.0, 1.0))
	var n := p.get_floor_normal()
	hv += Vector3(n.x, 0.0, n.z) * 9.0 * delta
	p.velocity = Vector3(hv.x, p.velocity.y, hv.z)
	if wants_jump:
		p.velocity.y = Player.JUMP
	p.move_and_slide()
	post_move(delta, input.length() > 0.1, false)


func can_sprint() -> bool:
	return not enabled or player.stamina > 1.0


# --- Climbing ------------------------------------------------------------------------------------

func _climb_step(delta: float, input: Vector2, wants_jump: bool) -> bool:
	var p := player
	var n := wall_normal
	var into := -Vector3(n.x, 0.0, n.z).normalized() if Vector2(n.x, n.z).length() > 0.05 else -p.global_basis.z
	var chest := _wall_probe(into, 1.1, 1.3)
	var feet := _wall_probe(into, 0.4, 1.3)
	var head := _wall_probe(into, 1.75, 1.3)
	if chest.is_empty() and feet.is_empty():
		_stop()
		_regrab = 0.3
		return false
	if not chest.is_empty():
		n = chest.normal
	elif not feet.is_empty():
		n = feet.normal
	wall_normal = wall_normal.slerp(n, clampf(delta * 10.0, 0.0, 1.0)).normalized() if wall_normal.length() > 0.5 else n
	n = wall_normal
	# out of stamina: hang, then fall
	if p.is_hanging:
		_hang_left -= delta
		p.velocity = -n * 0.5
		p.move_and_slide()
		if _hang_left <= 0.0 or not Input.is_action_pressed("climb"):
			_stop()
			_regrab = REGRAB_DELAY
			Game.say("Your grip gave out!")
		return true
	var moving := input.length() > 0.1
	var drain := (DRAIN_MOVE if moving else DRAIN_HOLD) * drain_factor
	p.stamina = maxf(p.stamina - drain * delta, 0.0)
	if p.stamina <= 0.0:
		p.is_hanging = true
		_hang_left = HANG_TIME
		Game.say("Out of stamina! Hold on: a crewmate can pull you up %s" % Settings.key_hint("interact"))
		return true
	# top edge: the head is above the wall while the chest still touches it -> mantle onto the ledge
	if input.y < -0.1 and head.is_empty():
		var ledge := _find_ledge(into)
		if ledge != Vector3.INF:
			_mantle_target = ledge
			_mantle_t = 0.0
			_stop()
			return true
	if wants_jump:
		if input.y > 0.1:
			_stop()
			_regrab = 0.5
			p.velocity = n * 4.0 + Vector3.UP * 3.0
			p.move_and_slide()
			return true
		if p.stamina >= LUNGE_COST:
			p.stamina -= LUNGE_COST
			_stop()
			_lunge = 0.35
			var up := (Vector3.UP - n * n.dot(Vector3.UP)).normalized()
			p.velocity = up * LUNGE_SPEED + n * 0.3
			p.move_and_slide()
			return true
	var up_dir := (Vector3.UP - n * n.dot(Vector3.UP))
	up_dir = up_dir.normalized() if up_dir.length() > 0.05 else Vector3.UP
	var side := up_dir.cross(n).normalized()
	var v := up_dir * (-input.y) * CLIMB_SPEED + side * input.x * SIDE_SPEED
	# stay close to the wall
	var dist := float(chest.get("distance", 0.5)) if not chest.is_empty() else float(feet.get("distance", 0.5))
	v += -n * clampf((dist - 0.35) * 4.0, -1.0, 2.5)
	p.velocity = v
	p.move_and_slide()
	# climbing down onto the ground: let go
	if input.y > 0.1 and p.is_on_floor():
		_stop()
		_regrab = 0.4
	return true


## Ray along `dir` from `height` above the feet; a climbable hit -> {normal, distance, position}, else {}.
func _wall_probe(dir: Vector3, height: float, reach := REACH) -> Dictionary:
	var from := player.global_position + Vector3.UP * height
	_query.from = from
	_query.to = from + dir * reach
	var hit := player.get_world_3d().direct_space_state.intersect_ray(_query)
	if hit.is_empty():
		return {}
	var n: Vector3 = hit.normal
	if n.y > WALL_MAX_NY or n.y < WALL_MIN_NY:
		return {}
	return {"normal": n, "distance": from.distance_to(hit.position), "position": hit.position}


## A standable spot just over the top edge in front of us, or INF.
func _find_ledge(into: Vector3) -> Vector3:
	for fwd: float in [0.7, 1.1, 1.6]:
		var top := player.global_position + into * fwd + Vector3.UP * 2.6
		_query.from = top
		_query.to = top + Vector3.DOWN * 2.6
		var hit := player.get_world_3d().direct_space_state.intersect_ray(_query)
		if not hit.is_empty() and hit.normal.y > 0.7:
			return hit.position + Vector3.UP * 0.05
	return Vector3.INF


func _do_mantle(delta: float) -> void:
	var p := player
	_mantle_t += delta
	var pos := p.global_position
	# first up, then over the edge
	if pos.y < _mantle_target.y + 0.15:
		pos.y = minf(pos.y + MANTLE_SPEED * delta, _mantle_target.y + 0.15)
	else:
		var flat := Vector3(_mantle_target.x - pos.x, 0.0, _mantle_target.z - pos.z)
		var stepv := minf(flat.length(), 3.5 * delta)
		pos += flat.normalized() * stepv if flat.length() > 0.001 else Vector3.ZERO
		if flat.length() < 0.05:
			_mantle_target = Vector3.INF
	p.global_position = pos
	p.velocity = Vector3.ZERO
	if _mantle_t > 4.0:
		_mantle_target = Vector3.INF
	if _mantle_target == Vector3.INF:
		_peak_y = -INF


# --- Rope ladders ------------------------------------------------------------------------------

func _find_ladder() -> Node3D:
	for l: Node in player.get_tree().get_nodes_in_group("quest_ladder"):
		var ladder := l as Node3D
		if ladder.has_method("grab_distance") and ladder.call("grab_distance", player.global_position) < 0.9:
			return ladder
	return null


func _ladder_step(delta: float, input: Vector2, wants_jump: bool) -> bool:
	var p := player
	var lad := _ladder
	if wants_jump or lad == null or not is_instance_valid(lad):
		_ladder = null
		return false
	var bottom: Vector3 = lad.get("bottom")
	var top: Vector3 = lad.get("top")
	var off: Vector3 = lad.get("offset")
	var axis := (top - bottom)
	var t := clampf((p.global_position - off - bottom).dot(axis) / axis.length_squared(), 0.0, 1.0)
	var on_line := bottom + axis * t + off
	if p.global_position.distance_to(on_line) > 1.6:
		_ladder = null
		return false
	if t >= 0.97 and input.y < -0.1:
		_mantle_target = lad.get("exit")
		_mantle_t = 0.0
		_ladder = null
		return true
	if t <= 0.02 and input.y > 0.1:
		_ladder = null
		return false
	# kinematic along the rope (the cliff behind it can't snag you)
	var v := axis.normalized() * (-input.y) * LADDER_SPEED
	var next := p.global_position + v * delta
	var along := clampf((next - off - bottom).dot(axis) / axis.length_squared(), 0.0, 1.0)
	next = next.lerp(bottom + axis * along + off, clampf(8.0 * delta, 0.0, 1.0))
	p.global_position = next
	p.velocity = Vector3.ZERO
	p.is_climbing = true
	p.is_hanging = false
	return true


# --- Help from a crewmate (sent by the host) -----------------------------------------------------

## "pull": a crewmate standing above pulls us up next to them. "boost": a leg-up from a crewmate beside us.
func receive_help(kind: String, helper_pos: Vector3) -> void:
	var p := player
	if kind == "pull":
		_stop()
		_ladder = null
		var to := helper_pos + (p.global_position - helper_pos) * Vector3(1, 0, 1)
		to = helper_pos + (to - helper_pos).normalized() * 0.9 if (to - helper_pos).length() > 0.1 else helper_pos + Vector3(0.9, 0, 0)
		_mantle_target = Vector3(to.x, helper_pos.y + 0.05, to.z)
		_mantle_t = 0.0
		p.stamina = maxf(p.stamina, 40.0)
		Game.say("Pulled up by a crewmate!")
	else:
		_stop()
		p.velocity = Vector3.UP * 8.5 + (-p.global_basis.z) * 1.5
		_boost_grace = 2.0
		_regrab = 0.0
		p.stamina = minf(p.stamina + 25.0, p.max_stamina)
		Game.say("Boosted up by a crewmate! Grab the wall %s" % Settings.key_hint("climb"))


func restore(amount: float) -> void:
	player.stamina = minf(player.stamina + amount, player.max_stamina)
	if player.is_hanging:
		player.is_hanging = false
