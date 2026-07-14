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
# Frame interpolation: interpolate rendered position between physics ticks
# so visual motion is smooth at uncapped FPS (not stuttery at 100Hz physics).
var _prev_tick_pos: Vector2 = Vector2.ZERO
var _curr_tick_pos: Vector2 = Vector2.ZERO
var _last_tick_time_ms: float = 0.0
var _smooth_look: Vector2 = Vector2.ZERO  # Smoothed look-ahead offset
# Multiplayer sync
signal died  # Emitted once per death (battle mode counts lives)

var _remote_sync: RemotePlayerSync = null
var _sync_accum: float = 0.0  # Time-based net broadcast (~33Hz at any FPS)
# EE camera catch-up: 1/16 per original 100Hz tick, compounded to 240Hz ticks
# so the camera lag FEEL is identical at the higher tick rate.
var _cam_lerp: float = 1.0 - pow(1.0 - 0.0625, EEPhysics.EE_TICK_FRAC)
# Visual smoothing and particle rates below were tuned when this code ran in
# _physics_process at a fixed 60Hz. It now runs once per rendered frame, so
# every per-call rate must be scaled by delta to keep the exact same look at
# any FPS. _rc() converts a per-60Hz-frame lerp factor to this frame's delta.
const VISUAL_TUNE_HZ: float = 60.0
# Gear roll: one full rotation per this many px of horizontal travel.
# 16.0 = one full spin per block moved (gear-on-the-grid feel).
# A physically rolling 16px ball would be PI*16 ~= 50.3 px/rev if preferred.
const ROLL_PX_PER_REV: float = 16.0
var _last_roll_x: float = 0.0  # Physics X last frame (gear roll displacement source)

func _rc(f: float, delta: float) -> float:
	return 1.0 - pow(1.0 - f, delta * VISUAL_TUNE_HZ)
var _smooth_normal: Vector2 = Vector2(0, -1)  # Smoothed surface normal for smiley
var _speech_label: Label = null
var _speech_text: String = ""
var _speech_timer: float = 0.0
var _pending_speech: String = ""  # Queued speech to broadcast

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
		# Scale 40x40 full-res down to exact 16x16 (no warp — prevents sprite overlapping blocks)
		_smiley_sprite.scale = Vector2(ANIM_SCALE, ANIM_SCALE)
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

	# Speech bubble (shows last chat message when idle)
	_speech_label = Label.new()
	_speech_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_speech_label.add_theme_font_size_override("font_size", 8)
	_speech_label.add_theme_color_override("font_color", Color.WHITE)
	_speech_label.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.9))
	_speech_label.add_theme_constant_override("shadow_offset_x", 1)
	_speech_label.add_theme_constant_override("shadow_offset_y", 1)
	_speech_label.position = Vector2(-40, -14)
	_speech_label.size = Vector2(96, 14)
	_speech_label.z_as_relative = false
	_speech_label.z_index = 6
	_speech_label.visible = false
	_speech_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	add_child(_speech_label)

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
	else:
		# Remote player — init sync module, set spawn position
		_remote_sync = RemotePlayerSync.new()
		_remote_sync.target_pos = position
		_remote_sync.prev_pos = position
		physics.set_collides_fn(_tile_collides)
		var sp: Vector2 = WorldManager.get_spawn_point()
		physics.set_position_tiles(sp.x, sp.y)
		_phys_pos = Vector2(physics.get_pixel_x(), physics.get_pixel_y())
		_visual_pos = _phys_pos
		position = _phys_pos

func _setup_camera() -> void:
	physics.set_collides_fn(_tile_collides)
	var sp: Vector2 = WorldManager.get_spawn_point()
	physics.set_position_tiles(sp.x, sp.y)
	_phys_pos = Vector2(physics.get_pixel_x(), physics.get_pixel_y())
	_visual_pos = _phys_pos
	position = _phys_pos
	# Initialize interpolation anchors so render doesn't lerp from (0,0) on first frame
	_prev_tick_pos = _phys_pos
	_curr_tick_pos = _phys_pos
	_last_tick_time_ms = Time.get_ticks_msec()

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

