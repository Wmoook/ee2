class_name GravityMode
extends Node2D
## GRAVITY sandbox: FULLY destructible arena. Any block with air beneath
## falls as tumbling debris and re-stacks where it lands; running into
## blocks knocks them flying with your momentum, so towers topple and
## collapses cascade. Offline test mode — own file per design rules.

const GROUND_Y: int = 36              # rows >= this are indestructible floor
const SCAN_DT: float = 0.07           # support-scan cadence (cascade speed)
const KNOCK_SPEED: float = 1.0        # min |EE speed| to plow through blocks
const MAX_DEBRIS: int = 900
const G_PX: float = 1150.0            # debris gravity px/s^2
const TERMINAL: float = 760.0

## attached=true: BLOCK GRAVITY toggle in a normal world — everything the
## player built obeys gravity (curves crumble into their component tiles).
## attached=false: the standalone GRAVITY arena mode.
var attached: bool = false
var ground_y: int = GROUND_Y
var _debris: Array = []               # {pos, vel, rot, rv, id, bn (bounce count)}
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
	if attached:
		ground_y = WorldManager.world_height - 1
		_crumble_curves_and_frees()
		return
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

func _exit_tree() -> void:
	# Toggle OFF mid-collapse: nothing vanishes — airborne debris comes to
	# rest instantly as rubble free blocks
	for d in _debris:
		WorldManager.free_blocks.append({"pos": (d.pos as Vector2) - Vector2(8, 8),
			"id": d.id, "rotation": rad_to_deg(round(d.rot / (PI / 12.0)) * (PI / 12.0)), "rubble": true})
	if _debris.size() > 0:
		WorldManager.free_blocks_changed.emit()
	_debris.clear()

func _crumble_curves_and_frees() -> void:
	## BLOCK GRAVITY ON: curves shatter into their component 16px tiles
	## (tangent-rotated debris) and every placed free block goes dynamic.
	for poly in WorldManager.polylines:
		if poly.get("collision_only", false) or poly.get("render_only", false):
			continue
		var pts: PackedVector2Array = poly.points
		var bid: int = poly.get("block_id", 9)
		var acc: float = 8.0
		for i in range(1, pts.size()):
			var seg: float = pts[i].distance_to(pts[i - 1])
			acc += seg
			while acc >= 16.0 and _debris.size() < MAX_DEBRIS:
				acc -= 16.0
				var t: Vector2 = (pts[i] - pts[i - 1]).normalized()
				_debris.append({"pos": pts[i], "vel": Vector2(_rng.randf_range(-25.0, 25.0), _rng.randf_range(-40.0, 0.0)),
					"rot": atan2(t.y, t.x), "rv": _rng.randf_range(-3.0, 3.0), "id": bid, "bn": 0})
	WorldManager.polylines.clear()
	WorldManager.build_curve_colliders()
	var fbs: Array = WorldManager.free_blocks.duplicate()
	WorldManager.free_blocks.clear()
	for fb in fbs:
		if fb.get("curve_visual", false) or fb.get("curve_collision", false):
			continue
		if _debris.size() < MAX_DEBRIS:
			_debris.append({"pos": (fb.pos as Vector2) + Vector2(8, 8), "vel": Vector2(0, -20),
				"rot": deg_to_rad(float(fb.get("rotation", 0.0))), "rv": _rng.randf_range(-2.0, 2.0),
				"id": fb.id, "bn": 0})
		else:
			WorldManager.free_blocks.append(fb)
	WorldManager.free_blocks_changed.emit()
	WorldManager.polylines_changed.emit()
	WorldManager.tile_changed.emit(0, 0, 0)

func _find_player() -> Node:
	for ch in get_parent().get_children():
		if ch.get("is_local") == true and ch.get("physics") != null:
			return ch
	return null

func _is_static(cx: int, cy: int) -> bool:
	if cy >= ground_y:
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
		"rot": 0.0, "rv": _rng.randf_range(-3.5, 3.5), "id": id, "bn": 0})

