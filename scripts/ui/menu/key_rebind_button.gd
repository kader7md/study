class_name KeyRebindButton
extends Button
## Shows an action's binding. Click it, then press a key or a mouse button to rebind (Esc cancels).
## The new binding is applied at once and saved by Settings.

signal rebound(action: String)

var action := ""
var listening := false
var _armed_frame := -1


static func create(action_name: String) -> KeyRebindButton:
	var b := KeyRebindButton.new()
	b.action = action_name
	b.theme_type_variation = &"KeyButton"
	b.custom_minimum_size = Vector2(170, 40)
	b.focus_mode = Control.FOCUS_NONE
	b.toggle_mode = false
	return b


func _ready() -> void:
	refresh()
	pressed.connect(_start)
	Settings.changed.connect(func(section: String, _key: String) -> void:
		if section == "controls" and not listening:
			refresh())


func refresh() -> void:
	text = Settings.binding_text(action)


func _start() -> void:
	if listening:
		return
	listening = true
	_armed_frame = Engine.get_process_frames()
	text = "Press a key…"
	add_theme_color_override("font_color", UiTheme.RUST_DARK)


func _stop() -> void:
	listening = false
	remove_theme_color_override("font_color")
	refresh()


func _input(event: InputEvent) -> void:
	if not listening or not is_visible_in_tree():
		return
	if event is InputEventKey and event.pressed and not event.echo:
		get_viewport().set_input_as_handled()
		var key := event as InputEventKey
		if key.physical_keycode == KEY_ESCAPE or key.keycode == KEY_ESCAPE:
			_stop()
			return
		Settings.rebind(action, key)
		_stop()
		rebound.emit(action)
	elif event is InputEventMouseButton and event.pressed:
		# ignore the click that started listening
		if Engine.get_process_frames() == _armed_frame:
			return
		get_viewport().set_input_as_handled()
		Settings.rebind(action, event)
		_stop()
		rebound.emit(action)
