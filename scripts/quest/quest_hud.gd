class_name QuestHud
extends CanvasLayer
## Quest-map UI: the stamina bar (a fallback: when the HUD has set_stamina(value, visible) it draws the bar beside
## health and frost instead), the crew's ropes, the last camp and a climbing hint. Only visible inside a quest map.

const W := 340.0

var quest: QuestManager
var _root: Control
var _bar_bg: Panel
var _bar: ColorRect
var _cold: ColorRect
var _info: Label
var _hint: Label
var _flash := 0.0


func _ready() -> void:
	layer = 5
	_root = Control.new()
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_root)
	_bar_bg = Panel.new()
	_bar_bg.anchor_left = 0.5
	_bar_bg.anchor_right = 0.5
	_bar_bg.anchor_top = 1.0
	_bar_bg.anchor_bottom = 1.0
	_bar_bg.offset_left = -W * 0.5 - 4
	_bar_bg.offset_right = W * 0.5 + 4
	_bar_bg.offset_top = -132
	_bar_bg.offset_bottom = -110
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.12, 0.09, 0.06, 0.8)
	sb.set_corner_radius_all(8)
	sb.border_color = Color(0.95, 0.88, 0.72, 0.9)
	sb.set_border_width_all(2)
	_bar_bg.add_theme_stylebox_override("panel", sb)
	_bar_bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(_bar_bg)
	_bar = ColorRect.new()
	_bar.color = Color(0.95, 0.75, 0.18)
	_bar.position = Vector2(4, 4)
	_bar.size = Vector2(W, 14)
	_bar_bg.add_child(_bar)
	_cold = ColorRect.new()
	_cold.color = Color(0.45, 0.7, 1.0, 0.85)
	_cold.position = Vector2(4 + W, 4)
	_cold.size = Vector2(0, 14)
	_bar_bg.add_child(_cold)
	var tag := Label.new()
	tag.text = "STAMINA"
	tag.add_theme_font_size_override("font_size", 13)
	tag.add_theme_color_override("font_color", Color(1, 0.97, 0.88))
	tag.add_theme_color_override("font_outline_color", Color(0.1, 0.06, 0.03))
	tag.add_theme_constant_override("outline_size", 5)
	tag.position = Vector2(8, -20)
	_bar_bg.add_child(tag)
	_info = _label(Vector2(16, 0))
	_info.anchor_top = 0.5
	_info.anchor_bottom = 0.5
	_info.offset_top = 40
	_hint = _label(Vector2(16, 0))
	_hint.anchor_top = 0.5
	_hint.anchor_bottom = 0.5
	_hint.offset_top = 70
	_hint.add_theme_font_size_override("font_size", 15)
	refresh()


func _label(pos: Vector2) -> Label:
	var l := Label.new()
	l.position = pos
	l.add_theme_font_size_override("font_size", 18)
	l.add_theme_color_override("font_color", Color(1, 0.96, 0.86))
	l.add_theme_color_override("font_outline_color", Color(0.1, 0.06, 0.03))
	l.add_theme_constant_override("outline_size", 6)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(l)
	return l


func refresh() -> void:
	if _root == null:
		return
	var on := quest != null and quest.active
	_root.visible = on
	if on and quest.map:
		_info.text = "%s  ·  ropes: %d  ·  checkpoint: %s" % [quest.map.title, quest.ropes, quest.map.camp_name(quest.camp)]
		_hint.text = "Hold %s on steep rock to climb  ·  %s while climbing: lunge  ·  %s on a crewmate: boost / pull up" % [
			Settings.key_hint("climb"), Settings.key_hint("jump"), Settings.key_hint("interact")]


func _process(delta: float) -> void:
	var p := _player()
	var on := quest != null and quest.active and p != null
	var hud: Node = quest.main.get("hud") if quest and quest.main else null
	var external := hud != null and hud.has_method("set_stamina")
	if external:
		hud.call("set_stamina", p.stamina if p else 100.0, on)
	if not on:
		return
	_bar_bg.visible = not external
	var frac := clampf(p.stamina / Climber.MAX_STAMINA, 0.0, 1.0)
	var max_frac := clampf(p.max_stamina / Climber.MAX_STAMINA, 0.0, 1.0)
	_bar.size.x = W * frac
	_cold.position.x = 4 + W * max_frac
	_cold.size.x = W * (1.0 - max_frac)
	_flash += delta * 8.0
	if p.is_hanging or frac < 0.2:
		_bar.color = Color(0.95, 0.25, 0.12).lerp(Color(1, 0.8, 0.3), 0.5 + 0.5 * sin(_flash))
	else:
		_bar.color = Color(0.95, 0.75, 0.18)


func _player() -> Player:
	if quest and quest.main and quest.main.get("player") is Player:
		return quest.main.get("player")
	return null
