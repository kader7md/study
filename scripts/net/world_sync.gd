class_name WorldSync
extends Node
## Host -> clients replication of one running world (a child of Main, online only; Net adds it).
## Every peer builds the same world from Main.SEED, so only CHANGES travel:
##   snapshot, 20 Hz, unreliable: train (distance, speed, lever, fuel, body / engine / chassis, wheel wear + state,
##     tipped + tip angle, current station, come-along hook / anchor), wind, next station, sabotage cooldowns.
##   extras, 20 Hz, unreliable, in packets of a few: the moving zombies, eagles, fallen panels and anchor points, which
##     clients show as puppets (only what moved, plus everything once a second); reliable "gone" when one disappears.
##   events, reliable: rail pieces broken / repaired (index, cratered, roll), each RailRepair's build state, train cover
##     pieces (off / placed / nails and welds / doors), pickups taken, inventory, station reached, meteors, gates,
##     objective and the end-of-run stats.
## A client that finished loading gets everything once (send_full_state), then the stream.
## Client-side, the train only interpolates (Train skips its simulation when not host).

const SNAPSHOT_RATE := 20.0
const STATE_RATE := 8.0
const DYN_ZOMBIE := 0
const DYN_EAGLE := 1
const DYN_FALLEN := 2
const DYN_ANCHOR := 3
const DYN_PER_PACKET := 8     # keeps every packet under the MTU

var main: Node
var track: Track
var train: Train
var _host := false
var _snap_clock := 0.0
var _state_clock := 0.0
var _inventory_dirty := false
var _repair_sent := {}      # piece index -> last sent state (as text)
var _part_sent := {}        # part index -> last sent state (as text)
var _gone: Array[String] = []   # host: pickups and keys taken (paths relative to Main)
var _dynamic: Array = []        # host: named zombies, eagles, fallen panels, anchors (may hold freed ones)
var _counter := 0
var _hooks: Array[Node] = []
var _dyn_sent := {}         # host: extra name -> last sent position
var _dyn_key_clock := 0.0
# client
var _snap_distance := 0.0
var _snap_speed := 0.0
var _snap_age := 0.0
var _has_snap := false
var _puppets := {}          # name -> {"node": Node3D, "pos": Vector3, "rot": Quaternion}


func setup(main_node: Node) -> void:
	main = main_node
	track = Game.track
	train = Game.train
	_host = Net.is_host()
	process_physics_priority = -10  # before Train, so the cars use this frame's distance
	name_tree(main)
	if train:
		_hooks.assign(train.cars[0].find_children("*", "HookSpot", true, false))
	if _host:
		track.piece_broken.connect(_on_piece_broken)
		track.piece_repaired.connect(_on_piece_repaired)
		track.gate_opened.connect(_on_gate_opened)
		Game.inventory_changed.connect(func(): _inventory_dirty = true)
		Game.station_reached.connect(_on_station_reached)
		Game.run_finished.connect(_on_run_finished)
		Game.objective_changed.connect(_on_objective_changed)
		main.child_entered_tree.connect(_on_main_child)


## Gives every auto-named node ("@Area3D@123") a name that is the same on every peer: "<Class>_<n>" by order among its
## siblings. The world is built in the same order everywhere, so a client and the host agree on every path.
static func name_tree(root: Node) -> void:
	var counts := {}
	for c in root.get_children():
		if c is Player or c is MultiplayerSpawner or c is WorldSync:
			continue
		if String(c.name).begins_with("@"):
			var cls := c.get_class()
			var k: int = counts.get(cls, 0)
			counts[cls] = k + 1
			c.name = "%s_%d" % [cls, k]
		name_tree(c)


func _send(method: StringName, args: Array = []) -> void:
	for id in Net.ready_peers():
		callv("rpc_id", [id, method] + args)


# --- Host: stream ---------------------------------------------------------------------

func _physics_process(delta: float) -> void:
	if _host:
		_host_tick(delta)
	else:
		_client_tick(delta)


