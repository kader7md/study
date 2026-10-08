class_name NetOverlay
extends CanvasLayer
## Net's own little screen layer (it lives in the Net autoload, so it survives scene changes):
## - a "please wait" card while the world loads or the host is reached,
## - a notice card for things like "Host left the game" that stays readable after going back to the menu.

const CREAM := Color(0.98, 0.93, 0.82)
const INK := Color(0.17, 0.12, 0.09)
const RUST := Color(0.78, 0.33, 0.16)
const TEAL := Color(0.16, 0.5, 0.5)

var _wait: PanelContainer
var _wait_label: Label
var _notice: PanelContainer
var _notice_label: Label
var _notice_tween: Tween
var _dots := 0.0
var _wait_text := ""


func _ready() -> void:
	layer = 90
	process_mode = Node.PROCESS_MODE_ALWAYS
	_wait = _card(TEAL)
	_wait_label = _card_label(_wait, 26)
	_place(_wait, 0.5, 0.5, Vector2(0, 0))
	_wait.visible = false
	_notice = _card(RUST)
	_notice_label = _card_label(_notice, 24)
	_place(_notice, 0.5, 0.0, Vector2(0, 40))
	_notice.visible = false


func _process(delta: float) -> void:
	if _wait.visible:
		_dots += delta * 2.0
		_wait_label.text = _wait_text + ".".repeat(int(_dots) % 4)


func show_wait(text: String) -> void:
	_wait_text = text.trim_suffix("…").trim_suffix("...")
	_wait_label.text = _wait_text
	_wait.visible = true


func hide_wait() -> void:
	_wait.visible = false


## A message card at the top of the screen for a few seconds.
func notice(text: String, seconds := 6.0) -> void:
	_notice_label.text = text
	_notice.visible = true
	_notice.modulate.a = 1.0
	if _notice_tween and _notice_tween.is_valid():
		_notice_tween.kill()
	_notice_tween = create_tween()
	_notice_tween.tween_interval(seconds)
	_notice_tween.tween_property(_notice, "modulate:a", 0.0, 0.8)
	_notice_tween.tween_callback(func(): _notice.visible = false)


func _card(accent: Color) -> PanelContainer:
	var p := PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = CREAM
	sb.set_corner_radius_all(16)
	sb.set_border_width_all(4)
	sb.border_width_left = 14  # a thick accent edge on the left
	sb.border_color = accent.darkened(0.2)
	sb.shadow_color = Color(0, 0, 0, 0.35)
	sb.shadow_size = 8
	sb.shadow_offset = Vector2(0, 5)
	sb.content_margin_left = 30
	sb.content_margin_right = 26
	sb.content_margin_top = 14
	sb.content_margin_bottom = 16
	p.add_theme_stylebox_override("panel", sb)
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(p)
	return p


func _card_label(card: PanelContainer, size: int) -> Label:
	var l := Label.new()
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", INK)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.custom_minimum_size = Vector2(420, 0)
	card.add_child(l)
	return l


func _place(c: Control, ax: float, ay: float, offset: Vector2) -> void:
	c.anchor_left = ax
	c.anchor_right = ax
	c.anchor_top = ay
	c.anchor_bottom = ay
	c.grow_horizontal = Control.GROW_DIRECTION_BOTH
	c.grow_vertical = Control.GROW_DIRECTION_BOTH if ay == 0.5 else Control.GROW_DIRECTION_END
	c.offset_left = offset.x
	c.offset_right = offset.x
	c.offset_top = offset.y
	c.offset_bottom = offset.y
