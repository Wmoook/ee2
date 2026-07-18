extends Node

const TILE_SIZE: int = 16
var is_edit_mode: bool = false
var selected_block_id: int = 5000  # Start with block_1
var _custom_block_textures: Dictionary = {}  # Custom block ID -> Texture2D
var selected_block: int = 9
var selected_palette_index: int = 0
var selected_category: int = 0
var state_channels: Dictionary = {}
var player_name: String = "Player"
var player_smiley_id: int = -1  # -1 = DREAMER ball; 0..187 EE smileys; 188..375 gold
var net_freeze: bool = false    # online 3-2-1-GO: input locked until GO

func save_profile() -> void:
	var f: FileAccess = FileAccess.open("user://profile.json", FileAccess.WRITE)
	if f:
		f.store_string(JSON.stringify({"name": player_name, "smiley_id": player_smiley_id}))
		f.close()

## Face crop inside the HD smiley sheet: every 52px cell holds a 32px face
## with 10px transparent padding. id 0..187 classic, 188..375 gold.
func smiley_face_region(id: int) -> Rect2:
	var sid: int = clampi(id, 0, 375)
	var row_y: float = 52.0 if sid >= 188 else 0.0
	return Rect2(float(sid % 188) * 52.0 + 10.0, row_y + 10.0, 32.0, 32.0)

func load_profile() -> void:
	if not FileAccess.file_exists("user://profile.json"):
		return
	var f: FileAccess = FileAccess.open("user://profile.json", FileAccess.READ)
	if f == null:
		return
	var data: Variant = JSON.parse_string(f.get_as_text())
	f.close()
	if data is Dictionary:
		player_name = str(data.get("name", "Player"))
		player_smiley_id = clampi(int(data.get("smiley_id", -1)), -1, 375)
var _block_db: Dictionary = {}
var _solid_set: Dictionary = {}
var _non_solid_fg: Dictionary = {}
var _slope_textures: Dictionary = {}   # slope_id (int) -> ImageTexture
var _slope_set: Dictionary = {}        # slope_id -> true  (quick membership test)
const PHYSICS_BOOST: float = 16.0
const SlopeGenerator = preload("res://scripts/world/slope_generator.gd")