func _host_tick(delta: float) -> void:
	if _inventory_dirty:
		_inventory_dirty = false
		_send(&"_rpc_inventory", [Game.inventory])
	_snap_clock += delta
	if _snap_clock >= 1.0 / SNAPSHOT_RATE:
		_snap_clock = 0.0
		var snap := snapshot()
		var extras := _extras_packets(delta)
		for id in Net.ready_peers():
			_rpc_snapshot.rpc_id(id, snap)
			for packet in extras:
				_rpc_extras.rpc_id(id, packet)
	_state_clock += delta
	if _state_clock >= 1.0 / STATE_RATE:
		_state_clock = 0.0
		_poll_repairs(false)
		_poll_parts(false)


func snapshot() -> Dictionary:
	var hook_index := _hooks.find(train.hook) if is_instance_valid(train.hook) else -1
	var anchor_name := String(train.anchor.name) if is_instance_valid(train.anchor) else ""
	var states := PackedByteArray()
	var wear := PackedFloat32Array()
	var bolt_hits := PackedByteArray()
	for i in Train.MAX_WHEELS:
		states.append(train.wheel_state(i))
		wear.append(train.wheel_wear[i])
		bolt_hits.append(int(train.wheel_slot(i).get("_hits")))
	var cds := PackedFloat32Array()
	if Game.sabotage:
		for id: String in SabotageManager.ABILITIES:
			cds.append(Game.sabotage.cooldowns.get(id, 0.0))
	return {
		"t": [train.distance, train.speed, train.lever, train.fuel, train.body_health, train.engine_damage,
			train.chassis_damage, train.tipped, train.tip_target, train.current_station, hook_index, anchor_name],
		"w": states, "ww": wear, "wh": bolt_hits,
		"g": [Game.next_station, Game.wind_active, Game.run_timing, Game.run_complete],
		"cd": cds,
	}


## The moving extras in small packets: what moved since last time, everything once a second (`force` = all).
## Extras that disappeared are announced reliably.
func _extras_packets(delta: float, force := false) -> Array:
	_dyn_key_clock += delta
	var keyframe := force or _dyn_key_clock >= 1.0
	if keyframe and not force:
		_dyn_key_clock = 0.0
	var alive := []
	for n: Variant in _dynamic:
		if is_instance_valid(n) and (n as Node).is_inside_tree() and not (n as Node).is_queued_for_deletion():
			alive.append(n)
	_dynamic = alive
	var names := {}
	var packets := []
	var packet := {}
	for n: Node in alive:
		var n3 := n as Node3D
		names[String(n.name)] = true
		var pos := n3.global_position
		var last: Variant = _dyn_sent.get(String(n.name))
		if not keyframe and last is Vector3 and (last as Vector3).distance_squared_to(pos) < 0.0004:
			continue
		if not force:
			_dyn_sent[String(n.name)] = pos
		var rot := n3.global_basis.get_rotation_quaternion()
		if n is Zombie:
			packet[n.name] = [DYN_ZOMBIE, pos, rot]
		elif n is Eagle:
			packet[n.name] = [DYN_EAGLE, pos, rot]
		elif n is FallenPart:
			packet[n.name] = [DYN_FALLEN, pos, rot, n.get_meta("net_part", -1)]
		elif n is AnchorSpot:
			packet[n.name] = [DYN_ANCHOR, pos, Quaternion.IDENTITY]
		if packet.size() >= DYN_PER_PACKET:
			packets.append(packet)
			packet = {}
	if not packet.is_empty():
		packets.append(packet)
	if not force:
		var gone := PackedStringArray()
		for n: String in _dyn_sent.keys():
			if not names.has(n):
				gone.append(n)
				_dyn_sent.erase(n)
		if not gone.is_empty():
			_send(&"_rpc_extras_gone", [gone])
	return packets


func _poll_repairs(force: bool) -> Array:
	var all := []
	for r in track.get_children():
		if r is RailRepair and not r.is_queued_for_deletion():
			var state: Dictionary = r.net_state()
			var text := var_to_str(state)
			if force:
				all.append([r.index, r.cratered, state])
			elif _repair_sent.get(r.index, "") != text:
				_repair_sent[r.index] = text
				_send(&"_rpc_repair", [r.index, state])
	return all


func _part_state(p: BodyPart) -> Array:
	var progress := []
	if p.is_pending():
		for f in _fasteners(p):
			progress.append(f.hits if f is NailSpot else (f as WeldSeam).progress)
	return [p.attached, p.is_pending(), p.door_open, progress]


