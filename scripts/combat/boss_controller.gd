class_name BossController
extends Node2D
## THE WARDEN — a giant armored eye-core boss. It fights with the arena's
## own rules: slam dashes you can PARRY, deflectable bullet barrages, floor
## shockwaves you jump, and an annihilation beam you can catch in an
## anime-style clash (managed by BossMode). All art is procedural vector
## drawing in world space, animated every frame.

signal boss_died
signal phase_changed(phase: int)

const ST_SPAWN: int = 0
const ST_HOVER: int = 1
const ST_TG_SLAM: int = 2
const ST_SLAM: int = 3
const ST_TG_BURST: int = 4
const ST_TG_POUND: int = 5
const ST_POUND_DROP: int = 6
const ST_TG_BEAM: int = 7
const ST_BEAM: int = 8
const ST_STUNNED: int = 9
const ST_TRANSITION: int = 10
const ST_DYING: int = 11
const ST_DEAD: int = 12

const BODY_R: float = 34.0          # Contact/hit radius
const PUSH_TO_PXS: float = 100.0    # EE speed unit -> px/s (impulse conversion)

var hp: int = 60
var max_hp: int = 60
var phase: int = 1
var state: int = ST_SPAWN
var st_t: float = 2.2               # Time left in the current state
var pos: Vector2 = Vector2(512.0, 240.0)
var vel: Vector2 = Vector2.ZERO

var ws: WeaponSystem = null
var get_player_center: Callable = Callable()
var get_player_vel: Callable = Callable()
var is_player_alive: Callable = Callable()
var hurt_player: Callable = Callable()
var push_player: Callable = Callable()

# Attack state
var slam_dir: Vector2 = Vector2.RIGHT
var slam_hit_done: bool = false
var beam_dir: Vector2 = Vector2.RIGHT
var beam_hit: Vector2 = Vector2.ZERO
var beam_t: float = 0.0
var struggle_freeze: bool = false   # BossMode holds the beam during a clash
var struggle_active: bool = false
var clash_point: Vector2 = Vector2.ZERO
var shocks: Array = []              # {x, dir, hit}
var _burst_extra: int = 0           # Phase-3 follow-up volleys
var _burst_timer: float = 0.0
var _beam_cd: float = 8.0           # First beam comes early — teach the clash
var _attack_idx: int = 0
var _flash: float = 0.0
var _shake: float = 0.0
var _time: float = 0.0
var _orbit: float = 0.0
var _ring_a: float = 0.0
var _ring_b: float = 0.0
var _eye: Vector2 = Vector2.ZERO
var _die_fx_t: float = 0.0
var _beam_sfx_t: float = 0.0
var _jink_t: float = 0.0
var _jink_target: Vector2 = Vector2(512.0, 240.0)
var _impact_cd: Dictionary = {}  # Vector2i tile -> cooldown (one chip per hit, not per frame)

# Flight envelope (set from BossMap by BossMode)
var min_x: float = 64.0
var max_x: float = 960.0
var min_y: float = 96.0
var floor_y: float = 512.0


func _ready() -> void:
	z_index = 3


func phase_color() -> Color:
	if phase == 1:
		return Color(0.45, 0.85, 1.0)
	if phase == 2:
		return Color(1.0, 0.62, 0.2)
	return Color(1.0, 0.28, 0.32)


func get_center() -> Vector2:
	return pos


func get_vel_pxs() -> Vector2:
	return vel


func alive() -> bool:
	return hp > 0 and state != ST_DYING and state != ST_DEAD


func vulnerable() -> bool:
	return alive() and state != ST_SPAWN and state != ST_TRANSITION and not struggle_active


func beam_muzzle() -> Vector2:
	return pos + beam_dir * (BODY_R + 4.0)


func _panic() -> bool:
	## The player is holding the DOOM RAY — the Warden is AFRAID of it.
	return ws != null and ws.get_weapon("player") == "doom"


func apply_push(v: Vector2) -> void:
	# The Warden barely budges — 12% of any knockback gets through
	vel += v * PUSH_TO_PXS * 0.12


func state_name() -> String:
	return ["SPAWN", "HOVER", "TG_SLAM", "SLAM", "TG_BURST", "TG_POUND", "POUND", "TG_BEAM", "BEAM", "STUNNED", "TRANSITION", "DYING", "DEAD"][state]


