class_name WeaponSystem
extends Node2D
## Weapons, projectiles, pickups, combat FX and SFX.
##
## Actors (player/bots) register with callables so this system knows nothing
## about their classes. Guns render as neon vector art floating beside the
## ball, aimed at the actor's aim direction. Projectiles collide with grid
## tiles, curve capsules and enemy actors. All effects use the game's opaque
## bright-particle style (same language as the fire trail).

const ACTOR_RADIUS: float = 10.0     # Projectile-vs-ball hit radius
const CURVE_HIT_DIST: float = 8.35   # Projectile-vs-curve centerline distance
const PICKUP_RADIUS: float = 16.0
const PICKUP_RESPAWN: float = 8.0    # Seconds until a taken pad refills

const WEAPONS: Dictionary = {
	"blaster": {
		"label": "BLASTER", "color": Color(1.0, 0.72, 0.15), "dmg": 1,
		"cooldown": 0.16, "speed": 950.0, "count": 1, "spread": 0.015,
		"life": 0.8, "size": 3.0, "sfx": "shoot_blaster", "shake": 1.6, "kick": 0.6,
	},
	"scatter": {
		"label": "SCATTER", "color": Color(0.25, 0.9, 1.0), "dmg": 1,
		"cooldown": 0.7, "speed": 760.0, "count": 6, "spread": 0.24,
		"life": 0.38, "size": 2.4, "sfx": "shoot_scatter", "shake": 3.2, "kick": 1.6,
	},
	"rail": {
		"label": "RAIL", "color": Color(0.75, 0.4, 1.0), "dmg": 2,
		"cooldown": 1.05, "speed": 2400.0, "count": 1, "spread": 0.0,
		"life": 0.5, "size": 3.6, "sfx": "shoot_rail", "shake": 4.5, "kick": 2.4,
	},
	"doom": {
		"label": "DOOM RAY", "color": Color(1.0, 0.22, 0.15), "dmg": 1,
		"cooldown": 0.0, "speed": 0.0, "count": 0, "spread": 0.0,
		"life": 0.0, "size": 0.0, "sfx": "", "shake": 0.0, "kick": 0.12,
		"beam": true, "duration": 10.0, "tick": 0.12, "range": 1100.0,
	},
}

const SUPER_PERIOD: float = 60.0     # A DOOM RAY materializes this often
const SUPER_ANIM_TIME: float = 1.8   # Spawn-in animation length

# Unarmed melee kit
const DASH_CD: float = 1.1           # Seconds between dashes
const DASH_WINDOW: float = 0.35      # Contact window after dashing
const DASH_DMG: int = 1
const SHIELD_MAX: float = 1.2        # Max shield hold (drains; regens when down)
const STUN_TIME: float = 1.0         # Parry stun duration

var _actors: Dictionary = {}      # id -> actor dict
var _pads: Array = []             # {pos, weapon, respawn_left, phase, super}
var _projectiles: Array = []      # {pos, vel, team, dmg, life, color, size}
var _fx: Array = []               # {pos, vel, life, max_life, color, size}
var _sfx: Dictionary = {}         # name -> AudioStream
var _sfx_pool: Array = []
var _sfx_next: int = 0
var _time: float = 0.0
# Super weapon (DOOM RAY) cycle
var super_pos: Vector2 = Vector2.ZERO   # Set by the map builder
var _super_timer: float = SUPER_PERIOD
var _super_state: int = 0               # 0=countdown, 1=materializing, 2=on the field
var _super_anim: float = 0.0
var _beam_audio: AudioStreamPlayer2D


func _ready() -> void:
	z_index = 3
	for n in ["shoot_blaster", "shoot_scatter", "shoot_rail", "hit", "explode", "pickup", "doom_spawn", "doom_beam"]:
		var stream: AudioStream = load("res://assets/sfx/%s.wav" % n) as AudioStream
		if stream:
			_sfx[n] = stream
	for _i in range(10):
		var p: AudioStreamPlayer2D = AudioStreamPlayer2D.new()
		p.max_distance = 2400.0
		p.attenuation = 1.2
		p.volume_db = -4.0
		add_child(p)
		_sfx_pool.append(p)
	# Dedicated looping player for the DOOM RAY hum
	_beam_audio = AudioStreamPlayer2D.new()
	_beam_audio.max_distance = 2400.0
	_beam_audio.volume_db = -6.0
	var beam_stream: AudioStreamWAV = _sfx.get("doom_beam") as AudioStreamWAV
	if beam_stream:
		beam_stream.loop_mode = AudioStreamWAV.LOOP_FORWARD
		beam_stream.loop_end = beam_stream.data.size() / 2
		_beam_audio.stream = beam_stream
	add_child(_beam_audio)


# ── Actors ────────────────────────────────────────────────────────────────────

