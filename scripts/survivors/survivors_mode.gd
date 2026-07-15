class_name SurvivorsMode
extends Node
## DOT SURVIVORS: Vampire Survivors with pure EE physics. The whole cave
## is dots — you FLY with EE inertia while the corrupted smiley horde
## floods in for 15 minutes. Auto-firing arsenal, EE coins as XP, chest
## treasure from minibosses, level-up cards, your dash & parry as the
## active kit. Minute 14 births THE WARDEN PRIME. Survive to 15:00.

const DURATION: float = 900.0

var player: Node = null
var horde: Horde = null
var arsenal: Arsenal = null

var elapsed: float = 0.0
var level: int = 1
var xp: int = 0
var xp_need: int = 6
var kills: int = 0
var max_hp: int = 6
var hp: int = 6
var _invuln: float = 0.0
var _over: bool = false
var _won: bool = false
var _choice_open: bool = false
var _pending_ups: int = 0

# Passives
var magnet_lv: int = 0
var overdrive_lv: int = 0
var plating_lv: int = 0
var thruster_lv: int = 0
var _regen_t: float = 9.0

# Active kit
var _dash_cd: float = 0.0
var _shield_energy: float = 2.4
var _shield_broken: bool = false
var _shield_on: bool = false
var _lmb_was: bool = false

# Director
var _spawn_accum: float = 0.0
var _boss_marks: Array = [180.0, 360.0, 540.0, 720.0]
var _prime_done: bool = false
var _intro_chest_done: bool = false

var _hud: CanvasLayer
var _timer_label: Label
var _level_label: Label
var _kills_label: Label
var _hearts_label: Label
var _warn_label: Label
var _warn_t: float = 0.0
var _xp_bar: Control
var _choice_layer: CanvasLayer
var _choice_box: HBoxContainer
var _choice_title: Label
var _result_panel: PanelContainer
var _result_label: Label
var _result_sub: Label

const PASSIVES: Dictionary = {
	"magnet": {"name": "COIN MAGNET", "icon": "◈", "desc": "Coins fly to you from farther away"},
	"overdrive": {"name": "OVERDRIVE CORE", "icon": "⚡", "desc": "All weapons fire faster"},
	"plating": {"name": "NANO PLATING", "icon": "✚", "desc": "+1 max HP, heal, slow regen"},
	"thruster": {"name": "ZEPHYR THRUSTERS", "icon": "✦", "desc": "Fly faster through the dots"},
}


func _ready() -> void:
	player = get_parent()._get_player(1)
	horde = Horde.new()
	arsenal = Arsenal.new()
	get_parent().add_child.call_deferred(horde)
	get_parent().add_child.call_deferred(arsenal)
	horde.mode = self
	arsenal.mode = self
	arsenal.horde = horde
	_build_hud()
	if is_instance_valid(player):
		player.physics.force_dot = true


func frozen() -> bool:
	return _over or _choice_open


func player_center() -> Vector2:
	if is_instance_valid(player):
		return Vector2(player.physics.x + 8.0, player.physics.y + 8.0)
	return Vector2(800.0, 448.0)


func cd_mult() -> float:
	return 1.0 - 0.08 * float(overdrive_lv)


func minute() -> float:
	return elapsed / 60.0


func on_coin(v: int) -> void:
	xp += v
	while xp >= xp_need:
		xp -= xp_need
		level += 1
		xp_need = int(5.0 + float(level) * 2.8)
		_pending_ups += 1
		horde.sfx("doom_spawn", player_center(), 1.8)
	if _pending_ups > 0 and not _choice_open and not _over:
		_open_choice()


func on_enemy_died(_type: String, _pos: Vector2) -> void:
	kills += 1


func on_contact(i: int) -> void:
	if _over:
		return
	var e: Dictionary = horde.enemies[i]
	if _shield_on:
		# PARRY: the horde bounces off your shield
		e.vel = (e.pos - player_center()).normalized() * 340.0
		_shield_energy = maxf(0.0, _shield_energy - 0.12)
		horde.sfx("bonk", e.pos, 1.4)
		return
	if _invuln > 0.0:
		return
	_hurt(1, (player_center() - e.pos).normalized())
	e.vel = (e.pos - player_center()).normalized() * 220.0