func take_damage(dmg: int, dir: Vector2 = Vector2.ZERO) -> void:
	if not alive():
		return
	if not vulnerable():
		_flash = maxf(_flash, 0.05)  # Plink — armored feedback
		return
	var mult: int = 2 if state == ST_STUNNED else 1
	_apply_damage(dmg * mult, dir)


func _apply_damage(amount: int, dir: Vector2 = Vector2.ZERO) -> void:
	hp = maxi(0, hp - amount)
	_flash = 0.16
	_shake = maxf(_shake, 2.5)
	if ws:
		ws.spawn_hit(pos - dir * 20.0, phase_color(), dir if dir != Vector2.ZERO else Vector2.UP)
	if hp <= 0:
		state = ST_DYING
		st_t = 1.8
		_die_fx_t = 0.0
		struggle_active = false
		struggle_freeze = false
		if ws:
			ws.play_sfx("explode", pos, 0.05, 0.7)
		return
	if phase == 1 and hp <= (max_hp * 2) / 3:
		_enter_transition(2)
	elif phase == 2 and hp <= max_hp / 3:
		_enter_transition(3)


func _enter_transition(new_phase: int) -> void:
	phase = new_phase
	state = ST_TRANSITION
	st_t = 1.5
	struggle_active = false
	struggle_freeze = false
	shocks.clear()
	if ws:
		ws.play_sfx("doom_spawn", pos, 0.0, 0.6)
		ws.spawn_ring(pos, phase_color(), 10.0, 130.0, 0.5)
		ws.spawn_ring(pos, Color(1, 1, 1), 6.0, 80.0, 0.35)
	# Harmless roar wave — shoves the player back to reset the arena
	if not push_player.is_null() and not get_player_center.is_null():
		var away: Vector2 = (get_player_center.call() - pos).normalized()
		push_player.call(away * 8.0 + Vector2(0.0, -3.0))
	GameState.cam_shake = maxf(GameState.cam_shake, 9.0)
	phase_changed.emit(phase)


func struggle_backfire() -> void:
	## The clash was pushed all the way back — the Warden eats its own beam.
	struggle_active = false
	struggle_freeze = false
	beam_t = 0.0
	_apply_damage(12, -beam_dir)
	if alive():
		state = ST_STUNNED
		st_t = 3.4
	if ws:
		ws.spawn_explosion(pos, Color(1.0, 0.85, 0.4))
		ws.spawn_ring(pos, Color(1, 1, 1), 8.0, 110.0, 0.4)
		ws.play_sfx("explode", pos, 0.05, 0.85)
	GameState.cam_shake = maxf(GameState.cam_shake, 14.0)


func end_beam(soon: float = 0.0) -> void:
	beam_t = minf(beam_t, soon)
	struggle_freeze = false
	struggle_active = false


