class_name BattleMode
extends Node
## Battle Arena: offline FFA vs 1-3 hard AI bots (1v1 up to 1v1v1v1).
## 10 lives each, 5 HP per life, weapons from pads, spikes count as deaths.
## Every bot is on its OWN team — they hunt each other exactly as hard as
## they hunt you, and each targets its nearest living enemy. Last ball
## rolling wins. Created by game_scene when GameState.battle_mode is set.

const MAX_LIVES: int = 10
const MAX_HP: int = 5
const INVULN_TIME: float = 1.2
const BOT_TINTS: Array = [
	Color(1.0, 0.55, 0.55),   # BOT 1 — crimson
	Color(0.72, 0.58, 1.0),   # BOT 2 — violet
	Color(1.0, 0.78, 0.42),   # BOT 3 — amber
]
const INITIAL_BOT_SPOTS: Array = [Vector2(77, 30), Vector2(67, 30), Vector2(60, 27)]

var player: Node = null
var weapons: WeaponSystem = null
var bots: Array = []             # BotController per enemy
var bots_lives: Array = []
var bots_hp: Array = []
var _bots_invuln: Array = []
var _bots_respawn: Array = []    # >0 = respawn countdown; <=0 = idle/eliminated

var player_lives: int = MAX_LIVES
var player_hp: int = MAX_HP
var _player_invuln: float = 0.0
var _over: bool = false
var _fight_timer: float = 1.6

var _lmb_was_down: bool = false
var _player_was_stunned: bool = false
var _hud: CanvasLayer
var _score_label: Label
var _weapon_label: Label
var _fight_label: Label
var _result_panel: PanelContainer
var _result_label: Label
var _result_sub: Label


func _ready() -> void:
	player = get_parent()._get_player(1)
	# World-space combat layer
	weapons = WeaponSystem.new()
	get_parent().add_child.call_deferred(weapons)
	# The bots — each on its own team (true free-for-all)
	var n: int = clampi(GameState.battle_bot_count, 1, 3)
	for i in range(n):
		var b: BotController = BotController.new()
		b.actor_id = _bot_id(i)
		b.team_id = i + 1
		b.display_name = "BOT" if n == 1 else "BOT %d" % (i + 1)
		b.tint = BOT_TINTS[i % BOT_TINTS.size()]
		b._ai_timer = 0.011 * i  # Stagger the think ticks across frames
		bots.append(b)
		bots_lives.append(MAX_LIVES)
		bots_hp.append(MAX_HP)
		_bots_invuln.append(0.0)
		_bots_respawn.append(-1.0)
		get_parent().add_child.call_deferred(b)
	_build_hud()
	call_deferred("_wire_up")


func _bot_id(i: int) -> String:
	return "bot%d" % (i + 1)


func _wire_up() -> void:
	if GameState.battle_guns_enabled:
		BattleMap.add_weapon_pads(weapons)
	else:
		# Guns OFF: pure dash & parry — but the DOOM RAY still drops every
		# 60s as the chaos prize
		weapons.super_pos = BattleMap.SUPER_POS
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
	for i in range(bots.size()):
		var idx: int = i
		var b: BotController = bots[i]
		b.weapon_system = weapons
		# FFA targeting: every callable resolves the NEAREST living enemy
		# (the player or any other bot) at call time
		b.get_player_center = func() -> Vector2: return _nearest_enemy(idx).get("center", Vector2(768.0, 300.0))
		b.get_player_vel = func() -> Vector2: return _nearest_enemy(idx).get("vel", Vector2.ZERO)
		b.is_player_alive = func() -> bool: return not _over and not _nearest_enemy(idx).is_empty()
		b.get_target_id = func() -> String: return _nearest_enemy(idx).get("id", "player")
		b.spawn_at(INITIAL_BOT_SPOTS[i % INITIAL_BOT_SPOTS.size()])
		weapons.register_actor(_bot_id(i), i + 1,
			b.get_center, b.get_vel_pxs,
			func() -> bool: return not b.dead,
			_hurt_bot.bind(idx),
			func() -> int: return bots_hp[idx], MAX_HP,
			func() -> bool: return b.physics.is_grounded,
			func(v: Vector2) -> void:
				b.physics._speedX += v.x
				b.physics._speedY += v.y)
	if player.has_signal("died"):
		player.died.connect(_on_player_died)


