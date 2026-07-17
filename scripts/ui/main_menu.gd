extends Control
## EE COMBAT / DREAMERS DESIGN — main menu.
## Tabbed start screen: PLAY (join the shared online world / LAN), BATTLE
## (online lobbies for every mode + offline vs bots), PROFILE (name + the
## original EE smiley picker). The scene supplies the aurora shader background;
## all UI is built here.
##
## Online flow: JOIN WORLD drops everyone into ONE persistent sandbox on the
## EE COMBAT server. Mode lobbies: browse/create per mode, the lobby host
## presses START, everyone gets 3-2-1-GO.

var name_input: LineEdit
var host_btn: Button
var join_btn: Button
var ip_input: LineEdit
var port_input: LineEdit
var paste_btn: Button
var status_label: Label
var join_world_btn: Button

var _tab_buttons: Array[Button] = []
var _pages: Array[Control] = []
var _current_tab: int = 0

# Lobby overlay
var _overlay: Control = null
var _browser_box: VBoxContainer = null
var _room_box: VBoxContainer = null
var _lobby_list_box: VBoxContainer = null
var _member_list_box: VBoxContainer = null
var _overlay_title: Label = null
var _room_title: Label = null
var _start_btn: Button = null
var _wait_label: Label = null
var _guns_row: HBoxContainer = null
var _guns_lobby_btn: Button = null
var _mode_tab_btns: Dictionary = {}
var _browse_mode: String = "battle"

# Smiley picker
var _smiley_sheet: Texture2D = null
var _ball_tex: Texture2D = null
var _smiley_btns: Dictionary = {}  # id -> Button
var _picker_preview: TextureRect = null
var _picker_label: Label = null

const ACCENT: Color = Color(0.36, 0.78, 1.0)     # dream cyan
const ACCENT2: Color = Color(0.72, 0.5, 1.0)     # violet
const TAB_NAMES: Array[String] = ["PLAY", "BATTLE", "PROFILE"]
const MODE_LABELS: Dictionary = {
	"battle": "⚔ BATTLE", "boss": "☠ BOSS", "zombies": "🧟 ZOMBIES", "survivors": "🩸 SURVIVORS",
}

var _style_smiley_normal: StyleBoxFlat = null
var _style_smiley_selected: StyleBoxFlat = null

func _ready() -> void:
	# Railway dedicated server boot: skip the menu entirely
	if "--server" in OS.get_cmdline_user_args():
		get_tree().change_scene_to_file.call_deferred("res://scenes/server/server_main.tscn")
		return

	_smiley_sheet = load("res://assets/sprites/ee_smileys_hd.png") as Texture2D
	_ball_tex = load("res://assets/sprites/NEW_SPRITES_BALL/BALL_1_frame1.png") as Texture2D

	_build_ui()

	NetworkManager.connection_succeeded.connect(_on_connected)
	NetworkManager.connection_failed.connect(_on_connect_failed)
	NetworkManager.server_disconnected.connect(_on_server_dc)
	NetworkManager.tunnel_ready.connect(_on_tunnel_ready)

	NetPlay.connected_ok.connect(_on_np_connected)
	NetPlay.connect_failed.connect(_on_np_failed)
	NetPlay.server_lost.connect(_on_np_lost)
	NetPlay.lobbies_updated.connect(_on_lobbies)
	NetPlay.room_updated.connect(_on_room_updated)
	NetPlay.world_joined.connect(_on_world_joined)

	name_input.text = GameState.player_name
	_refresh_picker_selection()
	_select_tab(0)

# ==================== UI construction ====================

