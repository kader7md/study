class_name RunDirector
extends Node
## Runs the journey (host-side): keeps Game.objective up to date, guards against softlocks
## (supply crates, an emergency wheel, a loaned nail gun), and plays the Chapter 1 ending at station 5:
## sabotage stops, and after END_DELAY seconds the EndScreen shows the run stats.

const END_SCREEN := "res://scenes/ui/EndScreen.tscn"
const END_DELAY := 2.0
## The objective switches to "Gate locked" / "Rebuild the track" this far ahead of the train.
const OBJECTIVE_RANGE := 150.0
## Supply crate (softlock guard) contents.
const SUPPLY_CRATE := {"wood": 6, "nails": 10, "rail": 2, "bolts": 4}
const COAL_CRATE := {"coal": 6}

var main: Node
var end_screen: EndScreen
var _objective_tick := 0.0
var _guard_tick := 0.0
var _crates := {}            # piece index -> true: one supply crate per gap
var _coal_crates: Array[float] = []
var _emergency_wheel := {}   # station index -> true
var _coal_ration := {}       # station index -> true


func _ready() -> void:
	Game.chapter_completed.connect(_on_chapter_completed)


func _process(delta: float) -> void:
	if not Game.is_host():
		return  # NET: clients get the objective from the host (WorldSync._rpc_objective); guards are host-side
	_objective_tick -= delta
	if _objective_tick <= 0.0:
		_objective_tick = 0.25
		Game.objective = compute_objective()
	_guard_tick -= delta
	if _guard_tick <= 0.0:
		_guard_tick = 1.0
		guard()


# --- Objective ------------------------------------------------------------------------

func compute_objective() -> String:
	var train := Game.train
	var track := Game.track
	if Game.run_complete:
		return "Chapter 1 complete! The trail leads on across the sea"
	if Game.in_quest():
		return Game.quest.objective()
	if train == null or track == null:
		return ""
	var next := mini(Game.next_station, Game.STATION_COUNT)
	if train.tipped:
		return "The train tipped over! Hook the come-along to its lifting eye, chain it to a tree and crank"
	if train.wheels < Train.MIN_WHEELS_TO_MOVE:
		return "Only %d wheels: fit a wheel (cargo car), or limp on to the station" % train.wheels
	if next < track.station_distances.size() and train.center_distance() > track.station_distances[next] + Track.STATION_LENGTH * 0.5:
		var where := "the port" if next == Game.STATION_COUNT else "station %d" % next
		return "You passed %s: pull the lever back and stop at the platform" % where
	var front := train.distance
	var piece := first_broken_ahead(front, OBJECTIVE_RANGE)
	var gate := track.locked_gate_ahead(front, OBJECTIVE_RANGE)
	var piece_first := piece >= 0 and (gate < 0 or track.piece_center(piece) < track.gate_distance(gate))
	if piece_first:
		var n := gap_size(piece)
		return "Rebuild the broken track ahead (%d piece%s): planks, rails, bolts" % [n, "" if n == 1 else "s"]
	if gate >= 0:
		if Game.crew_count("key") > 0:
			return "Open the gate: use the key on its padlock"
		if QuestManager.has_map(gate) and Game.quest:
			return Game.quest.gate_objective(gate)
		return "Gate locked: find the key (it glows beside the track)"
	if train.fuel <= 0.5 and Game.crew_count("coal") <= 0:
		return "Out of coal! Collect coal beside the track (or buy it at a station)"
	if train.fuel < 12.0 and Game.crew_count("coal") > 0:
		return "The fire is dying: shovel coal into the furnace"
	if train.is_stopped() and train.wheels < Train.MAX_WHEELS and Game.has("wheel"):
		return "Fit the spare wheel: carry it from the cargo car and bolt it on"
	var here := train.current_station
	if here >= 1 and here == Game.next_station - 1 and train.is_stopped():
		return "Station %d: shop, repair and rest, then drive on to station %d" % [here, next]
	if here == 0 and train.is_stopped():
		return "Shovel coal and push the lever forward: reach station 1"
	return "Reach station %d / %d" % [next, Game.STATION_COUNT]


## The nearest broken piece whose start is within `within` metres ahead of distance d, or -1.
func first_broken_ahead(d: float, within: float) -> int:
	var track := Game.track
	for i in range(track.piece_at(d), track.piece_at(d + within) + 1):
		if track.is_broken(i):
			return i
	return -1