func _fasteners(p: BodyPart) -> Array[Node]:
	var list: Array[Node] = []
	for f in p.car.get_children():
		if f.has_meta("part") and f.get_meta("part") == p and not f.is_queued_for_deletion():
			list.append(f)
	return list


## Gives a cover piece's "place it here" slot and its nails / welds stable names.
func _name_part_nodes(p: BodyPart) -> void:
	var slot := p.slot()
	if is_instance_valid(slot):
		slot.name = "Slot_%s" % p.name
	var k := 0
	for f in _fasteners(p):
		f.name = "Fix_%s_%d" % [p.name, k]
		k += 1


func _poll_parts(force: bool) -> Array:
	var all := []
	for i in train.parts.size():
		var p := train.parts[i]
		var st := _part_state(p)
		var text := var_to_str(st)
		if force:
			_name_part_nodes(p)
			all.append(st)
		elif _part_sent.get(i, "") != text:
			_part_sent[i] = text
			_name_part_nodes(p)
			_send(&"_rpc_part", [i, st])
	return all


## Sends a freshly loaded client everything that differs from the world it built itself.
func send_full_state(peer: int) -> void:
	var rolls := {}
	for i in track.piece_count:
		var r := track.piece_roll(i)
		if r != 0.0:
			rolls[i] = r
	var gold := {}
	var pickups := main.get_node_or_null("Pickups")
	if pickups:
		for p in pickups.get_children():
			if p is Pickup and p.item == "gold" and p.hits_left < 3:
				gold[String(p.name)] = p.hits_left
	var gates := []
	for seg in track.gate_count():
		gates.append(track.is_gate_locked(seg))
	var state := {
		"broken": _poll_repairs(true),
		"rolls": rolls,
		"gone": _gone,
		"gold": gold,
		"inventory": Game.inventory,
		"next_station": Game.next_station,
		"parts": _poll_parts(true),
		"gates": gates,
		"objective": Game.objective,
		"stats": Game.stats,
		"run": [Game.run_timing, Game.run_complete, Game.opened_gates.duplicate()],
		"pickups": _runtime_pickups(),
	}
	_rpc_full_state.rpc_id(peer, state)
	_rpc_snapshot.rpc_id(peer, snapshot())
	for packet in _extras_packets(0.0, true):
		_rpc_extras.rpc_id(peer, packet)


## After the host ran an action (its own or a client's): things taken away vanish everywhere, gold rocks count down.
func after_action(target: Object, args: Array) -> void:
	var subjects: Array = [target]
	subjects.append_array(args)
	for s: Variant in subjects:
		if not s is Node or not is_instance_valid(s):
			continue
		var n: Node = s
		# the topmost node (below Main) that is going away
		var gone_node: Node = null
		var cur := n
		while cur and cur != main:
			if cur.is_queued_for_deletion():
				gone_node = cur
			cur = cur.get_parent()
		if gone_node and (gone_node is Pickup or String(gone_node.name).begins_with("Key_") or String(gone_node.name).begins_with("Pickup_")):
			var rel := str(main.get_path_to(gone_node))
			if not rel in _gone:
				_gone.append(rel)
				_send(&"_rpc_gone", [rel])
		elif n is Pickup and n.item == "gold":
			_send(&"_rpc_gold", [str(main.get_path_to(n)), n.hits_left])


# --- Host: events -----------------------------------------------------------------------

func _on_piece_broken(index: int) -> void:
	var r := track.repair_at(index)
	_send(&"_rpc_break", [index, r.cratered if r else false])
	_repair_sent.erase(index)


func _on_piece_repaired(index: int) -> void:
	_send(&"_rpc_repaired", [index, track.piece_roll(index)])
	_repair_sent.erase(index)


func _on_gate_opened(seg: int) -> void:
	_send(&"_rpc_gate", [seg])


func _on_station_reached(index: int) -> void:
	_send(&"_rpc_station", [index, Game.stats])


func _on_run_finished(stats: Dictionary) -> void:
	_send(&"_rpc_run_finished", [stats])


func _on_objective_changed(text: String) -> void:
	_send(&"_rpc_objective", [text])


