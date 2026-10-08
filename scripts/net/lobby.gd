extends Control
## The crew lobby (scenes/net/Lobby.tscn): who is coming along, who is ready, and how to invite friends.
##   Host:   player cards (colour, name, crown, ready tick, kick), the invite code with Copy, LAN addresses,
##           optional UPnP, and Start (when everyone is ready, or alone = a plain offline solo run).
##   Client: the same cards and a big Ready toggle; the host starts.
## Opened without a connection (no main menu in this build, or after a disconnect) it shows a small Play card:
## solo, host, or join by code / IP. Uses the shared UiTheme when it exists (menus workstream), else a matching
## fallback built here.

const UI_THEME_PATH := "res://scripts/ui/menu/ui_theme.gd"
const MENU_BACKGROUND_PATH := "res://scripts/ui/menu/menu_background.gd"

# Palette (same values as UiTheme's, so the lobby looks the same with or without it)
const CREAM := Color("f7ecd6")
const CREAM_DARK := Color("e9d6b1")
const PAPER := Color("fff6e0")
const WOOD := Color("9a6a42")
const WOOD_DARK := Color("6b4428")
const WOOD_LIGHT := Color("b98a5c")
const INK := Color("2a1c13")
const INK_SOFT := Color("5a4334")
const RUST := Color("cf5b2e")
const RUST_DARK := Color("a5431f")
const TEAL := Color("2e8c84")
const TEAL_DARK := Color("1f6660")
const HONEY := Color("ffd27a")
const GREEN := Color("62b84a")

enum Mode { PLAY, CONNECTING, ROOM }

var _mode := -1
var _ui_theme: Script
var _status: Label
var _title_label: Label
var _tagline: Label
var _body: Control           # the current mode's content
var _cards: VBoxContainer
var _card_nodes := {}        # peer id -> PanelContainer
var _count_label: Label
var _code_label: Label
var _lan_label: Label
var _upnp_label: Label
var _upnp_button: Button
var _start_button: Button
var _ready_button: Button
var _hint: Label
var _name_edit: LineEdit
var _join_edit: LineEdit
var _port_edit: LineEdit
var _connect_label: Label


func _ready() -> void:
	get_tree().paused = false
	Game.ui_open = false
	if DisplayServer.get_name() != "headless":
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	if ResourceLoader.exists(UI_THEME_PATH):
		_ui_theme = load(UI_THEME_PATH)
		theme = _ui_theme.call("build")
	else:
		theme = _fallback_theme()
	_build_backdrop()
	_build_frame()
	Net.players_changed.connect(_refresh)
	Net.joined.connect(_refresh_mode)
	Net.connection_failed.connect(_on_failed)
	Net.upnp_finished.connect(func(_ok: bool, _text: String): _refresh())
	_refresh_mode()
	if Net.last_error != "" and _mode == Mode.PLAY:
		_set_status(Net.last_error, true)


func _process(_delta: float) -> void:
	var want := Mode.PLAY
	if Net.is_connecting():
		want = Mode.CONNECTING
	elif Net.is_online() and Net.players.has(Net.local_id()):
		want = Mode.ROOM
	if want != _mode:
		_refresh_mode()


# --- Frame ------------------------------------------------------------------------------------

func _build_backdrop() -> void:
	if ResourceLoader.exists(MENU_BACKGROUND_PATH):
		# the menu's slow camera over the station, under a warm shade
		var bg: Node = load(MENU_BACKGROUND_PATH).new()
		bg.name = "Background"
		add_child(bg)
		var shade := ColorRect.new()
		shade.color = Color(INK, 0.45)
		shade.set_anchors_preset(Control.PRESET_FULL_RECT)
		shade.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(shade)
		return
	var grad := Gradient.new()
	grad.set_color(0, Color("4a2f1c"))
	grad.set_color(1, Color("21150d"))
	var tex := GradientTexture2D.new()
	tex.gradient = grad
	tex.fill = GradientTexture2D.FILL_RADIAL
	tex.fill_from = Vector2(0.5, 0.35)
	tex.fill_to = Vector2(1.1, 1.1)
	var bg_rect := TextureRect.new()
	bg_rect.texture = tex
	bg_rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	bg_rect.stretch_mode = TextureRect.STRETCH_SCALE
	bg_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(bg_rect)
	# railway sleepers along the bottom, a little nod to the track
	var rails := _Sleepers.new()
	rails.set_anchors_preset(Control.PRESET_FULL_RECT)
	rails.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(rails)