func on_shrapnel(pr: Dictionary) -> bool:
	## Returns true if the shard should die
	if _over:
		return true
	if _shield_on:
		pr.vel = -pr.vel * 1.25
		pr.friendly = true
		_shield_energy = maxf(0.0, _shield_energy - 0.1)
		horde.sfx("hit", pr.pos, 1.5)
		return false
	if _invuln > 0.0:
		return false
	_hurt(1, pr.vel.normalized())
	return true


func on_chest(pos: Vector2) -> void:
	## TREASURE! Auto-roll 1-3 upgrades with a reveal panel
	horde.sfx("pickup", pos, 0.7)
	var n: int = 1
	var roll: float = randf()
	if roll > 0.95:
		n = 3
	elif roll > 0.72:
		n = 2
	var granted: Array = []
	for _i in range(n):
		var pool: Array = _upgrade_pool()
		if pool.is_empty():
			hp = mini(max_hp, hp + 1)
			granted.append("❤ RECOVERY")
			continue
		var pick: Dictionary = pool[randi() % pool.size()]
		_apply_upgrade(pick.id)
		granted.append("%s %s" % [pick.icon, pick.name])
	_show_treasure(granted)


func _hurt(dmg: int, dir: Vector2) -> void:
	hp -= dmg
	_invuln = 0.85
	GameState.cam_shake += 5.0
	player.physics._speedX += dir.x * 4.0
	player.physics._speedY += dir.y * 4.0
	horde.sfx("hit", player_center(), 0.8)
	if hp <= 0:
		_end(false)


func _end(won: bool) -> void:
	_over = true
	_won = won
	if won:
		_result_label.text = "YOU  SURVIVED"
		_result_label.add_theme_color_override("font_color", Color(0.3, 1.0, 0.4))
		_result_sub.text = "15:00 in the Dot Depths. LV %d — %d corrupted smileys scrapped." % [level, kills]
		for e in horde.enemies:
			horde.drop_coins(e.pos, 1)
		horde.enemies.clear()
	else:
		_result_label.text = "CONSUMED"
		_result_label.add_theme_color_override("font_color", Color(1.0, 0.35, 0.3))
		_result_sub.text = "Survived %s — LV %d, %d kills. The dots remember." % [_fmt_time(elapsed), level, kills]
		if is_instance_valid(player):
			player._die()
	_result_panel.visible = true


func _process(delta: float) -> void:
	if _invuln > 0.0:
		_invuln -= delta
	if _over or _choice_open:
		_layout_hud()
		return
	elapsed += delta
	if elapsed >= DURATION:
		_end(true)
		return
	# ── Active kit: LMB dash, RMB parry shield ──
	if is_instance_valid(player) and not player._is_dead:
		_dash_cd = maxf(0.0, _dash_cd - delta)
		var lmb: bool = Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT) and not GameState.is_edit_mode
		if lmb and not _lmb_was and _dash_cd <= 0.0:
			_dash_cd = 1.0
			var aim: Vector2 = (horde.get_global_mouse_position() - player_center()).normalized()
			player.physics._speedX += aim.x * 8.0
			player.physics._speedY += aim.y * 8.0
			horde.sfx("shoot_rail", player_center(), 1.6)
		_lmb_was = lmb
		var want_shield: bool = Input.is_mouse_button_pressed(MOUSE_BUTTON_RIGHT) and not _shield_broken
		if want_shield and _shield_energy > 0.0:
			_shield_on = true
			_shield_energy = maxf(0.0, _shield_energy - delta)
			if _shield_energy <= 0.0:
				_shield_broken = true
				_shield_on = false
				horde.sfx("hit", player_center(), 0.6)
		else:
			_shield_on = false
			_shield_energy = minf(2.4, _shield_energy + delta * (1.8 if overdrive_lv > 0 else 0.8))
			if _shield_broken and _shield_energy >= 2.4:
				_shield_broken = false
		arsenal.shield_visual = _shield_energy / 2.4 if _shield_on else -1.0
		# Zephyr thrusters: extra acceleration through the dots
		if thruster_lv > 0:
			var ix: float = Input.get_axis("ui_left", "ui_right")
			var iy: float = Input.get_axis("ui_up", "ui_down")
			player.physics._speedX += ix * 0.05 * float(thruster_lv)
			player.physics._speedY += iy * 0.05 * float(thruster_lv)
		player.physics.force_dot = true
	# NANO PLATING regen
	if plating_lv > 0 and hp < max_hp:
		_regen_t -= delta
		if _regen_t <= 0.0:
			_regen_t = maxf(4.0, 10.0 - 1.5 * float(plating_lv))
			hp += 1
	# ── Director ──
	var m: float = minute()
	horde.magnet_r = 70.0 + 48.0 * float(magnet_lv)
	var rate: float = 0.9 + m * 0.55 + pow(m, 1.5) * 0.13
	_spawn_accum += delta * rate
	var burst: int = 0
	while _spawn_accum >= 1.0 and burst < 8:
		_spawn_accum -= 1.0
		burst += 1
		_spawn_one(m)
	for bi in range(_boss_marks.size() - 1, -1, -1):
		if elapsed >= _boss_marks[bi]:
			_boss_marks.remove_at(bi)
			horde.spawn("jr", _spawn_pos(), 1.0 + m * 0.45, 1.0)
			for _e in range(6):
				_spawn_one(m)
			_warn("A  WARDEN  JR.  MANIFESTS")
	if not _prime_done and elapsed >= 840.0:
		_prime_done = true
		horde.spawn("prime", _spawn_pos(), 1.0, 1.0)
		_warn("☠  THE  WARDEN  PRIME  RISES  ☠")
		GameState.cam_shake += 10.0
	if not _intro_chest_done and elapsed >= 40.0:
		_intro_chest_done = true
		var cp: Vector2 = player_center() + Vector2(220.0, -60.0)
		horde.drop_chest(Vector2(clampf(cp.x, SurvivorsMap.MIN_X + 40.0, SurvivorsMap.MAX_X - 40.0), clampf(cp.y, SurvivorsMap.MIN_Y + 40.0, SurvivorsMap.MAX_Y - 40.0)))
	_layout_hud()


