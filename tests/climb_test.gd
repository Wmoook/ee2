extends Node
## Dev test: force the DOOM RAY drop and watch whether the bot can climb the
## tower and claim it. Prints breadcrumbs every second.

func _ready() -> void:
	GameState.battle_mode = true
	GameState.battle_guns_enabled = false
	GameState.battle_bot_count = 1
	BattleMap.build()
	var game: Node = (load("res://scenes/world/game.tscn") as PackedScene).instantiate()
	add_child(game)
	await get_tree().create_timer(1.0).timeout
	var battle: Node = game.get_node_or_null("BattleMode")
	battle.weapons._super_timer = 0.5  # Drop the super NOW
	var got_it: bool = false
	for i in range(26):
		await get_tree().create_timer(1.0).timeout
		var b: Node = battle.bots[0]
		print("t=%02d bot=(%.0f, %.0f) grounded=%s doom_state=%d held=%s" % [
			i, b.get_center().x, b.get_center().y, b.physics.is_grounded,
			battle.weapons._super_state, battle.weapons.get_weapon("bot1")])
		if battle.weapons.get_weapon("bot1") == "doom":
			print("CLIMB SUCCESS at t=%ds" % i)
			got_it = true
			break
	if not got_it:
		print("CLIMB FAILED - bot never reached the DOOM RAY")
	GameState.battle_mode = false
	GameState.battle_guns_enabled = true
	get_tree().quit(0)
