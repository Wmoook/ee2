extends Node
## Dev utility: boots the game scene, enters edit mode, saves a screenshot to
## user://ui_check.png and quits. Used to visually verify editor UI layout.

func _ready() -> void:
	var game: Node = (load("res://scenes/world/game.tscn") as PackedScene).instantiate()
	add_child(game)
	await get_tree().create_timer(1.2).timeout
	GameState.is_edit_mode = true
	GameState.edit_mode_changed.emit(true)
	await get_tree().create_timer(0.8).timeout
	var img: Image = get_viewport().get_texture().get_image()
	img.save_png("user://ui_check.png")
	print("SHOT SAVED")
	get_tree().quit(0)
