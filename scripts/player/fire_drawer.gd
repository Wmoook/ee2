extends Node2D
## Draws fire particles on a separate z-layer (above foreground blocks)

func _draw() -> void:
	var parent: PlayerController = get_parent() as PlayerController
	if not parent:
		return
	# Heat shield removed — now part of particle system in player_controller
	if parent._fire_particles.is_empty():
		return
	for p in parent._fire_particles:
		var lp: Vector2 = p.wpos - parent._visual_pos
		var t: float = p.life / p.max_life
		var is_hot: bool = p.get("hot", false)
		# Skip nearly-dead particles
		if t < 0.15:
			continue
		# Dim out toward the end: fade alpha for last 30% of life
		var fade: float = 1.0 if t > 0.3 else t / 0.3
		var col: Color
		if is_hot:
			col = Color(1.0, lerpf(0.85, 1.0, t), lerpf(0.5, 0.95, t), fade)
		elif t > 0.8:
			col = Color(1.0, 1.0, 0.9, fade)
		elif t > 0.6:
			col = Color(1.0, 0.9, 0.3, fade)
		elif t > 0.4:
			col = Color(1.0, 0.55, 0.08, fade)
		else:
			col = Color(0.9, 0.25, 0.05, fade)
		draw_rect(Rect2(floor(lp.x), floor(lp.y), 1, 1), col)

func _process(_delta: float) -> void:
	var parent: PlayerController = get_parent() as PlayerController
	if parent and (parent._fire_particles.size() > 0 or parent._at_max_speed):
		queue_redraw()
