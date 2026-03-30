class_name EEPhysics
extends RefCounted
## EXACT port of EEIO PlayerPhysics. Position in PIXELS, speed in internal units.

const MS_PER_TICK: float = 10.0
const MULT: float = 7.752
const SPEED_CLAMP: float = 16.0
const TICK_SCALE: float = 1.0

var _gravity: float = 2.0
var _jump_height: float = 26.0

var _base_drag: float = pow(0.9981, 10.0) * 1.00016093
var _no_mod_drag: float = pow(0.9900, 10.0) * 1.00016093
var _no_mod_drag_sqrt: float = sqrt(pow(0.9900, 10.0) * 1.00016093)  # For diagonal: apply to both axes = same total

# Position in PIXELS
var x: float = 16.0
var y: float = 16.0

# Speed in internal units
var _speedX: float = 0.0
var _speedY: float = 0.0

# Gravity vectors
var morx: float = 0.0
var mory: float = 0.0
var mox: float = 0.0
var moy: float = 0.0

var flipGravity: int = 0
var low_gravity: bool = false
var jumpBoost: int = 0
var speedBoost: int = 0
var maxJumps: int = 1
var jumpCount: int = 0
var lastJumpMs: float = -99999.0
var is_god_mode: bool = false
var is_grounded: bool = false
var is_wedged: bool = false  # Touching curve wall — frozen, jump straight up
var purple_pushed: bool = false  # True when purple line push is active (for visual smoothing)
var debug_text: String = ""  # On-screen debug info
var _wedge_pos: Vector2 = Vector2(-9999, -9999)  # Position where wedge occurred
var _wedge_protect: int = 0  # Ticks of post-wedge protection
var _wedge_safe_pos: Vector2 = Vector2(0, 0)  # Last position where NOT wedged
var _wedge_escape_cooldown: int = 0  # Ticks after escape — don't re-wedge
var _wedge_allow_left: bool = false
var _wedge_allow_right: bool = false
var _wedge_allow_up: bool = false
var _wedge_allow_down: bool = false
var _wedge_freeze_pos: Vector2 = Vector2(0, 0)  # Position where wedge was set
var _wedge_freeze_dir: Vector2 = Vector2(0, 0)  # Direction player can't move past (into the V)
var _poly_cross_cooldown: int = 0  # Ticks after crossing placement (prevent jitter)
var _last_good_pos: Vector2 = Vector2(-99999, -99999)  # Last position NOT inside any purple line
var _wedge_clear_ticks: int = 0  # Ticks wall has been NOT blocked (need 3 to clear)
var _wedge_arc: float = -1.0  # Arc position when wedge was set (preserved while wedged)
var on_rotated_block: bool = false
var _stick_curve: int = -1  # Source polyline index for curve collision filtering
var in_valley: bool = false
var valley_jump: bool = false
var _pos_history: Array = []
var _valley_center: Vector2 = Vector2(-1, -1)  # Locked position in V
var _surface_normal: Vector2 = Vector2(0, -1)
var _prev_push_normal: Vector2 = Vector2.ZERO
var _prev_poly_normal: Vector2 = Vector2.ZERO  # Polyline push from last tick
var _stick_poly_idx: int = -1  # Polyline index player is currently on
var _stick_poly_ticks: int = 0  # Ticks since last contact with stuck poly
var _stick_arc_pos: float = -1.0  # Arc-length position on stick poly
var _last_stick_poly: int = -1  # Remembers stick poly after decay
var _poly_segs: Array = []  # Cached nearby non-stick polyline segments
var _poly_active: bool = false
var _poly_thresh2: float = 16.5
var _valley_ticks: int = 0
var _flip_count: int = 0
var _near_pinch_ticks: int = 0  # Ticks spent near a V-junction pinch (for forced wedge)
var _jump_cooldown: int = 0
var _jumped_in_arrow: bool = false
var _arrow_clear_ticks: int = 0  # Count ticks without arrows before resetting
var _coyote_ticks: int = 0  # Ticks since last grounded on rotated block
var _stuck_ticks: int = 0
var _last_push_dir: Vector2 = Vector2.ZERO
var _last_push_rot2: int = -999
var _push_dampen: float = 1.0
var _was_on_rotated: bool = false
var on_dot: bool = false
var slow_dot: bool = false
var _active_arrow_dir: int = -1  # -1 = no arrow, 0-3 = nearest cardinal
# EE delayed action queue: [current, delayed] - gives 2-tick grace period
var _action_queue: Array = [0, 0]
var _action_queue_rot: Array = [0, 0]  # Rotation degrees parallel to _action_queue
var _current_action_id: int = 0
var _delayed_action_id: int = 0
var _current_action_rot: int = 0
var _delayed_action_rot: int = 0
var _now_ms: float = 0.0
var _last_input_h: float = 0.0  # Stored for slope input projection
var _fb_hit: bool = false

var _collides_fn: Callable = Callable()

func set_position_tiles(tx: float, ty: float) -> void:
	x = tx * 16.0
	y = ty * 16.0
	_speedX = 0.0
	_speedY = 0.0

func set_collides_fn(fn: Callable) -> void:
	_collides_fn = fn

func get_pixel_x() -> float:
	return x

func get_pixel_y() -> float:
	return y

func _get_grav_mult() -> float:
	if low_gravity: return 0.15
	return 1.0

func _get_jump_mult() -> float:
	if jumpBoost == 1: return 1.3
	if jumpBoost == 2: return 0.75
	return 1.0

func _get_speed_mult() -> float:
	if slow_dot: return 0.6
	if speedBoost == 1: return 1.5
	if speedBoost == 2: return 0.6
	return 1.0

