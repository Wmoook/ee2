class_name BattleMode
extends Node
## 1v1 Bot: offline arena duel. 10 lives each, 3 HP per life, weapons from
## pads, black hole + spikes count as deaths. First to strip all enemy lives
## wins. Created by game_scene when GameState.battle_mode is set.

const MAX_LIVES: int = 10
const MAX_HP: int = 5
const INVULN_TIME: float = 1.2

var player: Node = null
var weapons: WeaponSystem = null
var bot: BotController = null

var player_lives: int = MAX_LIVES
var bot_lives: int = MAX_LIVES
var player_hp: int = MAX_HP
var bot_hp: int = MAX_HP
var _player_invuln: float = 0.0
var _bot_invuln: float = 0.0
var _bot_respawn_in: float = -1.0
var _over: bool = false
var _fight_timer: float = 1.6

var _lmb_was_down: bool = false
var _hud: CanvasLayer
var _score_label: Label
var _weapon_label: Label
var _fight_label: Label
var _result_panel: PanelContainer


func _ready() -> void:
	player = get_parent()._get_player(1)
	# World-space combat layer
	weapons = WeaponSystem.new()
	get_parent().add_child.call_deferred(weapons)
	# The bot
	bot = BotController.new()
	get_parent().add_child.call_deferred(bot)
	_build_hud()
	call_deferred("_wire_up")


func _wire_up() -> void:
	if GameState.battle_guns_enabled:
		BattleMap.add_weapon_pads(weapons)
	# Guns OFF: no pads and no super cycle (super_pos stays ZERO) — the duel
	# is pure dash punches and parry shields.
	bot.weapon_system = weapons
	bot.get_player_center = func() -> Vector2: return Vector2(player.physics.x + 8.0, player.physics.y + 8.0)
	bot.get_player_vel = func() -> Vector2: return Vector2(player.physics._speedX, player.physics._speedY) * EEPhysics.EE_TICK_FRAC * EEPhysics.TPS
	bot.is_player_alive = func() -> bool: return is_instance_valid(player) and not player._is_dead
	bot.spawn_at(WorldManager.get_spawn_point(1))
	weapons.register_actor("player", 0,
		func() -> Vector2: return Vector2(player.physics.x + 8.0, player.physics.y + 8.0),
		func() -> Vector2: return Vector2(player.physics._speedX, player.physics._speedY) * EEPhysics.EE_TICK_FRAC * EEPhysics.TPS,
		func() -> bool: return is_instance_valid(player) and not player._is_dead and _player_invuln <= 0.0,
		_hurt_player,
		func() -> int: return player_hp, MAX_HP,
		func() -> bool: return player.physics.is_grounded,
		func(v: Vector2) -> void:
			player.physics._speedX += v.x
			player.physics._speedY += v.y)
	weapons.register_actor("bot", 1,
		bot.get_center, bot.get_vel_pxs,
		func() -> bool: return not bot.dead and _bot_invuln <= 0.0,
		_hurt_bot,
		func() -> int: return bot_hp, MAX_HP,
		func() -> bool: return bot.physics.is_grounded,
		func(v: Vector2) -> void:
			bot.physics._speedX += v.x
			bot.physics._speedY += v.y)
	if player.has_signal("died"):
		player.died.connect(_on_player_died)


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
	var result_label: Label = Label.new()
	result_label.name = "ResultLabel"
	result_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	result_label.add_theme_font_size_override("font_size", 40)
	rv.add_child(result_label)
	var sub: Label = Label.new()
	sub.name = "ResultSub"
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	sub.add_theme_font_size_override("font_size", 13)
	sub.add_theme_color_override("font_color", Color(0.75, 0.75, 0.85))
	rv.add_child(sub)
	var menu_btn: Button = EditorToolsDock.make_button("Return to Menu", Color(0.3, 0.4, 0.6))
	menu_btn.custom_minimum_size = Vector2(200, 34)
	menu_btn.pressed.connect(_return_to_menu)
	rv.add_child(menu_btn)


func _hurt_player(dmg: int, dir: Vector2) -> void:
	if _over or _player_invuln > 0.0 or player._is_dead:
		return
	player_hp -= dmg
	_player_invuln = 0.35
	player.physics._speedX += dir.x * 2.2
	player.physics._speedY += dir.y * 2.2
	GameState.cam_shake += 4.0
	if player_hp <= 0:
		player._die()  # died signal handles the life (and the explosion)


func _hurt_bot(dmg: int, dir: Vector2) -> void:
	if _over or _bot_invuln > 0.0 or bot.dead:
		return
	bot_hp -= dmg
	_bot_invuln = 0.3
	bot.apply_knockback(dir, 2.2)
	if bot_hp <= 0:
		_kill_bot()