func _nearest_enemy(idx: int) -> Dictionary:
	## Nearest LIVING enemy of bot idx in the FFA: the player or another bot.
	## Empty dictionary when nothing is left to fight.
	var my_c: Vector2 = bots[idx].get_center()
	var best: Dictionary = {}
	var best_d: float = 1e18
	if is_instance_valid(player) and not player._is_dead:
		var pc: Vector2 = Vector2(player.physics.x + 8.0, player.physics.y + 8.0)
		best_d = pc.distance_squared_to(my_c)
		best = {
			"id": "player",
			"center": pc,
			"vel": Vector2(player.physics._speedX, player.physics._speedY) * EEPhysics.EE_TICK_FRAC * EEPhysics.TPS,
		}
	for j in range(bots.size()):
		if j == idx or bots[j].dead:
			continue
		var d: float = bots[j].get_center().distance_squared_to(my_c)
		if d < best_d:
			best_d = d
			best = {"id": _bot_id(j), "center": bots[j].get_center(), "vel": bots[j].get_vel_pxs()}
	return best


func _build_hud() -> void:
	_hud = CanvasLayer.new()
	_hud.layer = 30
	add_child(_hud)

	var top: PanelContainer = PanelContainer.new()
	top.name = "ScorePanel"
	top.add_theme_stylebox_override("panel", EditorToolsDock.make_panel_style())
	_hud.add_child(top)
	var v: VBoxContainer = VBoxContainer.new()
	top.add_child(v)
	_score_label = Label.new()
	_score_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_score_label.add_theme_font_size_override("font_size", 15)
	_score_label.add_theme_color_override("font_color", Color(0.95, 0.95, 1.0))
	v.add_child(_score_label)
	_weapon_label = Label.new()
	_weapon_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_weapon_label.add_theme_font_size_override("font_size", 11)
	v.add_child(_weapon_label)

	_fight_label = Label.new()
	_fight_label.text = "FIGHT!"
	_fight_label.add_theme_font_size_override("font_size", 52)
	_fight_label.add_theme_color_override("font_color", Color(1.0, 0.6, 0.15))
	_fight_label.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.9))
	_fight_label.add_theme_constant_override("shadow_offset_x", 2)
	_fight_label.add_theme_constant_override("shadow_offset_y", 2)
	_hud.add_child(_fight_label)

	_result_panel = PanelContainer.new()
	_result_panel.visible = false
	_result_panel.add_theme_stylebox_override("panel", EditorToolsDock.make_panel_style())
	_hud.add_child(_result_panel)
	var rv: VBoxContainer = VBoxContainer.new()
	rv.add_theme_constant_override("separation", 10)
	_result_panel.add_child(rv)
	_result_label = Label.new()
	_result_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_result_label.add_theme_font_size_override("font_size", 40)
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


func _hurt_player(dmg: int, dir: Vector2) -> void:
	if _over or _player_invuln > 0.0 or player._is_dead:
		return
	player_hp -= dmg
	_player_invuln = 0.15  # Brief damage immunity — hits still visibly land
	player.physics._speedX += dir.x * 2.2
	player.physics._speedY += dir.y * 2.2
	GameState.cam_shake += 4.0
	if player_hp <= 0:
		player._die()  # died signal handles the life (and the explosion)


func _hurt_bot(dmg: int, dir: Vector2, i: int) -> void:
	if _over or _bots_invuln[i] > 0.0 or bots[i].dead:
		return
	bots_hp[i] -= dmg
	_bots_invuln[i] = 0.15
	bots[i].apply_knockback(dir, 2.2)
	if bots_hp[i] <= 0:
		_kill_bot(i)


func _kill_bot(i: int) -> void:
	var bot: BotController = bots[i]
	print("BOT DEATH [%s] at (%.0f, %.0f) tile (%d, %d) spd=(%.1f, %.1f) grounded=%s dash_t=%.2f commit=%d chold=%.2f | last_jump %dms ago: %s" % [
		_bot_id(i), bot.get_center().x, bot.get_center().y,
		int(bot.get_center().x / 16.0), int(bot.get_center().y / 16.0),
		bot.physics._speedX, bot.physics._speedY, bot.physics.is_grounded,
		weapons._actors[_bot_id(i)].dash_time, bot._committed_h, bot._charge_hold,
		Time.get_ticks_msec() - bot.last_jump_ms, bot.last_jump_info])
	weapons.spawn_explosion(bot.get_center(), bot.tint)
	weapons.strip_weapon(_bot_id(i))
	bot.set_dead(true)
	bots_lives[i] -= 1
	bots_hp[i] = MAX_HP
	if bots_lives[i] <= 0:
		# ELIMINATED — this bot stays down for the rest of the match
		_bots_respawn[i] = -1.0
		var any_alive: bool = false
		for l in bots_lives:
			if l > 0:
				any_alive = true
				break
		if not any_alive:
			_end(true)
	else:
		_bots_respawn[i] = 1.5