func _spawn_one(m: float) -> void:
	var pool: Array = [["gloom", 10.0]]
	if m >= 1.0:
		pool.append(["fang", 6.0 + m])
	if m >= 2.5:
		pool.append(["wisp", 4.0])
	if m >= 4.0:
		pool.append(["bulwark", 3.0 + m * 0.35])
	if m >= 6.0:
		pool.append(["spiker", 4.5])
	var total: float = 0.0
	for p in pool:
		total += p[1]
	var roll: float = randf() * total
	var pick: String = "gloom"
	for p in pool:
		roll -= p[1]
		if roll <= 0.0:
			pick = p[0]
			break
	var hp_scale: float = 1.0 + m * 0.42 + pow(maxf(m - 8.0, 0.0), 1.3) * 0.18
	var spd_scale: float = minf(1.0 + m * 0.028, 1.45)
	horde.spawn(pick, _spawn_pos(), hp_scale, spd_scale)


func _spawn_pos() -> Vector2:
	var pc: Vector2 = player_center()
	for _try in range(10):
		var a: float = randf() * TAU
		var p: Vector2 = pc + Vector2.from_angle(a) * randf_range(460.0, 640.0)
		p.x = clampf(p.x, SurvivorsMap.MIN_X + 20.0, SurvivorsMap.MAX_X - 20.0)
		p.y = clampf(p.y, SurvivorsMap.MIN_Y + 20.0, SurvivorsMap.MAX_Y - 20.0)
		if p.distance_to(pc) > 320.0:
			return p
	return Vector2(randf_range(SurvivorsMap.MIN_X + 40.0, SurvivorsMap.MAX_X - 40.0), SurvivorsMap.MIN_Y + 40.0)


func _warn(text: String) -> void:
	_warn_label.text = text
	_warn_t = 3.2
	horde.sfx("doom_spawn", player_center(), 0.7)


# ── Upgrades ──

func _upgrade_pool() -> Array:
	var out: Array = []
	for id in arsenal.upgradeable():
		var inf: Dictionary = Arsenal.INFO[id]
		out.append({"id": id, "name": inf.name, "icon": inf.icon, "desc": inf.desc, "lv": arsenal.levels[id]})
	for pid in PASSIVES:
		var lv: int = _passive_lv(pid)
		if lv < 5:
			var pinf: Dictionary = PASSIVES[pid]
			out.append({"id": pid, "name": pinf.name, "icon": pinf.icon, "desc": pinf.desc, "lv": lv})
	return out


func _passive_lv(id: String) -> int:
	match id:
		"magnet": return magnet_lv
		"overdrive": return overdrive_lv
		"plating": return plating_lv
		"thruster": return thruster_lv
	return 0


