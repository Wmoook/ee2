class_name GravityMode
extends Node2D
## GRAVITY sandbox: FULLY destructible arena. Any block with air beneath
## falls as tumbling debris and re-stacks where it lands; running into
## blocks knocks them flying with your momentum, so towers topple and
## collapses cascade. Offline test mode — own file per design rules.

const GROUND_Y: int = 36              # rows >= this are indestructible floor
const SCAN_DT: float = 0.07           # support-scan cadence (cascade speed)
const KNOCK_SPEED: float = 1.0        # min |EE speed| to plow through blocks
const MAX_DEBRIS: int = 600
const G_PX: float = 1150.0            # debris gravity px/s^2
const TERMINAL: float = 760.0

var _debris: Array = []               # {pos: Vector2, vel: Vector2, rot: float, rv: float, id: int}
var _scan_accum: float = 0.0
var _player: Node = null
var _renderer: Node2D = null
var _rng: RandomNumberGenerator = RandomNumberGenerator.new()

static func build_map() -> void:
	var W: int = 110
	var H: int = 42
	WorldManager.init_empty_world(W, H)
	# Solid ground slab
	for x in range(1, W - 1):
		for y in range(GROUND_Y, H - 1):
			WorldManager.set_fg_tile(x, y, 5000)
	# Towers of varying heights and blocks
	var tower_ids: Array = [6004, 6012, 6020, 6033, 6041]
	var tx: int = 14
	for t in range(5):
		var h: int = 8 + t * 3
		var wdt: int = 2 if t % 2 == 0 else 3
		for cx in range(tx, tx + wdt):
			for cy in range(GROUND_Y - h, GROUND_Y):
				WorldManager.set_fg_tile(cx, cy, tower_ids[t])
		tx += wdt + 6
	# Pyramid
	var px: int = 62
	for row in range(9):
		for cx in range(px + row, px + 18 - row):
			WorldManager.set_fg_tile(cx, GROUND_Y - 1 - row, 6008)
	# Arch: two legs + a span (knock a leg out!)
	var ax: int = 86
	for cy in range(GROUND_Y - 9, GROUND_Y):
		WorldManager.set_fg_tile(ax, cy, 6027)
		WorldManager.set_fg_tile(ax + 9, cy, 6027)
	for cx in range(ax, ax + 10):
		WorldManager.set_fg_tile(cx, GROUND_Y - 10, 6051)
		WorldManager.set_fg_tile(cx, GROUND_Y - 9 if cx == ax or cx == ax + 9 else GROUND_Y - 10, 6051)
	# Tall thin spire near spawn to topple immediately
	for cy in range(GROUND_Y - 14, GROUND_Y):
		WorldManager.set_fg_tile(9, cy, 6060)
	WorldManager.spawn_points = [Vector2(4, GROUND_Y - 2)]
	WorldManager.tile_changed.emit(0, 0, 0)

func _ready() -> void:
	z_index = 3
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_rng.randomize()
	var lay: CanvasLayer = CanvasLayer.new()
	var lbl: Label = Label.new()
	lbl.text = "GRAVITY SANDBOX — plow through the towers! Unsupported blocks FALL. ESC = menu"
	lbl.add_theme_font_size_override("font_size", 15)
	lbl.add_theme_color_override("font_color", Color(0.85, 0.95, 1.0))
	lbl.add_theme_color_override("font_outline_color", Color(0, 0, 0))
	lbl.add_theme_constant_override("outline_size", 6)
	lbl.set_anchors_preset(Control.PRESET_CENTER_TOP)
	lbl.position.y = 8
	lay.add_child(lbl)
	add_child(lay)

func _find_player() -> Node:
	for ch in get_parent().get_children():
		if ch.get("is_local") == true and ch.get("physics") != null:
			return ch
	return null

func _is_static(cx: int, cy: int) -> bool:
	if cy >= GROUND_Y:
		return true
	if cx <= 0 or cx >= WorldManager.world_width - 1 or cy <= 0:
		return true
	return WorldManager.get_tile(cx, cy) == 9  # border art

func _loosen(cx: int, cy: int, vel: Vector2) -> void:
	var id: int = WorldManager.get_tile(cx, cy)
	if id == 0 or _is_static(cx, cy):
		return
	if _debris.size() >= MAX_DEBRIS:
		return
	WorldManager.set_fg_tile(cx, cy, 0)
	_debris.append({"pos": Vector2(cx * 16 + 8, cy * 16 + 8), "vel": vel,
		"rot": 0.0, "rv": _rng.randf_range(-2.5, 2.5), "id": id})