func _tick_update(delta: float) -> void:
	## Runs the 240Hz physics accumulator. Called from _process (render rate)
	## so on high-refresh monitors ticks are paced one-per-frame with fresh
	## input — combined with the CBF event ticks this is Geometry-Dash-style
	## click-between-frames responsiveness.
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
			var base_s: float = ANIM_SCALE
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
		_visual_pos = position  # Keep fire_drawer offset correct during death
		# Camera follows player into black hole
		if _camera and _gz_death:
			var target: Vector2 = position + Vector2(8, 8)
			var cam: Vector2 = _camera.global_position
			cam.x += (target.x - cam.x) * _rc(0.0625, delta)
			cam.y += (target.y - cam.y) * _rc(0.0625, delta)
			_camera.global_position = cam
		if _gz_death:
			# Force clear ALL stray particles at 1.5s — no exceptions
			if not _fire_particles.is_empty() and _death_timer > 1.5:
				_fire_particles.clear()
				if _fire_layer:
					_fire_layer.queue_redraw()
			# Respawn 0.5s after clear
			if _fire_particles.is_empty() and _death_timer > 2.0:
				_respawn()
		elif _death_timer > 0.7:
			_respawn()
		return
	if not is_local:
		# Remote player: interpolate position from network state
		if _remote_sync:
			# Handle remote death animation
			if _remote_sync.is_dead and not _is_dead:
				_is_dead = true
				_death_timer = 0.0
				_gz_death = _remote_sync.gz_death
				_gz_death_center = _remote_sync.gz_death_center
				if not _gz_death:
					_smiley_sprite.visible = false
				_name_label.visible = false
			elif not _remote_sync.is_dead and _is_dead:
				# Respawned
				_is_dead = false
				_gz_death = false
				_smiley_sprite.visible = true
				_smiley_sprite.modulate = Color.WHITE
				_smiley_sprite.scale = Vector2(ANIM_SCALE, ANIM_SCALE)
				_smiley_sprite.rotation = 0.0
				_name_label.visible = true
				_fire_particles.clear()
			if _is_dead:
				_death_timer += delta
				if _gz_death and _smiley_sprite:
					var t: float = clampf(_death_timer / 0.5, 0.0, 1.0)
					var to_center: Vector2 = _gz_death_center - (_visual_pos + Vector2(8, 8))
					var stretch_angle: float = to_center.angle()
					_smiley_sprite.rotation = stretch_angle + PI * 0.5
					var base_s: float = ANIM_SCALE
					var stretch_y: float = lerpf(1.0, 2.5, t * t)
					var thin_x: float = lerpf(1.0, 0.1, t * t)
					var shrink: float = lerpf(1.0, 0.0, t * t * t)
					_smiley_sprite.scale = Vector2(base_s * thin_x * shrink, base_s * stretch_y * shrink)
					position = _visual_pos.lerp(_gz_death_center - Vector2(8, 8), t * t * t)
					_smiley_sprite.modulate = Color(1, lerpf(1, 0.1, t), lerpf(1, 0.0, t), lerpf(1.0, 0.0, t * t))
					if t >= 1.0:
						_smiley_sprite.visible = false
				return

			_visual_pos = _remote_sync.get_interpolated_position(delta)
			position = Vector2(floor(_visual_pos.x), floor(_visual_pos.y))
			if _smiley_sprite:
				if _use_anim_sprite and _anim_textures.size() >= 3:
					var af: int = clampi(_remote_sync.anim_frame, 0, _anim_textures.size() - 1)
					_smiley_sprite.texture = _anim_textures[af]
				_smiley_sprite.flip_h = _remote_sync.flip_h
				_smiley_sprite.rotation = lerp_angle(_smiley_sprite.rotation, _remote_sync.rotation, _rc(0.4, delta))
				_smiley_sprite.modulate = Color(0.6, 0.8, 1.0, 0.5) if _remote_sync.is_god else Color.WHITE
			# Generate fire trail for remote player based on their speed
			if _use_anim_sprite and not _remote_sync.is_god:
				var r_spd: Vector2 = _remote_sync.speed
				var r_len: float = r_spd.length()
				if r_len > 2.0:
					var r_center: Vector2 = _visual_pos + Vector2(8, 8)
					var r_dir: Vector2 = -r_spd.normalized()
					if _prev_fire_pos.distance_to(r_center) > 64:
						_prev_fire_pos = r_center
					var r_move: float = r_center.distance_to(_prev_fire_pos)
					var r_steps: int = maxi(1, int(r_move / 2.0))
					var r_budget: float = maxf(8.0 * delta * VISUAL_TUNE_HZ, r_move)
					var r_per: int = maxi(1, int(ceil(r_budget / r_steps)))
					for r_step in range(r_steps):
						var r_lerp_t: float = float(r_step) / float(r_steps)
						var r_spawn: Vector2 = _prev_fire_pos.lerp(r_center, r_lerp_t)
						for _ri in range(r_per):
							var r_angle: float = randf_range(-0.9, 0.9)
							var r_sdir: Vector2 = r_dir.rotated(r_angle)
							_fire_particles.append({
								"wpos": r_spawn + r_sdir * randf_range(3, 7),
								"vel": r_spd * randf_range(0.3, 0.6) + r_sdir * randf_range(5, 15),
								"life": randf_range(0.06, 0.18),
								"max_life": 0.18,
								"size": 1,
							})
					_prev_fire_pos = r_center
					if _fire_particles.size() > 2000:
						_fire_particles.resize(2000)
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
		# Snapshot previous tick position for interpolation
		_prev_tick_pos = _curr_tick_pos
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
		# Record new tick position for interpolation
		_curr_tick_pos = Vector2(physics.get_pixel_x(), physics.get_pixel_y())
		_last_tick_time_ms = Time.get_ticks_msec() - _tick_accumulator
		# Camera is a child so it moves with player. To create lag,
		# counter the player's movement in the offset, then slowly recover.
		# Exact EE camera: independent, offset += (target - offset) * 1/16
		if _camera:
			var player_center: Vector2 = Vector2(physics.get_pixel_x() + 8, physics.get_pixel_y() + 8)
			var target: Vector2 = player_center + GameState.camera_offset
			if GameState.cam_shake > 0.01:
				target += Vector2(randf_range(-1.0, 1.0), randf_range(-1.0, 1.0)) * minf(GameState.cam_shake, 14.0)
			var cam: Vector2 = _camera.global_position
			cam.x = cam.x + (target.x - cam.x) * _cam_lerp
			cam.y = cam.y + (target.y - cam.y) * _cam_lerp
			_camera.global_position = cam
	_space_just = false
	_cbf_consumed_jump = false  # Reset for next frame

	# Broadcast position to other players (~33Hz, time-based so FPS doesn't matter)
	_sync_accum += delta
	if _sync_accum >= 0.03 and NetworkManager._peer != null:
		_sync_accum = 0.0
		var af: int = _anim_frame
		var fh: bool = _smiley_sprite.flip_h if _smiley_sprite else false
		var rot: float = fmod(_smiley_sprite.rotation, TAU) if _smiley_sprite else 0.0
		var _bdata: Dictionary = {
			"x": physics.get_pixel_x(), "y": physics.get_pixel_y(),
			"sx": physics._speedX, "sy": physics._speedY,
			"af": af, "fh": fh, "r": rot,
			"g": physics.is_god_mode, "gr": physics.is_grounded,
			"dead": _is_dead, "gzd": _gz_death
		}
		if _gz_death:
			_bdata["gzc_x"] = _gz_death_center.x
			_bdata["gzc_y"] = _gz_death_center.y
		if not _pending_speech.is_empty():
			_bdata["sp"] = _pending_speech
			_pending_speech = ""
		_broadcast_state.rpc(_bdata)
		# Send tiles via RELIABLE RPC
		if WorldManager._pending_net_tiles.size() > 0:
			_broadcast_tiles.rpc(WorldManager._pending_net_tiles.duplicate())
			WorldManager._pending_net_tiles.clear()
		# All world edits go through NetworkManager (autoload, stable RPC path)
		if WorldManager._pending_net_clear_world:
			NetworkManager.send_clear_world()
			WorldManager._pending_net_clear_world = false
			WorldManager._pending_net_tiles.clear()
			WorldManager._pending_net_freeblocks.clear()
			WorldManager._pending_net_polylines.clear()
			WorldManager._pending_net_deletions.clear()
			WorldManager._pending_net_fb_replace = {}
			WorldManager._pending_net_gz.clear()
		if not WorldManager._pending_net_fb_replace.is_empty():
			var rep: Dictionary = WorldManager._pending_net_fb_replace
			NetworkManager.send_fb_replace(rep.remove, rep.blocks)
			WorldManager._pending_net_fb_replace = {}
		if WorldManager._pending_net_freeblocks.size() > 0:
			NetworkManager.send_freeblocks(WorldManager._pending_net_freeblocks.duplicate())
			WorldManager._pending_net_freeblocks.clear()
		if WorldManager._pending_net_polylines.size() > 0:
			NetworkManager.send_polylines(WorldManager._pending_net_polylines.duplicate())
			WorldManager._pending_net_polylines.clear()
		if WorldManager._pending_net_deletions.size() > 0:
			NetworkManager.send_deletions(WorldManager._pending_net_deletions.duplicate())
			WorldManager._pending_net_deletions.clear()
		if WorldManager._pending_net_poly_fullsync:
			NetworkManager.send_poly_fullsync()
			WorldManager._pending_net_poly_fullsync = false
		if WorldManager._pending_net_gz.size() > 0:
			NetworkManager.send_gz_changes(WorldManager._pending_net_gz.duplicate())
			WorldManager._pending_net_gz.clear()

	_phys_pos = Vector2(physics.get_pixel_x(), physics.get_pixel_y())
	_visual_pos = _phys_pos
	# Position is set in _process via interpolation for smooth rendering at uncapped FPS

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
	# Gear roll source: ACTUAL horizontal displacement since last frame — the
	# smiley is locked to the ground like a gear (one rotation per
	# ROLL_PX_PER_REV px moved, zero drift vs real movement).
	var _roll_dx: float = physics.x - _last_roll_x
	_last_roll_x = physics.x
	if absf(_roll_dx) > 32.0:
		_roll_dx = 0.0  # Teleport/respawn — no spin burst
	if _use_anim_sprite and _smiley_sprite:
		if physics.is_wedged:
			# Wedged between curves: perfectly upright, no rolling
			_smiley_sprite.rotation = lerp_angle(_smiley_sprite.rotation, 0.0, _rc(0.5, delta))
		elif physics.is_god_mode:
			# God mode: no rolling, stay upright (animation handles direction)
			_smiley_sprite.rotation = lerp_angle(_smiley_sprite.rotation, 0.0, _rc(0.3, delta))
		else:
			var spd_total: float = absf(physics._speedX) + absf(physics._speedY)
			if spd_total > 0.3 and GameState.rotation_enabled:
				# Gear roll: one full rotation per block of travel
				_smiley_sprite.rotation = fmod(_smiley_sprite.rotation + (_roll_dx / ROLL_PX_PER_REV) * TAU, TAU)
			elif not GameState.rotation_enabled and physics.on_rotated_block and physics.is_grounded:
				# Rotate OFF: no rolling, but tilt with the surface so the face
				# points "up" along the curve/slope normal
				_smooth_normal = _smooth_normal.lerp(physics._surface_normal, _rc(0.25, delta))
				if _smooth_normal.length() > 0.01:
					var tilt: float = atan2(_smooth_normal.x, -_smooth_normal.y)
					_smiley_sprite.rotation = lerp_angle(_smiley_sprite.rotation, tilt, _rc(0.25, delta))
			else:
				# No momentum: lerp back to upright so directional sprites look correct
				_smiley_sprite.rotation = lerp_angle(_smiley_sprite.rotation, 0.0, _rc(0.3, delta))
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
			_glow_intensity = lerpf(_glow_intensity, target, _rc(0.15, delta))
			if _glow_intensity > 0.1 and GameState.trails_enabled:
				var vel: Vector2 = Vector2(physics._speedX, physics._speedY)
				var spd_len: float = vel.length()
				if spd_len > 0.5:
					var vel_dir: Vector2 = vel / spd_len
					var ball_center: Vector2 = Vector2(physics.x + 8, physics.y + 8)
					# Reset prev position if too far (first frame or teleport)
					if _prev_fire_pos.distance_to(ball_center) > 64:
						_prev_fire_pos = ball_center
					# Interpolate spawn positions between prev and current to fill gaps
					var move_dist: float = ball_center.distance_to(_prev_fire_pos)
					var steps: int = maxi(1, int(move_dist / 1.0))  # One burst per ~1px
					# Time-scaled budget (tuned at 60Hz): same particles/second at any FPS
					var _budget: float = maxf((15.0 + _glow_intensity * 15.0) * delta * VISUAL_TUNE_HZ, 4.0 * move_dist)
					var per_step: int = maxi(1, int(ceil(_budget / steps)))
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
					# Meteor heat shield: falling with gravity, or any momentum in gravity zone
					var grav_dir: Vector2 = Vector2(physics.mox, physics.moy)
					if grav_dir.length() < 0.01:
						grav_dir = Vector2(0, 1)
					grav_dir = grav_dir.normalized()
					var fall_speed: float = vel.dot(grav_dir)
					# In gravity zone: all momentum counts
					var in_gz: bool = WorldManager.gravity_zones.get_gravity_at(physics.x + 8.0, physics.y + 8.0).in_zone
					if in_gz:
						fall_speed = vel.length()
					var meteor_intensity: float = clampf((fall_speed - 3.0) / 10.0, 0.0, 1.0)
					if meteor_intensity > 0.1:
						var meteor_amt: float = meteor_intensity
						var meteor_count: int = int(round((5.0 + meteor_amt * 60.0) * delta * VISUAL_TUNE_HZ))
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
					if _fire_particles.size() > 2000:
						_fire_particles.resize(2000)
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
		# Clear stray particles when stopped (but not in gravity zone — let them get sucked in)
		var _in_gz: bool = WorldManager.gravity_zones.get_gravity_at(physics.x + 8.0, physics.y + 8.0).in_zone
		if (not GameState.trails_enabled or _glow_intensity < 0.05) and not _fire_particles.is_empty() and not _in_gz and not _is_dead:
			_fire_particles.clear()
			_prev_fire_pos = Vector2.ZERO
			if _fire_layer:
				_fire_layer.queue_redraw()
		queue_redraw()
	elif _smiley_sprite:
		# Legacy smiley rotation for non-animated sprites
		if physics.is_god_mode:
			_smiley_sprite.rotation = lerp_angle(_smiley_sprite.rotation, 0.0, _rc(0.3, delta))
		elif physics.in_valley:
			_smiley_sprite.rotation = 0.0
			_valley_smiley_ticks = 10
		elif not physics.on_rotated_block or not physics.is_grounded:
			# In air or on grid: clear flip state and lerp back to upright
			_last_normal = Vector2(0, -1)
			_valley_smiley_ticks = 0
			_smiley_sprite.rotation = lerp_angle(_smiley_sprite.rotation, 0.0, _rc(0.3, delta))
		elif physics.on_rotated_block and physics.is_grounded:
			var n: Vector2 = physics._surface_normal
			# Smooth the normal to prevent flicker
			_smooth_normal = _smooth_normal.lerp(n, _rc(0.15, delta))
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
				_smiley_sprite.rotation = lerp_angle(_smiley_sprite.rotation, 0.0, _rc(0.3, delta))
			elif spd_total < 0.3:
				_smiley_sprite.rotation = lerp_angle(_smiley_sprite.rotation, 0.0, _rc(0.1, delta))
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
				_smiley_sprite.rotation = lerp_angle(_smiley_sprite.rotation, target_angle, _rc(0.15, delta))
		elif physics.is_grounded:
			_smiley_sprite.rotation = lerp_angle(_smiley_sprite.rotation, 0.0, _rc(0.2, delta))

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
	# Speech bubble: show when idle 2s and has text, hide on move
	if _speech_label:
		if _speech_timer > 0:
			_speech_timer -= delta
		if _total_speed > 0.3 or _speech_timer <= 0:
			_speech_label.visible = false
		elif _idle_timer > 2.0 and not _speech_text.is_empty():
			_speech_label.visible = true

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
			var kill_r: float = gz.get("center_radius", 8.0) + 9.0
			if player_center.distance_to(gz.center) < kill_r:
				_die_gravity_zone(gz.center)
				return
	# OOB
	if physics.y > WorldManager.world_height * 16 + 80:
		_die()

