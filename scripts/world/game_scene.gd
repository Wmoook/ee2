extends Node2D

var renderer: Node2D
var editor: Node2D
var _vignette: ColorRect
var _bg: ColorRect

func _ready() -> void:
	RenderingServer.set_default_clear_color(Color(0.0, 0.0, 0.0))

	# Load saved world or build sample
	if WorldManager.load_from_file("user://world_save.json") != OK:
		WorldManager.build_sample_room()

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

	# Spawn player FIRST (so FG overlay draws on top)
	var player: Node = preload("res://scenes/player/player.tscn").instantiate()
	player.is_local = true
	player.peer_id = 1
	player.player_name = "Player"
	player.position = WorldManager.get_spawn_pixel(0)
	add_child(player)

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
	if event is InputEventKey and event.pressed and not event.echo:
		if event.physical_keycode == KEY_E:
			GameState.set_edit_mode(not GameState.is_edit_mode)
			get_viewport().set_input_as_handled()
		# Escape handled by block_editor for deselect
	if event.is_action_pressed("save_world"):
		WorldManager.save_to_file("user://world_save.json")