func _pick_spawn(avoid_px: Vector2) -> Vector2:
	## Random curated spot, preferring ones far from the opponent — no more
	## camping a fixed respawn with the DOOM RAY.
	var candidates: Array = []
	for s in BattleMap.SPAWN_SPOTS:
		if Vector2(s.x * 16.0 + 8.0, s.y * 16.0 + 8.0).distance_to(avoid_px) > 300.0:
			candidates.append(s)
	if candidates.is_empty():
		candidates = BattleMap.SPAWN_SPOTS.duplicate()
	return candidates[randi() % candidates.size()]


func _nearest_threat_to(p: Vector2) -> Vector2:
	## Center of the nearest living bot (used to pick the player's respawn
	## away from danger). Falls back to arena center when all bots are down.
	var best: Vector2 = Vector2(768.0, 300.0)
	var best_d: float = 1e18
	for i in range(bots.size()):
		if bots[i].dead:
			continue
		var d: float = bots[i].get_center().distance_squared_to(p)
		if d < best_d:
			best_d = d
			best = bots[i].get_center()
	return best


func _on_player_died() -> void:
	if _over:
		return
	# Death animation for EVERY death cause — spikes included
	var pc: Vector2 = Vector2(player.physics.x + 8.0, player.physics.y + 8.0)
	weapons.spawn_explosion(pc, Color(0.4, 0.8, 1.0))
	weapons.strip_weapon("player")
	# Random respawn away from the nearest bot (the controller respawns at index 0)
	WorldManager.spawn_points[0] = _pick_spawn(_nearest_threat_to(pc))
	player_lives -= 1
	player_hp = MAX_HP
	_player_invuln = INVULN_TIME + 0.7  # Covers the respawn delay
	if player_lives <= 0:
		_end(false)


func _end(player_won: bool) -> void:
	_over = true
	for b in bots:
		b.set_dead(true)
	if player_won:
		_result_label.text = "VICTORY!"
		_result_label.add_theme_color_override("font_color", Color(0.3, 1.0, 0.4))
		if bots.size() == 1:
			_result_sub.text = "The bot is scrap metal. %d lives remaining." % player_lives
		else:
			_result_sub.text = "All %d bots are scrap metal. %d lives remaining." % [bots.size(), player_lives]
	else:
		_result_label.text = "DEFEATED"
		_result_label.add_theme_color_override("font_color", Color(1.0, 0.35, 0.3))
		var standing: int = 0
		for l in bots_lives:
			if l > 0:
				standing += 1
		if bots.size() == 1:
			_result_sub.text = "The bot takes this one. Rematch?"
		else:
			_result_sub.text = "%d of %d bots still standing. Rematch?" % [standing, bots.size()]
	_result_panel.visible = true


func _return_to_menu() -> void:
	GameState.battle_mode = false
	GameState.cam_shake = 0.0
	GameState.player_stunned = false
	NetworkManager.disconnect_game()
	get_tree().change_scene_to_file("res://scenes/ui/main_menu.tscn")


