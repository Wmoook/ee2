class_name Arsenal
extends Node2D
## The auto-firing arsenal: every weapon aims and fires ITSELF — you fly,
## it fights. Each weapon has 5 levels. Also draws the player's active kit
## (parry shield ring, dash ghosts) and all projectiles/FX in one canvas.

var levels: Dictionary = {"blaster": 1, "nova": 0, "rail": 0, "sweep": 0, "aura": 0}
var cd: Dictionary = {"blaster": 0.5, "nova": 2.0, "rail": 3.0, "sweep": 6.0, "aura": 2.0}
var projectiles: Array = []   # {pos, vel, dmg, life, color, size, pierce}
var _flashes: Array = []      # Transient beams/rings: {a, b, t, max_t, color, width, ring}
var _fx: Array = []
var _time: float = 0.0
var _orbit_a: float = 0.0
var _sweep_t: float = 0.0     # >0 while the doom sweep is live
var _sweep_a: float = 0.0
var mode: Node = null
var horde: Horde = null
var shield_visual: float = -1.0   # Energy fraction while shield up (else -1)
var _sfx: Dictionary = {}
var _sfx_pool: Array = []
var _sfx_next: int = 0

const INFO: Dictionary = {
	"blaster": {"name": "AUTO BLASTER", "icon": "◎", "desc": "Orbiting gun snipes the nearest foe"},
	"nova": {"name": "SCATTER NOVA", "icon": "✹", "desc": "Radial pellet burst around you"},
	"rail": {"name": "RAIL LANCE", "icon": "→", "desc": "Piercing lance to the farthest foe"},
	"sweep": {"name": "DOOM SWEEP", "icon": "☄", "desc": "Rotating annihilation beam"},
	"aura": {"name": "BONK AURA", "icon": "◉", "desc": "Knockback shockwave pulse"},
}


func _ready() -> void:
	z_index = 3
	for n in ["shoot_blaster", "shoot_scatter", "shoot_rail", "doom_beam", "bonk", "hit"]:
		var stream: AudioStream = load("res://assets/sfx/%s.wav" % n) as AudioStream
		if stream:
			_sfx[n] = stream
	for _i in range(6):
		var p: AudioStreamPlayer2D = AudioStreamPlayer2D.new()
		p.max_distance = 2400.0
		add_child(p)
		_sfx_pool.append(p)


func sfx(name: String, pos: Vector2, pitch: float = 1.0) -> void:
	if not _sfx.has(name):
		return
	var p: AudioStreamPlayer2D = _sfx_pool[_sfx_next]
	_sfx_next = (_sfx_next + 1) % _sfx_pool.size()
	p.stream = _sfx[name]
	p.global_position = pos
	p.pitch_scale = pitch + randf_range(-0.05, 0.05)
	p.play()


func upgradeable() -> Array:
	var out: Array = []
	for id in levels:
		if levels[id] < 5:
			out.append(id)
	return out


func apply_upgrade(id: String) -> void:
	if levels.has(id):
		levels[id] = mini(5, levels[id] + 1)


