class_name ZombiesMode
extends Node2D
## UNDEAD BUNKER — CoD Zombies, but it's a 2D EE ball game.
## Round-based survival: corrupted smiley-zombies pour in through plank
## windows, you earn $ per hit/kill/plank, spend it on wall guns, the
## MYSTERY BOX, and the vault door. Two gun slots + knife-dash + parry
## shield. Survive as many rounds as you can. Created by game_scene when
## GameState.zombies_mode is set (battle_mode gating applies: no edit/save).

const MAX_HP: int = 3
const TOUCH_IFRAMES: float = 0.9
const REGEN_DELAY: float = 5.0
const REGEN_TICK: float = 2.5
const PLANKS_MAX: int = 6
const CHEW_TIME: float = 1.1        # Seconds per plank ripped off
const REBUILD_TIME: float = 0.7     # Seconds per plank rebuilt (hold F)
const INTERACT_R: float = 34.0
const ALIVE_CAP: int = 22           # Max zombies on the field at once

const POINTS_HIT: int = 10
const POINTS_KILL: int = 60
const POINTS_MELEE_KILL: int = 130
const POINTS_PLANK: int = 10
const START_POINTS: int = 500

# Mystery box pool: weapon -> weight (doom is the jackpot)
const BOX_POOL: Dictionary = {
	"smg": 1.0, "scatter": 1.0, "rifle": 1.0, "blaster": 0.9,
	"rail": 0.8, "minigun": 0.7, "raygun": 0.55, "doom": 0.22,
}
# Full ammo pools per gun (box guns; wall guns carry their own in map data)
const AMMO_POOLS: Dictionary = {
	"pistol": 90, "smg": 180, "scatter": 60, "rifle": 60,
	"blaster": 150, "rail": 30, "minigun": 320, "raygun": 50,
}

var player: Node = null
var weapons: WeaponSystem = null

var points: int = START_POINTS
var round_num: int = 0
var kills: int = 0
var player_hp: int = MAX_HP
var _invuln: float = 0.0
var _since_hit: float = 999.0
var _regen_t: float = 0.0
var _over: bool = false

var _zombies: Dictionary = {}       # id -> zombie dict
var _purge: Array = []              # actor ids to unregister OUTSIDE weapon loops
var _zid: int = 0
var _to_spawn: int = 0
var _spawn_t: float = 0.0
var _round_break: float = 3.0
var _banner_t: float = 0.0
var _planks: Array = []             # per-window plank count
var _rebuild_t: float = 0.0
var _doors_open: Array = []         # per-door bought flag

# Atmosphere: parallax backdrop (per-zone skies) + ambient particles
var _backdrop: Node2D
var _stars: Array = []
var _fireflies: Array = []
var _cur_zone: String = ""
var _zone_label: Label
var _zone_t: float = 0.0

# Mystery box: 0 idle, 1 rolling, 2 result waiting
var _box_state: int = 0
var _box_t: float = 0.0
var _box_result: String = ""

var _lmb_was: bool = false
var _f_was: bool = false
var _prompt: String = ""
var _prompt_action: Callable = Callable()
var _time: float = 0.0

var _hud: CanvasLayer
var _points_label: Label
var _round_label: Label
var _hearts_label: Label
var _weapon_label: Label
var _kills_label: Label
var _prompt_label: Label
var _banner_label: Label
var _result_panel: PanelContainer
var _result_label: Label
var _result_sub: Label


func _ready() -> void:
	z_index = 3
	player = get_parent()._get_player(1)
	weapons = WeaponSystem.new()
	get_parent().add_child.call_deferred(weapons)
	for _w in ZombiesMap.WINDOWS:
		_planks.append(PLANKS_MAX)
	for _d in ZombiesMap.DOORS:
		_doors_open.append(false)
	# Backdrop layer (drawn behind the world tiles): zone skies, moon,
	# stars, city skyline. Plain Node2D + draw signal — no extra script.
	_backdrop = Node2D.new()
	_backdrop.z_index = -5
	add_child(_backdrop)
	_backdrop.draw.connect(_draw_backdrop)
	var srng: RandomNumberGenerator = RandomNumberGenerator.new()
	srng.seed = 1337
	for _i in range(70):
		_stars.append({
			"pos": Vector2(srng.randf_range(40.0, 2780.0), srng.randf_range(180.0, 420.0)),
			"tw": srng.randf_range(0.0, TAU), "s": srng.randf_range(0.8, 1.9),
		})
	for _i in range(16):
		_fireflies.append({
			"pos": Vector2(srng.randf_range(120.0, 900.0), srng.randf_range(300.0, 580.0)),
			"ph": srng.randf_range(0.0, TAU),
		})
	_build_hud()
	call_deferred("_wire_up")


func _wire_up() -> void:
	weapons.register_actor("player", 0,
		func() -> Vector2: return Vector2(player.physics.x + 8.0, player.physics.y + 8.0),
		func() -> Vector2: return Vector2(player.physics._speedX, player.physics._speedY) * EEPhysics.EE_TICK_FRAC * EEPhysics.TPS,
		func() -> bool: return is_instance_valid(player) and not player._is_dead and not _over,
		_hurt_player,
		func() -> int: return player_hp, MAX_HP,
		func() -> bool: return player.physics.is_grounded,
		func(v: Vector2) -> void:
			player.physics._speedX += v.x
			player.physics._speedY += v.y)
	# CoD kit: two gun slots (start: pistol), finite ammo, knife dash on 1
	weapons._actors["player"]["slot_guns"] = {2: "pistol", 3: ""}
	weapons._actors["player"]["ammo"] = {"pistol": AMMO_POOLS.pistol}
	weapons.select_slot("player", 2)


