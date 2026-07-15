class_name ZombiesMap
extends RefCounted
## UNDEAD BUNKER — the big map. Four zones, side view, all enclosed:
##
##   [treeline]  DARK FOREST      THE BUNKER (spawn)      DEAD CITY   [alley]
##    pocket    trees/hut/hill    concrete monolith     3 brick towers  pocket
##   ==========================  ground  =================================
##      [grave pockets]   stair shaft*        stair shaft*   [sewer pocket]
##   ~~~~~~~~~~~~~~~~~~ CRYSTAL HOLLOW (cave: rail + PaP) ~~~~~~~~~~~~~~~~~
##
## * debris-gated. Zombies live in SEALED pockets (treeline, graves, bunker
## shafts, alley, sewer, cave crack) and enter through plank barriers only.
## Wall-buy guns are free-standing STATIONS placed well away from windows so
## buy prompts never collide with barricade rebuilding.

const W: int = 176
const H: int = 48

const GRASS: int = 5016
const DIRT: int = 5017
const BARK: int = 5018
const LEAF: int = 5019
const BRICK: int = 5020
const CONC: int = 5021
const GLASS: int = 5022
const ROAD: int = 5023
const ROCK: int = 5024
const CRYSTAL: int = 5025
const DEBRIS: int = 5006  # Amber hazard debris (buyable doors)

const SPAWN_TILE: Vector2 = Vector2(87, 36)

# Windows: rect = plank area (px), inside/outside = steering anchors (px).
const WINDOWS: Array = [
	{"rect": Rect2(96, 544, 16, 48), "inside": Vector2(136, 568), "outside": Vector2(72, 568), "horizontal": false},      # 0 forest fence
	{"rect": Rect2(336, 608, 32, 32), "inside": Vector2(352, 584), "outside": Vector2(352, 664), "horizontal": true},     # 1 grave A
	{"rect": Rect2(784, 608, 32, 32), "inside": Vector2(800, 584), "outside": Vector2(800, 664), "horizontal": true},     # 2 grave B
	{"rect": Rect2(992, 448, 16, 48), "inside": Vector2(1032, 472), "outside": Vector2(968, 472), "horizontal": false},   # 3 bunker west shaft
	{"rect": Rect2(1792, 448, 16, 48), "inside": Vector2(1768, 472), "outside": Vector2(1832, 472), "horizontal": false}, # 4 bunker east shaft
	{"rect": Rect2(2704, 544, 16, 48), "inside": Vector2(2672, 568), "outside": Vector2(2736, 568), "horizontal": false}, # 5 city east wall
	{"rect": Rect2(2480, 608, 32, 32), "inside": Vector2(2496, 584), "outside": Vector2(2496, 664), "horizontal": true},  # 6 sewer grate
	{"rect": Rect2(128, 672, 16, 48), "inside": Vector2(160, 696), "outside": Vector2(96, 696), "horizontal": false},     # 7 cave crack
]

const ZSPAWNS: Array = [
	[Vector2(56, 500), Vector2(72, 380), Vector2(48, 560)],          # 0 treeline pocket
	[Vector2(344, 664), Vector2(360, 672)],                          # 1 grave A pocket
	[Vector2(792, 664), Vector2(808, 672)],                          # 2 grave B pocket
	[Vector2(968, 468), Vector2(976, 500)],                          # 3 bunker west shaft pocket
	[Vector2(1824, 468), Vector2(1816, 500)],                        # 4 bunker east shaft pocket
	[Vector2(2740, 500), Vector2(2756, 380), Vector2(2748, 560)],    # 5 alley pocket
	[Vector2(2488, 664), Vector2(2504, 672)],                        # 6 sewer pocket
	[Vector2(56, 696), Vector2(80, 710), Vector2(40, 680)],          # 7 cave west pocket
]

# Wall-buy STATIONS (free-standing, >=100px from every window inside-anchor)
const WALL_BUYS: Array = [
	{"pos": Vector2(1322, 592), "weapon": "pistol", "cost": 250, "ammo": 90},   # bunker, left of spawn
	{"pos": Vector2(688, 588), "weapon": "smg", "cost": 1000, "ammo": 180},     # forest hut
	{"pos": Vector2(592, 534), "weapon": "scatter", "cost": 1200, "ammo": 60},  # forest hill
	{"pos": Vector2(1878, 592), "weapon": "blaster", "cost": 750, "ammo": 150}, # city street
	{"pos": Vector2(2320, 278), "weapon": "rifle", "cost": 1400, "ammo": 60},   # building B roof
	{"pos": Vector2(1408, 702), "weapon": "rail", "cost": 1600, "ammo": 30},    # cave
]

