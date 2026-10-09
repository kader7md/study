class_name QuestManager
extends Node3D
## Quest maps (GDD 7): "games inside the game" that guard a locked gate's key. Main/Quest on every peer.
##
## - Every locked gate that has a quest map (MAPS) gets a QuestPortal in the overworld (in the terrain's reserved
##   QuestZone_<seg> plateau when Terrain.quest_zone() exists, else beside the gate). Its key does not lie beside
##   the track any more: it waits at the end of the quest map.
## - [hold E] on the portal (host-side, like every interaction): the whole crew enters together. Every peer builds
##   the quest map far away from the line (deterministic, the same everywhere) and moves its own player there.
## - Inside: campfire checkpoints (a player who falls off or dies is back at the last one at once), rope anchors
##   (a rope from the crew's coil makes a ladder), snacks, and the KEY at the end. Taking the key adds it to the crew
##   inventory, and after RETURN_DELAY everyone is back beside the portal; the key opens the gate as before.
## - A signpost at the start leads back without the key.
## NET: the host keeps the quest state (camp, ropes, what was taken / placed, won) and sends it whole on every change
## (_rpc_state); entering / leaving / respawns / help / snacks go to the peers by RPC on this node.

signal entered(segment: int)
signal left(segment: int, won: bool)
signal state_changed

## Segment -> quest map. The Mountain guards the mountain pass (segment 2: station 2 -> 3).
const MAPS := {2: {"title": "The Mountain", "script": "res://scripts/quest/mountain/mountain.gd"}}
const RETURN_DELAY := 4.0
## Quest maps are built this far beyond the east end of the line (out of sight of the overworld).
const ORIGIN_GAP := 5000.0
const CAMP_CHECK := 0.25

var main: Node
var active := false
var segment := -1
var map: QuestMap
var portals := {}       # segment -> QuestPortal
var camp := 0
var ropes := 0
var taken: Array[String] = []
var placed: Array[String] = []
var won := false
var hud: QuestHud
var _camp_clock := 0.0
var _leaving := false
var _origin := Vector3.INF


static func has_map(seg: int) -> bool:
	return MAPS.has(seg)


static func map_title(seg: int) -> String:
	return str(MAPS[seg].title) if MAPS.has(seg) else ""


func setup(main_node: Node) -> void:
	main = main_node
	Game.quest = self
	var track := Game.track
	for seg: int in MAPS:
		if track == null or seg >= track.gate_count():
			continue
		var portal := QuestPortal.new()
		portal.name = "Portal_%d" % seg
		portal.segment = seg
		add_child(portal)
		portal.place()
		portals[seg] = portal
	hud = QuestHud.new()
	hud.name = "QuestHud"
	hud.quest = self
	add_child(hud)
	if Net.is_online() and Net.is_host():
		Net.peer_world_ready.connect(_on_peer_world_ready)


## Where quest maps are built: beyond the east end of the line, the same on every peer.
func origin() -> Vector3:
	if _origin == Vector3.INF:
		var track := Game.track
		var hi := -INF
		var lo_z := INF
		var hi_z := -INF
		if track:
			var d := 0.0
			while d <= track.get_length():
				var p := track.point_at(d)
				hi = maxf(hi, p.x)
				lo_z = minf(lo_z, p.z)
				hi_z = maxf(hi_z, p.z)
				d += 25.0
		else:
			hi = 0.0
			lo_z = 0.0
			hi_z = 0.0
		_origin = Vector3(snappedf(hi + ORIGIN_GAP, 10.0), 0.0, snappedf((lo_z + hi_z) * 0.5, 10.0))
	return _origin


# --- Host: entering and leaving -------------------------------------------------------------

func can_enter(seg: int) -> bool:
	return not active and has_map(seg) and Game.track != null and Game.track.is_gate_locked(seg) and Game.crew_count("key") == 0


## Host: the whole crew enters segment `seg`'s quest map.
func enter(seg: int) -> bool:
	if not Game.is_host() or not can_enter(seg):
		return false
	for p: Node in get_tree().get_nodes_in_group("player"):
		if p is Player and (p as Player).downed:
			(p as Player).revive(100.0)
	var script: GDScript = load(str(MAPS[seg].script))
	var consts := script.get_script_constant_map()
	var state := {"camp": 0, "ropes": int(consts.get("START_ROPES", 0)), "taken": [], "placed": [], "won": false}
	var order := _spawn_order()
	_send(&"_rpc_enter", [seg, state, order])
	_do_enter(seg, state, order)
	return true