func _build_hud() -> void:
	_hud = CanvasLayer.new()
	add_child(_hud)

	_points_label = Label.new()
	_points_label.position = Vector2(18, 640)
	_points_label.add_theme_font_size_override("font_size", 26)
	_points_label.add_theme_color_override("font_color", Color(1.0, 0.85, 0.25))
	_points_label.add_theme_color_override("font_outline_color", Color(0.25, 0.15, 0.0))
	_points_label.add_theme_constant_override("outline_size", 5)
	_hud.add_child(_points_label)

	_round_label = Label.new()
	_round_label.position = Vector2(18, 12)
	_round_label.add_theme_font_size_override("font_size", 30)
	_round_label.add_theme_color_override("font_color", Color(0.85, 0.1, 0.1))
	_round_label.add_theme_color_override("font_outline_color", Color(0.15, 0.0, 0.0))
	_round_label.add_theme_constant_override("outline_size", 6)
	_hud.add_child(_round_label)

	_kills_label = Label.new()
	_kills_label.position = Vector2(18, 52)
	_kills_label.add_theme_font_size_override("font_size", 13)
	_kills_label.add_theme_color_override("font_color", Color(0.6, 0.62, 0.7))
	_hud.add_child(_kills_label)

	_hearts_label = Label.new()
	_hearts_label.position = Vector2(1090, 14)
	_hearts_label.add_theme_font_size_override("font_size", 24)
	_hearts_label.add_theme_color_override("font_color", Color(1.0, 0.3, 0.32))
	_hud.add_child(_hearts_label)

	_weapon_label = Label.new()
	_weapon_label.position = Vector2(960, 668)
	_weapon_label.add_theme_font_size_override("font_size", 17)
	_weapon_label.add_theme_color_override("font_color", Color(0.9, 0.92, 1.0))
	_hud.add_child(_weapon_label)

	_prompt_label = Label.new()
	_prompt_label.position = Vector2(0, 560)
	_prompt_label.custom_minimum_size = Vector2(1280, 0)
	_prompt_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_prompt_label.add_theme_font_size_override("font_size", 16)
	_prompt_label.add_theme_color_override("font_color", Color(1.0, 0.95, 0.6))
	_prompt_label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.8))
	_prompt_label.add_theme_constant_override("outline_size", 4)
	_hud.add_child(_prompt_label)

	_banner_label = Label.new()
	_banner_label.position = Vector2(0, 200)
	_banner_label.custom_minimum_size = Vector2(1280, 0)
	_banner_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_banner_label.add_theme_font_size_override("font_size", 64)
	_banner_label.add_theme_color_override("font_color", Color(0.9, 0.08, 0.08))
	_banner_label.add_theme_color_override("font_outline_color", Color(0.1, 0.0, 0.0))
	_banner_label.add_theme_constant_override("outline_size", 10)
	_banner_label.visible = false
	_hud.add_child(_banner_label)

	_zone_label = Label.new()
	_zone_label.position = Vector2(0, 90)
	_zone_label.custom_minimum_size = Vector2(1280, 0)
	_zone_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_zone_label.add_theme_font_size_override("font_size", 24)
	_zone_label.add_theme_color_override("font_color", Color(0.75, 0.8, 0.95))
	_zone_label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.85))
	_zone_label.add_theme_constant_override("outline_size", 6)
	_zone_label.visible = false
	_hud.add_child(_zone_label)

	_result_panel = PanelContainer.new()
	_result_panel.anchor_left = 0.5
	_result_panel.anchor_top = 0.5
	_result_panel.anchor_right = 0.5
	_result_panel.anchor_bottom = 0.5
	_result_panel.offset_left = -240.0
	_result_panel.offset_top = -130.0
	_result_panel.offset_right = 240.0
	_result_panel.offset_bottom = 130.0
	_result_panel.visible = false
	_hud.add_child(_result_panel)
	var rv: VBoxContainer = VBoxContainer.new()
	rv.add_theme_constant_override("separation", 10)
	_result_panel.add_child(rv)
	_result_label = Label.new()
	_result_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_result_label.add_theme_font_size_override("font_size", 34)
	_result_label.add_theme_color_override("font_color", Color(0.9, 0.12, 0.12))
	rv.add_child(_result_label)
	_result_sub = Label.new()
	_result_sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_result_sub.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_result_sub.add_theme_font_size_override("font_size", 15)
	_result_sub.add_theme_color_override("font_color", Color(0.8, 0.82, 0.9))
	rv.add_child(_result_sub)
	var retry: Button = EditorToolsDock.make_button("RETRY", Color(0.82, 0.42, 0.14))
	retry.custom_minimum_size = Vector2(0, 42)
	retry.pressed.connect(_retry)
	rv.add_child(retry)
	var menu: Button = EditorToolsDock.make_button("MAIN MENU", Color(0.4, 0.45, 0.6))
	menu.custom_minimum_size = Vector2(0, 36)
	menu.pressed.connect(_return_to_menu)
	rv.add_child(menu)


# ==================== Zombies ====================

func _spawn_zombie() -> void:
	# CoD-style spawn pressure: pick among the 3 windows nearest the player
	var pc: Vector2 = _player_center()
	var order: Array = []
	for i in range(ZombiesMap.WINDOWS.size()):
		order.append([ZombiesMap.WINDOWS[i].inside.distance_to(pc), i])
	order.sort()
	var win: int = order[randi() % 3][1]
	var spawns: Array = ZombiesMap.ZSPAWNS[win]
	var pos: Vector2 = spawns[randi() % spawns.size()] + Vector2(randf_range(-10, 10), randf_range(-10, 10))
	_zid += 1
	var id: String = "z%d" % _zid
	var hp: int = 2 + int(round_num * 1.4)
	var spd: float = (34.0 + minf(round_num * 5.0, 70.0)) * randf_range(0.85, 1.15)
	if round_num >= 4 and randf() < 0.2:
		spd *= 1.8  # sprinter
	var z: Dictionary = {
		"id": id, "pos": pos, "vel": Vector2.ZERO, "hp": hp, "max_hp": hp,
		"spd": spd, "r": 9.0, "state": 0, "win": win, "chew_t": 0.0,
		"enter_t": 0.0, "atk_cd": 0.0, "flash": 0.0, "bob": randf() * TAU,
		"stuck": 0.0,
	}
	_zombies[id] = z
	weapons.register_actor(id, 2,
		func() -> Vector2: return _zombies[id].pos if _zombies.has(id) else Vector2(-999, -999),
		func() -> Vector2: return _zombies[id].vel if _zombies.has(id) else Vector2.ZERO,
		func() -> bool: return _zombies.has(id) and _zombies[id].hp > 0,
		_hurt_zombie.bind(id),
		func() -> int: return int(_zombies[id].hp) if _zombies.has(id) else 0, hp,
		func() -> bool: return true,
		func(v: Vector2) -> void:
			if _zombies.has(id):
				_zombies[id].vel += v * (EEPhysics.EE_TICK_FRAC * EEPhysics.TPS))
	weapons._actors[id]["hit_radius"] = 10.0
	weapons.spawn_ring(pos, Color(0.45, 0.9, 0.3), 3.0, 18.0, 0.3)


