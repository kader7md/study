class_name ConfirmCard
extends Control
## A small "are you sure?" card in the UiTheme style (wood frame, cream paper, ink text): a title, one or two lines
## of text, a cancel button and a confirm button. Used before actions that lose progress or end the session for
## everyone (host Back to menu, Play solo over a save, restart from the last station...).
##   ConfirmCard.ask(parent, "Leave the run?", "This ends the run for everyone.", "Leave", func(): ...)
## Esc or the cancel button closes it without doing anything. Works while the tree is paused.

signal answered(confirmed: bool)

var _on_yes: Callable
var _yes: Button
var _no: Button


## Shows a confirm card over `parent` (full rect). Returns it (already open).
static func ask(parent: Node, title: String, text: String, yes_text: String, on_yes: Callable, danger := true) -> ConfirmCard:
	var c := ConfirmCard.new()
	c._on_yes = on_yes
	parent.add_child(c)
	c._build(title, text, yes_text, danger)
	return c


func _build(title: String, text: String, yes_text: String, danger: bool) -> void:
	name = "ConfirmCard"
	process_mode = Node.PROCESS_MODE_ALWAYS
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	var dim := ColorRect.new()
	dim.color = Color(UiTheme.INK, 0.55)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(dim)
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(center)
	var card := PanelContainer.new()
	card.theme_type_variation = &"WoodPanel"
	card.custom_minimum_size = Vector2(520, 0)
	center.add_child(card)
	var paper := PanelContainer.new()
	paper.theme_type_variation = &"PaperPanel"
	card.add_child(paper)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 12)
	paper.add_child(col)
	var t := Label.new()
	t.text = title
	t.add_theme_font_size_override("font_size", 30)
	t.add_theme_color_override("font_color", UiTheme.INK)
	t.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(t)
	var body := Label.new()
	body.text = text
	body.theme_type_variation = &"MutedLabel"
	body.add_theme_font_size_override("font_size", 19)
	body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	body.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	body.custom_minimum_size = Vector2(460, 0)
	col.add_child(body)
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 14)
	col.add_child(row)
	_no = Button.new()
	_no.text = "Cancel"
	_no.theme_type_variation = &"BigButton"
	_no.custom_minimum_size = Vector2(180, 0)
	_no.pressed.connect(cancel)
	row.add_child(_no)
	_yes = Button.new()
	_yes.text = yes_text
	_yes.theme_type_variation = &"DangerButton" if danger else &"AccentButton"
	_yes.custom_minimum_size = Vector2(180, 0)
	_yes.pressed.connect(confirm)
	row.add_child(_yes)
	card.pivot_offset = card.get_combined_minimum_size() * 0.5
	card.scale = Vector2(0.92, 0.92)
	var tw := create_tween().set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.tween_property(card, "scale", Vector2.ONE, 0.2)
	_no.grab_focus.call_deferred()


func confirm() -> void:
	if is_queued_for_deletion():
		return
	answered.emit(true)
	queue_free()
	if _on_yes.is_valid():
		_on_yes.call()


func cancel() -> void:
	if is_queued_for_deletion():
		return
	answered.emit(false)
	queue_free()


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("pause") or event.is_action_pressed("ui_cancel"):
		get_viewport().set_input_as_handled()
		cancel()