func _process(delta: float) -> void:
	if state == ST_DEAD:
		return
	_time += delta
	_flash = maxf(0.0, _flash - delta)
	_shake = maxf(0.0, _shake - delta * 6.0)
	_orbit += delta * (1.1 + 0.5 * phase)
	_ring_a += delta * (0.65 + 0.25 * phase)
	_ring_b -= delta * (0.9 + 0.35 * phase)
	var p_alive: bool = not is_player_alive.is_null() and is_player_alive.call()
	var pc: Vector2 = get_player_center.call() if p_alive else Vector2(512.0, 400.0)
	_eye = _eye.lerp((pc - pos).normalized() * 6.5, 1.0 - pow(0.001, delta))
	if state != ST_BEAM and state != ST_TG_BEAM:
		_beam_cd -= delta
	# Ambient embers drifting off the hull (a storm of them while panicking)
	if ws and alive() and randf() < delta * (80.0 if _panic() else 26.0):
		var ea: float = randf() * TAU
		ws.spawn_trail_dot(pos + Vector2.from_angle(ea) * randf_range(30.0, 44.0), Vector2(randf_range(-15, 15), randf_range(-40, -14)), phase_color())

	match state:
		ST_SPAWN:
			st_t -= delta
			vel = Vector2.ZERO
			if ws and randf() < delta * 120.0:
				var sa: float = randf() * TAU
				var sp: Vector2 = pos + Vector2.from_angle(sa) * randf_range(70.0, 160.0)
				ws.spawn_trail_dot(sp, (pos - sp) * 2.2, phase_color())
			if st_t <= 0.0:
				state = ST_HOVER
				st_t = _hover_time()
				if ws:
					ws.play_sfx("doom_spawn", pos, 0.0, 0.8)
					ws.spawn_ring(pos, phase_color(), 10.0, 120.0, 0.45)
				GameState.cam_shake = maxf(GameState.cam_shake, 6.0)
		ST_HOVER:
			var anchor: Vector2 = Vector2(clampf(pc.x, min_x + 190.0, max_x - 190.0), 215.0 + 24.0 * sin(_time * 1.15))
			var vmax: float = 240.0 + 70.0 * phase
			if _panic():
				# The player holds the DOOM RAY: SCATTER! Fast erratic jinks
				# biased away from the player, plus a hard perpendicular juke
				# whenever the live beam ray sweeps close.
				_jink_t -= delta
				if _jink_t <= 0.0:
					_jink_t = randf_range(0.2, 0.45)
					_jink_target = Vector2(randf_range(min_x + 110.0, max_x - 110.0), randf_range(min_y + 50.0, 340.0))
					if absf(_jink_target.x - pc.x) < 240.0:
						var flee: float = signf(pos.x - pc.x)
						if flee == 0.0:
							flee = 1.0
						_jink_target.x = clampf(pc.x + flee * randf_range(300.0, 480.0), min_x + 100.0, max_x - 100.0)
				anchor = _jink_target
				vmax = 430.0 + 60.0 * phase
				var pa2: Dictionary = ws._actors.get("player", {})
				if not pa2.is_empty() and pa2.get("beam_draw", false):
					var bd: Vector2 = pa2.aim
					var along: float = (pos - pc).dot(bd)
					if along > 0.0:
						var offv: Vector2 = pos - (pc + bd * along)
						if offv.length() < 160.0:
							var side: Vector2 = bd.orthogonal()
							if offv.dot(side) < 0.0:
								side = -side
							vel += side * 2400.0 * delta
				vel = vel.lerp((anchor - pos) * 3.0, 1.0 - pow(0.004, delta))
			else:
				vel = vel.lerp((anchor - pos) * 2.1, 1.0 - pow(0.02, delta))
			if vel.length() > vmax:
				vel = vel.normalized() * vmax
			pos += vel * delta
			st_t -= delta
			if st_t <= 0.0 and p_alive:
				if _panic():
					# Never slam or pound INTO the doom — snipe from range
					if _beam_cd <= 0.0:
						state = ST_TG_BEAM
						st_t = 1.15
					else:
						state = ST_TG_BURST
						st_t = 0.45
				else:
					_pick_attack()
			elif st_t <= 0.0:
				st_t = 1.0
		ST_TG_SLAM:
			vel = vel.lerp(Vector2.ZERO, 1.0 - pow(0.01, delta))
			pos += vel * delta
			st_t -= delta
			if st_t <= 0.0:
				var pv: Vector2 = get_player_vel.call() if p_alive else Vector2.ZERO
				slam_dir = ((pc + pv * 0.22) - pos).normalized()
				vel = slam_dir * (700.0 + 130.0 * phase)
				slam_hit_done = false
				state = ST_SLAM
				st_t = 0.62
				if ws:
					ws.play_sfx("shoot_rail", pos, 0.05, 0.6)
		ST_SLAM:
			pos += vel * delta
			st_t -= delta
			_slam_contact(pc, p_alive)
			# Stopped by arena bounds OR by crunching into terrain (tile
			# collision kills the into-surface velocity)
			var stopped: bool = pos.x <= min_x + BODY_R or pos.x >= max_x - BODY_R or pos.y <= min_y + BODY_R or pos.y >= floor_y - BODY_R
			if st_t < 0.55 and vel.length() < 260.0:
				stopped = true
			if stopped or st_t <= 0.0:
				if stopped and ws:
					ws.spawn_hit(pos + slam_dir * BODY_R, phase_color(), -slam_dir)
					ws.play_sfx("bonk", pos, 0.05, 0.6)
					GameState.cam_shake = maxf(GameState.cam_shake, 5.0)
				vel = -slam_dir * 60.0
				state = ST_HOVER
				st_t = _hover_time() * 0.6
		ST_TG_BURST:
			if _panic():
				# Keep fleeing while winding up — never a sitting duck
				vel = vel.lerp((_jink_target - pos) * 2.2, 1.0 - pow(0.01, delta))
				if vel.length() > 380.0:
					vel = vel.normalized() * 380.0
			else:
				vel = vel.lerp(Vector2.ZERO, 1.0 - pow(0.01, delta))
			pos += vel * delta
			st_t -= delta
			if st_t <= 0.0:
				_fire_burst(pc)
				if phase >= 3:
					_burst_extra = 2
					_burst_timer = 0.17
				state = ST_HOVER
				st_t = _hover_time() * 0.55
		ST_TG_POUND:
			vel = vel.lerp(Vector2(0.0, -120.0), 1.0 - pow(0.01, delta))
			pos += vel * delta
			st_t -= delta
			if st_t <= 0.0:
				vel = Vector2(0.0, 940.0)
				state = ST_POUND_DROP
		ST_POUND_DROP:
			pos += vel * delta
			# Lands on the floor OR on terrain (tile collision bleeds the
			# fall speed) — the shockwave runs along whatever it hit
			if pos.y >= floor_y - BODY_R - 2.0 or vel.y < 320.0:
				pos.y = minf(pos.y, floor_y - BODY_R - 2.0)
				var land_y: float = pos.y + BODY_R + 2.0
				shocks.append({"x": pos.x - BODY_R, "dir": -1, "hit": false, "y": land_y})
				shocks.append({"x": pos.x + BODY_R, "dir": 1, "hit": false, "y": land_y})
				if ws:
					ws.spawn_explosion(Vector2(pos.x, land_y - 8.0), phase_color())
					ws.spawn_ring(Vector2(pos.x, land_y - 10.0), phase_color(), 8.0, 70.0, 0.3)
					ws.play_sfx("bonk", pos, 0.05, 0.5)
				GameState.cam_shake = maxf(GameState.cam_shake, 10.0)
				vel = Vector2.ZERO
				state = ST_HOVER
				st_t = _hover_time()
		ST_TG_BEAM:
			if _panic():
				vel = vel.lerp((_jink_target - pos) * 2.2, 1.0 - pow(0.01, delta))
				if vel.length() > 340.0:
					vel = vel.normalized() * 340.0
			else:
				vel = vel.lerp(Vector2.ZERO, 1.0 - pow(0.01, delta))
			pos += vel * delta
			beam_dir = (pc - pos).normalized()
			st_t -= delta
			if ws and randf() < delta * 160.0:
				var ba: float = randf() * TAU
				var bp: Vector2 = beam_muzzle() + Vector2.from_angle(ba) * randf_range(30.0, 80.0)
				ws.spawn_trail_dot(bp, (beam_muzzle() - bp) * 3.0, Color(1.0, 0.5, 0.25))
			if st_t <= 0.0:
				state = ST_BEAM
				beam_t = 3.4
				_beam_cd = 16.0 - 3.4 * phase
				if ws:
					ws.play_sfx("doom_spawn", pos, 0.0, 1.25)
		ST_BEAM:
			vel = vel.lerp(Vector2.ZERO, 1.0 - pow(0.01, delta))
			pos += vel * delta
			if struggle_freeze:
				beam_dir = (pc - pos).normalized()
			else:
				# Sweep the beam toward the player at a dodgeable turn rate
				var want: float = (pc - pos).angle()
				var cur: float = beam_dir.angle()
				var turn: float = 0.5 + 0.18 * phase
				beam_dir = Vector2.from_angle(rotate_toward(cur, want, turn * delta))
				beam_t -= delta
			_march_beam()
			# The annihilation beam cooks the terrain it lands on
			if not struggle_active and ws:
				var cbx: int = int(floor(beam_hit.x / 16.0))
				var cby: int = int(floor(beam_hit.y / 16.0))
				if WorldManager.is_solid_at(cbx, cby):
					ws.damage_block(cbx, cby, delta)
			_beam_sfx_t -= delta
			if ws and _beam_sfx_t <= 0.0:
				_beam_sfx_t = 0.42
				ws.play_sfx("doom_beam", pos, 0.05, 0.85)
			GameState.cam_shake = maxf(GameState.cam_shake, 2.0)
			if beam_t <= 0.0 and not struggle_freeze:
				state = ST_HOVER
				st_t = _hover_time()
		ST_STUNNED:
			vel = vel.lerp(Vector2(0.0, 60.0), 1.0 - pow(0.03, delta))
			pos += vel * delta
			st_t -= delta
			if ws and randf() < delta * 40.0:
				ws.spawn_trail_dot(pos + Vector2(randf_range(-30, 30), randf_range(-30, 30)), Vector2(randf_range(-30, 30), randf_range(-60, -10)), Color(1.0, 0.9, 0.4))
			if st_t <= 0.0:
				state = ST_HOVER
				st_t = _hover_time() * 0.5
				if ws:
					ws.play_sfx("doom_spawn", pos, 0.0, 1.5)
		ST_TRANSITION:
			vel = vel.lerp(Vector2(0.0, -50.0), 1.0 - pow(0.02, delta))
			pos += vel * delta
			st_t -= delta
			if ws and randf() < delta * 30.0:
				ws.spawn_ring(pos, phase_color(), 8.0, randf_range(50.0, 100.0), 0.3)
			if st_t <= 0.0:
				state = ST_HOVER
				st_t = _hover_time() * 0.5
		ST_DYING:
			st_t -= delta
			pos += Vector2(0.0, 26.0) * delta
			_die_fx_t -= delta
			if ws and _die_fx_t <= 0.0:
				_die_fx_t = 0.13
				var off: Vector2 = Vector2(randf_range(-28, 28), randf_range(-28, 28))
				ws.spawn_explosion(pos + off, phase_color())
				ws.play_sfx("explode", pos + off, 0.2, randf_range(0.8, 1.4))
			GameState.cam_shake = maxf(GameState.cam_shake, 6.0)
			if st_t <= 0.0:
				if ws:
					ws.spawn_explosion(pos, Color(1.0, 0.9, 0.5))
					ws.spawn_explosion(pos, Color(1.0, 0.4, 0.2))
					ws.spawn_ring(pos, Color(1, 1, 1), 10.0, 160.0, 0.55)
					ws.spawn_ring(pos, phase_color(), 6.0, 110.0, 0.45)
					ws.play_sfx("explode", pos, 0.0, 0.5)
				GameState.cam_shake = maxf(GameState.cam_shake, 16.0)
				state = ST_DEAD
				boss_died.emit()

	# Phase-3 follow-up volleys
	if _burst_extra > 0:
		_burst_timer -= delta
		if _burst_timer <= 0.0:
			_burst_timer = 0.17
			_burst_extra -= 1
			_fire_burst(pc)
	# Clamp to the flight envelope
	pos.x = clampf(pos.x, min_x + BODY_R, max_x - BODY_R)
	pos.y = clampf(pos.y, min_y + BODY_R, floor_y - BODY_R - 2.0)
	# SOLID vs the arena: the Warden cannot pass through blocks
	if alive():
		_collide_tiles()
	for ck in _impact_cd.keys():
		_impact_cd[ck] -= delta
		if _impact_cd[ck] <= 0.0:
			_impact_cd.erase(ck)
	# Floor shockwaves travel until they hit a wall
	for si in range(shocks.size() - 1, -1, -1):
		var sh: Dictionary = shocks[si]
		sh.x += sh.dir * 430.0 * delta
		if ws and randf() < delta * 60.0:
			ws.spawn_trail_dot(Vector2(sh.x, sh.get("y", floor_y) - randf_range(4.0, 30.0)), Vector2(sh.dir * 40.0, randf_range(-60.0, -20.0)), phase_color())
		if sh.x < min_x + 8.0 or sh.x > max_x - 8.0:
			shocks.remove_at(si)
	queue_redraw()