func _build_ui() -> void:
	var on_web: bool = OS.has_feature("web")

	# ----- Header: title block -----
	var header: VBoxContainer = VBoxContainer.new()
	header.anchor_left = 0.5
	header.anchor_right = 0.5
	header.offset_left = -400.0
	header.offset_right = 400.0
	header.offset_top = 30.0
	header.add_theme_constant_override("separation", 0)
	add_child(header)

	var title: Label = Label.new()
	title.text = "EE COMBAT" if on_web else "DREAMERS"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 58)
	title.add_theme_color_override("font_color", Color(0.9, 0.97, 1.0))
	title.add_theme_color_override("font_outline_color", Color(0.14, 0.45, 0.8, 0.85))
	title.add_theme_constant_override("outline_size", 10)
	header.add_child(title)

	var title2: Label = Label.new()
	title2.text = "M U L T I P L A Y E R" if on_web else "D  E  S  I  G  N"
	title2.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title2.add_theme_font_size_override("font_size", 22)
	title2.add_theme_color_override("font_color", ACCENT2)
	title2.add_theme_color_override("font_outline_color", Color(0.18, 0.08, 0.32, 0.9))
	title2.add_theme_constant_override("outline_size", 5)
	header.add_child(title2)

	var subtitle: Label = Label.new()
	subtitle.text = "One world. Every mode. Bring your friends."
	subtitle.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	subtitle.add_theme_font_size_override("font_size", 12)
	subtitle.add_theme_color_override("font_color", Color(0.52, 0.58, 0.75))
	header.add_child(subtitle)

	# ----- Center column: tab bar + content panel + status -----
	var column: VBoxContainer = VBoxContainer.new()
	column.anchor_left = 0.5
	column.anchor_right = 0.5
	column.offset_left = -260.0
	column.offset_right = 260.0
	column.offset_top = 168.0
	column.add_theme_constant_override("separation", 10)
	add_child(column)

	var tabs: HBoxContainer = HBoxContainer.new()
	tabs.alignment = BoxContainer.ALIGNMENT_CENTER
	tabs.add_theme_constant_override("separation", 8)
	column.add_child(tabs)
	for i in range(TAB_NAMES.size()):
		var tb: Button = _make_tab(i, TAB_NAMES[i])
		tabs.add_child(tb)
		_tab_buttons.append(tb)

	var panel: PanelContainer = PanelContainer.new()
	panel.add_theme_stylebox_override("panel", _panel_style())
	column.add_child(panel)

	var pm: MarginContainer = MarginContainer.new()
	pm.add_theme_constant_override("margin_left", 24)
	pm.add_theme_constant_override("margin_right", 24)
	pm.add_theme_constant_override("margin_top", 18)
	pm.add_theme_constant_override("margin_bottom", 20)
	panel.add_child(pm)

	var page_play: VBoxContainer = _build_play_page()
	var page_battle: VBoxContainer = _build_battle_page()
	var page_profile: VBoxContainer = _build_profile_page()
	for p in [page_play, page_battle, page_profile]:
		pm.add_child(p)
		_pages.append(p)

	status_label = Label.new()
	status_label.text = ""
	status_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	status_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	status_label.add_theme_font_size_override("font_size", 13)
	status_label.add_theme_color_override("font_color", Color(1, 0.8, 0.3))
	column.add_child(status_label)

	# ----- Footer -----
	if not on_web:
		var quit_btn: Button = EditorToolsDock.make_button("QUIT", Color(0.55, 0.3, 0.3))
		quit_btn.custom_minimum_size = Vector2(110, 36)
		quit_btn.anchor_left = 1.0
		quit_btn.anchor_top = 1.0
		quit_btn.anchor_right = 1.0
		quit_btn.anchor_bottom = 1.0
		quit_btn.offset_left = -128.0
		quit_btn.offset_top = -54.0
		quit_btn.offset_right = -18.0
		quit_btn.offset_bottom = -18.0
		quit_btn.pressed.connect(_on_quit)
		add_child(quit_btn)

	var version: Label = Label.new()
	version.text = "EE COMBAT  ·  online alpha" if on_web else "DREAMERS DESIGN  ·  v0.1 alpha"
	version.add_theme_font_size_override("font_size", 10)
	version.add_theme_color_override("font_color", Color(0.35, 0.38, 0.5))
	version.anchor_top = 1.0
	version.anchor_bottom = 1.0
	version.offset_left = 18.0
	version.offset_top = -32.0
	add_child(version)

	_build_lobby_overlay()

func _panel_style() -> StyleBoxFlat:
	var s: StyleBoxFlat = EditorToolsDock.make_panel_style()
	s.bg_color = Color(0.05, 0.065, 0.12, 0.92)
	s.border_color = Color(0.28, 0.38, 0.6, 0.55)
	s.set_border_width_all(1)
	s.set_corner_radius_all(10)
	s.shadow_color = Color(0, 0, 0, 0.45)
	s.shadow_size = 14
	return s

func _caption(parent: Control, text: String, color: Color = Color(0.62, 0.7, 0.88)) -> void:
	var l: Label = Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", 12)
	l.add_theme_color_override("font_color", color)
	parent.add_child(l)

func _hint(parent: Control, text: String) -> void:
	var l: Label = Label.new()
	l.text = text
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.add_theme_font_size_override("font_size", 10)
	l.add_theme_color_override("font_color", Color(0.48, 0.52, 0.66))
	parent.add_child(l)

