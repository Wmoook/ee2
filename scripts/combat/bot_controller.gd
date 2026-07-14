class_name BotController
extends Node2D
## AI smiley: runs the exact same EEPhysics as the player and plays the game —
## navigates, jumps, grabs weapons, leads its shots and dodges. Hard difficulty.

const ANIM_SCALE: float = 16.0 / 40.0

var physics: EEPhysics = EEPhysics.new()
var weapon_system: WeaponSystem = null
var get_player_center: Callable = Callable()
var get_player_vel: Callable = Callable()
var is_player_alive: Callable = Callable()

var dead: bool = false
var _sprite: Sprite2D
var _label: Label
var _tick_accum: float = 0.0
var _prev_tick_pos: Vector2 = Vector2.ZERO
var _curr_tick_pos: Vector2 = Vector2.ZERO
var _last_tick_ms: float = 0.0
var _last_roll_x: float = 0.0

# AI state (recomputed at ~30Hz, consumed every physics tick)
var _ai_timer: float = 0.0
var _in_h: int = 0
var _in_jump_held: bool = false
var _jump_queued: bool = false
var _strafe_dir: int = 1
var _strafe_timer: float = 0.0
var _shoot_timer: float = 0.0
var _shield_want: bool = false
var _backoff_timer: float = 0.0  # Backing up to build a run-up over spikes
var _charge_hold: float = 0.0    # Winding up a charged dash


func _ready() -> void:
	z_index = 4
	physics.set_collides_fn(func(tx: int, ty: int) -> bool: return WorldManager.is_solid_at(tx, ty))
	_sprite = Sprite2D.new()
	var tex: Texture2D = load("res://assets/sprites/NEW_SPRITES_BALL/BALL_1_frame1.png") as Texture2D
	if tex:
		_sprite.texture = tex
		_sprite.scale = Vector2(ANIM_SCALE, ANIM_SCALE)
	_sprite.position = Vector2(8, 8)
	_sprite.modulate = Color(1.0, 0.55, 0.55)  # Crimson tint = enemy
	add_child(_sprite)
	_label = Label.new()
	_label.text = "BOT"
	_label.position = Vector2(-4, -22)
	_label.add_theme_font_size_override("font_size", 10)
	_label.add_theme_color_override("font_color", Color(1.0, 0.45, 0.45))
	_label.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.9))
	_label.add_theme_constant_override("shadow_offset_x", 1)
	_label.add_theme_constant_override("shadow_offset_y", 1)
	add_child(_label)


func spawn_at(tile: Vector2) -> void:
	physics.set_position_tiles(tile.x, tile.y)
	_prev_tick_pos = Vector2(physics.x, physics.y)
	_curr_tick_pos = _prev_tick_pos
	_last_roll_x = physics.x
	position = _prev_tick_pos
	dead = false
	visible = true


func set_dead(v: bool) -> void:
	dead = v
	visible = not v
	physics._speedX = 0.0
	physics._speedY = 0.0


func get_center() -> Vector2:
	return Vector2(physics.x + 8.0, physics.y + 8.0)


func get_vel_pxs() -> Vector2:
	# EE speed units -> px/s (speed * EE_TICK_FRAC px per tick * TPS ticks/s)
	return Vector2(physics._speedX, physics._speedY) * physics.EE_TICK_FRAC * physics.TPS


func apply_knockback(dir: Vector2, power: float) -> void:
	physics._speedX += dir.x * power
	physics._speedY += dir.y * power