func _collide_tiles() -> void:
	## Circle-vs-tile resolution: push out of any solid block and kill the
	## into-surface velocity. HARD impacts chip the block they struck —
	## two hits shatter it (the indestructible shell always contains the
	## Warden, so it can never leave the arena).
	var col_r: float = 30.0
	var t0x: int = int(floor((pos.x - col_r) / 16.0))
	var t1x: int = int(floor((pos.x + col_r) / 16.0))
	var t0y: int = int(floor((pos.y - col_r) / 16.0))
	var t1y: int = int(floor((pos.y + col_r) / 16.0))
	for ty in range(t0y, t1y + 1):
		for tx in range(t0x, t1x + 1):
			if not WorldManager.is_solid_at(tx, ty):
				continue
			var rx: float = clampf(pos.x, tx * 16.0, tx * 16.0 + 16.0)
			var ry: float = clampf(pos.y, ty * 16.0, ty * 16.0 + 16.0)
			var dvec: Vector2 = pos - Vector2(rx, ry)
			var d: float = dvec.length()
			if d >= col_r:
				continue
			var n: Vector2 = dvec / d if d > 0.01 else Vector2(0, -1)
			pos += n * (col_r - d)
			var into: float = -vel.dot(n)
			if into > 0.0:
				vel += n * into
			# A real hit (slam/pound speed) chips the block: 2 hits = shattered
			if into > 260.0 and ws:
				var key: Vector2i = Vector2i(tx, ty)
				if not _impact_cd.has(key):
					_impact_cd[key] = 0.35
					ws.damage_block(tx, ty, WeaponSystem.BLOCK_BREAK_TIME * 0.55)
					ws.spawn_hit(Vector2(rx, ry), phase_color(), n)
					ws.play_sfx("bonk", Vector2(rx, ry), 0.08, 0.9)
					GameState.cam_shake = maxf(GameState.cam_shake, 3.5)