func _kill_bot() -> void:
	weapons.spawn_explosion(bot.get_center(), Color(1.0, 0.35, 0.25))
	weapons.strip_weapon("bot")
	bot.set_dead(true)
	bot_lives -= 1
	bot_hp = MAX_HP
	if bot_lives <= 0:
		_end(true)
	else:
		_bot_respawn_in = 1.5


func _on_player_died() -> void:
	if _over:
		return
	# Death animation for EVERY death cause — spikes included
	weapons.spawn_explosion(Vector2(player.physics.x + 8.0, player.physics.y + 8.0), Color(0.4, 0.8, 1.0))
	weapons.strip_weapon("player")
	player_lives -= 1
	player_hp = MAX_HP
	_player_invuln = INVULN_TIME + 0.7  # Covers the respawn delay
	if player_lives <= 0:
		_end(false)


func _end(player_won: bool) -> void:
	_over = true
	bot.set_dead(true)
	var rl: Label = _result_panel.get_node("VBoxContainer/ResultLabel") as Label
	var rs: Label = _result_panel.get_node("VBoxContainer/ResultSub") as Label
	if player_won:
		rl.text = "VICTORY!"
		rl.add_theme_color_override("font_color", Color(0.3, 1.0, 0.4))
		rs.text = "The bot is scrap metal. %d lives remaining." % player_lives
	else:
		rl.text = "DEFEATED"
		rl.add_theme_color_override("font_color", Color(1.0, 0.35, 0.3))
		rs.text = "The bot takes this one. Rematch?"
	_result_panel.visible = true


func _return_to_menu() -> void:
	GameState.battle_mode = false
	GameState.cam_shake = 0.0
	NetworkManager.disconnect_game()
	get_tree().change_scene_to_file("res://scenes/ui/main_menu.tscn")


func _process(delta: float) -> void:
	if _player_invuln > 0.0:
		_player_invuln -= delta
	if _bot_invuln > 0.0:
		_bot_invuln -= delta
	if _fight_timer > 0.0:
		_fight_timer -= delta
		_fight_label.modulate.a = clampf(_fight_timer / 0.8, 0.0, 1.0)
		if _fight_timer <= 0.0:
			_fight_label.visible = false
	if _over:
		_layout_hud()
		return
	# Bot environmental deaths: hazard tiles + the black hole core.
	# (The player controller already handles both for the player.)
	if not bot.dead:
		var env_dead: bool = false
		var bt0x: int = int(floor(bot.physics.x / 16.0))
		var bt0y: int = int(floor(bot.physics.y / 16.0))
		var bt1x: int = int(floor((bot.physics.x + 15.0) / 16.0))
		var bt1y: int = int(floor((bot.physics.y + 15.0) / 16.0))
		for ty in range(bt0y, bt1y + 1):
			for tx in range(bt0x, bt1x + 1):
				if GameState.is_hazard(WorldManager.get_tile(tx, ty)):
					env_dead = true
		var bc: Vector2 = bot.get_center()
		for gz in WorldManager.gravity_zones.zones:
			if bc.distance_to(gz.center) < gz.get("center_radius", 8.0) + 8.0:
				env_dead = true
		if env_dead:
			_kill_bot()
	# Ball-vs-ball collision: equal-mass elastic swap with a little extra pop —
	# slam into a still opponent and THEY go flying (and you stop), with a bonk.
	if not bot.dead and is_instance_valid(player) and not player._is_dead:
		var pc: Vector2 = Vector2(player.physics.x + 8.0, player.physics.y + 8.0)
		var bc2: Vector2 = bot.get_center()
		var dvec: Vector2 = bc2 - pc
		var d: float = dvec.length()
		if d < 16.0 and d > 0.01:
			var n: Vector2 = dvec / d
			var overlap: float = 16.0 - d
			# Separate — but NEVER push a ball inside solid tiles (that was the
			# stuck-in-a-block bug); a blocked side just keeps its position
			var p_sep: Vector2 = -n * overlap * 0.5
			var b_sep: Vector2 = n * overlap * 0.5
			if not player.physics._collides_px(player.physics.x + p_sep.x, player.physics.y + p_sep.y):
				player.physics.x += p_sep.x
				player.physics.y += p_sep.y
			if not bot.physics._collides_px(bot.physics.x + b_sep.x, bot.physics.y + b_sep.y):
				bot.physics.x += b_sep.x
				bot.physics.y += b_sep.y
			var pv: Vector2 = Vector2(player.physics._speedX, player.physics._speedY)
			var bv: Vector2 = Vector2(bot.physics._speedX, bot.physics._speedY)
			var p_n: float = pv.dot(n)
			var b_n: float = bv.dot(n)
			var approach: float = p_n - b_n
			if approach > 0.0:
				# A raised shield REDIRECTS the ram: the rammer bounces off,
				# the shield holder doesn't budge
				var p_sh: bool = weapons.is_shielded("player")
				var b_sh: bool = weapons.is_shielded("bot")
				var p_new: float
				var b_new: float
				if b_sh and not p_sh:
					p_new = -p_n * 1.15
					b_new = b_n
				elif p_sh and not b_sh:
					p_new = p_n
					b_new = -b_n * 1.15
				elif p_sh and b_sh:
					p_new = -p_n * 1.1
					b_new = -b_n * 1.1
				else:
					p_new = b_n * 1.05
					b_new = p_n * 1.05
				pv += n * (p_new - p_n)
				bv += n * (b_new - b_n)
				player.physics._speedX = pv.x
				player.physics._speedY = pv.y
				bot.physics._speedX = bv.x
				bot.physics._speedY = bv.y
				if approach > 1.2:
					var mid: Vector2 = (pc + bc2) * 0.5
					var shield_bounce: bool = p_sh or b_sh
					weapons.play_sfx("bonk", mid, 0.08, clampf((1.8 if shield_bounce else 1.5) - approach * 0.07, 0.7, 1.8))
					weapons.spawn_hit(mid, Color(0.6, 0.95, 1.0) if shield_bounce else Color(0.9, 0.95, 1.0), n)
					GameState.cam_shake += clampf(approach * 0.35, 0.5, 4.0)
					if approach > 4.5 or shield_bounce:
						weapons.spawn_ring(mid, Color(0.7, 0.95, 1.0), 3.0, 18.0, 0.16)
	# Bot respawn (far spawn from the player)
	if _bot_respawn_in > 0.0:
		_bot_respawn_in -= delta
		if _bot_respawn_in <= 0.0:
			var pc: Vector2 = Vector2(player.physics.x, player.physics.y)
			var s0: Vector2 = WorldManager.get_spawn_pixel(0)
			var s1: Vector2 = WorldManager.get_spawn_pixel(1)
			var pick: Vector2 = WorldManager.get_spawn_point(1) if pc.distance_to(s1) > pc.distance_to(s0) else WorldManager.get_spawn_point(0)
			bot.spawn_at(pick)
			_bot_invuln = INVULN_TIME
	# Player aiming + shooting (LMB), blocked while editing (editing is
	# disabled in battle mode anyway) or over UI
	if is_instance_valid(player) and not player._is_dead:
		var pc2: Vector2 = Vector2(player.physics.x + 8.0, player.physics.y + 8.0)
		var aim: Vector2 = weapons.get_global_mouse_position() - pc2
		weapons.set_aim("player", aim)
		var unarmed: bool = weapons.get_weapon("player") == ""
		# RMB: parry shield (unarmed kit)
		weapons.set_shield("player", unarmed and Input.is_mouse_button_pressed(MOUSE_BUTTON_RIGHT) and not GameState.is_edit_mode)
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