func _build_frame() -> void:
	var margin := MarginContainer.new()
	margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	for side in ["left", "right"]:
		margin.add_theme_constant_override("margin_" + side, 64)
	margin.add_theme_constant_override("margin_top", 36)
	margin.add_theme_constant_override("margin_bottom", 36)
	add_child(margin)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 14)
	margin.add_child(col)
	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 22)
	col.add_child(head)
	_title_label = _title("CREW LOBBY", 72)
	head.add_child(_title_label)
	var sub := VBoxContainer.new()
	sub.alignment = BoxContainer.ALIGNMENT_CENTER
	sub.add_theme_constant_override("separation", 0)
	head.add_child(sub)
	_tagline = Label.new()
	_tagline.theme_type_variation = &"HudLabel"
	_tagline.add_theme_font_size_override("font_size", 22)
	sub.add_child(_tagline)
	_status = Label.new()
	_status.theme_type_variation = &"HudSmall"
	_status.add_theme_font_size_override("font_size", 19)
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	sub.add_child(_status)
	_body = Control.new()
	_body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	col.add_child(_body)


func _set_status(text: String, error := false) -> void:
	_status.text = text
	_status.add_theme_color_override("font_color", Color("ffb08a") if error else CREAM)


func _refresh_mode() -> void:
	var mode := Mode.PLAY
	if Net.is_connecting():
		mode = Mode.CONNECTING
	elif Net.is_online() and Net.players.has(Net.local_id()):
		mode = Mode.ROOM
	if mode == _mode:
		_refresh()
		return
	_mode = mode
	for c in _body.get_children():
		c.queue_free()
	_card_nodes.clear()
	match mode:
		Mode.PLAY:
			_title_label.text = "ALL ABOARD"
			_tagline.text = "Play solo, host a game for your friends, or join one with an invite code."
			_build_play()
		Mode.CONNECTING:
			_title_label.text = "CREW LOBBY"
			_tagline.text = "Knocking on the host's door…"
			_build_connecting()
		Mode.ROOM:
			_title_label.text = "CREW LOBBY"
			_tagline.text = "Gather your crew. The train leaves when the host says so."
			_build_room()
	_refresh()


# --- PLAY (offline) ----------------------------------------------------------------------------

func _build_play() -> void:
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	_body.add_child(center)
	var wood := _panel(&"WoodPanel", Vector2(640, 0))
	center.add_child(wood)
	var paper := _panel(&"PaperPanel", Vector2.ZERO)
	wood.add_child(paper)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 14)
	paper.add_child(col)
	col.add_child(_header("Your name"))
	_name_edit = _line(Net.my_name(), "Engineer")
	_name_edit.text_changed.connect(_on_name_changed)
	col.add_child(_name_edit)
	col.add_child(HSeparator.new())
	var solo := _button("Play solo", &"AccentButton", func(): Net.start_solo())
	col.add_child(solo)
	col.add_child(HSeparator.new())
	col.add_child(_header("Host a game"))
	var host_row := HBoxContainer.new()
	col.add_child(host_row)
	var pl := Label.new()
	pl.text = "Port"
	pl.theme_type_variation = &"MutedLabel"
	host_row.add_child(pl)
	_port_edit = _line(str(Net.DEFAULT_PORT), str(Net.DEFAULT_PORT))
	_port_edit.custom_minimum_size.x = 130
	host_row.add_child(_port_edit)
	var host := _button("Host", &"BigButton", _on_host)
	host.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	host_row.add_child(host)
	col.add_child(_header("Join a friend"))
	var join_row := HBoxContainer.new()
	col.add_child(join_row)
	_join_edit = _line("", "Invite code  or  192.168.1.20:24565")
	_join_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_join_edit.text_submitted.connect(func(_t: String): _on_join())
	join_row.add_child(_join_edit)
	join_row.add_child(_button("Join", &"", _on_join))
	if ResourceLoader.exists(Net.MENU_SCENE):
		col.add_child(_button("Back to the main menu", &"", func(): Net.go_to_menu()))
	else:
		col.add_child(_button("Quit", &"", func(): get_tree().quit()))


