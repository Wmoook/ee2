extends CharacterBody2D
class_name PlayerController

@export var is_local: bool = true
@export var peer_id: int = 0
@export var smiley_id: int = 0
@export var player_name: String = "Player"
@export var player_color_index: int = 0

const SMILEY_SIZE: int = 26
const SMILEY_OFFSET: int = 5
const SMILEYS_PER_CHUNK: int = 157

var physics: EEPhysics = EEPhysics.new()
var _tick_accumulator: float = 0.0
var _is_dead: bool = false
var _death_timer: float = 0.0
var _smiley_sprite: Sprite2D
var _name_label: Label
var _camera: Camera2D
var _smiley_textures: Array = []
var _space_just: bool = false
var _space_held: bool = false
var _cbf_consumed_jump: bool = false  # Prevents re-latch after CBF

# Smooth visual position
var _visual_pos: Vector2 = Vector2.ZERO
var _phys_pos: Vector2 = Vector2.ZERO
var _prev_pos: Vector2 = Vector2.ZERO
var _smooth_look: Vector2 = Vector2.ZERO  # Smoothed look-ahead offset

func _ready() -> void:
	for i in range(2):
		var tex: Texture2D = load("res://assets/sprites/smileys_%d.png" % i) as Texture2D
		if tex:
			_smiley_textures.append(tex)

	_smiley_sprite = Sprite2D.new()
	_smiley_sprite.centered = true
	_smiley_sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_smiley_sprite.position = Vector2(8, 8)  # Center of 16x16 hitbox
	# Z between bg (-2) and fg overlay (2) so blocks cover smiley border
	_smiley_sprite.z_as_relative = false
	_smiley_sprite.z_index = 0
	add_child(_smiley_sprite)
	_set_smiley(smiley_id)

	_name_label = Label.new()
	_name_label.text = player_name
	_name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_name_label.add_theme_font_size_override("font_size", 9)
	_name_label.add_theme_color_override("font_color", Color.WHITE)
	_name_label.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.8))
	_name_label.add_theme_constant_override("shadow_offset_x", 1)
	_name_label.add_theme_constant_override("shadow_offset_y", 1)
	_name_label.position = Vector2(-16, 16 + 2)  # Below the smiley
	_name_label.size = Vector2(48, 14)
	_name_label.z_as_relative = false
	_name_label.z_index = 5
	add_child(_name_label)

	if is_local:
		_camera = Camera2D.new()
		_camera.zoom = Vector2(3.0, 3.0)
		_camera.position_smoothing_enabled = false
		_camera.limit_left = 0
		_camera.limit_top = 0
		_camera.limit_right = WorldManager.world_width * 16
		_camera.limit_bottom = WorldManager.world_height * 16
		_camera.limit_smoothed = true
		# Independent camera (NOT child) - exact EE behavior
		call_deferred("_setup_camera")

func _setup_camera() -> void:
	physics.set_collides_fn(_tile_collides)
	var sp: Vector2 = WorldManager.get_spawn_point()
	physics.set_position_tiles(sp.x, sp.y)
	_phys_pos = Vector2(physics.get_pixel_x(), physics.get_pixel_y())
	_visual_pos = _phys_pos
	position = _phys_pos

	get_parent().add_child(_camera)
	_camera.global_position = Vector2(physics.get_pixel_x() + 8, physics.get_pixel_y() + 8)

func _set_smiley(id: int) -> void:
	if _smiley_textures.is_empty():
		return
	var col: int = id % 188
	var chunk: int = col / SMILEYS_PER_CHUNK
	var local_col: int = col % SMILEYS_PER_CHUNK
	if chunk >= _smiley_textures.size():
		chunk = 0
		local_col = 0
	var atlas_tex: AtlasTexture = AtlasTexture.new()
	atlas_tex.atlas = _smiley_textures[chunk]
	atlas_tex.region = Rect2(local_col * SMILEY_SIZE, 0, SMILEY_SIZE, SMILEY_SIZE)
	_smiley_sprite.texture = atlas_tex

