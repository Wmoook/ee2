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
const ANIM_SPRITE_SIZE: int = 40
const ANIM_SCALE: float = 16.0 / 40.0  # 0.4 to fit 40px into one 16x16 block

var physics: EEPhysics = EEPhysics.new()
var _tick_accumulator: float = 0.0
var _is_dead: bool = false
var _death_timer: float = 0.0
var _smiley_sprite: Sprite2D
var _name_label: Label
var _camera: Camera2D
var _debug_label: Label
var _show_debug: bool = false
var _last_normal: Vector2 = Vector2(0, -1)
var _valley_smiley_ticks: int = 0
var _slow_ticks: int = 0  # Ticks player has been slow
var _smiley_textures: Array = []
var _space_just: bool = false
# Animated smiley: 3 frames (idle, transition, moving)
var _anim_textures: Array = []  # [idle, transition, moving]
var _anim_frame: int = 0  # 0=idle, 1=transition, 2=moving
var _anim_timer: float = 0.0
var _anim_facing: int = 0  # -1=left, 0=none, 1=right
var _use_anim_sprite: bool = false
const MAX_SPEED_THRESHOLD: float = 5.0
const GLOW_START_SPEED: float = 2.0
var _at_max_speed: bool = false
var _glow_intensity: float = 0.0
var _was_max_speed: bool = false  # For startup burst detection
var _boxed_in_timer: float = 0.0  # Time spent motionless in a box
var _last_box_pos: Vector2 = Vector2.ZERO
var _glow_sprite: Sprite2D = null
var _fire_particles: Array = []  # Fire trail particles
var _prev_fire_pos: Vector2 = Vector2.ZERO  # Previous ball center for interpolation
var _fire_layer: Node2D = null  # Separate draw layer for fire (above blocks)
var _prev_fall_speed: float = 0.0  # Track fall speed for landing impact
var _was_grounded: bool = false
var _space_held: bool = false
var _cbf_consumed_jump: bool = false  # Prevents re-latch after CBF
var _show_hitboxes: bool = false
var _idle_timer: float = 0.0  # Time at zero velocity
var _name_fade: float = 0.0   # 0=hidden, 1=fully visible

# Smooth visual position
var _visual_pos: Vector2 = Vector2.ZERO
var _phys_pos: Vector2 = Vector2.ZERO
var _prev_pos: Vector2 = Vector2.ZERO
var _smooth_look: Vector2 = Vector2.ZERO  # Smoothed look-ahead offset
var _smooth_normal: Vector2 = Vector2(0, -1)  # Smoothed surface normal for smiley