func _on_main_child(node: Node) -> void:
	if node is Zombie or node is Eagle or node is FallenPart or node is AnchorSpot or node is Meteor:
		_name_dynamic.call_deferred(node)
	elif node is Pickup:
		_send_spawned_pickup.call_deferred(node)  # supply / coal crates the RunDirector drops at runtime


## Host: a pickup created during the run (RunDirector's softlock crates) appears on every client too.
func _send_spawned_pickup(p: Pickup) -> void:
	if is_instance_valid(p) and p.is_inside_tree() and not p.is_queued_for_deletion():
		_send(&"_rpc_pickup", [_pickup_state(p)])


func _pickup_state(p: Pickup) -> Array:
	return [String(p.name), p.item, p.amount, p.hits_left, p.bundle, p.position]


func _runtime_pickups() -> Array:
	var list := []
	for c in main.get_children():
		if c is Pickup and not c.is_queued_for_deletion():
			list.append(_pickup_state(c))
	return list


func _name_dynamic(node: Node) -> void:
	if not is_instance_valid(node) or not node.is_inside_tree():
		return
	_counter += 1
	var prefix := "Zombie"
	if node is Eagle:
		prefix = "Eagle"
	elif node is FallenPart:
		prefix = "Fallen"
		node.set_meta("net_part", _part_index_of(node))
	elif node is AnchorSpot:
		prefix = "Anchor"
	elif node is Meteor:
		prefix = "Meteor"
	node.name = "%s_%d" % [prefix, _counter]
	if node is Meteor:
		_send(&"_rpc_meteor", [String(node.name), (node as Meteor).target])
	else:
		_dynamic.append(node)


func _part_index_of(fallen: Node) -> int:
	for c in fallen.get_children():
		if c is MeshInstance3D:
			for i in train.parts.size():
				if train.parts[i].node.mesh == (c as MeshInstance3D).mesh:
					return i
	return -1


# --- Client: applying ------------------------------------------------------------------------

func _client_tick(delta: float) -> void:
	if train == null or not _has_snap:
		return
	_snap_age = minf(_snap_age + delta, 0.3)
	# predict where the host's train is now, glide there
	var target := _snap_distance + _snap_speed * _snap_age
	var step := train.speed * delta
	if step > 0.0:
		var block := track.blocking_distance(train.distance, train.distance + step)
		if block >= 0.0:
			step = maxf(block - 0.01 - train.distance, 0.0)
	train.distance += step
	var error := target - train.distance
	if absf(error) > 12.0:
		train.distance = target
	else:
		train.distance += error * clampf(8.0 * delta, 0.0, 1.0)
	for n: String in _puppets:
		var pup: Dictionary = _puppets[n]
		var node: Node3D = pup.node
		if not is_instance_valid(node):
			continue
		var k := clampf(12.0 * delta, 0.0, 1.0)
		var pos: Vector3 = pup.pos
		if node.global_position.distance_to(pos) > 10.0:
			node.global_position = pos
		else:
			node.global_position = node.global_position.lerp(pos, k)
		var rot: Quaternion = pup.rot
		node.quaternion = node.quaternion.slerp(rot, k)


@rpc("authority", "call_remote", "unreliable_ordered", 1)
func _rpc_snapshot(s: Dictionary) -> void:
	if train == null:
		return
	var t: Array = s.t
	_snap_distance = t[0]
	_snap_speed = t[1]
	_snap_age = 0.0
	if not _has_snap:
		train.distance = _snap_distance
	_has_snap = true
	train.speed = t[1]
	train.lever = t[2]
	train.fuel = t[3]
	train.body_health = t[4]
	train.engine_damage = t[5]
	train.chassis_damage = t[6]
	train.tipped = t[7]
	train.tip_target = t[8]
	train.current_station = t[9]
	var hook_index: int = t[10]
	train.hook = _hooks[hook_index] if hook_index >= 0 and hook_index < _hooks.size() else null
	var anchor_name: String = t[11]
	train.anchor = main.get_node_or_null(anchor_name) as AnchorSpot if anchor_name != "" else null
	var states: PackedByteArray = s.w
	var wear: PackedFloat32Array = s.ww
	var bolt_hits: PackedByteArray = s.get("wh", PackedByteArray())
	for i in mini(states.size(), Train.MAX_WHEELS):
		train.net_set_wheel(i, states[i], wear[i])
		if i < bolt_hits.size():
			train.wheel_slot(i).set("_hits", bolt_hits[i])  # the "Bolt the wheel 1/3" prompt
	var g: Array = s.g
	Game.next_station = g[0]
	Game.wind_active = g[1]
	if g.size() >= 4:
		Game.run_timing = g[2]  # the run clock ticks here too between station syncs
		Game.run_complete = g[3]
	var cds: PackedFloat32Array = s.cd
	if Game.sabotage:
		var k := 0
		for id: String in SabotageManager.ABILITIES:
			if k < cds.size():
				Game.sabotage.cooldowns[id] = cds[k]
			k += 1