# EE uses 4 main tabs: Blocks, Action, Decorative, Backgrounds
# All sub-themes merged into these 4 tabs like real EE
var BLOCK_CATEGORIES: Array = [
	{"name": "Blocks", "ids": [
		5000, 5001, 5002, 5003, 5004, 5005, 5006, 5007, 5008, 5009, 5010,
		5011, 5012, 5013, 5014, 5015,
		5016, 5017, 5018, 5019, 5020, 5021, 5022, 5023, 5024, 5025,
	]},
	{"name": "Candy", "color": Color(1.0, 0.5, 0.7), "ids": [5030, 5031, 5032, 5033, 5034, 5035]},
	{"name": "Neon", "color": Color(0.25, 0.9, 1.0), "ids": [5036, 5037, 5038, 5039, 5040, 5041]},
	{"name": "Castle", "color": Color(0.7, 0.72, 0.78), "ids": [5042, 5043, 5044, 5045, 5046, 5047]},
	{"name": "Frost", "color": Color(0.6, 0.85, 1.0), "ids": [5048, 5049, 5050, 5051, 5052]},
	{"name": "Magma", "color": Color(1.0, 0.45, 0.15), "ids": [5053, 5054, 5055, 5056, 5057]},
	{"name": "Jungle", "color": Color(0.35, 0.8, 0.3), "ids": [6000, 6001, 6002, 6003, 6004, 6005, 6006, 6007]},
	{"name": "Ocean", "color": Color(0.2, 0.65, 0.95), "ids": [6008, 6009, 6010, 6011, 6012, 6013, 6014, 6015]},
	{"name": "Space", "color": Color(0.6, 0.5, 1.0), "ids": [6016, 6017, 6018, 6019, 6020, 6021, 6022, 6023]},
	{"name": "Factory", "color": Color(0.85, 0.7, 0.3), "ids": [6024, 6025, 6026, 6027, 6028, 6029, 6030, 6031]},
	{"name": "Desert", "color": Color(0.95, 0.75, 0.4), "ids": [6032, 6033, 6034, 6035, 6036, 6037, 6038, 6039]},
	{"name": "Dream", "color": Color(0.9, 0.75, 0.95), "ids": [6040, 6041, 6042, 6043, 6044, 6045, 6046, 6047]},
	{"name": "Arcade", "color": Color(1.0, 0.85, 0.2), "ids": [6048, 6049, 6050, 6051, 6052, 6053, 6054, 6055]},
	{"name": "Gems", "color": Color(0.5, 0.95, 0.85), "ids": [6056, 6057, 6058, 6059, 6060, 6061, 6062, 6063]},
	{"name": "Spooky", "color": Color(0.85, 0.45, 0.1), "ids": [6064, 6065, 6066, 6067, 6068, 6069, 6070, 6071]},
	{"name": "Curves", "color": Color(0.95, 0.4, 0.85), "ids": [
		5058, 5059, 5060, 5061, 5062, 5063, 5064, 5065, 5066, 5067,
		6080, 6081, 6082, 6083, 6084, 6085, 6086, 6087, 6088, 6089]},
	{"name": "Slopes", "ids": [
		2000, 2001, 2002, 2003,
		2004, 2005, 2006, 2007,
		2008, 2009, 2010, 2011,
		2012, 2013, 2014, 2015,
		2016, 2017, 2018, 2019,
		2020, 2021, 2022, 2023,
		2024, 2025, 2026, 2027,
		2028, 2029, 2030, 2031,
		2032, 2033, 2034, 2035,
		2036, 2037, 2038, 2039,
		2040, 2041, 2042, 2043, 2044, 2045, 2046, 2047,
		2048, 2049, 2050, 2051, 2052, 2053, 2054, 2055,
		2056, 2057, 2058, 2059, 2060, 2061, 2062, 2063,
		2064, 2065, 2066, 2067, 2068, 2069, 2070, 2071,
		2072, 2073, 2074, 2075, 2076, 2077, 2078, 2079,
		2080, 2081, 2082, 2083, 2084, 2085, 2086, 2087,
		2088, 2089, 2090, 2091, 2092, 2093, 2094, 2095,
		2096, 2097, 2098, 2099, 2100, 2101, 2102, 2103,
		2104, 2105, 2106, 2107, 2108, 2109, 2110, 2111,
		2112, 2113, 2114, 2115, 2116, 2117, 2118, 2119,
	]},
	{"name": "Action", "ids": [
		1, 2, 3, 4, 411, 412, 413, 414, 459, 460, 1518, 1519,
		114, 115, 116, 117,
		6, 7, 8, 408, 409, 410,
		23, 24, 25, 26, 27, 28,
		1005, 1006, 1007, 1008, 1009, 1010,
		100, 101, 165, 43, 214, 213,
		113, 185, 184, 467, 1079, 1080,
		200, 201, 156, 157, 1011, 1012, 206, 207, 1027, 1028,
		361, 368, 119, 416, 369,
		5, 255, 360, 121, 466,
		114, 115, 116, 117, 118, 120, 98, 99, 424,
		417, 418, 419, 420, 421, 422, 423, 453, 461, 1064,
		242, 374, 381,
		77, 83,
		375, 376, 377, 378, 379, 380, 438, 439,
	]},
	{"name": "Decorative", "ids": [
		218, 219, 220, 221, 222,
		227, 431, 432, 433, 434,
		228, 229, 230, 231, 232,
		224, 225, 226,
		261, 154, 271, 272, 435, 436,
		276, 277, 278, 279, 280, 281, 282, 283, 284,
		285, 286, 287, 288, 289, 290, 291, 292, 293, 294, 295, 296, 297, 298,
		311, 312, 313, 314, 315, 316, 317, 318,
		319, 320, 321, 322, 323, 324,
		325, 326, 327, 328, 329, 330, 437, 440, 273, 275,
		150, 151, 152, 153,
		332, 333, 334, 335, 428, 429, 430, 331,
		336, 425, 426, 427,
		199, 357, 358, 359,
		362, 363, 364, 365, 366, 367,
		382, 383, 384,
		386, 387, 388, 389,
		398, 399, 400, 401, 402, 403, 404,
		405, 406, 407, 415,
		441, 442, 443, 444, 445,
		446, 447, 448, 449, 450, 451, 452,
		454, 455, 456, 457, 458,
		462, 463, 464, 465,
		468, 469, 470, 471,
		473, 474, 475, 476, 477,
		233, 234, 235, 236, 237, 238, 239, 240,
		241, 337, 397, 1000, 385,
		244, 245, 246, 247, 248,
		249, 250, 251, 252, 253, 254,
		256, 257, 258, 259, 260,
		300, 307, 308, 309, 310,
		338, 339, 340,
		343, 344, 345, 346, 347, 348, 349, 350, 351,
		352, 353, 354, 355, 356,
		370, 371, 372, 373,
		390, 391, 392, 393, 394, 395, 396,
	]},
	{"name": "Backgrounds", "ids": [
		5100, 5101, 5102, 5103, 5104,
		715, 500, 645, 503, 644, 504, 505, 506, 501, 502,
		646, 647, 509, 511, 507, 512, 510, 508, 648,
		513, 514, 515, 516, 649, 517, 518, 519, 650,
		520, 521, 522, 523, 651, 524, 525, 526, 652,
		527, 528, 529, 530, 531, 676, 677,
		533, 534, 536, 537, 538,
		539, 540, 541, 542, 543, 544,
		545, 546, 547, 548, 549, 550, 551, 552, 553,
		554, 555, 556, 557, 559, 560, 561, 562, 563, 564, 565, 566, 567,
		568, 569, 570, 571, 572, 573, 574, 575, 576, 577, 578, 579, 580, 581, 582, 583, 584,
		585, 586, 587, 588, 589, 590, 591, 592, 593,
		599, 600, 601, 602, 603, 604, 605, 606, 607,
		608, 609, 610, 611, 612, 613, 614, 615, 616,
		617, 618, 619, 620, 621, 622, 623, 624, 625, 626, 627, 628, 629, 630,
		637, 638, 639, 640, 641, 642, 643,
		644, 645, 646, 647, 648, 649, 650, 651, 652, 653, 654,
		655, 656, 657, 658, 659, 660, 661, 662, 663, 664, 665, 666,
		667, 668, 669, 670, 671, 672, 673, 674, 675,
		678, 679, 680, 681, 682, 683, 684, 685, 686, 687,
		688, 689, 690, 691, 692, 693, 694, 695, 696, 697, 698, 699, 700, 701,
		702, 703, 704, 705, 706, 707, 708, 709, 710, 711,
	]},
]

