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

# Beam struggle
var _struggle: bool = false
var _clash_t: float = 0.45       # 0 = at the boss, 1 = at the player
var _struggle_timer: float = 0.0

var _hud: CanvasLayer
var _boss_bar: Control
var _bar_chip: float = 1.0       # Delayed white damage trail
var _name_label: Label
var _proto_label: Label
var _player_label: Label
var _intro_label: Label
var _mash_label: Label
var _result_panel: PanelContainer
var _result_label: Label
var _result_sub: Label


func _ready() -> void:
	player = get_parent()._get_player(1)
	weapons = WeaponSystem.new()
	get_parent().add_child.call_deferred(weapons)
	boss = BossController.new()
	get_parent().add_child.call_deferred(boss)
	_build_hud()
	call_deferred("_wire_up")


func _wire_up() -> void:
	# Only the DOOM RAY appears in the world; guns are the permanent
	# slots 2/3 loadout when the toggle is ON
	weapons.super_pos = BossMap.SUPER_POS
	boss.max_hp = 90 if GameState.battle_guns_enabled else 42
	boss.hp = boss.max_hp
	boss.ws = weapons
	boss.min_x = BossMap.BOUNDS_MIN_X
	boss.max_x = BossMap.BOUNDS_MAX_X
	boss.min_y = BossMap.BOUNDS_MIN_Y
	boss.floor_y = BossMap.FLOOR_Y
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
	if player.has_signal("died"):
		player.died.connect(_on_player_died)


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
	# Phase notches at 2/3 and 1/3
	for notch in [1.0 / 3.0, 2.0 / 3.0]:
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
		_end(false)


func _on_boss_died() -> void:
	if not _over:
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
		_result_sub.text = "The Warden endures. Study its telegraphs — parry the slam, mash the clash."
	_result_panel.visible = true