func tick(input_h: int, input_v: int, space_just: bool, space_held: bool) -> void:
	# Wedge: only JUMP escapes (section 7 handles this).
	# Directional input while wedged is suppressed — the player is frozen.
	# (Old behavior let any input escape, causing rapid wedge/unwedge oscillation
	# when holding a key into the V.)
	_now_ms += MS_PER_TICK
	# Track speed in gravity direction to prevent jump during launch
	var _pre_tick_speedY: float = _speedY
	var _pre_tick_speedX: float = _speedX
	# Speed TOWARD the ground: dot product of speed with gravity direction
	# Positive = falling toward ground, negative = jumping away
	var _pre_tick_grav_speed: float = _speedY  # Default: down gravity
	var _grav_vec: Vector2 = Vector2(mox, moy)
	if _grav_vec.length_squared() > 0.01:
		_pre_tick_grav_speed = Vector2(_speedX, _speedY).dot(_grav_vec.normalized())
	else:
		match _active_arrow_dir:
			1: _pre_tick_grav_speed = -_speedX
			2: _pre_tick_grav_speed = -_speedY
			3: _pre_tick_grav_speed = _speedX
	if _jump_cooldown > 0:
		_jump_cooldown -= 1
	if _wedge_escape_cooldown > 0:
		_wedge_escape_cooldown -= 1
	# Reset grounded each tick - will be recomputed by _check_grounded later
	is_grounded = false
	# Save safe position when not wedged
	if not is_wedged:
		_wedge_safe_pos = Vector2(x, y)

	if is_god_mode:
		on_dot = true
		slow_dot = false

	if valley_jump:
		if input_h != 0:
			# Player wants to exit the valley
			valley_jump = false
			_valley_center = Vector2(-1, -1)
			_pos_history.clear()
			_prev_push_normal = Vector2.ZERO
		else:
			input_v = 0
			_speedX = 0
	_last_input_h = float(input_h)

	# 1. Gravity
	_compute_gravity()

	# 2. Input mapping (restrict to perpendicular axis, or free on dot)
	var inH: float = float(input_h)
	var inV: float = float(input_v)
	if on_dot:
		# Dots: allow both axes freely
		if slow_dot:
			inH *= 0.6
			inV *= 0.6
	else:
		# In arrow fields: allow both axes (raw world-space input)
		if _active_arrow_dir >= 0 and absf(mox) > 0.01 and absf(moy) > 0.01:
			pass  # Keep both inH and inV — raw directional input
		elif absf(moy) > 0:
			inV = 0
		elif absf(mox) > 0:
			inH = 0

	# 3. Multipliers
	var sm: float = _get_speed_mult()
	var gm: float = _get_grav_mult()
	var mx: float = inH * sm
	var my: float = inV * sm
	var moxAcc: float = mox * gm
	var moyAcc: float = moy * gm

	# 4. Modifiers (display -> internal, scaled for tick rate)
	var _modX: float = (moxAcc + mx) * TICK_SCALE / MULT
	var _modY: float = (moyAcc + my) * TICK_SCALE / MULT

	var _diag_arrow: bool = _active_arrow_dir >= 0 and absf(mox) > 0.01 and absf(moy) > 0.01

	# 5. X axis: speed += mod, base_drag, clamp
	if _speedX != 0 or _modX != 0:
		_speedX += _modX
		_speedX *= _base_drag
		if not on_dot and not _diag_arrow:
			if (mx == 0 and moyAcc != 0) or (_speedX < 0 and mx > 0) or (_speedX > 0 and mx < 0):
				_speedX *= _no_mod_drag
		if _speedX > SPEED_CLAMP: _speedX = SPEED_CLAMP
		elif _speedX < -SPEED_CLAMP: _speedX = -SPEED_CLAMP
		elif absf(_speedX) < 0.0001: _speedX = 0

	# 6. Y axis
	if _speedY != 0 or _modY != 0:
		_speedY += _modY
		_speedY *= _base_drag
		if not on_dot and not _diag_arrow:
			if (my == 0 and moxAcc != 0) or (_speedY < 0 and my > 0) or (_speedY > 0 and my < 0):
				_speedY *= _no_mod_drag
		if _speedY > SPEED_CLAMP: _speedY = SPEED_CLAMP
		elif _speedY < -SPEED_CLAMP: _speedY = -SPEED_CLAMP
		elif absf(_speedY) < 0.0001: _speedY = 0

	# Diagonal arrow fields: apply no_mod_drag to PERPENDICULAR component only
	# Matches flat ground where jump axis (Y) never gets extra drag
	if _diag_arrow and not on_dot:
		var has_input: bool = absf(_last_input_h) > 0.01
		if not has_input:
			var grav_n: Vector2 = Vector2(mox, moy)
			var gl: float = grav_n.length()
			if gl > 0.01:
				grav_n = grav_n / gl
				var spd: Vector2 = Vector2(_speedX, _speedY)
				var parallel: float = spd.dot(grav_n)  # Along gravity = jump axis, no drag
				var perp_vec: Vector2 = spd - grav_n * parallel  # Perpendicular = walk axis
				perp_vec *= _no_mod_drag  # Only drag the walk component
				var new_spd: Vector2 = grav_n * parallel + perp_vec
				_speedX = new_spd.x
				_speedY = new_spd.y

	# Valley: zero X speed after ALL modifiers (arrow gravity can add X)
	if valley_jump:
		_speedX = 0

	# 7. Step position
	# If wedged, suppress all speed — only jump can escape
	if _wedge_protect > 0:
		_wedge_protect -= 1
	if is_wedged:
		if space_just:
			# Jump = full reset, as if never been on a curve
			is_wedged = false
			_stick_curve = -1
			_wedge_protect = 0
			is_grounded = true
			_surface_normal = Vector2(0, -1)
			jumpCount = 0
		else:
			_speedX = 0
			_speedY = 0
			is_grounded = true
			# Clamp to wedge point — can't drift away
			x = _wedge_safe_pos.x
			y = _wedge_safe_pos.y
	var _pre_step_x: float = x
	var _pre_step_y: float = y
	var _pre_collision_speed: float = Vector2(_speedX, _speedY).length()
	# 7.05 CCD: prevent centerline crossing + V-junction overshoot
	if not is_god_mode and WorldManager.polylines.size() > 0:
		var _ccd_spd: float = absf(_speedX) + absf(_speedY)
		if _ccd_spd > 4.0:
			# Phase 1: prevent centerline crossing (anti-tunnel)
			# Skip when already riding the crossed curve (within 18px = normal riding distance).
			# Only clip when approaching from far away (actual tunneling).
			var _cross: Dictionary = WorldManager.check_polyline_crossing(x, y, x + _speedX, y + _speedY)
			if _cross.crossed:
				var _cross_dist: float = WorldManager.dist_to_polyline_idx(x + 8.0, y + 8.0, _cross.poly_idx)
				if _cross_dist > 18.0:
					var _safe_t: float = maxf(_cross.t - 0.1, 0.0)
					_speedX *= _safe_t
					_speedY *= _safe_t
		# Phase 2: prevent overshooting V-junction pinch points (ray-sphere test)
		# Only checks pre-computed wedge pair pinch points — no stutter on normal riding.
		if _ccd_spd > 2.0 and WorldManager.wedge_pairs.size() > 0:
			var _pre_cx: float = x + 8.0
			var _pre_cy: float = y + 8.0
			var _spd_vec: Vector2 = Vector2(_speedX, _speedY)
			var _spd_len: float = _spd_vec.length()
			if _spd_len > 0.1:
				var _spd_dir: Vector2 = _spd_vec / _spd_len
				var _min_scale: float = 1.0
				for _wp in WorldManager.wedge_pairs:
					var _pinch: Vector2 = _wp.pinch_point
					var _to_pinch: Vector2 = _pinch - Vector2(_pre_cx, _pre_cy)
					var _pre_dist: float = _to_pinch.length()
					if _pre_dist < 16.35:
						continue  # Inside pinch zone — post-movement check handles this
					var _approach: float = _to_pinch.dot(_spd_dir)
					if _approach <= 0:
						continue  # Moving away from pinch
					# Perpendicular distance squared from ray to pinch
					var _perp_sq: float = _pre_dist * _pre_dist - _approach * _approach
					var _r_sq: float = 16.35 * 16.35
					if _perp_sq >= _r_sq:
						continue  # Ray misses the pinch sphere
					# Distance along ray to sphere entry point
					var _entry: float = _approach - sqrt(_r_sq - _perp_sq)
					if _entry < 0:
						_entry = 0
					if _entry < _spd_len:
						var _scale: float = _entry / _spd_len
						if _scale < _min_scale:
							_min_scale = _scale
				if _min_scale < 1.0:
					_speedX *= _min_scale
					_speedY *= _min_scale
	var _pre_step_sX: float = _speedX  # Save for curve tangent projection after tile hits
	var _pre_step_sY: float = _speedY
	_step_position()

	# 7.07 Post-movement V-junction tunneling detection.
	# Only fires when the movement path actually crossed through a pinch point
	# (sign change on bisector plane while close to pinch). Does NOT interfere
	# with normal riding or oscillation — only catches genuine tunneling.
	if not is_god_mode and WorldManager.wedge_pairs.size() > 0:
		var _pm_pre: Vector2 = Vector2(_pre_step_x + 8.0, _pre_step_y + 8.0)
		var _pm_post: Vector2 = Vector2(x + 8.0, y + 8.0)
		var _pm_move: Vector2 = _pm_post - _pm_pre
		if _pm_move.length() > 2.0:
			for _wp in WorldManager.wedge_pairs:
				var _pinch: Vector2 = _wp.pinch_point
				var _bn: Vector2 = _wp.bisector_normal
				# Point-to-segment distance: did movement pass close to pinch?
				var _pm_len_sq: float = _pm_move.dot(_pm_move)
				var _pm_t: float = clampf((_pinch - _pm_pre).dot(_pm_move) / maxf(_pm_len_sq, 0.001), 0.0, 1.0)
				var _pm_closest: Vector2 = _pm_pre + _pm_move * _pm_t
				if _pm_closest.distance_to(_pinch) < 24.0:
					# Movement passed near pinch — check for plane crossing
					var _pm_pre_s: float = (_pm_pre - _pinch).dot(_bn)
					var _pm_post_s: float = (_pm_post - _pinch).dot(_bn)
					if _pm_pre_s > 0 and _pm_post_s < 0.0:
						# Crossed from open side deep into V interior — tunneling!
						# Snap to where signed_dist = 1.0 (safe margin on open side)
						var _pm_ds: float = _pm_pre_s - _pm_post_s
						if _pm_ds > 0.01:
							var _pm_safe_t: float = clampf((_pm_pre_s - 1.0) / _pm_ds, 0.0, 1.0)
							var _pm_safe: Vector2 = _pm_pre + _pm_move * _pm_safe_t
							x = _pm_safe.x - 8.0
							y = _pm_safe.y - 8.0
						else:
							x = _pre_step_x
							y = _pre_step_y
						# Zero speed into V, preserve along-V speed
						var _pm_into: float = Vector2(_speedX, _speedY).dot(-_bn)
						if _pm_into > 0:
							_speedX += _bn.x * _pm_into
							_speedY += _bn.y * _pm_into

	# 7.5 Line collision
	if not is_god_mode:
		var snap_y: float = WorldManager.check_line_collision(x, y + 2, 16.0, 16.0)
		if snap_y >= 0 and _pre_tick_grav_speed >= 0:  # Only when was falling/standing
			y = snap_y
			_speedY = 0
			is_grounded = true
			_surface_normal = Vector2(0, -1)  # Lines are roughly horizontal
			var slide: float = WorldManager.get_line_slide_force(x, y, 16.0, 16.0)
			if slide != 0.0:
				_speedX += slide
		else:
			var line_y: float = WorldManager.check_line_collision(x, y, 16.0, 16.0)
			if line_y >= 0 and line_y < y:
				y = line_y
				if _speedY > 0:
					_speedY = 0

	# 7.6 Rotated block surface sliding (simple best-push)
	var _polyline_normal: Vector2 = _surface_normal
	on_rotated_block = false
	in_valley = false
	var on_tile: bool = _check_grounded() and _pre_tick_grav_speed >= 0
	_fb_hit = false
	if not is_god_mode and not is_wedged and WorldManager.free_blocks.size() > 0:
		var best_push: Vector2 = Vector2.ZERO
		var best_depth: float = 0.0
		var hit: bool = false
		var _overlap_rots: Dictionary = {}
		var _ceiling_v_exit: bool = false  # Set when ceiling V early-exit fires
		for _pass in range(8):
			var pass_push: Vector2 = Vector2.ZERO
			var pass_depth: float = 0.0
			for fb in WorldManager.free_blocks:
				if not GameState.is_solid(fb.id):
					continue
				if fb.get("curve_visual", false):
					continue
				var bpos: Vector2 = fb.pos
				var rot_rad: float = deg_to_rad(fb.rotation)
				var bcx: float = bpos.x + 8.0
				var bcy: float = bpos.y + 8.0
				var dx2: float = (x + 8.0) - bcx
				var dy2: float = (y + 8.0) - bcy
				var cos_r: float = cos(-rot_rad)
				var sin_r: float = sin(-rot_rad)
				var lx: float = dx2 * cos_r - dy2 * sin_r
				var ly: float = dx2 * sin_r + dy2 * cos_r
				var ox2: float = 16.0 - absf(lx)
				var oy2: float = 16.0 - absf(ly)
				var abs_c: float = absf(cos(rot_rad))
				var abs_s: float = absf(sin(rot_rad))
				var bpx: float = 8.0 * abs_c + 8.0 * abs_s
				var bpy: float = 8.0 * abs_s + 8.0 * abs_c
				var wox: float = (8.0 + bpx) - absf(dx2)
				var woy: float = (8.0 + bpy) - absf(dy2)
				if ox2 > 0 and oy2 > 0 and wox > 0 and woy > 0:
					var push_lx: float = 0.0
					var push_ly: float = 0.0
					if oy2 < ox2:
						push_ly = oy2 * sign(ly)
					else:
						push_lx = ox2 * sign(lx)
					var cos_r2: float = cos(rot_rad)
					var sin_r2: float = sin(rot_rad)
					var wx: float = push_lx * cos_r2 - push_ly * sin_r2
					var wy: float = push_lx * sin_r2 + push_ly * cos_r2
					var depth: float = Vector2(wx, wy).length()
					var rk: int = (int(round(fb.rotation / 20.0)) * 20) % 180
					_overlap_rots[rk] = true
					if depth > pass_depth:
						pass_depth = depth
						pass_push = Vector2(wx, wy)
						hit = true
						_fb_hit = true
			if pass_depth > 0.01:
				if valley_jump:
					pass_push.x = 0
				x += pass_push.x
				y += pass_push.y
				if pass_depth > best_depth:
					best_depth = pass_depth
					best_push = pass_push
				if _overlap_rots.size() >= 2:
					var _gcheck: Vector2 = Vector2(mox, moy)
					if _gcheck.length() < 0.01: _gcheck = Vector2(0, 1)
					if -pass_push.normalized().dot(_gcheck.normalized()) <= 0:
						_ceiling_v_exit = true
						break
			else:
				break
		# Detect valley: only when actually overlapping 2+ different-rotation blocks
		var _pre_total_spd: float = absf(_pre_tick_speedX) + absf(_pre_tick_speedY)
		# Valley detection: only for floor V's (push against gravity)
		if hit and _overlap_rots.size() >= 2 and not _ceiling_v_exit:
			var _gd3: Vector2 = Vector2(mox, moy)
			if _gd3.length() < 0.01: _gd3 = Vector2(0, 1)
			var _bp_against: float = -best_push.normalized().dot(_gd3.normalized())
			if _bp_against > 0.3:  # Strong floor V only — exposed/ceiling V's let player slide out
				in_valley = true
				is_grounded = true
		if hit and best_depth > 0.01:
			# Valley: zero speed only when settling (low speed), not when entering at speed
			if in_valley and absf(_speedX) < 0.5 and absf(_speedY) < 0.5:
				_speedX = 0
			# Check if iterative pushes put us into a grid tile — undo if so
			if _collides_px(x, y):
				x -= best_push.x
				y -= best_push.y
				if not _collides_px(x + best_push.x, y):
					x += best_push.x
				elif not _collides_px(x, y + best_push.y):
					y += best_push.y
			var n: Vector2 = best_push.normalized() if best_push.length() > 0.01 else Vector2(0, -1)
			# Check if push is wall-like or floor-like relative to gravity
			var grav_dir2: Vector2 = Vector2(mox, moy)
			if grav_dir2.length() < 0.01:
				grav_dir2 = Vector2(0, 1)
			else:
				grav_dir2 = grav_dir2.normalized()
			var against_grav2: float = -n.dot(grav_dir2)  # Positive = floor, negative = ceiling
			var _is_ceiling_v: bool = _overlap_rots.size() >= 2 and against_grav2 < 0.3
			if not valley_jump:
				if against_grav2 < 0.05 or _is_ceiling_v:
					# Wall or ceiling V: just zero the speed component into the surface.
					# Don't do tangent projection — for walls it bleeds speed, for ceiling V's
					# it eats the gravity component that should pull the player out.
					var into_wall: float = Vector2(_speedX, _speedY).dot(n)
					if into_wall < 0:
						_speedX -= n.x * into_wall
						_speedY -= n.y * into_wall
				else:
					# Floor/slope: tangent projection with speed preservation
					var tangent: Vector2 = Vector2(-n.y, n.x)
					if tangent.x < 0:
						tangent = -tangent
					var spd: Vector2 = Vector2(_speedX, _speedY)
					var spd_mag: float = spd.length()
					var prev_n_dot: float = _prev_push_normal.dot(n) if _prev_push_normal.length() > 0.1 else 0.0
					var tangent_speed: float = spd.dot(tangent)
					var grav: Vector2 = Vector2(mox, moy) * _get_grav_mult() / MULT * 0.5
					tangent_speed += grav.dot(tangent)
					var new_spd: Vector2 = tangent * tangent_speed
					var _falling_into_v: bool = _overlap_rots.size() >= 2 and absf(_pre_tick_speedY) > absf(_pre_tick_speedX) * 1.5
					# Speed preservation: only at JUNCTIONS (surface angle changed significantly)
					# Not on same surface (prev_n_dot > 0.9 = same surface, handled above)
					var _has_horizontal: bool = absf(_pre_tick_speedX) > absf(_pre_tick_speedY) * 0.5
					var _at_junction: bool = prev_n_dot < 0.95  # Surface angle changed (wider threshold for curve blocks)
					if spd_mag > 1.0 and new_spd.length() < spd_mag * 0.2 and not _falling_into_v and _at_junction and (_was_on_rotated or _has_horizontal):
						var dir: float = sign(_pre_tick_speedX)
						if dir == 0: dir = 1.0
						_speedX = tangent.x * spd_mag * dir
						_speedY = tangent.y * spd_mag * dir
					else:
						_speedX = new_spd.x
						_speedY = new_spd.y
			# Only mark as "on rotated block" for floor/slope, not walls
			if against_grav2 >= 0.05:
				on_rotated_block = true
				_surface_normal = n
			var grav_dir: Vector2 = Vector2(mox, moy)
			var grav_len2: float = grav_dir.length()
			if grav_len2 > 0.01:
				grav_dir = grav_dir / grav_len2
			else:
				grav_dir = Vector2(0, 1)
			var against_grav: float = -n.dot(grav_dir)
			if against_grav > 0.05 and not on_tile:
				is_grounded = true
				_jump_cooldown = 0
				if against_grav > 0.45:  # Only grant coyote time on non-steep surfaces
					_coyote_ticks = 4

	# 7.65 Curve collision — iterative push-out matching free block SAT behavior
	# Runs AFTER free blocks so state persists into valley detection below.
	# Uses centerline distance + interpolated normals, NOT render edges (no two-edge trap).
	# KEY DIFFERENCE from free blocks: curves SUM all pushes per pass (not deepest-only).
	# At V-junctions, both arms push simultaneously — summing gives the correct upward
	# resultant instead of oscillating between arms.
	var _cv_on_tile: bool = _check_grounded()  # On grid tiles = no curve valley (check BEFORE push-out)
	if not is_god_mode and not is_wedged and WorldManager.polylines.size() > 0:
		var _curve_hit: bool = false
		var _curve_best_push: Vector2 = Vector2.ZERO
		var _curve_best_depth: float = 0.0
		var _curve_rots: Dictionary = {}  # Rotation bins for valley detection
		var _curve_had_cancellation: bool = false  # True when pushes actually opposed (real V)
		var _curve_polys: Dictionary = {}  # Distinct polyline indices pushing
		var _curve_deepest_arm_normal: Vector2 = Vector2.ZERO  # Deepest individual arm normal (for tangent projection at V-junctions)
		var _curve_deepest_arm_depth: float = 0.0
		for _cpass in range(8):
			var _cpushes: Array = WorldManager.get_curve_push_data(x + 8.0, y + 8.0)
			var _cpass_push: Vector2 = Vector2.ZERO
			var _cpass_depth: float = 0.0
			var _cpass_deepest_push: Vector2 = Vector2.ZERO
			for _cp in _cpushes:
				# Rotation binning: 40-degree bins mod 180 (wider than free blocks' 20°
				# to prevent false positives from iterative push normal rotation on
				# smooth single curves, while still detecting genuine V-junctions)
				var _cangle: float = rad_to_deg(atan2(_cp.normal.y, _cp.normal.x))
				var _crk: int = (int(round(_cangle / 40.0)) * 40) % 180
				if _crk < 0: _crk += 180
				_curve_rots[_crk] = true
				_curve_polys[_cp.poly_idx] = true
				# SUM all pushes
				_cpass_push += _cp.push
				if _cp.depth > _cpass_depth:
					_cpass_depth = _cp.depth
					_cpass_deepest_push = _cp.push
				# Track deepest individual arm across ALL passes (for V-junction tangent)
				if _cp.depth > _curve_deepest_arm_depth:
					_curve_deepest_arm_depth = _cp.depth
					_curve_deepest_arm_normal = _cp.normal
				_curve_hit = true
			# Detect push cancellation: if sum < 50% of max depth, pushes oppose.
			# ADAPTIVE BISECTOR: compute escape direction from actual arm normals
			# at the player's current position (not a flat pre-computed plane).
			var _cpass_mag: float = _cpass_push.length()
			if _cpushes.size() >= 2 and _cpass_mag < _cpass_depth * 0.5 and _cpass_depth > 0.5:
				_curve_had_cancellation = true  # Pushes actually opposed — real V
				# Direction: normalized sum of push normals = local bisector
				var _bisector: Vector2 = Vector2.ZERO
				for _cp2 in _cpushes:
					_bisector += _cp2.normal
				var _bisector_len: float = _bisector.length()
				if _bisector_len >= 0.1:
					_bisector = _bisector / _bisector_len
				else:
					# Full cancellation: normals perfectly opposing.
					# Fallback: push from midpoint of closest centerline points toward player.
					var _mid: Vector2 = Vector2.ZERO
					for _cp2 in _cpushes:
						_mid += _cp2.closest_pt
					_mid /= _cpushes.size()
					var _to_pl: Vector2 = Vector2(x + 8.0, y + 8.0) - _mid
					if _to_pl.length() >= 0.5:
						_bisector = _to_pl.normalized()
					else:
						# Ultimate fallback: push from nearest pinch toward player
						var _best_wp_dist: float = 99999.0
						var _best_wp_pinch: Vector2 = Vector2.ZERO
						for _wp3 in WorldManager.wedge_pairs:
							var _d3: float = Vector2(x + 8.0, y + 8.0).distance_to(_wp3.pinch_point)
							if _d3 < _best_wp_dist:
								_best_wp_dist = _d3
								_best_wp_pinch = _wp3.pinch_point
						if _best_wp_dist < 100.0:
							var _tp2: Vector2 = Vector2(x + 8.0, y + 8.0) - _best_wp_pinch
							if _tp2.length() >= 0.5:
								_bisector = _tp2.normalized()
							else:
								var _gfb: Vector2 = Vector2(mox, moy)
								_bisector = -_gfb.normalized() if _gfb.length() > 0.01 else Vector2(0, -1)
						else:
							var _gfb: Vector2 = Vector2(mox, moy)
							_bisector = -_gfb.normalized() if _gfb.length() > 0.01 else Vector2(0, -1)
				# Magnitude: push along bisector enough to clear ALL arms simultaneously.
				# For each arm: needed = depth / cos(angle between bisector and arm normal).
				var _needed_mag: float = 0.0
				for _cp2 in _cpushes:
					var _cos_a: float = _bisector.dot(_cp2.normal)
					if _cos_a > 0.1:
						_needed_mag = maxf(_needed_mag, _cp2.depth / _cos_a)
					else:
						# Bisector nearly perpendicular to arm normal (very acute V)
						_needed_mag = maxf(_needed_mag, _cp2.depth * 3.0)
				_needed_mag = minf(_needed_mag, _cpass_depth * 4.0)
				_cpass_push = _bisector * _needed_mag
			else:
				# Normal case (no cancellation): clamp sum to 2x deepest depth
				_cpass_mag = _cpass_push.length()
				if _cpass_mag > _cpass_depth * 2.0 and _cpass_mag > 0.01:
					_cpass_push = _cpass_push * (_cpass_depth * 2.0 / _cpass_mag)
			if _cpass_depth > 0.01:
				if valley_jump:
					_cpass_push.x = 0
				x += _cpass_push.x
				y += _cpass_push.y
				if _cpass_depth > _curve_best_depth:
					_curve_best_depth = _cpass_depth
					_curve_best_push = _cpass_push
				# Early exit for ceiling V (push not against gravity)
				if _curve_rots.size() >= 2:
					var _cgcheck: Vector2 = Vector2(mox, moy)
					if _cgcheck.length() < 0.01: _cgcheck = Vector2(0, 1)
					if -_cpass_push.normalized().dot(_cgcheck.normalized()) <= 0:
						break
			else:
				break
		if _curve_hit and _curve_best_depth > 0.01:
			_fb_hit = true
			# Grid tile safety: undo push if it landed inside a tile
			if _collides_px(x, y):
				x -= _curve_best_push.x
				y -= _curve_best_push.y
				if not _collides_px(x + _curve_best_push.x, y):
					x += _curve_best_push.x
				elif not _collides_px(x, y + _curve_best_push.y):
					y += _curve_best_push.y
			# For tangent projection at V-junctions: use the deepest individual arm's
			# normal, not the bisector. The bisector is correct for POSITION (pushing
			# out of the V), but the arm normal is correct for SPEED (preserving
			# momentum along the arm surface, enabling oscillation like free blocks).
			var _cn: Vector2
			if _curve_polys.size() >= 2 and _curve_deepest_arm_normal.length() > 0.01:
				_cn = _curve_deepest_arm_normal
			else:
				_cn = _curve_best_push.normalized() if _curve_best_push.length() > 0.01 else Vector2(0, -1)
			var _cgrav_dir: Vector2 = Vector2(mox, moy)
			if _cgrav_dir.length() < 0.01:
				_cgrav_dir = Vector2(0, 1)
			else:
				_cgrav_dir = _cgrav_dir.normalized()
			var _cagainst_grav: float = -_cn.dot(_cgrav_dir)
			# Tangent speed projection (mirrors free block section 7.6 exactly)
			# _step_position() may have zeroed speed on one axis due to a grid tile hit.
			# If the curve push-out moved us to a valid position (not in a tile), use
			# pre-step speed for tangent projection — the tile hit was transient, the
			# curve is the actual surface, and momentum should be preserved along it.
			var _cspd_for_proj: Vector2 = Vector2(_speedX, _speedY)
			if not _collides_px(x, y):
				var _pre_step_spd_vec: Vector2 = Vector2(_pre_step_sX, _pre_step_sY)
				if _pre_step_spd_vec.length() > _cspd_for_proj.length() + 0.5:
					_cspd_for_proj = _pre_step_spd_vec
			if not valley_jump:
				if _cagainst_grav < 0.05:
					# Wall: zero speed component going into wall
					var _cinto: float = _cspd_for_proj.dot(_cn)
					if _cinto < 0:
						_speedX = _cspd_for_proj.x - _cn.x * _cinto
						_speedY = _cspd_for_proj.y - _cn.y * _cinto
					else:
						_speedX = _cspd_for_proj.x
						_speedY = _cspd_for_proj.y
				else:
					# Floor/slope: tangent projection with junction speed preservation
					var _ctangent: Vector2 = Vector2(-_cn.y, _cn.x)
					if _ctangent.x < 0:
						_ctangent = -_ctangent
					var _cspd: Vector2 = _cspd_for_proj
					var _cspd_mag: float = _cspd.length()
					var _cprev_n_dot: float = _prev_poly_normal.dot(_cn) if _prev_poly_normal.length() > 0.1 else 0.0
					var _ctangent_speed: float = _cspd.dot(_ctangent)
					var _cgrav_half: Vector2 = Vector2(mox, moy) * _get_grav_mult() / MULT * 0.5
					_ctangent_speed += _cgrav_half.dot(_ctangent)
					var _cnew_spd: Vector2 = _ctangent * _ctangent_speed
					var _cfalling_v: bool = _curve_rots.size() >= 2 and absf(_pre_tick_speedY) > absf(_pre_tick_speedX) * 1.5
					var _chas_horiz: bool = absf(_pre_tick_speedX) > absf(_pre_tick_speedY) * 0.5
					var _cat_junction: bool = _cprev_n_dot < 0.95
					if _cspd_mag > 1.0 and _cnew_spd.length() < _cspd_mag * 0.2 and not _cfalling_v and _cat_junction and (_was_on_rotated or _chas_horiz):
						var _cdir: float = sign(_pre_tick_speedX)
						if _cdir == 0: _cdir = 1.0
						_speedX = _ctangent.x * _cspd_mag * _cdir
						_speedY = _ctangent.y * _cspd_mag * _cdir
					else:
						_speedX = _cnew_spd.x
						_speedY = _cnew_spd.y
			# Grounding from curves
			if _cagainst_grav >= 0.05:
				on_rotated_block = true
				_surface_normal = _cn
			var _con_tile: bool = _check_grounded() and _pre_tick_grav_speed >= 0
			if _cagainst_grav > 0.05 and not _con_tile:
				is_grounded = true
				_jump_cooldown = 0
				if _cagainst_grav > 0.45:  # Only grant coyote time on non-steep surfaces
					_coyote_ticks = 4
		# Valley detection for curves: 2+ different 40-degree rotation bins = V-junction.
		# Only for floor and horizontal V's — NOT ceiling V's (where gravity pulls player out).
		if _curve_hit and _curve_rots.size() >= 2 and not _cv_on_tile:
			var _cgd: Vector2 = Vector2(mox, moy)
			if _cgd.length() < 0.01: _cgd = Vector2(0, 1)
			var _cbp_against: float = -_curve_best_push.normalized().dot(_cgd.normalized())
			if _cbp_against > -0.3:  # Floor V (>0), horizontal V (~0) = valley. Ceiling V (<-0.3) = fall out.
				in_valley = true
				is_grounded = true
				_fb_hit = true
		# Valley speed zeroing and forced valley_jump after sustained in_valley.
		# When in_valley persists for 5+ ticks, trigger valley_jump which suppresses
		# input (line ~176). Without input adding speed, the player settles and wedges.
		if _curve_hit and in_valley:
			_valley_ticks += 1
			if absf(_speedX) < 0.5 and absf(_speedY) < 0.5:
				_speedX = 0
			if _valley_ticks >= 15 and not valley_jump:
				valley_jump = true
				_valley_center = Vector2(x, y)
				_pos_history = [x, x, x, x]
		elif _curve_hit:
			_valley_ticks = 0
		# Track curve push normal for next-tick junction detection
		if _curve_hit and _curve_best_push.length() > 0.01:
			_prev_poly_normal = _curve_best_push.normalized()
		elif not _fb_hit:
			_prev_poly_normal = Vector2.ZERO

	# (Section 7.66 removed: flat bisector plane constraint replaced by adaptive
	# bisector in section 7.65. The flat plane couldn't follow curved arms —
	# players slid past it by holding a key along one arm. The adaptive bisector
	# computes escape direction from actual arm normals at each position.)

	# When wedged, undo any push-out drift and re-lock to the wedge position.
	# Both free block and curve push-outs can move the player while wedged
	# (overlap detection still fires at zero speed), causing visual jitter.
	if is_wedged:
		x = _wedge_safe_pos.x
		y = _wedge_safe_pos.y
		_speedX = 0
		_speedY = 0

	# Wedge at V junction: in_valley (2+ curve rotations) with low speed = settled.
	# Skip wedging if gravity would pull player out (ceiling V / X-crossing):
	# test by temporarily adding gravity and checking if push-out still holds.
	if not is_wedged and not valley_jump and _wedge_escape_cooldown == 0 and in_valley:
		var _total_spd: float = absf(_speedX) + absf(_speedY)
		if _total_spd < 1.5:
			# Would gravity pull us out? Check if a position slightly toward gravity
			# is still within curve collision range (both arms still push).
			var _grav_test: Vector2 = Vector2(mox, moy).normalized() if Vector2(mox, moy).length() > 0.01 else Vector2(0, 1)
			var _test_pushes: Array = WorldManager.get_curve_push_data(x + 8.0 + _grav_test.x * 4.0, y + 8.0 + _grav_test.y * 4.0)
			var _test_rots: Dictionary = {}
			for _tp in _test_pushes:
				var _ta: float = rad_to_deg(atan2(_tp.normal.y, _tp.normal.x))
				var _trk: int = (int(round(_ta / 40.0)) * 40) % 180
				if _trk < 0: _trk += 180
				_test_rots[_trk] = true
			if _test_rots.size() >= 2:
				# Both arms still push 4px toward gravity = real V, wedge it
				is_wedged = true
				valley_jump = false
				_valley_center = Vector2(-1, -1)
				_near_pinch_ticks = 0
				_speedX = 0
				_speedY = 0
				is_grounded = true
				_wedge_safe_pos = Vector2(x, y)
			# else: gravity would pull us out of the V — don't wedge, let player fall

	# Fast V-shape detection: push normal X flips + low speed = settling into valley
	# Only for FLOOR V's (normal points against gravity), not ceiling V's
	var _is_floor_v: bool = false
	if on_rotated_block and _surface_normal.length() > 0.1:
		var _gd: Vector2 = Vector2(mox, moy)
		if _gd.length() < 0.01: _gd = Vector2(0, 1)
		_is_floor_v = -_surface_normal.dot(_gd.normalized()) > 0.2
	if on_rotated_block and not valley_jump and _prev_push_normal.length() > 0.1 and _is_floor_v and _fb_hit and in_valley:
		if _prev_push_normal.x * _surface_normal.x < -0.1 and absf(_surface_normal.x) > 0.3 and absf(_speedX) < 0.5:
			in_valley = true
			valley_jump = true
			is_grounded = true
			_speedX = 0
			_speedY = 0
			_valley_center = Vector2((x + _pos_history[-1]) / 2.0 if _pos_history.size() > 0 else x, y)
			x = _valley_center.x
			_pos_history = [_valley_center.x, _valley_center.x, _valley_center.x, _valley_center.x]
	_prev_push_normal = _surface_normal if (on_rotated_block and _fb_hit) else Vector2.ZERO

	# Valley: snap back to locked center AFTER collision resolves
	# Only lock when player has fallen back to valley floor (y >= center)
	if valley_jump and _valley_center.x >= 0 and _jump_cooldown == 0 and y >= _valley_center.y - 2.0:
		x = _valley_center.x
		y = _valley_center.y
		_speedX = 0
		_speedY = 0
		in_valley = true
		is_grounded = true
		on_rotated_block = true
		_fb_hit = true  # Force fb_hit so stuck_ticks doesn't clear valley
		_surface_normal = Vector2(0, -1)

	# Position oscillation detection for V-shapes
	_pos_history.append(x)
	if _pos_history.size() > 4:
		_pos_history.pop_front()
	if _pos_history.size() == 4 and on_rotated_block and _is_floor_v and _fb_hit and in_valley:
		# Check A-B-A-B pattern (position alternating) — only at actual V-junctions (2+ rotation bins)
		var d01: float = absf(_pos_history[0] - _pos_history[1])
		var d02: float = absf(_pos_history[0] - _pos_history[2])
		var d13: float = absf(_pos_history[1] - _pos_history[3])
		if d01 > 0.5 and d02 < 0.05 and d13 < 0.05:
			in_valley = true
			valley_jump = true
			is_grounded = true
			_speedX = 0
			_speedY = 0
			# Lock position at center of oscillation
			_valley_center = Vector2((_pos_history[0] + _pos_history[1]) / 2.0, y)
			x = _valley_center.x
			_pos_history = [_valley_center.x, _valley_center.x, _valley_center.x, _valley_center.x]
	elif valley_jump:
		# Stay locked as long as valley_jump is set
		_speedX = 0
		# Only grounded when at valley floor, not mid-air
		if _valley_center.y >= 0 and y >= _valley_center.y - 2.0:
			is_grounded = true
			in_valley = true
	# Clear valley_jump when far from valley center (landed elsewhere)
	if valley_jump and _valley_center.x >= 0:
		var dist_from_v: float = Vector2(x - _valley_center.x, y - _valley_center.y).length()
		if dist_from_v > 48.0 and _fb_hit and _jump_cooldown == 0:
			valley_jump = false
			_valley_center = Vector2(-1, -1)
			_pos_history.clear()
			_prev_push_normal = Vector2.ZERO
	# Clear valley_jump when no block overlap near valley floor
	if not _fb_hit and y >= _valley_center.y - 2.0 and _jump_cooldown == 0:
		_stuck_ticks += 1
		if _stuck_ticks > 10:
			_pos_history.clear()
			valley_jump = false
			_valley_center = Vector2(-1, -1)
	else:
		_stuck_ticks = 0

	# Coyote time: count down when not grounded on rotated block
	if on_rotated_block and is_grounded:
		_coyote_ticks = 4
	elif _coyote_ticks > 0:
		_coyote_ticks -= 1
		# Allow grounded state for a few ticks after leaving rotated block surface
		if _jump_cooldown == 0:
			is_grounded = true


	# 7.9 Gap-assist: when holding into axis-aligned wall with gaps, nudge Y to slip in
	if not is_god_mode and absf(_last_input_h) > 0.01 and absf(x - _pre_step_x) < 1.5:
		var _gn_dir: float = sign(_last_input_h)
		var _gn_test_x: float = x + _gn_dir * 4.0
		var _gn_blocked: bool = _collides_px(_gn_test_x, y) or _collides_free_blocks_axis(_gn_test_x, y)
		if _gn_blocked:
			# Find exact gap between axis-aligned free blocks (requires 2+ blocks with a gap)
			var _gn_gap_y: float = _find_gap_y_between_free_blocks(x, y, _gn_dir)
			if _gn_gap_y >= 0 and absf(y - _gn_gap_y) < 12.0:
				if not _collides_px(x, _gn_gap_y) and not _collides_free_blocks(x, _gn_gap_y, 0.5) \
					and not _collides_px(_gn_test_x, _gn_gap_y) and not _collides_free_blocks(_gn_test_x, _gn_gap_y, 0.5):
					y = _gn_gap_y
					_speedY = 0
					_speedX = _gn_dir * 1.0

	# 8. Grounded - ONLY when falling or stationary, never during upward jump
	if not is_grounded and _pre_tick_grav_speed >= 0:
		is_grounded = _check_grounded()
		if is_grounded:
			_surface_normal = Vector2(0, -1)  # Flat ground = straight up jump

	_was_on_rotated = on_rotated_block

	# 9. Jump — if wedged OR stuck between curves, allow straight up jump
	if is_wedged and space_just:
		is_grounded = true
		_surface_normal = Vector2(0, -1)
		jumpCount = 0
	elif on_rotated_block and not is_grounded and space_just:
		is_grounded = true
		_surface_normal = Vector2(0, -1)
		jumpCount = 0
	_handle_jump(space_just, space_held)

	# 10. (Curve collision is now in section 7.65 — iterative push-out + tangent projection)

	debug_text = "pos=(%.1f,%.1f) spd=(%.2f,%.2f) grnd=%s val=%s vj=%s w=%s pt=%d" % [x, y, _speedX, _speedY, is_grounded, in_valley, valley_jump, is_wedged, _near_pinch_ticks]

