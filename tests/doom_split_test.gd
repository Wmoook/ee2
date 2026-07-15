extends Node
## Dev test: DOOM RAY vs a raised shield. The ray must STOP at the shield,
## split off it (dead-center hit = straight back at the shooter), deal ZERO
## damage to the defender, and cook the shooter with their own reflected ray.

func _ready() -> void:
	GameState.battle_mode = true
	BattleMap.build()
	var ws: WeaponSystem = WeaponSystem.new()
	add_child(ws)
	var apos: Vector2 = Vector2(400.0, 500.0)
	var bpos: Vector2 = Vector2(600.0, 500.0)
	var a_hp: Array = [5]
	var b_hp: Array = [5]
	ws.register_actor("atk", 0,
		func() -> Vector2: return apos,
		func() -> Vector2: return Vector2.ZERO,
		func() -> bool: return true,
		func(dmg: int, _dir: Vector2) -> void: a_hp[0] -= dmg,
		func() -> int: return a_hp[0], 5,
		func() -> bool: return true,
		func(_v: Vector2) -> void: pass)
	ws.register_actor("def", 1,
		func() -> Vector2: return bpos,
		func() -> Vector2: return Vector2.ZERO,
		func() -> bool: return true,
		func(dmg: int, _dir: Vector2) -> void: b_hp[0] -= dmg,
		func() -> int: return b_hp[0], 5,
		func() -> bool: return true,
		func(_v: Vector2) -> void: pass)
	ws.give_weapon("atk", "doom")
	ws.set_aim("atk", Vector2.RIGHT)
	ws.set_shield("def", true)
	# Fire the beam for ~0.45s (shield stays up well past this; drain is 2.2/s)
	var t: float = 0.0
	while t < 0.45:
		ws.set_shield("def", true)
		ws.try_shoot("atk")
		await get_tree().process_frame
		t += get_process_delta_time()
	var actor: Dictionary = ws._actors["atk"]
	var sfrom: Vector2 = actor.get("beam_split_from", Vector2.ZERO)
	var sto: Vector2 = actor.get("beam_split_to", Vector2.ZERO)
	print("SPLIT TEST: def_hp=%d atk_hp=%d beam_end=%s split_from=%s split_to=%s" % [
		b_hp[0], a_hp[0], actor.beam_end, sfrom, sto])
	var stopped_at_shield: bool = actor.beam_end.x < 596.0 and actor.beam_end.x > 560.0
	var split_exists: bool = sfrom.distance_to(sto) > 30.0
	var split_back: bool = sto.x < sfrom.x  # Dead-center hit reflects LEFT, back at the shooter
	var def_untouched: bool = b_hp[0] == 5
	var shooter_cooked: bool = a_hp[0] < 5
	print("stopped_at_shield=%s split_exists=%s split_back=%s def_untouched=%s shooter_cooked=%s" % [
		stopped_at_shield, split_exists, split_back, def_untouched, shooter_cooked])
	if stopped_at_shield and split_exists and split_back and def_untouched and shooter_cooked:
		print("DOOM SPLIT PASS")
	else:
		print("DOOM SPLIT FAIL")
	GameState.battle_mode = false
	get_tree().quit(0)