func _hurt_zombie(dmg: int, dir: Vector2, id: String) -> void:
	if not _zombies.has(id) or _over:
		return
	var z: Dictionary = _zombies[id]
	if z.hp <= 0:
		return
	z.hp -= dmg
	z.flash = 0.14
	z.vel += dir * 60.0
	points += POINTS_HIT
	if z.hp <= 0:
		var melee: bool = weapons._actors.has("player") and weapons._actors["player"].dash_time > 0.0
		points += POINTS_MELEE_KILL if melee else POINTS_KILL
		kills += 1
		_kill_zombie(id)


func _kill_zombie(id: String) -> void:
	## Called from inside weapon_system's actor iteration (hurt callback) —
	## NEVER erase from weapons._actors here (modify-during-iteration).
	## The actor's is_alive() goes false immediately; the registry entry is
	## purged next frame in _process.
	var z: Dictionary = _zombies[id]
	weapons.spawn_explosion(z.pos, Color(0.5, 0.85, 0.25))
	weapons.play_sfx("explode", z.pos, 0.06, 1.7)
	_zombies.erase(id)
	_purge.append(id)


func _zombie_ai(delta: float) -> void:
	var pc: Vector2 = _player_center()
	var ids: Array = _zombies.keys()
	for id in ids:
		var z: Dictionary = _zombies[id]
		z.flash = maxf(0.0, z.flash - delta)
		z.atk_cd = maxf(0.0, z.atk_cd - delta)
		z.bob += delta * 3.0
		var stunned: bool = weapons.is_stunned(id)
		var w: Dictionary = ZombiesMap.WINDOWS[z.win]
		match int(z.state):
			0:  # OUTSIDE — drift to the window's outside anchor
				var tgt0: Vector2 = w.outside
				_steer(z, tgt0, delta, stunned, false)
				if z.pos.distance_to(tgt0) < 16.0:
					z.state = 1
			1:  # CHEW the planks (or walk in if they're gone)
				if _planks[z.win] <= 0:
					z.state = 2
					z.enter_t = 1.4
				elif not stunned:
					var anchor: Vector2 = w.outside
					z.pos = z.pos.lerp(anchor + Vector2(sin(z.bob * 7.0) * 2.0, cos(z.bob * 6.0) * 2.0), 6.0 * delta)
					z.chew_t += delta
					if z.chew_t >= CHEW_TIME:
						z.chew_t = 0.0
						_planks[z.win] = maxi(0, _planks[z.win] - 1)
						var rc: Vector2 = w.rect.get_center()
						weapons.play_sfx("bonk", rc, 0.07, 0.65)
						for _i in range(5):
							weapons._fx.append({
								"pos": rc, "vel": Vector2(randf_range(-90, 90), randf_range(-120, 20)),
								"life": randf_range(0.2, 0.45), "max_life": 0.45,
								"color": Color(0.55, 0.38, 0.2), "size": randf_range(1.5, 3.0),
							})
			2:  # ENTERING — glide through the opening (no wall collision)
				z.enter_t -= delta
				if not stunned:
					z.pos = z.pos.move_toward(w.inside, z.spd * 1.2 * delta)
				if z.enter_t <= 0.0 or z.pos.distance_to(w.inside) < 8.0:
					z.state = 3
			3:  # INSIDE — hunt the player
				_steer(z, pc, delta, stunned, true)
				# Claw the player
				if z.atk_cd <= 0.0 and z.pos.distance_to(pc) < z.r + 9.0 and not _over:
					z.atk_cd = 1.0
					_claw_player(z)
	# Separation so the horde doesn't stack into one mega-zombie
	for i in range(ids.size()):
		if not _zombies.has(ids[i]):
			continue
		var a: Dictionary = _zombies[ids[i]]
		for j in range(i + 1, ids.size()):
			if not _zombies.has(ids[j]):
				continue
			var b: Dictionary = _zombies[ids[j]]
			var dv: Vector2 = b.pos - a.pos
			var d: float = dv.length()
			if d > 0.01 and d < 15.0:
				var push: Vector2 = dv / d * (15.0 - d) * 3.0
				a.pos -= push * 0.5 * delta * 8.0
				b.pos += push * 0.5 * delta * 8.0


func _steer(z: Dictionary, tgt: Vector2, delta: float, stunned: bool, collide: bool) -> void:
	if stunned:
		z.vel = z.vel.move_toward(Vector2.ZERO, 300.0 * delta)
	else:
		var want: Vector2 = (tgt - z.pos).normalized() * z.spd
		want.y += sin(z.bob) * 8.0
		z.vel = z.vel.move_toward(want, 240.0 * delta)
	var step: Vector2 = z.vel * delta
	if not collide:
		z.pos += step
		return
	var nxt: Vector2 = z.pos + step
	if not _solid_ball(nxt, z.r):
		z.pos = nxt
		z.stuck = 0.0
	elif not _solid_ball(Vector2(nxt.x, z.pos.y), z.r):
		z.pos.x = nxt.x
		z.vel.y *= 0.4
		z.stuck += delta
	elif not _solid_ball(Vector2(z.pos.x, nxt.y), z.r):
		z.pos.y = nxt.y
		z.vel.x *= 0.4
		z.stuck += delta
	else:
		z.stuck += delta
		z.vel = z.vel.rotated(randf_range(-1.2, 1.2)) * 0.5
	if z.stuck > 1.6:
		# Wedged in a corner — hop toward the nearest open vertical
		z.stuck = 0.0
		z.vel = Vector2(randf_range(-40, 40), -z.spd)


