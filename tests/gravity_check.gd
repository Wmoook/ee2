extends Node
## GRAVITY mode test: map builds stable, knocked supports cascade into
## falling debris, debris settles back into grid tiles (mass conserved).

func _count_loose() -> int:
	# Grid blocks + resting rubble free blocks (tilted rest keeps mass)
	var n: int = 0
	for y in range(1, GravityMode.GROUND_Y):
		for x in range(1, WorldManager.world_width - 1):
			if WorldManager.get_tile(x, y) != 0 and WorldManager.get_tile(x, y) != 9:
				n += 1
	for fb in WorldManager.free_blocks:
		if fb.get("rubble", false):
			n += 1
	return n

func _ready() -> void:
	GameState.battle_mode = true
	GameState.gravity_mode = true
	GravityMode.build_map()
	var before: int = _count_loose()
	var game: Node = (load("res://scenes/world/game.tscn") as PackedScene).instantiate()
	game._world_ready = true
	add_child(game)
	await get_tree().create_timer(1.0).timeout
	var grav: Node = game.get_node_or_null("GravityMode")
	print("GRAV: mode=%s blocks=%d debris_after_1s=%d (map must be STABLE)" % [str(grav != null), before, grav._debris.size() if grav else -1])
	for dd in grav._debris:
		print("GRAV loose: id=%d pos=(%.0f,%.0f) vel=(%.0f,%.0f)" % [dd.id, dd.pos.x, dd.pos.y, dd.vel.x, dd.vel.y])
	var stable: bool = grav != null and grav._debris.size() == 0 and _count_loose() == before
	get_viewport().get_texture().get_image().save_png("user://grav_1_intact.png")
	# Knock out the arch's left leg base + a tower base pair
	grav._loosen(86, GravityMode.GROUND_Y - 1, Vector2(60, -80))
	grav._loosen(86, GravityMode.GROUND_Y - 2, Vector2(60, -80))
	grav._loosen(14, GravityMode.GROUND_Y - 1, Vector2(90, -60))
	grav._loosen(15, GravityMode.GROUND_Y - 1, Vector2(90, -60))
	await get_tree().create_timer(0.12).timeout
	var mid_debris: int = grav._debris.size()
	get_viewport().get_texture().get_image().save_png("user://grav_2_falling.png")
	await get_tree().create_timer(6.5).timeout
	var after: int = _count_loose()
	var left: int = grav._debris.size()
	for dd in grav._debris:
		print("GRAV straggler: id=%d pos=(%.0f,%.0f) vel=(%.0f,%.0f) bn=%d" % [dd.id, dd.pos.x, dd.pos.y, dd.vel.x, dd.vel.y, dd.bn])
	get_viewport().get_texture().get_image().save_png("user://grav_3_settled.png")
	print("GRAV: mid_debris=%d settled_left=%d blocks before=%d after=%d" % [mid_debris, left, before, after])
	var ok: bool = stable and mid_debris >= 2 and left == 0 and after >= before - 1 and after <= before
	print("GRAVITY CHECK: %s" % ("PASS" if ok else "FAIL"))
	get_tree().quit(0 if ok else 1)
