extends Node
## Repro + regression for held-button painting:
## A) hold LMB and MOVE THE MOUSE (warp_mouse → real motion events)
## B) hold LMB, mouse STILL, CAMERA pans (the reported bug: walking while
##    holding place used to paint nothing)

func _ready() -> void:
	GameState.battle_mode = false
	GameState.player_smiley_id = -1
	WorldManager.build_sample_room()
	WorldManager.spawn_points[0] = Vector2(20, 66)
	var game: Node = (load("res://scenes/world/game.tscn") as PackedScene).instantiate()
	game._world_ready = true
	add_child(game)
	await get_tree().create_timer(1.5).timeout
	GameState.set_edit_mode(true)
	GameState.select_block(6056)  # Ruby
	game.editor._align_mode = false  # grid placement path
	await get_tree().create_timer(0.3).timeout
	# ---- A: mouse-motion drag ----
	var vp_center: Vector2 = get_viewport().get_visible_rect().size / 2.0
	var start: Vector2 = vp_center + Vector2(-220, -80)
	Input.warp_mouse(start)
	await get_tree().process_frame
	var press: InputEventMouseButton = InputEventMouseButton.new()
	press.button_index = MOUSE_BUTTON_LEFT
	press.pressed = true
	press.position = start
	press.global_position = start
	Input.parse_input_event(press)
	await get_tree().process_frame
	for i in range(1, 20):
		Input.warp_mouse(start + Vector2(i * 20.0, 0))
		await get_tree().process_frame
		await get_tree().process_frame
	var count_a: int = _count(6056)
	# ---- B: camera pans while button held, mouse still ----
	GameState.select_block(6057)  # Emerald
	for i in range(40):
		GameState.camera_offset = Vector2(i * 12.0, 0)
		await get_tree().process_frame
		await get_tree().process_frame
		if i == 5 or i == 35:
			print("DBG B i=%d tile=%s last=%s held=%s ui=%s align=%s" % [i,
				str(game.editor._get_tile()), str(game.editor._last_place),
				Input.is_action_pressed("place_block"),
				game.editor._is_mouse_over_ui(), game.editor._align_mode])
	var rel: InputEventMouseButton = InputEventMouseButton.new()
	rel.button_index = MOUSE_BUTTON_LEFT
	rel.pressed = false
	rel.position = start
	rel.global_position = start
	Input.parse_input_event(rel)
	await get_tree().process_frame
	var count_b: int = _count(6057)
	print("DRAGPLACE: motion=%d camera=%d %s" % [count_a, count_b,
		"PASS" if count_a >= 8 and count_b >= 8 else "FAIL"])
	get_tree().quit(0)

func _count(id: int) -> int:
	var n: int = 0
	for y in range(WorldManager.world_height):
		for x in range(WorldManager.world_width):
			if WorldManager.get_tile(x, y) == id:
				n += 1
	return n
