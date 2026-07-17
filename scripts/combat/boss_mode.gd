class_name BossMode
extends Node
## BOSS FIGHT: you (3 lives, 5 HP) vs THE WARDEN. Works with the guns
## toggle: fists = parry/dash/deflect duel, guns = weapon pads + firepower.
## The DOOM RAY still materializes on the altar in both. Centerpiece: catch
## the Warden's annihilation beam on your shield (or your own DOOM RAY) and
## MASH LMB to win the anime clash — push it back into the Warden's face.

const MAX_LIVES: int = 3
const MAX_HP: int = 5
const INVULN_TIME: float = 1.2

var player: Node = null
var weapons: WeaponSystem = null
var boss: BossController = null

var player_lives: int = MAX_LIVES
var player_hp: int = MAX_HP
var _player_invuln: float = 0.0
var _over: bool = false
var _intro_timer: float = 2.6

var _lmb_was_down: bool = false
var _player_was_stunned: bool = false
var _beam_tick: float = 0.0
var _regen_tick: float = 0.0

# Beam struggle
var _struggle: bool = false
var _clash_t: float = 0.45       # 0 = at the boss, 1 = at the player
var _struggle_timer: float = 0.0

var _hud: CanvasLayer
var _boss_bar: Control
var _slot_bar: Control
var _bar_chip: float = 1.0       # Delayed white damage trail
var _name_label: Label
var _proto_label: Label
var _player_label: Label
var _intro_label: Label
var _mash_label: Label
var _result_panel: PanelContainer
var _result_label: Label
var _result_sub: Label

# ---- online co-op ----
var net: bool = false
var _is_host: bool = false
var _net_ids: Array = []
var _net_hp: Dictionary = {}       # pid -> hp (replicated, for floating bars)
var _net_out: Dictionary = {}      # pid -> eliminated
var _net_accum: float = 0.0
var _eliminated: bool = false
var _target_pid: int = -1          # host: whose ball the boss brain last targeted
var _pending_push: Dictionary = {} # pid -> accumulated push for remote targets


func _ready() -> void:
	net = NetPlay.match_active
	if net:
		_net_ids = NetPlay.member_ids()
		_is_host = NetPlay.i_am_host()
	player = get_parent()._get_player(NetPlay.my_id())
	weapons = WeaponSystem.new()
	get_parent().add_child.call_deferred(weapons)
	boss = BossController.new()
	boss.puppet = net and not _is_host
	get_parent().add_child.call_deferred(boss)
	_build_hud()
	call_deferred("_wire_up")


func _wire_up() -> void:
	# Only the DOOM RAY appears in the world; guns are the permanent
	# slots 2/3 loadout when the toggle is ON
	weapons.super_pos = BossMap.SUPER_POS
	weapons.ability_spots = BossMap.ABILITY_SPOTS.duplicate()
	weapons.ability_picked.connect(_on_ability)
	var base_hp: int = 130 if GameState.battle_guns_enabled else 60
	if net:
		# More players, more Warden: +65% max HP per extra ball
		boss.max_hp = int(round(base_hp * (1.0 + 0.65 * float(maxi(1, _net_ids.size()) - 1))))
	else:
		boss.max_hp = base_hp
	boss.hp = boss.max_hp
	boss.ws = weapons
	boss.min_x = BossMap.BOUNDS_MIN_X
	boss.max_x = BossMap.BOUNDS_MAX_X
	boss.min_y = BossMap.BOUNDS_MIN_Y
	boss.floor_y = BossMap.FLOOR_Y
	if net and _is_host:
		# The brain targets the NEAREST living ball; damage routes to whoever
		# was targeted when the attack landed.
		boss.get_player_center = _boss_target_center
		boss.get_player_vel = _boss_target_vel
		boss.is_player_alive = func() -> bool: return not _over and _any_ball_alive()
		boss.hurt_player = _boss_hurt_target
		boss.push_player = _boss_push_target
		boss.net_proj_cb = func(pr: Dictionary) -> void:
			NetPlay.send_mode({"m": "bpj",
				"x": pr.pos.x, "y": pr.pos.y, "vx": pr.vel.x, "vy": pr.vel.y,
				"d": pr.dmg, "l": pr.life, "s": pr.size,
				"cr": pr.color.r, "cg": pr.color.g, "cb": pr.color.b})
		weapons.net_break_cb = func(kind: String, a: float, b: float) -> void:
			NetPlay.send_mode({"m": "brk", "k": kind, "a": a, "b": b})
	else:
		boss.get_player_center = func() -> Vector2: return Vector2(player.physics.x + 8.0, player.physics.y + 8.0)
		boss.get_player_vel = func() -> Vector2: return Vector2(player.physics._speedX, player.physics._speedY) * EEPhysics.EE_TICK_FRAC * EEPhysics.TPS
		boss.is_player_alive = func() -> bool: return not _over and is_instance_valid(player) and not player._is_dead
		boss.hurt_player = _hurt_player
		boss.push_player = func(v: Vector2) -> void:
			player.physics._speedX += v.x
			player.physics._speedY += v.y
	boss.boss_died.connect(_on_boss_died)
	weapons.register_actor("player", 0,
		func() -> Vector2: return Vector2(player.physics.x + 8.0, player.physics.y + 8.0),
		func() -> Vector2: return Vector2(player.physics._speedX, player.physics._speedY) * EEPhysics.EE_TICK_FRAC * EEPhysics.TPS,
		func() -> bool: return is_instance_valid(player) and not player._is_dead,
		_hurt_player,
		func() -> int: return player_hp, MAX_HP,
		func() -> bool: return player.physics.is_grounded,
		func(v: Vector2) -> void:
			player.physics._speedX += v.x
			player.physics._speedY += v.y)
	weapons.register_actor("boss", 1,
		boss.get_center, boss.get_vel_pxs,
		boss.alive,
		func(dmg: int, dir: Vector2) -> void: boss.take_damage(dmg, dir),
		Callable(), 1,
		func() -> bool: return false,
		boss.apply_push)
	weapons._actors["boss"]["hit_radius"] = BossController.BODY_R
	weapons._actors["boss"]["no_pickup"] = true
	weapons._actors["player"]["loadout"] = GameState.battle_guns_enabled
	weapons._actors["player"]["auto_equip"] = false  # Doom waits in slot 2
	if net:
		if not _is_host:
			# Puppet boss: shots plink locally; the HOST's replay of my shots
			# is what actually chunks the HP bar.
			weapons._actors["boss"]["hurt"] = func(_dmg: int, _dir: Vector2) -> void:
				boss._flash = maxf(boss._flash, 0.1)
		_net_setup()
	if is_instance_valid(player) and player.has_signal("died"):
		player.died.connect(_on_player_died)