func _on_host() -> void:
	var p := int(_port_edit.text) if _port_edit.text.is_valid_int() else Net.DEFAULT_PORT
	if Net.host_game(clampi(p, 1024, 65535)) == OK:
		_set_status("")
		_refresh_mode()


func _on_join() -> void:
	if Net.join_game(_join_edit.text) == OK:
		_set_status("")
		_refresh_mode()


func _on_failed(reason: String) -> void:
	_set_status(reason, true)
	_refresh_mode()


func _on_name_changed(text: String) -> void:
	Net.set_local_name(text)
	var settings := get_node_or_null(^"/root/Settings")
	if settings and settings.has_method("set_value") and text.strip_edges() != "":
		settings.call("set_value", "profile", "name", Net.clean_name(text))


# --- CONNECTING ----------------------------------------------------------------------------------

func _build_connecting() -> void:
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	_body.add_child(center)
	var paper := _panel(&"PaperPanel", Vector2(560, 0))
	center.add_child(paper)
	var col := VBoxContainer.new()
	col.alignment = BoxContainer.ALIGNMENT_CENTER
	paper.add_child(col)
	_connect_label = Label.new()
	_connect_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_connect_label.add_theme_font_size_override("font_size", 26)
	col.add_child(_connect_label)
	var spinner := _Spinner.new()
	spinner.custom_minimum_size = Vector2(0, 70)
	col.add_child(spinner)
	col.add_child(_button("Cancel", &"", func():
		Net.leave()
		_refresh_mode()))


# --- ROOM -------------------------------------------------------------------------------------------

