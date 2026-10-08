class_name Station
extends Node3D
## A station on the right side of the track: platform, sign, shop, the big station welder
## (the only way to weld the train body back to 100 %) and the grave (revive comes in M5).
## Index 0 is the departure station. 1..5 are checkpoints; 5 is the last one (the port).

signal shop_requested(station: Station)

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
	Build.solid_box(self, Vector3(4.0, 4.0, length), Vector3(3.9, -0.8, 0), Color(0.5, 0.47, 0.42))
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

	# Big welder machine: welds the train body up to 100 % (the train's own welder stops at 60 %)
	WelderSource.create(self, "station", 25.0, Vector3(3.2, 1.2, 0))
	Build.label(self, "STATION WELDER", Vector3(3.2, 3.2, 0), 40)
	ActionSpot.create(self, Vector3(1.6, 1.4, 1.2), Vector3(3.2, 1.9, 0),
		func(_p): return "Station welder (cable 25 m): pick the welder [2] near it, weld metal panels back on up to 100%",
		func(_p): pass)

	# Grave (revive dead players here, M5)
	Build.box(self, Vector3(0.8, 1.0, 0.25), Vector3(5.2, 1.7, 15), Color(0.5, 0.5, 0.52))
	ActionSpot.create(self, Vector3(1.2, 1.4, 1.0), Vector3(5.2, 1.8, 15),
		func(_p): return "Grave: bring a dead friend's body here to revive them (M5)", func(_p): pass)
