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
}

var _actors: Dictionary = {}      # id -> actor dict
var _pads: Array = []             # {pos, weapon, respawn_left, phase}
var _projectiles: Array = []      # {pos, vel, team, dmg, life, color, size}
var _fx: Array = []               # {pos, vel, life, max_life, color, size}
var _sfx: Dictionary = {}         # name -> AudioStream
var _sfx_pool: Array = []
var _sfx_next: int = 0
var _time: float = 0.0


func _ready() -> void:
	z_index = 3
	for n in ["shoot_blaster", "shoot_scatter", "shoot_rail", "hit", "explode", "pickup"]:
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


# ── Actors ────────────────────────────────────────────────────────────────────

func register_actor(id: String, team: int, get_center: Callable, get_vel: Callable, is_alive: Callable, hurt: Callable) -> void:
	## get_center() -> Vector2 (px), get_vel() -> Vector2 (px/s),
	## is_alive() -> bool, hurt(dmg: int, dir: Vector2) -> void
	_actors[id] = {
		"team": team, "get_center": get_center, "get_vel": get_vel,
		"is_alive": is_alive, "hurt": hurt,
		"weapon": "", "cooldown": 0.0, "aim": Vector2.RIGHT,
	}


func set_aim(id: String, dir: Vector2) -> void:
	if _actors.has(id) and dir.length() > 0.01:
		_actors[id].aim = dir.normalized()


func give_weapon(id: String, weapon: String) -> void:
	if _actors.has(id) and WEAPONS.has(weapon):
		_actors[id].weapon = weapon
		_actors[id].cooldown = 0.15


func strip_weapon(id: String) -> void:
	if _actors.has(id):
		_actors[id].weapon = ""


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
	var w: Dictionary = WEAPONS[a.weapon]
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


func play_sfx(name: String, pos: Vector2, pitch_jitter: float = 0.08) -> void:
	if not _sfx.has(name):
		return
	var p: AudioStreamPlayer2D = _sfx_pool[_sfx_next]
	_sfx_next = (_sfx_next + 1) % _sfx_pool.size()
	p.stream = _sfx[name]
	p.global_position = pos
	p.pitch_scale = 1.0 + randf_range(-pitch_jitter, pitch_jitter)
	p.play()


# ── Simulation ────────────────────────────────────────────────────────────────

func _process(delta: float) -> void:
	_time += delta
	# Cooldowns
	for id in _actors:
		var a: Dictionary = _actors[id]
		if a.cooldown > 0.0:
			a.cooldown = maxf(0.0, a.cooldown - delta)
	# Pickups
	for pad in _pads:
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
				pad.respawn_left = PICKUP_RESPAWN
				play_sfx("pickup", pad.pos, 0.03)
				var wcol: Color = WEAPONS[pad.weapon].color
				for _i in range(14):
					var ang: float = randf() * TAU
					_fx.append({
						"pos": pad.pos, "vel": Vector2.from_angle(ang) * randf_range(50.0, 180.0),
						"life": randf_range(0.15, 0.35), "max_life": 0.35,
						"color": wcol, "size": randf_range(1.2, 2.6),
					})
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
					if c.distance_squared_to(pr.pos) < ACTOR_RADIUS * ACTOR_RADIUS:
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
	# Pickup pads
	for pad in _pads:
		var w: Dictionary = WEAPONS[pad.weapon]
		var col: Color = w.color
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
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
