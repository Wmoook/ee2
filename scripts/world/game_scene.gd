extends Node2D

var renderer: Node2D
var editor: Node2D
var _vignette: ColorRect
var _bg: ColorRect
var _players: Dictionary = {}  # peer_id -> PlayerController node
var _world_ready: bool = false
var _player_scene: PackedScene = preload("res://scenes/player/player.tscn")

func _ready() -> void:
	RenderingServer.set_default_clear_color(Color(0.0, 0.0, 0.0))

	# Connect network signals for player spawn/despawn
	NetworkManager.player_connected.connect(_on_player_connected)
	NetworkManager.player_disconnected.connect(_on_player_disconnected)
	NetworkManager.chat_received.connect(_on_chat_for_speech)

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

	# 1v1 Bot battle mode (weapons, AI opponent, lives HUD)
	if GameState.battle_mode:
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

func _process(_delta: float) -> void:
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
			# Save world — but NEVER in battle mode (the arena must not
			# overwrite the player's saved world)
			if not GameState.battle_mode:
				WorldManager.save_to_file("user://world_save.json")
			GameState.battle_mode = false
			GameState.cam_shake = 0.0
			NetworkManager.disconnect_game()
			get_tree().change_scene_to_file("res://scenes/ui/main_menu.tscn")
	if event.is_action_pressed("save_world") and not GameState.battle_mode:
		WorldManager.save_to_file("user://world_save.json")