# ==================== ONLINE CO-OP ====================

func _rid(pid: int) -> String:
	return "p%d" % pid


func _net_setup() -> void:
	NetPlay.mode_msg.connect(_on_mode_msg)
	NetworkManager.player_disconnected.connect(_on_net_player_left)
	for pid in _net_ids:
		_net_hp[pid] = MAX_HP
		_net_out[pid] = false
		if pid == NetPlay.my_id():
			continue
		var rid: String = _rid(pid)
		weapons.register_actor(rid, 0,  # all humans share team 0 — no friendly fire
			_remote_center.bind(pid),
			_remote_vel.bind(pid),
			_remote_alive.bind(pid),
			func(_dmg: int, _dir: Vector2) -> void: pass,
			func() -> int: return int(_net_hp.get(pid, MAX_HP)), MAX_HP,
			func() -> bool: return true,
			func(_v: Vector2) -> void: pass)
		weapons._actors[rid]["loadout"] = GameState.battle_guns_enabled
		weapons._actors[rid]["auto_equip"] = false
		weapons._actors[rid]["no_pickup"] = true


func _remote_node(pid: int) -> Node:
	var scene: Node = get_parent()
	if scene and scene.has_method("_get_player"):
		return scene._get_player(pid)
	return null


func _remote_center(pid: int) -> Vector2:
	var p: Node = _remote_node(pid)
	if p == null:
		return Vector2(-4000, -4000)
	return p.position + Vector2(8.0, 8.0)


func _remote_vel(pid: int) -> Vector2:
	var p: Node = _remote_node(pid)
	if p == null or p.get("_remote_sync") == null:
		return Vector2.ZERO
	return p._remote_sync.speed * EEPhysics.EE_TICK_FRAC * EEPhysics.TPS


func _remote_alive(pid: int) -> bool:
	if _net_out.get(pid, false):
		return false
	var p: Node = _remote_node(pid)
	return p != null and not p._is_dead


func _any_ball_alive() -> bool:
	if is_instance_valid(player) and not player._is_dead and not _eliminated:
		return true
	for pid in _net_ids:
		if pid != NetPlay.my_id() and _remote_alive(pid):
			return true
	return false


func _boss_target_center() -> Vector2:
	## HOST: nearest living ball to the Warden. Remembers who it picked so
	## a landing attack damages the right player.
	var best: Vector2 = Vector2(player.physics.x + 8.0, player.physics.y + 8.0) if is_instance_valid(player) else Vector2(512, 400)
	var best_d: float = 1e18
	_target_pid = NetPlay.my_id()
	if not (is_instance_valid(player) and not player._is_dead and not _eliminated):
		best_d = 1e17  # host ball dead — any living remote wins
	else:
		best_d = best.distance_squared_to(boss.pos)
	for pid in _net_ids:
		if pid == NetPlay.my_id() or not _remote_alive(pid):
			continue
		var rc: Vector2 = _remote_center(pid)
		var d: float = rc.distance_squared_to(boss.pos)
		if d < best_d:
			best_d = d
			best = rc
			_target_pid = pid
	return best


func _boss_target_vel() -> Vector2:
	if _target_pid == NetPlay.my_id() or _target_pid < 0:
		return Vector2(player.physics._speedX, player.physics._speedY) * EEPhysics.EE_TICK_FRAC * EEPhysics.TPS
	return _remote_vel(_target_pid)


func _boss_hurt_target(dmg: int, dir: Vector2) -> void:
	if _target_pid == NetPlay.my_id() or _target_pid < 0:
		_hurt_player(dmg, dir)
	else:
		NetPlay.send_mode({"m": "hit", "tgt": _target_pid, "d": dmg, "dx": dir.x, "dy": dir.y})