func register_actor(id: String, team: int, get_center: Callable, get_vel: Callable, is_alive: Callable, hurt: Callable, get_hp: Callable = Callable(), max_hp: int = 3) -> void:
	## get_center() -> Vector2 (px), get_vel() -> Vector2 (px/s),
	## is_alive() -> bool, hurt(dmg: int, dir: Vector2) -> void,
	## get_hp() -> int (for the floating HP bar)
	_actors[id] = {
		"team": team, "get_center": get_center, "get_vel": get_vel,
		"is_alive": is_alive, "hurt": hurt, "get_hp": get_hp, "max_hp": max_hp,
		"weapon": "", "cooldown": 0.0, "aim": Vector2.RIGHT,
		"weapon_left": -1.0, "beam_on": false, "beam_end": Vector2.ZERO, "beam_tick": 0.0,
		"dash_cd": 0.0, "dash_time": 0.0,
		"shield_req": false, "shield_on": false, "shield_energy": SHIELD_MAX,
		"stun_left": 0.0,
	}


func set_aim(id: String, dir: Vector2) -> void:
	if _actors.has(id) and dir.length() > 0.01:
		_actors[id].aim = dir.normalized()


func give_weapon(id: String, weapon: String) -> void:
	if _actors.has(id) and WEAPONS.has(weapon):
		_actors[id].weapon = weapon
		_actors[id].cooldown = 0.15
		_actors[id].weapon_left = WEAPONS[weapon].get("duration", -1.0)


func strip_weapon(id: String) -> void:
	if _actors.has(id):
		_actors[id].weapon = ""
		_actors[id].beam_on = false


func is_super_available() -> bool:
	return _super_state == 2


func get_super_status() -> String:
	match _super_state:
		0: return "DOOM RAY in %ds" % int(ceil(_super_timer))
		1: return "DOOM RAY INCOMING!"
		_: return "DOOM RAY ON THE FIELD!"


func get_weapon(id: String) -> String:
	return _actors[id].weapon if _actors.has(id) else ""


func get_weapon_color(id: String) -> Color:
	var w: String = get_weapon(id)
	return WEAPONS[w].color if WEAPONS.has(w) else Color.WHITE


func try_shoot(id: String) -> bool:
	if not _actors.has(id):
		return false
	var a: Dictionary = _actors[id]
	if a.weapon == "" or a.cooldown > 0.0 or not a.is_alive.call():
		return false
	if a.stun_left > 0.0:
		return false  # Parried — no shooting while stunned
	var w: Dictionary = WEAPONS[a.weapon]
	if w.get("beam", false):
		# Beam weapons fire continuously: request the beam for this frame
		a.beam_on = true
		return true
	a.cooldown = w.cooldown
	var center: Vector2 = a.get_center.call()
	var muzzle: Vector2 = center + a.aim * 18.0
	for i in range(w.count):
		var ang: float = a.aim.angle() + randfn(0.0, 0.0001 + w.spread)
		var dir: Vector2 = Vector2.from_angle(ang)
		_projectiles.append({
			"pos": muzzle, "vel": dir * w.speed * randf_range(0.95, 1.05),
			"team": a.team, "dmg": w.dmg, "life": w.life,
			"color": w.color, "size": w.size,
		})
	# Muzzle flash sparks
	for _i in range(7):
		var sdir: Vector2 = a.aim.rotated(randf_range(-0.55, 0.55))
		_fx.append({
			"pos": muzzle, "vel": sdir * randf_range(120.0, 340.0),
			"life": randf_range(0.05, 0.14), "max_life": 0.14,
			"color": w.color, "size": randf_range(1.5, 3.0),
		})
	_fx.append({
		"pos": muzzle, "vel": Vector2.ZERO, "life": 0.06, "max_life": 0.06,
		"color": Color(1, 1, 1), "size": 7.0,
	})
	play_sfx(w.sfx, muzzle)
	GameState.cam_shake += w.shake
	return true


func get_kick(id: String) -> float:
	## Recoil impulse (EE speed units) for the actor's current weapon.
	var w: String = get_weapon(id)
	return WEAPONS[w].kick if WEAPONS.has(w) else 0.0


# ── Unarmed melee: dash punch + parry shield ─────────────────────────────────

func try_dash(id: String) -> bool:
	## Unarmed lunge toward the aim direction. The CALLER applies the movement
	## impulse on success; contact damage is handled here during DASH_WINDOW.
	if not _actors.has(id):
		return false
	var a: Dictionary = _actors[id]
	if a.weapon != "" or a.dash_cd > 0.0 or a.stun_left > 0.0 or not a.is_alive.call():
		return false
	a.dash_cd = DASH_CD
	a.dash_time = DASH_WINDOW
	var c: Vector2 = a.get_center.call()
	for _i in range(10):
		var side: Vector2 = Vector2(-a.aim.y, a.aim.x) * randf_range(-4.0, 4.0)
		_fx.append({
			"pos": c - a.aim * randf_range(2.0, 10.0) + side,
			"vel": -a.aim * randf_range(60.0, 180.0),
			"life": randf_range(0.08, 0.2), "max_life": 0.2,
			"color": Color(0.6, 0.9, 1.0), "size": randf_range(1.2, 2.6),
		})
	play_sfx("shoot_scatter", c, 0.05, 1.7)
	GameState.cam_shake += 1.4
	return true