func _solid_ball(p: Vector2, r: float) -> bool:
	for off in [Vector2(0, 0), Vector2(r, 0), Vector2(-r, 0), Vector2(0, r), Vector2(0, -r)]:
		var q: Vector2 = p + off
		if WorldManager.is_solid_at(int(floor(q.x / 16.0)), int(floor(q.y / 16.0))):
			return true
	return false


func _claw_player(z: Dictionary) -> void:
	if _invuln > 0.0 or weapons.is_shielded("player"):
		if weapons.is_shielded("player"):
			# Shield holds the claw off — chip the shield instead
			var pa: Dictionary = weapons._actors["player"]
			pa.shield_energy = maxf(0.0, pa.shield_energy - 0.5)
			weapons.spawn_hit(z.pos.lerp(_player_center(), 0.5), Color(0.5, 0.9, 1.0), Vector2.UP)
			weapons.play_sfx("bonk", z.pos, 0.05, 1.5)
		return
	_hurt_player(1, (_player_center() - z.pos).normalized())


func _hurt_player(dmg: int, dir: Vector2) -> void:
	if _over or _invuln > 0.0:
		return
	player_hp -= dmg
	_invuln = TOUCH_IFRAMES
	_since_hit = 0.0
	weapons.play_sfx("hit", _player_center(), 0.08, 0.8)
	weapons.spawn_hit(_player_center(), Color(1.0, 0.25, 0.2), dir)
	GameState.cam_shake += 5.0
	player.physics._speedX += dir.x * 4.0
	player.physics._speedY += dir.y * 4.0 - 2.0
	if player_hp <= 0:
		_game_over()


# ==================== Rounds ====================

func _round_logic(delta: float) -> void:
	if _banner_t > 0.0:
		_banner_t -= delta
		_banner_label.modulate.a = clampf(_banner_t / 0.8, 0.0, 1.0)
		if _banner_t <= 0.0:
			_banner_label.visible = false
	if _to_spawn <= 0 and _zombies.is_empty():
		_round_break -= delta
		if _round_break <= 0.0:
			round_num += 1
			_to_spawn = 5 + round_num * 3
			_round_break = 8.0
			_banner_label.text = "ROUND %d" % round_num
			_banner_label.visible = true
			_banner_label.modulate.a = 1.0
			_banner_t = 2.6
			weapons.play_sfx("doom_spawn", _player_center(), 0.1, 0.55)
		return
	if _to_spawn > 0:
		_spawn_t -= delta
		if _spawn_t <= 0.0 and _zombies.size() < ALIVE_CAP:
			_spawn_t = maxf(0.45, 1.5 - round_num * 0.07)
			_to_spawn -= 1
			_spawn_zombie()


# ==================== Interactions (F) ====================

func _interactions(delta: float) -> void:
	_prompt = ""
	_prompt_action = Callable()
	var pc: Vector2 = _player_center()
	var f_down: bool = Input.is_physical_key_pressed(KEY_F)
	var f_edge: bool = f_down and not _f_was

	# Wall buys
	for wb in ZombiesMap.WALL_BUYS:
		if pc.distance_to(wb.pos) > INTERACT_R + 6.0:
			continue
		var wname: String = wb.weapon
		var lbl: String = WeaponSystem.WEAPONS[wname].label
		var pa: Dictionary = weapons._actors["player"]
		# Owning the PACK-A-PUNCHED version still counts for ammo refills
		var owned_name: String = ""
		for s in [2, 3]:
			var sg: String = pa.slot_guns.get(s, "")
			if sg == wname or sg == wname + "_pap":
				owned_name = sg
		if owned_name != "":
			var half: int = int(wb.cost / 2.0)
			_prompt = "F: %s AMMO — $%d" % [lbl, half]
			if f_edge and points >= half:
				points -= half
				pa.ammo[owned_name] = wb.ammo if not owned_name.ends_with("_pap") else int(wb.ammo * 1.5)
				weapons.play_sfx("pickup", pc, 0.06, 1.3)
		else:
			_prompt = "F: BUY %s — $%d" % [lbl, wb.cost]
			if f_edge and points >= wb.cost:
				points -= wb.cost
				_give_gun(wname, wb.ammo)
		return

	# Mystery box
	if pc.distance_to(ZombiesMap.BOX_POS) < INTERACT_R + 12.0:
		if _box_state == 0:
			_prompt = "F: MYSTERY BOX — $%d" % ZombiesMap.BOX_COST
			if f_edge and points >= ZombiesMap.BOX_COST:
				points -= ZombiesMap.BOX_COST
				_box_state = 1
				_box_t = 2.4
				weapons.play_sfx("doom_spawn", ZombiesMap.BOX_POS, 0.08, 1.2)
		elif _box_state == 2:
			var blbl: String = WeaponSystem.WEAPONS[_box_result].label
			_prompt = "F: TAKE %s" % blbl
			if f_edge:
				if _box_result == "doom":
					weapons.give_weapon("player", "doom")
				else:
					_give_gun(_box_result, AMMO_POOLS.get(_box_result, 60))
				_box_state = 0
				_box_result = ""
		return

	# PACK-A-PUNCH: forge the gun in your hands
	if pc.distance_to(ZombiesMap.PAP_POS) < INTERACT_R + 10.0:
		var pa2: Dictionary = weapons._actors["player"]
		var cur: String = weapons.get_weapon("player")
		if cur == "" or cur == "doom":
			_prompt = "PACK-A-PUNCH — bring it a gun"
		elif cur.ends_with("_pap"):
			_prompt = "It hums, satisfied. Already forged."
		elif WeaponSystem.WEAPONS.has(cur + "_pap"):
			_prompt = "F: FORGE %s — $%d" % [WeaponSystem.WEAPONS[cur].label, ZombiesMap.PAP_COST]
			if f_edge and points >= ZombiesMap.PAP_COST:
				points -= ZombiesMap.PAP_COST
				var papn: String = cur + "_pap"
				pa2.ammo.erase(cur)
				pa2.ammo[papn] = int(AMMO_POOLS.get(cur, 60) * 1.5)
				weapons.set_slot_gun("player", pa2.cur_slot, papn)
				weapons.play_sfx("doom_spawn", ZombiesMap.PAP_POS, 0.1, 0.8)
				weapons.spawn_ring(ZombiesMap.PAP_POS, Color(0.8, 0.4, 1.0), 6.0, 36.0, 0.4)
				GameState.cam_shake += 4.0
		return

	# Zone doors (debris buys)
	for di in range(ZombiesMap.DOORS.size()):
		if _doors_open[di]:
			continue
		var door: Dictionary = ZombiesMap.DOORS[di]
		if pc.distance_to(door.prompt) > INTERACT_R + 18.0:
			continue
		_prompt = "F: OPEN %s — $%d" % [door.label, door.cost]
		if f_edge and points >= door.cost:
			points -= door.cost
			_doors_open[di] = true
			for x in range(door.x0, door.x1 + 1):
				for y in range(door.y0, door.y1 + 1):
					WorldManager.fg_tiles[y][x] = 0
					WorldManager.tile_changed.emit(x, y, 0)
			weapons.play_sfx("explode", door.prompt, 0.1, 0.8)
			weapons.spawn_ring(door.prompt, Color(1.0, 0.7, 0.2), 4.0, 30.0, 0.3)
			GameState.cam_shake += 3.0
		return

	# Barricade rebuild (hold F)
	for i in range(ZombiesMap.WINDOWS.size()):
		var w: Dictionary = ZombiesMap.WINDOWS[i]
		if pc.distance_to(w.inside) > INTERACT_R + 12.0:
			continue
		if _planks[i] >= PLANKS_MAX:
			_prompt = "Barricade secure"
			return
		# Can't rebuild with a zombie in the frame
		var blocked: bool = false
		for id in _zombies:
			var z: Dictionary = _zombies[id]
			if z.state >= 1 and z.win == i and z.pos.distance_to(w.rect.get_center()) < 34.0 and z.state != 3:
				blocked = true
				break
		if blocked:
			_prompt = "They're at the window!"
			return
		_prompt = "HOLD F: REBUILD  (+$%d)" % POINTS_PLANK
		if f_down:
			_rebuild_t += delta
			if _rebuild_t >= REBUILD_TIME:
				_rebuild_t = 0.0
				_planks[i] = mini(PLANKS_MAX, _planks[i] + 1)
				points += POINTS_PLANK
				weapons.play_sfx("bonk", w.rect.get_center(), 0.06, 1.1)
		else:
			_rebuild_t = 0.0
		return
	_rebuild_t = 0.0