func _spawn_order() -> Dictionary:
	var ids: Array = []
	if Net.is_online():
		ids = Net.players.keys()
	else:
		ids = [Net.local_id()]
	ids.sort()
	var order := {}
	for i in ids.size():
		order[ids[i]] = i
	return order


## Host: everyone goes back to the portal (won = with the key).
func leave(with_key: bool) -> void:
	if not Game.is_host() or not active:
		return
	_send(&"_rpc_leave", [with_key])
	_do_leave(with_key)


func _do_enter(seg: int, state: Dictionary, order: Dictionary) -> void:
	if active and segment == seg:
		apply_state(state)
		return
	segment = seg
	active = true
	_leaving = false
	var script: GDScript = load(str(MAPS[seg].script))
	map = script.new()
	map.name = "Map_%d" % seg
	map.quest = self
	add_child(map)
	map.global_position = origin()
	map.build()
	apply_state(state)
	for p: Node in get_tree().get_nodes_in_group("player"):
		if p is Player:
			(p as Player).climber.set_enabled(true)
	var me := _local_player()
	if me:
		var index := int(order.get(Net.local_id(), 0))
		me.teleport(map.respawn_transform(camp, index))
	Game.show_banner(map.title)
	Game.say(map.intro_text())
	hud.refresh()
	entered.emit(seg)


func _do_leave(with_key: bool) -> void:
	if not active:
		return
	var seg := segment
	active = false
	for p: Node in get_tree().get_nodes_in_group("player"):
		if p is Player:
			(p as Player).climber.set_enabled(false)
	var me := _local_player()
	if me:
		var index := int(_spawn_order().get(Net.local_id(), 0))
		var portal: QuestPortal = portals.get(seg)
		if portal:
			me.teleport(portal.exit_transform(index))
		else:
			me.respawn_on_train()
	if map:
		map.queue_free()
		map = null
	segment = -1
	hud.refresh()
	if with_key:
		Game.show_banner("Back with the key!")
		Game.say("You have the key: use it on the gate's padlock %s" % Settings.key_hint("interact"))
	left.emit(seg, with_key)


func _local_player() -> Player:
	if main and main.get("player") is Player:
		return main.get("player")
	return Net.local_player()


# --- State ---------------------------------------------------------------------------------------

func state() -> Dictionary:
	return {"camp": camp, "ropes": ropes, "taken": taken.duplicate(), "placed": placed.duplicate(), "won": won}


func apply_state(s: Dictionary) -> void:
	camp = int(s.get("camp", 0))
	ropes = int(s.get("ropes", 0))
	taken.assign(s.get("taken", []))
	placed.assign(s.get("placed", []))
	won = bool(s.get("won", false))
	if map:
		map.apply_state(self)
	if hud:
		hud.refresh()
	state_changed.emit()


## Host: after any change.
func broadcast() -> void:
	_send(&"_rpc_state", [state()])
	apply_state(state())


func _send(method: StringName, args: Array) -> void:
	if not Net.is_online() or not Net.is_host():
		return
	for id in Net.ready_peers():
		if id != Net.local_id():
			callv("rpc_id", [id, method] + args)


func _on_peer_world_ready(id: int) -> void:
	# a player who (re)joined while the crew is in a quest map: build it there and send them to the last camp
	if active:
		_rpc_enter.rpc_id(id, segment, state(), {id: int(_spawn_order().get(id, 0))})


@rpc("authority", "call_remote", "reliable")
func _rpc_enter(seg: int, s: Dictionary, order: Dictionary) -> void:
	_do_enter(seg, s, order)


@rpc("authority", "call_remote", "reliable")
func _rpc_state(s: Dictionary) -> void:
	apply_state(s)


@rpc("authority", "call_remote", "reliable")
func _rpc_leave(with_key: bool) -> void:
	_do_leave(with_key)


# --- Host: things players do on the map ------------------------------------------------------------

func _process(delta: float) -> void:
	if not active or map == null or not Game.is_host():
		return
	_camp_clock -= delta
	if _camp_clock > 0.0:
		return
	_camp_clock = CAMP_CHECK
	# a campfire is reached when any player gets to its camp: everyone respawns there from now on
	for p: Node in get_tree().get_nodes_in_group("player"):
		var c := map.camp_at((p as Node3D).global_position - map.global_position)
		if c > camp:
			camp = c
			Game.say("%s reached %s: the crew respawns here now" % [(p as Player).display_name if p is Player and (p as Player).display_name != "" else "The crew", map.camp_name(c)])
			broadcast()