# Flat palette of all block IDs (built from categories)
var BLOCK_PALETTE: Array = []

func get_category_color(i: int) -> Color:
	if i >= 0 and i < BLOCK_CATEGORIES.size():
		return BLOCK_CATEGORIES[i].get("color", Color(0.45, 0.45, 0.7))
	return Color(0.45, 0.45, 0.7)

# Display names for every custom block (palette tooltips + info bar).
var custom_block_names: Dictionary = {
	9: "World Border",
	5000: "Dream Slab", 5001: "Dream Panel", 5002: "Dream Tile", 5003: "Dream Plate", 5004: "Dream Core",
	5005: "Arena Plate", 5006: "Hazard Core", 5007: "Arena Rail", 5008: "Arena Vent", 5009: "Arena Glass", 5010: "Plasma Spike",
	5011: "Obsidian Wall", 5012: "Ribbed Floor", 5013: "Rune Core", 5014: "Void Fill", 5015: "Warden Energy",
	5016: "Wild Grass", 5017: "Packed Dirt", 5018: "Old Bark", 5019: "Canopy Leaf", 5020: "City Brick",
	5021: "Concrete", 5022: "Wall Glass", 5023: "Asphalt", 5024: "Cave Rock", 5025: "Cave Crystal",
	5030: "Bubblegum", 5031: "Candy Cane", 5032: "Chocolate", 5033: "Mint Swirl", 5034: "Berry Jelly", 5035: "Golden Wafer",
	5036: "Tron Panel", 5037: "Circuit Magenta", 5038: "Hexcore", 5039: "Amber Scan", 5040: "Violet Pulse", 5041: "Grid Strobe",
	5042: "Stone Brick", 5043: "Cobblestone", 5044: "Mossy Brick", 5045: "Cracked Keep", 5046: "Marble", 5047: "Royal Inlay",
	5048: "Ice Glass", 5049: "Packed Snow", 5050: "Frost Brick", 5051: "Glacier", 5052: "Aurora Crystal",
	5053: "Basalt Columns", 5054: "Lava Cracks", 5055: "Ember Rock", 5056: "Obsidian", 5057: "Magma Flow",
	5058: "Rainbow Ribbon", 5059: "Neon Tube Cyan", 5060: "Neon Tube Pink", 5061: "Gold Rail", 5062: "Steel Pipe",
	5063: "Candy Stripe", 5064: "Lava Ribbon", 5065: "Ice Ribbon", 5066: "Jungle Vine", 5067: "Starlight",
	6000: "Canopy Leaf", 6001: "Mossy Log", 6002: "Bamboo", 6003: "Temple Stone", 6004: "Vine Wall",
	6005: "Bloom", 6006: "Root Tangle", 6007: "Glowshroom",
	6008: "Deep Water", 6009: "Coral Pink", 6010: "Coral Cyan", 6011: "Golden Sand", 6012: "Shell Tile",
	6013: "Kelp Weave", 6014: "Bubble Stone", 6015: "Treasure Hoard",
	6016: "Starfield", 6017: "Nebula", 6018: "Asteroid", 6019: "Hull Plate", 6020: "Portlight",
	6021: "Solar Cell", 6022: "Hazard Stripe", 6023: "Reactor Core",
	6024: "Steel Plate", 6025: "Rust Plate", 6026: "Vent Grate", 6027: "Gearbox", 6028: "Pipe Grid",
	6029: "Caution Tape", 6030: "Server Rack", 6031: "Conveyor",
	6032: "Sandstone", 6033: "Glyph Stone", 6034: "Pharaoh Gold", 6035: "Dune Sand", 6036: "Cracked Clay",
	6037: "Pyramid Brick", 6038: "Oasis Tile", 6039: "Scarab Lapis",
	6040: "Cloud Puff", 6041: "Mint Whip", 6042: "Lavender Haze", 6043: "Peach Sky", 6044: "Star Cream",
	6045: "Cotton Rose", 6046: "Moon Milk", 6047: "Aurora Silk",
	6048: "Pixel Brick", 6049: "Pixel Grass", 6050: "Bonus Star", 6051: "Checker", 6052: "Pipe Green",
	6053: "Sky Block", 6054: "Coin Tile", 6055: "Glitch",
	6056: "Ruby", 6057: "Emerald", 6058: "Sapphire", 6059: "Amethyst", 6060: "Topaz",
	6061: "Diamond", 6062: "Dark Gem", 6063: "Opal",
	6064: "Pumpkin", 6065: "Bone Pile", 6066: "Cobweb Stone", 6067: "Witchbrick", 6068: "Tombstone",
	6069: "Ghostglow", 6070: "Blood Moon", 6071: "Coffin Wood",
	6080: "Voltage", 6081: "Rose Vine", 6082: "Toxic Flow", 6083: "River Run", 6084: "Chrome",
	6085: "Ember Rope", 6086: "Cloudstream", 6087: "Royal Ribbon", 6088: "Void Trail", 6089: "Sakura Stream",
}