func _apply_upgrade(id: String) -> void:
	if Arsenal.INFO.has(id):
		arsenal.apply_upgrade(id)
		return
	match id:
		"magnet": magnet_lv = mini(5, magnet_lv + 1)
		"overdrive": overdrive_lv = mini(5, overdrive_lv + 1)
		"plating":
			plating_lv = mini(5, plating_lv + 1)
			max_hp += 1
			hp = mini(max_hp, hp + 2)
		"thruster": thruster_lv = mini(5, thruster_lv + 1)


func _open_choice() -> void:
	_pending_ups -= 1
	_choice_open = true
	get_tree().paused = true
	_choice_title.text = "⭐  LEVEL  %d  —  CHOOSE  ⭐" % level
	for c in _choice_box.get_children():
		c.queue_free()
	var pool: Array = _upgrade_pool()
	pool.shuffle()
	var count: int = mini(3, pool.size())
	if count == 0:
		_close_choice()
		hp = mini(max_hp, hp + 1)
		return
	for i in range(count):
		var up: Dictionary = pool[i]
		var card: PanelContainer = PanelContainer.new()
		card.add_theme_stylebox_override("panel", EditorToolsDock.make_panel_style())
		card.custom_minimum_size = Vector2(190, 150)
		var cv: VBoxContainer = VBoxContainer.new()
		cv.add_theme_constant_override("separation", 8)
		card.add_child(cv)
		var ic: Label = Label.new()
		ic.text = up.icon
		ic.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		ic.add_theme_font_size_override("font_size", 34)
		ic.add_theme_color_override("font_color", Color(1.0, 0.85, 0.3))
		cv.add_child(ic)
		var nm: Label = Label.new()
		nm.text = up.name
		nm.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		nm.add_theme_font_size_override("font_size", 14)
		cv.add_child(nm)
		var ds: Label = Label.new()
		ds.text = up.desc
		ds.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		ds.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		ds.custom_minimum_size = Vector2(170, 0)
		ds.add_theme_font_size_override("font_size", 10)
		ds.add_theme_color_override("font_color", Color(0.7, 0.72, 0.85))
		cv.add_child(ds)
		var btn: Button = EditorToolsDock.make_button("LV %d  →  %d" % [up.lv, up.lv + 1], Color(0.8, 0.55, 0.15))
		btn.custom_minimum_size = Vector2(0, 34)
		var uid: String = up.id
		btn.pressed.connect(func() -> void:
			_apply_upgrade(uid)
			_close_choice())
		cv.add_child(btn)
		_choice_box.add_child(card)
	_choice_layer.visible = true


func _close_choice() -> void:
	_choice_layer.visible = false
	_choice_open = false
	get_tree().paused = false
	if _pending_ups > 0:
		_open_choice()


func _show_treasure(granted: Array) -> void:
	_choice_open = true
	get_tree().paused = true
	_choice_title.text = "🏆  TREASURE  🏆"
	for c in _choice_box.get_children():
		c.queue_free()
	var card: PanelContainer = PanelContainer.new()
	card.add_theme_stylebox_override("panel", EditorToolsDock.make_panel_style())
	card.custom_minimum_size = Vector2(300, 130)
	var cv: VBoxContainer = VBoxContainer.new()
	cv.add_theme_constant_override("separation", 8)
	card.add_child(cv)
	for g in granted:
		var gl: Label = Label.new()
		gl.text = g
		gl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		gl.add_theme_font_size_override("font_size", 16)
		gl.add_theme_color_override("font_color", Color(1.0, 0.85, 0.3))
		cv.add_child(gl)
	var btn: Button = EditorToolsDock.make_button("CLAIM", Color(0.8, 0.55, 0.15))
	btn.custom_minimum_size = Vector2(0, 34)
	btn.pressed.connect(_close_choice)
	cv.add_child(btn)
	_choice_box.add_child(card)
	_choice_layer.visible = true


# ── HUD ──