# ----- PLAY page -----
func _build_play_page() -> VBoxContainer:
	var v: VBoxContainer = VBoxContainer.new()
	v.add_theme_constant_override("separation", 9)

	_caption(v, "THE WORLD")
	_hint(v, "One shared sandbox for everyone on the server. Build together, it saves forever.")

	join_world_btn = EditorToolsDock.make_button("🌍   JOIN WORLD", Color(0.2, 0.65, 0.5))
	join_world_btn.custom_minimum_size = Vector2(0, 52)
	join_world_btn.add_theme_font_size_override("font_size", 21)
	join_world_btn.tooltip_text = "Everyone joins the SAME persistent world. E = edit, build anything."
	join_world_btn.pressed.connect(_on_join_world)
	v.add_child(join_world_btn)

	if not OS.has_feature("web"):
		var sep: HSeparator = HSeparator.new()
		v.add_child(sep)

		_caption(v, "LAN / TUNNEL (advanced)")
		host_btn = EditorToolsDock.make_button("▶   HOST LOCAL WORLD", Color(0.22, 0.5, 0.78))
		host_btn.custom_minimum_size = Vector2(0, 38)
		host_btn.add_theme_font_size_override("font_size", 14)
		host_btn.tooltip_text = "Hosts YOUR saved world on the port below + opens a tunnel URL."
		host_btn.pressed.connect(_on_host)
		v.add_child(host_btn)

		var row: HBoxContainer = HBoxContainer.new()
		row.add_theme_constant_override("separation", 8)
		ip_input = LineEdit.new()
		ip_input.placeholder_text = "Tunnel URL or IP"
		ip_input.custom_minimum_size = Vector2(0, 32)
		ip_input.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(ip_input)
		paste_btn = EditorToolsDock.make_button("PASTE", Color(0.4, 0.45, 0.6))
		paste_btn.custom_minimum_size = Vector2(64, 32)
		paste_btn.pressed.connect(_on_paste)
		row.add_child(paste_btn)
		port_input = LineEdit.new()
		port_input.text = "7777"
		port_input.placeholder_text = "Port"
		port_input.custom_minimum_size = Vector2(74, 32)
		row.add_child(port_input)
		v.add_child(row)

		join_btn = EditorToolsDock.make_button("JOIN A FRIEND'S WORLD", Color(0.55, 0.45, 0.95))
		join_btn.custom_minimum_size = Vector2(0, 34)
		join_btn.add_theme_font_size_override("font_size", 13)
		join_btn.pressed.connect(_on_join)
		v.add_child(join_btn)
	else:
		# Web build still needs these vars for the shared handlers
		ip_input = LineEdit.new()
		port_input = LineEdit.new()
		port_input.text = "7777"
		host_btn = Button.new()
		join_btn = Button.new()

	return v

# ----- BATTLE page -----
func _build_battle_page() -> VBoxContainer:
	var bv: VBoxContainer = VBoxContainer.new()
	bv.add_theme_constant_override("separation", 8)

	# ---- ONLINE ----
	var online_btn: Button = EditorToolsDock.make_button("🌐  ONLINE LOBBIES — VS FRIENDS", Color(0.16, 0.5, 0.85))
	online_btn.custom_minimum_size = Vector2(0, 50)
	online_btn.add_theme_font_size_override("font_size", 17)
	online_btn.tooltip_text = "Battle / Boss / Zombies / Survivors with real people. Create a lobby, friends join, host hits START — 3, 2, 1, GO!"
	online_btn.pressed.connect(_open_lobbies)
	bv.add_child(online_btn)

	var sep0: HSeparator = HSeparator.new()
	bv.add_child(sep0)

	var bh: Label = Label.new()
	bh.text = "OFFLINE — VS BOTS"
	bh.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	bh.add_theme_font_size_override("font_size", 13)
	bh.add_theme_color_override("font_color", Color(1.0, 0.62, 0.2))
	bv.add_child(bh)

	# Bot count stepper: −  [ 2 BOTS · 1v1v1 ]  +
	var row: HBoxContainer = HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 10)
	bv.add_child(row)
	var minus_btn: Button = EditorToolsDock.make_button("−", Color(0.5, 0.32, 0.32))
	minus_btn.custom_minimum_size = Vector2(38, 32)
	minus_btn.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	row.add_child(minus_btn)
	var count_label: Label = Label.new()
	count_label.custom_minimum_size = Vector2(170, 0)
	count_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	count_label.add_theme_font_size_override("font_size", 14)
	count_label.add_theme_color_override("font_color", Color(0.92, 0.94, 1.0))
	row.add_child(count_label)
	var plus_btn: Button = EditorToolsDock.make_button("+", Color(0.32, 0.5, 0.34))
	plus_btn.custom_minimum_size = Vector2(38, 32)
	plus_btn.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	row.add_child(plus_btn)

	# Guns toggle: OFF = pure hand-to-hand (dash punch + parry shield)
	var guns_btn: Button = EditorToolsDock.make_button("GUNS: ON", Color(0.36, 0.42, 0.58))
	guns_btn.custom_minimum_size = Vector2(0, 32)
	guns_btn.tooltip_text = "Toggle weapons — OFF is a pure dash & parry brawl (the DOOM RAY still drops!)"
	bv.add_child(guns_btn)

	# FIGHT!
	var fight_btn: Button = EditorToolsDock.make_button("FIGHT!", Color(0.82, 0.42, 0.14))
	fight_btn.custom_minimum_size = Vector2(0, 42)
	fight_btn.add_theme_font_size_override("font_size", 18)
	fight_btn.tooltip_text = "10 lives each. Bots hunt everyone — including each other."
	fight_btn.pressed.connect(_on_battle)
	bv.add_child(fight_btn)

	# Compact row for the other three offline modes
	var mrow: HBoxContainer = HBoxContainer.new()
	mrow.add_theme_constant_override("separation", 6)
	bv.add_child(mrow)
	var boss_btn: Button = EditorToolsDock.make_button("☠ BOSS", Color(0.62, 0.18, 0.46))
	boss_btn.custom_minimum_size = Vector2(0, 38)
	boss_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	boss_btn.tooltip_text = "THE WARDEN: 3 lives vs a giant. Parry its slam, MASH LMB in the beam clash!"
	boss_btn.pressed.connect(_on_boss)
	mrow.add_child(boss_btn)
	var surv_btn: Button = EditorToolsDock.make_button("🩸 SURVIVORS", Color(0.55, 0.12, 0.2))
	surv_btn.custom_minimum_size = Vector2(0, 38)
	surv_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	surv_btn.tooltip_text = "15 minutes vs the corrupted smiley horde. Minute 14: THE WARDEN PRIME."
	surv_btn.pressed.connect(_on_survivors)
	mrow.add_child(surv_btn)
	var zomb_btn: Button = EditorToolsDock.make_button("🧟 ZOMBIES", Color(0.25, 0.45, 0.18))
	zomb_btn.custom_minimum_size = Vector2(0, 38)
	zomb_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	zomb_btn.tooltip_text = "UNDEAD BUNKER: rounds, wall guns, MYSTERY BOX, Pack-a-Punch. F = buy/rebuild."
	zomb_btn.pressed.connect(_on_zombies)
	mrow.add_child(zomb_btn)

	var refresh_battle_ui: Callable = func() -> void:
		var n: int = clampi(GameState.battle_bot_count, 1, 3)
		GameState.battle_bot_count = n
		var mode: String = "1v1"
		for i in range(n - 1):
			mode += "v1"
		count_label.text = "%d BOT%s   ·   %s" % [n, "" if n == 1 else "S", mode]
		fight_btn.text = "FIGHT!   %s" % mode
		guns_btn.text = "GUNS: ON" if GameState.battle_guns_enabled else "GUNS: OFF (fists!)"
	minus_btn.pressed.connect(func() -> void:
		GameState.battle_bot_count = maxi(1, GameState.battle_bot_count - 1)
		refresh_battle_ui.call())
	plus_btn.pressed.connect(func() -> void:
		GameState.battle_bot_count = mini(3, GameState.battle_bot_count + 1)
		refresh_battle_ui.call())
	guns_btn.pressed.connect(func() -> void:
		GameState.battle_guns_enabled = not GameState.battle_guns_enabled
		refresh_battle_ui.call())
	refresh_battle_ui.call()

	return bv