func _arrow_dir_to_vec(dir: int) -> Vector2:
	match dir:
		0: return Vector2(0, _gravity)
		1: return Vector2(-_gravity, 0)
		2: return Vector2(0, -_gravity)
		3: return Vector2(_gravity, 0)
	return Vector2(0, _gravity)

func _compute_gravity() -> void:
	if on_dot:
		morx = 0.0; mory = 0.0; mox = 0.0; moy = 0.0
		return

	# CURRENT action → morx/mory (used for jump direction)
	var cur_vec: Vector2 = Vector2(0, _gravity)  # Default down
	if GameState.is_arrow(_current_action_id):
		var cdir: int = GameState.get_arrow_gravity(_current_action_id)
		if cdir >= 0:
			cur_vec = _arrow_dir_to_vec(cdir)
			if _current_action_rot != 0:
				cur_vec = cur_vec.rotated(deg_to_rad(_current_action_rot))
	morx = cur_vec.x
	mory = cur_vec.y

	# DELAYED action → mox/moy (actual acceleration applied to speed)
	var del_vec: Vector2 = Vector2(0, _gravity)  # Default down
	if GameState.is_arrow(_delayed_action_id):
		var ddir: int = GameState.get_arrow_gravity(_delayed_action_id)
		if ddir >= 0:
			del_vec = _arrow_dir_to_vec(ddir)
			if _delayed_action_rot != 0:
				del_vec = del_vec.rotated(deg_to_rad(_delayed_action_rot))
	mox = del_vec.x
	moy = del_vec.y

	# Gravity zone override: works like arrows pointing toward center
	var gz_result: Dictionary = WorldManager.gravity_zones.get_gravity_at(x + 8.0, y + 8.0)
	if gz_result.in_zone:
		morx = gz_result.direction.x
		mory = gz_result.direction.y
		mox = gz_result.direction.x
		moy = gz_result.direction.y
		# Set active_arrow_dir so diagonal input + jump logic works like arrow fields
		_active_arrow_dir = 4  # Special value = gravity zone (not 0-3 cardinal)