## Number of broken pieces in a row starting at `piece`.
func gap_size(piece: int) -> int:
	var n := 0
	while Game.track.is_broken(piece + n) and n < 50:
		n += 1
	return n


# --- Softlock guards --------------------------------------------------------------------

func guard() -> void:
	var train := Game.train
	var track := Game.track
	if train == null or track == null or Game.run_complete or not train.is_stopped():
		return
	# 1. Stopped at a gap without the wood / nails / scrap to rebuild it and without gold to buy them:
	#    a supply crate (and over water without a nail gun: a loaned nail gun) turns up beside the gap.
	var piece := first_broken_ahead(train.distance, 25.0) if train.lever >= 0 else -1
	if piece >= 0 and not _crates.has(piece):
		var n := gap_size(piece)
		var need := {"wood": 3 * n, "nails": 6 * n, "rail": 2 * n, "bolts": 4 * n}
		var missing_cost := 0
		for item: String in need:
			var short: int = int(need[item]) - Game.count(item)
			if short > 0:
				var entry: Dictionary = Game.SHOP[item]
				var per: int = int(entry.gives[item])
				missing_cost += int(ceil(float(short) / per)) * int(entry.price)
		var bridge := false
		for k in n:
			bridge = bridge or track.is_bridge(piece + k)
		var gun_missing := bridge and Game.crew_count("nail_gun") <= 0
		if gun_missing:
			missing_cost += int(Game.SHOP.nail_gun.price)
		if missing_cost > 0 and Game.count("gold") < missing_cost:
			_crates[piece] = true
			var items := SUPPLY_CRATE.duplicate()
			if gun_missing:
				items["nail_gun"] = 1
			var p := _crate_spot(track.piece_center(piece) - 6.0)
			_spawn_crate(items, p)
			Game.say("Short of supplies? A supply crate lies beside the broken track (%s)" % Game.cost_text(items))
	# 2. No fuel, no coal, no gold for coal: a coal crate (at most one every 200 m). At a station the station
	#    master hands over a coal ration instead (once per station).
	if train.fuel <= 0.0 and Game.crew_count("coal") <= 0 and Game.count("gold") < int(Game.SHOP.coal.price):
		var d := train.distance
		if train.current_station >= 0:
			if not _coal_ration.has(train.current_station):
				_coal_ration[train.current_station] = true
				for p in get_tree().get_nodes_in_group("player"):
					Game.add_to((p as Player).peer_id, "coal", int(COAL_CRATE.coal))
				Game.say("The station master shovels you a ration of coal (%d). Feed the furnace!" % int(COAL_CRATE.coal))
		elif not _coal_crates.any(func(c: float): return absf(c - d) < 200.0):
			_coal_crates.append(d)
			_spawn_crate(COAL_CRATE, _crate_spot(d - 10.0))
			Game.say("Out of coal and gold: someone left a crate of coal beside the track")
	# 3. At a station with too few wheels to drive and no gold for a new one: one emergency wheel per station
	var st := train.current_station
	if st >= 0 and not _emergency_wheel.has(st):
		if train.wheels + Game.count("wheel") < Train.MIN_WHEELS_TO_MOVE and Game.count("gold") < int(Game.SHOP.wheel.price):
			_emergency_wheel[st] = true
			Game.add("wheel")
			Game.say("The station master hands you an emergency wheel. Fit it from the cargo car!")


func _crate_spot(d: float) -> Vector3:
	var track := Game.track
	for u in [3.5, -3.5, 5.0, -5.0]:
		var p := track.ground_point(d, u)
		if p.y > Track.WATER_LEVEL + 0.5 and not track.is_bridge_at(d):
			return p
	return track.point_at(d) + Vector3.UP * 0.2


func _spawn_crate(items: Dictionary, pos: Vector3) -> void:
	var p := Pickup.create_bundle(main, items, pos)
	p.name = "SupplyCrate_%d" % (_crates.size() + _coal_crates.size())


# --- Ending -------------------------------------------------------------------------------

func _on_chapter_completed() -> void:
	if Game.sabotage:
		Game.sabotage.stop_all()
	await get_tree().create_timer(END_DELAY).timeout
	if is_inside_tree():
		show_end_screen()


func show_end_screen() -> void:
	if end_screen == null:
		end_screen = load(END_SCREEN).instantiate()
		main.add_child(end_screen)
	end_screen.open(Game.stats)