# ----- PROFILE page -----
func _build_profile_page() -> VBoxContainer:
	var v: VBoxContainer = VBoxContainer.new()
	v.add_theme_constant_override("separation", 8)

	_caption(v, "PLAYER NAME")
	name_input = LineEdit.new()
	name_input.placeholder_text = "Enter your name..."
	name_input.custom_minimum_size = Vector2(0, 34)
	name_input.text_changed.connect(func(t: String) -> void:
		GameState.player_name = t.strip_edges()
		GameState.save_profile())
	v.add_child(name_input)

	# Selected smiley preview row
	var prow: HBoxContainer = HBoxContainer.new()
	prow.add_theme_constant_override("separation", 10)
	v.add_child(prow)
	_caption(prow, "YOUR SMILEY")
	_picker_preview = TextureRect.new()
	_picker_preview.custom_minimum_size = Vector2(40, 40)
	_picker_preview.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_picker_preview.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_picker_preview.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	prow.add_child(_picker_preview)
	_picker_label = Label.new()
	_picker_label.add_theme_font_size_override("font_size", 11)
	_picker_label.add_theme_color_override("font_color", Color(0.7, 0.78, 0.95))
	prow.add_child(_picker_label)

	# The original EE smiley grid (classic row + gold row) + the DREAMER ball
	_style_smiley_normal = StyleBoxFlat.new()
	_style_smiley_normal.bg_color = Color(0.09, 0.11, 0.19, 0.9)
	_style_smiley_normal.set_corner_radius_all(6)
	_style_smiley_normal.set_border_width_all(1)
	_style_smiley_normal.border_color = Color(0.2, 0.26, 0.4, 0.6)
	_style_smiley_selected = StyleBoxFlat.new()
	_style_smiley_selected.bg_color = Color(0.13, 0.24, 0.38, 1.0)
	_style_smiley_selected.set_corner_radius_all(6)
	_style_smiley_selected.set_border_width_all(2)
	_style_smiley_selected.border_color = ACCENT

	var scroll: ScrollContainer = ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(0, 236)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	v.add_child(scroll)
	var grid_holder: VBoxContainer = VBoxContainer.new()
	grid_holder.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	grid_holder.add_theme_constant_override("separation", 6)
	scroll.add_child(grid_holder)

	_caption(grid_holder, "DREAMER")
	var ball_grid: GridContainer = GridContainer.new()
	ball_grid.columns = 11
	ball_grid.add_theme_constant_override("h_separation", 3)
	ball_grid.add_theme_constant_override("v_separation", 3)
	grid_holder.add_child(ball_grid)
	ball_grid.add_child(_make_smiley_btn(-1))

	_caption(grid_holder, "CLASSIC SMILEYS")
	var grid1: GridContainer = GridContainer.new()
	grid1.columns = 11
	grid1.add_theme_constant_override("h_separation", 3)
	grid1.add_theme_constant_override("v_separation", 3)
	grid_holder.add_child(grid1)
	for i in range(188):
		grid1.add_child(_make_smiley_btn(i))

	_caption(grid_holder, "GOLD SMILEYS")
	var grid2: GridContainer = GridContainer.new()
	grid2.columns = 11
	grid2.add_theme_constant_override("h_separation", 3)
	grid2.add_theme_constant_override("v_separation", 3)
	grid_holder.add_child(grid2)
	for i in range(188, 376):
		grid2.add_child(_make_smiley_btn(i))

	_hint(v, "Saved automatically — this is you, online and off.")

	return v