func _hover_time() -> float:
	return maxf(0.7, 1.7 - 0.35 * phase)


func _pick_attack() -> void:
	if _beam_cd <= 0.0:
		state = ST_TG_BEAM
		st_t = 1.15
		return
	var pattern: Array
	if phase == 1:
		pattern = [ST_TG_SLAM, ST_TG_BURST, ST_TG_SLAM, ST_TG_POUND]
	elif phase == 2:
		pattern = [ST_TG_SLAM, ST_TG_BURST, ST_TG_POUND, ST_TG_BURST, ST_TG_SLAM]
	else:
		pattern = [ST_TG_SLAM, ST_TG_BURST, ST_TG_POUND, ST_TG_SLAM, ST_TG_BURST]
	state = pattern[_attack_idx % pattern.size()]
	_attack_idx += 1
	if state == ST_TG_SLAM:
		st_t = maxf(0.45, 0.85 - 0.1 * phase)
	elif state == ST_TG_BURST:
		st_t = 0.55
	else:
		st_t = 0.65


func _slam_contact(pc: Vector2, p_alive: bool) -> void:
	if slam_hit_done or not p_alive:
		return
	if pos.distance_to(pc) >= BODY_R + 10.0:
		return
	slam_hit_done = true
	if ws and ws.is_shielded("player"):
		# PARRIED! The shield takes the Warden's whole charge and throws it
		# back — long stun, double-damage punish window, shield refunded.
		vel = -slam_dir * 560.0 + Vector2(0.0, -190.0)
		state = ST_STUNNED
		st_t = maxf(1.8, 3.1 - 0.3 * phase)
		ws._actors["player"]["shield_energy"] = WeaponSystem.SHIELD_MAX
		ws.play_sfx("bonk", pc, 0.05, 0.62)
		ws.spawn_ring(pc, Color(0.6, 0.95, 1.0), 6.0, 52.0, 0.32)
		ws.spawn_ring(pc, Color(1, 1, 1), 4.0, 30.0, 0.22)
		ws.spawn_hit(pc, Color(0.7, 0.95, 1.0), -slam_dir)
		GameState.cam_shake = maxf(GameState.cam_shake, 11.0)
	else:
		hurt_player.call(2, slam_dir)
		push_player.call(slam_dir * 11.0 + Vector2(0.0, -4.5))
		if ws:
			ws.play_sfx("bonk", pc, 0.05, 0.8)
			ws.spawn_hit(pc, Color(1.0, 0.6, 0.3), slam_dir)
			ws.spawn_ring(pc, phase_color(), 5.0, 36.0, 0.25)
		GameState.cam_shake = maxf(GameState.cam_shake, 8.0)