func _return_to_menu() -> void:
	GameState.battle_mode = false
	GameState.boss_fight = false
	GameState.cam_shake = 0.0
	GameState.player_stunned = false
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
	if _over:
		_layout_hud()
		return

	var p_ok: bool = is_instance_valid(player) and not player._is_dead
	var pc: Vector2 = Vector2(player.physics.x + 8.0, player.physics.y + 8.0) if p_ok else Vector2.ZERO

	# ── Body contact vs the Warden: ram bounces, dash punches land ──
	if p_ok and boss.alive():
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
				boss.take_damage(pa.dash_dmg, -n)
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

	# ── Annihilation beam: damage or THE CLASH ──
	if boss.state == BossController.ST_BEAM and p_ok:
		# The laser path is a chain of segments (wall ricochets included) —
		# a reflected branch can catch you from behind
		var in_corridor: bool = false
		var hit_dir: Vector2 = boss.beam_dir
		for seg_d in boss.beam_segments:
			var sv: Vector2 = seg_d.to - seg_d.from
			if sv.length_squared() < 1.0:
				continue
			var st: float = clampf((pc - seg_d.from).dot(sv) / sv.length_squared(), 0.0, 1.0)
			if pc.distance_squared_to(seg_d.from + sv * st) < 34.0 * 34.0:
				in_corridor = true
				hit_dir = sv.normalized()
				break
		if not _struggle:
			if in_corridor:
				var has_doom: bool = weapons.get_weapon("player") == "doom"
				if weapons.is_shielded("player") or has_doom:
					_enter_struggle()
				else:
					_beam_tick -= delta
					if _beam_tick <= 0.0:
						_beam_tick = 0.32
						_hurt_player(1, hit_dir)
					player.physics._speedX += hit_dir.x * delta * 26.0
					player.physics._speedY += (hit_dir.y - 0.2) * delta * 26.0
			else:
				_beam_tick = 0.05
	elif _struggle:
		_exit_struggle()

	# ── THE CLASH: mash LMB to shove the beam back into the Warden ──
	if _struggle and p_ok:
		boss.struggle_freeze = true
		boss.struggle_active = true
		_struggle_timer += delta
		var has_doom2: bool = weapons.get_weapon("player") == "doom"
		# Shield is pinned up (fists) and can't die mid-clash
		if not has_doom2:
			weapons.set_shield("player", true)
			weapons._actors["player"]["shield_energy"] = maxf(weapons._actors["player"]["shield_energy"], 0.35)
		# Planted stance — the clash IS the fight right now
		player.physics._speedX *= pow(0.002, delta)
		# BRUTAL: the Warden pushes at 10 clicks/second — mashing 10cps only
		# HOLDS the clash. Surviving the 6s is the real goal; actually
		# shoving it back into the Warden's face is god-tier (or DOOM-armed:
		# counter-beam clicks count double).
		var pull: float = [0.50, 0.56, 0.62][boss.phase - 1]
		_clash_t += pull * delta
		var lmb_now: bool = Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT)
		if lmb_now and not _lmb_was_down:
			_clash_t -= 0.05 * (2.0 if has_doom2 else 1.0)
			var clash: Vector2 = boss.beam_muzzle().lerp(pc, clampf(_clash_t, 0.0, 1.0))
			weapons.spawn_hit(clash, Color(1, 1, 0.9), (boss.pos - pc).normalized())
			weapons.play_sfx("hit", clash, 0.1, 1.6)
			GameState.cam_shake += 1.5
		_lmb_was_down = lmb_now
		boss.clash_point = boss.beam_muzzle().lerp(pc, clampf(_clash_t, 0.0, 1.0))
		if randf() < delta * 200.0:
			var perp: Vector2 = boss.beam_dir.orthogonal()
			weapons.spawn_trail_dot(boss.clash_point, perp * randf_range(-260.0, 260.0), Color(0.6, 1.0, 0.6) if randf() < 0.6 else Color(0.6, 0.95, 1.0))
		GameState.cam_shake = maxf(GameState.cam_shake, lerpf(7.0, 2.5, _clash_t))
		if _clash_t <= 0.06:
			# WON THE CLASH — the beam backfires
			var mz2: Vector2 = boss.beam_muzzle()
			for k in range(4):
				weapons.spawn_ring(mz2.lerp(pc, 0.25 * k), Color(1.0, 0.8, 0.4), 6.0, 40.0, 0.3)
			weapons._actors["player"]["shield_energy"] = WeaponSystem.SHIELD_MAX
			weapons._actors["player"]["shield_broken"] = false
			boss.struggle_backfire()
			_exit_struggle()
		elif _clash_t >= 0.99:
			# LOST THE CLASH — blasted down-beam
			_exit_struggle()
			boss.end_beam(0.15)
			_player_invuln = 0.0
			_hurt_player(3, boss.beam_dir)
			player.physics._speedX += boss.beam_dir.x * 13.0
			player.physics._speedY += boss.beam_dir.y * 13.0 - 5.0
			weapons._actors["player"]["shield_energy"] = 0.0
			weapons._actors["player"]["shield_broken"] = true
			weapons.spawn_explosion(pc, Color(1.0, 0.5, 0.2))
			GameState.cam_shake += 10.0
		elif _struggle_timer > 6.0:
			# Stalemate — both thrown back, no damage
			weapons.spawn_ring(boss.clash_point, Color(1, 1, 1), 8.0, 60.0, 0.35)
			boss.end_beam(0.1)
			player.physics._speedX += -boss.beam_dir.x * 6.0
			player.physics._speedY += -3.0
			_exit_struggle()
	_mash_label.visible = _struggle
	if _struggle:
		_mash_label.modulate.a = 0.6 + 0.4 * sin(Time.get_ticks_msec() * 0.02)

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
		elif lmb and weapons.try_shoot("player"):
			var kick: float = weapons.get_kick("player")
			var wn: String = weapons.get_weapon("player")
			if wn != "" and WeaponSystem.WEAPONS[wn].get("beam", false):
				kick *= delta * 6.0
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


func _exit_struggle() -> void:
	_struggle = false
	boss.struggle_freeze = false
	boss.struggle_active = false
	_mash_label.visible = false


func _layout_hud() -> void:
	var vps: Vector2 = get_viewport().get_visible_rect().size
	var top: PanelContainer = _hud.get_node_or_null("BossPanel") as PanelContainer
	if top:
		var protos: Array = ["SENTINEL PROTOCOL", "WRATH PROTOCOL", "ANNIHILATION PROTOCOL"]
		_proto_label.text = "%s   —   PHASE %d/3" % [protos[boss.phase - 1], boss.phase]
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
		var s2: String = "DOOM %.0fs" % maxf(pa_hud.get("super_left", 0.0), 0.0) if pa_hud.get("super_left", 0.0) > 0.0 else ("blaster" if pa_hud.get("loadout", false) else "—")
		var s3: String = "scatter" if pa_hud.get("loadout", false) else "—"
		wtext += "   [1 fists · 2 %s · 3 %s]" % [s2, s3]
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