func _process(delta: float) -> void:
	# Game update runs at render rate: the 240Hz tick accumulator sees fresh
	# input every rendered frame (on a 240Hz display that is one tick per
	# frame — no batching, minimal input latency).
	_tick_update(delta)
	# Combat screen shake decays fast (half-life ~75ms)
	if is_local and GameState.cam_shake > 0.001:
		GameState.cam_shake *= pow(0.0001, delta)
	# Frame interpolation: smooth position between physics ticks at uncapped render FPS.
	if is_local and not _is_dead and _last_tick_time_ms > 0.0:
		var now_ms: float = Time.get_ticks_msec()
		var elapsed_ms: float = now_ms - _last_tick_time_ms
		var alpha: float = clampf(elapsed_ms / EEPhysics.MS_PER_TICK, 0.0, 1.0)
		position = _prev_tick_pos.lerp(_curr_tick_pos, alpha)
	if _show_debug and _debug_label and physics:
		_debug_label.text = physics.debug_text
	# Force clear particles 1.5s after death
	if _is_dead and _death_timer > 1.5 and not _fire_particles.is_empty():
		_fire_particles.clear()
		if _fire_layer:
			_fire_layer.queue_redraw()
		return
	# Update fire particles even when dead (get sucked into black hole)
	var fi: int = _fire_particles.size() - 1
	while fi >= 0:
		var gz_pull: Dictionary = WorldManager.gravity_zones.get_gravity_at(_fire_particles[fi].wpos.x, _fire_particles[fi].wpos.y)
		var in_gz: bool = gz_pull.in_zone
		# Only upon death: don't decay life in gravity zone (die at center void)
		if not (in_gz and _is_dead):
			_fire_particles[fi].life -= delta
		var hit_void: bool = false
		if _is_dead and _gz_death:
			for gz in WorldManager.gravity_zones.zones:
				var d: float = _fire_particles[fi].wpos.distance_to(gz.center)
				if d < 4.0:
					hit_void = true
					break
		if _fire_particles[fi].life <= 0 or hit_void:
			_fire_particles.remove_at(fi)
		else:
			var new_pos: Vector2 = _fire_particles[fi].wpos + _fire_particles[fi].vel * delta
			var tx: int = int(floor(new_pos.x / 16.0))
			var ty: int = int(floor(new_pos.y / 16.0))
			if WorldManager.is_solid_at(tx, ty):
				_fire_particles[fi].vel *= -0.2
				_fire_particles[fi].life *= 0.5
			else:
				_fire_particles[fi].wpos = new_pos
			_fire_particles[fi].vel *= 0.96
			if not (_is_dead and _gz_death):
				_fire_particles[fi].vel.x += randf_range(-1, 1) * delta * 20
				_fire_particles[fi].vel.y += randf_range(-1, 1) * delta * 20
			# Black hole sucks in fire particles
			if in_gz:
				var pull_str: float = 800.0
				if _is_dead:
					for gz in WorldManager.gravity_zones.zones:
						var d: float = _fire_particles[fi].wpos.distance_to(gz.center)
						if d < 30.0:
							pull_str += 2000.0 / maxf(d, 1.0)
							_fire_particles[fi].vel *= 0.9
				_fire_particles[fi].vel += gz_pull.direction * delta * pull_str
		fi -= 1
	# When dead: if only 1 particle left, it's the stray — kill it
	if _is_dead and _fire_particles.size() == 1:
		_fire_particles.clear()
	if _show_hitboxes:
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
	# Draw collision_only polyline centerlines (blue) and sprite edges (cyan)
	for _poly in WorldManager.polylines:
		if not _poly.get("collision_only", false):
			continue
		var _pts: PackedVector2Array = _poly.points
		var _norms: Array = _poly.normals
		for _si in range(_pts.size() - 1):
			var _a: Vector2 = _pts[_si] - position
			var _b: Vector2 = _pts[_si + 1] - position
			# Centerline
			draw_line(_a, _b, Color(0, 0.5, 1, 0.3), 1.0)
		# Draw sprite edges (render_top/render_bot) to show the actual visual boundary
		var _rt: PackedVector2Array = _poly.render_top
		var _rb: PackedVector2Array = _poly.render_bot
		for _si in range(mini(_rt.size(), _rb.size()) - 1):
			draw_line(_rt[_si] - position, _rt[_si + 1] - position, Color(0.7, 0, 1, 0.6), 1.0)
			draw_line(_rb[_si] - position, _rb[_si + 1] - position, Color(0.7, 0, 1, 0.6), 1.0)