func _give_gun(wname: String, ammo: int) -> void:
	## CoD carry rule: fills the empty gun slot if you have one, otherwise
	## replaces whatever you're holding (or slot 2 if you're on the knife).
	var pa: Dictionary = weapons._actors["player"]
	var slot: int
	if pa.slot_guns.get(2, "") == "":
		slot = 2
	elif pa.slot_guns.get(3, "") == "":
		slot = 3
	else:
		slot = pa.cur_slot if pa.cur_slot >= 2 else 2
	pa.ammo[wname] = ammo
	weapons.set_slot_gun("player", slot, wname)


# ==================== Frame ====================

func _process(delta: float) -> void:
	_time += delta
	queue_redraw()
	if not is_instance_valid(player) or weapons == null or not weapons._actors.has("player"):
		return
	_invuln = maxf(0.0, _invuln - delta)
	_since_hit += delta
	# Unregister dead zombies OUTSIDE any weapon_system iteration
	for pid in _purge:
		weapons._actors.erase(pid)
	_purge.clear()
	if _over:
		return

	# Regen (CoD style): untouched for a while -> hp crawls back
	if player_hp < MAX_HP and _since_hit > REGEN_DELAY:
		_regen_t -= delta
		if _regen_t <= 0.0:
			_regen_t = REGEN_TICK
			player_hp += 1
			weapons.spawn_ring(_player_center(), Color(0.4, 1.0, 0.5), 4.0, 18.0, 0.25)
	else:
		_regen_t = 0.6

	# Mystery box roll
	if _box_state == 1:
		_box_t -= delta
		if _box_t <= 0.0:
			var pool: Array = BOX_POOL.keys()
			var total: float = 0.0
			for k in pool:
				total += BOX_POOL[k]
			var pick: float = randf() * total
			for k in pool:
				pick -= BOX_POOL[k]
				if pick <= 0.0:
					_box_result = k
					break
			if _box_result == "":
				_box_result = "smg"
			_box_state = 2
			_box_t = 9.0
			weapons.play_sfx("pickup", ZombiesMap.BOX_POS, 0.08, 1.6)
	elif _box_state == 2:
		_box_t -= delta
		if _box_t <= 0.0:
			_box_state = 0  # left it too long — gone
			_box_result = ""

	# If the doom ray burned out, silently re-draw the slot gun
	var pa: Dictionary = weapons._actors["player"]
	if pa.weapon == "" and pa.cur_slot >= 2:
		pa.weapon = weapons.slot_weapon("player", pa.cur_slot)

	_round_logic(delta)
	_zombie_ai(delta)
	_interactions(delta)
	_player_input(delta)
	_atmosphere(delta)
	_refresh_hud()
	_f_was = Input.is_physical_key_pressed(KEY_F)


func _atmosphere(delta: float) -> void:
	_backdrop.queue_redraw()
	# fireflies drift on lazy sine paths
	for f in _fireflies:
		f.ph += delta * 0.8
		f.pos += Vector2(sin(f.ph * 1.3) * 14.0, cos(f.ph) * 8.0) * delta
	# zone caption when crossing region borders
	var pc: Vector2 = _player_center()
	var zname: String = ZombiesMap.CAVE_NAME if pc.y > ZombiesMap.CAVE_Y else ""
	if zname == "":
		for z in ZombiesMap.ZONES:
			if pc.x >= z.x0 and pc.x < z.x1:
				zname = z.name
				break
	if zname != "" and zname != _cur_zone:
		_cur_zone = zname
		_zone_label.text = "—  %s  —" % zname
		_zone_label.visible = true
		_zone_t = 2.4
	if _zone_t > 0.0:
		_zone_t -= delta
		_zone_label.modulate.a = clampf(_zone_t / 0.7, 0.0, 1.0)
		if _zone_t <= 0.0:
			_zone_label.visible = false


