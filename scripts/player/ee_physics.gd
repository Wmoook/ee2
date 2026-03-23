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
var on_rotated_block: bool = false
var in_valley: bool = false
var valley_jump: bool = false
var _pos_history: Array = []
var _valley_center: Vector2 = Vector2(-1, -1)  # Locked position in V
var _surface_normal: Vector2 = Vector2(0, -1)
var _prev_push_normal: Vector2 = Vector2.ZERO
var _prev_poly_normal: Vector2 = Vector2.ZERO  # Polyline push from last tick
var _stick_poly_idx: int = -1  # Polyline index player is currently on
var _stick_poly_ticks: int = 0  # Ticks since last contact with stuck poly
var _valley_ticks: int = 0
var _flip_count: int = 0
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
	# Reset grounded each tick - will be recomputed by _check_grounded later
	is_grounded = false

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
	var _pre_step_x: float = x
	var _pre_step_y: float = y
	_step_position()

	# 7.05 Gap-assist: when falling past a 1x1 gap while holding toward it, ALWAYS enter
	# Check ALL tile rows between pre-step and post-step Y (catches high-speed falls)
	# 7.05 Gap-assist: when moving toward a wall, snap into any opening passed through
	if not is_god_mode and absf(_last_input_h) > 0.01 and _collides_fn.is_valid():
		var dir: int = 1 if _last_input_h > 0 else -1
		# Check if wall exists in that direction (within 4px)
		var wall_blocked: bool = _collides_px(x + dir, y) or _collides_px(x + dir * 2, y) or _collides_px(x + dir * 4, y)
		if wall_blocked:
			# Find the wall tile column
			var wall_tx: int
			if dir > 0:
				wall_tx = int(floor((x + 15) / 16.0)) + 1  # Tile to the right of player
			else:
				wall_tx = int(floor(x / 16.0)) - 1  # Tile to the left of player
			# Scan tile rows the player passed through
			var ty_min: int = int(floor(minf(_pre_step_y, y) / 16.0))
			var ty_max: int = int(floor(maxf(_pre_step_y + 15, y + 15) / 16.0))
			for ty in range(ty_min, ty_max + 1):
				# Is this tile in the wall empty? (gap)
				if not _collides_fn.call(wall_tx, ty):
					var snap_y: float = float(ty) * 16.0
					# Would player fit there? (check full collision at snapped position)
					if not _collides_px(x, snap_y):
						y = snap_y
						_speedY = 0
						break

	# 7.15 Polyline collision — also check pre-step position for tunneling
	if not is_god_mode and WorldManager.polylines.size() > 0:
		var _poly_any_hit: bool = false
		var _poly_hit_normal: Vector2 = Vector2.ZERO
		var _poly_hit_tangent: Vector2 = Vector2(1, 0)
		var _poly_hit_against: float = -999.0
		# Decay stick tracking: release after 5 ticks without contact
		_stick_poly_ticks += 1
		if _stick_poly_ticks > 5:
			_stick_poly_idx = -1
		# Pass 1: resolve stick polyline (stay on your curve)
		var poly_result: Dictionary = WorldManager.check_polyline_collision(x, y, 16.0, 16.0, _prev_poly_normal, _stick_poly_idx)
		if poly_result.hit:
			_poly_any_hit = true
			var poly_vel: Vector2 = Vector2(_speedX, _speedY)
			var vel_toward: float = poly_vel.dot(-poly_result.normal)
			var _skip_poly: bool = vel_toward < -3.0 and poly_result.push.length() < 1.0
			if not _skip_poly:
				x += poly_result.push.x
				y += poly_result.push.y
				_stick_poly_idx = poly_result.poly_idx
				_stick_poly_ticks = 0
				var poly_grav_n: Vector2 = Vector2(mox, moy)
				if poly_grav_n.length() < 0.01:
					poly_grav_n = Vector2(0, 1)
				poly_grav_n = poly_grav_n.normalized()
				_poly_hit_against = -poly_result.normal.dot(poly_grav_n)
				_poly_hit_normal = poly_result.normal
				_poly_hit_tangent = poly_result.tangent
			_prev_poly_normal = poly_result.normal
		# Pass 2: resolve OTHER curves (exclude stick poly to find intersecting ones)
		var poly2: Dictionary = WorldManager.check_polyline_collision(x, y, 16.0, 16.0, _prev_poly_normal, -1, _stick_poly_idx)
		if poly2.hit and poly2.push.length() > 0.1:
			if _poly_any_hit and poly2.normal.dot(_poly_hit_normal) < -0.3:
				# Opposing curve at intersection — apply push but re-resolve stick curve
				x += poly2.push.x
				y += poly2.push.y
				# Zero speed into the opposing surface
				var into_wall: float = Vector2(_speedX, _speedY).dot(-poly2.normal)
				if into_wall > 0:
					_speedX += poly2.normal.x * into_wall
					_speedY += poly2.normal.y * into_wall
				# Re-resolve stick curve (pass 3)
				if _stick_poly_idx >= 0:
					var poly3: Dictionary = WorldManager.check_polyline_collision(x, y, 16.0, 16.0, _prev_poly_normal, _stick_poly_idx)
					if poly3.hit and poly3.push.length() > 0.01:
						x += poly3.push.x
						y += poly3.push.y
			else:
				# Same direction or no pass 1 — apply normally
				x += poly2.push.x
				y += poly2.push.y
				if not _poly_any_hit:
					_poly_any_hit = true
					_stick_poly_idx = poly2.poly_idx
					_stick_poly_ticks = 0
					var poly_grav_n2: Vector2 = Vector2(mox, moy)
					if poly_grav_n2.length() < 0.01:
						poly_grav_n2 = Vector2(0, 1)
					poly_grav_n2 = poly_grav_n2.normalized()
					_poly_hit_against = -poly2.normal.dot(poly_grav_n2)
					_poly_hit_normal = poly2.normal
					_poly_hit_tangent = poly2.tangent
					_prev_poly_normal = poly2.normal
		# Apply grounding/speed from the hit surface
		if _poly_any_hit and _poly_hit_against > -0.3:
			on_rotated_block = true
			_surface_normal = _poly_hit_normal
			if _poly_hit_against > 0.2 and _pre_tick_grav_speed >= 0:
				is_grounded = true
				var poly_spd_along: float = Vector2(_speedX, _speedY).dot(_poly_hit_tangent)
				var poly_grav_tang: float = Vector2(mox, moy).dot(_poly_hit_tangent) * _get_grav_mult() / MULT * 0.5
				poly_spd_along += poly_grav_tang
				_speedX = _poly_hit_tangent.x * poly_spd_along
				_speedY = _poly_hit_tangent.y * poly_spd_along


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
	var _on_polyline: bool = on_rotated_block  # Save polyline state before reset
	var _polyline_normal: Vector2 = _surface_normal
	on_rotated_block = false
	in_valley = false
	var on_tile: bool = _check_grounded() and _pre_tick_grav_speed >= 0
	_fb_hit = false
	if not is_god_mode and WorldManager.free_blocks.size() > 0:
		var best_push: Vector2 = Vector2.ZERO
		var best_depth: float = 0.0
		var hit: bool = false
		var _overlap_rots: Dictionary = {}
		# Iterative collision: resolve overlaps multiple passes
		for _pass in range(4):
			var pass_push: Vector2 = Vector2.ZERO
			var pass_depth: float = 0.0
			for fb in WorldManager.free_blocks:
				if not GameState.is_solid(fb.id):
					continue
				if fb.get("curve_visual", false):
					continue  # Curve blocks use line collision instead
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
				# World-axis SAT: trim diamond corners for axis-aligned player
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
					var rk: int = int(round(fb.rotation)) % 180
					_overlap_rots[rk] = true
					if depth > pass_depth:
						pass_depth = depth
						pass_push = Vector2(wx, wy)
						hit = true
						_fb_hit = true
			if pass_depth > 0.01:
				# Apply this pass's push and re-check
				if valley_jump:
					pass_push.x = 0  # Keep V jump vertical
				x += pass_push.x
				y += pass_push.y
				if pass_depth > best_depth:
					best_depth = pass_depth
					best_push = pass_push
				# Stop iterating if overlapping 2+ rotations in ceiling config
				if _overlap_rots.size() >= 2:
					var _gcheck: Vector2 = Vector2(mox, moy)
					if _gcheck.length() < 0.01: _gcheck = Vector2(0, 1)
					if -pass_push.normalized().dot(_gcheck.normalized()) <= 0:
						break  # Ceiling V - stop, let gravity handle it
			else:
				break  # No more overlaps
		# Detect valley: only when actually overlapping 2+ different-rotation blocks
		var _pre_total_spd: float = absf(_pre_tick_speedX) + absf(_pre_tick_speedY)
		# Valley detection: only for floor V's (push against gravity)
		if hit and _overlap_rots.size() >= 2:
			var _gd3: Vector2 = Vector2(mox, moy)
			if _gd3.length() < 0.01: _gd3 = Vector2(0, 1)
			var _bp_against: float = -best_push.normalized().dot(_gd3.normalized())
			if _bp_against > 0.0:  # Push is against gravity = floor V
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
			if not valley_jump:
				# Wall-like: push nearly perpendicular to gravity (< 0.2)
				# Floor/slope: push has gravity component (> 0.2)
				if against_grav2 < 0.2:
					# Wall: just zero the speed component into the wall
					var into_wall: float = Vector2(_speedX, _speedY).dot(n)
					if into_wall < 0:  # Moving into the wall
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
					var _at_junction: bool = prev_n_dot < 0.9  # Surface angle changed
					if spd_mag > 1.0 and new_spd.length() < spd_mag * 0.2 and not _falling_into_v and _at_junction and (_was_on_rotated or _has_horizontal):
						var dir: float = sign(_pre_tick_speedX)
						if dir == 0: dir = 1.0
						_speedX = tangent.x * spd_mag * dir
						_speedY = tangent.y * spd_mag * dir
					else:
						_speedX = new_spd.x
						_speedY = new_spd.y
			# Only mark as "on rotated block" for floor/slope, not walls
			if against_grav2 >= 0.2:
				on_rotated_block = true
				_surface_normal = n
			var grav_dir: Vector2 = Vector2(mox, moy)
			var grav_len2: float = grav_dir.length()
			if grav_len2 > 0.01:
				grav_dir = grav_dir / grav_len2
			else:
				grav_dir = Vector2(0, 1)
			var against_grav: float = -n.dot(grav_dir)
			if against_grav > 0.3 and not on_tile:
				is_grounded = true
				_jump_cooldown = 0  # Clear cooldown on rotated block contact
				_coyote_ticks = 4


	# Restore polyline state if no free block collision occurred
	if not on_rotated_block and _on_polyline and not _fb_hit:
		on_rotated_block = true
		_surface_normal = _polyline_normal

	# Fast V-shape detection: push normal X flips + low speed = settling into valley
	# Only for FLOOR V's (normal points against gravity), not ceiling V's
	var _is_floor_v: bool = false
	if on_rotated_block and _surface_normal.length() > 0.1:
		var _gd: Vector2 = Vector2(mox, moy)
		if _gd.length() < 0.01: _gd = Vector2(0, 1)
		_is_floor_v = -_surface_normal.dot(_gd.normalized()) > 0.2
	if on_rotated_block and not valley_jump and _prev_push_normal.length() > 0.1 and _is_floor_v:
		if _prev_push_normal.x * _surface_normal.x < -0.1 and absf(_surface_normal.x) > 0.3 and absf(_speedX) < 0.5:
			in_valley = true
			valley_jump = true
			is_grounded = true
			_speedX = 0
			_speedY = 0
			_valley_center = Vector2((x + _pos_history[-1]) / 2.0 if _pos_history.size() > 0 else x, y)
			x = _valley_center.x
			_pos_history = [_valley_center.x, _valley_center.x, _valley_center.x, _valley_center.x]
	_prev_push_normal = _surface_normal if on_rotated_block else Vector2.ZERO

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
	if _pos_history.size() == 4 and on_rotated_block and _is_floor_v:
		# Check A-B-A-B pattern (position alternating)
		var d01: float = absf(_pos_history[0] - _pos_history[1])
		var d02: float = absf(_pos_history[0] - _pos_history[2])
		var d13: float = absf(_pos_history[1] - _pos_history[3])
		if d01 > 0.1 and d02 < 0.05 and d13 < 0.05:
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


	# 8. Grounded - ONLY when falling or stationary, never during upward jump
	if not is_grounded and _pre_tick_grav_speed >= 0:
		is_grounded = _check_grounded()
		if is_grounded:
			_surface_normal = Vector2(0, -1)  # Flat ground = straight up jump

	_was_on_rotated = on_rotated_block


	# 9. Jump
	_handle_jump(space_just, space_held)

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
	# Also check polyline grounding for jump (sub-step may not set is_grounded)
	if not is_grounded and WorldManager.polylines.size() > 0:
		var jpc: Dictionary = WorldManager.check_polyline_collision(x, y, 16.0, 16.0, _prev_poly_normal, _stick_poly_idx)
		if jpc.hit:
			var jgn: Vector2 = Vector2(mox, moy)
			if jgn.length() < 0.01: jgn = Vector2(0, 1)
			if -jpc.normal.dot(jgn.normalized()) > 0.2:
				is_grounded = true
	if is_grounded:
		jumpCount = 0
	if jumpCount == 0 and not is_grounded:
		jumpCount = 1

	var did_jump: bool = false

	if in_valley or valley_jump:
		# Valley: always allow jump when at valley floor
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
			# Slope boost
			var slope_boost: float = _surface_normal.x * jump_speed
			if slope_boost != 0:
				if _speedX == 0 or sign(slope_boost) == sign(_speedX):
					_speedX += slope_boost
			_surface_normal = Vector2(0, -1)
			_jump_cooldown = 5
			did_jump = true

	if did_jump:
		if mod < 0:
			lastJumpMs = -_now_ms
		else:
			lastJumpMs = _now_ms

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

func _collides_free_blocks(px: float, py: float) -> bool:
	# Check player AABB against rotated free blocks using SAT-lite
	for fb in WorldManager.free_blocks:
		if not GameState.is_solid(fb.id):
			continue
		if fb.get("curve_visual", false):
			continue
		var bpos: Vector2 = fb.pos
		var rot: float = deg_to_rad(fb.rotation)
		var bcenter: Vector2 = bpos + Vector2(8, 8)
		# Transform player corners into block's local space
		var pcenter: Vector2 = Vector2(px + 8, py + 8)
		var rel: Vector2 = pcenter - bcenter
		var local: Vector2 = rel.rotated(-rot)
		# In local space, block is axis-aligned at (-8,-8) to (8,8)
		# Player is 16x16, check overlap with half-sizes
		if absf(local.x) < 16 and absf(local.y) < 16:
			return true
	return false

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