func _ready() -> void:
	for i in range(2):
		var tex: Texture2D = load("res://assets/sprites/smileys_%d.png" % i) as Texture2D
		if tex:
			_smiley_textures.append(tex)
	# Load animated sprite frames (BALL_1)
	for fname in ["BALL_1_frame1", "BALL_1_frame2", "BALL_1_frame3"]:
		var tex: Texture2D = load("res://assets/sprites/NEW_SPRITES_BALL/%s.png" % fname) as Texture2D
		if tex:
			_anim_textures.append(tex)
	_use_anim_sprite = _anim_textures.size() == 3

	_smiley_sprite = Sprite2D.new()
	_smiley_sprite.centered = true
	_smiley_sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_smiley_sprite.position = Vector2(8, 8)  # Center of 16x16 hitbox (original)
	# Z between bg (-2) and fg overlay (2) so blocks cover smiley border
	_smiley_sprite.z_as_relative = false
	_smiley_sprite.z_index = 4  # Above fire trail (z=3) and foreground blocks (z=2)
	if _use_anim_sprite:
		_smiley_sprite.texture = _anim_textures[0]
		# Scale 40x40 full-res down to 26x26 display (GPU nearest-neighbor = sharp)
		var _warp_px: float = 0.35 * 2.0 / 40.0
		_smiley_sprite.scale = Vector2(ANIM_SCALE + _warp_px, ANIM_SCALE + _warp_px)  # X+Y warp +0.35px for ball
	add_child(_smiley_sprite)
	if not _use_anim_sprite:
		_set_smiley(smiley_id)
	# Fire draw layer (above foreground blocks at z=2)
	if _use_anim_sprite:
		_fire_layer = Node2D.new()
		_fire_layer.z_as_relative = false
		_fire_layer.z_index = 3  # Above fg blocks (z=2)
		_fire_layer.set_script(preload("res://scripts/player/fire_drawer.gd"))
		add_child(_fire_layer)

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

	# Debug overlay (toggle with P key)
	var _dbg_canvas := CanvasLayer.new()
	_dbg_canvas.layer = 100
	add_child(_dbg_canvas)
	_debug_label = Label.new()
	_debug_label.position = Vector2(10, 10)
	_debug_label.size = Vector2(600, 100)
	_debug_label.add_theme_font_size_override("font_size", 11)
	_debug_label.add_theme_color_override("font_color", Color.YELLOW)
	_debug_label.visible = false
	_dbg_canvas.add_child(_debug_label)

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
	_camera.make_current()

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
		# Spaghettification effect for gravity zone death
		if _gz_death and _smiley_sprite:
			var t: float = clampf(_death_timer / 0.5, 0.0, 1.0)
			var to_center: Vector2 = _gz_death_center - (_visual_pos + Vector2(8, 8))
			var stretch_angle: float = to_center.angle()
			# Rotate to point toward hole
			_smiley_sprite.rotation = stretch_angle + PI * 0.5
			# Stretch along the direction INTO the hole, get thin perpendicular
			# Y = toward hole (stretch), X = perpendicular (thin)
			var base_s: float = ANIM_SCALE + 0.35 * 2.0 / 40.0
			var stretch_y: float = lerpf(1.0, 2.5, t * t)  # Elongate toward hole
			var thin_x: float = lerpf(1.0, 0.1, t * t)  # Get very thin
			var shrink: float = lerpf(1.0, 0.0, t * t * t)  # Shrink to nothing at end
			_smiley_sprite.scale = Vector2(base_s * thin_x * shrink, base_s * stretch_y * shrink)
			# Pull position INTO the hole (cubic acceleration)
			position = _visual_pos.lerp(_gz_death_center - Vector2(8, 8), t * t * t)
			# Turn red-hot, fade out
			_smiley_sprite.modulate = Color(1, lerpf(1, 0.1, t), lerpf(1, 0.0, t), lerpf(1.0, 0.0, t * t))
			if t >= 1.0:
				_smiley_sprite.visible = false
		if _death_timer > 0.7:
			_respawn()
		return
	if not is_local:
		return

	# Pre-tick: valley jump from smiley flip detection
	# Don't clear valley_jump - physics manages it via oscillation detection

	# Read raw input (WASD + Arrow keys both work)
	var raw_h: int = 0
	var raw_v: int = 0
	if Input.is_action_pressed("move_left") or Input.is_key_pressed(KEY_LEFT): raw_h -= 1
	if Input.is_action_pressed("move_right") or Input.is_key_pressed(KEY_RIGHT): raw_h += 1
	if Input.is_key_pressed(KEY_W) or Input.is_key_pressed(KEY_UP): raw_v -= 1
	if Input.is_key_pressed(KEY_S) or Input.is_key_pressed(KEY_DOWN): raw_v += 1
	var ix: int = raw_h
	var iy: int = raw_v
	# Space = jump (always check, works in all modes)
	_space_held = Input.is_key_pressed(KEY_SPACE)
	if not _cbf_consumed_jump and Input.is_action_just_pressed("jump") and Input.is_key_pressed(KEY_SPACE):
		_space_just = true

	# Save pre-tick position for interpolation
	_prev_pos = Vector2(physics.get_pixel_x(), physics.get_pixel_y())

	# Track fall speed BEFORE physics zeroes it on landing
	var _pre_tick_grounded: bool = physics.is_grounded
	var grav_pre: Vector2 = Vector2(physics.mox, physics.moy)
	if grav_pre.length() < 0.01:
		grav_pre = Vector2(0, 1)
	grav_pre = grav_pre.normalized()
	var _pre_tick_fall: float = Vector2(physics._speedX, physics._speedY).dot(grav_pre)

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
			var target: Vector2 = player_center + GameState.camera_offset
			var cam: Vector2 = _camera.global_position
			cam.x = cam.x + (target.x - cam.x) * 0.0625
			cam.y = cam.y + (target.y - cam.y) * 0.0625
			_camera.global_position = cam
	_space_just = false
	_cbf_consumed_jump = false  # Reset for next frame

	_phys_pos = Vector2(physics.get_pixel_x(), physics.get_pixel_y())
	# Visual position: pixel-snap on grid tiles, sub-pixel on curves/slopes
	# Grid tile check: prevents polyline collision from causing sub-pixel visual
	# when the player is actually standing on a solid grid tile
	var _snap_to_grid: bool = false
	if physics.is_grounded:
		var _gcx: int = int(floor((physics.x + 8) / 16.0))
		var _gcy: int = int(floor((physics.y + 16) / 16.0))
		if WorldManager.is_solid_at(_gcx, _gcy):
			_snap_to_grid = true
	if _snap_to_grid:
		_visual_pos = Vector2(floor(_phys_pos.x), floor(_phys_pos.y))
		# (Y nudge removed — warp handles alignment now)
	elif physics.on_rotated_block:
		_visual_pos = _phys_pos  # Sub-pixel = smooth diagonal on curves/slopes
	else:
		var on_line: float = WorldManager.check_line_collision(physics.x, physics.y + 1, 16.0, 16.0)
		if on_line >= 0:
			_visual_pos = _phys_pos
		else:
			_visual_pos = Vector2(floor(_phys_pos.x), floor(_phys_pos.y))
	position = _visual_pos

	# Animated smiley: update frame based on movement direction
	# States: 0=idle, 1=transition (starting), 2=moving, 3=transition (stopping)
	if _use_anim_sprite and _smiley_sprite:
		var spd_h: float = physics._speedX
		var moving_threshold: float = 0.3
		var new_facing: int = 0
		if spd_h > moving_threshold:
			new_facing = 1  # Right
		elif spd_h < -moving_threshold:
			new_facing = -1  # Left
		if new_facing != 0 and _anim_frame == 0:
			# Start moving from idle: play transition
			_anim_frame = 1
			_anim_timer = 0.0
			_anim_facing = new_facing
		elif new_facing != 0 and _anim_facing != 0 and new_facing != _anim_facing:
			# Direction flip: transition to new direction
			_anim_frame = 1
			_anim_timer = 0.0
			_anim_facing = new_facing
		elif new_facing != 0:
			# Still moving same direction
			_anim_timer += delta
			if _anim_frame == 1 and _anim_timer > 0.05:
				_anim_frame = 2  # moving frame
			elif _anim_frame == 3 and _anim_timer > 0.05:
				# Was stopping but started again
				_anim_frame = 2
		elif new_facing == 0 and (_anim_frame == 2 or _anim_frame == 1):
			# Released direction: play sprite2 as return transition
			_anim_frame = 3  # stopping transition
			_anim_timer = 0.0
		elif _anim_frame == 3:
			# In stopping transition
			_anim_timer += delta
			if _anim_timer > 0.05:
				_anim_frame = 0  # back to idle
				_anim_facing = 0
		# Map state to texture: 0=sprite1, 1=sprite2, 2=sprite3, 3=sprite2
		var tex_idx: int = 0
		if physics.is_wedged:
			tex_idx = 0  # Idle when wedged
			_anim_frame = 0
			_anim_facing = 0
		else:
			match _anim_frame:
				0: tex_idx = 0
				1: tex_idx = 1
				2: tex_idx = 2
				3: tex_idx = 1
		_smiley_sprite.texture = _anim_textures[tex_idx]
		# sprite3 faces right. Mirror for left. sprite2 also mirrors for left.
		if _anim_facing == -1:
			_smiley_sprite.flip_h = true
		else:
			_smiley_sprite.flip_h = false

	# Smiley rotation
	if _use_anim_sprite and _smiley_sprite:
		if physics.is_wedged:
			# Wedged between curves: perfectly upright, no rolling
			_smiley_sprite.rotation = lerp_angle(_smiley_sprite.rotation, 0.0, 0.5)
		elif physics.is_god_mode:
			# God mode: no rolling, stay upright (animation handles direction)
			_smiley_sprite.rotation = lerp_angle(_smiley_sprite.rotation, 0.0, 0.3)
		else:
			var spd_total: float = absf(physics._speedX) + absf(physics._speedY)
			if spd_total > 0.3:
				# Rolling ball: accumulate rotation from horizontal speed
				_smiley_sprite.rotation += physics._speedX / 8.0
			else:
				# No momentum: lerp back to upright so directional sprites look correct
				_smiley_sprite.rotation = lerp_angle(_smiley_sprite.rotation, 0.0, 0.3)
	# Fire trail (WORLD-SPACE so particles detach) + fire glow ring
	if _use_anim_sprite:
		if physics.is_god_mode:
			_glow_intensity = 0.0
			if not _fire_particles.is_empty():
				_fire_particles.clear()
				if _fire_layer:
					_fire_layer.queue_redraw()
		else:
			# Detect boxed-in: motionless for 0.2s = suppress trail
			var cur_pos: Vector2 = Vector2(physics.x, physics.y)
			if cur_pos.distance_to(_last_box_pos) < 2.0:
				_boxed_in_timer += delta
			else:
				_boxed_in_timer = 0.0
				_last_box_pos = cur_pos
			var _is_boxed: bool = _boxed_in_timer > 0.2
			var spd: float = Vector2(physics._speedX, physics._speedY).length()
			var target: float = clampf((spd - GLOW_START_SPEED) / (MAX_SPEED_THRESHOLD - GLOW_START_SPEED), 0.0, 1.0)
			if _is_boxed:
				target = 0.0  # Suppress trail when boxed in
			_glow_intensity = lerpf(_glow_intensity, target, 0.15)
			if _glow_intensity > 0.1:
				var vel: Vector2 = Vector2(physics._speedX, physics._speedY)
				var spd_len: float = vel.length()
				if spd_len > 0.5:
					var vel_dir: Vector2 = vel / spd_len
					var ball_center: Vector2 = Vector2(physics.x + 8, physics.y + 8)
					# Reset prev position if too far (first frame or teleport)
					if _prev_fire_pos.distance_to(ball_center) > 16:
						_prev_fire_pos = ball_center
					# Interpolate spawn positions between prev and current to fill gaps
					var move_dist: float = ball_center.distance_to(_prev_fire_pos)
					var steps: int = maxi(1, int(move_dist / 1.5))  # One burst per ~1.5px
					var per_step: int = maxi(4, int((15 + _glow_intensity * 15) / steps))
					for step in range(steps):
						var lerp_t: float = float(step) / float(steps)
						var spawn_center: Vector2 = _prev_fire_pos.lerp(ball_center, lerp_t)
						for _si in range(per_step):
							var angle: float = randf_range(-0.9, 0.9)
							var spawn_dir: Vector2 = (-vel_dir).rotated(angle)
							var radius: float = 5.0 + randf_range(0, 3)
							var wpos: Vector2 = spawn_center + spawn_dir * radius
							var scatter: float = randf_range(2, 8)
							var psize: float = randf_range(0.8, 2.8)
							_fire_particles.append({
								"wpos": wpos,
								"vel": vel * randf_range(0.85, 1.0) + spawn_dir * scatter,
								"life": randf_range(0.06, 0.18),
								"max_life": 0.18,
								"size": psize,
							})
					_prev_fire_pos = ball_center
					# Meteor heat shield: only when falling WITH gravity (not walking)
					# Compute speed along gravity direction
					var grav_dir: Vector2 = Vector2(physics.mox, physics.moy)
					if grav_dir.length() < 0.01:
						grav_dir = Vector2(0, 1)
					grav_dir = grav_dir.normalized()
					var fall_speed: float = vel.dot(grav_dir)  # Positive = falling
					var meteor_intensity: float = clampf((fall_speed - 3.0) / 10.0, 0.0, 1.0)
					if meteor_intensity > 0.1:
						var meteor_amt: float = meteor_intensity
						var meteor_count: int = int(5 + meteor_amt * 60)
						for _ri in range(meteor_count):
							# Crescent grows wider + more intense with speed
							var arc_width: float = lerpf(0.4, 1.8, meteor_amt)
							var angle: float = randf_range(-arc_width, arc_width)
							var front_dir: Vector2 = vel_dir.rotated(angle)
							var nose_bias: float = cos(angle)
							# Shield well ahead of ball — extra clearance
							var radius: float = lerpf(10.0, 15.0, meteor_amt) + randf_range(0, 3) * (1.0 - nose_bias)
							var mpos: Vector2 = ball_center + front_dir * radius
							# Push outward from ball, match velocity exactly
							_fire_particles.append({
								"wpos": mpos,
								"vel": vel + front_dir * randf_range(5, 15),
								"life": randf_range(0.01, 0.025),
								"max_life": 0.025,
								"hot": nose_bias > 0.5,
							})
					# Startup burst when first hitting max speed
					if _at_max_speed and not _was_max_speed:
						for _bi in range(30):
							var burst_angle: float = randf_range(0, TAU)
							var burst_dir: Vector2 = Vector2(cos(burst_angle), sin(burst_angle))
							_fire_particles.append({
								"wpos": ball_center + burst_dir * randf_range(4, 8),
								"vel": vel * 0.5 + burst_dir * randf_range(20, 50),
								"life": randf_range(0.08, 0.2),
								"max_life": 0.2,
								"hot": true,
							})
					_was_max_speed = _at_max_speed
					if _fire_particles.size() > 500:
						_fire_particles.resize(500)
		_at_max_speed = _glow_intensity > 0.7
		# Landing impact: was NOT grounded + falling fast → now grounded
		# Only trigger landing if actually fell a meaningful distance (not 1x1 gap bouncing)
		var _actual_fall_dist: float = absf(_phys_pos.y - _prev_pos.y)
		if physics.is_grounded and not _pre_tick_grounded and _pre_tick_fall > 3.0 and _actual_fall_dist > 8.0 and not physics.is_god_mode:
			# Impact scales with fall speed: tiny jump = tiny burst, terminal velocity = explosion
			# Normal jump lands at ~3-4 speed, terminal velocity is ~13-16
			var impact: float = clampf(_pre_tick_fall / 14.0, 0.0, 1.0)
			var impact_sq: float = impact * impact  # Exponential scaling — small jumps barely visible
			var bc: Vector2 = Vector2(physics.x + 8, physics.y + 8)
			var grav_d: Vector2 = grav_pre
			var perp_d: Vector2 = Vector2(-grav_d.y, grav_d.x)
			var count: int = int(3 + impact_sq * 80)
			var spray_force: float = 20 + impact_sq * 120
			var spray_life: float = lerpf(0.06, 0.35, impact_sq)
			for _li in range(count):
				var side: float = randf_range(-1.0, 1.0)
				var spray_dir: Vector2 = perp_d * side - grav_d * randf_range(0.1, 0.4)
				var offset: Vector2 = perp_d * side * (3 + impact * 5) + grav_d * 7
				_fire_particles.append({
					"wpos": bc + offset,
					"vel": spray_dir * randf_range(spray_force * 0.5, spray_force),
					"life": randf_range(spray_life * 0.5, spray_life),
					"max_life": spray_life,
					"hot": randf() < impact_sq * 0.6,
				})
		# Clear stray particles when stopped
		if _glow_intensity < 0.05 and not _fire_particles.is_empty():
			_fire_particles.clear()
			_prev_fire_pos = Vector2.ZERO
			if _fire_layer:
				_fire_layer.queue_redraw()
		queue_redraw()
	elif _smiley_sprite:
		# Legacy smiley rotation for non-animated sprites
		if physics.is_god_mode:
			_smiley_sprite.rotation = lerp_angle(_smiley_sprite.rotation, 0.0, 0.3)
		elif physics.in_valley:
			_smiley_sprite.rotation = 0.0
			_valley_smiley_ticks = 10
		elif not physics.on_rotated_block or not physics.is_grounded:
			# In air or on grid: clear flip state and lerp back to upright
			_last_normal = Vector2(0, -1)
			_valley_smiley_ticks = 0
			_smiley_sprite.rotation = lerp_angle(_smiley_sprite.rotation, 0.0, 0.3)
		elif physics.on_rotated_block and physics.is_grounded:
			var n: Vector2 = physics._surface_normal
			# Smooth the normal to prevent flicker
			_smooth_normal = _smooth_normal.lerp(n, 0.15)
			if _smooth_normal.length() > 0.01:
				_smooth_normal = _smooth_normal.normalized()
			# Flip detection: normal X flips = V-shape, smiley stays upright
			if _last_normal.x * n.x < -0.1 and absf(n.x) > 0.3:
				_valley_smiley_ticks = 10
			_last_normal = n
			# At rest: force upright (normal averaging at V bottom = ~straight up)
			var spd_total: float = absf(physics._speedX) + absf(physics._speedY)
			if _valley_smiley_ticks > 0:
				_valley_smiley_ticks -= 1
				_smiley_sprite.rotation = lerp_angle(_smiley_sprite.rotation, 0.0, 0.3)
			elif spd_total < 0.3:
				_smiley_sprite.rotation = lerp_angle(_smiley_sprite.rotation, 0.0, 0.1)
			else:
				# Use velocity direction for rotation when moving (feels natural on curves)
				var vel: Vector2 = Vector2(physics._speedX, physics._speedY)
				var target_angle: float
				if vel.length() > 0.5:
					# Perpendicular to velocity = smiley "up" direction
					var vel_n: Vector2 = vel.normalized()
					var vel_up: Vector2 = Vector2(-vel_n.y, vel_n.x)
					# Pick the "up" that's closer to the surface normal
					if vel_up.dot(_smooth_normal) < 0:
						vel_up = -vel_up
					target_angle = atan2(vel_up.x, -vel_up.y)
				else:
					target_angle = atan2(_smooth_normal.x, -_smooth_normal.y)
				_smiley_sprite.rotation = lerp_angle(_smiley_sprite.rotation, target_angle, 0.15)
		elif physics.is_grounded:
			_smiley_sprite.rotation = lerp_angle(_smiley_sprite.rotation, 0.0, 0.2)

	# Camera updated inside tick loop above

	# Name label: hide when moving, fade in after 3s idle
	var _total_speed: float = absf(physics._speedX) + absf(physics._speedY)
	if _total_speed > 0.3:
		_idle_timer = 0.0
		_name_fade = 0.0
	else:
		_idle_timer += delta
		if _idle_timer > 3.0:
			_name_fade = minf(_name_fade + delta * 2.0, 1.0)  # Fade in over 0.5s
	if _name_label:
		_name_label.modulate = Color(1, 1, 1, _name_fade)

	# Hazard check
	if not physics.is_god_mode:
		var tiles: Array[Vector2i] = physics.get_overlapping_tiles()
		for t in tiles:
			if GameState.is_hazard(WorldManager.get_tile(t.x, t.y)):
				_die()
				return
		# Gravity zone center = death (spaghettification)
		var player_center: Vector2 = Vector2(physics.x + 8, physics.y + 8)
		for gz in WorldManager.gravity_zones.zones:
			var kill_r: float = gz.get("center_radius", 8.0) + 2.0
			if player_center.distance_to(gz.center) < kill_r:
				_die_gravity_zone(gz.center)
				return
	# OOB
	if physics.y > WorldManager.world_height * 16 + 80:
		_die()