func _boss_push_target(v: Vector2) -> void:
	if _target_pid == NetPlay.my_id() or _target_pid < 0:
		player.physics._speedX += v.x
		player.physics._speedY += v.y
	else:
		_pending_push[_target_pid] = _pending_push.get(_target_pid, Vector2.ZERO) + v


func _deal_boss(dmg: int, dir: Vector2) -> void:
	## Boss damage authority: the host applies, everyone else asks the host.
	if not net or _is_host:
		boss.take_damage(dmg, dir)
	else:
		boss._flash = maxf(boss._flash, 0.12)
		NetPlay.send_mode({"m": "bdmg", "d": dmg, "dx": dir.x, "dy": dir.y})


func _on_net_player_left(pid: int) -> void:
	if not net or _over or not _net_out.has(pid):
		return
	_net_out[pid] = true
	if _is_host and not _any_ball_alive():
		NetPlay.send_mode({"m": "blose"})
		_end(false)


func _on_mode_msg(from_id: int, data: Dictionary) -> void:
	if not net:
		return
	var kind: String = str(data.get("m", ""))
	var rid: String = _rid(from_id)
	match kind:
		"bs":
			if weapons._actors.has(rid):
				var ra: Dictionary = weapons._actors[rid]
				weapons.set_aim(rid, Vector2(float(data.get("ax", 1.0)), float(data.get("ay", 0.0))))
				weapons.set_shield(rid, bool(data.get("sh", false)))
				var wpn: String = str(data.get("wpn", ""))
				if ra.weapon != wpn:
					if wpn == "":
						weapons.strip_weapon(rid)
					else:
						weapons.give_weapon(rid, wpn)
				if bool(data.get("fire", false)) and ra.weapon != "" \
						and WeaponSystem.WEAPONS.get(ra.weapon, {}).get("beam", false):
					ra.cooldown = 0.0
					weapons.try_shoot(rid)
			_net_hp[from_id] = int(data.get("hp", MAX_HP))
			if int(data.get("lives", MAX_LIVES)) <= 0:
				_net_out[from_id] = true
		"shot":
			if weapons._actors.has(rid):
				var ra2: Dictionary = weapons._actors[rid]
				var w: String = str(data.get("w", "pistol"))
				if ra2.weapon != w:
					weapons.give_weapon(rid, w)
				ra2.cooldown = 0.0
				ra2.stun_left = 0.0
				weapons.set_aim(rid, Vector2(float(data.get("ax", 1.0)), float(data.get("ay", 0.0))))
				weapons.try_shoot(rid)
		"dash":
			if weapons._actors.has(rid):
				var ra3: Dictionary = weapons._actors[rid]
				ra3.charge = float(data.get("pow", 0.0))
				ra3.stun_left = 0.0
				weapons.set_aim(rid, Vector2(float(data.get("ax", 1.0)), float(data.get("ay", 0.0))))
				weapons.release_dash(rid)
		"bdmg":
			if _is_host:
				# Their dash/backfire landed — kill any replayed dash so the
				# generic melee pass can't double-bill the same contact
				if weapons._actors.has(rid):
					weapons._actors[rid].dash_time = 0.0
				boss.take_damage(int(data.get("d", 1)), Vector2(float(data.get("dx", 0.0)), float(data.get("dy", 0.0))))
		"bos":
			if not _is_host:
				_apply_boss_state(data)
		"bpj":
			if not _is_host:
				weapons._projectiles.append({
					"pos": Vector2(float(data.x), float(data.y)),
					"vel": Vector2(float(data.vx), float(data.vy)),
					"team": 1, "dmg": int(data.get("d", 1)), "life": float(data.get("l", 3.0)),
					"color": Color(float(data.get("cr", 1.0)), float(data.get("cg", 0.4)), float(data.get("cb", 0.4))),
					"size": float(data.get("s", 3.2)),
				})
		"brk":
			if not _is_host:
				_apply_break(str(data.get("k", "tile")), float(data.get("a", 0.0)), float(data.get("b", 0.0)))
		"hit":
			if int(data.get("tgt", -1)) == NetPlay.my_id():
				_hurt_player(int(data.get("d", 1)), Vector2(float(data.get("dx", 0.0)), float(data.get("dy", 0.0))))
		"psh":
			if int(data.get("tgt", -1)) == NetPlay.my_id() and is_instance_valid(player):
				player.physics._speedX += float(data.get("x", 0.0))
				player.physics._speedY += float(data.get("y", 0.0))
		"out":
			_net_out[from_id] = true
			if _is_host and not _over and not _any_ball_alive():
				NetPlay.send_mode({"m": "blose"})
				_end(false)
		"bwin":
			if not _over:
				_end(true)
		"blose":
			if not _over:
				_end(false)
		"_host_left":
			if not _over:
				_over = true
				_result_label.text = "HOST  LOST"
				_result_label.add_theme_color_override("font_color", Color(1.0, 0.7, 0.3))
				_result_sub.text = "The lobby host disconnected — the Warden fades away."
				_result_panel.visible = true