func _support_scan() -> void:
	# Bottom-up so a whole hanging column releases in one scan (cascade).
	# Released blocks TOPPLE toward their open side, and the higher a block
	# sits in the released column the harder it is flung — a tower arcs
	# sideways like a falling tree instead of dropping in formation.
	var col_n: Dictionary = {}  # cx -> how many released below (this scan)
	for cy in range(ground_y - 1, 1, -1):
		for cx in range(1, WorldManager.world_width - 1):
			if WorldManager.get_tile(cx, cy) == 0 or _is_static(cx, cy):
				continue
			if WorldManager.get_tile(cx, cy + 1) == 0 and cy + 1 < ground_y:
				var left_open: bool = WorldManager.get_tile(cx - 1, cy) == 0
				var right_open: bool = WorldManager.get_tile(cx + 1, cy) == 0
				var tip: float
				if left_open and not right_open:
					tip = -1.0
				elif right_open and not left_open:
					tip = 1.0
				else:
					tip = 1.0 if _rng.randf() < 0.5 else -1.0
				var n: int = col_n.get(cx, 0)
				col_n[cx] = n + 1
				var vx: float = tip * (22.0 + float(n) * 26.0 + _rng.randf_range(0.0, 30.0))
				_loosen(cx, cy, Vector2(vx, _rng.randf_range(-30.0, 0.0)))

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
				if not ph.is_god_mode:
					ph._speedX *= 0.88  # impact costs a little momentum (not as a god)
	# Plow through resting RUBBLE free blocks the same way
	if absf(sx) > KNOCK_SPEED or absf(sy) > KNOCK_SPEED:
		var kicked: Array = []
		for fb in WorldManager.fb_near(bx, by, 26.0):
			if fb.get("rubble", false):
				var fc: Vector2 = (fb.pos as Vector2) + Vector2(8, 8)
				if fc.distance_to(Vector2(bx + 8.0, by + 8.0)) < 24.0:
					kicked.append(fb)
		for fb in kicked:
			WorldManager.free_blocks.erase(fb)
			_debris.append({"pos": (fb.pos as Vector2) + Vector2(8, 8),
				"vel": Vector2(sx * 34.0, minf(sy * 26.0, 0.0) - 110.0),
				"rot": deg_to_rad(float(fb.get("rotation", 0.0))),
				"rv": _rng.randf_range(-5.0, 5.0), "id": fb.id, "bn": 0})
		if kicked.size() > 0:
			WorldManager.free_blocks_changed.emit()
	# Head bonk: knock the ceiling block when jumping up into it
	if sy < -KNOCK_SPEED:
		var cyu: int = int(floor((by - 3.0) / 16.0))
		for cxx in [int(floor(bx / 16.0)), int(floor((bx + 15.0) / 16.0))]:
			if WorldManager.get_tile(cxx, cyu) != 0 and not _is_static(cxx, cyu):
				_loosen(cxx, cyu, Vector2(_rng.randf_range(-40.0, 40.0), sy * 26.0))

func _step_debris(delta: float) -> void:
	# Player collision setup: debris deflects OFF the ball, never through it
	var pc: Vector2 = Vector2.INF
	var pvel: Vector2 = Vector2.ZERO
	if _player != null and _player.get("physics") != null:
		pc = Vector2(_player.physics.x + 8.0, _player.physics.y + 8.0)
		pvel = Vector2(_player.physics._speedX, _player.physics._speedY) * 100.0
	var i: int = _debris.size() - 1
	while i >= 0:
		var d: Dictionary = _debris[i]
		var vel: Vector2 = d.vel
		vel.y = minf(vel.y + G_PX * delta, TERMINAL)
		vel.x *= pow(0.4, delta)  # lateral decay
		var pos: Vector2 = d.pos + vel * delta
		d.rot = d.rot + d.rv * delta
		# Deflect off the player ball (16px circle vs 16px block ~ r8+r8)
		if pc.x != INF:
			var away: Vector2 = pos - pc
			var adist: float = away.length()
			if adist < 16.5:
				away = away.normalized() if adist > 0.01 else Vector2(0, -1)
				pos = pc + away * 16.5
				var rel: Vector2 = vel - pvel
				var into: float = rel.dot(-away)
				if into > 0.0:
					vel += away * (into * 1.15) + pvel * 0.25
				d.rv = _rng.randf_range(-5.0, 5.0)
		var cx: int = clampi(int(floor(pos.x / 16.0)), 1, WorldManager.world_width - 2)
		# Wall bump: cancel lateral motion into solids
		if vel.x != 0.0:
			var side_cx: int = int(floor((pos.x + (8.0 if vel.x > 0.0 else -8.0)) / 16.0))
			if WorldManager.get_tile(side_cx, int(floor(pos.y / 16.0))) != 0:
				vel.x = 0.0
				pos.x = d.pos.x
				cx = clampi(int(floor(pos.x / 16.0)), 1, WorldManager.world_width - 2)
		# Landed? bounce with spin (up to 2 hops), then come to rest — TILTED
		# blocks stay tilted as rubble free blocks; only near-square landings
		# merge back into the grid. Debris also stacks on rubble piles.
		var below: int = int(floor((pos.y + 8.0) / 16.0))
		var on_rubble: bool = WorldManager.free_block_at_point(Vector2(pos.x, pos.y + 9.5)) >= 0
		if vel.y > 0.0 and (below >= ground_y or WorldManager.get_tile(cx, below) != 0 or on_rubble):
			if vel.y > 230.0 and int(d.bn) < 2:
				d.bn = int(d.bn) + 1
				vel.y = -vel.y * 0.38
				vel.x += _rng.randf_range(-80.0, 80.0)
				d.rv = _rng.randf_range(-7.0, 7.0) + vel.x * 0.02
				pos.y -= 1.0
				d.vel = vel
				d.pos = pos
				i -= 1
				continue
			if pc.x != INF and pos.distance_to(pc) < 22.0:
				# Would entomb the ball — kick the block off sideways instead
				vel.x = 120.0 * (1.0 if pos.x >= pc.x else -1.0)
				vel.y = -90.0
				d.vel = vel
				d.pos = pos
				i -= 1
				continue
			var tilt: float = absf(fposmod(d.rot, PI / 2.0) - PI / 4.0)
			var square_ish: bool = tilt > PI / 4.0 - 0.14  # within ~8 deg of upright
			if on_rubble or not square_ish:
				# Rest askew where it lies (snap the angle a little for repose)
				var rr: float = round(d.rot / (PI / 12.0)) * (PI / 12.0)
				WorldManager.free_blocks.append({"pos": Vector2(pos.x - 8.0, pos.y - 8.0),
					"id": d.id, "rotation": rad_to_deg(rr), "rubble": true})
				WorldManager.free_blocks_changed.emit()
				_debris.remove_at(i)
				i -= 1
				continue
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