func _build_room() -> void:
	var col := VBoxContainer.new()
	col.set_anchors_preset(Control.PRESET_FULL_RECT)
	col.add_theme_constant_override("separation", 16)
	_body.add_child(col)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 24)
	row.size_flags_vertical = Control.SIZE_EXPAND_FILL
	col.add_child(row)

	# Left: the crew
	var crew := _panel(&"PaperPanel", Vector2.ZERO)
	crew.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	crew.size_flags_stretch_ratio = 1.6
	row.add_child(crew)
	var crew_col := VBoxContainer.new()
	crew_col.add_theme_constant_override("separation", 10)
	crew.add_child(crew_col)
	var crew_head := HBoxContainer.new()
	crew_col.add_child(crew_head)
	var h := _header("The crew")
	h.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	crew_head.add_child(h)
	_count_label = _chip_label("1 / %d" % Net.MAX_PLAYERS)
	crew_head.add_child(_count_label.get_parent())
	_cards = VBoxContainer.new()
	_cards.add_theme_constant_override("separation", 8)
	crew_col.add_child(_cards)
	var foot := Label.new()
	foot.theme_type_variation = &"MutedLabel"
	foot.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	foot.text = "1-2 players: pure co-op, the world itself sabotages you.  3-5 players: one of you is secretly the impostor."
	crew_col.add_child(foot)

	# Right: the invite
	var inv := _panel(&"WoodPanel", Vector2(520, 0))
	inv.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(inv)
	var inv_col := VBoxContainer.new()
	inv_col.add_theme_constant_override("separation", 12)
	inv.add_child(inv_col)
	var ih := _header("Invite friends")
	ih.add_theme_color_override("font_color", HONEY)
	inv_col.add_child(ih)
	var code_box := _panel(&"PaperPanel", Vector2.ZERO)
	inv_col.add_child(code_box)
	var code_col := VBoxContainer.new()
	code_col.add_theme_constant_override("separation", 6)
	code_box.add_child(code_col)
	var cl := Label.new()
	cl.text = "Invite code"
	cl.theme_type_variation = &"MutedLabel"
	cl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	code_col.add_child(cl)
	_code_label = Label.new()
	_code_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_code_label.add_theme_font_size_override("font_size", 52)
	_code_label.add_theme_color_override("font_color", RUST_DARK)
	_code_label.add_theme_constant_override("outline_size", 0)
	var mono := SystemFont.new()
	mono.font_names = PackedStringArray(["DejaVu Sans Mono", "Consolas", "Menlo", "monospace"])
	mono.font_weight = 800
	_code_label.add_theme_font_override("font", mono)
	code_col.add_child(_code_label)
	var copy := _button("Copy code", &"AccentButton", _copy_code)
	copy.icon = null
	code_col.add_child(copy)
	_lan_label = Label.new()
	_lan_label.theme_type_variation = &"HudSmall"
	_lan_label.add_theme_font_size_override("font_size", 18)
	_lan_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	inv_col.add_child(_lan_label)
	if Net.is_host():
		var up_row := HBoxContainer.new()
		inv_col.add_child(up_row)
		_upnp_button = _button("Open the port (UPnP)", &"", func():
			Net.open_upnp()
			_refresh())
		up_row.add_child(_upnp_button)
		_upnp_label = Label.new()
		_upnp_label.theme_type_variation = &"HudSmall"
		_upnp_label.add_theme_font_size_override("font_size", 17)
		_upnp_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		_upnp_label.custom_minimum_size.x = 200
		_upnp_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		up_row.add_child(_upnp_label)
	var spacer := Control.new()
	spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	inv_col.add_child(spacer)
	var name_row := HBoxContainer.new()
	inv_col.add_child(name_row)
	var nl := Label.new()
	nl.text = "Your name"
	nl.theme_type_variation = &"HudLabel"
	name_row.add_child(nl)
	_name_edit = _line(Net.player_name(Net.local_id()), "Engineer")
	_name_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_name_edit.text_changed.connect(_on_name_changed)
	name_row.add_child(_name_edit)

	# Bottom bar on a dark strip
	var strip := PanelContainer.new()
	var ss := StyleBoxFlat.new()
	ss.bg_color = Color(INK, 0.72)
	ss.set_corner_radius_all(18)
	ss.set_border_width_all(3)
	ss.border_color = Color(WOOD_DARK, 0.9)
	ss.content_margin_left = 14
	ss.content_margin_right = 14
	ss.content_margin_top = 10
	ss.content_margin_bottom = 10
	strip.add_theme_stylebox_override("panel", ss)
	col.add_child(strip)
	var bar := HBoxContainer.new()
	bar.add_theme_constant_override("separation", 18)
	strip.add_child(bar)
	bar.add_child(_button("Leave", &"DangerButton", func(): Net.leave_to_menu()))
	_hint = Label.new()
	_hint.theme_type_variation = &"HudLabel"
	_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_hint.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bar.add_child(_hint)
	if Net.is_host():
		_start_button = _button("Start the run", &"AccentButton", func(): Net.start_run())
		_start_button.custom_minimum_size.x = 300
		bar.add_child(_start_button)
	else:
		_ready_button = _button("I'm ready", &"AccentButton", func(): Net.set_ready(not _my_ready()))
		_ready_button.custom_minimum_size.x = 300
		bar.add_child(_ready_button)


func _my_ready() -> bool:
	return Net.players.has(Net.local_id()) and bool(Net.players[Net.local_id()].ready)


func _copy_code() -> void:
	if DisplayServer.get_name() != "headless":
		DisplayServer.clipboard_set(Net.invite_code())
	_set_status("Invite code copied: %s" % Net.invite_code())


# --- Refresh -------------------------------------------------------------------------------------

func _refresh() -> void:
	match _mode:
		Mode.CONNECTING:
			if _connect_label:
				_connect_label.text = "Connecting to %s" % Net.joined_address
		Mode.ROOM:
			_refresh_room()