const BOX_POS: Vector2 = Vector2(2000, 486)   # Building A, 2nd floor
const BOX_COST: int = 950
const PAP_POS: Vector2 = Vector2(1600, 698)   # Deep in the cave
const PAP_COST: int = 5000

# Buyable doors: {tiles: Array[Vector2i], cost, prompt (px), label}
const DOORS: Array = [
	{"cost": 1000, "prompt": Vector2(976, 576), "label": "FOREST", "x0": 59, "x1": 62, "y0": 34, "y1": 37},
	{"cost": 1000, "prompt": Vector2(1832, 576), "label": "CITY", "x0": 112, "x1": 115, "y0": 34, "y1": 37},
	{"cost": 1250, "prompt": Vector2(440, 596), "label": "CAVE SHAFT", "x0": 26, "x1": 28, "y0": 38, "y1": 39},
	{"cost": 1250, "prompt": Vector2(2360, 596), "label": "CAVE SHAFT", "x0": 146, "x1": 148, "y0": 38, "y1": 39},
]

# Zone bands for banners/backdrop (px x ranges; cave = y > 648)
const ZONES: Array = [
	{"name": "THE DARK FOREST", "x0": 32, "x1": 944},
	{"name": "THE BUNKER", "x0": 944, "x1": 1856},
	{"name": "DEAD CITY", "x0": 1856, "x1": 2784},
]
const CAVE_NAME: String = "CRYSTAL HOLLOW"
const CAVE_Y: float = 648.0


