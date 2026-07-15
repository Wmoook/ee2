extends Node
## Dev smoke test: boots BOSS FIGHT (fists), forces an early beam, then arms
## the player with a DOOM RAY so the second beam triggers the clash. Verifies
## the boss cycles attacks and the beam struggle engages, and saves
## user://boss_clash.png (mid-clash) + user://boss_check.png (end of run).

func _ready() -> void:
	GameState.battle_mode = true
	GameState.boss_fight = true
	GameState.battle_guns_enabled = false
	BossMap.build()
	var game: Node = (load("res://scenes/world/game.tscn") as PackedScene).instantiate()
	add_child(game)
	await get_tree().create_timer(0.8).timeout
	var bm: Node = game.get_node_or_null("BossMode")
	if bm == null:
		print("BOSS SMOKE FAIL - no BossMode node")
		get_tree().quit(1)
		return
	bm.boss._beam_cd = 2.0
	var seen: Dictionary = {}
	var saw_struggle: bool = false
	var clash_shot: bool = false
	var doom_given: bool = false
	var pl: Node = game._get_player(1)
	for i in range(110):
		await get_tree().create_timer(0.2).timeout
		seen[bm.boss.state_name()] = true
		if i == 10 and pl and not pl._is_dead:
			# Step out of the gallery's beam cover — open floor, clear LOS
			pl.physics.x = 488.0
			pl.physics.y = 496.0
		if i >= 40 and not doom_given and pl and not pl._is_dead:
			# Deterministic clash setup: doom in hand, boss pinned overhead
			# with clear LOS, beam forced to fire now
			doom_given = true
			bm.weapons.give_weapon("player", "doom")
			bm.weapons.select_slot("player", 2)  # Draw it (no auto-equip)
			pl.physics.x = 488.0
			pl.physics.y = 496.0
			bm.boss.pos = Vector2(496.0, 230.0)
			bm.boss._jink_target = Vector2(496.0, 230.0)
			bm.boss.vel = Vector2.ZERO
			bm.boss.state = bm.boss.ST_TG_BEAM
			bm.boss.st_t = 0.6
		if i == 70:
			# Force the endgame: drive the Warden into PHASE 5 (OMEGA)
			bm.boss.hp = mini(bm.boss.hp, bm.boss.max_hp / 5 + 2)
			while bm.boss.phase < 5 and bm.boss.alive():
				bm.boss._apply_damage(1, Vector2.ZERO)
		if bm._struggle:
			saw_struggle = true
			if not clash_shot:
				clash_shot = true
				var img: Image = get_viewport().get_texture().get_image()
				img.save_png("user://boss_clash.png")
				print("CLASH SHOT SAVED at t=%.1f" % (i * 0.2))
		if i % 5 == 0:
			print("t=%4.1f state=%-10s hp=%d/%d lives=%d struggle=%s" % [
				i * 0.2, bm.boss.state_name(), bm.boss.hp, bm.boss.max_hp, bm.player_lives, bm._struggle])
	# The result panel must actually appear (it used to crash on mangled
	# node paths, leaving the game input-dead with no DEFEATED screen)
	bm._end(false)
	await get_tree().process_frame
	print("END PANEL %s (visible=%s text=%s)" % [
		"PASS" if (bm._result_panel.visible and bm._result_label.text != "") else "FAIL",
		bm._result_panel.visible, bm._result_label.text])
	# Inventory (1 fists / 2 blaster / 3 scatter), doom never auto-cancels
	# fists, shields work armed. Checked on a CONTROLLED dummy actor — the
	# real player may be mid-respawn when the run ends (flaky).
	var d_hp: Array = [5]
	bm.weapons.register_actor("dummy", 7,
		func() -> Vector2: return Vector2(200.0, 200.0),
		func() -> Vector2: return Vector2.ZERO,
		func() -> bool: return true,
		func(dmg: int, _dir: Vector2) -> void: d_hp[0] -= dmg,
		Callable(), 5,
		func() -> bool: return true,
		func(_v: Vector2) -> void: pass)
	bm.weapons._actors["dummy"]["loadout"] = true
	bm.weapons._actors["dummy"]["auto_equip"] = false
	bm.weapons.select_slot("dummy", 2)
	var slot2_ok: bool = bm.weapons.get_weapon("dummy") == "blaster"
	bm.weapons.select_slot("dummy", 3)
	var slot3_ok: bool = bm.weapons.get_weapon("dummy") == "scatter"
	bm.weapons.select_slot("dummy", 1)
	var slot1_ok: bool = bm.weapons.get_weapon("dummy") == ""
	bm.weapons.give_weapon("dummy", "doom")
	var no_cancel: bool = bm.weapons.get_weapon("dummy") == ""  # STAYED on fists
	bm.weapons.select_slot("dummy", 2)
	var doom_ok: bool = bm.weapons.get_weapon("dummy") == "doom"
	bm.weapons.set_shield("dummy", true)
	await get_tree().process_frame
	await get_tree().process_frame
	var armed_shield: bool = bm.weapons.is_shielded("dummy")
	bm.weapons._actors["dummy"]["cooldown"] = 0.0
	bm.weapons.try_shoot("dummy")
	var shoot_shield: bool = bm.weapons._actors["dummy"].shield_on  # Shooting keeps the shield up now
	print("SLOTS %s | DOOM_NO_CANCEL %s | ARMED_SHIELD %s | SHOOT_WHILE_SHIELD %s" % [
		"PASS" if (slot1_ok and slot2_ok and slot3_ok and doom_ok) else "FAIL",
		"PASS" if no_cancel else "FAIL",
		"PASS" if armed_shield else "FAIL",
		"PASS" if shoot_shield else "FAIL"])
	# Terrain destruction: altar block breaks, shell is immune
	var was_solid: bool = WorldManager.is_solid_at(36, 30)
	var broke: bool = bm.weapons.damage_block(36, 30, 99.0)
	var now_air: bool = WorldManager.get_tile(36, 30) == 0
	var shell_immune: bool = not bm.weapons.damage_block(0, 10, 99.0) and WorldManager.is_solid_at(0, 10)
	print("BLOCK BREAK %s (was_solid=%s broke=%s now_air=%s shell_immune=%s)" % [
		"PASS" if (was_solid and broke and now_air and shell_immune) else "FAIL",
		was_solid, broke, now_air, shell_immune])
	var img2: Image = get_viewport().get_texture().get_image()
	img2.save_png("user://boss_check.png")
	print("STATES SEEN: %s" % [seen.keys()])
	var super_states: Array = ["TG_SING", "TG_RIFT", "RIFT_GONE", "RIFT_ERUPT", "CAGE", "TG_CAGE", "TG_SKY", "SKYFALL"]
	var saw_super: bool = false
	for ss in super_states:
		if seen.has(ss):
			saw_super = true
			break
	var ok: bool = seen.has("BEAM") and seen.has("HOVER") and saw_struggle and saw_super
	print("BOSS SMOKE %s (struggle=%s super_phases=%s phase=%d)" % ["PASS" if ok else "FAIL", saw_struggle, saw_super, bm.boss.phase])
	GameState.battle_mode = false
	GameState.boss_fight = false
	get_tree().quit(0)