func set_shield(id: String, want: bool) -> void:
	if _actors.has(id):
		_actors[id].shield_req = want


func is_shielded(id: String) -> bool:
	return _actors.has(id) and _actors[id].shield_on


func is_stunned(id: String) -> bool:
	return _actors.has(id) and _actors[id].stun_left > 0.0


func _stun_team(team: int, at: Vector2) -> void:
	## Parry payoff: stun every enemy-team actor (1v1: the attacker).
	for id in _actors:
		var a: Dictionary = _actors[id]
		if a.team == team:
			a.stun_left = STUN_TIME
			a.beam_on = false
	for _i in range(16):
		var ang: float = randf() * TAU
		_fx.append({
			"pos": at, "vel": Vector2.from_angle(ang) * randf_range(90.0, 260.0),
			"life": randf_range(0.1, 0.3), "max_life": 0.3,
			"color": Color(0.7, 0.95, 1.0), "size": randf_range(1.4, 3.0),
		})
	# PARRY! Double shockwave ring + flash
	spawn_ring(at, Color(0.6, 0.95, 1.0), 6.0, 34.0, 0.3)
	spawn_ring(at, Color(1.0, 1.0, 1.0), 3.0, 20.0, 0.18)
	_fx.append({
		"pos": at, "vel": Vector2.ZERO, "life": 0.08, "max_life": 0.08,
		"color": Color(1, 1, 1), "size": 12.0,
	})
	play_sfx("pickup", at, 0.03, 1.7)
	GameState.cam_shake += 4.5


# ── Pickups ───────────────────────────────────────────────────────────────────

func add_pad(pos: Vector2, weapon: String) -> void:
	_pads.append({"pos": pos, "weapon": weapon, "respawn_left": 0.0, "phase": randf() * TAU})


# ── FX helpers ────────────────────────────────────────────────────────────────

func spawn_explosion(pos: Vector2, color: Color) -> void:
	for _i in range(46):
		var ang: float = randf() * TAU
		var spd: float = randf_range(60.0, 420.0)
		_fx.append({
			"pos": pos, "vel": Vector2.from_angle(ang) * spd,
			"life": randf_range(0.15, 0.55), "max_life": 0.55,
			"color": color.lerp(Color(1, 0.9, 0.5), randf() * 0.6),
			"size": randf_range(1.5, 4.0),
		})
	_fx.append({
		"pos": pos, "vel": Vector2.ZERO, "life": 0.1, "max_life": 0.1,
		"color": Color(1, 1, 1), "size": 16.0,
	})
	play_sfx("explode", pos)
	GameState.cam_shake += 7.0


func spawn_hit(pos: Vector2, color: Color, dir: Vector2) -> void:
	for _i in range(10):
		var sdir: Vector2 = (-dir).rotated(randf_range(-0.8, 0.8))
		_fx.append({
			"pos": pos, "vel": sdir * randf_range(80.0, 280.0),
			"life": randf_range(0.08, 0.22), "max_life": 0.22,
			"color": color, "size": randf_range(1.2, 2.6),
		})


func spawn_trail_dot(pos: Vector2, vel: Vector2, color: Color) -> void:
	_fx.append({
		"pos": pos, "vel": vel, "life": randf_range(0.08, 0.2), "max_life": 0.2,
		"color": color, "size": randf_range(1.0, 2.2),
	})


func spawn_ring(pos: Vector2, color: Color, r0: float = 6.0, r1: float = 30.0, life: float = 0.25) -> void:
	## Expanding shockwave ring (parries, impacts, materializations).
	_fx.append({
		"pos": pos, "vel": Vector2.ZERO, "life": life, "max_life": life,
		"color": color, "size": 0.0, "ring": true, "r0": r0, "r1": r1,
	})


func play_sfx(name: String, pos: Vector2, pitch_jitter: float = 0.08, pitch_base: float = 1.0) -> void:
	if not _sfx.has(name):
		return
	var p: AudioStreamPlayer2D = _sfx_pool[_sfx_next]
	_sfx_next = (_sfx_next + 1) % _sfx_pool.size()
	p.stream = _sfx[name]
	p.global_position = pos
	p.pitch_scale = pitch_base + randf_range(-pitch_jitter, pitch_jitter)
	p.play()