func custom_block_name(id: int) -> String:
	if custom_block_names.has(id):
		return custom_block_names[id]
	if custom_block_names.has(id - 100):
		return custom_block_names[id - 100] + " BG"
	if custom_block_names.has(id - 1000):
		return custom_block_names[id - 1000] + " BG"
	return ""

# Action block classification
var _action_arrows: Dictionary = {}
var _action_dots: Dictionary = {}
var _action_boosts: Dictionary = {}
var _hazard_set: Dictionary = {}
var _door_set: Dictionary = {}
var _key_set: Dictionary = {}
var _coin_set: Dictionary = {}
var _effect_set: Dictionary = {}
var _music_set: Dictionary = {}
var _portal_set: Dictionary = {}
var _switch_set: Dictionary = {}

var camera_offset: Vector2 = Vector2.ZERO  # Manual camera pan offset
var trails_enabled: bool = true  # Fire trail toggle
var rotation_enabled: bool = true  # Ball roll visual toggle (HUD "Rotate" button)
var battle_mode: bool = false  # 1v1 bot arena active — blocks world saves + editing
var battle_guns_enabled: bool = true  # OFF = pure melee duel (dash + parry only)
var battle_bot_count: int = 1  # Enemy bots in the arena: 1 = 1v1 ... 3 = 1v1v1v1 (FFA)
var boss_fight: bool = false  # BOSS FIGHT mode (battle_mode is also set — same gating)
var survivors_mode: bool = false  # DOT SURVIVORS mode (battle_mode also set — same gating)
var zombies_mode: bool = false  # UNDEAD BUNKER round-based zombies (battle_mode also set)
var cam_shake: float = 0.0  # Screen shake impulse (added by combat, decays in player controller)
var player_stunned: bool = false  # Set by battle mode: parried players lose control briefly

signal edit_mode_changed(enabled: bool)
signal block_selected(block_id: int)
signal state_channel_changed(channel_id: int, value: int)

func _ready() -> void:
	load_profile()
	# Web has NO system font fallback — every symbol/emoji beyond the built-in
	# font (hearts, skulls, arrows, planets, the reconnect spinner) rendered as
	# a hex box (e.g. "27F3"). Bundle Noto symbol + emoji fonts as global
	# fallbacks so every platform shows the same glyphs.
	var _fbf: Font = ThemeDB.fallback_font
	if _fbf != null:
		var _sym: Font = load("res://assets/fonts/NotoSansSymbols2-Regular.ttf")
		var _emo: Font = load("res://assets/fonts/NotoEmoji-Regular.ttf")
		var _fbs = _fbf.get("fallbacks")
		if _fbs != null and _sym != null and _emo != null:
			var _list: Array = _fbs.duplicate()
			_list.append(_sym)
			_list.append(_emo)
			_fbf.set("fallbacks", _list)
	# Uncapped FPS + no vsync so render framerate is independent of physics (100Hz).
	# Frame interpolation in player_controller makes motion smooth at any FPS.
	# On the web, browsers own the frame loop — leave vsync/fps defaults alone.
	if not OS.has_feature("web"):
		Engine.max_fps = 0
		DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	if "--cap-fps" in OS.get_cmdline_user_args():
		Engine.max_fps = 240  # test harnesses: pre-optimization frame pacing
	# Load items_map.json
	_load_items_map()
	# Register custom blocks (40x40 textures scaled to 16x16)
	_register_custom_blocks()
	# Generate slope textures and register slope blocks
	_generate_slopes()
	# Build flat palette
	_build_palette()
	# Build action/hazard/door/key lookups and non-solid set
	_build_lookups()