func _fire_burst(pc: Vector2) -> void:
	if ws == null:
		return
	var base: Vector2 = (pc - pos).normalized()
	var n: int = 5 + phase
	var spread: float = 0.42 + 0.06 * phase
	for k in range(n):
		var f: float = 0.5 if n <= 1 else float(k) / float(n - 1)
		var dir: Vector2 = base.rotated(lerpf(-spread, spread, f))
		_spawn_proj(dir, 300.0 + 40.0 * phase)
	if phase >= 2:
		# Radial halo on top of the aimed fan
		for k2 in range(10 + phase * 2):
			var ang: float = _orbit + TAU * float(k2) / float(10 + phase * 2)
			_spawn_proj(Vector2.from_angle(ang), 210.0 + 30.0 * phase)
	ws.play_sfx("shoot_scatter", pos, 0.06, 0.7)
	GameState.cam_shake = maxf(GameState.cam_shake, 2.5)


func _spawn_proj(dir: Vector2, spd: float) -> void:
	ws._projectiles.append({
		"pos": pos + dir * (BODY_R + 6.0), "vel": dir * spd,
		"team": 1, "dmg": 1, "life": 3.6,
		"color": phase_color(), "size": 3.2,
	})


func _march_beam() -> void:
	var mz: Vector2 = beam_muzzle()
	beam_hit = mz
	for s in range(220):
		beam_hit = mz + beam_dir * (s * 6.0)
		if WorldManager.is_solid_at(int(floor(beam_hit.x / 16.0)), int(floor(beam_hit.y / 16.0))):
			break