func _process(delta: float) -> void:
	if dead:
		return
	# Rescue: if an external push ever leaves us inside a solid tile, pop out
	if physics._collides_px(physics.x, physics.y):
		for off in [Vector2(0, -8), Vector2(0, -16), Vector2(8, 0), Vector2(-8, 0), Vector2(0, 8), Vector2(8, -16), Vector2(-8, -16), Vector2(0, -24)]:
			if not physics._collides_px(physics.x + off.x, physics.y + off.y):
				physics.x += off.x
				physics.y += off.y
				break
	_ai_timer -= delta
	if _ai_timer <= 0.0:
		_ai_timer = 0.033
		_think()
	_shoot_timer -= delta
	# Physics at the same tick rate as the player
	_tick_accum += delta * 1000.0
	var jump_just: bool = _jump_queued
	while _tick_accum >= EEPhysics.MS_PER_TICK:
		_tick_accum -= EEPhysics.MS_PER_TICK
		_prev_tick_pos = _curr_tick_pos
		# Action tiles (arrows/dots/boosts) work for the bot too
		var ctx: int = int(floor((physics.x + 8.0) / 16.0))
		var cty: int = int(floor((physics.y + 8.0) / 16.0))
		physics.apply_action_tile(WorldManager.get_tile(ctx, cty), WorldManager.get_rotation(ctx, cty))
		physics.tick(_in_h, 0, jump_just, _in_jump_held)
		jump_just = false
		_curr_tick_pos = Vector2(physics.x, physics.y)
		_last_tick_ms = Time.get_ticks_msec() - _tick_accum
	_jump_queued = false
	# Interpolated rendering (same as the player)
	if _last_tick_ms > 0.0:
		var alpha: float = clampf((Time.get_ticks_msec() - _last_tick_ms) / EEPhysics.MS_PER_TICK, 0.0, 1.0)
		position = _prev_tick_pos.lerp(_curr_tick_pos, alpha)
	# Gear roll (one rotation per block), honoring the Rotate toggle
	var roll_dx: float = physics.x - _last_roll_x
	_last_roll_x = physics.x
	if absf(roll_dx) > 32.0:
		roll_dx = 0.0
	if _sprite:
		if GameState.rotation_enabled and absf(physics._speedX) + absf(physics._speedY) > 0.3:
			_sprite.rotation = fmod(_sprite.rotation + (roll_dx / 16.0) * TAU, TAU)
		elif not GameState.rotation_enabled and physics.on_rotated_block and physics.is_grounded:
			# Rotate OFF: tilt with the surface instead of rolling
			var n: Vector2 = physics._surface_normal
			_sprite.rotation = lerp_angle(_sprite.rotation, atan2(n.x, -n.y), 1.0 - pow(0.75, delta * 60.0))
		else:
			_sprite.rotation = lerp_angle(_sprite.rotation, 0.0, 1.0 - pow(0.7, delta * 60.0))
		_sprite.flip_h = physics._speedX < -0.3
	# Crimson speed trail via the weapon system's FX pool
	if weapon_system and Vector2(physics._speedX, physics._speedY).length() > 4.0 and randf() < delta * 90.0:
		weapon_system.spawn_trail_dot(get_center() - get_vel_pxs().normalized() * 7.0, -get_vel_pxs() * 0.12, Color(1.0, 0.3, 0.2))
	# Combat: aim + shoot / melee
	if weapon_system and not is_player_alive.is_null() and is_player_alive.call():
		weapon_system.set_shield("bot", _shield_want)
		var aim: Vector2 = _combat_aim()
		if aim != Vector2.ZERO:
			weapon_system.set_aim("bot", aim)
			var wname: String = weapon_system.get_weapon("bot")
			var is_beam: bool = wname != "" and WeaponSystem.WEAPONS[wname].get("beam", false)
			if wname == "":
				# Unarmed melee: quick dash close up, or wind up a CHARGED
				# heavy dash from mid range and release it at the player
				var pdist: float = get_center().distance_to(get_player_center.call())
				if _charge_hold > 0.0:
					weapon_system.charge_dash("bot", delta)
					_charge_hold -= delta
					if _charge_hold <= 0.0 or pdist < 70.0:
						var res: Dictionary = weapon_system.release_dash("bot")
						if res.ok:
							var imp: float = 7.0 + 10.0 * res.power
							physics._speedX += aim.x * imp
							physics._speedY += aim.y * imp
				elif pdist < 130.0 and _has_los(get_player_center.call()) and weapon_system.try_dash("bot"):
					physics._speedX += aim.x * 7.0
					physics._speedY += aim.y * 7.0
				elif pdist > 150.0 and pdist < 340.0 and _has_los(get_player_center.call()) and randf() < delta * 0.5:
					_charge_hold = randf_range(0.9, 2.6)  # Start winding up
			elif (is_beam or _shoot_timer <= 0.0) and _has_los(get_player_center.call()):
				if weapon_system.try_shoot("bot"):
					apply_knockback(-aim, weapon_system.get_kick("bot") * (0.1 if is_beam else 1.0))
					if not is_beam:
						_shoot_timer = randf_range(0.05, 0.22)  # Hard: fast follow-ups