func _register_custom_blocks() -> void:
	var custom_blocks: Array = [
		{"id": 5000, "path": "res://assets/sprites/NEW_BLOCK_SPRITE/block_1.png", "path16": "res://assets/sprites/NEW_BLOCK_SPRITE/block_1_16.png"},
		{"id": 5001, "path": "res://assets/sprites/NEW_BLOCK_SPRITE/block_2.png", "path16": "res://assets/sprites/NEW_BLOCK_SPRITE/block_2_16.png"},
		{"id": 5002, "path": "res://assets/sprites/NEW_BLOCK_SPRITE/block_3.png", "path16": "res://assets/sprites/NEW_BLOCK_SPRITE/block_3_16.png"},
		{"id": 5003, "path": "res://assets/sprites/NEW_BLOCK_SPRITE/block_4.png", "path16": "res://assets/sprites/NEW_BLOCK_SPRITE/block_4_16.png"},
		{"id": 5004, "path": "res://assets/sprites/NEW_BLOCK_SPRITE/block_5.png", "path16": "res://assets/sprites/NEW_BLOCK_SPRITE/block_5_16.png"},
		{"id": 5005, "path": "res://assets/sprites/NEW_BLOCK_SPRITE/block_6.png", "path16": "res://assets/sprites/NEW_BLOCK_SPRITE/block_6_16.png"},
		{"id": 5006, "path": "res://assets/sprites/NEW_BLOCK_SPRITE/block_7.png", "path16": "res://assets/sprites/NEW_BLOCK_SPRITE/block_7_16.png"},
		{"id": 5007, "path": "res://assets/sprites/NEW_BLOCK_SPRITE/block_8.png", "path16": "res://assets/sprites/NEW_BLOCK_SPRITE/block_8_16.png"},
		{"id": 5008, "path": "res://assets/sprites/NEW_BLOCK_SPRITE/block_9.png", "path16": "res://assets/sprites/NEW_BLOCK_SPRITE/block_9_16.png"},
		{"id": 5009, "path": "res://assets/sprites/NEW_BLOCK_SPRITE/block_10.png", "path16": "res://assets/sprites/NEW_BLOCK_SPRITE/block_10_16.png"},
		{"id": 5010, "path": "res://assets/sprites/NEW_BLOCK_SPRITE/block_11.png", "path16": "res://assets/sprites/NEW_BLOCK_SPRITE/block_11_16.png"},
		{"id": 5011, "path": "res://assets/sprites/NEW_BLOCK_SPRITE/block_12.png", "path16": "res://assets/sprites/NEW_BLOCK_SPRITE/block_12_16.png"},
		{"id": 5012, "path": "res://assets/sprites/NEW_BLOCK_SPRITE/block_13.png", "path16": "res://assets/sprites/NEW_BLOCK_SPRITE/block_13_16.png"},
		{"id": 5013, "path": "res://assets/sprites/NEW_BLOCK_SPRITE/block_14.png", "path16": "res://assets/sprites/NEW_BLOCK_SPRITE/block_14_16.png"},
		{"id": 5014, "path": "res://assets/sprites/NEW_BLOCK_SPRITE/block_15.png", "path16": "res://assets/sprites/NEW_BLOCK_SPRITE/block_15_16.png"},
		{"id": 5015, "path": "res://assets/sprites/NEW_BLOCK_SPRITE/block_16.png", "path16": "res://assets/sprites/NEW_BLOCK_SPRITE/block_16_16.png"},
		{"id": 5016, "path": "res://assets/sprites/NEW_BLOCK_SPRITE/block_17.png", "path16": "res://assets/sprites/NEW_BLOCK_SPRITE/block_17_16.png"},
		{"id": 5017, "path": "res://assets/sprites/NEW_BLOCK_SPRITE/block_18.png", "path16": "res://assets/sprites/NEW_BLOCK_SPRITE/block_18_16.png"},
		{"id": 5018, "path": "res://assets/sprites/NEW_BLOCK_SPRITE/block_19.png", "path16": "res://assets/sprites/NEW_BLOCK_SPRITE/block_19_16.png"},
		{"id": 5019, "path": "res://assets/sprites/NEW_BLOCK_SPRITE/block_20.png", "path16": "res://assets/sprites/NEW_BLOCK_SPRITE/block_20_16.png"},
		{"id": 5020, "path": "res://assets/sprites/NEW_BLOCK_SPRITE/block_21.png", "path16": "res://assets/sprites/NEW_BLOCK_SPRITE/block_21_16.png"},
		{"id": 5021, "path": "res://assets/sprites/NEW_BLOCK_SPRITE/block_22.png", "path16": "res://assets/sprites/NEW_BLOCK_SPRITE/block_22_16.png"},
		{"id": 5022, "path": "res://assets/sprites/NEW_BLOCK_SPRITE/block_23.png", "path16": "res://assets/sprites/NEW_BLOCK_SPRITE/block_23_16.png"},
		{"id": 5023, "path": "res://assets/sprites/NEW_BLOCK_SPRITE/block_24.png", "path16": "res://assets/sprites/NEW_BLOCK_SPRITE/block_24_16.png"},
		{"id": 5024, "path": "res://assets/sprites/NEW_BLOCK_SPRITE/block_25.png", "path16": "res://assets/sprites/NEW_BLOCK_SPRITE/block_25_16.png"},
		{"id": 5025, "path": "res://assets/sprites/NEW_BLOCK_SPRITE/block_26.png", "path16": "res://assets/sprites/NEW_BLOCK_SPRITE/block_26_16.png"},
	]
	# Block packs (Candy/Neon/Castle/Frost/Magma) + the Curves tab ribbons:
	# ids 5030..5067 map to block_31.png..block_68.png (id - 4999)
	for pk_id in range(5030, 5068):
		var pk_n: int = pk_id - 4999
		custom_blocks.append({"id": pk_id,
			"path": "res://assets/sprites/NEW_BLOCK_SPRITE/block_%d.png" % pk_n,
			"path16": "res://assets/sprites/NEW_BLOCK_SPRITE/block_%d_16.png" % pk_n})
	# MEGA PACKS (Jungle/Ocean/Space/Factory/Desert/Dream/Arcade/Gems/Spooky
	# 6000-6071) + CURVES II ribbons (6080-6089). The classic +100 BG scheme
	# is full past id 5099, so these BG twins live at id + 1000 (7000s).
	var pack2_ids: Array = []
	for mp in range(6000, 6072):
		pack2_ids.append(mp)
	for mp2 in range(6080, 6090):
		pack2_ids.append(mp2)
	for mp_id in pack2_ids:
		custom_blocks.append({"id": mp_id,
			"path": "res://assets/sprites/BLOCK_PACKS/%d.png" % mp_id,
			"path16": "res://assets/sprites/BLOCK_PACKS/%d_16.png" % mp_id,
			"bg_off": 1000})
	# The world BORDER (id 9) wears the standard block art — identical to the
	# normal blocks in the game instead of the legacy EE gray brick.
	custom_blocks.append({"id": 9,
		"path": "res://assets/sprites/NEW_BLOCK_SPRITE/block_1.png",
		"path16": "res://assets/sprites/NEW_BLOCK_SPRITE/block_1_16.png",
		"no_bg": true})  # id 9+100=109 is a REAL EE block — no BG twin here
	for cb in custom_blocks:
		var tex: Texture2D = load(cb.path) as Texture2D
		var tex16: Texture2D = load(cb.path16) as Texture2D
		if tex:
			_custom_block_textures[cb.id] = tex  # 40x40 for HUD preview
			if tex16:
				_custom_block_textures[cb.id * -1] = tex16  # 16x16 for grid (negative key)
			_block_db[cb.id] = {"atlas": "custom", "layer": "foreground", "artoffset": 0, "custom_tex": true}
			_solid_set[cb.id] = true
			if cb.get("no_bg", false):
				continue
			# Register BG version — same texture, background layer. Classic
			# customs use +100; the 6000-range mega packs use +1000.
			var bg_id: int = cb.id + int(cb.get("bg_off", 100))
			_custom_block_textures[bg_id] = tex
			if tex16:
				_custom_block_textures[bg_id * -1] = tex16
			_block_db[bg_id] = {"atlas": "custom", "layer": "background", "artoffset": 0, "custom_tex": true}