func _player_input(delta: float) -> void:
	if player._is_dead:
		return
	var pc: Vector2 = _player_center()
	var aim: Vector2 = weapons.get_global_mouse_position() - pc
	weapons.set_aim("player", aim)
	if Input.is_physical_key_pressed(KEY_1):
		weapons.select_slot("player", 1)
	elif Input.is_physical_key_pressed(KEY_2):
		weapons.select_slot("player", 2)
	elif Input.is_physical_key_pressed(KEY_3):
		weapons.select_slot("player", 3)
	var unarmed: bool = weapons.get_weapon("player") == ""
	weapons.set_shield("player", Input.is_mouse_button_pressed(MOUSE_BUTTON_RIGHT) and not GameState.is_edit_mode)
	var lmb: bool = Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT) and not GameState.is_edit_mode
	if unarmed:
		if lmb:
			weapons.charge_dash("player", delta)
		elif _lmb_was:
			var res: Dictionary = weapons.release_dash("player")
			if res.ok:
				var ddir: Vector2 = aim.normalized()
				var imp: float = 7.0 + 10.0 * res.power
				player.physics._speedX += ddir.x * imp
				player.physics._speedY += ddir.y * imp
	elif lmb and weapons.try_shoot("player"):
		var kick: float = weapons.get_kick("player")
		var wn: String = weapons.get_weapon("player")
		if wn != "" and WeaponSystem.WEAPONS[wn].get("beam", false):
			kick *= delta * 6.0
		var kdir: Vector2 = aim.normalized()
		player.physics._speedX -= kdir.x * kick
		player.physics._speedY -= kdir.y * kick
	_lmb_was = lmb


func _player_center() -> Vector2:
	return Vector2(player.physics.x + 8.0, player.physics.y + 8.0)


func _refresh_hud() -> void:
	_points_label.text = "$%d" % points
	_round_label.text = "ROUND %d" % maxi(round_num, 1) if round_num > 0 else "GET READY..."
	_kills_label.text = "%d kills" % kills
	var hearts: String = ""
	for i in range(MAX_HP):
		hearts += "♥" if i < player_hp else "♡"
	_hearts_label.text = hearts
	var wn: String = weapons.get_weapon("player")
	if wn == "":
		_weapon_label.text = "KNIFE  (1)"
		_weapon_label.add_theme_color_override("font_color", Color(0.75, 0.78, 0.9))
	else:
		var pa: Dictionary = weapons._actors["player"]
		var ammo_s: String = "∞"
		if WeaponSystem.WEAPONS[wn].get("beam", false):
			ammo_s = "%.0fs" % maxf(pa.weapon_left, 0.0)
		elif pa.has("ammo"):
			ammo_s = str(int(pa.ammo.get(wn, 0)))
		_weapon_label.text = "%s   AMMO %s" % [WeaponSystem.WEAPONS[wn].label, ammo_s]
		_weapon_label.add_theme_color_override("font_color", weapons.get_weapon_color("player"))
	_prompt_label.text = _prompt


func _game_over() -> void:
	_over = true
	weapons.set_shield("player", false)
	_result_label.text = "YOU DIED"
	_result_sub.text = "Survived %d round%s — %d kills, $%d earned.\nThe bunker falls silent." % [
		maxi(round_num, 1), "" if round_num == 1 else "s", kills, points]
	_result_panel.visible = true


func _retry() -> void:
	GameState.battle_mode = true
	GameState.zombies_mode = true
	GameState.boss_fight = false
	GameState.survivors_mode = false
	GameState.cam_shake = 0.0
	ZombiesMap.build()
	get_tree().change_scene_to_file("res://scenes/world/game.tscn")


func _return_to_menu() -> void:
	GameState.battle_mode = false
	GameState.zombies_mode = false
	GameState.cam_shake = 0.0
	GameState.player_stunned = false
	NetworkManager.disconnect_game()
	get_tree().change_scene_to_file("res://scenes/ui/main_menu.tscn")


# ==================== World-space drawing ====================