func _refresh_room() -> void:
	if _cards == null:
		return
	var ids: Array = Net.players.keys()
	ids.sort()
	# remove cards of players who left
	for id: int in _card_nodes.keys():
		if not id in ids:
			_card_nodes[id].queue_free()
			_card_nodes.erase(id)
	for c in _cards.get_children():
		if c.has_meta("empty"):
			c.queue_free()
	for id: int in ids:
		if not _card_nodes.has(id):
			var card := _player_card(id)
			_cards.add_child(card)
			_card_nodes[id] = card
			card.pivot_offset = Vector2(40, 40)
			card.scale = Vector2(0.9, 0.9)
			card.modulate.a = 0.0
			var tw := card.create_tween().set_parallel().set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
			tw.tween_property(card, "scale", Vector2.ONE, 0.3)
			tw.tween_property(card, "modulate:a", 1.0, 0.2)
		_update_card(id)
	# keep host first, then join order
	for i in ids.size():
		_cards.move_child(_card_nodes[ids[i]], i)
	for k in Net.MAX_PLAYERS - ids.size():
		_cards.add_child(_empty_card())
	_count_label.text = "%d / %d" % [ids.size(), Net.MAX_PLAYERS]
	_code_label.text = Net.invite_code()
	if Net.is_host():
		var lan := Net.lan_addresses()
		var lines := PackedStringArray()
		lines.append("Same Wi-Fi / LAN: %s" % (", ".join(Array(lan).map(func(a: String): return "%s:%d" % [a, Net.port])) if not lan.is_empty() else "no network found"))
		if Net.external_ip != "":
			lines.append("Internet: %s:%d (the code above uses it)" % [Net.external_ip, Net.port])
		else:
			lines.append("Over the internet: forward UDP port %d to this PC, or try UPnP below." % Net.port)
		lines.append("This PC: 127.0.0.1:%d" % Net.port)
		_lan_label.text = "\n".join(lines)
		_upnp_label.text = Net.upnp_status
		_upnp_button.disabled = Net.external_ip != "" or Net.upnp_status.ends_with("…")
		var waiting := 0
		for id: int in ids:
			if not Net.players[id].host and not Net.players[id].ready:
				waiting += 1
		_start_button.disabled = not Net.can_start()
		_start_button.text = "Start solo" if ids.size() == 1 else "Start the run"
		if ids.size() == 1:
			_hint.text = "Alone? Start solo, or share the code and wait for friends."
		elif waiting > 0:
			_hint.text = "Waiting for %d player%s to be ready…" % [waiting, "" if waiting == 1 else "s"]
		else:
			_hint.text = "Everyone is ready!"
	else:
		_lan_label.text = "Connected to %s\nShare the code: friends join the same host." % Net.joined_address
		var ready := _my_ready()
		_ready_button.text = "Ready!" if ready else "I'm ready"
		_ready_button.theme_type_variation = &"BigButton" if ready else &"AccentButton"
		_hint.text = "Waiting for the host to start…" if ready else "Press Ready when you are set."


func _player_card(id: int) -> PanelContainer:
	var card := PanelContainer.new()
	card.add_theme_stylebox_override("panel", _card_style(INK))
	card.custom_minimum_size = Vector2(0, 74)
	var row := HBoxContainer.new()
	row.name = "Row"
	row.add_theme_constant_override("separation", 14)
	card.add_child(row)
	var avatar := _Avatar.new()
	avatar.name = "Avatar"
	avatar.custom_minimum_size = Vector2(56, 56)
	avatar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(avatar)
	var names := VBoxContainer.new()
	names.name = "Names"
	names.alignment = BoxContainer.ALIGNMENT_CENTER
	names.add_theme_constant_override("separation", 0)
	names.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(names)
	var name_row := HBoxContainer.new()
	name_row.name = "NameRow"
	name_row.add_theme_constant_override("separation", 8)
	names.add_child(name_row)
	var n := Label.new()
	n.name = "Name"
	n.add_theme_font_size_override("font_size", 28)
	name_row.add_child(n)
	var crown := NetIcon.create("crown", 30, HONEY)
	crown.name = "Crown"
	crown.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	name_row.add_child(crown)
	var sub := Label.new()
	sub.name = "Sub"
	sub.theme_type_variation = &"MutedLabel"
	sub.add_theme_font_size_override("font_size", 17)
	names.add_child(sub)
	var pill := PanelContainer.new()
	pill.name = "Pill"
	pill.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(pill)
	var pill_row := HBoxContainer.new()
	pill_row.name = "PillRow"
	pill_row.add_theme_constant_override("separation", 6)
	pill.add_child(pill_row)
	var tick := NetIcon.create("tick", 26, GREEN)
	tick.name = "Tick"
	pill_row.add_child(tick)
	var pl := Label.new()
	pl.name = "PillText"
	pl.add_theme_font_size_override("font_size", 19)
	pill_row.add_child(pl)
	if Net.is_host() and id != Net.local_id():
		var kick := Button.new()
		kick.name = "Kick"
		kick.text = "Kick"
		kick.theme_type_variation = &"DangerButton"
		kick.tooltip_text = "Remove this player from the lobby"
		kick.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		kick.pressed.connect(func(): Net.kick(id))
		row.add_child(kick)
	return card