func get_custom_block_texture_16(id: int) -> Texture2D:
	return _custom_block_textures.get(id * -1, _custom_block_textures.get(id, null))

func _load_items_map() -> void:
	var path: String = "res://data/items_map.json"
	if not FileAccess.file_exists(path):
		# Fallback: hardcode basic blocks
		for i in range(9, 22):
			_block_db[i] = {"atlas": "blocks", "layer": "foreground", "artoffset": i}
			_solid_set[i] = true
		return

	var file = FileAccess.open(path, FileAccess.READ)
	if not file:
		return
	var json_text: String = file.get_as_text()
	file.close()

	var parsed = JSON.parse_string(json_text)
	if not parsed is Dictionary:
		return

	var data: Dictionary = parsed as Dictionary
	for key in data.keys():
		var id_int: int = int(key)
		var info: Dictionary = data[key]
		_block_db[id_int] = info
		# Mark foreground blocks as solid initially;
		# _build_lookups() will remove non-solid ones later
		if info.get("layer", "") == "foreground":
			_solid_set[id_int] = true

	# Add missing block entries that aren't in items_map but we need
	# Boosts (114-117)
	if not _block_db.has(114):
		_block_db[114] = {"atlas": "blocks", "layer": "decoration", "artoffset": 114}
	if not _block_db.has(115):
		_block_db[115] = {"atlas": "blocks", "layer": "decoration", "artoffset": 115}
	if not _block_db.has(116):
		_block_db[116] = {"atlas": "blocks", "layer": "decoration", "artoffset": 116}
	if not _block_db.has(117):
		_block_db[117] = {"atlas": "blocks", "layer": "decoration", "artoffset": 117}
	# Slow dots (459, 460)
	if not _block_db.has(459):
		_block_db[459] = {"atlas": "special", "layer": "decoration", "artoffset": 332}
	if not _block_db.has(460):
		_block_db[460] = {"atlas": "special", "layer": "decoration", "artoffset": 337}
	# Hazard blocks that may be missing
	if not _block_db.has(156):
		_block_db[156] = {"atlas": "blocks", "layer": "decoration", "artoffset": 156}
	if not _block_db.has(157):
		_block_db[157] = {"atlas": "blocks", "layer": "decoration", "artoffset": 157}
	if not _block_db.has(218):
		_block_db[218] = {"atlas": "blocks", "layer": "decoration", "artoffset": 218}
	if not _block_db.has(219):
		_block_db[219] = {"atlas": "blocks", "layer": "decoration", "artoffset": 219}
	if not _block_db.has(361):
		_block_db[361] = {"atlas": "special", "layer": "decoration", "artoffset": 156}
	if not _block_db.has(368):
		_block_db[368] = {"atlas": "special", "layer": "decoration", "artoffset": 245}
	# Decoration 120 (ladder) if missing
	if not _block_db.has(120):
		_block_db[120] = {"atlas": "blocks", "layer": "decoration", "artoffset": 120}
	# Eraser
	if not _block_db.has(0):
		_block_db[0] = {"atlas": "blocks", "layer": "background", "artoffset": 0}

