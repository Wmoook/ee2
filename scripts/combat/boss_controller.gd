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
const ST_TG_SING: int = 13   # Phase 4: charge a void singularity
const ST_TG_RIFT: int = 14   # Phase 4: dissolve into the void...
const ST_RIFT_GONE: int = 15 # ...gone — rift marker hunts the player
const ST_RIFT_ERUPT: int = 16 # ...ERUPTS out of the rift
const ST_CAGE: int = 17      # Phase 5: rotating 4-beam laser cage
const ST_TG_SKY: int = 18    # Phase 5: charge the meteor skyfall
const ST_SKYFALL: int = 19   # Phase 5: golden comets rain
const ST_TG_CAGE: int = 20

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
var beam_segments: Array = []    # [{from, to}] — the laser path, wall bounces included
var _beam_fires: int = 0         # Each firing adds one more wall reflection
var _pending_roar: bool = false  # Phase crossed mid-beam: roar AFTER the beam ends
var sings: Array = []            # Void singularities: {pos, vel, target, armed, t}
var rift_pos: Vector2 = Vector2.ZERO
var cage_angle: float = 0.0
var _sky_t: float = 0.0

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
	if phase == 3:
		return Color(1.0, 0.28, 0.32)
	if phase == 4:
		return Color(0.72, 0.35, 1.0)
	return Color(1.0, 0.88, 0.4)


func get_center() -> Vector2:
	return pos


func get_vel_pxs() -> Vector2:
	return vel


func alive() -> bool:
	return hp > 0 and state != ST_DYING and state != ST_DEAD


func vulnerable() -> bool:
	return alive() and state != ST_SPAWN and state != ST_TRANSITION and state != ST_RIFT_GONE and not struggle_active


func beam_muzzle() -> Vector2:
	return pos + beam_dir * (BODY_R + 4.0)


func _panic() -> bool:
	## The player is holding the DOOM RAY — the Warden is AFRAID of it.
	return ws != null and ws.get_weapon("player") == "doom"


func apply_push(v: Vector2) -> void:
	# The Warden barely budges — 12% of any knockback gets through
	vel += v * PUSH_TO_PXS * 0.12


func state_name() -> String:
	return ["SPAWN", "HOVER", "TG_SLAM", "SLAM", "TG_BURST", "TG_POUND", "POUND", "TG_BEAM", "BEAM", "STUNNED", "TRANSITION", "DYING", "DEAD", "TG_SING", "TG_RIFT", "RIFT_GONE", "RIFT_ERUPT", "CAGE", "TG_SKY", "SKYFALL", "TG_CAGE"][state]


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
		sings.clear()
		if ws:
			ws.play_sfx("explode", pos, 0.05, 0.7)
		return
	# FIVE phases: thresholds at every fifth of max HP
	if phase == 1 and hp <= (max_hp * 4) / 5:
		_request_phase(2)
	elif phase == 2 and hp <= (max_hp * 3) / 5:
		_request_phase(3)
	elif phase == 3 and hp <= (max_hp * 2) / 5:
		_request_phase(4)
	elif phase == 4 and hp <= max_hp / 5:
		_request_phase(5)


func _request_phase(new_phase: int) -> void:
	## Phase crossings must NEVER cut the annihilation beam short (that was
	## the "ray ends early" bug — the transition roar hijacked ST_BEAM).
	## Mid-beam: power up silently, roar once the beam finishes.
	if state == ST_BEAM:
		phase = new_phase
		_pending_roar = true
		phase_changed.emit(phase)
		if ws:
			ws.spawn_ring(pos, phase_color(), 8.0, 70.0, 0.35)
	else:
		_enter_transition(new_phase)