func _update_card(id: int) -> void:
	var card: PanelContainer = _card_nodes[id]
	var e: Dictionary = Net.players[id]
	var color: Color = e.color
	# a stripe in the player's colour on the left edge
	card.add_theme_stylebox_override("panel", _card_style(color.darkened(0.1)))
	(card.get_node("Row/Avatar") as _Avatar).setup(str(e.name), color)
	(card.get_node("Row/Names/NameRow/Name") as Label).text = str(e.name)
	(card.get_node("Row/Names/NameRow/Crown") as Control).visible = bool(e.host)
	var bits := PackedStringArray()
	if e.host:
		bits.append("Host")
	if id == Net.local_id():
		bits.append("You")
	(card.get_node("Row/Names/Sub") as Label).text = " · ".join(bits) if not bits.is_empty() else "Crew"
	var ready: bool = e.host or e.ready
	var ps := StyleBoxFlat.new()
	ps.bg_color = Color("dff0cf") if ready else CREAM_DARK
	ps.set_corner_radius_all(18)
	ps.set_border_width_all(3)
	ps.border_color = INK
	ps.content_margin_left = 8
	ps.content_margin_right = 14
	ps.content_margin_top = 4
	ps.content_margin_bottom = 4
	var pill := card.get_node("Row/Pill") as PanelContainer
	pill.add_theme_stylebox_override("panel", ps)
	(pill.get_node("PillRow/Tick") as NetIcon).set_kind("tick" if ready else "cross", GREEN if ready else WOOD_LIGHT)
	(pill.get_node("PillRow/PillText") as Label).text = ("Host" if e.host else "Ready") if ready else "Not ready"


func _card_style(stripe: Color) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = CREAM
	sb.set_corner_radius_all(14)
	sb.set_border_width_all(3)
	sb.border_width_left = 12
	sb.border_color = stripe
	sb.content_margin_left = 16
	sb.content_margin_right = 14
	sb.content_margin_top = 8
	sb.content_margin_bottom = 8
	sb.shadow_color = Color(0, 0, 0, 0.25)
	sb.shadow_size = 3
	sb.shadow_offset = Vector2(0, 3)
	return sb


func _empty_card() -> Control:
	var card := PanelContainer.new()
	card.set_meta("empty", true)
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(CREAM_DARK, 0.45)
	sb.set_corner_radius_all(14)
	sb.set_border_width_all(2)
	sb.border_color = Color(INK, 0.25)
	sb.content_margin_left = 20
	card.add_theme_stylebox_override("panel", sb)
	card.custom_minimum_size = Vector2(0, 58)
	var l := Label.new()
	l.text = "Free seat: waiting for a friend…"
	l.theme_type_variation = &"MutedLabel"
	l.add_theme_color_override("font_color", Color(INK_SOFT, 0.7))
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	card.add_child(l)
	return card


# --- Small builders ------------------------------------------------------------------------------

func _title(text: String, size: int) -> Label:
	if _ui_theme:
		return _ui_theme.call("title_label", text, size)
	var l := Label.new()
	l.text = text
	l.theme_type_variation = &"TitleLabel"
	l.add_theme_font_size_override("font_size", size)
	return l


func _header(text: String) -> Label:
	var l := Label.new()
	l.text = text
	l.theme_type_variation = &"HeaderLabel"
	l.add_theme_font_size_override("font_size", 28)
	return l


func _chip_label(text: String) -> Label:
	var chip := PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = TEAL
	sb.set_corner_radius_all(14)
	sb.set_border_width_all(3)
	sb.border_color = INK
	sb.content_margin_left = 14
	sb.content_margin_right = 14
	sb.content_margin_top = 2
	sb.content_margin_bottom = 4
	chip.add_theme_stylebox_override("panel", sb)
	chip.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var l := Label.new()
	l.text = text
	l.add_theme_color_override("font_color", PAPER)
	l.add_theme_font_size_override("font_size", 22)
	chip.add_child(l)
	return l


func _panel(variation: StringName, min_size: Vector2) -> PanelContainer:
	var p := PanelContainer.new()
	p.theme_type_variation = variation
	p.custom_minimum_size = min_size
	return p