func _support_scan() -> void:
	# Bottom-up so a whole hanging column releases in one scan (cascade)
	for cy in range(GROUND_Y - 1, 1, -1):
		for cx in range(1, WorldManager.world_width - 1):
			if WorldManager.get_tile(cx, cy) == 0 or _is_static(cx, cy):
				continue
			if WorldManager.get_tile(cx, cy + 1) == 0 and cy + 1 < GROUND_Y:
				_loosen(cx, cy, Vector2(_rng.randf_range(-14.0, 14.0), 0.0))

func _knock_from_player(_delta: float) -> void:
	if _player == null or _player.get("physics") == null:
		return
	var ph = _player.physics
	var sx: float = ph._speedX
	var sy: float = ph._speedY
	var bx: float = ph.x
	var by: float = ph.y
	var rows: Array = [int(floor(by / 16.0)), int(floor((by + 15.0) / 16.0))]
	# Horizontal plow: the column just ahead of the leading edge
	if absf(sx) > KNOCK_SPEED:
		var lead_x: float = bx + 18.0 if sx > 0.0 else bx - 3.0
		var cx: int = int(floor(lead_x / 16.0))
		for cy in rows:
			if WorldManager.get_tile(cx, cy) != 0 and not _is_static(cx, cy):
				_loosen(cx, cy, Vector2(sx * 34.0, minf(sy * 20.0, 0.0) - 90.0))
				ph._speedX *= 0.88  # impact costs a little momentum
	# Head bonk: knock the ceiling block when jumping up into it
	if sy < -KNOCK_SPEED:
		var cyu: int = int(floor((by - 3.0) / 16.0))
		for cxx in [int(floor(bx / 16.0)), int(floor((bx + 15.0) / 16.0))]:
			if WorldManager.get_tile(cxx, cyu) != 0 and not _is_static(cxx, cyu):
				_loosen(cxx, cyu, Vector2(_rng.randf_range(-40.0, 40.0), sy * 26.0))

func _step_debris(delta: float) -> void:
	var i: int = _debris.size() - 1
	while i >= 0:
		var d: Dictionary = _debris[i]
		var vel: Vector2 = d.vel
		vel.y = minf(vel.y + G_PX * delta, TERMINAL)
		vel.x *= pow(0.25, delta)  # lateral decay
		var pos: Vector2 = d.pos + vel * delta
		d.rot = d.rot + d.rv * delta
		var cx: int = clampi(int(floor(pos.x / 16.0)), 1, WorldManager.world_width - 2)
		# Wall bump: cancel lateral motion into solids
		if vel.x != 0.0:
			var side_cx: int = int(floor((pos.x + (8.0 if vel.x > 0.0 else -8.0)) / 16.0))
			if WorldManager.get_tile(side_cx, int(floor(pos.y / 16.0))) != 0:
				vel.x = 0.0
				pos.x = d.pos.x
				cx = clampi(int(floor(pos.x / 16.0)), 1, WorldManager.world_width - 2)
		# Landed? settle into the cell above the support
		var below: int = int(floor((pos.y + 8.0) / 16.0))
		if vel.y > 0.0 and (below >= GROUND_Y or WorldManager.get_tile(cx, below) != 0):
			var cy: int = below - 1
			while cy > 1 and WorldManager.get_tile(cx, cy) != 0:
				cy -= 1
			if cy > 1:
				WorldManager.set_fg_tile(cx, cy, d.id)
			_debris.remove_at(i)
			i -= 1
			continue
		d.vel = vel
		d.pos = pos
		i -= 1

func _process(delta: float) -> void:
	if _player == null:
		_player = _find_player()
	if _renderer == null:
		_renderer = get_parent().get("renderer")
	_knock_from_player(delta)
	_scan_accum += delta
	if _scan_accum >= SCAN_DT:
		_scan_accum = 0.0
		_support_scan()
	_step_debris(delta)
	if _debris.size() > 0 or true:
		queue_redraw()

func _draw() -> void:
	if _renderer == null:
		return
	for d in _debris:
		draw_set_transform(d.pos, d.rot, Vector2.ONE)
		_renderer.draw_block_at(self, Rect2(-8, -8, 16, 16), d.id)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
