extends Node
## Dev utility: boots the 1v1 bot arena and saves a screenshot to
## user://battle_check.png for layout/visual verification.

func _ready() -> void:
	GameState.battle_mode = true
	BattleMap.build()
	var game: Node = (load("res://scenes/world/game.tscn") as PackedScene).instantiate()
	add_child(game)
	await get_tree().create_timer(20.0).timeout
	var img: Image = get_viewport().get_texture().get_image()
	img.save_png("user://battle_check.png")
	print("SHOT SAVED")
	var battle: Node = game.get_node_or_null("BattleMode")
	if battle:
		print("AFK SOAK 20s -> bot lives: %d/10, player lives: %d/10" % [battle.bot_lives, battle.player_lives])
	GameState.battle_mode = false
	get_tree().quit(0)