func _button(text: String, variation: StringName, action: Callable) -> Button:
	var b := Button.new()
	b.text = text
	if variation != &"":
		b.theme_type_variation = variation
	b.pressed.connect(action)
	return b


func _line(text: String, placeholder: String) -> LineEdit:
	var e := LineEdit.new()
	e.text = text
	e.placeholder_text = placeholder
	e.max_length = 24
	return e


# --- Fallback theme (when the shared UiTheme is not in this build) ---------------------------------

static func _fallback_theme() -> Theme:
	var t := Theme.new()
	var base := ThemeDB.fallback_font
	var bold := FontVariation.new()
	bold.base_font = base
	bold.variation_embolden = 0.6
	var heavy := FontVariation.new()
	heavy.base_font = base
	heavy.variation_embolden = 1.1
	heavy.spacing_glyph = 1
	t.default_font = bold
	t.default_font_size = 22
	t.set_color("font_color", "Label", INK)
	t.set_type_variation("TitleLabel", "Label")
	t.set_font("font", "TitleLabel", heavy)
	t.set_color("font_color", "TitleLabel", CREAM)
	t.set_color("font_outline_color", "TitleLabel", INK)
	t.set_constant("outline_size", "TitleLabel", 14)
	t.set_color("font_shadow_color", "TitleLabel", Color(INK, 0.55))
	t.set_constant("shadow_offset_y", "TitleLabel", 7)
	t.set_constant("shadow_outline_size", "TitleLabel", 14)
	t.set_type_variation("HeaderLabel", "Label")
	t.set_font("font", "HeaderLabel", heavy)
	t.set_color("font_color", "HeaderLabel", RUST_DARK)
	t.set_type_variation("MutedLabel", "Label")
	t.set_font_size("font_size", "MutedLabel", 18)
	t.set_color("font_color", "MutedLabel", INK_SOFT)
	for v in ["HudLabel", "HudSmall"]:
		t.set_type_variation(v, "Label")
		t.set_color("font_color", v, CREAM)
		t.set_color("font_outline_color", v, INK)
		t.set_constant("outline_size", v, 7 if v == "HudLabel" else 5)
	t.set_font_size("font_size", "HudSmall", 16)
	t.set_type_variation("WoodPanel", "PanelContainer")
	t.set_stylebox("panel", "WoodPanel", _box(WOOD, 18, 4, true))
	t.set_type_variation("PaperPanel", "PanelContainer")
	t.set_stylebox("panel", "PaperPanel", _box(PAPER, 14, 3, true))
	t.set_stylebox("panel", "PanelContainer", _box(CREAM, 16, 4, true))
	_buttons(t, "Button", CREAM, HONEY, Color("f0b452"), INK, bold, 22)
	t.set_type_variation("BigButton", "Button")
	_buttons(t, "BigButton", CREAM, HONEY, Color("f0b452"), INK, heavy, 26)
	t.set_type_variation("AccentButton", "Button")
	_buttons(t, "AccentButton", RUST, Color("e87a45"), RUST_DARK, CREAM, heavy, 28)
	t.set_color("font_outline_color", "AccentButton", INK)
	t.set_constant("outline_size", "AccentButton", 6)
	t.set_type_variation("DangerButton", "Button")
	_buttons(t, "DangerButton", Color("e9c7a8"), Color("f08a6e"), Color("c8382a"), INK, bold, 22)
	var le := _box(PAPER, 10, 3, false)
	le.content_margin_left = 14
	le.content_margin_top = 8
	le.content_margin_bottom = 8
	t.set_stylebox("normal", "LineEdit", le)
	var focus := _box(PAPER, 10, 3, false)
	focus.border_color = TEAL
	focus.content_margin_left = 14
	focus.content_margin_top = 8
	focus.content_margin_bottom = 8
	t.set_stylebox("focus", "LineEdit", focus)
	t.set_color("font_color", "LineEdit", INK)
	t.set_color("font_placeholder_color", "LineEdit", Color(INK, 0.4))
	t.set_color("caret_color", "LineEdit", RUST)
	var sep := StyleBoxLine.new()
	sep.color = Color(WOOD, 0.5)
	sep.thickness = 3
	t.set_stylebox("separator", "HSeparator", sep)
	return t