func _enter_transition(new_phase: int) -> void:
	phase = new_phase
	state = ST_TRANSITION
	st_t = 1.5
	struggle_active = false
	struggle_freeze = false
	shocks.clear()
	sings.clear()
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
	_pending_roar = false  # The stun IS the drama — no late roar
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
	# Beam-cut resets each frame; re-set by _cancel_vs_player_doom on crossing
	if ws and ws._actors.has("player"):
		ws._actors["player"]["beam_cut"] = -1.0
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
					_jink_t = randf_range(0.13, 0.3)
					_jink_target = Vector2(randf_range(min_x + 110.0, max_x - 110.0), randf_range(min_y + 50.0, 340.0))
					if absf(_jink_target.x - pc.x) < 240.0:
						var flee: float = signf(pos.x - pc.x)
						if flee == 0.0:
							flee = 1.0
						_jink_target.x = clampf(pc.x + flee * randf_range(300.0, 480.0), min_x + 100.0, max_x - 100.0)
				anchor = _jink_target
				vmax = 500.0 + 70.0 * phase
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
				vel = vel.lerp((anchor - pos) * 3.4, 1.0 - pow(0.003, delta))
			else:
				# Restless even when calm: periodic wander jinks so the
				# Warden never just floats above you
				_jink_t -= delta
				if _jink_t <= 0.0:
					_jink_t = randf_range(0.4, 0.8)
					_jink_target = anchor + Vector2(randf_range(-200.0, 200.0), randf_range(-70.0, 85.0))
				anchor = Vector2(clampf(_jink_target.x, min_x + 90.0, max_x - 90.0), clampf(_jink_target.y, min_y + 50.0, 370.0))
				vmax = 300.0 + 85.0 * phase
				vel = vel.lerp((anchor - pos) * 2.5, 1.0 - pow(0.01, delta))
			if vel.length() > vmax:
				vel = vel.normalized() * vmax
			pos += vel * delta
			st_t -= delta
			if st_t <= 0.0 and p_alive:
				if _panic():
					# Never slam or pound INTO the doom — snipe from range,
					# or (void phases) RIFT-ESCAPE across the arena
					if _beam_cd <= 0.0:
						state = ST_TG_BEAM
						st_t = 1.15
					elif phase >= 4 and randf() < 0.45:
						state = ST_TG_RIFT
						st_t = 0.55
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
				_beam_cd = maxf(6.0, 16.0 - 2.8 * phase)
				_beam_fires += 1  # Every firing reflects one MORE time
				if ws:
					ws.play_sfx("doom_spawn", pos, 0.0, 1.25)
		ST_BEAM:
			vel = vel.lerp(Vector2.ZERO, 1.0 - pow(0.01, delta))
			pos += vel * delta
			if struggle_freeze:
				beam_dir = (pc - pos).normalized()
			else:
				# Sweep the beam toward the player SLOWLY — a full-speed run
				# always outpaces the sweep (evasion is a real answer)
				var want: float = (pc - pos).angle()
				var cur: float = beam_dir.angle()
				var turn: float = 0.32 + 0.08 * phase
				beam_dir = Vector2.from_angle(rotate_toward(cur, want, turn * delta))
				beam_t -= delta
			_march_beam(delta)
			_cancel_vs_player_doom()
			_beam_sfx_t -= delta
			if ws and _beam_sfx_t <= 0.0:
				_beam_sfx_t = 0.42
				ws.play_sfx("doom_beam", pos, 0.05, 0.85)
			GameState.cam_shake = maxf(GameState.cam_shake, 2.0)
			if beam_t <= 0.0 and not struggle_freeze:
				if _pending_roar:
					# The deferred phase roar fires now that the beam is done
					_pending_roar = false
					_enter_transition(phase)
				else:
					state = ST_HOVER
					st_t = _hover_time()
		ST_TG_SING:
			vel = vel.lerp(Vector2.ZERO, 1.0 - pow(0.01, delta))
			pos += vel * delta
			st_t -= delta
			if ws and randf() < delta * 140.0:
				var va: float = randf() * TAU
				var vp: Vector2 = pos + Vector2.from_angle(va) * randf_range(40.0, 90.0)
				ws.spawn_trail_dot(vp, (pos - vp) * 2.8, Color(0.72, 0.35, 1.0))
			if st_t <= 0.0:
				var starget: Vector2 = pc + (get_player_vel.call() * 0.3 if p_alive else Vector2.ZERO)
				sings.append({
					"pos": pos, "vel": (starget - pos).normalized() * 520.0,
					"target": starget, "armed": false, "t": 1.2,
				})
				if ws:
					ws.play_sfx("shoot_rail", pos, 0.05, 0.5)
				state = ST_HOVER
				st_t = _hover_time() * 0.7
		ST_TG_RIFT:
			vel = vel.lerp(Vector2.ZERO, 1.0 - pow(0.01, delta))
			pos += vel * delta
			st_t -= delta
			if ws and randf() < delta * 200.0:
				var ra2: float = randf() * TAU
				ws.spawn_trail_dot(pos + Vector2.from_angle(ra2) * randf_range(10.0, 44.0), Vector2.from_angle(ra2) * -120.0, Color(0.72, 0.35, 1.0))
			if st_t <= 0.0:
				if _panic():
					# Escape teleport: rift to the FAR side of the arena
					var flee_x: float = pc.x + (620.0 if pc.x < (min_x + max_x) * 0.5 else -620.0)
					rift_pos = Vector2(clampf(flee_x, min_x + 120.0, max_x - 120.0), 235.0)
				else:
					rift_pos = pc
				state = ST_RIFT_GONE
				st_t = 0.95
				if ws:
					ws.play_sfx("doom_spawn", pos, 0.05, 1.6)
					ws.spawn_ring(pos, Color(0.72, 0.35, 1.0), 30.0, 4.0, 0.3)
		ST_RIFT_GONE:
			st_t -= delta
			if not _panic():
				rift_pos = rift_pos.move_toward(pc, 130.0 * delta)
			if ws and randf() < delta * 220.0:
				var ga2: float = randf() * TAU
				var gp: Vector2 = rift_pos + Vector2.from_angle(ga2) * randf_range(26.0, 70.0)
				ws.spawn_trail_dot(gp, (rift_pos - gp) * 3.0, Color(0.8, 0.5, 1.0))
			if st_t <= 0.0:
				pos = Vector2(clampf(rift_pos.x, min_x + BODY_R, max_x - BODY_R), clampf(rift_pos.y - 12.0, min_y + BODY_R, floor_y - BODY_R - 2.0))
				vel = Vector2.ZERO
				state = ST_RIFT_ERUPT
				st_t = 0.3
				if ws:
					ws.spawn_explosion(pos, Color(0.72, 0.35, 1.0))
					ws.spawn_ring(pos, Color(0.85, 0.55, 1.0), 8.0, 70.0, 0.35)
					ws.play_sfx("explode", pos, 0.08, 0.7)
				for k in range(10 + phase):
					_spawn_proj(Vector2.from_angle(TAU * float(k) / float(10 + phase)), 260.0 + 30.0 * phase)
				if p_alive and pos.distance_to(pc) < 86.0:
					hurt_player.call(1, (pc - pos).normalized())
					push_player.call((pc - pos).normalized() * 7.0 + Vector2(0.0, -3.0))
				GameState.cam_shake = maxf(GameState.cam_shake, 9.0)
		ST_RIFT_ERUPT:
			st_t -= delta
			if st_t <= 0.0:
				state = ST_HOVER
				st_t = _hover_time() * 0.8
		ST_TG_CAGE:
			pos = pos.lerp(Vector2((min_x + max_x) * 0.5, 218.0), 1.0 - pow(0.03, delta))
			st_t -= delta
			if ws and randf() < delta * 160.0:
				var ca: float = randf() * TAU
				var cp2: Vector2 = pos + Vector2.from_angle(ca) * randf_range(40.0, 100.0)
				ws.spawn_trail_dot(cp2, (pos - cp2) * 2.6, Color(1.0, 0.88, 0.4))
			if st_t <= 0.0:
				state = ST_CAGE
				st_t = 4.2
				cage_angle = randf() * TAU
				if ws:
					ws.play_sfx("doom_spawn", pos, 0.0, 1.1)
		ST_CAGE:
			pos = pos.lerp(Vector2((min_x + max_x) * 0.5, 218.0), 1.0 - pow(0.05, delta))
			st_t -= delta
			cage_angle += delta * (0.45 + 0.05 * phase)
			beam_segments.clear()
			for k in range(4):
				var cd: Vector2 = Vector2.from_angle(cage_angle + float(k) * PI / 2.0)
				var cfrom: Vector2 = pos + cd * (BODY_R + 4.0)
				var cend: Vector2 = cfrom
				for s in range(220):
					cend = cfrom + cd * (s * 6.0)
					var ctx2: int = int(floor(cend.x / 16.0))
					var cty2: int = int(floor(cend.y / 16.0))
					if WorldManager.is_solid_at(ctx2, cty2):
						if ws:
							ws.damage_block(ctx2, cty2, delta * 0.5)
						break
				beam_segments.append({"from": cfrom, "to": cend})
			_cancel_vs_player_doom()
			_beam_sfx_t -= delta
			if ws and _beam_sfx_t <= 0.0:
				_beam_sfx_t = 0.5
				ws.play_sfx("doom_beam", pos, 0.05, 1.3)
			GameState.cam_shake = maxf(GameState.cam_shake, 1.5)
			if st_t <= 0.0:
				beam_segments.clear()
				state = ST_HOVER
				st_t = _hover_time()
		ST_TG_SKY:
			vel = vel.lerp(Vector2(0.0, -90.0), 1.0 - pow(0.02, delta))
			pos += vel * delta
			st_t -= delta
			if ws and randf() < delta * 150.0:
				ws.spawn_trail_dot(Vector2(randf_range(min_x + 40.0, max_x - 40.0), min_y + randf_range(4.0, 30.0)), Vector2(0, 60), Color(1.0, 0.88, 0.4))
			if st_t <= 0.0:
				state = ST_SKYFALL
				st_t = 2.8
				_sky_t = 0.0
		ST_SKYFALL:
			vel = vel.lerp(Vector2.ZERO, 1.0 - pow(0.02, delta))
			pos += vel * delta
			st_t -= delta
			_sky_t -= delta
			if _sky_t <= 0.0 and ws:
				_sky_t = 0.09
				# Golden comets: half random, half hunting the player's column
				var cx2: float
				if randf() < 0.5 and p_alive:
					cx2 = clampf(pc.x + randf_range(-130.0, 130.0), min_x + 24.0, max_x - 24.0)
				else:
					cx2 = randf_range(min_x + 24.0, max_x - 24.0)
				ws._projectiles.append({
					"pos": Vector2(cx2, min_y + 6.0), "vel": Vector2(randf_range(-45.0, 45.0), randf_range(520.0, 650.0)),
					"team": 1, "dmg": 1, "life": 2.5,
					"color": Color(1.0, 0.85, 0.4), "size": 4.2,
				})
			if st_t <= 0.0:
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
	# Void singularities: fly to their mark, then DEVOUR — a hungry well
	# that drags the ball in, then collapses in a violet blast
	for si2 in range(sings.size() - 1, -1, -1):
		var sg2: Dictionary = sings[si2]
		sg2.t -= delta
		if not sg2.armed:
			sg2.pos += sg2.vel * delta
			if sg2.t <= 0.0 or sg2.pos.distance_to(sg2.target) < 16.0:
				sg2.armed = true
				sg2.t = 3.2
				if ws:
					ws.spawn_ring(sg2.pos, Color(0.72, 0.35, 1.0), 6.0, 44.0, 0.3)
					ws.play_sfx("doom_spawn", sg2.pos, 0.05, 0.9)
		else:
			if p_alive:
				var to_s: Vector2 = sg2.pos - pc
				var sd: float = to_s.length()
				if sd < 320.0 and sd > 4.0:
					push_player.call(to_s / sd * lerpf(8.5, 1.6, sd / 320.0) * delta)
			if ws and randf() < delta * 170.0:
				var ia: float = randf() * TAU
				var ip: Vector2 = sg2.pos + Vector2.from_angle(ia) * randf_range(30.0, 95.0)
				ws.spawn_trail_dot(ip, (sg2.pos - ip) * 2.6, Color(0.75, 0.4, 1.0))
			if sg2.t <= 0.0:
				if ws:
					ws.spawn_explosion(sg2.pos, Color(0.75, 0.35, 1.0))
					ws.spawn_ring(sg2.pos, Color(0.85, 0.55, 1.0), 6.0, 76.0, 0.4)
					ws.play_sfx("explode", sg2.pos, 0.1, 0.8)
				if p_alive and pc.distance_to(sg2.pos) < 90.0:
					hurt_player.call(1, (pc - sg2.pos).normalized())
					push_player.call((pc - sg2.pos).normalized() * 8.0 + Vector2(0.0, -3.0))
				GameState.cam_shake = maxf(GameState.cam_shake, 7.0)
				sings.remove_at(si2)
	# Clamp to the flight envelope
	pos.x = clampf(pos.x, min_x + BODY_R, max_x - BODY_R)
	pos.y = clampf(pos.y, min_y + BODY_R, floor_y - BODY_R - 2.0)
	# SOLID vs the arena: the Warden cannot pass through blocks
	# (not while it IS the void — the rift passes through everything)
	if alive() and state != ST_RIFT_GONE:
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
	## Circle-vs-tile resolution: the Warden cannot pass through blocks.
	## HARD impacts (slam/pound speed) SHATTER the block in one hit and
	## carom the Warden off it; soft contact just slides. The
	## indestructible shell always contains it — it can never leave.
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
			if into > 260.0 and ws:
				# A real hit (slam/pound speed): the block SHATTERS in one
				# and the Warden CAROMS off it — crash, debris, rebound
				var key: Vector2i = Vector2i(tx, ty)
				if not _impact_cd.has(key):
					_impact_cd[key] = 0.35
					ws.damage_block(tx, ty, WeaponSystem.BLOCK_BREAK_TIME + 0.01)
					ws.spawn_hit(Vector2(rx, ry), phase_color(), n)
					ws.play_sfx("bonk", Vector2(rx, ry), 0.08, 0.9)
					GameState.cam_shake = maxf(GameState.cam_shake, 4.0)
				vel = vel.bounce(n) * 0.55
			elif into > 0.0:
				vel += n * into