func _process(delta: float) -> void:
	if _show_debug and _debug_label and physics:
		_debug_label.text = physics.debug_text
	if _is_dead:
		return
	var fi: int = _fire_particles.size() - 1
	while fi >= 0:
		_fire_particles[fi].life -= delta
		if _fire_particles[fi].life <= 0:
			_fire_particles.remove_at(fi)
		else:
			var new_pos: Vector2 = _fire_particles[fi].wpos + _fire_particles[fi].vel * delta
			# Collide with solid blocks: bounce/splash on walls
			var tx: int = int(floor(new_pos.x / 16.0))
			var ty: int = int(floor(new_pos.y / 16.0))
			if WorldManager.is_solid_at(tx, ty):
				# Hit a wall — kill velocity, die faster
				_fire_particles[fi].vel *= -0.2  # Slight bounce
				_fire_particles[fi].life *= 0.5  # Die faster on impact
			else:
				_fire_particles[fi].wpos = new_pos
			_fire_particles[fi].vel *= 0.96
			_fire_particles[fi].vel.x += randf_range(-1, 1) * delta * 20
			_fire_particles[fi].vel.y += randf_range(-1, 1) * delta * 20
		fi -= 1
	if _show_hitboxes or _fire_particles.size() > 0:
		queue_redraw()