func _handle_jump(space_just: bool, space_held: bool) -> void:
	var do_jump: bool = false
	var mod: int = 1

	if space_just:
		lastJumpMs = -_now_ms
		do_jump = true
		mod = -1
	elif space_held:
		# Hold-repeat: jump immediately when grounded, delayed in air
		if is_grounded:
			do_jump = true
			mod = 1
		elif lastJumpMs < 0:
			if _now_ms + lastJumpMs > 750:
				do_jump = true
				mod = 1
		else:
			if _now_ms - lastJumpMs > 150:
				do_jump = true
				mod = 1

	if not do_jump:
		return
	# performJump (EE exact)
	# Polyline grounding removed — curves use free blocks now
	if is_grounded:
		jumpCount = 0
	if jumpCount == 0 and not is_grounded:
		jumpCount = 1

	var did_jump: bool = false

	if in_valley or valley_jump:
		# Valley: allow jump only when grounded at valley floor
		if is_grounded:
			jumpCount = 0
		if jumpCount < maxJumps:
			if maxJumps < 1000: jumpCount += 1
			var jump_mag: float = _gravity * _jump_height * _get_jump_mult() * 0.995 * TICK_SCALE / MULT
			_speedY = -jump_mag
			_jump_cooldown = 5
			# Don't clear center - resume lock on landing
			did_jump = true
	elif _active_arrow_dir >= 0:
		# Arrow field: jump opposite to gravity, PRESERVE tangent speed
		var grav_vec: Vector2 = Vector2(morx, mory)
		var grav_len: float = grav_vec.length()
		if jumpCount < maxJumps and grav_len > 0.01:
			if maxJumps < 1000: jumpCount += 1
			var grav_dir: Vector2 = grav_vec / grav_len
			var jump_mag: float = _gravity * _jump_height * _get_jump_mult() * 0.995 * TICK_SCALE / MULT
			var tangent_dir: Vector2 = Vector2(-grav_dir.y, grav_dir.x)
			var cur_spd: Vector2 = Vector2(_speedX, _speedY)
			var tangent_spd: float = cur_spd.dot(tangent_dir)
			_speedX = tangent_dir.x * tangent_spd + (-grav_dir.x * jump_mag)
			_speedY = tangent_dir.y * tangent_spd + (-grav_dir.y * jump_mag)
			_jump_cooldown = 5
			_jumped_in_arrow = true
			did_jump = true
	else:
		# Normal gravity: EE-exact separate axis jumps
		# X axis jump (horizontal gravity - shouldn't fire in normal mode)
		if jumpCount < maxJumps and morx != 0:
			if maxJumps < 1000: jumpCount += 1
			var v: float = -morx * _jump_height * _get_jump_mult() * 0.995
			_speedX = v * TICK_SCALE / MULT
			_jump_cooldown = 5
			did_jump = true

		# Y axis jump - preserve horizontal speed
		if jumpCount < maxJumps and mory != 0:
			if maxJumps < 1000: jumpCount += 1
			var jump_speed: float = absf(mory) * _jump_height * _get_jump_mult() * 0.995 * TICK_SCALE / MULT
			_speedY = -sign(mory) * jump_speed
			# Slope boost — capped so steep/vertical surfaces don't launch sideways
			var slope_boost: float = clampf(_surface_normal.x, -0.5, 0.5) * jump_speed
			if slope_boost != 0:
				if _speedX == 0 or sign(slope_boost) == sign(_speedX):
					_speedX += slope_boost
			_surface_normal = Vector2(0, -1)
			_jump_cooldown = 5
			did_jump = true

	if did_jump:
		_stick_curve = -1
		on_rotated_block = false
		if mod < 0:
			lastJumpMs = -_now_ms
		else:
			lastJumpMs = _now_ms