@rpc("authority", "call_remote", "unreliable_ordered", 1)
func _rpc_extras(dyn: Dictionary) -> void:
	for n: String in dyn:
		var e: Array = dyn[n]
		if not _puppets.has(n) or not is_instance_valid(_puppets[n].node):
			var node := _make_puppet(n, e)
			if node == null:
				continue
			_puppets[n] = {"node": node, "pos": e[1], "rot": e[2]}
		else:
			_puppets[n].pos = e[1]
			_puppets[n].rot = e[2]


@rpc("authority", "call_remote", "reliable")
func _rpc_extras_gone(names: PackedStringArray) -> void:
	for n in names:
		if _puppets.has(n):
			var node: Node = _puppets[n].node
			if is_instance_valid(node):
				node.queue_free()
			_puppets.erase(n)


func _make_puppet(n: String, e: Array) -> Node3D:
	var kind: int = e[0]
	var pos: Vector3 = e[1]
	var node: Node3D
	match kind:
		DYN_ZOMBIE:
			node = Zombie.spawn(main, pos)
		DYN_EAGLE:
			node = Eagle.spawn(main, pos)
		DYN_FALLEN:
			var idx: int = e[3]
			if idx < 0 or idx >= train.parts.size():
				return null
			var part := train.parts[idx]
			var fallen := FallenPart.spawn(main, part.node, part.car)
			fallen.freeze = true
			node = fallen
		DYN_ANCHOR:
			var a := AnchorSpot.new()
			a.train = train
			main.add_child(a)
			node = a
		_:
			return null
	# puppets only follow the host
	node.set_physics_process(false)
	node.name = n
	node.global_position = pos
	node.quaternion = e[2]
	return node


@rpc("authority", "call_remote", "reliable")
func _rpc_full_state(s: Dictionary) -> void:
	var host_broken := {}
	for e: Array in s.broken:
		host_broken[int(e[0])] = e
	var rolls: Dictionary = s.rolls
	for r in track.get_children():
		if r is RailRepair and not host_broken.has(r.index):
			track.repair_piece(r.index, rolls.get(r.index, 0.0))
	for i: int in host_broken:
		var e: Array = host_broken[i]
		if not track.is_broken(i):
			track.break_piece(i, e[1])
		var repair := track.repair_at(i)
		if repair:
			repair.apply_net_state(e[2])
	for rel: String in s.gone:
		_remove(rel)
	var gold: Dictionary = s.gold
	for rel: String in gold:
		_rpc_gold(rel, gold[rel])
	_rpc_inventory(s.inventory)
	Game.next_station = s.next_station
	var parts: Array = s.parts
	for i in mini(parts.size(), train.parts.size()):
		_apply_part(i, parts[i])
	# gates both ways: open what the host opened, lock (and put the key back) what the host has locked
	var gates: Array = s.gates
	for seg in mini(gates.size(), track.gate_count()):
		track.set_gate_locked(seg, bool(gates[seg]))
	_rpc_objective(str(s.objective))
	var host_stats: Dictionary = s.get("stats", {})
	if not host_stats.is_empty():
		Game.stats = host_stats.duplicate()
	var run: Array = s.get("run", [])
	if run.size() >= 3:
		Game.run_timing = bool(run[0])
		Game.run_complete = bool(run[1])
		Game.opened_gates.clear()
		for seg: Variant in run[2]:
			Game.opened_gates.append(int(seg))
	var runtime: Array = s.get("pickups", [])
	for e: Array in runtime:
		_rpc_pickup(e)


