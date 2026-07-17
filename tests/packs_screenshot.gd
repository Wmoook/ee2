extends Node
## Lays out every new pack block + draws winding curves textured with the
## Curves-tab ribbons, then saves user://packs_check.png.

func _ready() -> void:
	GameState.battle_mode = false
	GameState.player_smiley_id = -1
	WorldManager.build_sample_room()
	# Pack rows (Candy, Neon, Castle, Frost+Magma, spare)
	var rows: Array = [
		[5030, 5031, 5032, 5033, 5034, 5035, 5036, 5037, 5038, 5039, 5040, 5041],
		[5042, 5043, 5044, 5045, 5046, 5047, 5048, 5049, 5050, 5051, 5052, -1],
		[5053, 5054, 5055, 5056, 5057, -1, 5058, 5059, 5060, 5061, 5062, 5063],
		[5064, 5065, 5066, 5067, -1, -1, -1, -1, -1, -1, -1, -1],
	]
	for r in range(rows.size()):
		for c in range(rows[r].size()):
			var id: int = rows[r][c]
			if id > 0:
				WorldManager.set_fg_tile(8 + c * 2, 9 + r * 2, id)
	# Ribbon curves: three S-waves with different Curves-tab textures
	var ribbons: Array = [5058, 5060, 5064]  # rainbow, cyan tube, candy
	for k in range(ribbons.size()):
		var pts: PackedVector2Array = PackedVector2Array()
		for px in range(0, 360, 2):
			pts.append(Vector2(120 + px, 305.0 + k * 42.0 + sin(px * 0.022 + k) * 22.0))
		WorldManager.add_polyline(pts, "top", ribbons[k])
	WorldManager.spawn_points[0] = Vector2(19, 15)
	var game: Node = (load("res://scenes/world/game.tscn") as PackedScene).instantiate()
	game._world_ready = true  # keep OUR staged room — don't load world_save.json
	add_child(game)
	await get_tree().create_timer(1.4).timeout
	var img: Image = get_viewport().get_texture().get_image()
	img.save_png("user://packs_check.png")
	print("PACKS SHOT SAVED")
	get_tree().quit(0)
