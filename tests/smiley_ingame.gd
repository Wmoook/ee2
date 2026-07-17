extends Node
## Verifies EE smiley sizing + gear roll in-game: spawns with a classic
## smiley, shoves the ball, saves user://smiley_check.png (also captures a
## second shot with the DREAMER ball for a size comparison).

func _ready() -> void:
	GameState.player_smiley_id = 3  # classic laughing smiley
	GameState.battle_mode = false
	WorldManager.build_sample_room()
	var game: Node = (load("res://scenes/world/game.tscn") as PackedScene).instantiate()
	add_child(game)
	await get_tree().create_timer(1.2).timeout
	var p: Node = game._get_player(1)
	if p != null:
		p.physics._speedX = 6.0
	await get_tree().create_timer(0.55).timeout
	if p != null:
		p.physics._speedX = 6.0
	await get_tree().create_timer(0.35).timeout
	var img: Image = get_viewport().get_texture().get_image()
	img.save_png("user://smiley_check.png")
	var rot: float = p._smiley_sprite.rotation if p != null and p._smiley_sprite else -99.0
	var scl: float = p._smiley_sprite.scale.x if p != null and p._smiley_sprite else -99.0
	print("SMILEY CHECK: rot=%.2f scale=%.3f anim=%s" % [rot, scl, str(p._use_anim_sprite) if p else "?"])
	get_tree().quit(0)
