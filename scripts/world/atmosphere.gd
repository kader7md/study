class_name Atmosphere
extends Node
## Weather and time of day along the line: every landscape theme has its own light (the run goes from a fresh
## morning in the forest hills, through a grey drizzle in the river valley and snowfall on the mountain pass, to a
## misty golden afternoon at the lake and a sunset on the coast). The sky, sun, fog and weather blend smoothly
## between themes, following the camera. A cold wind (Game.wind_active) thickens the fog on top of that.
## Purely visual: every peer shows the weather where its own camera is.

const BLEND := 260.0
const WIND_FOG := 0.02
## sun: (pitch, yaw) in degrees. weather: "", "rain", "snow" or "mist".
const PRESETS := [
	{"sun": Vector2(-34, -55), "sun_color": Color(1.0, 0.93, 0.8), "energy": 1.05, "top": Color(0.32, 0.53, 0.86),
		"horizon": Color(0.72, 0.79, 0.86), "fog": Color(0.76, 0.83, 0.9), "density": 0.00026, "ambient": 0.45, "weather": ""},
	{"sun": Vector2(-58, -20), "sun_color": Color(0.9, 0.92, 0.95), "energy": 0.7, "top": Color(0.42, 0.5, 0.6),
		"horizon": Color(0.66, 0.7, 0.74), "fog": Color(0.62, 0.67, 0.72), "density": 0.0007, "ambient": 0.55, "weather": "rain"},
	{"sun": Vector2(-42, 25), "sun_color": Color(0.95, 0.97, 1.0), "energy": 0.95, "top": Color(0.36, 0.5, 0.74),
		"horizon": Color(0.8, 0.84, 0.9), "fog": Color(0.82, 0.86, 0.92), "density": 0.0006, "ambient": 0.55, "weather": "snow"},
	{"sun": Vector2(-24, 55), "sun_color": Color(1.0, 0.84, 0.62), "energy": 1.0, "top": Color(0.33, 0.48, 0.78),
		"horizon": Color(0.9, 0.8, 0.66), "fog": Color(0.86, 0.8, 0.7), "density": 0.0005, "ambient": 0.45, "weather": "mist"},
	{"sun": Vector2(-11, 75), "sun_color": Color(1.0, 0.62, 0.36), "energy": 0.95, "top": Color(0.3, 0.38, 0.62),
		"horizon": Color(0.98, 0.64, 0.42), "fog": Color(0.9, 0.68, 0.52), "density": 0.00035, "ambient": 0.4, "weather": ""},
]

var env: Environment
var sky_mat: ProceduralSkyMaterial
var sun: DirectionalLight3D
var track: Track
## The theme blend currently shown (segment index + fraction towards the next), for tests and the HUD.
var current := 0.0
var _wind := 0.0
var _rain: CPUParticles3D
var _snow: CPUParticles3D
var _visual := true


func setup(e: Environment, sky: ProceduralSkyMaterial, s: DirectionalLight3D, t: Track) -> void:
	env = e
	sky_mat = sky
	sun = s
	track = t


func _ready() -> void:
	name = "Atmosphere"
	_visual = DisplayServer.get_name() != "headless"
	if _visual:
		_rain = _make_weather(Vector2(0.025, 0.7), Color(0.75, 0.8, 0.9, 0.45), 700, Vector3(0, -22.0, 0), 1.1)
		_snow = _make_weather(Vector2(0.09, 0.09), Color(1, 1, 1, 0.9), 600, Vector3(0.6, -2.2, 0.3), 7.0)
	_apply(0.0, 1.0)


func _make_weather(size: Vector2, color: Color, amount: int, fall: Vector3, life: float) -> CPUParticles3D:
	var p := CPUParticles3D.new()
	p.amount = amount
	p.lifetime = life
	p.emitting = false
	p.local_coords = false
	p.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
	p.emission_box_extents = Vector3(28, 2, 28)
	p.position = Vector3(0, 14, 0)
	p.direction = fall.normalized()
	p.spread = 6.0
	p.initial_velocity_min = fall.length() * 0.8
	p.initial_velocity_max = fall.length()
	p.gravity = Vector3.ZERO
	var quad := QuadMesh.new()
	quad.size = size
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.billboard_mode = BaseMaterial3D.BILLBOARD_FIXED_Y if size.y > size.x * 2.0 else BaseMaterial3D.BILLBOARD_ENABLED
	m.albedo_color = color
	if size.y <= size.x * 2.0:
		m.albedo_texture = GateKey._radial_texture()
	quad.material = m
	p.mesh = quad
	p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(p)
	return p


func _process(delta: float) -> void:
	var cam := get_viewport().get_camera_3d() if is_inside_tree() else null
	if cam == null or track == null:
		return
	var d := track.closest_distance(cam.global_position)
	_wind = move_toward(_wind, 1.0 if Game.wind_active else 0.0, delta * 0.5)
	_apply(d, delta)
	for w: CPUParticles3D in [_rain, _snow]:
		if w:
			w.global_position = cam.global_position + Vector3.UP * 14.0


## Theme blend at track distance d: x = segment, y = weight of the next one.
func blend_at(d: float) -> Vector2:
	var seg := track.segment_at(d)
	var k := 0.0
	if seg + 1 < track.station_distances.size() - 1:
		var next := track.station_distances[seg + 1]
		k = smoothstep(next - BLEND, next + BLEND, d)
	if seg > 0 and d < track.station_distances[seg] + BLEND:
		seg -= 1
		k = smoothstep(track.station_distances[seg + 1] - BLEND, track.station_distances[seg + 1] + BLEND, d)
	return Vector2(seg, k)


func _apply(d: float, _delta: float) -> void:
	if env == null or track == null or track.station_distances.is_empty():
		return
	var b := blend_at(d)
	var a: Dictionary = PRESETS[clampi(int(b.x), 0, PRESETS.size() - 1)]
	var n: Dictionary = PRESETS[clampi(int(b.x) + 1, 0, PRESETS.size() - 1)]
	var k := b.y
	current = b.x + k
	var fog: Color = (a.fog as Color).lerp(n.fog, k)
	env.fog_light_color = fog.lerp(Color(0.85, 0.92, 1.0), _wind)
	env.fog_density = lerpf(lerpf(a.density, n.density, k), WIND_FOG, _wind)
	env.ambient_light_energy = lerpf(a.ambient, n.ambient, k)
	if sky_mat:
		sky_mat.sky_top_color = (a.top as Color).lerp(n.top, k)
		sky_mat.sky_horizon_color = (a.horizon as Color).lerp(n.horizon, k)
		sky_mat.ground_horizon_color = sky_mat.sky_horizon_color.darkened(0.25)
	if sun:
		var sa: Vector2 = a.sun
		var sb: Vector2 = n.sun
		var s := sa.lerp(sb, k)
		sun.rotation_degrees = Vector3(s.x, s.y, 0.0)
		sun.light_color = (a.sun_color as Color).lerp(n.sun_color, k)
		sun.light_energy = lerpf(a.energy, n.energy, k)
	var weather: String = a.weather if k < 0.5 else n.weather
	var strength := 1.0 - absf(k - (0.0 if k < 0.5 else 1.0)) * 2.0
	env.fog_height_density = 0.004 + (0.012 * strength if weather == "mist" else 0.0)
	if _rain:
		_rain.emitting = weather == "rain" and strength > 0.3
		_snow.emitting = weather == "snow" and strength > 0.3
