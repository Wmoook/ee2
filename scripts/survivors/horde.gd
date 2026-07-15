class_name Horde
extends Node2D
## The corrupted smiley horde: hundreds of pooled enemies, EE coins (the
## XP), treasure chests, enemy shrapnel and spawn portals — all updated
## and drawn here in one canvas for speed. Enemies are the game's own
## ball sprite, corrupted with tints; minibosses are miniature Warden
## eye-cores. Everything reports back to SurvivorsMode via callbacks.

const CAP: int = 240

var enemies: Array = []
var coins: Array = []
var chests: Array = []
var eproj: Array = []       # Enemy shrapnel: {pos, vel, life, friendly}
var portals: Array = []     # Spawn-in FX: {pos, t, color}
var _fx: Array = []         # Sparks: {pos, vel, life, max_life, color, size}
var _time: float = 0.0
var _ball_tex: Texture2D
var mode: Node = null       # SurvivorsMode (callbacks)
var magnet_r: float = 70.0

var _sfx: Dictionary = {}
var _sfx_pool: Array = []
var _sfx_next: int = 0
var _sfx_gate: float = 0.0

# Every mob wears a REAL EE smiley (picked by eye from the sheet):
# glooms are the pale dead, fangs the burning and bloodthirsty, wisps the
# ghosts, bulwarks the armored, spikers the exploding freaks.
const TYPES: Dictionary = {
	"gloom":   {"hp": 3.0, "spd": 62.0, "acc": 230.0, "r": 8.0, "tint": Color(0.55, 0.62, 0.78), "coins": 1,
		"faces": [78, 39, 87, 119, 94, 12]},   # pale husk, shades, stone, mummy, cultist, ninja
	"fang":    {"hp": 2.0, "spd": 100.0, "acc": 330.0, "r": 7.5, "tint": Color(1.0, 0.42, 0.36), "coins": 1,
		"faces": [85, 110, 4, 109, 49, 147, 142]},  # fire head, red-eyes, rage, clown, vampire, devil, werewolf
	"bulwark": {"hp": 12.0, "spd": 40.0, "acc": 150.0, "r": 10.0, "tint": Color(0.58, 0.68, 0.8), "coins": 2,
		"faces": [35, 66, 90, 64, 156]},        # knight, helm, spartan, robot, dark visor
	"wisp":    {"hp": 2.0, "spd": 85.0, "acc": 300.0, "r": 7.0, "tint": Color(0.8, 0.55, 1.0), "coins": 3,
		"faces": [54, 141, 133]},               # pink ghost, white spirit, blue droplet
	"spiker":  {"hp": 4.0, "spd": 68.0, "acc": 240.0, "r": 8.5, "tint": Color(1.0, 0.76, 0.36), "coins": 2,
		"faces": [44, 45, 63, 118, 143, 10]},   # pumpkins, gasmask, zombie, fish freak, imp
	"jr":      {"hp": 90.0, "spd": 52.0, "acc": 190.0, "r": 16.0, "tint": Color(1.0, 0.35, 0.4), "coins": 8, "faces": []},
	"prime":   {"hp": 1200.0, "spd": 44.0, "acc": 170.0, "r": 30.0, "tint": Color(1.0, 0.85, 0.4), "coins": 40, "faces": []},
}
const SMILEY_SIZE: int = 26
const SMILEYS_PER_CHUNK: int = 157


var _smileys: Array = []


func _ready() -> void:
	z_index = 3
	_ball_tex = load("res://assets/sprites/NEW_SPRITES_BALL/BALL_1_frame1.png") as Texture2D
	for i in range(2):
		var st: Texture2D = load("res://assets/sprites/smileys_%d.png" % i) as Texture2D
		if st:
			_smileys.append(st)
	for n in ["hit", "explode", "pickup", "bonk", "shoot_scatter", "doom_spawn"]:
		var stream: AudioStream = load("res://assets/sfx/%s.wav" % n) as AudioStream
		if stream:
			_sfx[n] = stream
	for _i in range(8):
		var p: AudioStreamPlayer2D = AudioStreamPlayer2D.new()
		p.max_distance = 2400.0
		add_child(p)
		_sfx_pool.append(p)


func sfx(name: String, pos: Vector2, pitch: float = 1.0) -> void:
	if not _sfx.has(name) or _sfx_gate > 0.0:
		return
	_sfx_gate = 0.02
	var p: AudioStreamPlayer2D = _sfx_pool[_sfx_next]
	_sfx_next = (_sfx_next + 1) % _sfx_pool.size()
	p.stream = _sfx[name]
	p.global_position = pos
	p.pitch_scale = pitch + randf_range(-0.06, 0.06)
	p.play()