func _cancel_vs_player_doom() -> void:
	## BEAM vs BEAM: if the player's DOOM RAY crosses the Warden's laser,
	## they ANNIHILATE each other at the crossing — both beams stop there
	## in a white-hot flare and nothing beyond it gets hit.
	if ws == null or not ws._actors.has("player"):
		return
	var pa: Dictionary = ws._actors["player"]
	if not pa.get("beam_draw", false):
		return
	var p_from: Vector2 = pa.get_center.call() + pa.aim * 16.0
	var p_to: Vector2 = pa.beam_end
	for i in range(beam_segments.size()):
		var sg: Dictionary = beam_segments[i]
		var hit = Geometry2D.segment_intersects_segment(sg.from, sg.to, p_from, p_to)
		if hit == null:
			continue
		var x: Vector2 = hit
		# Truncate the Warden's laser at the crossing (later bounces die)
		sg.to = x
		beam_segments.resize(i + 1)
		beam_hit = x
		# The player's doom stops there next frame too
		pa["beam_cut"] = p_from.distance_to(x)
		# Annihilation flare
		if randf() < 0.6:
			ws.spawn_trail_dot(x, Vector2(randf_range(-220, 220), randf_range(-220, 220)), Color(1.0, 0.9, 0.6) if randf() < 0.5 else Color(0.5, 1.0, 0.55))
		if randf() < 0.14:
			ws.spawn_ring(x, Color(1.0, 0.95, 0.8), 4.0, 28.0, 0.2)
		GameState.cam_shake = maxf(GameState.cam_shake, 2.5)
		break