func _physics_process(delta: float) -> void:
	if _is_dead:
		_death_timer += delta
		if _death_timer > 0.5:
			_respawn()
		return
	if not is_local:
		return

	# Read input
	var ix: int = 0
	var iy: int = 0
	# All movement works in both play and edit mode
	if Input.is_action_pressed("move_left"): ix -= 1
	if Input.is_action_pressed("move_right"): ix += 1
	if physics.is_god_mode or physics.on_dot:
		if Input.is_key_pressed(KEY_W) or Input.is_key_pressed(KEY_UP): iy -= 1
		if Input.is_key_pressed(KEY_S) or Input.is_key_pressed(KEY_DOWN): iy += 1
	else:
		if Input.is_key_pressed(KEY_W) or Input.is_key_pressed(KEY_UP): iy -= 1
		if Input.is_key_pressed(KEY_S) or Input.is_key_pressed(KEY_DOWN): iy += 1
		# Space = jump (works in all modes)
		if not physics.is_god_mode and not physics.on_dot:
			_space_held = Input.is_key_pressed(KEY_SPACE)
			# Only latch if CBF hasn't already consumed the jump this frame
			if not _cbf_consumed_jump and Input.is_action_just_pressed("jump") and Input.is_key_pressed(KEY_SPACE):
				_space_just = true

	# Save pre-tick position for interpolation
	_prev_pos = Vector2(physics.get_pixel_x(), physics.get_pixel_y())

	# Run physics ticks (EE: detect action tile at START of each tick)
	_tick_accumulator += delta * 1000.0
	var used_just: bool = false
	while _tick_accumulator >= EEPhysics.MS_PER_TICK:
		_tick_accumulator -= EEPhysics.MS_PER_TICK
		# Detect action tile before physics (updates delayed queue)
		if not physics.is_god_mode:
			var ctx: int = int(floor((physics.x + 8) / 16.0))
			var cty: int = int(floor((physics.y + 8) / 16.0))
			var cid: int = WorldManager.get_tile(ctx, cty)
			var crot: int = WorldManager.get_rotation(ctx, cty)
			# Also check free blocks for action tiles (rotated arrows etc.)
			if not GameState.is_action(cid):
				var fb_action: Dictionary = _get_free_block_action()
				if not fb_action.is_empty():
					cid = fb_action.id
					crot = fb_action.rot
			physics.apply_action_tile(cid, crot)
			if GameState.is_key(cid):
				var kcolor: String = GameState.get_key_color(cid)
				if not kcolor.is_empty():
					WorldManager.activate_key(kcolor)
		physics.tick(ix, iy, _space_just and not used_just, _space_held)
		if _space_just:
			used_just = true
		# Camera is a child so it moves with player. To create lag,
		# counter the player's movement in the offset, then slowly recover.
		# Exact EE camera: independent, offset += (target - offset) * 1/16
		if _camera:
			var player_center: Vector2 = Vector2(physics.get_pixel_x() + 8, physics.get_pixel_y() + 8)
			var cam: Vector2 = _camera.global_position
			cam.x = cam.x + (player_center.x - cam.x) * 0.0625
			cam.y = cam.y + (player_center.y - cam.y) * 0.0625
			_camera.global_position = cam
	_space_just = false
	_cbf_consumed_jump = false  # Reset for next frame

	_phys_pos = Vector2(physics.get_pixel_x(), physics.get_pixel_y())
	# On a freeform line: use exact sub-pixel position for smooth diagonal
	# On tiles: floor to pixel for crisp rendering
	# Sub-pixel on lines/slopes for smooth diagonal, floor on flat tiles
	if physics.on_rotated_block:
		_visual_pos = _phys_pos  # Sub-pixel = smooth diagonal
	else:
		var on_line: float = WorldManager.check_line_collision(physics.x, physics.y + 1, 16.0, 16.0)
		if on_line >= 0:
			_visual_pos = _phys_pos
		else:
			_visual_pos = Vector2(floor(_phys_pos.x), floor(_phys_pos.y))
	position = _visual_pos

	# Smiley rotation: match slope surface whenever touching rotated blocks
	# God mode: always upright
	if _smiley_sprite:
		if physics.is_god_mode:
			_smiley_sprite.rotation = lerp_angle(_smiley_sprite.rotation, 0.0, 0.3)
		elif physics.on_rotated_block and physics.is_grounded and not physics.in_valley:
			var n: Vector2 = physics._surface_normal
			var target_angle: float = atan2(n.x, -n.y)
			_smiley_sprite.rotation = lerp_angle(_smiley_sprite.rotation, target_angle, 0.3)
		elif physics.in_valley:
			_smiley_sprite.rotation = lerp_angle(_smiley_sprite.rotation, 0.0, 0.3)
		elif physics.is_grounded:
			_smiley_sprite.rotation = lerp_angle(_smiley_sprite.rotation, 0.0, 0.2)

	# Camera updated inside tick loop above

	# Hazard check
	if not physics.is_god_mode:
		var tiles: Array[Vector2i] = physics.get_overlapping_tiles()
		for t in tiles:
			if GameState.is_hazard(WorldManager.get_tile(t.x, t.y)):
				_die()
				return
	# OOB
	if physics.y > WorldManager.world_height * 16 + 80:
		_die()

func _process(delta: float) -> void:
	if _is_dead:
		return
	# Fixed-timestep interpolation: blend between pre-tick and post-tick positions
	# based on how far through the current tick we are.