## Client: a pickup the host created during the run (same name, contents and place).
@rpc("authority", "call_remote", "reliable")
func _rpc_pickup(e: Array) -> void:
	var n := String(e[0])
	if main.get_node_or_null(n) != null:
		return
	var p := Pickup.new()
	p.name = n
	p.item = String(e[1])
	p.amount = int(e[2])
	p.hits_left = int(e[3])
	var b: Dictionary = e[4]
	p.bundle = b.duplicate()
	p.position = e[5]
	main.add_child(p)


@rpc("authority", "call_remote", "reliable")
func _rpc_inventory(inv: Dictionary) -> void:
	Game.inventory = inv.duplicate()
	Game.inventory_changed.emit()


@rpc("authority", "call_remote", "reliable")
func _rpc_break(index: int, cratered: bool) -> void:
	track.break_piece(index, cratered)


@rpc("authority", "call_remote", "reliable")
func _rpc_repaired(index: int, roll: float) -> void:
	track.repair_piece(index, roll)


@rpc("authority", "call_remote", "reliable")
func _rpc_repair(index: int, state: Dictionary) -> void:
	var repair := track.repair_at(index)
	if repair and not repair.is_queued_for_deletion():
		repair.apply_net_state(state)


@rpc("authority", "call_remote", "reliable")
func _rpc_part(index: int, state: Array) -> void:
	if index >= 0 and index < train.parts.size():
		_apply_part(index, state)


func _apply_part(index: int, st: Array) -> void:
	var p := train.parts[index]
	var attached: bool = st[0]
	var pending: bool = st[1]
	if attached and not p.attached:
		p.refit_instantly()
	elif not attached and p.attached:
		p.detach(false)  # the flying piece is the host's (a puppet)
	if not attached and pending and not p.is_pending():
		var slot := p.slot()
		if is_instance_valid(slot):
			slot.queue_free()
		p._on_placed(null)  # shows the piece and adds its nails / welds
	_name_part_nodes(p)
	if pending:
		var progress: Array = st[3]
		var fixes := _fasteners(p)
		for k in mini(progress.size(), fixes.size()):
			if fixes[k] is NailSpot:
				(fixes[k] as NailSpot).net_set_hits(int(progress[k]))
			elif fixes[k] is WeldSeam:
				(fixes[k] as WeldSeam).net_set_progress(float(progress[k]))
	if p.attached and bool(st[2]) != p.door_open:
		p.toggle_door()


@rpc("authority", "call_remote", "reliable")
func _rpc_gone(rel: String) -> void:
	_remove(rel)


func _remove(rel: String) -> void:
	var n := main.get_node_or_null(rel)
	if n:
		n.queue_free()


@rpc("authority", "call_remote", "reliable")
func _rpc_gold(rel: String, hits_left: int) -> void:
	var p := main.get_node_or_null(rel) as Pickup
	if p:
		p.hits_left = hits_left


@rpc("authority", "call_remote", "reliable")
func _rpc_meteor(n: String, target: Vector3) -> void:
	var m := Meteor.spawn(main, target)
	m.name = n


@rpc("authority", "call_remote", "reliable")
func _rpc_gate(seg: int) -> void:
	track.open_gate(seg)


@rpc("authority", "call_remote", "reliable")
func _rpc_station(index: int, stats: Dictionary) -> void:
	if not stats.is_empty():
		Game.stats = stats.duplicate()
	Game.next_station = maxi(Game.next_station, index + 1)
	if index >= Game.STATION_COUNT:
		Game.run_timing = false
		Game.run_complete = true
	Game.station_reached.emit(index)
	if index >= Game.STATION_COUNT:
		Game.chapter_completed.emit()


@rpc("authority", "call_remote", "reliable")
func _rpc_run_finished(stats: Dictionary) -> void:
	Game.stats = stats.duplicate()
	Game.run_timing = false
	Game.run_complete = true
	Game.run_finished.emit(stats)


@rpc("authority", "call_remote", "reliable")
func _rpc_objective(text: String) -> void:
	Game.objective = text