func _combat_aim() -> Vector2:
	## Lead the player based on projectile speed, with a small aim error.
	if get_player_center.is_null():
		return Vector2.ZERO
	var target: Vector2 = get_player_center.call()
	var my_c: Vector2 = get_center()
	var wname: String = weapon_system.get_weapon("bot") if weapon_system else ""
	if wname != "" and not get_player_vel.is_null():
		var proj_speed: float = WeaponSystem.WEAPONS[wname].speed
		var t_flight: float = clampf(my_c.distance_to(target) / proj_speed, 0.0, 0.6)
		target += get_player_vel.call() * t_flight
	var dir: Vector2 = target - my_c
	if dir.length() < 1.0:
		return Vector2.RIGHT
	return dir.normalized().rotated(randfn(0.0, 0.035))  # Hard: tight error


func _has_los(target: Vector2) -> bool:
	var from: Vector2 = get_center()
	var d: float = from.distance_to(target)
	if d > 520.0:
		return false
	var steps: int = maxi(1, int(d / 8.0))
	for i in range(1, steps):
		var p: Vector2 = from.lerp(target, float(i) / float(steps))
		if WorldManager.is_solid_at(int(floor(p.x / 16.0)), int(floor(p.y / 16.0))):
			return false
	return true


func _think() -> void:
	## ~30Hz decisions: pick a goal position, derive movement inputs.
	if get_player_center.is_null():
		return
	# Stunned (parried): drop all inputs until it wears off
	if weapon_system and weapon_system.is_stunned("bot"):
		_in_h = 0
		_in_jump_held = false
		_shield_want = false
		return
	var my_c: Vector2 = get_center()
	var player_c: Vector2 = get_player_center.call()
	var armed: bool = weapon_system != null and weapon_system.get_weapon("bot") != ""
	var goal: Vector2 = player_c
	if weapon_system and not armed:
		# Seek nearest active weapon pad
		var best_d: float = 999999.0
		var found: bool = false
		for pad in weapon_system._pads:
			if pad.respawn_left > 0.0:
				continue
			var pd: float = my_c.distance_to(pad.pos)
			if pd < best_d:
				best_d = pd
				goal = pad.pos
				found = true
		if not found:
			goal = player_c  # Nothing up — chase anyway
	# The DOOM RAY outranks everything — sprint for the super pad
	if weapon_system and weapon_system.is_super_available() and weapon_system.get_weapon("bot") != "doom":
		goal = weapon_system.super_pos
	# High goals (the rail pad / lift entrance): climb via a mid platform first
	if goal.y < my_c.y - 100.0:
		var best_via: Vector2 = Vector2.ZERO
		var best_vd: float = 999999.0
		for v in BattleMap.RAIL_VIA:
			var vd: float = my_c.distance_to(v)
			if vd < best_vd:
				best_vd = vd
				best_via = v
		if best_vd > 24.0 and my_c.y > best_via.y - 8.0:
			goal = best_via  # Not up on the platform yet — climb there first
	else:
		# Engage: keep a mid-range band, strafe inside it
		var dist: float = my_c.distance_to(player_c)
		_strafe_timer -= 0.033
		if _strafe_timer <= 0.0:
			_strafe_timer = randf_range(0.6, 1.3)
			_strafe_dir = 1 if randf() < 0.5 else -1
		if dist > 300.0:
			goal = player_c
		elif dist < 140.0:
			goal = my_c + (my_c - player_c)  # Back off
		else:
			goal = my_c + Vector2(_strafe_dir * 80.0, 0)
	# Black hole MASTERY: never blunder into the pull, escape hard if caught,
	# and route around the hole instead of cutting straight through it.
	# Getting sucked in should only happen when outplayed (knockback etc).
	var escaping: bool = false
	for gz in WorldManager.gravity_zones.zones:
		var to_me: Vector2 = my_c - gz.center
		var d: float = to_me.length()
		if d < gz.radius * 1.15:
			# Inside or skirting the pull: overriding priority — leave radially
			var out_dir: Vector2 = to_me.normalized() if d > 1.0 else Vector2.RIGHT
			goal = gz.center + out_dir * (gz.radius + 80.0)
			escaping = d < gz.radius
		else:
			# If the straight path to the goal passes through the pull,
			# stay on my side of the hole instead of jumping across it
			var seg: Vector2 = goal - my_c
			var t: float = clampf((gz.center - my_c).dot(seg) / maxf(seg.length_squared(), 0.001), 0.0, 1.0)
			if (my_c + seg * t).distance_to(gz.center) < gz.radius + 20.0:
				if my_c.y > gz.center.y:
					goal.y = maxf(goal.y, gz.center.y + gz.radius + 48.0)
				else:
					goal.y = minf(goal.y, gz.center.y - gz.radius - 48.0)
	# Horizontal input with a deadzone (no deadzone while escaping the hole)
	var dx: float = goal.x - my_c.x
	if escaping:
		_in_h = 1 if dx >= 0.0 else -1
	else:
		_in_h = 0 if absf(dx) < 10.0 else (1 if dx > 0.0 else -1)
	# Jumping: blocked ahead, goal above, escape launch, or a dodge hop
	var want_jump: bool = false
	if physics.is_grounded:
		if escaping:
			# Inside a gravity zone, jumps launch AWAY from the center —
			# the fastest way out when touching any surface
			want_jump = true
		if _in_h != 0:
			var ahead_x: int = int(floor((my_c.x + _in_h * 20.0) / 16.0))
			var head_y: int = int(floor(my_c.y / 16.0))
			if WorldManager.is_solid_at(ahead_x, head_y) or WorldManager.is_solid_at(ahead_x, head_y - 1):
				want_jump = true
			# SPIKE INTELLIGENCE: measure the hazard span ahead and only jump
			# if current speed will actually CLEAR the far edge; if too slow,
			# back off and build a run-up instead of hopping short onto them.
			var speed_px: float = absf(physics._speedX) * physics.EE_TICK_FRAC * physics.TPS
			var foot_y: int = int(floor((my_c.y + 6.0) / 16.0))
			var tile_x: int = int(floor(my_c.x / 16.0))
			var first_h: int = 0
			var last_h: int = 0
			var found_h: bool = false
			for look in range(1, 9):
				var tx: int = tile_x + _in_h * look
				var hz: bool = _hazard_col(tx, foot_y)
				if hz and not found_h:
					found_h = true
					first_h = tx
					last_h = tx
				elif hz and found_h:
					last_h = tx
				elif found_h:
					break
			if found_h:
				var near_px: float = first_h * 16.0 + (16.0 if _in_h < 0 else 0.0)
				var far_px: float = last_h * 16.0 + (0.0 if _in_h < 0 else 16.0)
				var dist_to: float = absf(near_px - my_c.x)
				if dist_to < 72.0:
					# TRAJECTORY PRECOGNITION: ghost-simulate the actual jump
					# with the real physics engine (ceilings, curves, arrows,
					# spikes all included). Only jump if the ghost lands alive
					# PAST the hazard; otherwise back off for a run-up.
					var sim: Dictionary = _simulate_jump(_in_h, 220)
					var progressed: bool = (sim.end_x + 8.0 - far_px) * float(_in_h) > 6.0
					if sim.safe and progressed:
						want_jump = true
					else:
						_backoff_timer = 0.35
		if goal.y < my_c.y - 40.0:
			want_jump = true
		if armed and not escaping and randf() < 0.05:
			want_jump = true  # Unpredictable dodge hop
		# Dodge incoming projectiles (hard: reacts most of the time).
		# Unarmed, prefer the PARRY over the dodge — shield up instead.
		if weapon_system and not escaping and randf() < 0.8:
			var incoming: bool = false
			for pr in weapon_system._projectiles:
				if pr.team != 1 and pr.pos.distance_to(my_c) < 130.0 and pr.vel.dot(my_c - pr.pos) > 0.0:
					incoming = true
					break
			if incoming:
				if armed:
					want_jump = true
				else:
					_shield_want = true
	# Drop the shield once nothing threatening is inbound
	if _shield_want and weapon_system:
		var still_threat: bool = false
		for pr in weapon_system._projectiles:
			if pr.team != 1 and pr.pos.distance_to(my_c) < 170.0:
				still_threat = true
				break
		if not still_threat:
			_shield_want = false
	# Airborne spike awareness: if falling toward hazards below (knockback,
	# short hop), air-steer toward the nearest safe column
	if not physics.is_grounded and physics._speedY > 0.0:
		var below_y: int = int(floor((my_c.y + 22.0) / 16.0))
		var col: int = int(floor(my_c.x / 16.0))
		if _hazard_col(col, below_y) or _hazard_col(col, below_y + 1):
			for off in [1, 2, 3]:
				if not _hazard_col(col + off, below_y) and not _hazard_col(col + off, below_y + 1):
					_in_h = 1
					break
				if not _hazard_col(col - off, below_y) and not _hazard_col(col - off, below_y + 1):
					_in_h = -1
					break
	# Run-up backoff: reverse away from the spikes to gather speed
	_backoff_timer = maxf(0.0, _backoff_timer - 0.033)
	if _backoff_timer > 0.0 and physics.is_grounded:
		_in_h = -_in_h
		want_jump = false
	if want_jump:
		_jump_queued = true
		_in_jump_held = true
	else:
		_in_jump_held = goal.y < my_c.y - 60.0  # Hold to climb tall gaps