func _smiley_tex(id: int) -> Texture2D:
	if id < 0:
		return _ball_tex
	if _smiley_sheet == null:
		return null
	var at: AtlasTexture = AtlasTexture.new()
	at.atlas = _smiley_sheet
	# Face crop — icons fill their buttons just like the ball does
	at.region = GameState.smiley_face_region(id)
	return at

func _make_smiley_btn(id: int) -> Button:
	var b: Button = Button.new()
	b.custom_minimum_size = Vector2(38, 38)
	b.focus_mode = Control.FOCUS_NONE
	b.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	b.icon = _smiley_tex(id)
	b.expand_icon = true
	b.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
	b.add_theme_stylebox_override("normal", _style_smiley_normal)
	b.add_theme_stylebox_override("hover", _style_smiley_selected)
	b.add_theme_stylebox_override("pressed", _style_smiley_selected)
	b.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	b.pressed.connect(func() -> void:
		GameState.player_smiley_id = id
		GameState.save_profile()
		_refresh_picker_selection())
	_smiley_btns[id] = b
	return b

func _refresh_picker_selection() -> void:
	var sel: int = GameState.player_smiley_id
	for id in _smiley_btns:
		var b: Button = _smiley_btns[id]
		b.add_theme_stylebox_override("normal", _style_smiley_selected if id == sel else _style_smiley_normal)
	if _picker_preview:
		_picker_preview.texture = _smiley_tex(sel)
	if _picker_label:
		if sel < 0:
			_picker_label.text = "DREAMER BALL"
		elif sel >= 188:
			_picker_label.text = "GOLD #%d" % (sel - 188)
		else:
			_picker_label.text = "CLASSIC #%d" % sel

# ----- Tabs -----
func _make_tab(i: int, text: String) -> Button:
	var b: Button = Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(140, 38)
	b.focus_mode = Control.FOCUS_NONE
	b.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	b.add_theme_font_size_override("font_size", 15)
	b.pressed.connect(func() -> void: _select_tab(i))
	return b

func _select_tab(i: int) -> void:
	_current_tab = i
	for j in range(_pages.size()):
		_pages[j].visible = j == i
	_restyle_tabs()

func _restyle_tabs() -> void:
	for i in range(_tab_buttons.size()):
		var b: Button = _tab_buttons[i]
		var sel: bool = i == _current_tab
		var s: StyleBoxFlat = StyleBoxFlat.new()
		s.bg_color = Color(0.14, 0.2, 0.36, 1.0) if sel else Color(0.07, 0.09, 0.16, 0.85)
		s.border_color = ACCENT if sel else Color(0.22, 0.28, 0.45, 0.8)
		s.set_border_width_all(1)
		s.border_width_bottom = 3 if sel else 1
		s.set_corner_radius_all(7)
		s.content_margin_top = 6.0
		s.content_margin_bottom = 6.0
		b.add_theme_stylebox_override("normal", s)
		var h: StyleBoxFlat = s.duplicate()
		h.bg_color = s.bg_color.lightened(0.05)
		b.add_theme_stylebox_override("hover", h)
		b.add_theme_stylebox_override("pressed", h)
		b.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
		b.add_theme_color_override("font_color", Color.WHITE if sel else Color(0.55, 0.62, 0.78))
		b.add_theme_color_override("font_hover_color", Color.WHITE)
		b.add_theme_color_override("font_pressed_color", Color.WHITE)

# ==================== Lobby overlay ====================

