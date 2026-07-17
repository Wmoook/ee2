extends Node
## Render stress: dense build (12k+ tiles, 400 free blocks, 24 curves, 60
## lines). Measures REAL frame time (delta) in three phases: idle at 3x zoom,
## panning at 3x, and panning fully ZOOMED OUT at 0.5x over the dense field.

var _phase: int = 0
var _frames: int = 0
var _acc: float = 0.0
var _game: Node = null
var _labels: Array = ["idle 3x", "pan 3x", "pan 0.5x ZOOMED OUT"]

func _ready() -> void:
	GameState.battle_mode = false
	GameState.player_smiley_id = -1
	WorldManager.build_sample_room()
	var pack_ids: Array = []
	for cat in GameState.BLOCK_CATEGORIES:
		if cat.name in ["Candy", "Neon", "Castle", "Frost", "Magma", "Jungle", "Ocean", "Space", "Factory", "Desert", "Dream", "Arcade", "Gems", "Spooky"]:
			pack_ids.append_array(cat.ids)
	for y in range(2, 62):
		for x in range(2, 202):
			WorldManager.set_fg_tile(x, y, pack_ids[(x * 7 + y * 13) % pack_ids.size()])
			if y % 2 == 0:
				WorldManager.set_bg_tile(x, y + 70, 5120)
	var nofb: bool = "--nofb" in OS.get_cmdline_user_args()
	for i in range(0 if nofb else 400):
		WorldManager.free_blocks.append({
			"pos": Vector2(40.0 + (i * 37 % 3000), 1200.0 + (i * 53 % 500)),
			"id": pack_ids[i % pack_ids.size()], "rotation": float(i * 11 % 360), "group": -1})
	WorldManager.free_blocks_changed.emit()
	for k in range(0 if nofb else 24):
		var pts: PackedVector2Array = PackedVector2Array()
		for pxx in range(0, 400, 4):
			pts.append(Vector2(200 + (k % 6) * 500 + pxx, 2000.0 + (k / 6) * 120.0 + sin(pxx * 0.03 + k) * 30.0))
		WorldManager.add_polyline(pts, "top", 5058 + (k % 10))
	for L in range(0 if nofb else 60):
		WorldManager.lines.append({"start": Vector2(100 + L * 50, 2600), "end": Vector2(140 + L * 50, 2680), "color": Color(1, 1, 1), "width": 2.0})
	WorldManager.lines_changed.emit()
	WorldManager.spawn_points[0] = Vector2(20, 66)
	_game = (load("res://scenes/world/game.tscn") as PackedScene).instantiate()
	_game._world_ready = true
	add_child(_game)
	await get_tree().create_timer(4.0).timeout
	_game.renderer.perf_redraws = 0
	_phase = 1

func _process(delta: float) -> void:
	if _phase == 0:
		return
	_frames += 1
	_acc += delta * 1000.0  # real frame time (vsync off, fps uncapped)
	if _frames >= 300:
		var avg: float = _acc / _frames
		print("STRESS [%s]: %.2fms (~%.0f fps) redraws=%d" % [_labels[_phase - 1], avg, 1000.0 / maxf(avg, 0.001), _game.renderer.perf_redraws])
		_game.renderer.perf_redraws = 0
		_frames = 0
		_acc = 0.0
		_phase += 1
		if _phase == 3:
			# Fully zoomed out over the dense field
			var p: Node = _game._get_player(1)
			if p != null and p._camera != null:
				p._camera.zoom = Vector2(0.5, 0.5)
		elif _phase > 3:
			print("STRESS DONE")
			get_tree().quit(0)
	if _phase >= 2:
		GameState.camera_offset = Vector2(fmod(GameState.camera_offset.x + delta * 600.0, 2400.0), sin(Time.get_ticks_msec() * 0.001) * 300.0 - 400.0)
