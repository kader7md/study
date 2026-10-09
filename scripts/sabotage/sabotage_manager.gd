class_name SabotageManager
extends Node
## The impostor's sabotage abilities, each with a cooldown.
## - Impostor: uses them on purpose (debug: F2 to play as impostor, [X] menu, then keys 1-4).
## - No impostor (1-2 players): "the world" triggers random sabotage now and then.
## - A correct vote at the meeting table (M4) sets `locked`, silently disabling everything.

signal used(id: String)

const ABILITIES := {
	"meteor": {"label": "Meteor", "cooldown": 40.0, "key": 1},
	"zombies": {"label": "Zombie horde", "cooldown": 80.0, "key": 2},
	"eagles": {"label": "Eagles", "cooldown": 60.0, "key": 3},
	"freezing_wind": {"label": "Freezing wind", "cooldown": 100.0, "key": 4},
}
const WIND_DURATION := 30.0
## Seconds between world sabotage events per segment (calm in segment 1, busier towards the port).
const WORLD_INTERVALS := [Vector2(100.0, 160.0), Vector2(80.0, 140.0), Vector2(65.0, 120.0), Vector2(55.0, 105.0), Vector2(50.0, 95.0)]
## No world sabotage this soon after leaving a station.
const STATION_GRACE := 20.0

var cooldowns := {}
var locked := false
var _world_timer := 0.0
var _wind_left := 0.0
var _since_station := 0.0
var _stopped := false
var _rng := RandomNumberGenerator.new()


func _ready() -> void:
	_rng.randomize()
	for id: String in ABILITIES:
		cooldowns[id] = 0.0
	_world_timer = _next_interval()


func _next_interval() -> float:
	var seg := 0
	if Game.track and Game.train:
		seg = clampi(Game.track.segment_at(Game.train.center_distance()), 0, WORLD_INTERVALS.size() - 1)
	var r: Vector2 = WORLD_INTERVALS[seg]
	return _rng.randf_range(r.x, r.y)


## The run is over (or paused for a cutscene): no more sabotage, the wind dies down, enemies leave.
func stop_all() -> void:
	locked = true
	_stopped = true
	_wind_left = 0.0
	Game.wind_active = false
	for e in get_tree().get_nodes_in_group("enemy"):
		e.queue_free()


func can_use(id: String) -> bool:
	return not locked and cooldowns.get(id, 1.0) <= 0.0


## Uses an ability. `target` is only used by the meteor (world position).
func use(id: String, target := Vector3.ZERO) -> bool:
	if not can_use(id):
		return false
	cooldowns[id] = ABILITIES[id].cooldown
	match id:
		"meteor":
			Meteor.spawn(get_parent(), target)
			Game.say("☄ Something is falling from the sky!")
		"zombies":
			_spawn_zombies(5)
			Game.say("🧟 Zombies are coming for the train!")
		"eagles":
			_spawn_eagles(2)
			Game.say("🦅 Eagles are diving at the cargo!")
		"freezing_wind":
			_wind_left = WIND_DURATION
			Game.wind_active = true
			Game.say("🌬 A freezing wind! Train slower, coal burns faster. Stay near the furnace!")
	used.emit(id)
	return true


func _process(delta: float) -> void:
	if not Game.is_host():
		return  # NET: the host runs sabotage; clients get the cooldowns in the world snapshot
	for id: String in cooldowns:
		cooldowns[id] = maxf(cooldowns[id] - delta, 0.0)
	if _wind_left > 0.0:
		_wind_left -= delta
		if _wind_left <= 0.0:
			Game.wind_active = false
			Game.say("The freezing wind has passed")
	_world_sabotage(delta)


func _world_sabotage(delta: float) -> void:
	var train := Game.train
	if Game.role != "crew" or not Game.world_sabotage or train == null or _stopped:
		return
	if train.current_station != -1:
		_since_station = 0.0
		return
	_since_station += delta
	if train.is_stopped() or _since_station < STATION_GRACE:
		return  # the world only attacks a moving train, and leaves it alone right after a station
	_world_timer -= delta
	if _world_timer > 0.0:
		return
	_world_timer = _next_interval()
	var options: Array[String] = []
	for id: String in ABILITIES:
		if can_use(id):
			options.append(id)
	if options.is_empty():
		return
	var id := options[_rng.randi() % options.size()]
	var target := Vector3.ZERO
	if id == "meteor":
		# Aim at the track ahead of a forward-moving train (or behind a reversing one).
		var ahead := signf(train.speed) * _rng.randf_range(40.0, 90.0)
		var d := train.distance + ahead if ahead > 0.0 else train.rear_distance() + ahead
		d = _safe_meteor_distance(d, signf(ahead))
		target = Game.track.point_at(d) + Vector3(_rng.randf_range(-2.0, 2.0), 0.0, _rng.randf_range(-2.0, 2.0))
	use(id, target)


## World meteors never hit a bridge (rebuilding over water needs the nail gun) or the area of a locked gate:
## the aim moves along the track until it is on solid, open ground.
func _safe_meteor_distance(d: float, dir: float) -> float:
	var track := Game.track
	for k in 40:
		var ok := true
		for off in [-8.0, -4.0, 0.0, 4.0, 8.0]:
			if track.is_bridge_at(d + off):
				ok = false
		for s in track.gate_count():
			if absf(d - track.gate_distance(s)) < 40.0:
				ok = false
		if ok:
			return d
		d += dir * 10.0
	return d


func _spawn_zombies(count: int) -> void:
	var train := Game.train
	var ahead := 1.0 if train.speed >= 0.0 else -1.0
	var base := train.distance + 35.0 if ahead > 0.0 else train.rear_distance() - 35.0
	for i in count:
		var side := -1.0 if i % 2 == 0 else 1.0
		var pos := Game.track.ground_point(base + _rng.randf_range(-8.0, 8.0), side * _rng.randf_range(5.0, 12.0))
		Zombie.spawn(get_parent(), pos + Vector3.UP)


func _spawn_eagles(count: int) -> void:
	for i in count:
		var dir := Vector3.FORWARD.rotated(Vector3.UP, _rng.randf() * TAU)
		Eagle.spawn(get_parent(), Game.train.cars[1].global_position + dir * 45.0 + Vector3.UP * 25.0)