func _apply_boss_state(data: Dictionary) -> void:
	var new_phase: int = int(data.get("ph", boss.phase))
	if new_phase != boss.phase:
		boss.phase = new_phase
		boss._shake = 5.0
		weapons.spawn_ring(boss.pos, boss.phase_color(), 8.0, 90.0, 0.4)
		GameState.cam_shake = maxf(GameState.cam_shake, 5.0)
	var new_hp: int = int(data.get("hp", boss.hp))
	if new_hp < boss.hp:
		boss._flash = 0.14
	boss.hp = new_hp
	boss.max_hp = int(data.get("mhp", boss.max_hp))
	boss.net_pos_target = Vector2(float(data.get("x", boss.pos.x)), float(data.get("y", boss.pos.y)))
	if boss.pos == Vector2(512.0, 240.0) and boss.net_pos_target != Vector2.ZERO:
		boss.pos = boss.net_pos_target
	boss.vel = Vector2(float(data.get("vx", 0.0)), float(data.get("vy", 0.0)))
	boss.state = int(data.get("st", boss.state))
	boss.st_t = float(data.get("stt", boss.st_t))
	boss.beam_dir = Vector2(float(data.get("bdx", 1.0)), float(data.get("bdy", 0.0)))
	boss.beam_t = float(data.get("bt", 0.0))
	boss.slam_dir = Vector2(float(data.get("sdx", 1.0)), float(data.get("sdy", 0.0)))
	boss.cage_angle = float(data.get("ca", 0.0))
	boss.rift_pos = Vector2(float(data.get("rx", 0.0)), float(data.get("ry", 0.0)))
	var segs: Array = data.get("segs", [])
	boss.beam_segments.clear()
	var si: int = 0
	while si + 3 < segs.size():
		boss.beam_segments.append({
			"from": Vector2(float(segs[si]), float(segs[si + 1])),
			"to": Vector2(float(segs[si + 2]), float(segs[si + 3]))})
		si += 4
	var shk: Array = data.get("shk", [])
	# Rebuild only when the count changes so local `hit` marks survive updates
	if shk.size() != boss.shocks.size():
		boss.shocks.clear()
		for s in shk:
			boss.shocks.append({"x": float(s[0]), "dir": float(s[1]), "y": float(s[2]), "hit": bool(s[3])})
	else:
		for i2 in range(shk.size()):
			boss.shocks[i2].x = float(shk[i2][0])
			boss.shocks[i2].dir = float(shk[i2][1])
			boss.shocks[i2].y = float(shk[i2][2])
	var sg: Array = data.get("sg", [])
	boss.sings.clear()
	for s2 in sg:
		boss.sings.append({
			"pos": Vector2(float(s2[0]), float(s2[1])), "vel": Vector2.ZERO,
			"target": Vector2(float(s2[0]), float(s2[1])),
			"armed": bool(s2[2]), "t": float(s2[3])})


func _apply_break(kind: String, a: float, b: float) -> void:
	## Mirror a host-side terrain break exactly (force-break, no re-broadcast
	## — clients never set net_break_cb).
	match kind:
		"tile":
			weapons.damage_block(int(a), int(b), 999.0)
		"fb":
			for i in range(WorldManager.free_blocks.size()):
				var fb: Dictionary = WorldManager.free_blocks[i]
				if (fb.pos as Vector2).distance_to(Vector2(a, b)) < 3.0:
					weapons.damage_free_block(i, 999.0)
					break
		"curve":
			var ci: int = WorldManager.curve_at_point(Vector2(a, b), 10.0)
			if ci >= 0:
				weapons.damage_curve(ci, Vector2(a, b), 999.0)


func _net_pump(delta: float) -> void:
	_net_accum += delta
	if _net_accum < 0.05:
		return
	_net_accum = 0.0
	var pa: Dictionary = weapons._actors.get("player", {})
	if not pa.is_empty():
		var beam_firing: bool = Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT) and pa.weapon != "" \
				and WeaponSystem.WEAPONS.get(pa.weapon, {}).get("beam", false) and not _struggle
		NetPlay.send_mode_u({
			"m": "bs", "sh": pa.shield_on,
			"ax": pa.aim.x, "ay": pa.aim.y,
			"wpn": pa.weapon, "fire": beam_firing,
			"hp": player_hp, "lives": player_lives,
		})
	if _is_host:
		var segs: Array = []
		for s in boss.beam_segments:
			segs.append(s.from.x)
			segs.append(s.from.y)
			segs.append(s.to.x)
			segs.append(s.to.y)
		var shk: Array = []
		for sh in boss.shocks:
			shk.append([sh.x, float(sh.dir), float(sh.get("y", BossMap.FLOOR_Y)), bool(sh.hit)])
		var sg: Array = []
		for s2 in boss.sings:
			sg.append([s2.pos.x, s2.pos.y, bool(s2.get("armed", false)), float(s2.get("t", 0.0))])
		NetPlay.send_mode_u({
			"m": "bos", "x": boss.pos.x, "y": boss.pos.y,
			"vx": boss.vel.x, "vy": boss.vel.y,
			"st": boss.state, "stt": boss.st_t, "ph": boss.phase,
			"hp": boss.hp, "mhp": boss.max_hp,
			"bdx": boss.beam_dir.x, "bdy": boss.beam_dir.y, "bt": boss.beam_t,
			"sdx": boss.slam_dir.x, "sdy": boss.slam_dir.y,
			"ca": boss.cage_angle, "rx": boss.rift_pos.x, "ry": boss.rift_pos.y,
			"segs": segs, "shk": shk, "sg": sg,
		})
		for pid in _pending_push:
			var v: Vector2 = _pending_push[pid]
			if v.length_squared() > 0.001:
				NetPlay.send_mode_u({"m": "psh", "tgt": pid, "x": v.x, "y": v.y})
		_pending_push.clear()


