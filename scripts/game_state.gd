extends Node

const TILE_SIZE: int = 16
var is_edit_mode: bool = false
var selected_block_id: int = 9
var selected_block: int = 9
var selected_palette_index: int = 0
var selected_category: int = 0
var state_channels: Dictionary = {}
var player_name: String = "Player"
var player_smiley_id: int = 0
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
		0,
		1088, 9, 182, 12, 1018, 13, 14, 15, 10, 11,
		1089, 42, 1021, 40, 1020, 41, 38, 1019, 39, 37,
		1022, 1023, 18, 20, 16, 21, 19, 17, 1024,
		29, 30, 31, 34, 35, 36,
		22, 1057, 32, 1058, 33, 44, 45, 46, 47, 48, 49, 50, 243, 136,
		51, 52, 53, 54, 55, 56, 57, 58,
		72, 71, 70, 76, 75, 74, 73,
		78, 79, 80, 81, 82,
		60, 61, 62, 63, 64, 65, 66, 67,
		59, 68, 69,
		84, 85, 86, 87, 88, 89, 90, 91, 1051,
		92, 93, 94, 95, 96, 97, 1044, 1045, 1046,
		122, 123, 124, 125, 126, 127,
		128, 129, 130, 131, 132, 133, 134, 135, 137, 138, 139, 140, 141, 142, 143,
		144, 145, 146, 147, 148, 149,
		158, 159, 160, 162, 163,
		166, 167, 168, 169, 170, 171, 172, 173, 174, 175,
		176, 1029, 177, 178, 179, 180, 181,
		186, 187, 188, 189, 1025, 190, 191, 192, 1026, 193,
		194, 195, 196, 197, 198,
		202, 203, 204, 208, 209, 210, 211, 212, 215, 216,
		1013, 1014, 1015, 1016, 1017,
		1065, 1066, 1067, 1068, 1069,
		1030, 1031, 1032, 1033, 1034,
		1035, 1036, 1037, 1038, 1039, 1040, 1041, 1042, 1043,
		1047, 1048, 1049, 1050,
		1059, 1060, 1061, 1062, 1063,
		1070, 1071, 1072, 1073, 1074, 1075, 1076, 1077, 1078,
		1081, 1082,
	]},
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

signal edit_mode_changed(enabled: bool)
signal block_selected(block_id: int)
signal state_channel_changed(channel_id: int, value: int)

func _ready() -> void:
	# Load items_map.json
	_load_items_map()
	# Generate slope textures and register slope blocks
	_generate_slopes()
	# Build flat palette
	_build_palette()
	# Build action/hazard/door/key lookups and non-solid set
	_build_lookups()

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

func is_hazard(id: int) -> bool:
	return _hazard_set.has(id)

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
