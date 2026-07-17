extends Node2D

var renderer: Node2D
var editor: Node2D
var _vignette: ColorRect
var _bg: ColorRect
var _players: Dictionary = {}  # peer_id -> PlayerController node
var _world_ready: bool = false
var _player_scene: PackedScene = preload("res://scenes/player/player.tscn")
var _count_layer: CanvasLayer = null
var _count_label: Label = null
var _go_hold: float = 0.0

func _ready() -> void:
	RenderingServer.set_default_clear_color(Color(0.0, 0.0, 0.0))

	# Connect network signals for player spawn/despawn
	NetworkManager.player_connected.connect(_on_player_connected)
	NetworkManager.player_disconnected.connect(_on_player_disconnected)
	NetworkManager.chat_received.connect(_on_chat_for_speech)
	NetPlay.server_lost.connect(_on_server_lost)

	# Load world: host loads from file, client already has it (loaded in main_menu).
	# Battle mode skips this — the arena was already built by BattleMap.build().
	if (NetworkManager.is_host or NetworkManager._peer == null) and not GameState.battle_mode:
		# Host or singleplayer — load world from file
		if not _world_ready:
			if WorldManager.load_from_file("user://world_save.json") != OK:
				WorldManager.build_sample_room()
	# Client world was already loaded via receive_world_snapshot before scene switch
	_world_ready = true

	_setup_scene()

func _setup_scene() -> void:
	# World background with shader
	_bg = ColorRect.new()
	_bg.z_index = -10
	_bg.color = Color(0.0, 0.0, 0.0)
	_bg.position = Vector2(-500, -500)
	_bg.size = Vector2(WorldManager.world_width * 16 + 1000, WorldManager.world_height * 16 + 1000)
	add_child(_bg)

	# World renderer (BG + FG base, z=-2)
	renderer = preload("res://scripts/world/world_renderer.gd").new()
	add_child(renderer)

	# Gravity zone renderer (behind player, above background)
	var gz_renderer: Node2D = preload("res://scripts/world/gravity_zone_renderer.gd").new()
	add_child(gz_renderer)

	# Block editor
	editor = preload("res://scripts/world/block_editor.gd").new()
	add_child(editor)

	# Spawn local player
	if _world_ready:
		_spawn_local_player()
		# Spawn existing remote players (if host and others already connected)
		for pid in NetworkManager.players:
			if pid != multiplayer.get_unique_id() and not _players.has(pid):
				_spawn_remote_player(pid)

	# FG overlay - draws foreground blocks ON TOP of player (z=2)
	var fg_overlay: Node2D = preload("res://scripts/world/fg_overlay.gd").new()
	fg_overlay.set_renderer(renderer)
	add_child(fg_overlay)

	# Vignette overlay (GPU shader on full screen)
	_vignette = ColorRect.new()
	_vignette.z_index = 100
	_vignette.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var vig_shader: ShaderMaterial = ShaderMaterial.new()
	vig_shader.shader = preload("res://assets/shaders/vignette.gdshader")
	_vignette.material = vig_shader
	add_child(_vignette)

	# HUD on top
	var hud: CanvasLayer = preload("res://scripts/ui/game_hud.gd").new()
	add_child(hud)

	# Online match: 3-2-1-GO countdown (everyone frozen until GO)
	if NetPlay.match_active and NetPlay.match_countdown > 0.0:
		_build_countdown()

	# Combat modes (weapons, AI opponents, lives HUD)
	if GameState.battle_mode:
		if GameState.zombies_mode:
			var zomb: ZombiesMode = ZombiesMode.new()
			zomb.name = "ZombiesMode"
			add_child(zomb)
		elif GameState.survivors_mode:
			var surv: SurvivorsMode = SurvivorsMode.new()
			surv.name = "SurvivorsMode"
			add_child(surv)
		elif GameState.boss_fight:
			var boss: BossMode = BossMode.new()
			boss.name = "BossMode"
			add_child(boss)
		else:
			var battle: BattleMode = BattleMode.new()
			battle.name = "BattleMode"
			add_child(battle)

	# Show tunnel URL with copy button when hosting
	if NetworkManager.is_host:
		var _tl_canvas: CanvasLayer = CanvasLayer.new()
		_tl_canvas.layer = 90
		add_child(_tl_canvas)
		var _hbox: HBoxContainer = HBoxContainer.new()
		_hbox.position = Vector2(10, 8)
		_hbox.add_theme_constant_override("separation", 8)
		_tl_canvas.add_child(_hbox)
		var _tunnel_label: Label = Label.new()
		_tunnel_label.name = "TunnelLabel"
		_tunnel_label.add_theme_font_size_override("font_size", 13)
		_tunnel_label.add_theme_color_override("font_color", Color(0.3, 0.9, 1.0))
		_hbox.add_child(_tunnel_label)
		var _copy_btn: Button = Button.new()
		_copy_btn.text = "Copy"
		_copy_btn.add_theme_font_size_override("font_size", 11)
		_copy_btn.visible = false
		_hbox.add_child(_copy_btn)
		_copy_btn.pressed.connect(func():
			DisplayServer.clipboard_set(NetworkManager.tunnel_url)
			_copy_btn.text = "Copied!"
			await get_tree().create_timer(1.5).timeout
			_copy_btn.text = "Copy"
		)
		if NetworkManager.tunnel_url.length() > 0 and not NetworkManager.tunnel_url.begins_with("Starting"):
			_tunnel_label.text = "Join URL: " + NetworkManager.tunnel_url
			_copy_btn.visible = true
		else:
			_tunnel_label.text = "Starting tunnel..."
			NetworkManager.tunnel_ready.connect(func(url: String):
				_tunnel_label.text = "Join URL: " + url
				_copy_btn.visible = true
			)