# ── Simulation ────────────────────────────────────────────────────────────────

func _process(delta: float) -> void:
	_time += delta
	# Cooldowns + timed weapons (the DOOM RAY expires)
	for id in _actors:
		var a: Dictionary = _actors[id]
		if a.cooldown > 0.0:
			a.cooldown = maxf(0.0, a.cooldown - delta)
		# Melee kit timers
		if a.dash_cd > 0.0:
			a.dash_cd = maxf(0.0, a.dash_cd - delta)
		if a.dash_time > 0.0:
			a.dash_time = maxf(0.0, a.dash_time - delta)
		if a.stun_left > 0.0:
			a.stun_left = maxf(0.0, a.stun_left - delta)
		# Shield: only while unarmed, drains on use, regens when down
		var was_shielded: bool = a.shield_on
		a.shield_on = a.shield_req and a.weapon == "" and a.stun_left <= 0.0 and a.shield_energy > 0.05 and a.is_alive.call()
		if a.shield_on and not was_shielded:
			play_sfx("pickup", a.get_center.call(), 0.03, 0.7)  # Shield hum-up
			spawn_ring(a.get_center.call(), Color(0.5, 0.9, 1.0), 4.0, 15.0, 0.15)
		elif was_shielded and not a.shield_on and a.shield_energy <= 0.05:
			play_sfx("hit", a.get_center.call(), 0.05, 0.55)  # Shield fizzles out
			spawn_ring(a.get_center.call(), Color(0.4, 0.6, 0.8), 13.0, 4.0, 0.2)
		if a.shield_on:
			a.shield_energy = maxf(0.0, a.shield_energy - delta)
		else:
			a.shield_energy = minf(SHIELD_MAX, a.shield_energy + delta * 0.6)
		# Dash afterimages: a bright motion trail while the punch window is live
		if a.dash_time > 0.0 and a.is_alive.call():
			var dc: Vector2 = a.get_center.call()
			_fx.append({
				"pos": dc, "vel": Vector2.ZERO, "life": 0.16, "max_life": 0.16,
				"color": Color(0.55, 0.85, 1.0), "size": 6.0,
			})
	# Dash contact: damage on touch, or get PARRIED by a raised shield
	for id in _actors:
		var a: Dictionary = _actors[id]
		if a.dash_time <= 0.0 or not a.is_alive.call():
			continue
		var ac: Vector2 = a.get_center.call()
		for vid in _actors:
			var v: Dictionary = _actors[vid]
			if v.team == a.team or not v.is_alive.call():
				continue
			var vc: Vector2 = v.get_center.call()
			if ac.distance_to(vc) < 16.0:
				a.dash_time = 0.0
				if v.shield_on:
					_stun_team(a.team, (ac + vc) * 0.5)  # PARRIED!
				else:
					v.hurt.call(DASH_DMG, (vc - ac).normalized())
					spawn_hit((ac + vc) * 0.5, Color(0.7, 0.95, 1.0), (vc - ac).normalized())
					spawn_ring((ac + vc) * 0.5, Color(0.7, 0.95, 1.0), 4.0, 20.0, 0.2)
					play_sfx("hit", vc)
					GameState.cam_shake += 3.0
				break
		if a.weapon != "" and a.weapon_left > 0.0:
			a.weapon_left -= delta
			if a.weapon_left <= 0.0:
				var fizzle_c: Vector2 = a.get_center.call()
				for _i in range(16):
					var fang: float = randf() * TAU
					_fx.append({
						"pos": fizzle_c, "vel": Vector2.from_angle(fang) * randf_range(30.0, 140.0),
						"life": randf_range(0.1, 0.3), "max_life": 0.3,
						"color": WEAPONS[a.weapon].color, "size": randf_range(1.0, 2.4),
					})
				play_sfx("pickup", fizzle_c, 0.02)
				strip_weapon(id)
	# Super weapon cycle: countdown -> materialize animation -> pad on field
	if super_pos != Vector2.ZERO:
		if _super_state == 0:
			_super_timer -= delta
			if _super_timer <= 0.0:
				_super_state = 1
				_super_anim = SUPER_ANIM_TIME
				play_sfx("doom_spawn", super_pos, 0.0)
		elif _super_state == 1:
			_super_anim -= delta
			# Converging energy: particles spiral into the spawn point
			var burst: int = clampi(int(delta * 260.0), 2, 14)
			for _i in range(burst):
				var sang: float = randf() * TAU
				var r: float = randf_range(50.0, 150.0)
				var p: Vector2 = super_pos + Vector2.from_angle(sang) * r
				_fx.append({
					"pos": p, "vel": (super_pos - p) / maxf(_super_anim, 0.25),
					"life": randf_range(0.15, minf(_super_anim + 0.1, 0.5)), "max_life": 0.5,
					"color": Color(1.0, 0.25, 0.15).lerp(Color(1, 0.8, 0.4), randf()),
					"size": randf_range(1.2, 3.0),
				})
			GameState.cam_shake = maxf(GameState.cam_shake, 1.5 * (1.0 - _super_anim / SUPER_ANIM_TIME))
			if _super_anim <= 0.0:
				_super_state = 2
				_pads.append({"pos": super_pos, "weapon": "doom", "respawn_left": 0.0, "phase": 0.0, "super": true})
				spawn_explosion(super_pos, Color(1.0, 0.3, 0.15))
				spawn_ring(super_pos, Color(1.0, 0.4, 0.2), 8.0, 60.0, 0.45)
				spawn_ring(super_pos, Color(1.0, 0.8, 0.5), 4.0, 34.0, 0.3)
	# Pickups
	for pi in range(_pads.size() - 1, -1, -1):
		var pad: Dictionary = _pads[pi]
		if pad.respawn_left > 0.0:
			pad.respawn_left = maxf(0.0, pad.respawn_left - delta)
			continue
		for id in _actors:
			var a: Dictionary = _actors[id]
			if not a.is_alive.call():
				continue
			var c: Vector2 = a.get_center.call()
			if c.distance_to(pad.pos) < PICKUP_RADIUS:
				give_weapon(id, pad.weapon)
				play_sfx("pickup", pad.pos, 0.03)
				var wcol: Color = WEAPONS[pad.weapon].color
				for _i in range(14):
					var ang: float = randf() * TAU
					_fx.append({
						"pos": pad.pos, "vel": Vector2.from_angle(ang) * randf_range(50.0, 180.0),
						"life": randf_range(0.15, 0.35), "max_life": 0.35,
						"color": wcol, "size": randf_range(1.2, 2.6),
					})
				if pad.get("super", false):
					# Supers don't refill in place — restart the 60s cycle
					_pads.remove_at(pi)
					_super_state = 0
					_super_timer = SUPER_PERIOD
				else:
					pad.respawn_left = PICKUP_RESPAWN
				break
	# DOOM RAY beams: raycast, continuous damage ticks, heavy presence.
	# beam_on is a per-frame request (re-issued by holders every frame);
	# beam_draw is what _draw renders this frame.
	var any_beam: bool = false
	for id in _actors:
		_actors[id]["beam_draw"] = false
	for id in _actors:
		var a: Dictionary = _actors[id]
		if not a.beam_on:
			continue
		a.beam_on = false
		if a.weapon == "" or not WEAPONS[a.weapon].get("beam", false) or not a.is_alive.call():
			continue
		a.beam_draw = true
		any_beam = true
		var w: Dictionary = WEAPONS[a.weapon]
		var from: Vector2 = a.get_center.call() + a.aim * 16.0
		var beam_end: Vector2 = from
		var victim: Dictionary = {}
		var steps: int = int(w.range / 6.0)
		for s in range(steps):
			beam_end = from + a.aim * (s * 6.0)
			if WorldManager.is_solid_at(int(floor(beam_end.x / 16.0)), int(floor(beam_end.y / 16.0))):
				break
			for vid in _actors:
				var v: Dictionary = _actors[vid]
				if v.team == a.team or not v.is_alive.call():
					continue
				if v.get_center.call().distance_squared_to(beam_end) < 144.0:
					victim = v
			if not victim.is_empty():
				break
		a.beam_end = beam_end
		# Sparks along the beam + at the impact point
		if randf() < delta * 240.0:
			var bt: float = randf()
			_fx.append({
				"pos": from.lerp(beam_end, bt), "vel": Vector2(randf_range(-40, 40), randf_range(-40, 40)),
				"life": randf_range(0.05, 0.14), "max_life": 0.14,
				"color": Color(1.0, randf_range(0.3, 0.8), 0.2), "size": randf_range(1.0, 2.4),
			})
		spawn_hit(beam_end, Color(1.0, 0.4, 0.2), a.aim)
		GameState.cam_shake = maxf(GameState.cam_shake, 2.5)
		a.beam_tick -= delta
		if a.beam_tick <= 0.0:
			a.beam_tick = w.tick
			if not victim.is_empty():
				if victim.shield_on:
					# Even the DOOM RAY respects a parry
					_stun_team(a.team, beam_end)
				else:
					victim.hurt.call(w.dmg, a.aim)
					play_sfx("hit", beam_end)
	if _beam_audio and _beam_audio.stream:
		if any_beam and not _beam_audio.playing:
			_beam_audio.play()
		elif not any_beam and _beam_audio.playing:
			_beam_audio.stop()
	if any_beam:
		# Position the hum at the first active beam's muzzle
		for id in _actors:
			if _actors[id].get("beam_draw", false):
				_beam_audio.global_position = _actors[id].get_center.call()
				break
	# Projectiles (substepped so fast shots can't skip through walls/players)
	var world_max: Vector2 = Vector2(WorldManager.world_width * 16.0 + 64.0, WorldManager.world_height * 16.0 + 64.0)
	var i: int = _projectiles.size() - 1
	while i >= 0:
		var pr: Dictionary = _projectiles[i]
		pr.life -= delta
		var alive: bool = pr.life > 0.0
		if alive:
			var move: Vector2 = pr.vel * delta
			var steps: int = maxi(1, int(ceil(move.length() / 4.0)))
			for s in range(steps):
				pr.pos += move / float(steps)
				# Trail glow
				if randf() < 0.5:
					spawn_trail_dot(pr.pos, -pr.vel * 0.05, pr.color)
				# World bounds
				if pr.pos.x < -64.0 or pr.pos.y < -64.0 or pr.pos.x > world_max.x or pr.pos.y > world_max.y:
					alive = false
					break
				# Grid tiles
				if WorldManager.is_solid_at(int(floor(pr.pos.x / 16.0)), int(floor(pr.pos.y / 16.0))):
					spawn_hit(pr.pos, pr.color, pr.vel.normalized())
					play_sfx("hit", pr.pos)
					alive = false
					break
				# Curves
				if WorldManager.polylines.size() > 0 and WorldManager.dist_to_nearest_polyline(pr.pos.x, pr.pos.y) < CURVE_HIT_DIST:
					spawn_hit(pr.pos, pr.color, pr.vel.normalized())
					play_sfx("hit", pr.pos)
					alive = false
					break
				# Actors (enemy team only)
				for id in _actors:
					var a: Dictionary = _actors[id]
					if a.team == pr.team or not a.is_alive.call():
						continue
					var c: Vector2 = a.get_center.call()
					var hit_r: float = 14.0 if a.shield_on else ACTOR_RADIUS
					if c.distance_squared_to(pr.pos) < hit_r * hit_r:
						if a.shield_on:
							# PARRY: shot blocked, shooter stunned for 1s
							_stun_team(pr.team, pr.pos)
						else:
							a.hurt.call(pr.dmg, pr.vel.normalized())
							spawn_hit(pr.pos, pr.color, pr.vel.normalized())
							play_sfx("hit", pr.pos)
							GameState.cam_shake += 2.0
						alive = false
						break
				if not alive:
					break
		if not alive:
			_projectiles.remove_at(i)
		i -= 1
	# FX particles
	var j: int = _fx.size() - 1
	while j >= 0:
		var f: Dictionary = _fx[j]
		f.life -= delta
		if f.life <= 0.0:
			_fx.remove_at(j)
		else:
			f.pos += f.vel * delta
			f.vel *= pow(0.04, delta)  # Strong drag, embers hang briefly
		j -= 1
	if _fx.size() > 1600:
		_fx.resize(1600)
	queue_redraw()


