class_name CrewList
extends PanelContainer
## Small HUD card listing the crew in an online run: colour dot, name, a crown for the host, "(you)", and a speaker
## mark while someone talks on voice chat. Added with HUD.add_corner_widget when the HUD has it.

const CREAM := Color(0.98, 0.93, 0.82, 0.92)
const INK := Color(0.17, 0.12, 0.09)

var _box: VBoxContainer
var _rows := {}   # peer id -> Label


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	var sb := StyleBoxFlat.new()
	sb.bg_color = CREAM
	sb.set_corner_radius_all(12)
	sb.set_border_width_all(3)
	sb.border_color = INK
	sb.content_margin_left = 12
	sb.content_margin_right = 12
	sb.content_margin_top = 6
	sb.content_margin_bottom = 8
	add_theme_stylebox_override("panel", sb)
	_box = VBoxContainer.new()
	_box.add_theme_constant_override("separation", 2)
	add_child(_box)
	var title := Label.new()
	title.text = "CREW"
	title.add_theme_font_size_override("font_size", 15)
	title.add_theme_color_override("font_color", INK.lightened(0.3))
	_box.add_child(title)
	Net.players_changed.connect(_rebuild)
	_rebuild()


## Without HUD.add_corner_widget: top right, under the train status text.
func place_default() -> void:
	anchor_left = 1.0
	anchor_right = 1.0
	offset_left = -230
	offset_right = -20
	offset_top = 96
	grow_horizontal = Control.GROW_DIRECTION_BEGIN


func _rebuild() -> void:
	for id: int in _rows:
		_rows[id].get_parent().queue_free()
	_rows.clear()
	var ids: Array = Net.players.keys()
	ids.sort()
	for id: int in ids:
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 8)
		var dot := ColorRect.new()
		dot.color = Net.player_color(id)
		dot.custom_minimum_size = Vector2(14, 14)
		dot.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		row.add_child(dot)
		var l := Label.new()
		l.add_theme_font_size_override("font_size", 18)
		l.add_theme_color_override("font_color", INK)
		row.add_child(l)
		_box.add_child(row)
		_rows[id] = l
	_process(0.0)


func _process(_delta: float) -> void:
	for id: int in _rows:
		if not Net.players.has(id):
			continue
		var text: String = ("♛ " if Net.players[id].host else "") + Net.player_name(id)
		if id == Net.local_id():
			text += " (you)"
		var voice: Node = Net.get_node_or_null("Voice")
		if voice and voice.has_method("is_speaking") and voice.is_speaking(id):
			text += "  ((•))"
		_rows[id].text = text