@rpc("any_peer", "unreliable_ordered")
func _broadcast_state(data: Dictionary) -> void:
	var sender: int = multiplayer.get_remote_sender_id()
	# Route position to the correct player's remote sync
	var scene: Node = get_parent()
	if scene and scene.has_method("_get_player"):
		var p: Node = scene._get_player(sender)
		if p and p != self and p._remote_sync:
			p._remote_sync.receive_state(data)
			if data.has("sp"):
				p.set_speech(str(data.sp))
	elif _remote_sync and peer_id == sender:
		_remote_sync.receive_state(data)
		if data.has("sp"):
			set_speech(str(data.sp))

@rpc("any_peer", "reliable", "call_remote")
func _broadcast_tiles(tiles: Array) -> void:
	for tile in tiles:
		if tile.l == "fg":
			WorldManager.set_fg_tile(tile.x, tile.y, tile.id)
		elif tile.l == "bg":
			WorldManager.set_bg_tile(tile.x, tile.y, tile.id)

@rpc("any_peer", "reliable", "call_remote")
func _broadcast_clear_world() -> void:
	WorldManager.free_blocks.clear()
	WorldManager.block_groups.clear()
	WorldManager.polylines.clear()
	WorldManager.lines.clear()
	WorldManager.gravity_zones.clear()
	for y in range(1, WorldManager.world_height - 1):
		for x in range(1, WorldManager.world_width - 1):
			WorldManager.set_fg_tile(x, y, 0)
			WorldManager.set_bg_tile(x, y, 0)
			WorldManager.set_rotation(x, y, 0)
	WorldManager.tile_changed.emit(0, 0, 0)
	WorldManager.polylines_changed.emit()
	# Server relays to clients
	if NetworkManager.is_host and multiplayer.get_remote_sender_id() != 0:
		_broadcast_clear_world.rpc()