# ── Rendering ────────────────────────────────────────────────────────────────

func _draw() -> void:
	# Super weapon materialization: growing ring + light pillar
	if _super_state == 1 and super_pos != Vector2.ZERO:
		var prog: float = 1.0 - _super_anim / SUPER_ANIM_TIME
		var scol: Color = Color(1.0, 0.3, 0.15)
		draw_arc(super_pos, 40.0 - 26.0 * prog, 0, TAU, 32, Color(scol.r, scol.g, scol.b, 0.25 + 0.6 * prog), 2.0 + 3.0 * prog)
		draw_rect(Rect2(super_pos.x - 1.5 - 2.0 * prog, super_pos.y - 220.0, 3.0 + 4.0 * prog, 220.0), Color(1.0, 0.5, 0.3, 0.12 + 0.3 * prog))
		draw_circle(super_pos, 4.0 + 8.0 * prog, Color(1, 0.8, 0.6, 0.5 * prog))
	# Pickup pads
	for pad in _pads:
		var w: Dictionary = WEAPONS[pad.weapon]
		var col: Color = w.color
		if pad.get("super", false):
			# The DOOM RAY pad: big double ring, fast pulse, light pillar
			var spulse: float = 0.5 + 0.5 * sin(_time * 7.0)
			draw_arc(pad.pos, 16.0 + spulse * 4.0, 0, TAU, 32, Color(1.0, 0.25, 0.15, 0.5 + 0.4 * spulse), 2.5)
			draw_arc(pad.pos, 24.0 + spulse * 2.0, 0, TAU, 32, Color(1.0, 0.6, 0.2, 0.25), 1.5)
			draw_rect(Rect2(pad.pos.x - 1.0, pad.pos.y - 180.0, 2.0, 180.0), Color(1.0, 0.4, 0.2, 0.1 + 0.1 * spulse))
			_draw_gun(pad.pos + Vector2(0, -8 + sin(_time * 3.0) * 3.0), Vector2.RIGHT, "doom", 1.1 + spulse * 0.15)
			continue
		if pad.respawn_left > 0.0:
			# Refilling: dim ring with progress arc
			var frac: float = 1.0 - pad.respawn_left / PICKUP_RESPAWN
			draw_arc(pad.pos, 11.0, 0, TAU, 24, Color(col.r, col.g, col.b, 0.18), 1.5)
			draw_arc(pad.pos, 11.0, -PI / 2.0, -PI / 2.0 + TAU * frac, 24, Color(col.r, col.g, col.b, 0.5), 1.5)
		else:
			var pulse: float = 0.6 + 0.4 * sin(_time * 4.0 + pad.phase)
			var bob: float = sin(_time * 2.4 + pad.phase) * 3.0
			draw_arc(pad.pos, 11.0 + pulse * 2.0, 0, TAU, 24, Color(col.r, col.g, col.b, 0.35 + 0.3 * pulse), 1.8)
			draw_circle(pad.pos, 3.0 + pulse * 1.5, Color(col.r, col.g, col.b, 0.25))
			_draw_gun(pad.pos + Vector2(0, -6 + bob), Vector2.RIGHT, pad.weapon, 1.0 + pulse * 0.12)
	# Guns held by actors
	for id in _actors:
		var a: Dictionary = _actors[id]
		if a.weapon == "" or not a.is_alive.call():
			continue
		var c: Vector2 = a.get_center.call()
		var gun_pos: Vector2 = c + a.aim * 14.0
		_draw_gun(gun_pos, a.aim, a.weapon, 1.0)
		# Charge glow while cooling down (rail feels chunky)
		if a.cooldown > 0.0 and WEAPONS[a.weapon].cooldown > 0.5:
			var readiness: float = 1.0 - a.cooldown / WEAPONS[a.weapon].cooldown
			var wcol: Color = WEAPONS[a.weapon].color
			draw_arc(c, 13.0, -PI / 2.0, -PI / 2.0 + TAU * readiness, 20, Color(wcol.r, wcol.g, wcol.b, 0.5), 1.2)
	# DOOM RAY beams: layered core + glow + impact flare
	for id in _actors:
		var a: Dictionary = _actors[id]
		if not a.get("beam_draw", false):
			continue
		var from: Vector2 = a.get_center.call() + a.aim * 16.0
		var to: Vector2 = a.beam_end
		var flicker: float = 0.85 + 0.15 * sin(_time * 60.0)
		draw_line(from, to, Color(1.0, 0.2, 0.1, 0.35), 11.0 * flicker)
		draw_line(from, to, Color(1.0, 0.45, 0.15, 0.8), 5.5 * flicker)
		draw_line(from, to, Color(1, 1, 0.9), 2.2)
		draw_circle(to, 5.0 + 3.0 * flicker, Color(1.0, 0.7, 0.4, 0.8))
		draw_circle(from, 3.5, Color(1, 1, 0.9))
	# Shields and stun stars
	for id in _actors:
		var a: Dictionary = _actors[id]
		if not a.is_alive.call():
			continue
		var c: Vector2 = a.get_center.call()
		if a.shield_on:
			var sp: float = 0.6 + 0.4 * sin(_time * 10.0)
			var energy_frac: float = a.shield_energy / SHIELD_MAX
			draw_arc(c, 13.0, 0, TAU, 24, Color(0.5, 0.9, 1.0, 0.35 + 0.25 * sp), 2.2)
			draw_arc(c, 13.0, _time * 5.0, _time * 5.0 + TAU * 0.3, 10, Color(0.8, 1.0, 1.0, 0.8), 2.2)
			draw_arc(c, 16.0, -PI / 2.0, -PI / 2.0 + TAU * energy_frac, 20, Color(0.5, 0.9, 1.0, 0.4), 1.2)
		if a.stun_left > 0.0:
			for k in range(3):
				var sa: float = _time * 6.0 + k * TAU / 3.0
				var sp2: Vector2 = c + Vector2(cos(sa) * 11.0, -14.0 + sin(sa * 2.0) * 2.0)
				draw_circle(sp2, 1.6, Color(1.0, 0.9, 0.3))
	# Floating HP bars (small, above each living actor)
	for id in _actors:
		var a: Dictionary = _actors[id]
		if a.get_hp.is_null() or not a.is_alive.call():
			continue
		var hp: int = a.get_hp.call()
		var mx: int = a.max_hp
		if hp >= mx:
			continue  # Full HP: keep the screen clean
		var c: Vector2 = a.get_center.call()
		var bar_w: float = 18.0
		var seg_w: float = bar_w / float(mx)
		draw_rect(Rect2(c.x - bar_w * 0.5 - 1.0, c.y - 18.0, bar_w + 2.0, 5.0), Color(0.05, 0.05, 0.08, 0.75))
		for s in range(mx):
			var seg_col: Color
			if s < hp:
				seg_col = Color(1.0, 0.3, 0.2) if hp == 1 else Color(0.3, 1.0, 0.45)
			else:
				seg_col = Color(0.22, 0.22, 0.28)
			draw_rect(Rect2(c.x - bar_w * 0.5 + s * seg_w, c.y - 17.0, seg_w - 1.0, 3.0), seg_col)
	# Projectiles: bright core + colored glow
	for pr in _projectiles:
		var col: Color = pr.color
		var dir: Vector2 = pr.vel.normalized()
		draw_line(pr.pos - dir * pr.size * 3.0, pr.pos, Color(col.r, col.g, col.b, 0.5), pr.size * 1.4)
		draw_circle(pr.pos, pr.size, col)
		draw_circle(pr.pos, pr.size * 0.55, Color(1, 1, 1))
	# FX particles (opaque bright — same style as the fire trail)
	for f in _fx:
		var t: float = f.life / f.max_life
		if f.get("ring", false):
			# Expanding shockwave ring
			var radius: float = f.r0 + (f.r1 - f.r0) * (1.0 - t)
			var rc: Color = f.color
			draw_arc(f.pos, radius, 0, TAU, 28, Color(rc.r, rc.g, rc.b, t * 0.85), 2.0 + 2.0 * t)
			continue
		var col: Color = f.color
		if t > 0.66:
			col = col.lerp(Color(1, 1, 1), (t - 0.66) * 2.0)
		else:
			col = col.lerp(Color(0.25, 0.1, 0.08), (0.66 - t) * 0.9)
		var s: float = f.size * (0.5 + 0.5 * t)
		draw_rect(Rect2(f.pos - Vector2(s, s) * 0.5, Vector2(s, s)), col)