func _process(delta: float) -> void:
	if _player_invuln > 0.0:
		_player_invuln -= delta
	for i in range(bots.size()):
		if _bots_invuln[i] > 0.0:
			_bots_invuln[i] -= delta
	# Player stun: control lock + unmissable visual (yellow strobe)
	var p_stunned: bool = weapons.is_stunned("player")
	GameState.player_stunned = p_stunned
	if is_instance_valid(player) and player._smiley_sprite:
		if p_stunned:
			var strobe: float = 0.5 + 0.5 * sin(Time.get_ticks_msec() * 0.03)
			player._smiley_sprite.modulate = Color(1.0, 1.0, 0.45).lerp(Color(1.0, 0.75, 0.3), strobe)
			_player_was_stunned = true
		elif _player_was_stunned:
			player._smiley_sprite.modulate = Color.WHITE
			_player_was_stunned = false
	if _fight_timer > 0.0:
		_fight_timer -= delta
		_fight_label.modulate.a = clampf(_fight_timer / 0.8, 0.0, 1.0)
		if _fight_timer <= 0.0:
			_fight_label.visible = false
	if _over:
		_layout_hud()
		return
	# Bot environmental deaths: hazard tiles + gravity-zone cores.
	# (The player controller already handles both for the player.)
	for i in range(bots.size()):
		if bots[i].dead:
			continue
		var env_dead: bool = GameState.hazard_at_ball(bots[i].physics.x, bots[i].physics.y)
		var bc: Vector2 = bots[i].get_center()
		for gz in WorldManager.gravity_zones.zones:
			if bc.distance_to(gz.center) < gz.get("center_radius", 8.0) + 8.0:
				env_dead = true
		if env_dead:
			_kill_bot(i)
	# Ball-vs-ball collision: EVERY living pair in the arena (player + bots)
	var balls: Array = []
	if is_instance_valid(player) and not player._is_dead:
		balls.append({"id": "player", "phys": player.physics})
	for i in range(bots.size()):
		if not bots[i].dead:
			balls.append({"id": _bot_id(i), "phys": bots[i].physics})
	for a in range(balls.size()):
		for b in range(a + 1, balls.size()):
			_collide_pair(balls[a], balls[b])
	# Bot respawns (each away from ITS nearest enemy)
	for i in range(bots.size()):
		if _bots_respawn[i] > 0.0:
			_bots_respawn[i] -= delta
			if _bots_respawn[i] <= 0.0:
				var avoid: Vector2 = _nearest_enemy(i).get("center", Vector2(768.0, 300.0))
				bots[i].spawn_at(_pick_spawn(avoid))
				_bots_invuln[i] = INVULN_TIME
	# Player aiming + shooting (LMB), blocked while editing (editing is
	# disabled in battle mode anyway) or over UI
	if is_instance_valid(player) and not player._is_dead:
		var pc2: Vector2 = Vector2(player.physics.x + 8.0, player.physics.y + 8.0)
		var aim: Vector2 = weapons.get_global_mouse_position() - pc2
		weapons.set_aim("player", aim)
		# Weapon slots: 1 = fists (full melee kit), 2 = draw the stowed gun
		if Input.is_physical_key_pressed(KEY_1):
			weapons.select_slot("player", 1)
		elif Input.is_physical_key_pressed(KEY_2):
			weapons.select_slot("player", 2)
		var unarmed: bool = weapons.get_weapon("player") == ""
		# RMB: parry shield — works armed too (firing drops it briefly)
		weapons.set_shield("player", Input.is_mouse_button_pressed(MOUSE_BUTTON_RIGHT) and not GameState.is_edit_mode)
		var lmb: bool = Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT) and not GameState.is_edit_mode
		if unarmed:
			# LMB: hold to CHARGE (3s = full power), release to dash.
			# A quick click is a normal dash; a full charge hits for 2.
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
				kick *= delta * 6.0  # Beams fire every frame — gentle steady pushback
			var kdir: Vector2 = aim.normalized()
			player.physics._speedX -= kdir.x * kick
			player.physics._speedY -= kdir.y * kick
		_lmb_was_down = lmb
	_layout_hud()