func _hover_time() -> float:
	return maxf(0.5, 1.7 - 0.28 * phase)


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
	elif phase == 3:
		pattern = [ST_TG_SLAM, ST_TG_BURST, ST_TG_POUND, ST_TG_SLAM, ST_TG_BURST]
	elif phase == 4:
		# VOID PROTOCOL: singularities + rift teleport-strikes
		pattern = [ST_TG_RIFT, ST_TG_BURST, ST_TG_SING, ST_TG_SLAM, ST_TG_RIFT, ST_TG_SING, ST_TG_POUND]
	else:
		# OMEGA PROTOCOL: everything, plus the laser cage and the skyfall
		pattern = [ST_TG_CAGE, ST_TG_RIFT, ST_TG_SKY, ST_TG_BURST, ST_TG_SING, ST_TG_SLAM, ST_TG_SKY, ST_TG_RIFT]
	state = pattern[_attack_idx % pattern.size()]
	_attack_idx += 1
	if state == ST_TG_SLAM:
		st_t = maxf(0.35, 0.85 - 0.1 * phase)
	elif state == ST_TG_BURST:
		st_t = 0.55
	elif state == ST_TG_SING:
		st_t = 0.7
	elif state == ST_TG_RIFT:
		st_t = 0.55
	elif state == ST_TG_SKY:
		st_t = 0.6
	elif state == ST_TG_CAGE:
		st_t = 0.8
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


