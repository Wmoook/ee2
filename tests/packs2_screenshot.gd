extends Node
## Showcase: lays out all 82 MEGA-PACK blocks + new CURVES II ribbons,
## saves user://packs2_world.png, then opens the palette (edit mode) on a
## pack tab and saves user://packs2_palette.png.

func _ready() -> void:
	GameState.battle_mode = false
	GameState.player_smiley_id = 3
	WorldManager.build_sample_room()
	var row_ids: Array = []
	for r in range(9):
		var row: Array = []
		for c in range(8):
			row.append(6000 + r * 8 + c)
		row_ids.append(row)
	for r2 in range(row_ids.size()):
		for c2 in range(row_ids[r2].size()):
			WorldManager.set_fg_tile(7 + c2 * 2, 4 + r2 * 2, row_ids[r2][c2])
	# CURVES II ribbons winding beneath the grid
	var ribbons: Array = [6080, 6083, 6084, 6087, 6089]
	for k in range(ribbons.size()):
		var pts: PackedVector2Array = PackedVector2Array()
		for pxx in range(0, 300, 2):
			pts.append(Vector2(390 + pxx, 105.0 + k * 44.0 + sin(pxx * 0.024 + k * 1.3) * 20.0))
		WorldManager.add_polyline(pts, "top", ribbons[k])
	WorldManager.spawn_points[0] = Vector2(21, 15)
	var game: Node = (load("res://scenes/world/game.tscn") as PackedScene).instantiate()
	game._world_ready = true
	add_child(game)
	await get_tree().create_timer(1.4).timeout
	var img: Image = get_viewport().get_texture().get_image()
	img.save_png("user://packs2_world.png")
	# Palette UI with pack tabs
	GameState.set_edit_mode(true)
	var hud: Node = null
	for ch in game.get_children():
		if ch is CanvasLayer and ch.has_method("_on_tab_pressed"):
			hud = ch
			break
	if hud != null:
		hud._on_tab_pressed(13)  # Gems
	await get_tree().create_timer(0.5).timeout
	var img2: Image = get_viewport().get_texture().get_image()
	img2.save_png("user://packs2_palette.png")
	print("PACKS2 SHOTS SAVED (hud=%s)" % str(hud != null))
	get_tree().quit(0)