func _build_hud() -> void:
	_hud = CanvasLayer.new()
	_hud.layer = 30
	add_child(_hud)

	var top: PanelContainer = PanelContainer.new()
	top.name = "BossPanel"
	top.add_theme_stylebox_override("panel", EditorToolsDock.make_panel_style())
	_hud.add_child(top)
	var v: VBoxContainer = VBoxContainer.new()
	v.add_theme_constant_override("separation", 3)
	top.add_child(v)
	_name_label = Label.new()
	_name_label.text = "T H E   W A R D E N"
	_name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_name_label.add_theme_font_size_override("font_size", 20)
	_name_label.add_theme_color_override("font_color", Color(1.0, 0.3, 0.32))
	_name_label.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.9))
	_name_label.add_theme_constant_override("shadow_offset_y", 2)
	v.add_child(_name_label)
	_boss_bar = Control.new()
	_boss_bar.custom_minimum_size = Vector2(540, 18)
	_boss_bar.draw.connect(_draw_boss_bar)
	v.add_child(_boss_bar)
	_proto_label = Label.new()
	_proto_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_proto_label.add_theme_font_size_override("font_size", 10)
	_proto_label.add_theme_color_override("font_color", Color(0.6, 0.65, 0.8))
	v.add_child(_proto_label)
	_player_label = Label.new()
	_player_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_player_label.add_theme_font_size_override("font_size", 12)
	v.add_child(_player_label)
	# Inventory bar: pinned TOP-LEFT of the screen
	_slot_bar = Control.new()
	_slot_bar.position = Vector2(12, 10)
	_slot_bar.custom_minimum_size = Vector2(140, 40)
	_slot_bar.draw.connect(_draw_slots)
	_hud.add_child(_slot_bar)

	_intro_label = Label.new()
	_intro_label.text = "THE  WARDEN  AWAKENS"
	_intro_label.add_theme_font_size_override("font_size", 46)
	_intro_label.add_theme_color_override("font_color", Color(1.0, 0.32, 0.3))
	_intro_label.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.9))
	_intro_label.add_theme_constant_override("shadow_offset_x", 3)
	_intro_label.add_theme_constant_override("shadow_offset_y", 3)
	_hud.add_child(_intro_label)

	_mash_label = Label.new()
	_mash_label.text = "⚔  DEFEND!  MASH LMB!!  ⚔"
	_mash_label.add_theme_font_size_override("font_size", 30)
	_mash_label.add_theme_color_override("font_color", Color(1.0, 0.85, 0.3))
	_mash_label.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.9))
	_mash_label.add_theme_constant_override("shadow_offset_x", 2)
	_mash_label.add_theme_constant_override("shadow_offset_y", 2)
	_mash_label.visible = false
	_hud.add_child(_mash_label)

	_result_panel = PanelContainer.new()
	_result_panel.visible = false
	_result_panel.add_theme_stylebox_override("panel", EditorToolsDock.make_panel_style())
	_hud.add_child(_result_panel)
	var rv: VBoxContainer = VBoxContainer.new()
	rv.add_theme_constant_override("separation", 10)
	_result_panel.add_child(rv)
	_result_label = Label.new()
	_result_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_result_label.add_theme_font_size_override("font_size", 38)
	rv.add_child(_result_label)
	_result_sub = Label.new()
	_result_sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_result_sub.add_theme_font_size_override("font_size", 13)
	_result_sub.add_theme_color_override("font_color", Color(0.75, 0.75, 0.85))
	rv.add_child(_result_sub)
	var menu_btn: Button = EditorToolsDock.make_button("Return to Menu", Color(0.3, 0.4, 0.6))
	menu_btn.custom_minimum_size = Vector2(200, 34)
	menu_btn.pressed.connect(_return_to_menu)
	rv.add_child(menu_btn)


func _draw_slots() -> void:
	weapons.draw_player_slots(_slot_bar, Vector2.ZERO)


func _draw_boss_bar() -> void:
	var w: float = _boss_bar.size.x
	var h: float = _boss_bar.size.y
	var frac: float = 0.0
	if boss and boss.max_hp > 0:
		frac = float(boss.hp) / float(boss.max_hp)
	_boss_bar.draw_rect(Rect2(0, 0, w, h), Color(0.05, 0.04, 0.08, 0.95))
	# Delayed damage chip (white trail behind the real bar)
	if _bar_chip > frac:
		_boss_bar.draw_rect(Rect2(2, 2, (w - 4.0) * _bar_chip, h - 4.0), Color(1.0, 0.9, 0.85, 0.55))
	var col: Color = boss.phase_color() if boss else Color(1, 0, 0)
	_boss_bar.draw_rect(Rect2(2, 2, (w - 4.0) * frac, h - 4.0), col)
	_boss_bar.draw_rect(Rect2(2, 2, (w - 4.0) * frac, (h - 4.0) * 0.4), Color(1, 1, 1, 0.25))
	# Phase notches at every fifth (5 phases)
	for notch in [0.2, 0.4, 0.6, 0.8]:
		_boss_bar.draw_line(Vector2(2.0 + (w - 4.0) * notch, 1.0), Vector2(2.0 + (w - 4.0) * notch, h - 1.0), Color(0, 0, 0, 0.8), 2.0)
	_boss_bar.draw_rect(Rect2(0.5, 0.5, w - 1.0, h - 1.0), Color(col.r, col.g, col.b, 0.8), false, 1.5)