func _build_hud() -> void:
	_hud = CanvasLayer.new()
	_hud.layer = 30
	add_child(_hud)
	_xp_bar = Control.new()
	_xp_bar.custom_minimum_size = Vector2(0, 8)
	_xp_bar.draw.connect(_draw_xp)
	_hud.add_child(_xp_bar)
	_timer_label = _mk_label(34, Color(0.95, 0.95, 1.0))
	_level_label = _mk_label(16, Color(1.0, 0.85, 0.3))
	_kills_label = _mk_label(16, Color(1.0, 0.5, 0.4))
	_hearts_label = _mk_label(16, Color(1.0, 0.35, 0.4))
	_warn_label = _mk_label(30, Color(1.0, 0.4, 0.35))

	_choice_layer = CanvasLayer.new()
	_choice_layer.layer = 40
	_choice_layer.visible = false
	_choice_layer.process_mode = Node.PROCESS_MODE_ALWAYS
	add_child(_choice_layer)
	var dim: ColorRect = ColorRect.new()
	dim.color = Color(0.0, 0.0, 0.05, 0.6)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	_choice_layer.add_child(dim)
	var center: VBoxContainer = VBoxContainer.new()
	center.set_anchors_preset(Control.PRESET_CENTER)
	center.add_theme_constant_override("separation", 14)
	center.grow_horizontal = Control.GROW_DIRECTION_BOTH
	center.grow_vertical = Control.GROW_DIRECTION_BOTH
	_choice_layer.add_child(center)
	_choice_title = Label.new()
	_choice_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_choice_title.add_theme_font_size_override("font_size", 26)
	_choice_title.add_theme_color_override("font_color", Color(1.0, 0.85, 0.3))
	center.add_child(_choice_title)
	_choice_box = HBoxContainer.new()
	_choice_box.add_theme_constant_override("separation", 14)
	_choice_box.alignment = BoxContainer.ALIGNMENT_CENTER
	center.add_child(_choice_box)

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


func _mk_label(size: int, col: Color) -> Label:
	var l: Label = Label.new()
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", col)
	l.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.9))
	l.add_theme_constant_override("shadow_offset_x", 2)
	l.add_theme_constant_override("shadow_offset_y", 2)
	_hud.add_child(l)
	return l


func _draw_xp() -> void:
	var w: float = _xp_bar.size.x
	_xp_bar.draw_rect(Rect2(0, 0, w, 8), Color(0.04, 0.04, 0.09, 0.9))
	var frac: float = clampf(float(xp) / float(xp_need), 0.0, 1.0)
	_xp_bar.draw_rect(Rect2(0, 0, w * frac, 8), Color(0.35, 0.85, 1.0))
	_xp_bar.draw_rect(Rect2(maxf(w * frac - 8.0, 0.0), 0, 8.0, 8), Color(0.9, 1.0, 1.0, 0.9))


func _fmt_time(t: float) -> String:
	return "%02d:%02d" % [int(t) / 60, int(t) % 60]


func _layout_hud() -> void:
	var vps: Vector2 = get_viewport().get_visible_rect().size
	_xp_bar.position = Vector2.ZERO
	_xp_bar.size = Vector2(vps.x, 8)
	_xp_bar.queue_redraw()
	_timer_label.text = _fmt_time(maxf(DURATION - elapsed, 0.0))
	_timer_label.position = Vector2(vps.x / 2.0 - _timer_label.size.x / 2.0, 14)
	_level_label.text = "LV %d" % level
	_level_label.position = Vector2(vps.x / 2.0 - 130.0, 26)
	_kills_label.text = "☠ %d" % kills
	_kills_label.position = Vector2(vps.x / 2.0 + 96.0, 26)
	var hearts: String = ""
	for i in range(max_hp):
		hearts += "♥" if i < hp else "♡"
	_hearts_label.text = hearts
	if _invuln > 0.3:
		_hearts_label.add_theme_color_override("font_color", Color(1.0, 1.0, 0.5))
	else:
		_hearts_label.add_theme_color_override("font_color", Color(1.0, 0.35, 0.4))
	_hearts_label.position = Vector2(vps.x / 2.0 - _hearts_label.size.x / 2.0, 56)
	if _warn_t > 0.0:
		_warn_t -= get_process_delta_time()
		_warn_label.visible = true
		_warn_label.modulate.a = clampf(_warn_t / 1.0, 0.0, 1.0)
		_warn_label.position = Vector2(vps.x / 2.0 - _warn_label.size.x / 2.0, vps.y * 0.3)
	else:
		_warn_label.visible = false
	if _result_panel.visible:
		_result_panel.position = Vector2(vps.x / 2.0 - _result_panel.size.x / 2.0, vps.y * 0.34)


func _return_to_menu() -> void:
	get_tree().paused = false
	GameState.battle_mode = false
	GameState.survivors_mode = false
	GameState.cam_shake = 0.0
	NetworkManager.disconnect_game()
	get_tree().change_scene_to_file("res://scenes/ui/main_menu.tscn")