func _dist_to_seg(cx: float, cy: float, sa: Vector2, sb: Vector2) -> float:
	var ab: Vector2 = sb - sa
	var ap: Vector2 = Vector2(cx, cy) - sa
	var ab_dot: float = ab.dot(ab)
	var t: float = clampf(ap.dot(ab) / maxf(ab_dot, 0.001), 0.0, 1.0)
	var on_pt: Vector2 = sa + ab * t
	return Vector2(cx, cy).distance_to(on_pt)

# ── Swept AABB curve collision functions ──────────────────────────────────────

func _swept_aabb_vs_line_seg(center: Vector2, half_size: Vector2, delta: Vector2, seg_a: Vector2, seg_b: Vector2, outward_normal: Vector2) -> Dictionary:
	## Swept AABB vs line segment with correct support point and sign conventions.
	var no_hit: Dictionary = {"hit": false, "t": 1.0, "normal": Vector2.ZERO, "start_pen": false, "pen": 0.0}
	var seg: Vector2 = seg_b - seg_a
	var seg_len: float = seg.length()
	if seg_len <= 0.00001:
		return no_hit
	var tangent: Vector2 = seg / seg_len
	var n: Vector2 = outward_normal.normalized()
	# Support point: AABB corner farthest opposite the face normal (touches first)
	var support_offset: Vector2 = Vector2.ZERO
	if n.x > 0.0:
		support_offset.x = -half_size.x
	elif n.x < 0.0:
		support_offset.x = half_size.x
	if n.y > 0.0:
		support_offset.y = -half_size.y
	elif n.y < 0.0:
		support_offset.y = half_size.y
	var support0: Vector2 = center + support_offset
	# Signed face distance: >0 separated, =0 touching, <0 penetrating
	var dist: float = n.dot(support0 - seg_a)
	# Motion relative to face: <0 moving into face, >0 moving away
	var approach: float = n.dot(delta)
	var touch_eps: float = 0.01
	var pen_eps: float = 2.0  # Only depenetrate when >2px past (not surface riding drift)
	# Deep penetration: push back out
	if dist < -pen_eps:
		return {"hit": true, "t": 0.0, "normal": n, "start_pen": true, "pen": -dist}
	# Small penetration (surface riding drift): ignore
	if dist < -touch_eps and dist >= -pen_eps:
		return no_hit
	var t_hit: float = 0.0
	if dist <= touch_eps:
		if approach >= -touch_eps:
			return no_hit
		t_hit = 0.0
	else:
		if approach >= -touch_eps:
			return no_hit
		t_hit = dist / -approach
		if t_hit < 0.0 or t_hit > 1.0:
			return no_hit
	# Finite-segment check: project box center onto tangent at hit time
	var center_at_hit: Vector2 = center + delta * t_hit
	var center_u: float = tangent.dot(center_at_hit - seg_a)
	var box_tangent_radius: float = absf(tangent.x) * half_size.x + absf(tangent.y) * half_size.y
	if center_u + box_tangent_radius < -touch_eps:
		return no_hit
	if center_u - box_tangent_radius > seg_len + touch_eps:
		return no_hit
	return {"hit": true, "t": maxf(t_hit, 0.0), "normal": n, "start_pen": false, "pen": 0.0}

