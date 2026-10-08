class_name Station
extends Node3D
## A station on the right side of the track: platform, sign, shop,
## station-only repairs (arc welding, wheel fitting) and the grave (revive comes in M5).
## Index 0 is the departure station. 1..5 are checkpoints; 5 is the last one (the port).

signal shop_requested(station: Station)

const WELD_COST := {"scrap": 4, "gold": 2}

var index := 0
var track: Track


func setup(t: Track, station_index: int) -> void:
	track = t
	index = station_index
	name = "Station%d" % index
	global_transform = track.transform_at(track.station_distances[index])
	_build()


func display_name() -> String:
	if index == 0:
		return "Departure: City Station"
	if index == Game.STATION_COUNT:
		return "Station %d: The Port (final)" % index
	return "Station %d / %d" % [index, Game.STATION_COUNT]


func _train_here() -> bool:
	return Game.train != null and Game.train.current_station == index


func _build() -> void:
	var length := Track.STATION_LENGTH
	# Platform (right side of the track) and a roof
	Build.solid_box(self, Vector3(4.0, 1.2, length), Vector3(3.9, 0.6, 0), Color(0.5, 0.47, 0.42))
	Build.box(self, Vector3(4.4, 0.2, length * 0.5), Vector3(4.2, 4.2, 0), Color(0.55, 0.2, 0.15))
	for z in [-length * 0.2, 0.0, length * 0.2]:
		Build.box(self, Vector3(0.2, 3.0, 0.2), Vector3(5.6, 2.7, z), Color(0.3, 0.3, 0.3))
	Build.label(self, display_name(), Vector3(4.0, 5.2, 0), 96)

	# Shop
	Build.box(self, Vector3(1.6, 1.0, 1.0), Vector3(5.0, 1.7, -10), Color(0.25, 0.5, 0.75))
	Build.label(self, "SHOP", Vector3(5.0, 2.8, -10), 48)
	ActionSpot.create(self, Vector3(1.8, 1.4, 1.2), Vector3(5.0, 1.8, -10),
		func(_p): return "Shop (you have %d gold)  [E]" % Game.count("gold"),
		func(_p): shop_requested.emit(self))

	# Welding bench: heavy body damage, train must be stopped here
	Build.box(self, Vector3(1.2, 1.0, 1.0), Vector3(3.0, 1.7, 0), Color(0.75, 0.45, 0.1))
	Build.label(self, "WELDING", Vector3(3.0, 2.8, 0), 40)
	var weld := ActionSpot.create(self, Vector3(1.4, 1.4, 1.2), Vector3(3.0, 1.8, 0),
		func(_p): return _weld_prompt(), func(_p): _weld())
	weld.hold_fn = func(_p): return 1.5 if Game.has("repair_hammer") else 3.0

	# Wheel fitting
	Build.cylinder(self, 0.5, 0.25, Vector3(3.0, 1.75, 6), Color(0.15, 0.15, 0.15)).rotation.z = PI * 0.5
	Build.label(self, "WHEELS", Vector3(3.0, 2.8, 6), 40)
	var wheel := ActionSpot.create(self, Vector3(1.4, 1.4, 1.2), Vector3(3.0, 1.8, 6),
		func(_p): return _wheel_prompt(), func(_p): _fit_wheel())
	wheel.hold_fn = func(_p): return 2.5

	# Grave (revive dead players here, M5)
	Build.box(self, Vector3(0.8, 1.0, 0.25), Vector3(5.2, 1.7, 15), Color(0.5, 0.5, 0.52))
	ActionSpot.create(self, Vector3(1.2, 1.4, 1.0), Vector3(5.2, 1.8, 15),
		func(_p): return "Grave: bring a dead friend's body here to revive them (M5)", func(_p): pass)


func _weld_prompt() -> String:
	var train := Game.train
	if not _train_here():
		return "Welding bench: stop the train at this station first"
	if train.health >= 100.0:
		return "Train body is 100%"
	return "Arc-weld train body %d%% → 100%% (%s)  [hold E]" % [int(train.health), Game.cost_text(WELD_COST)]


func _weld() -> void:
	if not _train_here() or Game.train.health >= 100.0:
		return
	if Game.pay(WELD_COST):
		Game.train.weld_full()
		Game.say("Train welded to 100%")
	else:
		Game.say("Need %s to weld" % Game.cost_text(WELD_COST))


func _wheel_prompt() -> String:
	var train := Game.train
	if not _train_here():
		return "Wheel fitting: stop the train at this station first"
	if train.wheels >= Train.MAX_WHEELS:
		return "All wheels OK (%d/%d)" % [train.wheels, Train.MAX_WHEELS]
	return "Fit a wheel %d/%d (have %d wheels; buy at the shop)  [hold E]" % [train.wheels, Train.MAX_WHEELS, Game.count("wheel")]


func _fit_wheel() -> void:
	if not _train_here() or Game.train.wheels >= Train.MAX_WHEELS:
		return
	if Game.take("wheel"):
		Game.train.fit_wheel()
		Game.say("Wheel fitted (%d/%d)" % [Game.train.wheels, Train.MAX_WHEELS])
	else:
		Game.say("No wheel. Buy one at the shop.")