func _draw() -> void:
	# Fire particles drawn by fire_drawer.gd (z=3, above blocks)
	if not _show_hitboxes:
		return
	# Player hitbox (16x16 square - this IS the EE collision shape)
	# Draw OVER the smiley with z_index handled by draw order
	draw_rect(Rect2(0, 0, 16, 16), Color(0, 1, 0, 0.4), true)
	draw_rect(Rect2(0, 0, 16, 16), Color(0, 1, 0, 1.0), false, 2.0)
	# Draw grid tile hitboxes nearby
	var ptx: int = int(floor(physics.x / 16.0))
	var pty: int = int(floor(physics.y / 16.0))
	for ty in range(pty - 8, pty + 9):
		for tx in range(ptx - 12, ptx + 13):
			if tx >= 0 and ty >= 0 and tx < WorldManager.world_width and ty < WorldManager.world_height:
				if WorldManager.is_solid_at(tx, ty):
					var tile_pos: Vector2 = Vector2(tx * 16.0, ty * 16.0) - position
					draw_rect(Rect2(tile_pos, Vector2(16, 16)), Color(1, 0, 0, 0.3), true)
					draw_rect(Rect2(tile_pos, Vector2(16, 16)), Color(1, 0, 0, 0.8), false)
	# Draw free block hitboxes relative to player
	for fb in WorldManager.free_blocks:
		if not GameState.is_solid(fb.id):
			continue
		var bpos: Vector2 = fb.pos - position
		var rot_rad: float = deg_to_rad(fb.rotation)
		var center: Vector2 = bpos + Vector2(8, 8)
		# Draw rotated rectangle (block collision shape)
		var corners: Array = []
		for c in [Vector2(-8, -8), Vector2(8, -8), Vector2(8, 8), Vector2(-8, 8)]:
			var rx: float = c.x * cos(rot_rad) - c.y * sin(rot_rad)
			var ry: float = c.x * sin(rot_rad) + c.y * cos(rot_rad)
			corners.append(center + Vector2(rx, ry))
		draw_colored_polygon(PackedVector2Array(corners), Color(1, 0, 0, 0.3))
		for i in range(4):
			draw_line(corners[i], corners[(i + 1) % 4], Color(1, 0, 0, 0.8), 1.0)