func _swept_aabb_vs_quad(center: Vector2, half_size: Vector2, delta: Vector2, quad_verts: Array, edge_normals: Array, external: Array) -> Dictionary:
	## Swept AABB vs convex quad using Separating Axis Theorem (SAT).
	## Tests AABB axes (right, up) + external quad edge normals.
	## Returns {hit: bool, t: float, normal: Vector2}
	var result: Dictionary = {"hit": false, "t": 1.0, "normal": Vector2.ZERO}
	# Collect separation axes: AABB axes + external quad edge normals
	var axes: Array = [Vector2(1, 0), Vector2(0, 1)]
	for ei in range(4):
		if external[ei]:
			var n: Vector2 = edge_normals[ei]
			# Skip degenerate normals
			if n.length_squared() < 0.0001:
				continue
			# Don't duplicate axes too close to existing ones
			var dup: bool = false
			for existing in axes:
				if absf(n.dot(existing)) > 0.999:
					dup = true
					break
			if not dup:
				axes.append(n)
	# Swept SAT: find the latest entry and earliest exit across all axes
	var t_enter: float = -99999.0
	var t_exit: float = 99999.0
	var best_axis: Vector2 = Vector2.ZERO
	for axis in axes:
		# Project AABB onto axis
		var aabb_half_proj: float = absf(axis.x) * half_size.x + absf(axis.y) * half_size.y
		var aabb_center_proj: float = center.dot(axis)
		# Project quad onto axis
		var q_min: float = 99999.0
		var q_max: float = -99999.0
		for vi in range(4):
			var p: float = quad_verts[vi].dot(axis)
			if p < q_min:
				q_min = p
			if p > q_max:
				q_max = p
		# AABB interval: [aabb_center_proj - aabb_half_proj, aabb_center_proj + aabb_half_proj]
		# Quad interval: [q_min, q_max]
		var a_min: float = aabb_center_proj - aabb_half_proj
		var a_max: float = aabb_center_proj + aabb_half_proj
		# Sweep: project delta onto axis
		var vel_proj: float = delta.dot(axis)
		if absf(vel_proj) < 0.00001:
			# Static on this axis: check overlap
			if a_max < q_min or a_min > q_max:
				return result  # No overlap, no hit possible
			# Overlapping on this axis, doesn't constrain t
		else:
			# Moving: find entry and exit times
			var inv_vel: float = 1.0 / vel_proj
			var t0: float = (q_min - a_max) * inv_vel
			var t1: float = (q_max - a_min) * inv_vel
			var axis_sign: float = 1.0
			if t0 > t1:
				var tmp: float = t0
				t0 = t1
				t1 = tmp
				axis_sign = -1.0
			if t0 > t_enter:
				t_enter = t0
				best_axis = axis * (-axis_sign if vel_proj > 0 else axis_sign)
			if t1 < t_exit:
				t_exit = t1
	# Check if there is a valid intersection
	if t_enter > t_exit or t_enter >= 1.0 or t_exit <= 0.0:
		return result
	if t_enter < 0.0:
		return result  # Already overlapping — don't treat as hit, let clip resolve
	# Ensure the hit normal points away from the movement direction
	if best_axis.dot(delta) > 0:
		best_axis = -best_axis
	result.hit = true
	result.t = t_enter
	result.normal = best_axis.normalized() if best_axis.length() > 0.001 else Vector2(0, -1)
	return result

func _find_curve_hits(pos: Vector2, delta: Vector2) -> Array:
	## Query spatial hash for render edge segments, sweep test each, return sorted hits.
	var hits: Array = []
	var half_size: Vector2 = Vector2(8.0, 8.0)
	var center: Vector2 = pos + half_size  # Player center
	var cs: int = WorldManager._curve_collider_cell
	var hash_data: Dictionary = WorldManager._curve_collider_hash
	if hash_data.is_empty():
		return hits
	# Compute swept AABB bounds for spatial hash query
	var sweep_min: Vector2 = Vector2(minf(center.x, center.x + delta.x) - half_size.x - 2, minf(center.y, center.y + delta.y) - half_size.y - 2)
	var sweep_max: Vector2 = Vector2(maxf(center.x, center.x + delta.x) + half_size.x + 2, maxf(center.y, center.y + delta.y) + half_size.y + 2)
	var gx0: int = int(floor(sweep_min.x / cs))
	var gy0: int = int(floor(sweep_min.y / cs))
	var gx1: int = int(floor(sweep_max.x / cs))
	var gy1: int = int(floor(sweep_max.y / cs))
	var checked: Dictionary = {}
	for gx in range(gx0, gx1 + 1):
		for gy in range(gy0, gy1 + 1):
			var key: int = gx * 100000 + gy
			if not hash_data.has(key):
				continue
			for seg in hash_data[key]:
				var seg_id: int = int(seg.a.x * 10000 + seg.a.y * 100 + seg.b.x * 10 + seg.b.y)
				if checked.has(seg_id):
					continue
				checked[seg_id] = true
				# Quick distance check: skip segments whose midpoint is far from swept path
				var seg_mid: Vector2 = (seg.a + seg.b) * 0.5
				var sweep_center: Vector2 = center + delta * 0.5
				if seg_mid.distance_to(sweep_center) > 60.0:
					continue
				var r: Dictionary = _swept_aabb_vs_line_seg(center, half_size, delta, seg.a, seg.b, seg.normal)
				if r.hit:
					hits.append({"t": r.t, "normal": r.normal, "seg": seg})
	hits.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return a.t < b.t)
	return hits

