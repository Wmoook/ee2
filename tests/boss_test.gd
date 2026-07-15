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
	var img2: Image = get_viewport().get_texture().get_image()
	img2.save_png("user://boss_check.png")
	print("STATES SEEN: %s" % [seen.keys()])
	var ok: bool = seen.has("BEAM") and seen.has("HOVER") and saw_struggle
	print("BOSS SMOKE %s (struggle=%s)" % ["PASS" if ok else "FAIL", saw_struggle])
	GameState.battle_mode = false
	GameState.boss_fight = false
	get_tree().quit(0)