func _input(event: InputEvent) -> void:
	if not is_local:
		return
	# Ctrl+scroll = zoom
	if event is InputEventMouseButton and Input.is_key_pressed(KEY_CTRL) and _camera:
		if event.button_index == MOUSE_BUTTON_WHEEL_UP:
			_camera.zoom = clampf(_camera.zoom.x + 0.5, 0.5, 10.0) * Vector2.ONE
			get_viewport().set_input_as_handled()
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			_camera.zoom = clampf(_camera.zoom.x - 0.5, 0.5, 10.0) * Vector2.ONE
			get_viewport().set_input_as_handled()
	if event is InputEventKey and event.pressed and not event.echo:
		if event.physical_keycode == KEY_G:
			physics.is_god_mode = not physics.is_god_mode
			_smiley_sprite.modulate = Color(0.6, 0.8, 1.0, 0.5) if physics.is_god_mode else Color.WHITE
			# God mode: above all layers; normal: between bg and fg
			_smiley_sprite.z_index = 10 if physics.is_god_mode else 4
			_name_label.z_index = 11 if physics.is_god_mode else 5
		elif event.physical_keycode == KEY_N:
			_name_label.visible = not _name_label.visible
		elif event.physical_keycode == KEY_P:
			_show_debug = not _show_debug
			_debug_label.visible = _show_debug
		elif event.physical_keycode == KEY_B:
			_show_hitboxes = not _show_hitboxes
			if not physics.is_god_mode:
				_smiley_sprite.modulate = Color(1, 1, 1, 0.3) if _show_hitboxes else Color.WHITE
			queue_redraw()

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
		var pc: Vector2 = _phys_pos + Vector2(8, 8) + GameState.camera_offset
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