func _march_beam(delta: float = 0.0) -> void:
	## The RICOCHET LASER: marches from the muzzle, REFLECTS off walls
	## (one more bounce per firing, up to 7) and cooks every surface it
	## touches. Segments feed the draw pass and BossMode's corridor checks.
	beam_segments.clear()
	var dir: Vector2 = beam_dir
	var p: Vector2 = beam_muzzle()
	var seg_start: Vector2 = p
	var bounces_left: int = mini(_beam_fires, 7)
	var budget: int = 300
	var done: bool = false
	while budget > 0 and not done:
		var prev: Vector2 = p
		p += dir * 6.0
		budget -= 1
		var tx: int = int(floor(p.x / 16.0))
		var ty: int = int(floor(p.y / 16.0))
		if WorldManager.is_solid_at(tx, ty):
			# Binary-refine the contact point: the raw 6px march made bounce
			# points pop around as the beam swept, thrashing the whole
			# reflected path (the "glitching" look)
			var lo: Vector2 = prev
			var hi: Vector2 = p
			for _r in range(4):
				var mid: Vector2 = (lo + hi) * 0.5
				if WorldManager.is_solid_at(int(floor(mid.x / 16.0)), int(floor(mid.y / 16.0))):
					hi = mid
				else:
					lo = mid
			if seg_start.distance_squared_to(lo) > 16.0:
				beam_segments.append({"from": seg_start, "to": lo})
			# EVERY contact melts terrain — bounce mirrors included. When a
			# mirror gives way the laser punches through and re-paths.
			if ws and not struggle_active and delta > 0.0:
				ws.damage_block(tx, ty, delta)
			if bounces_left <= 0:
				done = true
			else:
				bounces_left -= 1
				# Corner hits pick ONE stable axis (dominant travel axis) —
				# alternating X/Y normals made the far path flip-flop
				var ptx: int = int(floor(lo.x / 16.0))
				var pty: int = int(floor(lo.y / 16.0))
				var cx: bool = ptx != tx
				var cy: bool = pty != ty
				var nrm: Vector2
				if cx and cy:
					nrm = Vector2(-signf(dir.x), 0.0) if absf(dir.x) >= absf(dir.y) else Vector2(0.0, -signf(dir.y))
				elif cx:
					nrm = Vector2(-signf(dir.x), 0.0)
				elif cy:
					nrm = Vector2(0.0, -signf(dir.y))
				else:
					nrm = -dir
				dir = dir.bounce(nrm.normalized()).normalized()
				p = lo
				seg_start = lo
				# Corner pocket: next probe still solid -> terminate cleanly
				# instead of strobing micro-bounces in place
				var probe: Vector2 = p + dir * 6.0
				if WorldManager.is_solid_at(int(floor(probe.x / 16.0)), int(floor(probe.y / 16.0))):
					done = true
	if not done:
		beam_segments.append({"from": seg_start, "to": p})
	beam_hit = beam_segments[0].to if beam_segments.size() > 0 else beam_muzzle()


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
	elif state == ST_TG_RIFT:
		mat = clampf(st_t / 0.55, 0.1, 1.0)  # Dissolving into the void
	var pulse: float = 0.5 + 0.5 * sin(_time * 3.2)

	# ── Shockwaves: traveling energy walls along the surface they hit ──
	for sh in shocks:
		var sx: float = sh.x
		var sy: float = sh.get("y", floor_y)
		var wob: float = 4.0 * sin(_time * 30.0 + sx)
		draw_line(Vector2(sx, sy), Vector2(sx, sy - 40.0 - wob), Color(col.r, col.g, col.b, 0.85), 5.0)
		draw_line(Vector2(sx, sy), Vector2(sx, sy - 26.0), Color(1, 1, 0.9, 0.9), 2.5)
		draw_circle(Vector2(sx, sy - 6.0), 7.0, Color(col.r, col.g, col.b, 0.6))

	# ── Void singularities ──
	for sg in sings:
		if sg.armed:
			var swirl: float = _time * 9.0
			draw_circle(sg.pos, 26.0, Color(0.2, 0.05, 0.3, 0.35))
			draw_circle(sg.pos, 10.0, Color(0.04, 0.0, 0.08, 0.92))
			for k in range(3):
				var aa: float = swirl + float(k) * TAU / 3.0
				draw_arc(sg.pos, 16.0 + 5.0 * sin(_time * 7.0 + float(k)), aa, aa + 2.2, 12, Color(0.75, 0.4, 1.0, 0.8), 2.2)
			draw_arc(sg.pos, 30.0, -swirl, -swirl + 1.6, 10, Color(0.9, 0.6, 1.0, 0.5), 1.6)
		else:
			draw_circle(sg.pos, 8.0, Color(0.6, 0.25, 0.95))
			draw_circle(sg.pos, 4.0, Color(0.95, 0.85, 1.0))

	# ── Rifted away: only the hunting void tear is visible ──
	if state == ST_RIFT_GONE:
		var rs: float = _time * 12.0
		draw_circle(rift_pos, 20.0 + 4.0 * sin(_time * 10.0), Color(0.2, 0.05, 0.3, 0.4))
		draw_circle(rift_pos, 8.0, Color(0.05, 0.0, 0.1, 0.9))
		for k in range(2):
			var ra3: float = rs + float(k) * PI
			draw_arc(rift_pos, 15.0, ra3, ra3 + 2.4, 12, Color(0.8, 0.5, 1.0, 0.85), 2.4)
		draw_arc(rift_pos, 26.0, -rs * 0.7, -rs * 0.7 + 1.8, 10, Color(0.9, 0.7, 1.0, 0.5), 1.6)
		return

	# ── The RICOCHET LASER (emerald annihilation beam) ──
	if state == ST_BEAM:
		var mz: Vector2 = pos + beam_dir * (BODY_R + 4.0)
		var flicker: float = 0.85 + 0.15 * sin(_time * 60.0)
		if struggle_active:
			# Locked in the clash: laser grinds against the defender
			var to: Vector2 = clash_point
			var pc2: Vector2 = get_player_center.call()
			var bdir: Vector2 = (to - mz).normalized()
			draw_line(mz, to, Color(0.15, 1.0, 0.35, 0.22), 58.0 * flicker)
			draw_line(mz, to, Color(0.3, 1.0, 0.45, 0.55), 34.0 * flicker)
			draw_line(mz, to, Color(0.7, 1.0, 0.6, 0.9), 18.0 * flicker)
			draw_line(mz, to, Color(0.96, 1.0, 0.9), 8.0)
			var doom_held: bool = ws != null and ws.get_weapon("player") == "doom"
			if doom_held:
				# DOOM counter-beam: your own annihilation stream meets it
				draw_line(pc2, to, Color(1.0, 0.2, 0.08, 0.28), 30.0 * flicker)
				draw_line(pc2, to, Color(1.0, 0.45, 0.15, 0.6), 16.0 * flicker)
				draw_line(pc2, to, Color(1.0, 0.85, 0.5), 7.0)
			else:
				# SHIELD projection: your barrier shoved out to the contact
				# point — a cyan energy wall HOLDING the laser, fed by thin
				# streamers from the ball. No magic counter-beam.
				var fang: float = bdir.angle() + PI
				var arc_c: Vector2 = to + bdir * 14.0
				draw_arc(arc_c, 20.0, fang - 1.1, fang + 1.1, 18, Color(0.55, 0.9, 1.0, 0.92), 3.5)
				draw_arc(arc_c, 26.0, fang - 0.8, fang + 0.8, 14, Color(0.4, 0.8, 1.0, 0.5 + 0.3 * sin(_time * 30.0)), 2.0)
				var perp: Vector2 = bdir.orthogonal()
				for k in range(3):
					var wob2: float = sin(_time * 22.0 + float(k) * 2.1) * 6.0
					var mid1: Vector2 = pc2.lerp(to, 0.55) + perp * wob2
					draw_line(pc2, mid1, Color(0.5, 0.9, 1.0, 0.35), 1.5)
					draw_line(mid1, to - bdir * 4.0, Color(0.5, 0.9, 1.0, 0.35), 1.5)
			# White-hot clash core + radial sparks
			var cr: float = 15.0 + 4.0 * sin(_time * 45.0)
			draw_circle(to, cr + 8.0, Color(0.7, 1.0, 0.7, 0.3))
			draw_circle(to, cr, Color(1, 1, 1, 0.95))
			for k in range(6):
				var ra: float = _time * 14.0 + TAU * float(k) / 6.0
				draw_line(to + Vector2.from_angle(ra) * 6.0, to + Vector2.from_angle(ra) * (cr + 14.0), Color(0.8, 1.0, 0.85, 0.8), 2.0)
		else:
			# Free-firing: every segment of the bouncing laser, with bright
			# emerald nodes at each wall reflection
			for sgi in range(beam_segments.size()):
				var sg: Dictionary = beam_segments[sgi]
				draw_line(sg.from, sg.to, Color(0.15, 1.0, 0.35, 0.2), 52.0 * flicker)
				draw_line(sg.from, sg.to, Color(0.3, 1.0, 0.45, 0.55), 30.0 * flicker)
				draw_line(sg.from, sg.to, Color(0.7, 1.0, 0.6, 0.9), 16.0 * flicker)
				draw_line(sg.from, sg.to, Color(0.96, 1.0, 0.9), 7.0)
				if sgi > 0:
					draw_circle(sg.from, 9.0 + 4.0 * flicker, Color(0.6, 1.0, 0.6, 0.8))
					draw_circle(sg.from, 5.0, Color(0.95, 1.0, 0.9))
			if beam_segments.size() > 0:
				var endp: Vector2 = beam_segments[-1].to
				draw_circle(endp, 12.0 + 6.0 * flicker, Color(0.3, 1.0, 0.4, 0.7))
				draw_circle(endp, 6.5, Color(0.95, 1.0, 0.9))
		draw_circle(mz, 12.0, Color(0.9, 1.0, 0.9))
	elif state == ST_CAGE:
		# OMEGA: the rotating golden laser cage
		var cflick: float = 0.85 + 0.15 * sin(_time * 55.0)
		for sg in beam_segments:
			draw_line(sg.from, sg.to, Color(1.0, 0.85, 0.3, 0.18), 30.0 * cflick)
			draw_line(sg.from, sg.to, Color(1.0, 0.9, 0.45, 0.55), 15.0 * cflick)
			draw_line(sg.from, sg.to, Color(1.0, 0.98, 0.8), 6.0)
			draw_circle(sg.to, 8.0 + 4.0 * cflick, Color(1.0, 0.9, 0.5, 0.7))
		draw_circle(c, 16.0, Color(1.0, 0.95, 0.75, 0.9))
	elif state == ST_TG_BEAM:
		# Telegraph: thin emerald aim line + swelling charge orb
		var mz2: Vector2 = pos + beam_dir * (BODY_R + 4.0)
		var chg: float = 1.0 - st_t / 1.15
		draw_line(mz2, mz2 + beam_dir * 900.0, Color(0.3, 1.0, 0.4, 0.25 + 0.3 * chg), 2.0)
		draw_circle(mz2, 4.0 + 14.0 * chg, Color(0.4, 1.0, 0.5, 0.8))
		draw_circle(mz2, 2.0 + 8.0 * chg, Color(0.95, 1.0, 0.9))
	elif state == ST_TG_SING:
		# Winding up the singularity: collapsing violet charge
		var sc2: float = 1.0 - st_t / 0.7
		draw_circle(c, 10.0 + 26.0 * sc2, Color(0.72, 0.35, 1.0, 0.22 + 0.3 * sc2))
		draw_arc(c, 14.0 + 30.0 * sc2, _time * 8.0, _time * 8.0 + 2.0, 12, Color(0.85, 0.6, 1.0, 0.8), 2.5)

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