func spawn(type: String, pos: Vector2, hp_scale: float = 1.0, spd_scale: float = 1.0) -> void:
	if enemies.size() >= CAP and type != "jr" and type != "prime":
		return
	var t: Dictionary = TYPES[type]
	var faces: Array = t.get("faces", [])
	enemies.append({
		"type": type, "pos": pos, "vel": Vector2.ZERO,
		"hp": t.hp * hp_scale, "max_hp": t.hp * hp_scale,
		"spd": t.spd * spd_scale, "acc": t.acc, "r": t.r, "tint": t.tint,
		"face": faces[randi() % faces.size()] if faces.size() > 0 else -1,
		"t": randf() * TAU, "flash": 0.0, "lunge": randf_range(1.0, 2.4),
		"orbit": randf() * TAU, "shoot": randf_range(1.5, 2.5), "wob": randf() * TAU,
	})
	portals.append({"pos": pos, "t": 0.4, "color": Color(0.72, 0.35, 1.0) if type != "prime" else Color(1.0, 0.85, 0.4)})


func drop_coins(pos: Vector2, n: int) -> void:
	for _i in range(n):
		coins.append({
			"pos": pos, "vel": Vector2.from_angle(randf() * TAU) * randf_range(30.0, 110.0),
			"value": 1, "t": randf() * TAU, "life": 45.0,
		})


func drop_chest(pos: Vector2) -> void:
	chests.append({"pos": pos, "t": 0.0})
	sfx("doom_spawn", pos, 1.4)


func hurt(i: int, dmg: float, kb: Vector2 = Vector2.ZERO) -> void:
	if i < 0 or i >= enemies.size():
		return
	var e: Dictionary = enemies[i]
	e.hp -= dmg
	e.flash = 0.12
	var resist: float = 0.25 if e.type == "bulwark" else (0.05 if e.type == "jr" or e.type == "prime" else 1.0)
	e.vel += kb * resist
	if e.hp <= 0.0:
		_kill(i)


func _kill(i: int) -> void:
	var e: Dictionary = enemies[i]
	for _k in range(10):
		var a: float = randf() * TAU
		_fx.append({
			"pos": e.pos, "vel": Vector2.from_angle(a) * randf_range(50.0, 240.0),
			"life": randf_range(0.14, 0.35), "max_life": 0.35,
			"color": e.tint.lerp(Color(1, 1, 1), randf() * 0.5), "size": randf_range(1.4, 3.2),
		})
	sfx("explode", e.pos, 1.5 if e.r < 12.0 else 0.9)
	if e.type == "spiker":
		# Spikers burst into shrapnel — respect the cover islands!
		for k in range(6):
			var sa: float = TAU * float(k) / 6.0
			eproj.append({"pos": e.pos, "vel": Vector2.from_angle(sa) * 240.0, "life": 2.2, "friendly": false})
	drop_coins(e.pos, TYPES[e.type].coins)
	if e.type == "jr":
		drop_chest(e.pos)
	elif e.type == "prime":
		for _c in range(3):
			drop_chest(e.pos + Vector2(randf_range(-40, 40), randf_range(-40, 40)))
	if mode:
		mode.on_enemy_died(e.type, e.pos)
	enemies.remove_at(i)


func nearest_enemy(pos: Vector2, max_d: float) -> int:
	var best: int = -1
	var bd: float = max_d * max_d
	for i in range(enemies.size()):
		var d: float = enemies[i].pos.distance_squared_to(pos)
		if d < bd:
			bd = d
			best = i
	return best


func farthest_enemy(pos: Vector2, max_d: float) -> int:
	var best: int = -1
	var bd: float = 0.0
	var lim: float = max_d * max_d
	for i in range(enemies.size()):
		var d: float = enemies[i].pos.distance_squared_to(pos)
		if d > bd and d < lim:
			bd = d
			best = i
	return best


