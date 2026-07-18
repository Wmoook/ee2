extends Node
## Verifies non-palette classic ids (world border 9 + old EE bricks) render
## through the TileMap bake. Saves user://border_check.png.

func _ready() -> void:
	GameState.battle_mode = false
	GameState.player_smiley_id = -1
	WorldManager.build_sample_room()
	for x in range(12, 32):
		WorldManager.set_fg_tile(x, 61, 21)
		WorldManager.set_fg_tile(x, 62, 9)   # the world-border block
		WorldManager.set_fg_tile(x, 63, 10)
		WorldManager.set_fg_tile(x, 64, 11)
	WorldManager.spawn_points[0] = Vector2(21, 59)
	var game: Node = (load("res://scenes/world/game.tscn") as PackedScene).instantiate()
	game._world_ready = true
	add_child(game)
	await get_tree().create_timer(1.2).timeout
	var img: Image = get_viewport().get_texture().get_image()
	img.save_png("user://border_check.png")
	print("BORDER SHOT SAVED")
	get_tree().quit(0)
