extends Node
## Dev utility: boots the main menu and saves a screenshot to
## user://menu_check.png for layout verification.

func _ready() -> void:
	var menu: Node = (load("res://scenes/ui/main_menu.tscn") as PackedScene).instantiate()
	add_child(menu)
	await get_tree().create_timer(1.2).timeout
	var img: Image = get_viewport().get_texture().get_image()
	img.save_png("user://menu_check.png")
	print("MENU SHOT SAVED")
	get_tree().quit(0)
