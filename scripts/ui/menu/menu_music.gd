class_name MenuMusic
extends AudioStreamPlayer
## A small cosy music-box loop for the title screen, generated in code on a worker thread (no audio files):
## F - Dm - Bb - C arpeggios over a soft bass, 8 seconds, looped, on the Music bus. Fades in when ready.

const RATE := 22050
const BEAT := 0.25            # one arpeggio note (eighth at 120 bpm)
const CHORDS := [
	[41, [65, 69, 72, 77, 72, 69, 72, 76]],   # F
	[38, [62, 65, 69, 74, 69, 65, 69, 72]],   # Dm
	[34, [58, 62, 65, 70, 65, 62, 65, 69]],   # Bb
	[36, [60, 64, 67, 72, 67, 64, 67, 71]],   # C
]

var _task := -1
var _buf := PackedFloat32Array()   # filled on the worker thread only


func _ready() -> void:
	bus = "Music" if AudioServer.get_bus_index("Music") >= 0 else "Master"
	volume_db = -40.0
	process_mode = Node.PROCESS_MODE_ALWAYS
	if DisplayServer.get_name() == "headless":
		return
	_task = WorkerThreadPool.add_task(_generate)


func _exit_tree() -> void:
	if _task >= 0:
		WorkerThreadPool.wait_for_task_completion(_task)
		_task = -1


func _generate() -> void:
	var n := int(RATE * BEAT * 8 * CHORDS.size())
	_buf.resize(n)
	var step := int(RATE * BEAT)
	for c in CHORDS.size():
		var chord: Array = CHORDS[c]
		var start := c * step * 8
		_note(start, 2.6, _hz(int(chord[0])), 0.22, 1.6, true)
		_note(start + step * 4, 1.4, _hz(int(chord[0]) + 12), 0.08, 2.5, true)
		var arp: Array = chord[1]
		for k in arp.size():
			var accent := 1.0 if k % 4 == 0 else 0.7
			_note(start + k * step, 1.1, _hz(int(arp[k])), 0.13 * accent, 4.5, false)
	var data := PackedByteArray()
	data.resize(n * 2)
	for i in n:
		data.encode_s16(i * 2, clampi(int(_buf[i] * 1.8 * 32767.0), -32768, 32767))
	var wav := AudioStreamWAV.new()
	wav.format = AudioStreamWAV.FORMAT_16_BITS
	wav.mix_rate = RATE
	wav.stereo = false
	wav.data = data
	wav.loop_mode = AudioStreamWAV.LOOP_FORWARD
	wav.loop_begin = 0
	wav.loop_end = n
	_start.call_deferred(wav)


func _start(wav: AudioStreamWAV) -> void:
	_task = -1
	if not is_inside_tree():
		return
	stream = wav
	play()
	create_tween().tween_property(self, "volume_db", -9.0, 2.5)


static func _hz(midi: int) -> float:
	return 440.0 * pow(2.0, (midi - 69) / 12.0)


## Adds one plucked note (wrapping around the loop end so the loop is seamless).
func _note(start: int, length: float, freq: float, amp: float, decay: float, soft: bool) -> void:
	var n := _buf.size()
	var count := int(length * RATE)
	var w := TAU * freq / RATE
	for i in count:
		var t := float(i) / RATE
		var env := exp(-t * decay) * minf(1.0, t * (60.0 if soft else 400.0))
		var s := sin(w * i)
		if soft:
			s = s * 0.85 + sin(w * 2.0 * i) * 0.15
		else:
			s = s * 0.7 + sin(w * 2.0 * i) * 0.2 + sin(w * 3.0 * i) * 0.06 * exp(-t * 6.0)
		var idx := (start + i) % n
		_buf[idx] += s * env * amp