func _input(event: InputEvent) -> void:
	if not is_local:
		return
	if event is InputEventKey and event.pressed and not event.echo:
		if event.physical_keycode == KEY_G:
			physics.is_god_mode = not physics.is_god_mode
			_smiley_sprite.modulate = Color(0.6, 0.8, 1.0, 0.5) if physics.is_god_mode else Color.WHITE
			# God mode: above all layers; normal: between bg and fg
			_smiley_sprite.z_index = 10 if physics.is_god_mode else 0
			_name_label.z_index = 11 if physics.is_god_mode else 5
		elif event.physical_keycode == KEY_N:
			_name_label.visible = not _name_label.visible

	# CBF - disabled in arrow fields to prevent extra ticks on key press
	if not is_local or _is_dead or physics._active_arrow_dir >= 0:
		return
	if event is InputEventKey and not event.echo:
		_run_cbf_tick()

func _run_cbf_tick() -> void:
	# Read current input state at this exact moment
	var ix: int = 0
	var iy: int = 0
	if Input.is_action_pressed("move_left"): ix -= 1
	if Input.is_action_pressed("move_right"): ix += 1
	if Input.is_key_pressed(KEY_W) or Input.is_key_pressed(KEY_UP): iy -= 1
	if Input.is_key_pressed(KEY_S) or Input.is_key_pressed(KEY_DOWN): iy += 1

	var space_held: bool = Input.is_key_pressed(KEY_SPACE)
	var space_just: bool = _space_just  # Use the latched value, not re-querying

	# Detect action tile
	if not physics.is_god_mode:
		var ctx: int = int(floor((physics.x + 8) / 16.0))
		var cty: int = int(floor((physics.y + 8) / 16.0))
		var cid: int = WorldManager.get_tile(ctx, cty)
		var crot: int = WorldManager.get_rotation(ctx, cty)
		physics.apply_action_tile(cid, crot)
		if GameState.is_key(cid):
			var kcolor: String = GameState.get_key_color(cid)
			if not kcolor.is_empty():
				WorldManager.activate_key(kcolor)

	# Run one tick immediately
	_prev_pos = Vector2(physics.get_pixel_x(), physics.get_pixel_y())
	physics.tick(ix, iy, space_just, space_held)
	if space_just:
		_cbf_consumed_jump = true  # Block re-latch in _physics_process
	_space_just = false
	_phys_pos = Vector2(physics.get_pixel_x(), physics.get_pixel_y())
	_visual_pos = Vector2(floor(_phys_pos.x), floor(_phys_pos.y))
	position = _visual_pos

	# Update camera in sync with CBF tick
	if _camera:
		var pc: Vector2 = _phys_pos + Vector2(8, 8)
		var cam: Vector2 = _camera.global_position
		cam.x = cam.x + (pc.x - cam.x) * 0.0625
		cam.y = cam.y + (pc.y - cam.y) * 0.0625
		_camera.global_position = cam

	# Consume accumulator
	_tick_accumulator = maxf(0, _tick_accumulator - EEPhysics.MS_PER_TICK)
	_space_just = false

func _tile_collides(tile_x: int, tile_y: int) -> bool:
	return WorldManager.is_solid_at(tile_x, tile_y)

func _get_free_block_action() -> Dictionary:
	## Check if player AABB overlaps any non-solid free block (arrows, dots, etc.)
	## Uses player hitbox overlap, not just center, to avoid gaps between adjacent blocks
	var pcx: float = physics.x + 8.0
	var pcy: float = physics.y + 8.0
	var best_dist: float = 999999.0
	var best_fb: Dictionary = {}
	for fb in WorldManager.free_blocks:
		if GameState.is_solid(fb.id):
			continue
		var bpos: Vector2 = fb.pos
		var rot_deg: float = fb.rotation
		var bcx: float = bpos.x + 8.0
		var bcy: float = bpos.y + 8.0
		# Transform player center into block's local space
		var rot_rad: float = deg_to_rad(rot_deg)
		var dx: float = pcx - bcx
		var dy: float = pcy - bcy
		var lx: float = dx * cos(-rot_rad) - dy * sin(-rot_rad)
		var ly: float = dx * sin(-rot_rad) + dy * cos(-rot_rad)
		# Player center within 10px of block center (tighter than full AABB to avoid wrong arrows)
		if absf(lx) < 10.0 and absf(ly) < 10.0:
			var dist: float = lx * lx + ly * ly
			if dist < best_dist:
				best_dist = dist
				best_fb = {"id": fb.id, "rot": int(round(rot_deg))}
	return best_fb

func _die() -> void:
	if _is_dead: return
	_is_dead = true
	_death_timer = 0.0
	_smiley_sprite.visible = false
	_name_label.visible = false

func _respawn() -> void:
	_is_dead = false
	_smiley_sprite.visible = true
	_name_label.visible = true
	var sp: Vector2 = WorldManager.get_spawn_point()
	physics.set_position_tiles(sp.x, sp.y)
	_phys_pos = Vector2(physics.get_pixel_x(), physics.get_pixel_y())
	_visual_pos = _phys_pos
	position = _phys_pos
	if _camera:
		_camera.global_position = _phys_pos + Vector2(8, 8)