func _clip_velocity_vec(vel: Vector2, contact_normals: Array) -> Vector2:
	## Remove velocity components going into contact normals. Two passes for stability.
	var clipped: Vector2 = vel
	for _pass in range(2):
		for n in contact_normals:
			var into: float = clipped.dot(n)
			if into < 0:
				clipped -= n * into
	return clipped

func _has_similar_normal(normals: Array, n: Vector2) -> bool:
	## Check if any existing normal is very similar to n (dot > 0.95)
	for existing in normals:
		if existing.dot(n) > 0.95:
			return true
	return false

func _step_position() -> void:
	var currentSX: float = _speedX
	var currentSY: float = _speedY
	var rx: float = fmod(x, 1.0)
	if rx < 0: rx += 1.0
	var ry: float = fmod(y, 1.0)
	if ry < 0: ry += 1.0
	var donex: bool = false
	var doney: bool = false
	var ox: float; var oy: float; var osx: float; var osy: float


	var guard: int = 0
	while ((currentSX != 0 and not donex) or (currentSY != 0 and not doney)) and guard < 64:
		guard += 1
		ox = x; oy = y; osx = currentSX; osy = currentSY

		# Step X
		if currentSX != 0 and not donex:
			if currentSX > 0:
				if currentSX + rx >= 1:
					x += (1.0 - rx); x = floor(x); currentSX -= (1.0 - rx); rx = 0
				else:
					x += currentSX; currentSX = 0
			elif currentSX < 0:
				if rx + currentSX < 0 and rx != 0:
					currentSX += rx; x -= rx; x = floor(x); rx = 1
				else:
					x += currentSX; currentSX = 0
			rx = fmod(x, 1.0)
			if rx < 0: rx += 1.0
			if _collides_px(x, y):
				x = ox; _speedX = 0; currentSX = osx; donex = true

		# Step Y
		if currentSY != 0 and not doney:
			if currentSY > 0:
				if currentSY + ry >= 1:
					y += (1.0 - ry); y = floor(y); currentSY -= (1.0 - ry); ry = 0
				else:
					y += currentSY; currentSY = 0
			elif currentSY < 0:
				if ry + currentSY < 0 and ry != 0:
					y -= ry; y = floor(y); currentSY += ry; ry = 1
				else:
					y += currentSY; currentSY = 0
			ry = fmod(y, 1.0)
			if ry < 0: ry += 1.0
			if _collides_px(x, y):
				y = oy; _speedY = 0; currentSY = osy; doney = true



func _collides_curve_blocks(px: float, py: float) -> bool:
	if is_god_mode:
		return false
	var cx: float = px + 8.0
	var cy: float = py + 8.0
	for fb in WorldManager.free_blocks:
		if not fb.get("curve_collision", false):
			continue
		if not GameState.is_solid(fb.id):
			continue
		var bcx: float = fb.pos.x + 8.0
		var bcy: float = fb.pos.y + 8.0
		var dx2: float = cx - bcx
		var dy2: float = cy - bcy
		# Quick AABB check first
		if absf(dx2) > 20.0 or absf(dy2) > 20.0:
			continue
		var rot: float = deg_to_rad(fb.rotation)
		var cos_r: float = cos(-rot)
		var sin_r: float = sin(-rot)
		var lx: float = dx2 * cos_r - dy2 * sin_r
		var ly: float = dx2 * sin_r + dy2 * cos_r
		if absf(lx) < 16.0 and absf(ly) < 16.0:
			return true
	return false

func _collides_px(px: float, py: float) -> bool:
	if is_god_mode:
		return false
	if not _collides_fn.is_valid():
		return false
	var l: int = int(floor(px)) / 16
	var t: int = int(floor(py)) / 16
	var r: int = int(floor(px + 15)) / 16
	var b: int = int(floor(py + 15)) / 16
	for cy in range(t, b + 1):
		for cx in range(l, r + 1):
			if _collides_fn.call(cx, cy):
				return true
	return false

func _slope_collides(px: float, py: float, tx: int, ty: int, slope_id: int) -> bool:
	var tile_x: float = float(tx * 16)
	var tile_y: float = float(ty * 16)
	var orient: int = 0
	var is_half: bool = slope_id >= 2040
	var half_side: int = 0  # 0=left, 1=right

	if is_half:
		var rel: int = (slope_id - 2040) % 8
		orient = rel / 2
		half_side = rel % 2
	else:
		orient = (slope_id - 2000) % 4

	for check_x in [px, px + 7, px + 15]:
		if check_x < tile_x or check_x >= tile_x + 16:
			continue
		var local_x: float = clampf(check_x - tile_x, 0, 15)
		var surface_y: float = 0.0

		if is_half:
			match orient:
				0:  # / up-right
					if half_side == 0:
						surface_y = tile_y + 15.0 - local_x * 0.5
					else:
						surface_y = tile_y + 7.0 - local_x * 0.5
				1:  # \ up-left
					if half_side == 0:
						surface_y = tile_y + local_x * 0.5
					else:
						surface_y = tile_y + 8.0 + local_x * 0.5
				2:  # / inv
					if half_side == 0:
						surface_y = tile_y + 15.0 - local_x * 0.5
					else:
						surface_y = tile_y + 7.0 - local_x * 0.5
				3:  # \ inv
					if half_side == 0:
						surface_y = tile_y + local_x * 0.5
					else:
						surface_y = tile_y + 8.0 + local_x * 0.5
		else:
			match orient:
				0: surface_y = tile_y + 15.0 - local_x
				1: surface_y = tile_y + local_x
				2: surface_y = tile_y + 15.0 - local_x
				3: surface_y = tile_y + local_x

		match orient:
			0, 1:
				if py + 15.0 > surface_y and py < tile_y + 16:
					return true
			2, 3:
				if py < surface_y and py + 15 >= tile_y:
					return true
	return false

func _is_on_slope(px: float, py: float) -> bool:
	# Check if any tile the player overlaps is a slope
	var l: int = int(floor(px)) / 16
	var t: int = int(floor(py)) / 16
	var r: int = int(floor(px + 15)) / 16
	var b: int = int(floor(py + 15)) / 16
	for cy in range(t, b + 1):
		for cx in range(l, r + 1):
			var bid: int = WorldManager.get_tile(cx, cy)
			if GameState.is_slope(bid):
				return true
	return false

func _get_slope_surface_y(px: float, py: float) -> float:
	# Find the exact Y position to sit on the slope surface
	# Returns -1 if no slope found or can't resolve
	var l: int = int(floor(px)) / 16
	var t: int = int(floor(py)) / 16
	var r: int = int(floor(px + 15)) / 16
	var b: int = int(floor(py + 15)) / 16
	for cy in range(t, b + 1):
		for cx in range(l, r + 1):
			var bid: int = WorldManager.get_tile(cx, cy)
			if not GameState.is_slope(bid):
				continue
			var tile_x: float = float(cx * 16)
			var tile_y: float = float(cy * 16)
			# Use player center X for surface calculation
			var center_x: float = clampf(px + 8, tile_x, tile_x + 15)
			var local_x: float = center_x - tile_x
			var surface: float = 0.0
			var is_half: bool = bid >= 2040
			var orient: int = 0
			var half_side: int = 0
			if is_half:
				var rel: int = (bid - 2040) % 8
				orient = rel / 2
				half_side = rel % 2
				match orient:
					0:
						surface = tile_y + (15.0 - local_x * 0.5) if half_side == 0 else tile_y + (7.0 - local_x * 0.5)
					1:
						surface = tile_y + (local_x * 0.5) if half_side == 0 else tile_y + (8.0 + local_x * 0.5)
					_: return -1.0
			else:
				orient = (bid - 2000) % 4
				match orient:
					0: surface = tile_y + 15.0 - local_x
					1: surface = tile_y + local_x
					_: return -1.0  # Ceiling slopes don't push down
			# Player bottom should sit on surface
			var new_y: float = surface - 15.0
			if new_y < py:  # Only push up, not down
				if not _collides_px(px, new_y):
					return new_y
	return -1.0

func get_slope_slide_force() -> float:
	var l: int = int(floor(x)) / 16
	var t: int = int(floor(y)) / 16
	var r: int = int(floor(x + 15)) / 16
	var b: int = int(floor(y + 15)) / 16
	for cy in range(t, b + 1):
		for cx in range(l, r + 1):
			var bid: int = WorldManager.get_tile(cx, cy)
			if not GameState.is_slope(bid):
				continue
			var is_half: bool = bid >= 2040
			var orient: int = 0
			if is_half:
				orient = ((bid - 2040) % 8) / 2
			else:
				orient = (bid - 2000) % 4
			# Steeper = faster slide, gentler = slower
			var force: float = 0.2 if not is_half else 0.08
			match orient:
				0: return -force  # / slide LEFT
				1: return force   # \ slide RIGHT
			return 0.0
	return 0.0

