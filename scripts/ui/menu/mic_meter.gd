class_name MicMeter
extends Control
## Live microphone level meter. While running it plays an AudioStreamMicrophone into the muted "Mic" bus
## and reads the bus's AudioEffectCapture. Nothing reaches the speakers unless Settings.set_mic_monitor(true).
## Call start() when it becomes visible and stop() when hidden (the Settings menu does this).

const SEGMENTS := 24

var level := 0.0          # 0..1 smoothed
var peak_hold := 0.0
var running := false
var _player: AudioStreamPlayer
var _capture: AudioEffectCapture


func _ready() -> void:
	custom_minimum_size = Vector2(360, 34)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_process(false)


static func has_input_device() -> bool:
	if DisplayServer.get_name() == "headless":
		return false
	return not AudioServer.get_input_device_list().is_empty()


func start() -> bool:
	if running:
		return true
	var bus := AudioServer.get_bus_index("Mic")
	if bus < 0 or not has_input_device():
		return false
	for i in AudioServer.get_bus_effect_count(bus):
		var fx := AudioServer.get_bus_effect(bus, i)
		if fx is AudioEffectCapture:
			_capture = fx
	if _capture == null:
		return false
	_capture.clear_buffer()
	_player = AudioStreamPlayer.new()
	_player.stream = AudioStreamMicrophone.new()
	_player.bus = "Mic"
	add_child(_player)
	_player.play()
	running = true
	set_process(true)
	return true


func stop() -> void:
	if _player:
		_player.stop()
		_player.queue_free()
		_player = null
	if _capture:
		_capture.clear_buffer()
	running = false
	level = 0.0
	peak_hold = 0.0
	set_process(false)
	queue_redraw()


func _exit_tree() -> void:
	stop()


func _process(delta: float) -> void:
	var frames := _capture.get_frames_available() if _capture else 0
	var peak := 0.0
	if frames > 0:
		var buf := _capture.get_buffer(frames)
		for f in buf:
			peak = maxf(peak, maxf(absf(f.x), absf(f.y)))
	# perceptual scale: -50 dB .. 0 dB -> 0..1
	var target := clampf((linear_to_db(maxf(peak, 0.00001)) + 50.0) / 50.0, 0.0, 1.0)
	level = target if target > level else move_toward(level, target, delta * 1.5)
	peak_hold = maxf(peak_hold - delta * 0.4, level)
	queue_redraw()


func _draw() -> void:
	var r := Rect2(Vector2.ZERO, size)
	draw_style_box(UiTheme.flat(UiTheme.INK, 10), r)
	var pad := 5.0
	var w := (size.x - pad * 2.0) / SEGMENTS
	var lit := int(round(level * SEGMENTS))
	var hold := int(round(peak_hold * SEGMENTS))
	for i in SEGMENTS:
		var f := float(i) / SEGMENTS
		var col := UiTheme.BODY_GREEN if f < 0.6 else (UiTheme.WHEEL_YELLOW if f < 0.85 else UiTheme.ENGINE_RED)
		if i >= lit and i != hold - 1:
			col = Color(col, 0.18)
		var seg := Rect2(pad + i * w + 1.5, pad, w - 3.0, size.y - pad * 2.0)
		draw_rect(seg, col)