func _generate_slopes() -> void:
	# Run the slope generator to produce ImageTextures from existing block sprites.
	# Register each slope ID in _block_db with atlas="slope" so the renderer knows
	# to look them up via get_slope_texture() instead of the atlas system.
	_slope_textures = SlopeGenerator.generate()
	for slope_id in _slope_textures.keys():
		_block_db[slope_id] = {"atlas": "slope", "layer": "foreground", "artoffset": slope_id}
		_non_solid_fg[slope_id] = true
		_slope_set[slope_id] = true

func is_slope(id: int) -> bool:
	return _slope_set.has(id)

func get_slope_texture(id: int) -> Texture2D:
	if _slope_textures.has(id):
		return _slope_textures[id]
	return null

func _build_palette() -> void:
	BLOCK_PALETTE.clear()
	for cat in BLOCK_CATEGORIES:
		for bid in cat["ids"]:
			if not BLOCK_PALETTE.has(bid):
				BLOCK_PALETTE.append(bid)

func _build_lookups() -> void:
	# ---- Non-solid foreground block set ----
	# These blocks appear in foreground but players pass through them.
	# After building this set, we remove them from _solid_set.

	# Arrows (gravity modifiers)
	_action_arrows[1] = 1      # LEFT
	_action_arrows[411] = 1    # LEFT
	_action_arrows[2] = 2      # UP
	_action_arrows[412] = 2    # UP
	_action_arrows[3] = 3      # RIGHT
	_action_arrows[413] = 3    # RIGHT
	_action_arrows[1518] = 0   # DOWN
	_action_arrows[1519] = 0   # DOWN
	for aid in _action_arrows.keys():
		_non_solid_fg[aid] = true

	# Dot blocks -> 0 = normal dot, 1 = slow dot
	_action_dots[4] = 0
	_action_dots[414] = 0
	_action_dots[459] = 1
	_action_dots[460] = 1
	for did in _action_dots.keys():
		_non_solid_fg[did] = true

	# Boost blocks -> [speedX, speedY]
	_action_boosts[114] = Vector2(-PHYSICS_BOOST, 0)  # LEFT
	_action_boosts[115] = Vector2(PHYSICS_BOOST, 0)   # RIGHT
	_action_boosts[116] = Vector2(0, -PHYSICS_BOOST)  # UP
	_action_boosts[117] = Vector2(0, PHYSICS_BOOST)   # DOWN
	for bid in _action_boosts.keys():
		_non_solid_fg[bid] = true

	# Keys (collectible, non-solid)
	_key_set[6] = "red"
	_key_set[7] = "green"
	_key_set[8] = "blue"
	_key_set[408] = "cyan"
	_key_set[409] = "magenta"
	_key_set[410] = "yellow"
	for kid in _key_set.keys():
		_non_solid_fg[kid] = true

	# Switches (non-solid)
	_switch_set[113] = true    # purple switch
	_switch_set[467] = true    # orange switch
	for sid in _switch_set.keys():
		_non_solid_fg[sid] = true

	# Doors & gates (non-solid - player passes through when activated)
	var door_ids: Array = [23, 24, 25, 26, 27, 28, 1005, 1006, 1007, 1008, 1009, 1010,
		165, 43, 214, 213, 200, 201, 184, 185, 156, 157,
		1079, 1080, 1011, 1012, 206, 207, 1027, 1028]
	for did in door_ids:
		_door_set[did] = true
		_non_solid_fg[did] = true

	# Coins (collectible, non-solid)
	_coin_set[100] = true   # gold coin
	_coin_set[101] = true   # blue coin
	for cid in _coin_set.keys():
		_non_solid_fg[cid] = true

	# Music / instrument blocks (non-solid)
	_music_set[77] = true    # piano
	_music_set[83] = true    # drums
	for mid in _music_set.keys():
		_non_solid_fg[mid] = true

	# Hazards (non-solid, damage the player)
	_hazard_set[361] = true   # fire
	_hazard_set[368] = true   # spike
	_hazard_set[119] = true   # water
	_hazard_set[416] = true   # lava liquid
	_hazard_set[369] = true   # mud
	_hazard_set[5010] = true  # plasma spikes (custom arena hazard)
	for hid in _hazard_set.keys():
		_non_solid_fg[hid] = true

	# Effects (non-solid, apply status to player)
	var effect_ids: Array = [417, 418, 419, 420, 421, 422, 423, 453, 461, 1064]
	for eid in effect_ids:
		_effect_set[eid] = true
		_non_solid_fg[eid] = true

	# Portals (non-solid, teleport player)
	_portal_set[242] = true   # portal (invisible)
	_portal_set[374] = true   # world portal
	_portal_set[381] = true   # portal (visible)
	for pid in _portal_set.keys():
		_non_solid_fg[pid] = true

	# Crown / spawn / checkpoint / trophy / sign / misc non-solid
	var misc_nonsolid: Array = [
		5,      # crown
		255,    # spawn point
		360,    # checkpoint
		121,    # trophy / world complete
		466,    # team door / sign
		118,    # chain (climbable)
		120,    # ladder (climbable)
		98,     # vine left
		99,     # vine right
		424,    # diamond
		241,    # text sign
		337,    # world portal label
		397,    # reset point
		1000,   # NPC
		385,    # gold gate / misc
	]
	for nid in misc_nonsolid:
		_non_solid_fg[nid] = true

	# Eraser is never solid
	_non_solid_fg[0] = true

	# ---- Remove all non-solid blocks from _solid_set ----
	for ns_id in _non_solid_fg.keys():
		if _solid_set.has(ns_id):
			_solid_set.erase(ns_id)