func _draw_gun(pos: Vector2, aim: Vector2, weapon: String, scale_f: float) -> void:
	## Neon vector gun, rotated to aim. Flips vertically when aiming left so it
	## never renders upside-down on a rolling ball.
	var w: Dictionary = WEAPONS[weapon]
	var col: Color = w.color
	var ang: float = aim.angle()
	var flip: float = -1.0 if absf(ang) > PI / 2.0 else 1.0
	draw_set_transform(pos, ang, Vector2(scale_f, scale_f * flip))
	var dark: Color = Color(col.r * 0.25, col.g * 0.25, col.b * 0.3)
	match weapon:
		"blaster":
			draw_rect(Rect2(-6, -3, 9, 6), dark)                    # body
			draw_rect(Rect2(3, -1.6, 8, 3.2), dark)                 # barrel
			draw_rect(Rect2(3, -0.9, 8, 1.8), col)                  # barrel glow
			draw_rect(Rect2(-5, -2, 6, 1.6), col * 0.8)             # top stripe
			draw_circle(Vector2(11, 0), 1.6, Color(1, 1, 0.85))     # tip
		"scatter":
			draw_rect(Rect2(-7, -3.5, 10, 7), dark)
			draw_rect(Rect2(3, -3.0, 7, 2.4), dark)                 # twin barrels
			draw_rect(Rect2(3, 0.6, 7, 2.4), dark)
			draw_rect(Rect2(3, -2.6, 7, 1.6), col)
			draw_rect(Rect2(3, 1.0, 7, 1.6), col)
			draw_circle(Vector2(-4, 0), 2.0, col * 0.7)             # drum
		"rail":
			draw_rect(Rect2(-8, -2.6, 12, 5.2), dark)
			draw_rect(Rect2(4, -1.2, 11, 2.4), dark)
			draw_rect(Rect2(4, -0.6, 11, 1.2), col)
			for k in range(3):                                       # coil rings
				draw_rect(Rect2(5.5 + k * 3.0, -2.2, 1.2, 4.4), col * 0.9)
			draw_circle(Vector2(15, 0), 1.8, Color(1, 1, 1))
		"doom":
			draw_rect(Rect2(-9, -4.5, 13, 9), dark)                  # heavy body
			draw_rect(Rect2(4, -3.0, 12, 6.0), dark)                 # wide barrel
			draw_rect(Rect2(4, -1.8, 12, 3.6), col)                  # burning core
			draw_rect(Rect2(4, -0.7, 12, 1.4), Color(1, 0.9, 0.7))   # white-hot center
			for k in range(2):                                       # vents
				draw_rect(Rect2(-6 + k * 4.0, -6.0, 2.0, 2.0), col * 0.9)
				draw_rect(Rect2(-6 + k * 4.0, 4.0, 2.0, 2.0), col * 0.9)
			draw_circle(Vector2(16.5, 0), 2.6, Color(1, 1, 0.9))
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