func _hurt_player(dmg: int, dir: Vector2) -> void:
	if _over or _player_invuln > 0.0 or player._is_dead or _struggle:
		return
	player_hp -= dmg
	_player_invuln = 0.15
	player.physics._speedX += dir.x * 2.2
	player.physics._speedY += dir.y * 2.2
	GameState.cam_shake += 4.0
	if player_hp <= 0:
		player._die()


func _on_player_died() -> void:
	if _over:
		return
	weapons.spawn_explosion(Vector2(player.physics.x + 8.0, player.physics.y + 8.0), Color(0.4, 0.8, 1.0))
	weapons.strip_weapon("player")
	if _struggle:
		_exit_struggle()
		boss.end_beam(0.1)
	player_lives -= 1
	player_hp = MAX_HP
	_player_invuln = INVULN_TIME + 0.7
	if player_lives <= 0:
		if net:
			# DOWN — spectate in god mode; the fight ends when every ball is out
			_eliminated = true
			_net_out[NetPlay.my_id()] = true
			NetPlay.send_mode({"m": "out"})
			if is_instance_valid(player):
				player.physics.is_god_mode = true
			if _is_host and not _any_ball_alive():
				NetPlay.send_mode({"m": "blose"})
				_end(false)
		else:
			_end(false)


func _on_boss_died() -> void:
	if not _over:
		if net and _is_host:
			NetPlay.send_mode({"m": "bwin"})
		_end(true)


func _end(player_won: bool) -> void:
	_over = true
	if _struggle:
		_exit_struggle()
	if player_won:
		_result_label.text = "WARDEN  DESTROYED"
		_result_label.add_theme_color_override("font_color", Color(0.3, 1.0, 0.4))
		_result_sub.text = "The chamber falls silent. You are the storm."
	else:
		_result_label.text = "SYSTEM  PURGED"
		_result_label.add_theme_color_override("font_color", Color(1.0, 0.35, 0.3))
		_result_sub.text = "The Warden endures. Parry the slam, block or outrun the laser."
	_result_panel.visible = true


func _return_to_menu() -> void:
	NetPlay.leave_room()
	GameState.battle_mode = false
	GameState.boss_fight = false
	GameState.cam_shake = 0.0
	GameState.player_stunned = false
	GameState.net_freeze = false
	NetworkManager.disconnect_game()
	get_tree().change_scene_to_file("res://scenes/ui/main_menu.tscn")