func _hazard_col(tx: int, foot_y: int) -> bool:
	return GameState.is_hazard(WorldManager.get_tile(tx, foot_y)) \
		or GameState.is_hazard(WorldManager.get_tile(tx, foot_y + 1))


func _simulate_jump(ih: int, max_ticks: int) -> Dictionary:
	## Ghost-run the REAL physics engine forward from the bot's current state:
	## jump on tick 1, hold direction ih, and watch what actually happens —
	## head bonks, curve deflections and arrow fields all included.
	var ghost: EEPhysics = EEPhysics.new()
	ghost.set_collides_fn(func(tx: int, ty: int) -> bool: return WorldManager.is_solid_at(tx, ty))
	ghost.x = physics.x
	ghost.y = physics.y
	ghost._speedX = physics._speedX
	ghost._speedY = physics._speedY
	ghost.is_grounded = true
	ghost.jumpCount = 0
	var space: bool = true
	var died: bool = false
	var landed: bool = false
	for i in range(max_ticks):
		var ctx: int = int(floor((ghost.x + 8.0) / 16.0))
		var cty: int = int(floor((ghost.y + 8.0) / 16.0))
		ghost.apply_action_tile(WorldManager.get_tile(ctx, cty), WorldManager.get_rotation(ctx, cty))
		ghost.tick(ih, 0, space, space)
		space = false
		for ty2 in range(int(floor(ghost.y / 16.0)), int(floor((ghost.y + 15.0) / 16.0)) + 1):
			for tx2 in range(int(floor(ghost.x / 16.0)), int(floor((ghost.x + 15.0) / 16.0)) + 1):
				if GameState.is_hazard(WorldManager.get_tile(tx2, ty2)):
					died = true
		if died:
			break
		if i > 30 and ghost.is_grounded:
			landed = true
			break
	return {"safe": landed and not died, "died": died, "end_x": ghost.x}
