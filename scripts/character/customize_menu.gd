class_name CustomizeMenu
extends CanvasLayer
## "Change your look": a live 3D preview of your crew member (drag to turn it, it waves when you change something)
## and the choices: skin colour, eyes, eye colour, mouth, accessory and its colour, outfit colour, Randomise.
## Save stores the look in Settings (profile/look) and, in a run, sends it to the other players (Net.set_local_look).
## Opened by the Mirror on the train and from the main menu.
##   var m := CustomizeMenu.open_on(get_tree().root); m.closed.connect(...)

signal saved(code: String)
signal closed

const PREVIEW_SIZE := Vector2i(520, 640)

var look := Appearance.new()
var preview_yaw := PI + 0.4
var preview: CharacterModel
var is_open := false

var _original := ""
var _viewport: SubViewport
var _cam: Camera3D
var _rows := {}           # option key -> HBoxContainer of buttons
var _dragging := false
var _idle_time := 0.0
var _panel: PanelContainer


## Opens a new menu on `parent` (a scene's root or the HUD) with the saved look.
static func open_on(parent: Node) -> CustomizeMenu:
	var m := CustomizeMenu.new()
	m.name = "CustomizeMenu"
	parent.add_child(m)
	m.open()
	return m


func _ready() -> void:
	layer = 40
	process_mode = Node.PROCESS_MODE_ALWAYS
	_build()


func open() -> void:
	_original = Appearance.saved_code()
	look = Appearance.load_local() if _original != "" else _current_look()
	is_open = true
	visible = true
	_refresh()
	Game.open_ui(&"customize")
	if _panel:
		_panel.modulate.a = 0.0
		create_tween().tween_property(_panel, "modulate:a", 1.0, 0.15)


## The look the local player has right now (also when it was never saved).
func _current_look() -> Appearance:
	var me := Net.local_player()
	if me and me.look != "":
		return Appearance.decode(me.look)
	return Appearance.for_color(Net.player_color(Net.local_id()))


func close() -> void:
	if not is_open:
		return
	is_open = false
	Game.close_ui(&"customize")
	closed.emit()
	queue_free()


## Saves the current look (settings + everyone in the run) and closes.
func save() -> void:
	var code := look.encode()
	Appearance.save_local(look)
	Net.set_local_look(code)
	saved.emit(code)
	Game.say("New look saved")
	close()


func randomise() -> void:
	look = Appearance.random()
	_refresh()
	if preview:
		preview.play_action("wave")


func set_option(key: String, value: Variant) -> void:
	match key:
		"skin": look.skin = int(value)
		"eyes": look.eyes = str(value)
		"eye_color": look.eye_color = int(value)
		"mouth": look.mouth = str(value)
		"accessory": look.accessory = str(value)
		"hat_color": look.hat_color = int(value)
		"outfit": look.outfit = int(value)
	_refresh()
	_idle_time = 0.0


# --- UI ---------------------------------------------------------------------------------------------

func _build() -> void:
	var dim := ColorRect.new()
	dim.color = Color(0.1, 0.06, 0.03, 0.55)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(dim)
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(center)
	_panel = PanelContainer.new()
	_panel.add_theme_stylebox_override("panel", UiTheme.panel(UiTheme.CREAM, 22, 5))
	center.add_child(_panel)
	var outer := VBoxContainer.new()
	outer.add_theme_constant_override("separation", 10)
	_panel.add_child(outer)
	var title := UiTheme.title_label("YOUR LOOK", 54)
	outer.add_child(title)
	var cols := HBoxContainer.new()
	cols.add_theme_constant_override("separation", 22)
	outer.add_child(cols)

	# left: live preview (drag to turn)
	var left := VBoxContainer.new()
	left.add_theme_constant_override("separation", 8)
	cols.add_child(left)
	var frame := PanelContainer.new()
	var fsb := UiTheme.panel(UiTheme.WOOD_DARK, 16, 4, false)
	fsb.set_content_margin_all(6)
	frame.add_theme_stylebox_override("panel", fsb)
	left.add_child(frame)
	var holder := SubViewportContainer.new()
	holder.stretch = true
	holder.custom_minimum_size = Vector2(PREVIEW_SIZE)
	holder.mouse_filter = Control.MOUSE_FILTER_STOP
	holder.gui_input.connect(_on_preview_input)
	frame.add_child(holder)
	_viewport = SubViewport.new()
	_viewport.size = PREVIEW_SIZE
	_viewport.own_world_3d = true
	_viewport.transparent_bg = false
	_viewport.msaa_3d = Viewport.MSAA_2X
	_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	holder.add_child(_viewport)
	_build_stage()
	var hint := Label.new()
	hint.text = "Drag to turn · [B] waves in game"
	hint.theme_type_variation = &"MutedLabel"
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	left.add_child(hint)

	# right: the choices
	var right := VBoxContainer.new()
	right.add_theme_constant_override("separation", 6)
	right.custom_minimum_size = Vector2(560, 0)
	cols.add_child(right)
	_swatch_row(right, "Skin", "skin", Appearance.SKINS)
	_text_row(right, "Eyes", "eyes", Appearance.EYES)
	_swatch_row(right, "Eye colour", "eye_color", Appearance.EYE_COLORS)
	_text_row(right, "Mouth", "mouth", Appearance.MOUTHS)
	_text_row(right, "Accessory", "accessory", Appearance.ACCESSORIES)
	_swatch_row(right, "Accessory colour", "hat_color", Appearance.COLORS)
	_swatch_row(right, "Outfit", "outfit", Appearance.COLORS)
	var spacer := Control.new()
	spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	right.add_child(spacer)
	var buttons := HBoxContainer.new()
	buttons.add_theme_constant_override("separation", 12)
	buttons.alignment = BoxContainer.ALIGNMENT_END
	right.add_child(buttons)
	_button(buttons, "Randomise", &"BigButton", randomise)
	_button(buttons, "Cancel", &"BigButton", close)
	var ok := _button(buttons, "Save look", &"AccentButton", save)
	ok.name = "Save"


