extends Node
## Dev smoke test for DOT SURVIVORS: director spawns the horde, coins level
## you up (paused choice), chests roll treasure, damage works, and hitting
## 15:00 wins. Saves user://survivors_check.png.

func _ready() -> void:
	GameState.battle_mode = true
	GameState.survivors_mode = true
	GameState.boss_fight = false
	SurvivorsMap.build()
	var game: Node = (load("res://scenes/world/game.tscn") as PackedScene).instantiate()
	add_child(game)
	await get_tree().create_timer(1.0).timeout
	var sm: Node = game.get_node_or_null("SurvivorsMode")
	if sm == null:
		print("SURV FAIL - no SurvivorsMode node")
		get_tree().quit(1)
		return
	# Fast-forward the director to minute ~6.5 and let it spawn
	sm.elapsed = 400.0
	await get_tree().create_timer(2.5).timeout
	var spawned: int = sm.horde.enemies.size()
	print("SPAWNED %s (%d enemies at m=%.1f)" % ["PASS" if spawned >= 8 else "FAIL", spawned, sm.minute()])
	# Coins -> level up -> choice opens (tree pauses)
	sm.on_coin(sm.xp_need)
	await get_tree().create_timer(0.3).timeout
	var choice_ok: bool = sm._choice_open and get_tree().paused
	sm._close_choice()
	await get_tree().create_timer(0.2).timeout
	var resumed: bool = not get_tree().paused
	print("LEVELUP %s (choice=%s resumed=%s level=%d)" % ["PASS" if (choice_ok and resumed) else "FAIL", choice_ok, resumed, sm.level])
	# Chest treasure roll
	var lv_before: int = sm.arsenal.levels.blaster + sm.arsenal.levels.nova + sm.arsenal.levels.rail + sm.arsenal.levels.sweep + sm.arsenal.levels.aura + sm.magnet_lv + sm.overdrive_lv + sm.plating_lv + sm.thruster_lv
	sm.on_chest(sm.player_center())
	await get_tree().create_timer(0.3).timeout
	var chest_open: bool = sm._choice_open
	sm._close_choice()
	await get_tree().create_timer(0.2).timeout
	var lv_after: int = sm.arsenal.levels.blaster + sm.arsenal.levels.nova + sm.arsenal.levels.rail + sm.arsenal.levels.sweep + sm.arsenal.levels.aura + sm.magnet_lv + sm.overdrive_lv + sm.plating_lv + sm.thruster_lv
	print("CHEST %s (panel=%s upgrades %d->%d)" % ["PASS" if (chest_open and lv_after > lv_before) else "FAIL", chest_open, lv_before, lv_after])
	# Damage
	var hp0: int = sm.hp
	sm._invuln = 0.0
	sm._hurt(1, Vector2.RIGHT)
	print("DAMAGE %s (hp %d->%d)" % ["PASS" if sm.hp == hp0 - 1 else "FAIL", hp0, sm.hp])
	var img: Image = get_viewport().get_texture().get_image()
	img.save_png("user://survivors_check.png")
	print("SHOT SAVED")
	# Victory at 15:00
	sm.elapsed = 899.5
	await get_tree().create_timer(1.0).timeout
	print("VICTORY %s (over=%s won=%s)" % ["PASS" if (sm._over and sm._won) else "FAIL", sm._over, sm._won])
	get_tree().paused = false
	GameState.battle_mode = false
	GameState.survivors_mode = false
	get_tree().quit(0)