func _process(delta: float) -> void:
	_time += delta
	_sfx_gate = maxf(0.0, _sfx_gate - delta)
	if mode == null or mode.frozen():
		queue_redraw()
		return
	var pc: Vector2 = mode.player_center()
	# ── Enemies ──
	for i in range(enemies.size() - 1, -1, -1):
		var e: Dictionary = enemies[i]
		e.t += delta
		e.flash = maxf(0.0, e.flash - delta)
		var to_p: Vector2 = pc - e.pos
		var dist: float = to_p.length()
		var seek: Vector2 = to_p / maxf(dist, 0.01)
		var want: Vector2 = seek * e.spd
		match e.type:
			"fang":
				e.lunge -= delta
				if e.lunge <= 0.0 and dist < 340.0:
					e.lunge = randf_range(1.8, 2.6)
					e.vel = seek * e.spd * 3.1
			"wisp":
				e.orbit += delta * 1.7
				var ring: Vector2 = pc + Vector2.from_angle(e.orbit) * maxf(150.0 - e.t * 4.0, 40.0)
				want = (ring - e.pos).normalized() * e.spd * 1.4
			"jr":
				e.shoot -= delta
				if e.shoot <= 0.0:
					e.shoot = 2.6
					for k in range(8):
						var ja: float = TAU * float(k) / 8.0 + e.t
						eproj.append({"pos": e.pos, "vel": Vector2.from_angle(ja) * 200.0, "life": 3.0, "friendly": false})
					sfx("shoot_scatter", e.pos, 0.7)
			"prime":
				e.shoot -= delta
				if e.shoot <= 0.0:
					e.shoot = 1.7
					for k in range(12):
						var pa2: float = TAU * float(k) / 12.0 + e.t * 0.7
						eproj.append({"pos": e.pos, "vel": Vector2.from_angle(pa2) * 230.0, "life": 3.4, "friendly": false})
					for k2 in range(3):
						eproj.append({"pos": e.pos, "vel": seek.rotated((float(k2) - 1.0) * 0.22) * 330.0, "life": 3.0, "friendly": false})
					sfx("shoot_scatter", e.pos, 0.55)
		# Organic drift wobble so the swarm doesn't stack into a line
		want += seek.orthogonal() * sin(e.t * 2.1 + e.wob) * e.spd * 0.35
		e.vel = e.vel.move_toward(want, e.acc * delta)
		e.pos += e.vel * delta
		e.pos.x = clampf(e.pos.x, SurvivorsMap.MIN_X, SurvivorsMap.MAX_X)
		e.pos.y = clampf(e.pos.y, SurvivorsMap.MIN_Y, SurvivorsMap.MAX_Y)
		# Contact with the player
		if dist < e.r + 9.0:
			mode.on_contact(i)
	# ── Enemy shrapnel ──
	for i in range(eproj.size() - 1, -1, -1):
		var pr: Dictionary = eproj[i]
		pr.pos += pr.vel * delta
		pr.life -= delta
		var dead: bool = pr.life <= 0.0
		if not dead and WorldManager.is_solid_at(int(floor(pr.pos.x / 16.0)), int(floor(pr.pos.y / 16.0))):
			dead = true
			_fx.append({"pos": pr.pos, "vel": Vector2.ZERO, "life": 0.1, "max_life": 0.1, "color": Color(0.8, 0.6, 1.0), "size": 3.0})
		if not dead:
			if pr.friendly:
				# Parried shrapnel hurts the horde
				var hit_i: int = nearest_enemy(pr.pos, 14.0)
				if hit_i >= 0:
					hurt(hit_i, 3.0, pr.vel.normalized() * 60.0)
					dead = true
			elif pr.pos.distance_to(pc) < 10.0:
				dead = mode.on_shrapnel(pr)
		if dead:
			eproj.remove_at(i)
	# ── Coins (magnet + collect) ──
	for i in range(coins.size() - 1, -1, -1):
		var c: Dictionary = coins[i]
		c.t += delta
		c.life -= delta
		var d2: float = c.pos.distance_to(pc)
		if d2 < magnet_r:
			c.vel = c.vel.move_toward((pc - c.pos).normalized() * 520.0, 1600.0 * delta)
		else:
			c.vel = c.vel.move_toward(Vector2.ZERO, 260.0 * delta)
		c.pos += c.vel * delta
		if d2 < 14.0:
			mode.on_coin(c.value)
			sfx("pickup", c.pos, 1.7)
			coins.remove_at(i)
		elif c.life <= 0.0:
			coins.remove_at(i)
	# ── Chests ──
	for i in range(chests.size() - 1, -1, -1):
		var ch: Dictionary = chests[i]
		ch.t += delta
		if ch.pos.distance_to(pc) < 22.0:
			var cpos: Vector2 = ch.pos
			chests.remove_at(i)
			mode.on_chest(cpos)
	# ── FX + portals ──
	for i in range(_fx.size() - 1, -1, -1):
		var f: Dictionary = _fx[i]
		f.life -= delta
		f.pos += f.vel * delta
		f.vel *= pow(0.02, delta)
		if f.life <= 0.0:
			_fx.remove_at(i)
	for i in range(portals.size() - 1, -1, -1):
		portals[i].t -= delta
		if portals[i].t <= 0.0:
			portals.remove_at(i)
	queue_redraw()