func _process(delta: float) -> void:
	if _player_invuln > 0.0:
		_player_invuln -= delta
	# Player stun visual (parity with battle mode; the Warden doesn't stun)
	var p_stunned: bool = weapons.is_stunned("player")
	GameState.player_stunned = p_stunned and not _struggle
	if is_instance_valid(player) and player._smiley_sprite:
		if p_stunned:
			var strobe: float = 0.5 + 0.5 * sin(Time.get_ticks_msec() * 0.03)
			player._smiley_sprite.modulate = Color(1.0, 1.0, 0.45).lerp(Color(1.0, 0.75, 0.3), strobe)
			_player_was_stunned = true
		elif _player_was_stunned:
			player._smiley_sprite.modulate = Color.WHITE
			_player_was_stunned = false
	if _intro_timer > 0.0:
		_intro_timer -= delta
		_intro_label.modulate.a = clampf(_intro_timer / 1.0, 0.0, 1.0)
		if _intro_timer <= 0.0:
			_intro_label.visible = false
	# Bar chip eases down toward the real HP
	if boss and boss.max_hp > 0:
		_bar_chip = maxf(float(boss.hp) / float(boss.max_hp), _bar_chip - delta * 0.25)
	if _boss_bar:
		_boss_bar.queue_redraw()
	if _slot_bar:
		_slot_bar.queue_redraw()
	if _over:
		_layout_hud()
		return
	if net:
		_net_pump(delta)

	var p_ok: bool = is_instance_valid(player) and not player._is_dead and not _eliminated
	var pc: Vector2 = Vector2(player.physics.x + 8.0, player.physics.y + 8.0) if p_ok else Vector2.ZERO

	# Online: armed singularities drag MY ball in (victim-side gravity)
	if net and p_ok:
		for s in boss.sings:
			if not s.get("armed", false):
				continue
			var to_s: Vector2 = (s.pos as Vector2) - pc
			var sd: float = to_s.length()
			if sd > 6.0 and sd < 260.0:
				var pull: Vector2 = to_s / sd * delta * clampf(340.0 / maxf(sd * 0.22, 8.0), 1.0, 9.0)
				player.physics._speedX += pull.x
				player.physics._speedY += pull.y

	# ── Active abilities: ZERO-G flight + NANO-MEND regen ──
	if p_ok:
		var pab: Dictionary = weapons._actors["player"]
		player.physics.force_dot = pab.get("abil_fly", 0.0) > 0.0
		if pab.get("abil_regen", 0.0) > 0.0:
			_regen_tick -= delta
			if _regen_tick <= 0.0:
				_regen_tick = 2.5
				if player_hp < MAX_HP:
					player_hp += 1
					weapons.spawn_ring(pc, Color(0.4, 1.0, 0.5), 4.0, 20.0, 0.25)
		else:
			_regen_tick = 0.6

	# ── Body contact vs the Warden: ram bounces, dash punches land ──
	# (not while it's rifted away — the void has no hull)
	if p_ok and boss.alive() and boss.state != BossController.ST_RIFT_GONE:
		var dvec: Vector2 = pc - boss.pos
		var d: float = dvec.length()
		if d < BossController.BODY_R + 10.0 and d > 0.01:
			var n: Vector2 = dvec / d
			# Push the ball out (the Warden is an anchor), never into tiles
			var want: Vector2 = n * (BossController.BODY_R + 10.0 - d)
			if not player.physics._collides_px(player.physics.x + want.x, player.physics.y + want.y):
				player.physics.x += want.x
				player.physics.y += want.y
			var pa: Dictionary = weapons._actors["player"]
			var pv: Vector2 = Vector2(player.physics._speedX, player.physics._speedY)
			if pa.dash_time > 0.0 and boss.state != BossController.ST_SLAM:
				# Dash punch connects — chunk the armor, bounce off it
				pa.dash_time = 0.0
				_deal_boss(pa.dash_dmg, -n)
				var out_v: Vector2 = n * maxf(pv.length() * 0.9, 6.0)
				player.physics._speedX = out_v.x
				player.physics._speedY = out_v.y
				weapons.spawn_hit(boss.pos + n * BossController.BODY_R, Color(0.7, 0.95, 1.0), n)
				weapons.spawn_ring(boss.pos + n * BossController.BODY_R, Color(0.7, 0.95, 1.0), 4.0, 26.0, 0.2)
				weapons.play_sfx("hit", pc, 0.05, 0.9)
				GameState.cam_shake += 4.0
			elif boss.state != BossController.ST_SLAM:
				# Plain ram: full-force bounce off the hull
				var into: float = pv.dot(-n)
				if into > 0.3:
					var out_v2: Vector2 = n * maxf(pv.length() * 1.05, 3.0)
					player.physics._speedX = out_v2.x
					player.physics._speedY = out_v2.y
					if into > 1.2:
						weapons.play_sfx("bonk", pc, 0.08, 1.1)
						weapons.spawn_hit(pc, Color(0.9, 0.95, 1.0), n)

	# ── Annihilation beam: shield BLOCKS it, full-speed running outruns it ──
	var beam_like: bool = boss.state == BossController.ST_BEAM or boss.state == BossController.ST_CAGE
	if beam_like and p_ok:
		# The laser path is a chain of segments (wall ricochets / the four
		# cage beams) — a reflected branch can catch you from behind
		var is_cage: bool = boss.state == BossController.ST_CAGE
		var corr_r: float = 24.0 if is_cage else 34.0
		var in_corridor: bool = false
		var hit_dir: Vector2 = boss.beam_dir
		for seg_d in boss.beam_segments:
			var sv: Vector2 = seg_d.to - seg_d.from
			if sv.length_squared() < 1.0:
				continue
			var st: float = clampf((pc - seg_d.from).dot(sv) / sv.length_squared(), 0.0, 1.0)
			if pc.distance_squared_to(seg_d.from + sv * st) < corr_r * corr_r:
				in_corridor = true
				hit_dir = sv.normalized()
				break
		if in_corridor:
			if weapons.is_shielded("player"):
				# BLOCKED — the shield simply grinds against the ray: steady
				# drain, zero damage, light pressure. No clash minigame.
				var pa3: Dictionary = weapons._actors["player"]
				pa3["shield_energy"] = maxf(0.0, pa3["shield_energy"] - delta * 0.85)
				player.physics._speedX += hit_dir.x * delta * 8.0
				if randf() < delta * 160.0:
					weapons.spawn_trail_dot(pc - hit_dir * 12.0, hit_dir.orthogonal() * randf_range(-220.0, 220.0), Color(0.6, 0.95, 1.0))
				_beam_tick = 0.32
			else:
				_beam_tick -= delta
				if _beam_tick <= 0.0:
					_beam_tick = 0.32
					_hurt_player(1, hit_dir)
				player.physics._speedX += hit_dir.x * delta * 26.0
				player.physics._speedY += (hit_dir.y - 0.2) * delta * 26.0
		else:
			_beam_tick = 0.05

	# ── Floor shockwaves vs the player (jump them!) ──
	if p_ok:
		for sh in boss.shocks:
			if sh.hit:
				continue
			var sh_y: float = sh.get("y", BossMap.FLOOR_Y)
			if player.physics.is_grounded and absf(pc.y - sh_y) < 34.0 and absf(pc.x - sh.x) < 16.0:
				sh.hit = true
				_hurt_player(1, Vector2(sh.dir, -0.6).normalized())
				player.physics._speedX += sh.dir * 4.0
				player.physics._speedY -= 7.0
				weapons.spawn_hit(Vector2(sh.x, sh_y - 12.0), boss.phase_color(), Vector2(0, -1))

	# ── Player input: aim/shoot/dash/shield (skipped during the clash) ──
	if p_ok and not _struggle:
		var aim: Vector2 = weapons.get_global_mouse_position() - pc
		weapons.set_aim("player", aim)
		# Inventory: 1 = fists, 2 = blaster/DOOM, 3 = scatter
		if Input.is_physical_key_pressed(KEY_1):
			weapons.select_slot("player", 1)
		elif Input.is_physical_key_pressed(KEY_2):
			weapons.select_slot("player", 2)
		elif Input.is_physical_key_pressed(KEY_3):
			weapons.select_slot("player", 3)
		var unarmed: bool = weapons.get_weapon("player") == ""
		# RMB: parry shield — works armed too (firing drops it briefly)
		weapons.set_shield("player", Input.is_mouse_button_pressed(MOUSE_BUTTON_RIGHT) and not GameState.is_edit_mode)
		var lmb: bool = Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT) and not GameState.is_edit_mode
		if unarmed:
			if lmb:
				weapons.charge_dash("player", delta)
			elif _lmb_was_down:
				var res: Dictionary = weapons.release_dash("player")
				if res.ok:
					var ddir: Vector2 = aim.normalized()
					var imp: float = 7.0 + 10.0 * res.power
					player.physics._speedX += ddir.x * imp
					player.physics._speedY += ddir.y * imp
					if net:
						NetPlay.send_mode({"m": "dash", "pow": res.power, "ax": aim.x, "ay": aim.y})
		elif lmb and weapons.try_shoot("player"):
			var kick: float = weapons.get_kick("player")
			var wn: String = weapons.get_weapon("player")
			if wn != "" and WeaponSystem.WEAPONS[wn].get("beam", false):
				kick *= delta * 6.0
			elif net and wn != "":
				NetPlay.send_mode({"m": "shot", "w": wn, "ax": aim.x, "ay": aim.y})
			var kdir: Vector2 = aim.normalized()
			player.physics._speedX -= kdir.x * kick
			player.physics._speedY -= kdir.y * kick
		_lmb_was_down = lmb
	_layout_hud()