func _layout_hud() -> void:
	var vps: Vector2 = get_viewport().get_visible_rect().size
	var top: PanelContainer = _hud.get_node_or_null("ScorePanel") as PanelContainer
	if top:
		var hearts_you: String = "%d" % player_lives
		var hearts_bot: String = "%d" % bot_lives
		_score_label.text = "YOU  %s ♥ %s  BOT" % [hearts_you, hearts_bot]
		var wname: String = weapons.get_weapon("player")
		var wtext: String
		if wname != "":
			wtext = WeaponSystem.WEAPONS[wname].label
			if weapons._actors["player"].weapon_left > 0.0:
				wtext += " %.1fs" % weapons._actors["player"].weapon_left
			_weapon_label.add_theme_color_override("font_color", weapons.get_weapon_color("player"))
		else:
			wtext = "FISTS — LMB dash punch, RMB parry shield" if not GameState.battle_guns_enabled else "UNARMED — LMB dash punch, RMB parry shield"
			_weapon_label.add_theme_color_override("font_color", Color(0.7, 0.7, 0.8))
		if GameState.battle_guns_enabled:
			_weapon_label.text = "%s  |  HP %d/%d  |  %s" % [wtext, player_hp, MAX_HP, weapons.get_super_status()]
		else:
			_weapon_label.text = "%s  |  HP %d/%d" % [wtext, player_hp, MAX_HP]
		top.position = Vector2(vps.x / 2.0 - top.size.x / 2.0, 8)
	if _fight_label.visible:
		_fight_label.position = Vector2(vps.x / 2.0 - _fight_label.size.x / 2.0, vps.y * 0.32)
	if _result_panel.visible:
		_result_panel.position = Vector2(vps.x / 2.0 - _result_panel.size.x / 2.0, vps.y * 0.34)