func _build_lobby_overlay() -> void:
	_overlay = Control.new()
	_overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	_overlay.visible = false
	add_child(_overlay)

	var dim: ColorRect = ColorRect.new()
	dim.color = Color(0.01, 0.02, 0.05, 0.72)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	_overlay.add_child(dim)

	var panel: PanelContainer = PanelContainer.new()
	panel.add_theme_stylebox_override("panel", _panel_style())
	panel.anchor_left = 0.5
	panel.anchor_right = 0.5
	panel.anchor_top = 0.5
	panel.anchor_bottom = 0.5
	panel.offset_left = -300.0
	panel.offset_right = 300.0
	panel.offset_top = -230.0
	panel.offset_bottom = 230.0
	_overlay.add_child(panel)

	var pm: MarginContainer = MarginContainer.new()
	pm.add_theme_constant_override("margin_left", 20)
	pm.add_theme_constant_override("margin_right", 20)
	pm.add_theme_constant_override("margin_top", 16)
	pm.add_theme_constant_override("margin_bottom", 16)
	panel.add_child(pm)

	# --- Browser box ---
	_browser_box = VBoxContainer.new()
	_browser_box.add_theme_constant_override("separation", 8)
	pm.add_child(_browser_box)

	_overlay_title = Label.new()
	_overlay_title.text = "ONLINE LOBBIES"
	_overlay_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_overlay_title.add_theme_font_size_override("font_size", 20)
	_overlay_title.add_theme_color_override("font_color", ACCENT)
	_browser_box.add_child(_overlay_title)

	var mode_tabs: HBoxContainer = HBoxContainer.new()
	mode_tabs.alignment = BoxContainer.ALIGNMENT_CENTER
	mode_tabs.add_theme_constant_override("separation", 6)
	_browser_box.add_child(mode_tabs)
	for mode: String in ["battle", "boss", "zombies", "survivors"]:
		var mb: Button = EditorToolsDock.make_button(MODE_LABELS[mode], Color(0.2, 0.26, 0.42))
		mb.custom_minimum_size = Vector2(128, 32)
		mb.pressed.connect(_on_mode_tab.bind(mode))
		mode_tabs.add_child(mb)
		_mode_tab_btns[mode] = mb

	var lscroll: ScrollContainer = ScrollContainer.new()
	lscroll.custom_minimum_size = Vector2(0, 210)
	lscroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	lscroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_browser_box.add_child(lscroll)
	_lobby_list_box = VBoxContainer.new()
	_lobby_list_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_lobby_list_box.add_theme_constant_override("separation", 6)
	lscroll.add_child(_lobby_list_box)

	var create_btn: Button = EditorToolsDock.make_button("＋  CREATE LOBBY", Color(0.2, 0.62, 0.4))
	create_btn.custom_minimum_size = Vector2(0, 44)
	create_btn.add_theme_font_size_override("font_size", 16)
	create_btn.tooltip_text = "You become the host — only you can press START."
	create_btn.pressed.connect(_on_create_lobby)
	_browser_box.add_child(create_btn)

	var back_btn: Button = EditorToolsDock.make_button("BACK", Color(0.4, 0.4, 0.5))
	back_btn.custom_minimum_size = Vector2(0, 32)
	back_btn.pressed.connect(_close_overlay)
	_browser_box.add_child(back_btn)

	# --- Room box (inside a lobby) ---
	_room_box = VBoxContainer.new()
	_room_box.add_theme_constant_override("separation", 8)
	_room_box.visible = false
	pm.add_child(_room_box)

	_room_title = Label.new()
	_room_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_room_title.add_theme_font_size_override("font_size", 20)
	_room_title.add_theme_color_override("font_color", Color(1.0, 0.72, 0.25))
	_room_box.add_child(_room_title)

	var mscroll: ScrollContainer = ScrollContainer.new()
	mscroll.custom_minimum_size = Vector2(0, 200)
	mscroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	mscroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_room_box.add_child(mscroll)
	_member_list_box = VBoxContainer.new()
	_member_list_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_member_list_box.add_theme_constant_override("separation", 4)
	mscroll.add_child(_member_list_box)

	_guns_row = HBoxContainer.new()
	_guns_row.alignment = BoxContainer.ALIGNMENT_CENTER
	_room_box.add_child(_guns_row)
	_guns_lobby_btn = EditorToolsDock.make_button("GUNS: ON", Color(0.36, 0.42, 0.58))
	_guns_lobby_btn.custom_minimum_size = Vector2(220, 32)
	_guns_lobby_btn.pressed.connect(_on_lobby_guns)
	_guns_row.add_child(_guns_lobby_btn)

	_start_btn = EditorToolsDock.make_button("▶  START MATCH", Color(0.85, 0.45, 0.12))
	_start_btn.custom_minimum_size = Vector2(0, 48)
	_start_btn.add_theme_font_size_override("font_size", 19)
	_start_btn.pressed.connect(func() -> void: NetPlay.start_match())
	_room_box.add_child(_start_btn)

	_wait_label = Label.new()
	_wait_label.text = "Waiting for the host to start…"
	_wait_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_wait_label.add_theme_font_size_override("font_size", 13)
	_wait_label.add_theme_color_override("font_color", Color(0.65, 0.72, 0.9))
	_room_box.add_child(_wait_label)

	var leave_btn: Button = EditorToolsDock.make_button("LEAVE LOBBY", Color(0.55, 0.3, 0.3))
	leave_btn.custom_minimum_size = Vector2(0, 32)
	leave_btn.pressed.connect(_on_leave_lobby)
	_room_box.add_child(leave_btn)

func _open_lobbies() -> void:
	_apply_settings()
	_overlay.visible = true
	_browser_box.visible = true
	_room_box.visible = false
	_restyle_mode_tabs()
	_set_lobby_list_message("Connecting to EE COMBAT server…")
	if NetPlay.online:
		NetPlay.browse(_browse_mode)
	else:
		NetPlay._browse_mode = _browse_mode
		if NetPlay.connect_to_server() != OK:
			_set_lobby_list_message("Could not reach the server.")

func _close_overlay() -> void:
	_overlay.visible = false

func _on_mode_tab(mode: String) -> void:
	_browse_mode = mode
	_restyle_mode_tabs()
	if NetPlay.online:
		NetPlay.browse(mode)

func _restyle_mode_tabs() -> void:
	for mode in _mode_tab_btns:
		var b: Button = _mode_tab_btns[mode]
		b.modulate = Color(1, 1, 1, 1.0) if mode == _browse_mode else Color(0.75, 0.78, 0.9, 0.66)