func _check_grounded() -> bool:
	if on_dot:
		return false
	# Use delayed gravity direction too - prevents false grounding when
	# player bounces out of arrow tile momentarily
	var gdir: int = 0
	if _active_arrow_dir >= 0:
		gdir = _active_arrow_dir
	elif GameState.is_arrow(_delayed_action_id):
		var _dd: int = GameState.get_arrow_gravity(_delayed_action_id)
		if _dd >= 0:
			gdir = _dd
	match gdir:
		0: return _collides_px(x, y + 1)       # Down: solid 1px below
		1: return _collides_px(x - 1, y)       # Left: solid 1px to the left
		2: return _collides_px(x, y - 1)       # Up: solid 1px above
		3: return _collides_px(x + 1, y)       # Right: solid 1px to the right
	return false

func get_overlapping_tiles() -> Array[Vector2i]:
	var result: Array[Vector2i] = []
	var l: int = int(floor(x)) / 16
	var t: int = int(floor(y)) / 16
	var r: int = int(floor(x + 15)) / 16
	var b: int = int(floor(y + 15)) / 16
	for cy in range(t, b + 1):
		for cx in range(l, r + 1):
			result.append(Vector2i(cx, cy))
	return result

func set_gravity(direction: int) -> void:
	flipGravity = clampi(direction, 0, 3)

func apply_action_tile(block_id: int, rotation_deg: int = 0) -> void:
	## Called before each tick with center tile block_id.
	## Uses EE's 2-element delayed action queue for smooth transitions.

	on_dot = false
	slow_dot = false
	_active_arrow_dir = -1

	# Update the action queue (EE exact: 2-element shift queue)
	var idc: int = block_id if block_id > 0 else 0
	var is_dot_id: bool = (idc == 4 or idc == 414)

	if is_dot_id:
		_delayed_action_id = _action_queue[1]
		_delayed_action_rot = _action_queue_rot[1]
		_action_queue = [idc, idc]
		_action_queue_rot = [rotation_deg, rotation_deg]
		_current_action_id = idc
		_current_action_rot = rotation_deg
	else:
		_delayed_action_id = _action_queue[0]
		_delayed_action_rot = _action_queue_rot[0]
		_action_queue = [_action_queue[1], idc]
		_action_queue_rot = [_action_queue_rot[1], rotation_deg]
		_current_action_id = idc
		_current_action_rot = rotation_deg

	# Set arrow direction: compute rotated gravity vector, store nearest cardinal
	if GameState.is_arrow(_current_action_id):
		var base_dir: int = GameState.get_arrow_gravity(_current_action_id)
		if base_dir >= 0:
			var gvec: Vector2 = _arrow_dir_to_vec(base_dir)
			if rotation_deg != 0:
				gvec = gvec.rotated(deg_to_rad(rotation_deg))
			# Nearest cardinal direction for grounded check
			if absf(gvec.y) >= absf(gvec.x):
				_active_arrow_dir = 0 if gvec.y > 0 else 2
			else:
				_active_arrow_dir = 3 if gvec.x > 0 else 1

	# Dot state
	if GameState.is_dot(_current_action_id):
		on_dot = true
		var dot_type: int = GameState.get_dot_type(_current_action_id)
		if dot_type == 1:
			slow_dot = true

	# Boost blocks: set speed directly (scaled for tick rate)
	if GameState.is_boost(_current_action_id):
		var boost: Vector2 = GameState.get_boost_vector(_current_action_id)
		if boost.x != 0:
			_speedX = boost.x * TICK_SCALE
		if boost.y != 0:
			_speedY = boost.y * TICK_SCALE

func _collides_free_blocks(px: float, py: float, shrink: float = 0.0) -> bool:
	# Check player AABB against rotated free blocks using SAT-lite
	# shrink: reduce collision box by this amount on each side (for gap-assist tolerance)
	var half: float = 16.0 - shrink
	for fb in WorldManager.free_blocks:
		if not GameState.is_solid(fb.id):
			continue
		if fb.get("curve_visual", false):
			continue
		var bpos: Vector2 = fb.pos
		var rot: float = deg_to_rad(fb.rotation)
		var bcenter: Vector2 = bpos + Vector2(8, 8)
		var pcenter: Vector2 = Vector2(px + 8, py + 8)
		var rel: Vector2 = pcenter - bcenter
		var local: Vector2 = rel.rotated(-rot)
		# In local space, block is axis-aligned at (-8,-8) to (8,8)
		# Player is 16x16, check overlap with half-sizes
		if absf(local.x) < half and absf(local.y) < half:
			return true
	return false

func _collides_free_blocks_axis(px: float, py: float) -> bool:
	# Like _collides_free_blocks but ONLY checks axis-aligned blocks (0/90/180/270)
	for fb in WorldManager.free_blocks:
		if not GameState.is_solid(fb.id):
			continue
		if fb.get("curve_visual", false):
			continue
		var rot_deg: float = fmod(absf(fb.rotation), 360.0)
		if rot_deg > 1.0 and absf(rot_deg - 90.0) > 1.0 and absf(rot_deg - 180.0) > 1.0 and absf(rot_deg - 270.0) > 1.0:
			continue
		var bpos: Vector2 = fb.pos
		var rot: float = deg_to_rad(fb.rotation)
		var bcenter: Vector2 = bpos + Vector2(8, 8)
		var pcenter: Vector2 = Vector2(px + 8, py + 8)
		var rel: Vector2 = pcenter - bcenter
		var local: Vector2 = rel.rotated(-rot)
		if absf(local.x) < 16 and absf(local.y) < 16:
			return true
	return false

func _find_gap_y_between_free_blocks(px: float, py: float, dir_x: float) -> float:
	## Find the exact Y position where the player fits between free blocks.
	## Only considers axis-aligned blocks (0/90/180/270 degrees). Returns -1 if no gap found.
	var test_x: float = px + dir_x * 4.0
	var pcx: float = test_x + 8.0
	var pcy: float = py + 8.0
	# Collect all blocking free blocks at the test position
	var block_centers_y: Array = []
	for fb in WorldManager.free_blocks:
		if not GameState.is_solid(fb.id):
			continue
		if fb.get("curve_visual", false):
			continue
		# Only axis-aligned blocks (0, 90, 180, 270)
		var rot_deg: float = fmod(absf(fb.rotation), 360.0)
		if rot_deg > 1.0 and absf(rot_deg - 90.0) > 1.0 and absf(rot_deg - 180.0) > 1.0 and absf(rot_deg - 270.0) > 1.0:
			continue
		var bpos: Vector2 = fb.pos
		var rot: float = deg_to_rad(fb.rotation)
		var bcenter: Vector2 = bpos + Vector2(8, 8)
		var rel: Vector2 = Vector2(pcx, pcy) - bcenter
		var local: Vector2 = rel.rotated(-rot)
		# Check if X overlaps (player would be in this column)
		if absf(local.x) < 16:
			block_centers_y.append(bcenter.y)
	if block_centers_y.size() < 2:
		return -1.0
	# Sort block centers by Y
	block_centers_y.sort()
	# Find gaps between consecutive blocks
	var best_gap_y: float = -1.0
	var best_dist: float = 999.0
	for i in range(block_centers_y.size() - 1):
		var gap_size: float = block_centers_y[i + 1] - block_centers_y[i]
		# Gap must be >= 32 (16px block + 16px gap = 32 between centers)
		if gap_size >= 31.5:
			var gap_center_y: float = (block_centers_y[i] + block_centers_y[i + 1]) / 2.0
			var target_y: float = gap_center_y - 8.0  # Player top-left Y
			var dist: float = absf(py - target_y)
			if dist < best_dist:
				best_dist = dist
				best_gap_y = target_y
	return best_gap_y

func _check_free_block_collision() -> void:
	# Push player out of free blocks (only solid ones)
	for fb in WorldManager.free_blocks:
		if not GameState.is_solid(fb.id):
			continue
		if fb.get("curve_visual", false):
			continue
		var bpos: Vector2 = fb.pos
		var rot: float = deg_to_rad(fb.rotation)
		var bcenter: Vector2 = bpos + Vector2(8, 8)
		var pcenter: Vector2 = Vector2(x + 8, y + 8)
		var rel: Vector2 = pcenter - bcenter
		var local: Vector2 = rel.rotated(-rot)
		# Check overlap (half-sizes: player 8, block 8, total 16)
		if absf(local.x) < 16 and absf(local.y) < 16:
			# Find smallest push-out direction in local space
			var push_x: float = 16 - absf(local.x)
			var push_y: float = 16 - absf(local.y)
			if push_y < push_x:
				# Push vertically
				var push_dir: float = -1.0 if local.y < 0 else 1.0
				var push_local: Vector2 = Vector2(0, push_dir * push_y)
				var push_world: Vector2 = push_local.rotated(rot)
				y += push_world.y
				x += push_world.x
				if absf(push_world.y) > absf(push_world.x):
					_speedY = 0
				else:
					_speedX = 0
			else:
				# Push horizontally
				var push_dir: float = -1.0 if local.x < 0 else 1.0
				var push_local: Vector2 = Vector2(push_dir * push_x, 0)
				var push_world: Vector2 = push_local.rotated(rot)
				y += push_world.y
				x += push_world.x
				if absf(push_world.x) > absf(push_world.y):
					_speedX = 0
				else:
					_speedY = 0

func _check_edge_collision(a: Vector2, b: Vector2) -> void:
	# Same logic as WorldManager.check_line_collision but applied per-edge
	var player_bottom: float = y + 15.0
	var min_x: float = minf(a.x, b.x)
	var max_x: float = maxf(a.x, b.x)
	# Check X overlap
	if x + 15 < min_x or x > max_x:
		return
	# Get edge Y at player center X
	var center_x: float = clampf(x + 8, min_x, max_x)
	var t: float = 0.0
	if absf(b.x - a.x) > 0.01:
		t = (center_x - a.x) / (b.x - a.x)
	var edge_y: float = a.y + (b.y - a.y) * t
	# If player bottom is below edge and player top is above, push up
	if player_bottom > edge_y and y < edge_y:
		y = edge_y - 15.0
		if _speedY > 0:
			_speedY = 0