static func _box(color: Color, radius: int, outline: int, shadow: bool) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = color
	sb.set_corner_radius_all(radius)
	sb.set_border_width_all(outline)
	sb.border_color = INK
	sb.corner_detail = 10
	if shadow:
		sb.shadow_color = Color(0.12, 0.07, 0.03, 0.45)
		sb.shadow_size = 6
		sb.shadow_offset = Vector2(0, 5)
	sb.set_content_margin_all(radius + 4)
	return sb


static func _buttons(t: Theme, type: String, base: Color, hover: Color, pressed: Color, text: Color, font: Font, size: int) -> void:
	for state in ["normal", "hover", "pressed", "hover_pressed", "disabled"]:
		var c := base
		if state == "hover":
			c = hover
		elif state.contains("pressed"):
			c = pressed
		var sb := StyleBoxFlat.new()
		sb.bg_color = Color(c, 0.5) if state == "disabled" else c
		sb.set_corner_radius_all(16)
		sb.corner_detail = 10
		sb.set_border_width_all(3)
		sb.border_width_bottom = 4 if state.contains("pressed") else 8
		sb.border_color = Color(INK, 0.45) if state == "disabled" else INK
		sb.content_margin_left = 26
		sb.content_margin_right = 26
		sb.content_margin_top = 10 + (3 if state.contains("pressed") else 0)
		sb.content_margin_bottom = 10 - (3 if state.contains("pressed") else 0)
		t.set_stylebox(state, type, sb)
	t.set_stylebox("focus", type, StyleBoxEmpty.new())
	t.set_font("font", type, font)
	t.set_font_size("font_size", type, size)
	for key in ["font_color", "font_hover_color", "font_pressed_color", "font_hover_pressed_color", "font_focus_color"]:
		t.set_color(key, type, text)
	t.set_color("font_disabled_color", type, Color(text, 0.45))


# --- Little drawn bits -------------------------------------------------------------------------------

## A round badge in the player's colour with their initial.
class _Avatar extends Control:
	var letter := "?"
	var color := Color.WHITE

	func setup(n: String, c: Color) -> void:
		letter = n.substr(0, 1).to_upper() if n != "" else "?"
		color = c
		queue_redraw()

	func _draw() -> void:
		var r := minf(size.x, size.y) * 0.5
		var c := size * 0.5
		draw_circle(c + Vector2(0, 3), r, Color(0, 0, 0, 0.25))
		draw_circle(c, r, Color("2a1c13"))
		draw_circle(c, r - 3.5, color)
		draw_circle(c + Vector2(-r * 0.25, -r * 0.3), r * 0.35, Color(1, 1, 1, 0.18))
		var font := get_theme_default_font()
		var fs := int(r * 1.15)
		var w := font.get_string_size(letter, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
		var pos := c + Vector2(-w * 0.5, fs * 0.36)
		draw_string_outline(font, pos, letter, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, 6, Color("2a1c13"))
		draw_string(font, pos, letter, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color("fff6e0"))


## Three bouncing dots while connecting.
class _Spinner extends Control:
	var t := 0.0

	func _process(delta: float) -> void:
		t += delta
		queue_redraw()

	func _draw() -> void:
		for i in 3:
			var y := size.y * 0.5 - absf(sin(t * 4.0 - i * 0.6)) * 14.0
			draw_circle(Vector2(size.x * 0.5 + (i - 1) * 30.0, y), 9.0, Color("2a1c13"))
			draw_circle(Vector2(size.x * 0.5 + (i - 1) * 30.0, y), 6.0, Color("cf5b2e"))


## Sleepers and two rails across the bottom of the plain backdrop.
class _Sleepers extends Control:
	func _draw() -> void:
		var y := size.y - 34.0
		var x := -20.0
		while x < size.x + 40.0:
			draw_rect(Rect2(x, y - 6, 26, 54), Color("3a2414"))
			draw_rect(Rect2(x + 3, y - 3, 20, 48), Color("4d311c"))
			x += 64.0
		for ry in [y + 4.0, y + 32.0]:
			draw_rect(Rect2(0, ry, size.x, 8), Color("7d746c"))
			draw_rect(Rect2(0, ry, size.x, 3), Color("a39a90"))