func _draw() -> void:
	# Spawn portals
	for p in portals:
		var pf: float = 1.0 - p.t / 0.4
		draw_arc(p.pos, 6.0 + 18.0 * pf, 0, TAU, 20, Color(p.color.r, p.color.g, p.color.b, 1.0 - pf), 2.5)
	# Coins: spinning EE gold
	for c in coins:
		var w: float = absf(sin(c.t * 5.0))
		var fade: float = clampf(c.life / 3.0, 0.2, 1.0)
		draw_rect(Rect2(c.pos.x - 4.0 * w, c.pos.y - 5.0, 8.0 * w, 10.0), Color(1.0, 0.85, 0.25, fade))
		draw_rect(Rect2(c.pos.x - 2.4 * w, c.pos.y - 3.0, 4.8 * w, 6.0), Color(1.0, 0.95, 0.6, fade))
	# Chests: bobbing gold-rimmed treasure with light rays
	for ch in chests:
		var cp: Vector2 = ch.pos + Vector2(0.0, 3.0 * sin(ch.t * 2.6))
		for k in range(4):
			var ra: float = ch.t * 1.2 + TAU * float(k) / 4.0
			draw_line(cp, cp + Vector2.from_angle(ra) * (18.0 + 5.0 * sin(ch.t * 5.0)), Color(1.0, 0.9, 0.4, 0.35), 2.0)
		draw_rect(Rect2(cp.x - 9.0, cp.y - 7.0, 18.0, 14.0), Color(0.45, 0.26, 0.1))
		draw_rect(Rect2(cp.x - 9.0, cp.y - 7.0, 18.0, 14.0), Color(1.0, 0.85, 0.35), false, 2.0)
		draw_line(cp + Vector2(-9, -1), cp + Vector2(9, -1), Color(1.0, 0.85, 0.35), 2.0)
		draw_circle(cp + Vector2(0, -1), 2.2, Color(1.0, 0.95, 0.7))
	# Enemy shrapnel
	for pr in eproj:
		var pcol: Color = Color(0.5, 1.0, 0.6) if pr.friendly else Color(0.85, 0.5, 1.0)
		draw_circle(pr.pos, 3.4, pcol)
		draw_circle(pr.pos, 1.6, Color(1, 1, 1, 0.9))
	# Enemies
	for e in enemies:
		if e.type == "jr" or e.type == "prime":
			# Miniature Warden eye-cores
			var col: Color = e.tint
			var rr: float = e.r
			draw_circle(e.pos, rr + 4.0, Color(col.r, col.g, col.b, 0.12))
			for k in range(5):
				var aa: float = _time * 1.4 + TAU * float(k) / 5.0
				draw_arc(e.pos, rr + 2.0, aa, aa + TAU / 5.0 * 0.55, 6, col, 2.5)
			draw_circle(e.pos, rr - 3.0, Color(0.07, 0.05, 0.1, 0.95))
			draw_circle(e.pos, rr * 0.42, col)
			draw_circle(e.pos, rr * 0.2, Color(1, 1, 1))
			if e.flash > 0.0:
				draw_circle(e.pos, rr, Color(1, 1, 1, e.flash * 5.0))
			var bw: float = rr * 2.4
			draw_rect(Rect2(e.pos.x - bw / 2.0, e.pos.y - rr - 9.0, bw, 3.0), Color(0.05, 0.05, 0.08, 0.8))
			draw_rect(Rect2(e.pos.x - bw / 2.0, e.pos.y - rr - 9.0, bw * clampf(e.hp / e.max_hp, 0.0, 1.0), 3.0), col)
		else:
			# A real EE smiley, lightly corrupted toward its type tint
			var sz: float = e.r * 2.2
			var flash_add: float = e.flash * 4.0
			var base: Color = Color(1, 1, 1).lerp(e.tint, 0.22)
			var tint: Color = Color(base.r + flash_add, base.g + flash_add, base.b + flash_add)
			var rect: Rect2 = Rect2(e.pos.x - sz / 2.0, e.pos.y - sz / 2.0, sz, sz)
			var face: int = e.get("face", -1)
			var chunk: int = face / SMILEYS_PER_CHUNK
			if face >= 0 and chunk < _smileys.size():
				var lc: int = face % SMILEYS_PER_CHUNK
				draw_texture_rect_region(_smileys[chunk], rect, Rect2(lc * SMILEY_SIZE, 0, SMILEY_SIZE, SMILEY_SIZE), tint)
			elif _ball_tex:
				draw_texture_rect(_ball_tex, rect, false, tint)
			if e.type == "bulwark":
				draw_arc(e.pos, e.r + 3.0, 0, TAU, 14, Color(0.75, 0.85, 0.95, 0.8), 2.0)
			elif e.type == "spiker":
				for k in range(4):
					var spa: float = e.t * 2.0 + TAU * float(k) / 4.0
					var tip: Vector2 = e.pos + Vector2.from_angle(spa) * (e.r + 5.0)
					draw_line(e.pos + Vector2.from_angle(spa) * (e.r + 1.0), tip, Color(1.0, 0.8, 0.4), 2.0)
	# Sparks
	for f in _fx:
		var a: float = clampf(f.life / f.max_life, 0.0, 1.0)
		draw_circle(f.pos, f.size * a, Color(f.color.r, f.color.g, f.color.b, a))