func _set_lobby_list_message(text: String) -> void:
	for c in _lobby_list_box.get_children():
		c.queue_free()
	var l: Label = Label.new()
	l.text = text
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.add_theme_font_size_override("font_size", 12)
	l.add_theme_color_override("font_color", Color(0.55, 0.6, 0.75))
	_lobby_list_box.add_child(l)

func _on_lobbies(list: Array) -> void:
	if not _overlay.visible or not _browser_box.visible:
		return
	for c in _lobby_list_box.get_children():
		c.queue_free()
	var shown: int = 0
	for lob in list:
		if str(lob.get("mode", "")) != _browse_mode:
			continue
		shown += 1
		var row: HBoxContainer = HBoxContainer.new()
		row.add_theme_constant_override("separation", 8)
		var name_l: Label = Label.new()
		name_l.text = "%s's lobby" % str(lob.get("host_name", "Player"))
		name_l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		name_l.add_theme_font_size_override("font_size", 13)
		name_l.add_theme_color_override("font_color", Color(0.9, 0.94, 1.0))
		row.add_child(name_l)
		var cnt: Label = Label.new()
		cnt.text = "%d/%d" % [int(lob.get("count", 1)), int(lob.get("max", 8))]
		cnt.add_theme_font_size_override("font_size", 12)
		cnt.add_theme_color_override("font_color", Color(0.6, 0.85, 0.6))
		row.add_child(cnt)
		var jb: Button = EditorToolsDock.make_button("JOIN", Color(0.24, 0.55, 0.3))
		jb.custom_minimum_size = Vector2(70, 30)
		var lid: int = int(lob.get("id", 0))
		jb.pressed.connect(func() -> void: NetPlay.join_lobby(lid))
		row.add_child(jb)
		_lobby_list_box.add_child(row)
	if shown == 0:
		_set_lobby_list_message("No %s lobbies yet — create one!" % _browse_mode.to_upper())

func _on_room_updated(info: Dictionary) -> void:
	if not NetPlay.in_lobby():
		return
	_overlay.visible = true
	_browser_box.visible = false
	_room_box.visible = true
	var mode: String = str(info.get("mode", "battle"))
	_room_title.text = "%s LOBBY" % str(MODE_LABELS.get(mode, mode)).to_upper()
	for c in _member_list_box.get_children():
		c.queue_free()
	var host: int = int(info.get("host", -1))
	var members: Dictionary = info.get("members", {})
	var ids: Array = members.keys()
	ids.sort()
	for k in ids:
		var m: Dictionary = members[k]
		var row: HBoxContainer = HBoxContainer.new()
		row.add_theme_constant_override("separation", 8)
		var icon: TextureRect = TextureRect.new()
		icon.custom_minimum_size = Vector2(26, 26)
		icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		icon.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		icon.texture = _smiley_tex(int(m.get("smiley_id", -1)))
		row.add_child(icon)
		var nm: Label = Label.new()
		var tag: String = "  ★ HOST" if int(k) == host else ""
		var you: String = "  (you)" if int(k) == NetPlay.my_id() else ""
		nm.text = str(m.get("name", "Player")) + you + tag
		nm.add_theme_font_size_override("font_size", 14)
		nm.add_theme_color_override("font_color", Color(1.0, 0.85, 0.4) if int(k) == host else Color(0.88, 0.92, 1.0))
		row.add_child(nm)
		_member_list_box.add_child(row)
	var iam_host: bool = NetPlay.i_am_host()
	var guns_on: bool = bool(info.get("opts", {}).get("guns", true))
	_guns_lobby_btn.text = "GUNS: ON" if guns_on else "GUNS: OFF (fists!)"
	_guns_lobby_btn.disabled = not iam_host
	_guns_row.visible = mode == "battle" or mode == "boss"
	_start_btn.visible = iam_host
	_wait_label.visible = not iam_host
	_start_btn.text = "▶  START MATCH  (%d player%s)" % [members.size(), "" if members.size() == 1 else "s"]

func _on_lobby_guns() -> void:
	var opts: Dictionary = NetPlay.room_info.get("opts", {}).duplicate()
	opts["guns"] = not bool(opts.get("guns", true))
	NetPlay.set_lobby_opts(opts)

func _on_create_lobby() -> void:
	if not NetPlay.online:
		return
	NetPlay.create_lobby(_browse_mode, {"guns": GameState.battle_guns_enabled})

func _on_leave_lobby() -> void:
	NetPlay.leave_room()
	_browser_box.visible = true
	_room_box.visible = false
	if NetPlay.online:
		NetPlay.browse(_browse_mode)

# ==================== Mode launchers (OFFLINE) ====================

func _go_offline() -> void:
	_apply_settings()
	NetPlay.match_active = false
	NetPlay.match_countdown = 0.0
	GameState.net_freeze = false
	GameState.set_edit_mode(false)
	GameState.camera_offset = Vector2.ZERO  # No stale pan from the camera pad

func _on_battle() -> void:
	_go_offline()
	GameState.battle_mode = true
	GameState.boss_fight = false
	GameState.survivors_mode = false
	GameState.zombies_mode = false
	BattleMap.build()
	get_tree().change_scene_to_file("res://scenes/world/game.tscn")

