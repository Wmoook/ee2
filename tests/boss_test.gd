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
		if i >= 40 and not doom_given:
			doom_given = true
			bm.weapons.give_weapon("player", "doom")
			bm.weapons.select_slot("player", 2)  # Draw it (no auto-equip)
			bm.boss._beam_cd = 1.0
			if pl and not pl._is_dead:
				pl.physics.x = 488.0
				pl.physics.y = 496.0
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
	# fists, shields work armed (_over is set by _end above → no override)
	bm.weapons._actors["player"]["loadout"] = true
	bm.weapons._actors["player"]["auto_equip"] = false
	bm.weapons._actors["player"]["super_left"] = -1.0
	bm.weapons.select_slot("player", 2)
	var slot2_ok: bool = bm.weapons.get_weapon("player") == "blaster"
	bm.weapons.select_slot("player", 3)
	var slot3_ok: bool = bm.weapons.get_weapon("player") == "scatter"
	bm.weapons.select_slot("player", 1)
	var slot1_ok: bool = bm.weapons.get_weapon("player") == ""
	bm.weapons.give_weapon("player", "doom")
	var no_cancel: bool = bm.weapons.get_weapon("player") == ""  # STAYED on fists
	bm.weapons.select_slot("player", 2)
	var doom_ok: bool = bm.weapons.get_weapon("player") == "doom"
	bm.weapons.set_shield("player", true)
	await get_tree().process_frame
	await get_tree().process_frame
	var armed_shield: bool = bm.weapons.is_shielded("player")
	bm.weapons._actors["player"]["cooldown"] = 0.0
	bm.weapons.try_shoot("player")
	var shot_drops: bool = not bm.weapons._actors["player"].shield_on and bm.weapons._actors["player"].shield_lock > 0.0
	print("SLOTS %s | DOOM_NO_CANCEL %s | ARMED_SHIELD %s | SHOT_DROPS_SHIELD %s" % [
		"PASS" if (slot1_ok and slot2_ok and slot3_ok and doom_ok) else "FAIL",
		"PASS" if no_cancel else "FAIL",
		"PASS" if armed_shield else "FAIL",
		"PASS" if shot_drops else "FAIL"])
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
	var ok: bool = seen.has("BEAM") and seen.has("HOVER") and saw_struggle
	print("BOSS SMOKE %s (struggle=%s)" % ["PASS" if ok else "FAIL", saw_struggle])
	GameState.battle_mode = false
	GameState.boss_fight = false
	get_tree().quit(0)