func get_block_info(id: int) -> Dictionary:
	if _block_db.has(id):
		return _block_db[id]
	return {}

func get_block_layer(id: int) -> String:
	if _block_db.has(id):
		var info: Dictionary = _block_db[id]
		return info.get("layer", "foreground")
	return "foreground"

func is_solid(id: int) -> bool:
	return _solid_set.has(id)

func is_solid_block(id: int) -> bool:
	return _solid_set.has(id)

func get_custom_block_texture(id: int) -> Texture2D:
	return _custom_block_textures.get(id, null)

func is_custom_block(id: int) -> bool:
	return _custom_block_textures.has(id)

# Visual warp per block id (Ctrl+Arrows editor tool can still set these).
# Baked warps are GONE: every block renders at exactly 16x16 so the grid is
# perfectly uniform and the ball sits flush against every surface.
var _custom_block_warps: Dictionary = {}

func get_custom_block_warp(id: int) -> Vector2:
	return _custom_block_warps.get(id, Vector2.ZERO)

func set_custom_block_warp(id: int, warp: Vector2) -> void:
	_custom_block_warps[id] = warp

func is_hazard(id: int) -> bool:
	return _hazard_set.has(id)

func hazard_at_ball(px: float, py: float) -> bool:
	## True if a 16x16 ball at top-left (px,py) meaningfully overlaps a hazard.
	## Plasma spikes (5010) use a forgiving inset (>=5px lateral, 6px deep) so
	## sub-pixel boundary grazes never kill — real contact still does.
	for ty in range(int(floor(py / 16.0)), int(floor((py + 15.0) / 16.0)) + 1):
		for tx in range(int(floor(px / 16.0)), int(floor((px + 15.0) / 16.0)) + 1):
			var id: int = WorldManager.get_tile(tx, ty)
			if not is_hazard(id):
				continue
			if id == 5010:
				var x_over: float = minf(px + 16.0, tx * 16.0 + 16.0) - maxf(px, tx * 16.0)
				if x_over >= 5.0 and py + 16.0 >= ty * 16.0 + 6.0:
					return true
			else:
				return true
	return false

func is_hazard_block(id: int) -> bool:
	return _hazard_set.has(id)

func is_action(id: int) -> bool:
	return _action_arrows.has(id) or _action_dots.has(id) or _action_boosts.has(id)

func is_arrow(id: int) -> bool:
	return _action_arrows.has(id)

func get_arrow_gravity(id: int) -> int:
	return _action_arrows.get(id, -1)

func is_dot(id: int) -> bool:
	return _action_dots.has(id)

func get_dot_type(id: int) -> int:
	# 0 = normal, 1 = slow
	return _action_dots.get(id, -1)

func is_boost(id: int) -> bool:
	return _action_boosts.has(id)

func get_boost_vector(id: int) -> Vector2:
	return _action_boosts.get(id, Vector2.ZERO)

func is_door(id: int) -> bool:
	return _door_set.has(id)

func is_key(id: int) -> bool:
	return _key_set.has(id)

func get_key_color(id: int) -> String:
	return _key_set.get(id, "")

func is_coin(id: int) -> bool:
	return _coin_set.has(id)

func is_effect(id: int) -> bool:
	return _effect_set.has(id)

func is_music(id: int) -> bool:
	return _music_set.has(id)

func is_portal(id: int) -> bool:
	return _portal_set.has(id)

func is_switch(id: int) -> bool:
	return _switch_set.has(id)

func is_non_solid_foreground(id: int) -> bool:
	return _non_solid_fg.has(id)

func get_category_ids(cat_index: int) -> Array:
	if cat_index >= 0 and cat_index < BLOCK_CATEGORIES.size():
		return BLOCK_CATEGORIES[cat_index]["ids"]
	return []

func get_category_name(cat_index: int) -> String:
	if cat_index >= 0 and cat_index < BLOCK_CATEGORIES.size():
		return BLOCK_CATEGORIES[cat_index]["name"]
	return ""

func get_category_count() -> int:
	return BLOCK_CATEGORIES.size()

func set_edit_mode(enabled: bool) -> void:
	is_edit_mode = enabled
	edit_mode_changed.emit(enabled)

func select_block(id: int) -> void:
	selected_block = id
	selected_block_id = id
	block_selected.emit(id)

func cycle_block(forward: bool) -> void:
	var cat_ids: Array = get_category_ids(selected_category)
	if cat_ids.is_empty():
		return
	var idx: int = cat_ids.find(selected_block_id)
	if idx < 0:
		idx = 0
	if forward:
		idx = (idx + 1) % cat_ids.size()
	else:
		idx = (idx - 1 + cat_ids.size()) % cat_ids.size()
	selected_palette_index = idx
	select_block(cat_ids[idx])

func set_state_channel(channel_id: int, value: int) -> void:
	state_channels[channel_id] = value

func get_state_channel(channel_id: int) -> int:
	if state_channels.has(channel_id):
		return state_channels[channel_id]
	return 0