func _on_boss() -> void:
	_go_offline()
	GameState.battle_mode = true
	GameState.boss_fight = true
	GameState.survivors_mode = false
	GameState.zombies_mode = false
	BossMap.build()
	get_tree().change_scene_to_file("res://scenes/world/game.tscn")

func _on_survivors() -> void:
	_go_offline()
	GameState.battle_mode = true
	GameState.boss_fight = false
	GameState.survivors_mode = true
	GameState.zombies_mode = false
	SurvivorsMap.build()
	get_tree().change_scene_to_file("res://scenes/world/game.tscn")

func _on_zombies() -> void:
	_go_offline()
	GameState.battle_mode = true
	GameState.boss_fight = false
	GameState.survivors_mode = false
	GameState.zombies_mode = true
	ZombiesMap.build()
	get_tree().change_scene_to_file("res://scenes/world/game.tscn")

# ==================== Online world flow ====================

func _on_join_world() -> void:
	_apply_settings()
	NetPlay.match_active = false
	GameState.net_freeze = false
	GameState.battle_mode = false
	GameState.boss_fight = false
	GameState.survivors_mode = false
	GameState.zombies_mode = false
	status_label.text = "Connecting to EE COMBAT…"
	join_world_btn.disabled = true
	NetPlay.join_world()

func _on_world_joined() -> void:
	status_label.text = "World received! Entering…"
	get_tree().change_scene_to_file("res://scenes/world/game.tscn")

func _on_np_connected() -> void:
	if _overlay.visible:
		_set_lobby_list_message("Loading lobbies…")

func _on_np_failed() -> void:
	status_label.text = "Could not reach the EE COMBAT server."
	if join_world_btn:
		join_world_btn.disabled = false
	if _overlay.visible:
		_set_lobby_list_message("Could not reach the server — try again.")

func _on_np_lost() -> void:
	status_label.text = "Lost connection to the server."
	if join_world_btn:
		join_world_btn.disabled = false
	if _overlay.visible:
		_browser_box.visible = true
		_room_box.visible = false
		_set_lobby_list_message("Connection lost — reopen to retry.")

# ==================== LAN / tunnel flow (desktop) ====================

func _on_host() -> void:
	_apply_settings()
	var port := int(port_input.text) if port_input.text.is_valid_int() else 7777
	status_label.text = "Starting server on port %d..." % port
	var err := NetworkManager.host_game(port)
	if err != OK:
		status_label.text = "Failed to host: %s" % error_string(err)
		return
	status_label.text = "Hosting! Starting tunnel..."
	var load_err := WorldManager.load_from_file("user://world_save.json")
	if load_err != OK:
		WorldManager.build_sample_room()
	get_tree().change_scene_to_file("res://scenes/world/game.tscn")

func _on_join() -> void:
	_apply_settings()
	var address := ip_input.text.strip_edges()
	if address.is_empty():
		address = "127.0.0.1"
	var port := int(port_input.text) if port_input.text.is_valid_int() else 7777
	if address.contains("trycloudflare.com") or address.begins_with("wss://"):
		status_label.text = "Connecting to tunnel..."
	else:
		status_label.text = "Connecting to %s:%d..." % [address, port]
	var err := NetworkManager.join_game(address, port)
	if err != OK:
		status_label.text = "Failed to connect: %s" % error_string(err)

func _on_connected() -> void:
	if NetPlay.online or NetPlay.connecting:
		return  # dedicated-server flow is handled by NetPlay
	status_label.text = "Connected! Waiting for world data..."
	host_btn.disabled = true
	join_btn.disabled = true
	WorldManager.world_loaded.connect(_on_world_received, CONNECT_ONE_SHOT)

func _on_world_received() -> void:
	status_label.text = "World loaded! Entering..."
	get_tree().change_scene_to_file("res://scenes/world/game.tscn")

func _on_tunnel_ready(url: String) -> void:
	status_label.text = "Tunnel: " + url

func _on_connect_failed() -> void:
	if NetPlay.connecting or NetPlay.online:
		return
	status_label.text = "Connection failed! Is the server running?"
	host_btn.disabled = false
	join_btn.disabled = false

func _on_server_dc() -> void:
	status_label.text = "Disconnected from server."
	host_btn.disabled = false
	join_btn.disabled = false

func _on_quit() -> void:
	get_tree().quit()

func _on_paste() -> void:
	var clipboard_text := DisplayServer.clipboard_get()
	if clipboard_text.is_empty() and OS.has_feature("web"):
		JavaScriptBridge.eval("""
			var text = prompt('Paste your tunnel URL here:');
			if (text) {
				window._godot_paste = text;
			}
		""")
		var result = JavaScriptBridge.eval("window._godot_paste || ''")
		if result is String and not result.is_empty():
			ip_input.text = result.strip_edges()
			JavaScriptBridge.eval("window._godot_paste = null")
			return
	if not clipboard_text.is_empty():
		ip_input.text = clipboard_text.strip_edges()

func _apply_settings() -> void:
	GameState.player_name = name_input.text.strip_edges()
	if GameState.player_name.is_empty():
		GameState.player_name = "Player"
	GameState.save_profile()