func _build_stage() -> void:
	var root := Node3D.new()
	_viewport.add_child(root)
	var env := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_COLOR
	e.background_color = Color("e9d6b1")
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color("f3e6d0")
	e.ambient_light_energy = 0.5
	e.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	e.tonemap_white = 6.0  # like the game world (main.gd): bright colours keep their hue
	env.environment = e
	root.add_child(env)
	var sun := DirectionalLight3D.new()
	sun.rotation = Vector3(-0.75, 0.55, 0.0)
	sun.light_energy = 1.0
	sun.shadow_enabled = true
	root.add_child(sun)
	var fill := OmniLight3D.new()
	fill.position = Vector3(-1.8, 1.6, 1.4)
	fill.light_color = Color("ffd9a8")
	fill.light_energy = 0.4
	fill.omni_range = 6.0
	root.add_child(fill)
	var disc := MeshInstance3D.new()
	var cyl := CylinderMesh.new()
	cyl.top_radius = 0.75
	cyl.bottom_radius = 0.8
	cyl.height = 0.08
	disc.mesh = cyl
	disc.position.y = -0.04
	disc.material_override = Build.material(Color("9a6a42"))
	root.add_child(disc)
	preview = CharacterModel.new()
	root.add_child(preview)
	_cam = Camera3D.new()
	_cam.fov = 30.0
	_cam.position = Vector3(0, 1.05, 3.9)
	root.add_child(_cam)
	_cam.look_at(Vector3(0, 0.9, 0))
	_cam.current = true


func _row(parent: Control, label: String) -> HFlowContainer:
	var l := Label.new()
	l.text = label
	l.theme_type_variation = &"HeaderLabel"
	l.add_theme_font_size_override("font_size", 20)
	parent.add_child(l)
	var flow := HFlowContainer.new()
	flow.add_theme_constant_override("h_separation", 6)
	flow.add_theme_constant_override("v_separation", 6)
	parent.add_child(flow)
	return flow


func _swatch_row(parent: Control, label: String, key: String, colors: Array[Color]) -> void:
	var flow := _row(parent, label)
	_rows[key] = flow
	for i in colors.size():
		var b := Button.new()
		b.custom_minimum_size = Vector2(40, 40)
		b.tooltip_text = "%s %d" % [label, i + 1]
		b.toggle_mode = true
		b.focus_mode = Control.FOCUS_NONE
		b.set_meta("value", i)
		for st: String in ["normal", "hover", "pressed", "hover_pressed", "focus"]:
			var sel := st.contains("pressed")
			var sb := UiTheme.flat(colors[i] if not st.begins_with("hover") else colors[i].lightened(0.12), 12,
				5 if sel else 3, UiTheme.INK if not sel else UiTheme.HONEY_DARK)
			if sel:
				sb.shadow_color = Color(UiTheme.INK, 0.6)
				sb.shadow_size = 3
			b.add_theme_stylebox_override(st, sb)
		b.pressed.connect(set_option.bind(key, i))
		flow.add_child(b)


func _text_row(parent: Control, label: String, key: String, values: Array[String]) -> void:
	var flow := _row(parent, label)
	_rows[key] = flow
	for v in values:
		var b := Button.new()
		b.text = str(Appearance.LABELS.get(v, v.capitalize()))
		b.toggle_mode = true
		b.focus_mode = Control.FOCUS_NONE
		b.add_theme_font_size_override("font_size", 18)
		b.set_meta("value", v)
		b.pressed.connect(set_option.bind(key, v))
		flow.add_child(b)


func _button(parent: Control, text: String, variation: StringName, fn: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.theme_type_variation = variation
	b.pressed.connect(fn)
	parent.add_child(b)
	return b


## Shows the look on the preview and marks the chosen buttons.
func _refresh() -> void:
	if preview:
		preview.apply_look(look)
	var values := {"skin": look.skin, "eyes": look.eyes, "eye_color": look.eye_color, "mouth": look.mouth,
		"accessory": look.accessory, "hat_color": look.hat_color, "outfit": look.outfit}
	for key: String in _rows:
		for b: Button in (_rows[key] as Control).get_children():
			b.set_pressed_no_signal(b.get_meta("value") == values[key])
	if _rows.has("hat_color"):
		(_rows["hat_color"] as Control).modulate.a = 0.35 if look.accessory in ["none", "glasses", "mustache"] else 1.0


func _on_preview_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		_dragging = event.pressed
	elif event is InputEventMouseMotion and _dragging:
		preview_yaw += event.relative.x * 0.012
		_idle_time = 0.0


func _input(event: InputEvent) -> void:
	if is_open and (event.is_action_pressed("pause") or event.is_action_pressed("ui_cancel")):
		get_viewport().set_input_as_handled()
		close()


func _process(delta: float) -> void:
	_idle_time += delta
	if not _dragging and _idle_time > 2.5:
		preview_yaw += delta * 0.35  # a slow turntable when nobody touches it
	if preview:
		preview.rotation.y = lerp_angle(preview.rotation.y, preview_yaw, clampf(delta * 10.0, 0.0, 1.0))