@rpc("any_peer", "reliable", "call_remote")
func _broadcast_fb_replace(remove_count: int, blocks: Array) -> void:
	# Remove last N free blocks (the ones being rotated)
	if remove_count > 0 and remove_count <= WorldManager.free_blocks.size():
		WorldManager.free_blocks.resize(WorldManager.free_blocks.size() - remove_count)
	# Add the new rotated blocks
	for b in blocks:
		WorldManager.free_blocks.append({"pos": Vector2(b.pos_x, b.pos_y), "id": b.id, "rotation": b.rot})
	WorldManager.tile_changed.emit(0, 0, 0)

@rpc("any_peer", "reliable", "call_remote")
func _broadcast_freeblocks(blocks: Array) -> void:
	for b in blocks:
		WorldManager.free_blocks.append({"pos": Vector2(b.pos_x, b.pos_y), "id": b.id, "rotation": b.rot})
	WorldManager.tile_changed.emit(0, 0, 0)

@rpc("any_peer", "reliable", "call_remote")
func _broadcast_polylines(polylines: Array) -> void:
	for pl in polylines:
		var pts: PackedVector2Array = PackedVector2Array()
		for p in pl.pts:
			pts.append(Vector2(p.x, p.y))
		WorldManager.add_polyline(pts, pl.side, pl.bid)