func _process(delta: float) -> void:
	_time += delta
	if mode == null or horde == null or mode.frozen():
		queue_redraw()
		return
	var pc: Vector2 = mode.player_center()
	var cdm: float = mode.cd_mult()
	_orbit_a += delta * 2.2
	# ── AUTO BLASTER ──
	if levels.blaster > 0:
		cd.blaster -= delta
		if cd.blaster <= 0.0:
			var ti: int = horde.nearest_enemy(pc, 480.0)
			if ti >= 0:
				cd.blaster = (0.92 - 0.12 * levels.blaster) * cdm
				var gp: Vector2 = _gun_pos(pc)
				var aim: Vector2 = (horde.enemies[ti].pos - gp).normalized()
				var shots: int = 3 if levels.blaster >= 5 else 1
				for s in range(shots):
					var a2: Vector2 = aim.rotated((float(s) - float(shots - 1) * 0.5) * 0.14)
					projectiles.append({
						"pos": gp, "vel": a2 * 540.0, "dmg": 1.0 + 0.6 * levels.blaster,
						"life": 1.1, "color": Color(1.0, 0.62, 0.2), "size": 3.0, "pierce": 1,
					})
				for _m in range(4):
					_fx.append({"pos": gp, "vel": aim.rotated(randf_range(-0.5, 0.5)) * randf_range(90.0, 260.0), "life": 0.12, "max_life": 0.12, "color": Color(1.0, 0.7, 0.3), "size": 1.8})
				sfx("shoot_blaster", pc, 1.1)
	# ── SCATTER NOVA ──
	if levels.nova > 0:
		cd.nova -= delta
		if cd.nova <= 0.0:
			cd.nova = (4.4 - 0.42 * levels.nova) * cdm
			var n: int = 8 + 2 * levels.nova
			for k in range(n):
				var na: float = TAU * float(k) / float(n)
				projectiles.append({
					"pos": pc, "vel": Vector2.from_angle(na) * 310.0, "dmg": 1.0 + 0.4 * levels.nova,
					"life": 0.9, "color": Color(0.4, 0.9, 1.0), "size": 2.6, "pierce": 1,
				})
			_flashes.append({"a": pc, "b": pc, "t": 0.22, "max_t": 0.22, "color": Color(0.5, 0.95, 1.0), "width": 2.0, "ring": 60.0})
			sfx("shoot_scatter", pc, 1.0)
	# ── RAIL LANCE ──
	if levels.rail > 0:
		cd.rail -= delta
		if cd.rail <= 0.0:
			var fi: int = horde.farthest_enemy(pc, 620.0)
			if fi >= 0:
				cd.rail = (5.6 - 0.55 * levels.rail) * cdm
				var dir: Vector2 = (horde.enemies[fi].pos - pc).normalized()
				var endp: Vector2 = pc + dir * 680.0
				# Pierce EVERYTHING along the lance
				for i in range(horde.enemies.size() - 1, -1, -1):
					var ep: Vector2 = horde.enemies[i].pos
					var t2: float = clampf((ep - pc).dot(dir), 0.0, 680.0)
					if ep.distance_squared_to(pc + dir * t2) < 20.0 * 20.0:
						horde.hurt(i, 3.0 + 1.2 * levels.rail, dir * 220.0)
				_flashes.append({"a": pc, "b": endp, "t": 0.18, "max_t": 0.18, "color": Color(0.75, 0.5, 1.0), "width": 5.0, "ring": 0.0})
				_flashes.append({"a": pc, "b": endp, "t": 0.3, "max_t": 0.3, "color": Color(1, 1, 1), "width": 1.6, "ring": 0.0})
				sfx("shoot_rail", pc, 1.0)
	# ── DOOM SWEEP ──
	if levels.sweep > 0:
		if _sweep_t > 0.0:
			_sweep_t -= delta
			_sweep_a += delta * 2.4
			var send: Vector2 = pc + Vector2.from_angle(_sweep_a) * 230.0
			for i in range(horde.enemies.size() - 1, -1, -1):
				var ep2: Vector2 = horde.enemies[i].pos
				var seg: Vector2 = send - pc
				var tt: float = clampf((ep2 - pc).dot(seg) / seg.length_squared(), 0.0, 1.0)
				if ep2.distance_squared_to(pc + seg * tt) < 22.0 * 22.0:
					horde.hurt(i, (2.0 + float(levels.sweep)) * delta * 8.0, seg.normalized() * 40.0)
		else:
			cd.sweep -= delta
			if cd.sweep <= 0.0:
				cd.sweep = (13.0 - 1.1 * levels.sweep) * cdm
				_sweep_t = 2.4 + 0.35 * levels.sweep
				_sweep_a = randf() * TAU
				sfx("doom_beam", pc, 1.0)
	# ── BONK AURA ──
	if levels.aura > 0:
		cd.aura -= delta
		if cd.aura <= 0.0:
			cd.aura = (2.7 - 0.26 * levels.aura) * cdm
			var rad: float = 74.0 + 9.0 * levels.aura
			var hit_any: bool = false
			for i in range(horde.enemies.size() - 1, -1, -1):
				var e: Dictionary = horde.enemies[i]
				if e.pos.distance_to(pc) < rad + e.r:
					hit_any = true
					horde.hurt(i, 1.0 + 0.5 * levels.aura, (e.pos - pc).normalized() * 260.0)
			_flashes.append({"a": pc, "b": pc, "t": 0.28, "max_t": 0.28, "color": Color(0.85, 0.92, 1.0), "width": 3.0, "ring": rad})
			if hit_any:
				sfx("bonk", pc, 1.2)
	# ── Player projectiles vs the horde ──
	for i in range(projectiles.size() - 1, -1, -1):
		var pr: Dictionary = projectiles[i]
		pr.pos += pr.vel * delta
		pr.life -= delta
		var dead: bool = pr.life <= 0.0
		if not dead and WorldManager.is_solid_at(int(floor(pr.pos.x / 16.0)), int(floor(pr.pos.y / 16.0))):
			dead = true
		if not dead:
			for j in range(horde.enemies.size() - 1, -1, -1):
				var e2: Dictionary = horde.enemies[j]
				if e2.pos.distance_squared_to(pr.pos) < (e2.r + 4.0) * (e2.r + 4.0):
					horde.hurt(j, pr.dmg, pr.vel.normalized() * 120.0)
					pr.pierce -= 1
					if pr.pierce <= 0:
						dead = true
						break
		if dead:
			projectiles.remove_at(i)
	# ── FX decay ──
	for i in range(_flashes.size() - 1, -1, -1):
		_flashes[i].t -= delta
		if _flashes[i].t <= 0.0:
			_flashes.remove_at(i)
	for i in range(_fx.size() - 1, -1, -1):
		var f: Dictionary = _fx[i]
		f.life -= delta
		f.pos += f.vel * delta
		if f.life <= 0.0:
			_fx.remove_at(i)
	queue_redraw()