static func build() -> void:
	WorldManager.init_empty_world(W, H)
	WorldManager.free_blocks.clear()
	WorldManager.polylines.clear()
	WorldManager.wedge_pairs.clear()
	WorldManager.curve_colliders.clear()
	WorldManager.lines.clear()
	WorldManager.block_groups.clear()
	WorldManager.gravity_zones.zones.clear()
	WorldManager.spawn_points.clear()

	# ── Outer shell (2 thick, indestructible) ──
	for x in range(W):
		_fg(x, 0, ROCK); _fg(x, 1, ROCK)
		_fg(x, H - 1, ROCK); _fg(x, H - 2, ROCK)
	for y in range(H):
		_fg(0, y, ROCK); _fg(1, y, ROCK)
		_fg(W - 2, y, ROCK); _fg(W - 1, y, ROCK)

	# ── Master ceiling band y=10 (forest canopy / concrete / smog slab) ──
	for x in range(2, W - 2):
		var cid: int = LEAF if x < 59 else (CONC if x <= 115 else ROCK)
		_fg(x, 10, cid)

	# ── Ground surface y=38 + underlayer y=39..40 ──
	for x in range(2, W - 2):
		var gid: int = GRASS if x < 59 else (CONC if x <= 115 else ROAD)
		_fg(x, 38, gid)
		_fg(x, 39, DIRT if x < 59 else (CONC if x <= 115 else ROCK))
		_fg(x, 40, ROCK)

	# ── Cave (CRYSTAL HOLLOW): open span y 41..45, rock floor y=46 area ──
	for x in range(2, W - 2):
		for y in range(41, 46):
			_fg(x, y, 0)
	for x in range(2, W - 2):
		_bg_fill(x, 41, 45, ROCK + 100)
	# crystals (floor clusters + ceiling stubs)
	for cx in [20, 60, 91, 130, 160]:
		_fg(cx, 45, CRYSTAL)
		_fg(cx + 1, 45, ROCK)
		_fg(cx - 3, 41, CRYSTAL)
	_fg(99, 45, CRYSTAL)
	_fg(101, 45, CRYSTAL)

	# ══════════ FOREST (x 2..58) ══════════
	# west fence (bark posts) sealing the treeline pocket, window cut y 34..36
	for y in range(11, 38):
		_fg(6, y, BARK)
	for y in range(34, 37):
		_fg(6, y, 0)
	# treeline pocket ambience (bg bark columns)
	for y in range(20, 38):
		_bg(3, y, BARK + 100)
		_bg(5, y, LEAF + 100)
	# forest wall vs bunker: x=59 (concrete monolith face)
	for y in range(11, 38):
		_fg(59, y, CONC)
	# Trees: trunks STOP above head height (y<=34) so the forest floor stays
	# walkable — root flares at ground level sell the arch. Canopies solid.
	for y in range(28, 35):
		_fg(14, y, BARK)
	_fg(13, 37, BARK)
	_fg(15, 37, BARK)
	for x in range(10, 19):
		for y in range(25, 28):
			_fg(x, y, LEAF)
	for y in range(24, 35):
		_fg(30, y, BARK)
	_fg(29, 37, BARK)
	_fg(31, 37, BARK)
	for x in range(24, 37):
		for y in range(20, 24):
			_fg(x, y, LEAF)
	for x in range(26, 35):
		for y in range(18, 20):
			_fg(x, y, LEAF)
	for y in range(30, 35):
		_fg(46, y, BARK)
	_fg(45, 37, BARK)
	_fg(47, 37, BARK)
	for x in range(42, 51):
		for y in range(27, 30):
			_fg(x, y, LEAF)
	# bg foliage depth behind the trees
	for x in range(8, 56):
		if (x % 7) < 3:
			_bg(x, 30 + (x % 5), LEAF + 100)
	# forest hut (SMG): bark walls, leaf roof, door gap east
	for y in range(32, 38):
		_fg(40, y, BARK)
		_fg(44, y, BARK)
	for y in range(32, 35):
		_fg(44, y, BARK)
	for y in range(35, 38):
		_fg(44, y, 0)  # hut door
	for x in range(39, 46):
		_fg(x, 31, LEAF)
	for x in range(41, 44):
		_bg(x, 34, BARK + 100)
		_bg(x, 36, BARK + 100)
	# forest hill (SCATTER on top): stacked grass mound
	for x in range(33, 42):
		_fg(x, 37, DIRT)
	for x in range(34, 41):
		_fg(x, 36, DIRT)
	for x in range(35, 40):
		_fg(x, 35, GRASS)
	for x in range(36, 39):
		_fg(x, 34, GRASS)
	# graves: headstones + ground cut (windows 1 & 2) + sealed pockets below
	_fg(20, 37, CONC)
	_fg(48, 37, CONC)
	for gx in [21, 22, 49, 50]:
		_fg(gx, 38, 0)
		_fg(gx, 39, 0)
	for gp in [[19, 24], [47, 52]]:
		# sealed pocket box: side walls + rock floor, interior carved open
		for y in range(40, 44):
			_fg(gp[0], y, ROCK)
			_fg(gp[1], y, ROCK)
		for x in range(gp[0] + 1, gp[1]):
			_fg(x, 43, ROCK)
			_fg(x, 40, 0)
			_fg(x, 41, 0)
			_fg(x, 42, 0)
			_bg(x, 41, ROCK + 100)

	# ══════════ BUNKER (x 59..115) ══════════
	# monolith mass above the interior
	for x in range(60, 116):
		for y in range(11, 27):
			_fg(x, y, CONC)
	# interior box: roof y=26 (already CONC), walls x=62/x=112
	for y in range(27, 38):
		_fg(62, y, CONC)
		_fg(112, y, CONC)
	# clear interior
	for x in range(63, 112):
		for y in range(27, 38):
			_fg(x, y, 0)
	# full interior back-wall (auto-darkened by the renderer = concrete depth)
	for x in range(63, 112):
		for y in range(27, 38):
			_bg(x, y, CONC + 100)
		if (x % 9) == 4:
			_bg(x, 29, GLASS + 100)  # wall monitors

	# west/east zombie shafts (pockets) + their windows in the bunker walls.
	# The floor under each pocket (y32..33) MUST be solid — otherwise the
	# pocket leaks into the door tunnel and zombies skip the barrier.
	for p in [[60, 61], [113, 114]]:
		for x2 in p:
			for y in range(27, 32):
				_fg(x2, y, 0)
			_fg(x2, 32, CONC)
			_fg(x2, 33, CONC)
			_bg(x2, 29, ROCK + 100)
	for y in range(28, 31):
		_fg(62, y, 0)   # window 3 opening
		_fg(112, y, 0)  # window 4 opening
	# mezzanines + 48px steps
	for x in range(66, 79):
		_fg(x, 32, CONC)
	for x in range(96, 109):
		_fg(x, 32, CONC)
	for sx in [80, 81]:
		_fg(sx, 35, CONC)
	for sx in [93, 94]:
		_fg(sx, 35, CONC)
	# doors: forest tunnel (x59..62) + city tunnel (x112..115), debris-filled
	for d in [DOORS[0], DOORS[1]]:
		for x in range(d.x0, d.x1 + 1):
			for y in range(d.y0, d.y1 + 1):
				_fg(x, y, DEBRIS)
	# city wall face x=115
	for y in range(11, 34):
		_fg(115, y, CONC)

	# ══════════ CITY (x 116..173) ══════════
	# east alley pocket wall x=169 + window cut
	for y in range(11, 38):
		_fg(169, y, BRICK)
	for y in range(34, 37):
		_fg(169, y, 0)
	for y in range(16, 38):
		_bg(171, y, BRICK + 100)
		_bg(173, y, GLASS + 100)
	# Building A (x 118..132): 2 floors, box on 2F
	for y in range(24, 38):
		_fg(118, y, BRICK)
		_fg(132, y, BRICK)
	for x in range(118, 133):
		_fg(x, 24, CONC)
	for x in range(118, 130):
		_fg(x, 31, CONC)
	for sx in [129, 130]:
		_fg(sx, 35, CONC)
	for sx in [127, 128]:
		_fg(sx, 32, CONC)
	for y in range(35, 38):
		_fg(118, y, 0)  # street door
	for x in range(119, 132):
		for y in range(25, 31):
			_bg(x, y, BRICK + 100)
			if (x % 3) == 1 and (y % 3) == 1:
				_bg(x, y, GLASS + 100)
		for y in range(32, 38):
			_bg(x, y, BRICK + 100)
			if (x % 3) == 2 and y == 34:
				_bg(x, y, GLASS + 100)
	# Building B (x 138..152): tall, rifle on the roof
	for y in range(18, 38):
		_fg(138, y, BRICK)
		_fg(152, y, BRICK)
	for x in range(138, 153):
		_fg(x, 18, CONC)
	for x in range(141, 153):
		_fg(x, 25, CONC)
	for x in range(138, 150):
		_fg(x, 31, CONC)
	for sx in [150, 151]:
		_fg(sx, 35, CONC)
	for sx in [148, 149]:
		_fg(sx, 32, CONC)
	for sx in [139, 140]:
		_fg(sx, 28, CONC)
	for sx in [141, 142]:
		_fg(sx, 22, CONC)
	for y in range(35, 38):
		_fg(152, y, 0)  # street door (east side)
	for x in range(139, 152):
		for y in range(19, 25):
			_bg(x, y, BRICK + 100)
			if (x % 3) == 0 and (y % 3) == 2:
				_bg(x, y, GLASS + 100)
		for y in range(26, 31):
			_bg(x, y, BRICK + 100)
			if (x % 4) == 1 and y == 28:
				_bg(x, y, GLASS + 100)
		for y in range(32, 38):
			_bg(x, y, BRICK + 100)
	# Building C (x 158..168): low, roof walkable
	for y in range(30, 38):
		_fg(158, y, BRICK)
		_fg(168, y, BRICK)
	for x in range(158, 169):
		_fg(x, 30, CONC)
	for y in range(35, 38):
		_fg(158, y, 0)
	for x in range(159, 168):
		for y in range(31, 38):
			_bg(x, y, BRICK + 100)
			if (x % 3) == 0 and y == 33:
				_bg(x, y, GLASS + 100)
	# Rooftop chain: fire escape up Building A's west face (48px zigzag from
	# the street), then A roof -> gap step -> B roof (rifle). C roof is a
	# one-way drop from B/A. Alley dumpster for cover.
	_fg(117, 35, CONC)
	_fg(116, 32, CONC)
	_fg(117, 29, CONC)
	_fg(116, 26, CONC)
	for sx in [134, 135]:
		_fg(sx, 21, CONC)
	for sx in [156, 157]:
		_fg(sx, 34, CONC)
	# sewer grate (window 6) + pocket
	for gx in [155, 156]:
		_fg(gx, 38, 0)
		_fg(gx, 39, 0)
	for y in range(40, 44):
		_fg(153, y, ROCK)
		_fg(158, y, ROCK)
	for x in range(154, 158):
		_fg(x, 43, ROCK)
		_fg(x, 40, 0)
		_fg(x, 41, 0)
		_fg(x, 42, 0)
		_bg(x, 41, ROCK + 100)

	# ══════════ CAVE ACCESS ══════════
	# stair shafts (debris-gated): forest x26..28, city x146..148
	for d in [DOORS[2], DOORS[3]]:
		for x in range(d.x0, d.x1 + 1):
			for y in range(d.y0, d.y1 + 1):
				_fg(x, y, DEBRIS)
	# rock stairs down into the hollow (48px-safe hop chain)
	_fg(25, 41, ROCK)
	_fg(24, 43, ROCK)
	_fg(149, 41, ROCK)
	_fg(150, 43, ROCK)
	# cave west crack pocket (window 7): wall x=8 with crack y42..44
	for y in range(41, 46):
		_fg(8, y, ROCK)
	for y in range(42, 45):
		_fg(8, y, 0)
	for x in range(3, 8):
		_bg(x, 43, CRYSTAL + 100)

	WorldManager.spawn_points.append(SPAWN_TILE)
	WorldManager.free_blocks_changed.emit()
	WorldManager.polylines_changed.emit()
	WorldManager.tile_changed.emit(0, 0, 0)


static func _fg(x: int, y: int, id: int) -> void:
	if x >= 0 and x < W and y >= 0 and y < H:
		WorldManager.fg_tiles[y][x] = id


static func _bg(x: int, y: int, id: int) -> void:
	if x >= 0 and x < W and y >= 0 and y < H:
		WorldManager.bg_tiles[y][x] = id


static func _bg_fill(x: int, y0: int, y1: int, id: int) -> void:
	for y in range(y0, y1 + 1):
		_bg(x, y, id)
