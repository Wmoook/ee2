extends Node
## Dev utility: boots the main menu and saves a screenshot of every tab to
## user://menu_check_<i>.png for layout verification.

func _ready() -> void:
	var menu: Node = (load("res://scenes/ui/main_menu.tscn") as PackedScene).instantiate()
	add_child(menu)
	await get_tree().create_timer(1.0).timeout
	for i in range(3):
		menu._select_tab(i)
		await get_tree().create_timer(0.3).timeout
		var img: Image = get_viewport().get_texture().get_image()
		img.save_png("user://menu_check_%d.png" % i)
	# Lobby overlay (browser view)
	menu._select_tab(1)
	menu._overlay.visible = true
	menu._browser_box.visible = true
	menu._room_box.visible = false
	menu._set_lobby_list_message("No BATTLE lobbies yet — create one!")
	await get_tree().create_timer(0.3).timeout
	var img2: Image = get_viewport().get_texture().get_image()
	img2.save_png("user://menu_check_lobby.png")
	print("MENU SHOTS SAVED")
	get_tree().quit(0)