func _collide_pair(a: Dictionary, b: Dictionary) -> void:
	## Equal-mass elastic swap with a little extra pop — slam into a still
	## opponent and THEY go flying (and you stop), with a bonk. A raised
	## shield REDIRECTS the ram: the rammer bounces off, the holder doesn't
	## budge.
	var ap: EEPhysics = a.phys
	var bp: EEPhysics = b.phys
	var ac: Vector2 = Vector2(ap.x + 8.0, ap.y + 8.0)
	var bc: Vector2 = Vector2(bp.x + 8.0, bp.y + 8.0)
	var dvec: Vector2 = bc - ac
	var d: float = dvec.length()
	if d >= 16.0 or d <= 0.01:
		return
	var n: Vector2 = dvec / d
	var overlap: float = 16.0 - d
	var a_sh: bool = weapons.is_shielded(a.id)
	var b_sh: bool = weapons.is_shielded(b.id)
	# Separate — but NEVER push a ball inside solid tiles (that was the
	# stuck-in-a-block bug); a blocked side just keeps its position. A shield
	# holder is an ANCHOR: the rammer takes ALL of the push-out, the holder
	# is never displaced by the hit (displacing them read as "swapping places").
	var a_w: float = 0.5
	var b_w: float = 0.5
	if a_sh and not b_sh:
		a_w = 0.0
		b_w = 1.0
	elif b_sh and not a_sh:
		a_w = 1.0
		b_w = 0.0
	var a_sep: Vector2 = -n * overlap * a_w
	var b_sep: Vector2 = n * overlap * b_w
	if not ap._collides_px(ap.x + a_sep.x, ap.y + a_sep.y):
		ap.x += a_sep.x
		ap.y += a_sep.y
	if not bp._collides_px(bp.x + b_sep.x, bp.y + b_sep.y):
		bp.x += b_sep.x
		bp.y += b_sep.y
	var av: Vector2 = Vector2(ap._speedX, ap._speedY)
	var bv: Vector2 = Vector2(bp._speedX, bp._speedY)
	var a_n: float = av.dot(n)
	var b_n: float = bv.dot(n)
	var approach: float = a_n - b_n
	if approach <= 0.0:
		return
	if b_sh and not a_sh:
		# FULL-FORCE REDIRECT: the shield catches ALL of the rammer's momentum
		# (tangential included — flipping only the normal part let glancing
		# hits slide past like a place-swap) and hurls it straight back off
		# the shield face. Slow bumps still get a minimum rejection pop; the
		# holder's velocity is completely untouched.
		av = -n * maxf(av.length() * 1.2, 4.5)
	elif a_sh and not b_sh:
		bv = n * maxf(bv.length() * 1.2, 4.5)
	elif a_sh and b_sh:
		av = -n * maxf(av.length() * 1.1, 3.0)
		bv = n * maxf(bv.length() * 1.1, 3.0)
	else:
		# Equal-mass elastic swap along the contact normal
		var a_new: float = b_n * 1.05
		var b_new: float = a_n * 1.05
		av += n * (a_new - a_n)
		bv += n * (b_new - b_n)
	ap._speedX = av.x
	ap._speedY = av.y
	bp._speedX = bv.x
	bp._speedY = bv.y
	if approach > 1.2 or a_sh or b_sh:
		var mid: Vector2 = (ac + bc) * 0.5
		var shield_bounce: bool = a_sh or b_sh
		weapons.play_sfx("bonk", mid, 0.08, clampf((1.8 if shield_bounce else 1.5) - approach * 0.07, 0.7, 1.8))
		weapons.spawn_hit(mid, Color(0.6, 0.95, 1.0) if shield_bounce else Color(0.9, 0.95, 1.0), n)
		GameState.cam_shake += clampf(approach * 0.35, 0.5, 4.0)
		if approach > 4.5 or shield_bounce:
			weapons.spawn_ring(mid, Color(0.7, 0.95, 1.0), 3.0, 18.0, 0.16)


func _layout_hud() -> void:
	var vps: Vector2 = get_viewport().get_visible_rect().size
	var top: PanelContainer = _hud.get_node_or_null("ScorePanel") as PanelContainer
	if top:
		var bot_bits: PackedStringArray = PackedStringArray()
		for i in range(bots.size()):
			bot_bits.append(("%d" % bots_lives[i]) if bots_lives[i] > 0 else "✖")
		if bots.size() == 1:
			_score_label.text = "YOU  %d ♥ %s  BOT" % [player_lives, bot_bits[0]]
		else:
			_score_label.text = "YOU  %d ♥ %s  BOTS" % [player_lives, " · ".join(bot_bits)]
		var wname: String = weapons.get_weapon("player")
		var wtext: String
		if wname != "":
			wtext = WeaponSystem.WEAPONS[wname].label
			if weapons._actors["player"].weapon_left > 0.0:
				wtext += " %.1fs" % weapons._actors["player"].weapon_left
			wtext += "  [1: fists]"
			_weapon_label.add_theme_color_override("font_color", weapons.get_weapon_color("player"))
		else:
			wtext = "FISTS — LMB dash punch, RMB parry shield" if not GameState.battle_guns_enabled else "UNARMED — LMB dash punch, RMB parry shield"
			var stowed: String = weapons._actors["player"].get("stowed_weapon", "")
			if stowed != "":
				wtext = "FISTS — dash & parry  [2: %s]" % WeaponSystem.WEAPONS[stowed].label
			_weapon_label.add_theme_color_override("font_color", Color(0.7, 0.7, 0.8))
		if weapons.super_pos != Vector2.ZERO:
			_weapon_label.text = "%s  |  HP %d/%d  |  %s" % [wtext, player_hp, MAX_HP, weapons.get_super_status()]
		else:
			_weapon_label.text = "%s  |  HP %d/%d" % [wtext, player_hp, MAX_HP]
		top.position = Vector2(vps.x / 2.0 - top.size.x / 2.0, 8)
	if _fight_label.visible:
		_fight_label.position = Vector2(vps.x / 2.0 - _fight_label.size.x / 2.0, vps.y * 0.32)
	if _result_panel.visible:
		_result_panel.position = Vector2(vps.x / 2.0 - _result_panel.size.x / 2.0, vps.y * 0.34)
