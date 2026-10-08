class_name Station
extends Node3D
## A station on the right side of the track: platform, sign, shop, the station welder
## (the only welder in the game: metal train panels are welded back on here) and the grave (revive comes in M5).
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


## Platform top (local y) and the track-side edge of the platform (local x).
const PLATFORM_TOP := 1.2
const EDGE_X := 1.9
const SHOP_Z := 22.0
const SIGN_Z := -24.0
const GRAVE_Z := 28.0
const SIGN_X := 5.4

static var _paving: StandardMaterial3D


func _build() -> void:
	var length := Track.STATION_LENGTH
	# Platform (right side of the track): paving, a stone coping along the edge and a yellow safety line
	var platform := Build.solid_box(self, Vector3(4.0, 4.0, length), Vector3(3.9, PLATFORM_TOP - 2.0, 0), Color(0.4, 0.38, 0.35))
	(platform.get_child(0) as MeshInstance3D).material_override = paving_material()
	Build.box(self, Vector3(0.45, 0.1, length), Vector3(EDGE_X + 0.22, PLATFORM_TOP + 0.04, 0), Color(0.55, 0.53, 0.5))
	Build.box(self, Vector3(0.1, 0.02, length), Vector3(EDGE_X + 0.62, PLATFORM_TOP + 0.005, 0), Color(0.95, 0.75, 0.15))
	# Canopy with columns, valance, benches and lamps (Blender model station_shelter.glb)
	var shelter := Props.instance("station_shelter")
	shelter.position = Vector3(3.6, PLATFORM_TOP, 0)
	add_child(shelter)
	# Name board on posts, and the name over the roof so it reads from the cab
	var sign_board := Props.instance("station_sign")
	sign_board.position = Vector3(SIGN_X, PLATFORM_TOP, SIGN_Z)
	add_child(sign_board)
	_sign_text(display_name(), Vector3(SIGN_X - 0.07, PLATFORM_TOP + 2.55, SIGN_Z), 3.1)
	var roof_label := Build.label(self, display_name(), Vector3(4.0, PLATFORM_TOP + 4.4, 0), 96)
	roof_label.modulate = UiTheme.CREAM

	# Shop kiosk (striped awning, counter) with SHOP on its sign board
	var kiosk := Props.instance("shop_kiosk")
	kiosk.position = Vector3(4.6, PLATFORM_TOP, SHOP_Z)
	add_child(kiosk)
	var kiosk_body := StaticBody3D.new()
	kiosk_body.collision_layer = Build.LAYER_WORLD
	kiosk_body.position = Vector3(4.6, PLATFORM_TOP + 1.3, SHOP_Z)
	add_child(kiosk_body)
	Build.collider(kiosk_body, Vector3(2.0, 2.6, 2.6), Vector3.ZERO)
	_sign_text("SHOP", Vector3(4.6 - 1.0 + 0.14, PLATFORM_TOP + 3.25, SHOP_Z), 2.0)
	ActionSpot.create(self, Vector3(1.0, 1.6, 2.6), Vector3(3.3, PLATFORM_TOP + 0.9, SHOP_Z),
		func(_p): return "Shop (you have %d gold)  [E]" % Game.count("gold"),
		func(_p): shop_requested.emit(self))

	# Big welder machine: welds the train body up to 100 % (the train's own welder stops at 60 %)
	WelderSource.create(self, "station", 30.0, Vector3(3.2, PLATFORM_TOP, 0))
	Build.label(self, "STATION WELDER", Vector3(3.2, PLATFORM_TOP + 2.0, 0), 40)

	# Grave (revive dead players here, M5)
	Build.box(self, Vector3(0.8, 1.0, 0.25), Vector3(5.2, PLATFORM_TOP + 0.5, GRAVE_Z), Color(0.5, 0.5, 0.52))
	ActionSpot.create(self, Vector3(1.2, 1.4, 1.0), Vector3(5.2, PLATFORM_TOP + 0.6, GRAVE_Z),
		func(_p): return "Grave: bring a dead friend's body here to revive them (M5)", func(_p): pass)


## Painted text on a board facing the track (-X), `width` metres wide at most.
func _sign_text(text: String, pos: Vector3, width: float) -> Label3D:
	var l := Build.label(self, text, pos, 96)
	l.billboard = BaseMaterial3D.BILLBOARD_DISABLED
	l.rotation_degrees.y = -90.0
	l.modulate = UiTheme.INK
	l.outline_size = 0
	l.width = width / l.pixel_size
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	var natural := l.font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, l.font_size).x * l.pixel_size
	if natural > width:
		l.pixel_size *= width / natural
		l.width = width / l.pixel_size
	return l


## Grey paving with a little colour noise (shared by every station).
static func paving_material() -> StandardMaterial3D:
	if _paving == null:
		var noise := FastNoiseLite.new()
		noise.frequency = 0.08
		var tex := NoiseTexture2D.new()
		tex.noise = noise
		tex.seamless = true
		tex.width = 256
		tex.height = 256
		var ramp := Gradient.new()
		ramp.set_color(0, Color(0.33, 0.31, 0.29))
		ramp.set_color(1, Color(0.46, 0.44, 0.4))
		tex.color_ramp = ramp
		_paving = StandardMaterial3D.new()
		_paving.albedo_texture = tex
		_paving.uv1_triplanar = true
		_paving.uv1_world_triplanar = true
		_paving.uv1_scale = Vector3(0.25, 0.25, 0.25)
		_paving.roughness = 0.95
	return _paving
