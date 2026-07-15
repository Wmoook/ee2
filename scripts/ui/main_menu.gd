extends Control
## Main menu - Host/Join/Quit flow with Cloudflare Tunnel support

@onready var name_input: LineEdit = $VBox/NameInput
@onready var smiley_input: SpinBox = $VBox/SmileyInput
@onready var host_btn: Button = $VBox/HostBtn
@onready var join_btn: Button = $VBox/JoinBtn
@onready var quit_btn: Button = $VBox/QuitBtn
@onready var ip_input: LineEdit = $VBox/HBoxJoin/IPInput
@onready var port_input: LineEdit = $VBox/HBoxJoin/PortInput
@onready var paste_btn: Button = $VBox/HBoxJoin/PasteBtn
@onready var status_label: Label = $VBox/StatusLabel

func _ready() -> void:
	host_btn.pressed.connect(_on_host)
	join_btn.pressed.connect(_on_join)
	quit_btn.pressed.connect(_on_quit)
	paste_btn.pressed.connect(_on_paste)
	NetworkManager.connection_succeeded.connect(_on_connected)
	NetworkManager.connection_failed.connect(_on_connect_failed)
	NetworkManager.server_disconnected.connect(_on_server_dc)
	NetworkManager.tunnel_ready.connect(_on_tunnel_ready)

	name_input.text = GameState.player_name
	smiley_input.value = GameState.player_smiley_id

	# Menu facelift: shared arena-style skin on the scene buttons
	_skin_button(host_btn, Color(0.25, 0.65, 0.9))
	_skin_button(join_btn, Color(0.55, 0.45, 0.95))
	_skin_button(paste_btn, Color(0.4, 0.45, 0.6))
	_skin_button(quit_btn, Color(0.55, 0.3, 0.3))

	# ⚔ BATTLE ARENA — offline FFA vs 1-3 hard AI bots (1v1 up to 1v1v1v1)
	var battle_panel: PanelContainer = PanelContainer.new()
	battle_panel.add_theme_stylebox_override("panel", EditorToolsDock.make_panel_style())
	$VBox.add_child(battle_panel)
	$VBox.move_child(battle_panel, quit_btn.get_index())
	var bv: VBoxContainer = VBoxContainer.new()
	bv.add_theme_constant_override("separation", 7)
	battle_panel.add_child(bv)
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

func _on_battle() -> void:
	_apply_settings()
	GameState.battle_mode = true
	GameState.set_edit_mode(false)
	GameState.camera_offset = Vector2.ZERO  # No stale pan from the camera pad
	BattleMap.build()
	get_tree().change_scene_to_file("res://scenes/world/game.tscn")

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

func _skin_button(b: Button, tint: Color) -> void:
	## Apply the shared EditorToolsDock button look to a scene-built button.
	var s: StyleBoxFlat = StyleBoxFlat.new()
	s.bg_color = Color(tint.r * 0.4, tint.g * 0.4, tint.b * 0.4, 0.9)
	s.border_color = Color(tint.r, tint.g, tint.b, 0.7)
	s.set_border_width_all(1)
	s.set_corner_radius_all(4)
	s.content_margin_left = 8.0
	s.content_margin_right = 8.0
	b.add_theme_stylebox_override("normal", s)
	var sh: StyleBoxFlat = s.duplicate()
	sh.bg_color = Color(tint.r * 0.6, tint.g * 0.6, tint.b * 0.6, 0.95)
	b.add_theme_stylebox_override("hover", sh)
	var sp: StyleBoxFlat = s.duplicate()
	sp.bg_color = Color(tint.r * 0.85, tint.g * 0.85, tint.b * 0.85, 1.0)
	b.add_theme_stylebox_override("pressed", sp)
	b.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	b.add_theme_color_override("font_color", Color(0.92, 0.92, 0.96))
	b.add_theme_color_override("font_hover_color", Color.WHITE)
	b.add_theme_color_override("font_pressed_color", Color.WHITE)
	b.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	b.focus_mode = Control.FOCUS_NONE
