class_name BattleMode
extends Node
## 1v1 Bot: offline arena duel. 10 lives each, 3 HP per life, weapons from
## pads, black hole + spikes count as deaths. First to strip all enemy lives
## wins. Created by game_scene when GameState.battle_mode is set.

const MAX_LIVES: int = 10
const MAX_HP: int = 3
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
	BattleMap.add_weapon_pads(weapons)
	bot.weapon_system = weapons
	bot.get_player_center = func() -> Vector2: return Vector2(player.physics.x + 8.0, player.physics.y + 8.0)
	bot.get_player_vel = func() -> Vector2: return Vector2(player.physics._speedX, player.physics._speedY) * EEPhysics.EE_TICK_FRAC * EEPhysics.TPS
	bot.is_player_alive = func() -> bool: return is_instance_valid(player) and not player._is_dead
	bot.spawn_at(WorldManager.get_spawn_point(1))
	weapons.register_actor("player", 0,
		func() -> Vector2: return Vector2(player.physics.x + 8.0, player.physics.y + 8.0),
		func() -> Vector2: return Vector2(player.physics._speedX, player.physics._speedY) * EEPhysics.EE_TICK_FRAC * EEPhysics.TPS,
		func() -> bool: return is_instance_valid(player) and not player._is_dead and _player_invuln <= 0.0,
		_hurt_player)
	weapons.register_actor("bot", 1,
		bot.get_center, bot.get_vel_pxs,
		func() -> bool: return not bot.dead and _bot_invuln <= 0.0,
		_hurt_bot)
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
		weapons.spawn_explosion(Vector2(player.physics.x + 8, player.physics.y + 8), Color(0.4, 0.8, 1.0))
		player._die()  # died signal handles the life


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
		if Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT) and not GameState.is_edit_mode:
			if weapons.try_shoot("player"):
				var kick: float = weapons.get_kick("player")
				var kdir: Vector2 = aim.normalized()
				player.physics._speedX -= kdir.x * kick
				player.physics._speedY -= kdir.y * kick
	_layout_hud()


func _layout_hud() -> void:
	var vps: Vector2 = get_viewport().get_visible_rect().size
	var top: PanelContainer = _hud.get_node_or_null("ScorePanel") as PanelContainer
	if top:
		var hearts_you: String = "%d" % player_lives
		var hearts_bot: String = "%d" % bot_lives
		_score_label.text = "YOU  %s ♥ %s  BOT" % [hearts_you, hearts_bot]
		var wname: String = weapons.get_weapon("player")
		if wname != "":
			_weapon_label.text = WeaponSystem.WEAPONS[wname].label + "  |  HP %d/%d" % [player_hp, MAX_HP]
			_weapon_label.add_theme_color_override("font_color", weapons.get_weapon_color("player"))
		else:
			_weapon_label.text = "UNARMED — grab a weapon pad!  |  HP %d/%d" % [player_hp, MAX_HP]
			_weapon_label.add_theme_color_override("font_color", Color(0.7, 0.7, 0.8))
		top.position = Vector2(vps.x / 2.0 - top.size.x / 2.0, 8)
	if _fight_label.visible:
		_fight_label.position = Vector2(vps.x / 2.0 - _fight_label.size.x / 2.0, vps.y * 0.32)
	if _result_panel.visible:
		_result_panel.position = Vector2(vps.x / 2.0 - _result_panel.size.x / 2.0, vps.y * 0.34)