## Host: a rope from the crew's coil on anchor `anchor_name`.
func place_rope(anchor_name: String) -> bool:
	if anchor_name in placed:
		return false
	if ropes <= 0:
		Game.say("No rope left: rope coils lie at the camps")
		return false
	ropes -= 1
	placed.append(anchor_name)
	Game.say("Rope ladder down! Anyone can climb it without tiring (%d rope%s left)" % [ropes, "" if ropes == 1 else "s"])
	broadcast()
	return true


## Host: a pickup on the map was taken. kind: "rope" (n ropes for the crew), "snack" / "coconut" (stamina for
## the player who took it), "stew" (health).
func take_pickup(pickup_name: String, kind: String, amount: float, player: Player) -> bool:
	if pickup_name in taken:
		return false
	taken.append(pickup_name)
	match kind:
		"rope":
			ropes += int(amount)
			Game.say("+%d rope (the crew has %d)" % [int(amount), ropes])
		"stew":
			player.health = minf(player.health + amount, 100.0)
			Game.say("Warm stew: +%d health" % int(amount))
		_:
			_restore_for(player, amount)
			Game.say("Energy! Stamina restored")
	broadcast()
	return true


## Host: the key at the end of the map was taken.
func win() -> void:
	if won:
		return
	won = true
	Game.add("key")
	Game.show_banner("THE KEY IS YOURS!")
	Game.say("Got the gate key! Back to the train in a moment...")
	broadcast()
	var tree := get_tree()
	await tree.create_timer(RETURN_DELAY).timeout
	if is_inside_tree() and active:
		leave(true)


## Host: player `p` died on the map: back at the last camp with full health.
func on_player_died(p: Player) -> bool:
	if not active or map == null:
		return false
	p.health = 100.0
	p.frost = 0.0
	Net.run_as(p.peer_id, Game.say, ["You fell! Back at %s" % map.camp_name(camp)])
	if p.is_local():
		_respawn_local()
	else:
		_rpc_respawn.rpc_id(p.peer_id)
	return true


## Local player: off the map (the sea, below the kill height): back to the last camp.
func check_local_player(p: Player) -> void:
	if map == null:
		return
	var local := p.global_position - map.global_position
	var delta := get_physics_process_delta_time()
	p.climber.drain_factor = map.drain_factor(local)
	var rate := map.cold_rate(local)
	p.climber.cold = clampf(p.climber.cold + rate * delta, 0.0, 1.0)
	p.climber.ice = p.is_on_floor() and map.ice_at(local)
	if map.is_out(local):
		Game.say("Lost! Back at %s" % map.camp_name(camp))
		Net.request(p, &"take_damage", [10.0])
		_respawn_local()


func _respawn_local() -> void:
	var me := _local_player()
	if me and map:
		var index := int(_spawn_order().get(Net.local_id(), 0))
		me.teleport(map.respawn_transform(camp, index))
		me.climber.restore(100.0)


@rpc("authority", "call_remote", "reliable")
func _rpc_respawn() -> void:
	_respawn_local()


## Host: `helper` aimed at `target` and pressed [E]: pull them up (hanging) or give them a boost.
func help(target: Player, helper: Player) -> bool:
	if not active or target == helper:
		return false
	var kind := "pull" if target.is_hanging or (target.is_climbing and target.global_position.y < helper.global_position.y - 0.8) else "boost"
	Net.run_as(helper.peer_id, Game.say, ["You %s %s" % ["pulled up" if kind == "pull" else "boosted", target.display_name]])
	if target.is_local():
		target.climber.receive_help(kind, helper.global_position)
	else:
		_rpc_help.rpc_id(target.peer_id, kind, helper.global_position)
	return true


@rpc("authority", "call_remote", "reliable")
func _rpc_help(kind: String, helper_pos: Vector3) -> void:
	var me := _local_player()
	if me:
		me.climber.receive_help(kind, helper_pos)


func _restore_for(p: Player, amount: float) -> void:
	if p.is_local():
		p.climber.restore(amount)
	else:
		_rpc_restore.rpc_id(p.peer_id, amount)


@rpc("authority", "call_remote", "reliable")
func _rpc_restore(amount: float) -> void:
	var me := _local_player()
	if me:
		me.climber.restore(amount)


# --- Texts -------------------------------------------------------------------------------------------

func objective() -> String:
	if map == null:
		return ""
	return map.objective(self)


## The objective while the train waits at the locked gate of a quest segment.
func gate_objective(seg: int) -> String:
	return "Gate locked: win its key on %s (the trailhead beside the gate, hold %s)" % [map_title(seg), Settings.key_hint("interact")]


## Test helper: completes the quest as if the crew reached the key.
func debug_win() -> void:
	if map and map.has_method("key_node"):
		var k: Node = map.call("key_node")
		if k:
			k.call("interact", _local_player())
			return
	win()