@rpc("any_peer", "reliable", "call_remote")
func _broadcast_deletions(deletions: Array) -> void:
	for d in deletions:
		if d.type == "fb":
			# Find and remove free block by position + id
			for i in range(WorldManager.free_blocks.size() - 1, -1, -1):
				var fb: Dictionary = WorldManager.free_blocks[i]
				if fb.id == d.id and absf(fb.pos.x - d.x) < 2.0 and absf(fb.pos.y - d.y) < 2.0:
					WorldManager.free_blocks.remove_at(i)
					break
		elif d.type == "poly":
			WorldManager.remove_polyline_near(Vector2(d.x, d.y), d.r)
	WorldManager.tile_changed.emit(0, 0, 0)

func _input(event: InputEvent) -> void:
	if not is_local:
		return
	# Ctrl+scroll = zoom
	if event is InputEventMouseButton and (Input.is_key_pressed(KEY_CTRL) or Input.is_key_pressed(KEY_META)) and _camera:
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
		cam.x = cam.x + (pc.x - cam.x) * _cam_lerp
		cam.y = cam.y + (pc.y - cam.y) * _cam_lerp
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
	# Clear fire trail — but NOT for gravity zone death (let it get sucked in)
	if not _gz_death:
		_fire_particles.clear()
	_glow_intensity = 0.0
	_prev_fire_pos = Vector2.ZERO
	if _fire_layer:
		_fire_layer.queue_redraw()
	if not _gz_death:
		_smiley_sprite.visible = false
	died.emit()

func set_speech(text: String) -> void:
	_speech_text = text
	_speech_timer = 8.0  # Show for 8 seconds
	if _speech_label:
		_speech_label.text = text
	if is_local:
		_pending_speech = text

func _respawn() -> void:
	_is_dead = false
	_gz_death = false
	_smiley_sprite.visible = true
	_smiley_sprite.modulate = Color.WHITE
	_smiley_sprite.scale = Vector2(ANIM_SCALE, ANIM_SCALE)
	_smiley_sprite.rotation = 0.0
	_name_label.visible = true
	var sp: Vector2 = WorldManager.get_spawn_point()
	physics.set_position_tiles(sp.x, sp.y)
	_phys_pos = Vector2(physics.get_pixel_x(), physics.get_pixel_y())
	_visual_pos = _phys_pos
	position = _phys_pos
	if _camera:
		_camera.global_position = _phys_pos + Vector2(8, 8)
