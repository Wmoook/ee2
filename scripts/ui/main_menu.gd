extends Control
## DREAMERS DESIGN — main menu.
## Professional tabbed start screen: PLAY (host / join the sandbox world),
## BATTLE (arena vs bots, boss fight, dot survivors), PROFILE (name + smiley).
## The scene only supplies the aurora shader background — all UI is built here.

var name_input: LineEdit
var smiley_input: SpinBox
var host_btn: Button
var join_btn: Button
var ip_input: LineEdit
var port_input: LineEdit
var paste_btn: Button
var status_label: Label

var _tab_buttons: Array[Button] = []
var _pages: Array[Control] = []
var _current_tab: int = 0

const ACCENT: Color = Color(0.36, 0.78, 1.0)     # dream cyan
const ACCENT2: Color = Color(0.72, 0.5, 1.0)     # violet
const TAB_NAMES: Array[String] = ["PLAY", "BATTLE", "PROFILE"]

func _ready() -> void:
	_build_ui()

	NetworkManager.connection_succeeded.connect(_on_connected)
	NetworkManager.connection_failed.connect(_on_connect_failed)
	NetworkManager.server_disconnected.connect(_on_server_dc)
	NetworkManager.tunnel_ready.connect(_on_tunnel_ready)

	name_input.text = GameState.player_name
	smiley_input.value = GameState.player_smiley_id
	_select_tab(0)

# ==================== UI construction ====================

func _build_ui() -> void:
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
	title.text = "DREAMERS"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 58)
	title.add_theme_color_override("font_color", Color(0.9, 0.97, 1.0))
	title.add_theme_color_override("font_outline_color", Color(0.14, 0.45, 0.8, 0.85))
	title.add_theme_constant_override("outline_size", 10)
	header.add_child(title)

	var title2: Label = Label.new()
	title2.text = "D  E  S  I  G  N"
	title2.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title2.add_theme_font_size_override("font_size", 22)
	title2.add_theme_color_override("font_color", ACCENT2)
	title2.add_theme_color_override("font_outline_color", Color(0.18, 0.08, 0.32, 0.9))
	title2.add_theme_constant_override("outline_size", 5)
	header.add_child(title2)

	var subtitle: Label = Label.new()
	subtitle.text = "Build worlds. Share dreams."
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
	column.offset_top = 180.0
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
	version.text = "DREAMERS DESIGN  ·  v0.1 alpha"
	version.add_theme_font_size_override("font_size", 10)
	version.add_theme_color_override("font_color", Color(0.35, 0.38, 0.5))
	version.anchor_top = 1.0
	version.anchor_bottom = 1.0
	version.offset_left = 18.0
	version.offset_top = -32.0
	add_child(version)

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

	_caption(v, "SANDBOX WORLD")
	_hint(v, "Your persistent build world. Hosting opens an online tunnel automatically — friends can join with the URL.")

	host_btn = EditorToolsDock.make_button("▶   START WORLD", Color(0.22, 0.62, 0.88))
	host_btn.custom_minimum_size = Vector2(0, 50)
	host_btn.add_theme_font_size_override("font_size", 20)
	host_btn.tooltip_text = "Hosts on the port below and loads your saved world."
	host_btn.pressed.connect(_on_host)
	v.add_child(host_btn)

	var sep: HSeparator = HSeparator.new()
	v.add_child(sep)

	_caption(v, "JOIN A FRIEND")
	var row: HBoxContainer = HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	ip_input = LineEdit.new()
	ip_input.placeholder_text = "Tunnel URL or IP"
	ip_input.custom_minimum_size = Vector2(0, 34)
	ip_input.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(ip_input)
	paste_btn = EditorToolsDock.make_button("PASTE", Color(0.4, 0.45, 0.6))
	paste_btn.custom_minimum_size = Vector2(64, 34)
	paste_btn.pressed.connect(_on_paste)
	row.add_child(paste_btn)
	port_input = LineEdit.new()
	port_input.text = "7777"
	port_input.placeholder_text = "Port"
	port_input.custom_minimum_size = Vector2(74, 34)
	row.add_child(port_input)
	v.add_child(row)

	join_btn = EditorToolsDock.make_button("JOIN GAME", Color(0.55, 0.45, 0.95))
	join_btn.custom_minimum_size = Vector2(0, 42)
	join_btn.add_theme_font_size_override("font_size", 16)
	join_btn.pressed.connect(_on_join)
	v.add_child(join_btn)

	return v