func _enter_struggle() -> void:
	_struggle = true
	_clash_t = 0.72
	_struggle_timer = 0.0
	boss.struggle_freeze = true
	boss.struggle_active = true
	weapons.play_sfx("doom_spawn", Vector2(player.physics.x + 8.0, player.physics.y + 8.0), 0.0, 1.5)
	weapons.spawn_ring(Vector2(player.physics.x + 8.0, player.physics.y + 8.0), Color(0.6, 0.95, 1.0), 6.0, 44.0, 0.3)
	GameState.cam_shake += 6.0


func _on_ability(kind: String) -> void:
	if kind == "mend":
		player_hp = mini(MAX_HP, player_hp + 2)
	GameState.cam_shake += 2.0


func _exit_struggle() -> void:
	_struggle = false
	boss.struggle_freeze = false
	boss.struggle_active = false
	_mash_label.visible = false
	_beam_tick = 0.45  # Never an instant damage tick right after a clash


func _layout_hud() -> void:
	var vps: Vector2 = get_viewport().get_visible_rect().size
	var top: PanelContainer = _hud.get_node_or_null("BossPanel") as PanelContainer
	if top:
		var protos: Array = ["SENTINEL PROTOCOL", "WRATH PROTOCOL", "ANNIHILATION PROTOCOL", "VOID PROTOCOL", "OMEGA PROTOCOL"]
		_proto_label.text = "%s   —   PHASE %d/5" % [protos[boss.phase - 1], boss.phase]
		var hearts: String = ""
		for i in range(player_lives):
			hearts += "♥ "
		var wname: String = weapons.get_weapon("player")
		var pa_hud: Dictionary = weapons._actors["player"]
		var wtext: String
		if wname != "":
			wtext = WeaponSystem.WEAPONS[wname].label
			if weapons._actors["player"].weapon_left > 0.0:
				wtext += " %.1fs" % weapons._actors["player"].weapon_left
		else:
			wtext = "FISTS — dash punch, parry shield"
		if pa_hud.get("abil_fly", 0.0) > 0.0:
			wtext += "   ✦ ZERO-G %.0fs" % pa_hud.abil_fly
		if pa_hud.get("abil_od", 0.0) > 0.0:
			wtext += "   ⚡ OVERDRIVE %.0fs" % pa_hud.abil_od
		if pa_hud.get("abil_regen", 0.0) > 0.0:
			wtext += "   ✚ MEND %.0fs" % pa_hud.abil_regen
		if weapons.super_pos != Vector2.ZERO:
			_player_label.text = "%s  |  HP %d/%d  |  %s  |  %s" % [hearts.strip_edges(), player_hp, MAX_HP, wtext, weapons.get_super_status()]
		else:
			_player_label.text = "%s  |  HP %d/%d  |  %s" % [hearts.strip_edges(), player_hp, MAX_HP, wtext]
		top.position = Vector2(vps.x / 2.0 - top.size.x / 2.0, 8)
	if _intro_label.visible:
		_intro_label.position = Vector2(vps.x / 2.0 - _intro_label.size.x / 2.0, vps.y * 0.30)
	if _mash_label.visible:
		_mash_label.position = Vector2(vps.x / 2.0 - _mash_label.size.x / 2.0, vps.y * 0.68)
	if _result_panel.visible:
		_result_panel.position = Vector2(vps.x / 2.0 - _result_panel.size.x / 2.0, vps.y * 0.34)