func _draw() -> void:
	if state == ST_DEAD:
		return
	var jit: Vector2 = Vector2.ZERO
	if _shake > 0.0 or state == ST_TG_SLAM or state == ST_DYING:
		var amp: float = maxf(_shake, 3.0 if state == ST_TG_SLAM else 0.0)
		if state == ST_DYING:
			amp = 6.0
		jit = Vector2(randf_range(-amp, amp), randf_range(-amp, amp))
	var c: Vector2 = pos + jit
	var col: Color = phase_color()
	var mat: float = 1.0
	if state == ST_SPAWN:
		mat = clampf(1.0 - st_t / 2.2, 0.05, 1.0)
	var pulse: float = 0.5 + 0.5 * sin(_time * 3.2)

	# ── Shockwaves: traveling energy walls along the surface they hit ──
	for sh in shocks:
		var sx: float = sh.x
		var sy: float = sh.get("y", floor_y)
		var wob: float = 4.0 * sin(_time * 30.0 + sx)
		draw_line(Vector2(sx, sy), Vector2(sx, sy - 40.0 - wob), Color(col.r, col.g, col.b, 0.85), 5.0)
		draw_line(Vector2(sx, sy), Vector2(sx, sy - 26.0), Color(1, 1, 0.9, 0.9), 2.5)
		draw_circle(Vector2(sx, sy - 6.0), 7.0, Color(col.r, col.g, col.b, 0.6))

	# ── Annihilation beam ──
	if state == ST_BEAM:
		var mz: Vector2 = pos + beam_dir * (BODY_R + 4.0)
		var to: Vector2 = clash_point if struggle_active else beam_hit
		var flicker: float = 0.85 + 0.15 * sin(_time * 60.0)
		draw_line(mz, to, Color(col.r, col.g, col.b, 0.22), 58.0 * flicker)
		draw_line(mz, to, Color(1.0, 0.35, 0.15, 0.55), 34.0 * flicker)
		draw_line(mz, to, Color(1.0, 0.75, 0.4, 0.9), 18.0 * flicker)
		draw_line(mz, to, Color(1, 1, 0.92), 8.0)
		draw_circle(mz, 12.0, Color(1, 1, 0.92))
		draw_circle(to, 12.0 + 6.0 * flicker, Color(1.0, 0.6, 0.3, 0.75))
		if struggle_active:
			# The player's counter-stream + the white-hot clash core
			var pc2: Vector2 = get_player_center.call()
			draw_line(pc2, to, Color(0.3, 0.8, 1.0, 0.3), 30.0 * flicker)
			draw_line(pc2, to, Color(0.55, 0.9, 1.0, 0.7), 16.0 * flicker)
			draw_line(pc2, to, Color(0.95, 1.0, 1.0), 7.0)
			var cr: float = 15.0 + 4.0 * sin(_time * 45.0)
			draw_circle(to, cr + 8.0, Color(1.0, 0.8, 0.5, 0.35))
			draw_circle(to, cr, Color(1, 1, 1, 0.95))
			for k in range(6):
				var ra: float = _time * 14.0 + TAU * float(k) / 6.0
				draw_line(to + Vector2.from_angle(ra) * 6.0, to + Vector2.from_angle(ra) * (cr + 14.0), Color(1, 1, 0.9, 0.8), 2.0)
	elif state == ST_TG_BEAM:
		# Telegraph: thin aim line + swelling charge orb
		var mz2: Vector2 = pos + beam_dir * (BODY_R + 4.0)
		var chg: float = 1.0 - st_t / 1.15
		draw_line(mz2, mz2 + beam_dir * 900.0, Color(1.0, 0.3, 0.2, 0.25 + 0.3 * chg), 2.0)
		draw_circle(mz2, 4.0 + 14.0 * chg, Color(1.0, 0.6, 0.3, 0.8))
		draw_circle(mz2, 2.0 + 8.0 * chg, Color(1, 1, 0.9))

	# ── Slam telegraph: warning dashes toward the player ──
	if state == ST_TG_SLAM:
		var dirp: Vector2 = (_eye / 6.5) if _eye.length() > 0.1 else Vector2.RIGHT
		for k in range(5):
			var d0: float = BODY_R + 12.0 + k * 22.0
			draw_line(c + dirp * d0, c + dirp * (d0 + 12.0), Color(1.0, 0.3, 0.25, 0.9 - 0.14 * k), 3.0)

	# ── Aura ──
	draw_circle(c, BODY_R + 18.0 + 5.0 * pulse, Color(col.r, col.g, col.b, 0.06 * mat))
	draw_circle(c, BODY_R + 9.0 + 3.0 * pulse, Color(col.r, col.g, col.b, 0.1 * mat))
	if _panic() and alive():
		# Fear halo: the Warden KNOWS what you're holding
		draw_arc(c, BODY_R + 24.0, 0, TAU, 32, Color(1.0, 0.3, 0.2, 0.22 + 0.2 * sin(_time * 18.0)), 2.2)

	# ── Armor rings: counter-rotating segmented halos ──
	for k in range(8):
		var a0: float = _ring_a + TAU * float(k) / 8.0
		draw_arc(c, 52.0, a0, a0 + TAU / 8.0 * 0.62, 8, Color(col.r, col.g, col.b, 0.75 * mat), 4.5)
	for k in range(6):
		var a1: float = _ring_b + TAU * float(k) / 6.0
		draw_arc(c, 43.0, a1, a1 + TAU / 6.0 * 0.55, 8, Color(col.r * 0.7 + 0.3, col.g * 0.7 + 0.3, col.b * 0.7 + 0.3, 0.85 * mat), 5.5)

	# ── Orbital pods (they glow hot when a burst is coming) ──
	var pod_glow: float = 1.0 - st_t / 0.55 if state == ST_TG_BURST else 0.0
	for k in range(6):
		var pa: float = _orbit + TAU * float(k) / 6.0
		var pp: Vector2 = c + Vector2.from_angle(pa) * 37.0
		var tip: Vector2 = Vector2.from_angle(pa)
		var side: Vector2 = tip.orthogonal()
		var pts: PackedVector2Array = PackedVector2Array([pp + tip * 7.0, pp - tip * 3.0 + side * 4.5, pp - tip * 3.0 - side * 4.5])
		if pod_glow > 0.0:
			draw_circle(pp, 7.0 + 4.0 * pod_glow, Color(1.0, 0.7, 0.3, 0.5 * pod_glow))
		draw_colored_polygon(pts, Color(col.r, col.g, col.b, (0.9 + 0.1 * pod_glow) * mat))

	# ── Core ──
	draw_circle(c, 27.0, Color(0.06, 0.05, 0.1, 0.96 * mat))
	draw_arc(c, 27.0, 0, TAU, 40, Color(col.r, col.g, col.b, 0.95 * mat), 2.6)
	draw_circle(c, 20.0, Color(col.r * 0.25, col.g * 0.25, col.b * 0.3, 0.9 * mat))
	# Iris + tracking pupil
	var stunned: bool = state == ST_STUNNED
	var iris_col: Color = Color(1.0, 0.85, 0.35) if stunned else col
	draw_circle(c + _eye * 0.5, 13.0, Color(iris_col.r, iris_col.g, iris_col.b, 0.85 * mat))
	if stunned:
		# X-eyes: the Warden is reeling — POUND ON IT
		var ex: Vector2 = c + _eye * 0.5
		draw_line(ex + Vector2(-6, -6), ex + Vector2(6, 6), Color(0.1, 0.05, 0.1), 3.0)
		draw_line(ex + Vector2(-6, 6), ex + Vector2(6, -6), Color(0.1, 0.05, 0.1), 3.0)
		for k in range(3):
			var sa2: float = _time * 5.0 + TAU * float(k) / 3.0
			draw_circle(c + Vector2(cos(sa2) * 30.0, -44.0 + sin(sa2 * 2.0) * 4.0), 3.0, Color(1.0, 0.9, 0.3))
	else:
		draw_circle(c + _eye, 5.5, Color(1, 1, 1, 0.98 * mat))
		draw_circle(c + _eye + Vector2(-1.5, -1.5), 1.8, Color(1, 1, 1))
	# Damage flash
	if _flash > 0.0:
		draw_circle(c, 30.0, Color(1, 1, 1, clampf(_flash * 4.5, 0.0, 0.85)))
	# Transition roar rings
	if state == ST_TRANSITION:
		var tf: float = 1.0 - st_t / 1.5
		draw_arc(c, 30.0 + 90.0 * tf, 0, TAU, 40, Color(col.r, col.g, col.b, 0.8 * (1.0 - tf)), 4.0)
		draw_arc(c, 30.0 + 55.0 * tf, 0, TAU, 40, Color(1, 1, 1, 0.6 * (1.0 - tf)), 2.5)