# ----- BATTLE page -----
func _build_battle_page() -> VBoxContainer:
	var bv: VBoxContainer = VBoxContainer.new()
	bv.add_theme_constant_override("separation", 8)

	var bh: Label = Label.new()
	bh.text = "⚔  BATTLE ARENA"
	bh.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	bh.add_theme_font_size_override("font_size", 17)
	bh.add_theme_color_override("font_color", Color(1.0, 0.62, 0.2))
	bv.add_child(bh)
	var bsub: Label = Label.new()
	bsub.text = "Offline free-for-all vs hard AI — 10 lives each"
	bsub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	bsub.add_theme_font_size_override("font_size", 10)
	bsub.add_theme_color_override("font_color", Color(0.55, 0.58, 0.7))
	bv.add_child(bsub)

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
	fight_btn.custom_minimum_size = Vector2(0, 46)
	fight_btn.add_theme_font_size_override("font_size", 19)
	fight_btn.tooltip_text = "10 lives each. Bots hunt everyone — including each other."
	fight_btn.pressed.connect(_on_battle)
	bv.add_child(fight_btn)

	var sep: HSeparator = HSeparator.new()
	bv.add_child(sep)

	# ☠ BOSS FIGHT — you vs THE WARDEN
	var boss_btn: Button = EditorToolsDock.make_button("☠  BOSS FIGHT", Color(0.62, 0.18, 0.46))
	boss_btn.custom_minimum_size = Vector2(0, 40)
	boss_btn.add_theme_font_size_override("font_size", 15)
	boss_btn.tooltip_text = "THE WARDEN: 3 lives vs a giant. Parry its slam, jump its shockwaves, MASH LMB to win the beam clash. Guns toggle applies!"
	boss_btn.pressed.connect(_on_boss)
	bv.add_child(boss_btn)

	# 🩸 DOT SURVIVORS — Vampire Survivors, but it's EE
	var surv_btn: Button = EditorToolsDock.make_button("🩸  DOT SURVIVORS", Color(0.55, 0.12, 0.2))
	surv_btn.custom_minimum_size = Vector2(0, 40)
	surv_btn.add_theme_font_size_override("font_size", 15)
	surv_btn.tooltip_text = "15 minutes. A dot cave, free flight, the corrupted smiley horde. Auto-weapons, coins, chests, level-ups. Minute 14: THE WARDEN PRIME."
	surv_btn.pressed.connect(_on_survivors)
	bv.add_child(surv_btn)

	# 🧟 UNDEAD BUNKER — CoD Zombies, but it's EE
	var zomb_btn: Button = EditorToolsDock.make_button("🧟  UNDEAD BUNKER", Color(0.25, 0.45, 0.18))
	zomb_btn.custom_minimum_size = Vector2(0, 40)
	zomb_btn.add_theme_font_size_override("font_size", 15)
	zomb_btn.tooltip_text = "Round-based zombies. Barricade the windows, earn $ per kill and plank, buy wall guns, gamble the MYSTERY BOX, open the vault. F = buy/rebuild. How many rounds can you survive?"
	zomb_btn.pressed.connect(_on_zombies)
	bv.add_child(zomb_btn)

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
	v.add_theme_constant_override("separation", 9)

	_caption(v, "PLAYER NAME")
	name_input = LineEdit.new()
	name_input.placeholder_text = "Enter your name..."
	name_input.custom_minimum_size = Vector2(0, 36)
	name_input.text_changed.connect(func(t: String) -> void:
		GameState.player_name = t.strip_edges())
	v.add_child(name_input)

	_caption(v, "SMILEY ID (0-187)")
	smiley_input = SpinBox.new()
	smiley_input.max_value = 187
	smiley_input.custom_minimum_size = Vector2(0, 36)
	smiley_input.value_changed.connect(func(val: float) -> void:
		GameState.player_smiley_id = int(val))
	v.add_child(smiley_input)

	_hint(v, "Saved automatically — applied when you start any mode.")

	return v

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

# ==================== Mode launchers ====================

func _on_battle() -> void:
	_apply_settings()
	GameState.battle_mode = true
	GameState.boss_fight = false
	GameState.survivors_mode = false
	GameState.zombies_mode = false
	GameState.set_edit_mode(false)
	GameState.camera_offset = Vector2.ZERO  # No stale pan from the camera pad
	BattleMap.build()
	get_tree().change_scene_to_file("res://scenes/world/game.tscn")

func _on_boss() -> void:
	_apply_settings()
	GameState.battle_mode = true
	GameState.boss_fight = true
	GameState.survivors_mode = false
	GameState.zombies_mode = false
	GameState.set_edit_mode(false)
	GameState.camera_offset = Vector2.ZERO
	BossMap.build()
	get_tree().change_scene_to_file("res://scenes/world/game.tscn")

func _on_survivors() -> void:
	_apply_settings()
	GameState.battle_mode = true
	GameState.boss_fight = false
	GameState.survivors_mode = true
	GameState.zombies_mode = false
	GameState.set_edit_mode(false)
	GameState.camera_offset = Vector2.ZERO
	SurvivorsMap.build()
	get_tree().change_scene_to_file("res://scenes/world/game.tscn")


func _on_zombies() -> void:
	_apply_settings()
	GameState.battle_mode = true
	GameState.boss_fight = false
	GameState.survivors_mode = false
	GameState.zombies_mode = true
	GameState.set_edit_mode(false)
	GameState.camera_offset = Vector2.ZERO
	ZombiesMap.build()
	get_tree().change_scene_to_file("res://scenes/world/game.tscn")

# ==================== Network flow ====================

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
	# Detect if it's a tunnel URL or direct IP
	if address.contains("trycloudflare.com") or address.begins_with("wss://"):
		status_label.text = "Connecting to tunnel..."
	else:
		status_label.text = "Connecting to %s:%d..." % [address, port]
	var err := NetworkManager.join_game(address, port)
	if err != OK:
		status_label.text = "Failed to connect: %s" % error_string(err)

func _on_connected() -> void:
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
		# Web fallback: use JavaScript clipboard API
		JavaScriptBridge.eval("""
			navigator.clipboard.readText().then(function(text) {
				var el = document.querySelector('canvas');
				if (el) el.dispatchEvent(new CustomEvent('paste_text', {detail: text}));
			});
		""")
		# Also try the sync method
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
	GameState.player_smiley_id = int(smiley_input.value)