func _draw() -> void:
	var font: Font = ThemeDB.fallback_font
	# Windows: frame + planks
	for i in range(ZombiesMap.WINDOWS.size()):
		var w: Dictionary = ZombiesMap.WINDOWS[i]
		var r: Rect2 = w.rect
		draw_rect(r.grow(2.0), Color(0.16, 0.12, 0.08, 0.85))
		draw_rect(r, Color(0.03, 0.03, 0.05, 0.9))
		var n: int = _planks[i]
		for p in range(n):
			var shake: Vector2 = Vector2.ZERO
			# Planks rattle while zombies chew
			for id in _zombies:
				var z: Dictionary = _zombies[id]
				if z.win == i and z.state == 1:
					shake = Vector2(randf_range(-0.8, 0.8), randf_range(-0.8, 0.8))
					break
			if w.horizontal:
				var px: float = r.position.x - 4.0 + shake.x
				var py: float = r.position.y + 2.0 + float(p) * (r.size.y + 0.0) / PLANKS_MAX + shake.y
				py = r.position.y + 1.0 + float(p) * (r.size.y - 4.0) / PLANKS_MAX + shake.y
				draw_rect(Rect2(px, py, r.size.x + 8.0, 3.2), Color(0.5, 0.34, 0.16))
				draw_rect(Rect2(px, py + 2.2, r.size.x + 8.0, 1.0), Color(0.3, 0.19, 0.08))
			else:
				var py2: float = r.position.y + 2.0 + float(p) * (r.size.y - 6.0) / PLANKS_MAX + shake.y
				draw_rect(Rect2(r.position.x - 4.0 + shake.x, py2, r.size.x + 8.0, 3.2), Color(0.5, 0.34, 0.16))
				draw_rect(Rect2(r.position.x - 4.0 + shake.x, py2 + 2.2, r.size.x + 8.0, 1.0), Color(0.3, 0.19, 0.08))
	# Wall buys: chalk gun outline + price
	for wb in ZombiesMap.WALL_BUYS:
		var gp: Vector2 = wb.pos
		var col: Color = Color(0.9, 0.92, 1.0, 0.55 + 0.15 * sin(_time * 3.0))
		# chalk gun: body + barrel + grip
		draw_rect(Rect2(gp.x - 12.0, gp.y - 5.0, 16.0, 5.0), col, false, 1.4)
		draw_rect(Rect2(gp.x + 4.0, gp.y - 4.0, 9.0, 2.6), col, false, 1.4)
		draw_line(gp + Vector2(-8.0, 0.0), gp + Vector2(-10.0, 7.0), col, 1.4)
		draw_string(font, gp + Vector2(-22.0, -10.0), WeaponSystem.WEAPONS[wb.weapon].label,
			HORIZONTAL_ALIGNMENT_LEFT, -1, 8, Color(0.95, 0.9, 0.7, 0.9))
		draw_string(font, gp + Vector2(-22.0, 18.0), "$%d" % wb.cost,
			HORIZONTAL_ALIGNMENT_LEFT, -1, 8, Color(1.0, 0.85, 0.3, 0.9))
	# Mystery box
	var bp: Vector2 = ZombiesMap.BOX_POS
	var glow: float = 0.5 + 0.5 * sin(_time * 2.2)
	draw_rect(Rect2(bp.x - 16.0, bp.y - 10.0, 32.0, 20.0), Color(0.32, 0.2, 0.1))
	draw_rect(Rect2(bp.x - 16.0, bp.y - 10.0, 32.0, 20.0), Color(0.9, 0.75, 0.3, 0.5 + glow * 0.3), false, 1.6)
	draw_rect(Rect2(bp.x - 16.0, bp.y - 2.0, 32.0, 2.0), Color(0.9, 0.75, 0.3, 0.7))
	if _box_state == 0:
		draw_string(font, bp + Vector2(-4.0, -14.0), "?", HORIZONTAL_ALIGNMENT_LEFT, -1, 12,
			Color(0.55, 0.85, 1.0, 0.6 + glow * 0.4))
	elif _box_state == 1:
		# Rolling: weapon colors strobe out of the box
		var keys: Array = BOX_POOL.keys()
		var kcol: Color = WeaponSystem.WEAPONS[keys[int(_time * 14.0) % keys.size()]].color
		draw_rect(Rect2(bp.x - 5.0, bp.y - 34.0 - glow * 6.0, 10.0, 24.0), Color(kcol.r, kcol.g, kcol.b, 0.85))
		draw_circle(bp + Vector2(0.0, -38.0 - glow * 6.0), 4.0, Color(1, 1, 1, 0.9))
	elif _box_state == 2:
		var rw: Dictionary = WeaponSystem.WEAPONS[_box_result]
		var rc2: Color = rw.color
		var fade: float = clampf(_box_t / 3.0, 0.3, 1.0)
		draw_rect(Rect2(bp.x - 14.0, bp.y - 36.0, 28.0, 9.0), Color(rc2.r, rc2.g, rc2.b, fade))
		draw_string(font, bp + Vector2(-24.0, -42.0), rw.label, HORIZONTAL_ALIGNMENT_LEFT, -1, 8,
			Color(1, 1, 1, fade))
	# Door prices (closed doors only)
	for di in range(ZombiesMap.DOORS.size()):
		if _doors_open[di]:
			continue
		var door: Dictionary = ZombiesMap.DOORS[di]
		var dp: Vector2 = door.prompt
		draw_string(font, dp + Vector2(-26.0, -24.0), "%s" % door.label,
			HORIZONTAL_ALIGNMENT_LEFT, -1, 8, Color(0.95, 0.85, 0.6, 0.8))
		draw_string(font, dp + Vector2(-16.0, -13.0), "$%d" % door.cost,
			HORIZONTAL_ALIGNMENT_LEFT, -1, 9, Color(1.0, 0.75, 0.2, 0.65 + 0.2 * sin(_time * 3.0)))
	# PACK-A-PUNCH machine: dark forge, violet runes, pulsing crown light
	var pp: Vector2 = ZombiesMap.PAP_POS
	var pulse: float = 0.5 + 0.5 * sin(_time * 3.4)
	draw_rect(Rect2(pp.x - 14.0, pp.y - 24.0, 28.0, 38.0), Color(0.12, 0.09, 0.19))
	draw_rect(Rect2(pp.x - 14.0, pp.y - 24.0, 28.0, 38.0), Color(0.6, 0.3, 1.0, 0.45 + pulse * 0.3), false, 1.6)
	draw_rect(Rect2(pp.x - 10.0, pp.y - 20.0, 20.0, 11.0), Color(0.38, 0.2, 0.66, 0.6 + pulse * 0.3))
	draw_line(pp + Vector2(-8.0, 2.0), pp + Vector2(8.0, 2.0), Color(0.75, 0.45, 1.0, 0.6 + pulse * 0.3), 1.4)
	draw_circle(pp + Vector2(0.0, -29.0), 2.6 + pulse * 1.8, Color(0.78, 0.42, 1.0, 0.85))
	draw_string(font, pp + Vector2(-30.0, 26.0), "PACK-A-PUNCH", HORIZONTAL_ALIGNMENT_LEFT, -1, 8, Color(0.8, 0.55, 1.0, 0.9))
	draw_string(font, pp + Vector2(-14.0, 36.0), "$%d" % ZombiesMap.PAP_COST, HORIZONTAL_ALIGNMENT_LEFT, -1, 8, Color(1.0, 0.85, 0.3, 0.85))
	# Zombies — rotting smiley balls
	for id in _zombies:
		var z: Dictionary = _zombies[id]
		var zp: Vector2 = z.pos + Vector2(0.0, sin(z.bob) * 2.0)
		var body: Color = Color(0.32, 0.45, 0.18)
		if z.flash > 0.0:
			body = body.lerp(Color(1, 1, 1), z.flash / 0.14)
		draw_circle(zp, z.r, Color(0.1, 0.14, 0.06))
		draw_circle(zp, z.r - 1.0, body)
		# rot patches
		draw_circle(zp + Vector2(-3.0, 3.0), 2.2, Color(0.22, 0.3, 0.1))
		draw_circle(zp + Vector2(4.0, -2.0), 1.7, Color(0.24, 0.33, 0.12))
		# glowing eyes track the player
		var look: Vector2 = (_player_center() - zp).normalized() * 2.0
		var ecol: Color = Color(1.0, 0.25, 0.1) if z.state == 3 else Color(1.0, 0.7, 0.2)
		draw_circle(zp + Vector2(-3.0, -2.5) + look, 1.6, ecol)
		draw_circle(zp + Vector2(3.0, -2.5) + look, 1.6, ecol)
		# jagged jaw (chews when at a window)
		var jaw: float = 1.5 + (sin(_time * 16.0) * 2.0 if z.state == 1 else 0.0)
		draw_line(zp + Vector2(-3.5, 3.5), zp + Vector2(-1.2, 3.5 + jaw), Color(0.08, 0.1, 0.04), 1.2)
		draw_line(zp + Vector2(-1.2, 3.5 + jaw), zp + Vector2(1.2, 3.5), Color(0.08, 0.1, 0.04), 1.2)
		draw_line(zp + Vector2(1.2, 3.5), zp + Vector2(3.5, 3.5 + jaw * 0.7), Color(0.08, 0.1, 0.04), 1.2)
		# stun stars handled by weapon_system's own draw