func _on_world_loaded() -> void:
	# Client received world snapshot — now spawn players
	_world_ready = true
	_spawn_local_player()
	for pid in NetworkManager.players:
		if pid != multiplayer.get_unique_id() and not _players.has(pid):
			_spawn_remote_player(pid)

func _spawn_local_player() -> void:
	var my_id: int = 1
	if NetworkManager._peer != null:
		my_id = multiplayer.get_unique_id()
	if _players.has(my_id):
		return
	var player: Node = _player_scene.instantiate()
	player.is_local = true
	player.peer_id = my_id
	player.player_name = GameState.player_name
	player.smiley_id = GameState.player_smiley_id
	player.position = WorldManager.get_spawn_pixel(0)
	add_child(player)
	_players[my_id] = player

func _spawn_remote_player(peer_id: int) -> void:
	if _players.has(peer_id) or not _world_ready:
		return
	var info: Dictionary = NetworkManager.get_player_info(peer_id)
	var player: Node = _player_scene.instantiate()
	player.is_local = false
	player.peer_id = peer_id
	player.player_name = info.get("name", "Player")
	player.smiley_id = info.get("smiley_id", 0)
	player.position = WorldManager.get_spawn_pixel(0)
	add_child(player)
	_players[peer_id] = player

func _on_player_connected(peer_id: int) -> void:
	if peer_id != multiplayer.get_unique_id():
		_spawn_remote_player(peer_id)

func _on_player_disconnected(peer_id: int) -> void:
	if _players.has(peer_id):
		_players[peer_id].queue_free()
		_players.erase(peer_id)

func _get_player(peer_id: int) -> Node:
	return _players.get(peer_id, null)

func _on_chat_for_speech(sender_name: String, _message: String) -> void:
	# Set speech on local player when they send a message
	var my_id: int = 1
	if NetworkManager._peer != null:
		my_id = multiplayer.get_unique_id()
	if _players.has(my_id) and sender_name == GameState.player_name:
		_players[my_id].set_speech(_message)

func _build_countdown() -> void:
	_count_layer = CanvasLayer.new()
	_count_layer.layer = 95
	add_child(_count_layer)
	_count_label = Label.new()
	_count_label.set_anchors_preset(Control.PRESET_FULL_RECT)
	_count_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_count_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_count_label.add_theme_font_size_override("font_size", 110)
	_count_label.add_theme_color_override("font_color", Color(1.0, 0.9, 0.35))
	_count_label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.9))
	_count_label.add_theme_constant_override("outline_size", 16)
	_count_label.text = str(int(ceil(NetPlay.match_countdown)))
	_count_layer.add_child(_count_label)

func _process(_delta: float) -> void:
	# Online countdown: 3-2-1-GO, then unfreeze
	if _count_layer != null:
		if NetPlay.match_countdown > 0.0:
			NetPlay.match_countdown -= _delta
			if NetPlay.match_countdown <= 0.0:
				GameState.net_freeze = false
				_count_label.text = "GO!"
				_count_label.add_theme_color_override("font_color", Color(0.45, 1.0, 0.5))
				_go_hold = 0.8
			else:
				_count_label.text = str(int(ceil(NetPlay.match_countdown)))
		elif _go_hold > 0.0:
			_go_hold -= _delta
			if _go_hold <= 0.0:
				_count_layer.queue_free()
				_count_layer = null
	# Keep vignette covering viewport
	if _vignette and _camera_exists():
		var cam: Camera2D = get_viewport().get_camera_2d()
		var vp: Vector2 = get_viewport_rect().size / cam.zoom
		_vignette.position = cam.global_position - vp / 2.0
		_vignette.size = vp

func _camera_exists() -> bool:
	var cam: Camera2D = get_viewport().get_camera_2d()
	return cam != null

func _input(event: InputEvent) -> void:
	# Don't handle keys when typing in chat or any text field
	var focused: Control = get_viewport().gui_get_focus_owner()
	if focused is LineEdit or focused is TextEdit:
		return
	if event is InputEventKey and event.pressed and not event.echo:
		if event.physical_keycode == KEY_E and not GameState.battle_mode:
			GameState.set_edit_mode(not GameState.is_edit_mode)
			get_viewport().set_input_as_handled()
		if event.physical_keycode == KEY_ESCAPE:
			_leave_to_menu()
	if event.is_action_pressed("save_world") and not GameState.battle_mode and not NetPlay.online:
		WorldManager.save_to_file("user://world_save.json")

func _leave_to_menu() -> void:
	# Save world — but NEVER in battle mode (the arena must not overwrite the
	# player's saved world) and never as a guest of the shared online world
	# (the dedicated server owns that save).
	if not GameState.battle_mode and not NetPlay.online:
		WorldManager.save_to_file("user://world_save.json")
	NetPlay.leave_room()
	GameState.battle_mode = false
	GameState.boss_fight = false
	GameState.survivors_mode = false
	GameState.zombies_mode = false
	GameState.player_stunned = false
	GameState.net_freeze = false
	GameState.cam_shake = 0.0
	get_tree().paused = false
	NetworkManager.disconnect_game()
	get_tree().change_scene_to_file("res://scenes/ui/main_menu.tscn")

func _on_server_lost() -> void:
	# Connection to the dedicated server dropped mid-game — back to the menu
	_leave_to_menu()
