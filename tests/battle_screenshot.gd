extends Node
## Dev utility: boots the 1v1 bot arena and saves a screenshot to
## user://battle_check.png for layout/visual verification.

func _ready() -> void:
	GameState.battle_mode = true
	GameState.battle_guns_enabled = false  # FISTS soak: pure chase = max center crossings
	GameState.battle_bot_count = 3  # Full 1v1v1v1 FFA stress
	BattleMap.build()
	var game: Node = (load("res://scenes/world/game.tscn") as PackedScene).instantiate()
	add_child(game)
	# Teleport the player side to side so the bot must cross the center strip
	# over and over — the worst case for spike deaths.
	for cycle in range(7):
		await get_tree().create_timer(4.0).timeout
		var pl: Node = game._get_player(1)
		if pl and not pl._is_dead:
			pl.physics.x = 250.0 if (cycle % 2 == 0) else 1250.0
			pl.physics.y = 464.0
			pl.physics._speedX = 0.0
			pl.physics._speedY = 0.0
	var img: Image = get_viewport().get_texture().get_image()
	img.save_png("user://battle_check.png")
	print("SHOT SAVED")
	var battle: Node = game.get_node_or_null("BattleMode")
	if battle:
		var bl: PackedStringArray = PackedStringArray()
		for l in battle.bots_lives:
			bl.append(str(l))
		print("FFA CROSSING SOAK 28s -> bot lives: [%s]/10, player lives: %d/10" % [", ".join(bl), battle.player_lives])
	GameState.battle_mode = false
	GameState.battle_guns_enabled = true
	GameState.battle_bot_count = 1
	get_tree().quit(0)
