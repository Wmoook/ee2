extends Node
## Dev utility: boots UNDEAD BUNKER, lets round 1 spawn and chew, then saves
## a screenshot to user://zombies_check.png plus a state printout.

func _ready() -> void:
	GameState.battle_mode = true
	GameState.zombies_mode = true
	GameState.boss_fight = false
	GameState.survivors_mode = false
	ZombiesMap.build()
	var game: Node = (load("res://scenes/world/game.tscn") as PackedScene).instantiate()
	add_child(game)
	await get_tree().create_timer(16.0).timeout
	var img: Image = get_viewport().get_texture().get_image()
	img.save_png("user://zombies_check.png")
	print("ZOMBIES SHOT SAVED")
	var zm: Node = game.get_node_or_null("ZombiesMode")
	if zm:
		var planks: Array = []
		for p in zm._planks:
			planks.append(str(p))
		print("ZOMBIES SMOKE: round=%d alive=%d to_spawn=%d points=%d hp=%d planks=[%s] over=%s" % [
			zm.round_num, zm._zombies.size(), zm._to_spawn, zm.points, zm.player_hp,
			", ".join(planks), str(zm._over)])
	else:
		print("ZOMBIES SMOKE FAIL: mode node missing")
	get_tree().quit(0)