func _draw_backdrop() -> void:
	## Painted onto the z=-5 backdrop node — everything here sits BEHIND the
	## world tiles. Per-zone night skies, moon, stars, skyline, ambience.
	var bd: Node2D = _backdrop
	# Zone sky gradients (8 vertical slices each, lerped top->horizon)
	var skies: Array = [
		{"x0": 32.0, "x1": 944.0, "top": Color(0.015, 0.05, 0.035), "hor": Color(0.05, 0.13, 0.08)},    # forest: deep green night
		{"x0": 944.0, "x1": 1856.0, "top": Color(0.03, 0.035, 0.05), "hor": Color(0.09, 0.09, 0.12)},   # bunker: dead slate
		{"x0": 1856.0, "x1": 2784.0, "top": Color(0.03, 0.02, 0.07), "hor": Color(0.11, 0.06, 0.16)},   # city: bruised violet
	]
	for sk in skies:
		var y0: float = 160.0
		var y1: float = 624.0
		for i in range(8):
			var t0: float = float(i) / 8.0
			var c: Color = sk.top.lerp(sk.hor, t0)
			bd.draw_rect(Rect2(sk.x0, y0 + (y1 - y0) * t0, sk.x1 - sk.x0, (y1 - y0) / 8.0 + 1.0), c)
	# Cave depth wash
	bd.draw_rect(Rect2(32.0, 648.0, 2752.0, 96.0), Color(0.02, 0.015, 0.045))
	# Stars (twinkle; skip over the bunker monolith band where sky is hidden anyway)
	for st in _stars:
		var a: float = 0.25 + 0.3 * (0.5 + 0.5 * sin(_time * 1.3 + st.tw))
		bd.draw_rect(Rect2(st.pos.x, st.pos.y, st.s, st.s), Color(0.8, 0.85, 1.0, a))
	# Moon over the city + soft halo
	var moon: Vector2 = Vector2(2380.0, 240.0)
	bd.draw_circle(moon, 26.0, Color(0.5, 0.5, 0.62, 0.12))
	bd.draw_circle(moon, 17.0, Color(0.88, 0.9, 0.95, 0.9))
	bd.draw_circle(moon + Vector2(-5.0, -3.0), 4.0, Color(0.72, 0.75, 0.82, 0.9))
	bd.draw_circle(moon + Vector2(6.0, 5.0), 2.6, Color(0.74, 0.77, 0.84, 0.9))
	# City skyline silhouette + a few lit windows
	var sx: float = 1880.0
	var si: int = 0
	while sx < 2760.0:
		var bw: float = 60.0 + float((si * 37) % 70)
		var bh: float = 120.0 + float((si * 53) % 160)
		bd.draw_rect(Rect2(sx, 624.0 - bh, bw, bh), Color(0.05, 0.04, 0.09))
		if (si % 2) == 0:
			var wa: float = 0.35 + 0.25 * (0.5 + 0.5 * sin(_time * 0.9 + float(si)))
			bd.draw_rect(Rect2(sx + bw * 0.3, 624.0 - bh + 24.0, 5.0, 6.0), Color(0.95, 0.75, 0.35, wa))
			bd.draw_rect(Rect2(sx + bw * 0.62, 624.0 - bh + 52.0, 5.0, 6.0), Color(0.95, 0.75, 0.35, wa * 0.8))
		sx += bw + 14.0
		si += 1
	# Forest treeline silhouette
	var tx: float = 60.0
	var ti: int = 0
	while tx < 920.0:
		var th: float = 90.0 + float((ti * 41) % 110)
		bd.draw_rect(Rect2(tx, 624.0 - th, 10.0, th), Color(0.02, 0.05, 0.03))
		bd.draw_circle(Vector2(tx + 5.0, 624.0 - th), 26.0 + float((ti * 17) % 18), Color(0.025, 0.06, 0.035))
		tx += 70.0 + float((ti * 23) % 40)
		ti += 1
	# Fireflies (forest band only)
	for f in _fireflies:
		var fa: float = 0.35 + 0.45 * (0.5 + 0.5 * sin(_time * 2.0 + f.ph * 3.0))
		bd.draw_circle(f.pos, 1.3, Color(0.65, 1.0, 0.45, fa))
		bd.draw_circle(f.pos, 3.2, Color(0.5, 0.9, 0.35, fa * 0.25))
	# Crystal glints in the hollow
	for cx in [320.0, 976.0, 1472.0, 2096.0, 2576.0]:
		var ga: float = 0.2 + 0.35 * (0.5 + 0.5 * sin(_time * 1.6 + cx))
		bd.draw_circle(Vector2(cx, 700.0), 2.0, Color(0.75, 0.5, 1.0, ga))
		bd.draw_circle(Vector2(cx, 700.0), 6.0, Color(0.6, 0.35, 0.9, ga * 0.3))