var _gz_death: bool = false  # Dying from gravity zone
var _gz_death_center: Vector2 = Vector2.ZERO

func _die_gravity_zone(gz_center: Vector2) -> void:
	if _is_dead: return
	_gz_death = true
	_gz_death_center = gz_center
	_die()

func _die() -> void:
	if _is_dead: return
	_is_dead = true
	_death_timer = 0.0
	_name_label.visible = false
	# Clear fire trail
	_fire_particles.clear()
	_glow_intensity = 0.0
	_prev_fire_pos = Vector2.ZERO
	if _fire_layer:
		_fire_layer.queue_redraw()
	if not _gz_death:
		_smiley_sprite.visible = false

func _respawn() -> void:
	_is_dead = false
	_gz_death = false
	_smiley_sprite.visible = true
	_smiley_sprite.modulate = Color.WHITE
	_smiley_sprite.scale = Vector2(ANIM_SCALE + 0.35 * 2.0 / 40.0, ANIM_SCALE + 0.35 * 2.0 / 40.0)
	_smiley_sprite.rotation = 0.0
	_name_label.visible = true
	var sp: Vector2 = WorldManager.get_spawn_point()
	physics.set_position_tiles(sp.x, sp.y)
	_phys_pos = Vector2(physics.get_pixel_x(), physics.get_pixel_y())
	_visual_pos = _phys_pos
	position = _phys_pos
	if _camera:
		_camera.global_position = _phys_pos + Vector2(8, 8)