func _gun_pos(pc: Vector2) -> Vector2:
	return pc + Vector2.from_angle(_orbit_a) * 20.0


func _draw() -> void:
	if mode == null:
		return
	var pc: Vector2 = mode.player_center()
	# Doom sweep beam
	if _sweep_t > 0.0:
		var send: Vector2 = pc + Vector2.from_angle(_sweep_a) * 230.0
		var flicker: float = 0.85 + 0.15 * sin(_time * 60.0)
		draw_line(pc, send, Color(1.0, 0.25, 0.1, 0.2), 26.0 * flicker)
		draw_line(pc, send, Color(1.0, 0.45, 0.15, 0.55), 14.0 * flicker)
		draw_line(pc, send, Color(1.0, 0.85, 0.5), 6.0)
		draw_circle(send, 7.0, Color(1.0, 0.7, 0.4, 0.8))
	# Orbiting auto-gun
	if levels.blaster > 0:
		var gp: Vector2 = _gun_pos(pc)
		var aim_a: float = _orbit_a
		var ti: int = horde.nearest_enemy(pc, 480.0) if horde else -1
		if ti >= 0:
			aim_a = (horde.enemies[ti].pos - gp).angle()
		var d: Vector2 = Vector2.from_angle(aim_a)
		draw_line(gp - d * 3.0, gp + d * 7.0, Color(1.0, 0.62, 0.2), 3.5)
		draw_circle(gp - d * 3.0, 3.0, Color(0.9, 0.9, 1.0))
	# Projectiles
	for pr in projectiles:
		draw_circle(pr.pos, pr.size + 1.5, Color(pr.color.r, pr.color.g, pr.color.b, 0.35))
		draw_circle(pr.pos, pr.size, pr.color)
		draw_circle(pr.pos, pr.size * 0.45, Color(1, 1, 1, 0.9))
	# Beam/ring flashes
	for fl in _flashes:
		var a: float = fl.t / fl.max_t
		if fl.ring > 0.0:
			draw_arc(fl.a, fl.ring * (1.0 - a * 0.4), 0, TAU, 30, Color(fl.color.r, fl.color.g, fl.color.b, a), fl.width)
		else:
			draw_line(fl.a, fl.b, Color(fl.color.r, fl.color.g, fl.color.b, a), fl.width)
	# Player kit: parry shield
	if shield_visual >= 0.0:
		var sp: float = 0.6 + 0.4 * sin(_time * 10.0)
		draw_arc(pc, 13.0, 0, TAU, 24, Color(0.5, 0.9, 1.0, 0.35 + 0.25 * sp), 2.2)
		draw_arc(pc, 13.0, _time * 5.0, _time * 5.0 + TAU * 0.3, 10, Color(0.8, 1.0, 1.0, 0.85), 2.2)
		draw_arc(pc, 16.0, -PI / 2.0, -PI / 2.0 + TAU * shield_visual, 20, Color(0.5, 0.9, 1.0, 0.4), 1.2)
	# Sparks
	for f in _fx:
		var a2: float = clampf(f.life / f.max_life, 0.0, 1.0)
		draw_circle(f.pos, f.size * a2, Color(f.color.r, f.color.g, f.color.b, a2))
