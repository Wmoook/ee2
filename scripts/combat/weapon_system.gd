class_name WeaponSystem
extends Node2D
## Weapons, projectiles, pickups, combat FX and SFX.
##
## Actors (player/bots) register with callables so this system knows nothing
## about their classes. Guns render as neon vector art floating beside the
## ball, aimed at the actor's aim direction. Projectiles collide with grid
## tiles, curve capsules and enemy actors. All effects use the game's opaque
## bright-particle style (same language as the fire trail).

const ACTOR_RADIUS: float = 10.0     # Projectile-vs-ball hit radius
const CURVE_HIT_DIST: float = 8.35   # Projectile-vs-curve centerline distance
const PICKUP_RADIUS: float = 16.0
const PICKUP_RESPAWN: float = 8.0    # Seconds until a taken pad refills

const WEAPONS: Dictionary = {
	"blaster": {
		"label": "BLASTER", "color": Color(1.0, 0.72, 0.15), "dmg": 1,
		"cooldown": 0.16, "speed": 950.0, "count": 1, "spread": 0.015,
		"life": 0.8, "size": 3.0, "sfx": "shoot_blaster", "shake": 1.6, "kick": 0.6,
	},
	"scatter": {
		"label": "SCATTER", "color": Color(0.25, 0.9, 1.0), "dmg": 1,
		"cooldown": 0.7, "speed": 760.0, "count": 6, "spread": 0.24,
		"life": 0.38, "size": 2.4, "sfx": "shoot_scatter", "shake": 3.2, "kick": 1.6,
	},
	"rail": {
		"label": "RAIL", "color": Color(0.75, 0.4, 1.0), "dmg": 2,
		"cooldown": 1.05, "speed": 2400.0, "count": 1, "spread": 0.0,
		"life": 0.5, "size": 3.6, "sfx": "shoot_rail", "shake": 4.5, "kick": 2.4,
	},
	# ── ZOMBIES-mode arsenal (wall buys + mystery box) ──
	"pistol": {
		"label": "PISTOL", "color": Color(0.85, 0.85, 0.9), "dmg": 1,
		"cooldown": 0.34, "speed": 900.0, "count": 1, "spread": 0.02,
		"life": 0.9, "size": 2.6, "sfx": "shoot_blaster", "shake": 1.0, "kick": 0.4,
	},
	"smg": {
		"label": "SMG", "color": Color(1.0, 0.9, 0.5), "dmg": 1,
		"cooldown": 0.09, "speed": 1000.0, "count": 1, "spread": 0.055,
		"life": 0.7, "size": 2.4, "sfx": "shoot_blaster", "shake": 1.2, "kick": 0.35,
	},
	"rifle": {
		"label": "RIFLE", "color": Color(0.6, 1.0, 0.9), "dmg": 3,
		"cooldown": 0.55, "speed": 1700.0, "count": 1, "spread": 0.004,
		"life": 0.8, "size": 3.2, "sfx": "shoot_rail", "shake": 2.6, "kick": 1.4,
	},
	"minigun": {
		"label": "MINIGUN", "color": Color(1.0, 0.55, 0.3), "dmg": 1,
		"cooldown": 0.055, "speed": 1050.0, "count": 1, "spread": 0.1,
		"life": 0.65, "size": 2.4, "sfx": "shoot_blaster", "shake": 1.8, "kick": 0.5,
	},
	"raygun": {
		"label": "RAY GUN", "color": Color(0.35, 1.0, 0.45), "dmg": 4,
		"cooldown": 0.28, "speed": 1100.0, "count": 1, "spread": 0.01,
		"life": 0.9, "size": 4.2, "sfx": "shoot_rail", "shake": 3.0, "kick": 1.0,
	},
	# ── PACK-A-PUNCH forgings (zombies vault machine, $5000) ──
	"pistol_pap": {
		"label": "MUSTANG", "color": Color(1.0, 0.5, 0.9), "dmg": 3,
		"cooldown": 0.22, "speed": 1100.0, "count": 1, "spread": 0.015,
		"life": 0.9, "size": 3.4, "sfx": "shoot_blaster", "shake": 1.8, "kick": 0.6,
	},
	"smg_pap": {
		"label": "SHREDDER", "color": Color(1.0, 0.6, 0.85), "dmg": 2,
		"cooldown": 0.07, "speed": 1150.0, "count": 1, "spread": 0.05,
		"life": 0.75, "size": 2.8, "sfx": "shoot_blaster", "shake": 1.5, "kick": 0.4,
	},
	"scatter_pap": {
		"label": "HELLSPRAY", "color": Color(0.6, 0.75, 1.0), "dmg": 2,
		"cooldown": 0.55, "speed": 850.0, "count": 8, "spread": 0.26,
		"life": 0.42, "size": 2.8, "sfx": "shoot_scatter", "shake": 4.0, "kick": 2.0,
	},
	"rifle_pap": {
		"label": "LONGSHOT PRIME", "color": Color(0.75, 1.0, 0.95), "dmg": 7,
		"cooldown": 0.4, "speed": 2000.0, "count": 1, "spread": 0.002,
		"life": 0.8, "size": 3.8, "sfx": "shoot_rail", "shake": 3.2, "kick": 1.7,
	},
	"blaster_pap": {
		"label": "SUNLANCE", "color": Color(1.0, 0.85, 0.4), "dmg": 2,
		"cooldown": 0.11, "speed": 1150.0, "count": 1, "spread": 0.012,
		"life": 0.85, "size": 3.4, "sfx": "shoot_blaster", "shake": 2.0, "kick": 0.7,
	},
	"rail_pap": {
		"label": "STARPIERCER", "color": Color(0.9, 0.6, 1.0), "dmg": 5,
		"cooldown": 0.8, "speed": 2600.0, "count": 1, "spread": 0.0,
		"life": 0.55, "size": 4.4, "sfx": "shoot_rail", "shake": 5.0, "kick": 2.6,
	},
	"minigun_pap": {
		"label": "DOOMSPINNER", "color": Color(1.0, 0.4, 0.5), "dmg": 2,
		"cooldown": 0.045, "speed": 1150.0, "count": 1, "spread": 0.09,
		"life": 0.7, "size": 2.8, "sfx": "shoot_blaster", "shake": 2.2, "kick": 0.6,
	},
	"raygun_pap": {
		"label": "RAY GUN MK2", "color": Color(0.2, 1.0, 0.7), "dmg": 8,
		"cooldown": 0.22, "speed": 1250.0, "count": 1, "spread": 0.008,
		"life": 0.95, "size": 5.0, "sfx": "shoot_rail", "shake": 3.8, "kick": 1.2,
	},
	"doom": {
		"label": "DOOM RAY", "color": Color(1.0, 0.22, 0.15), "dmg": 1,
		"cooldown": 0.0, "speed": 0.0, "count": 0, "spread": 0.0,
		"life": 0.0, "size": 0.0, "sfx": "", "shake": 0.0, "kick": 0.12,
		"beam": true, "duration": 10.0, "tick": 0.12, "range": 1100.0,
	},
}

const SUPER_PERIOD: float = 60.0     # A DOOM RAY materializes this often
const SUPER_ANIM_TIME: float = 1.8   # Spawn-in animation length

# Unarmed melee kit
const DASH_CD: float = 1.1           # Seconds between dashes
const DASH_WINDOW: float = 0.35      # Contact window after dashing
const DASH_DMG: int = 1
const SHIELD_MAX: float = 2.4        # Max shield hold (drains; regens when down)
const STUN_TIME: float = 1.0         # Parry stun duration
const PARRY_WINDOW: float = 0.28     # A dash is only PARRIED (stun) if the shield
                                     # went up this recently — timed parry. A held
                                     # shield still blocks, but stuns nobody
                                     # (hold-and-ram was a free-stun cheese).

const BLOCK_BREAK_TIME: float = 0.35  # Seconds of beam-cook to shatter a block
const BLOCK_RESPAWN: float = 10.0     # Shattered terrain re-materializes after this
const CURVE_BREAK_TIME: float = 0.9   # A whole curve is worth ~3 blocks of cooking

# Random ability drops (player-only pickups; one orb on the field at a time)
const ABILITIES: Dictionary = {
	"zerog": {"label": "ZERO-G FLIGHT", "color": Color(0.4, 0.9, 1.0), "dur": 8.0},
	"overdrive": {"label": "OVERDRIVE", "color": Color(1.0, 0.85, 0.3), "dur": 8.0},
	"mend": {"label": "NANO-MEND", "color": Color(0.4, 1.0, 0.5), "dur": 8.0},
}

signal ability_picked(kind: String)

var _actors: Dictionary = {}      # id -> actor dict
var _pads: Array = []             # {pos, weapon, respawn_left, phase, super}
var _projectiles: Array = []      # {pos, vel, team, dmg, life, color, size}
var _fx: Array = []               # {pos, vel, life, max_life, color, size}
var _block_dmg: Dictionary = {}   # Vector2i tile -> accumulated break progress (0..BREAK_TIME)
var _cooked_now: Dictionary = {}  # Tiles damaged this frame (skip their decay)
var _broken: Array = []           # {x, y, id, respawn} — shattered tiles pending respawn
var net_break_cb: Callable = Callable()  # online host: mirror terrain breaks to the lobby
var _curve_dmg: Dictionary = {}   # curve key (first point, quantized) -> cook progress
var _curve_cooked_now: Dictionary = {}
var _broken_free: Array = []      # {fb, respawn} — shattered free blocks pending respawn
var _broken_curves: Array = []    # {polys, all_points, respawn} — shattered curves pending respawn
var ability_spots: Array = []     # Set by the mode/map — where orbs may appear
var _abil_orb: Dictionary = {}    # {pos, kind, life} — the orb on the field
var _abil_timer: float = 12.0     # First drop comes fairly quickly
var _sfx: Dictionary = {}         # name -> AudioStream
var _sfx_pool: Array = []
var _sfx_next: int = 0
var _time: float = 0.0
# Super weapon (DOOM RAY) cycle
var super_pos: Vector2 = Vector2.ZERO   # Set by the map builder
var _super_timer: float = SUPER_PERIOD
var _super_state: int = 0               # 0=countdown, 1=materializing, 2=on the field
var _super_anim: float = 0.0
var _beam_audio: AudioStreamPlayer2D


func _ready() -> void:
	z_index = 3
	for n in ["shoot_blaster", "shoot_scatter", "shoot_rail", "hit", "explode", "pickup", "doom_spawn", "doom_beam", "bonk"]:
		var stream: AudioStream = load("res://assets/sfx/%s.wav" % n) as AudioStream
		if stream:
			_sfx[n] = stream
	for _i in range(10):
		var p: AudioStreamPlayer2D = AudioStreamPlayer2D.new()
		p.max_distance = 2400.0
		p.attenuation = 1.2
		p.volume_db = -4.0
		add_child(p)
		_sfx_pool.append(p)
	# Dedicated looping player for the DOOM RAY hum
	_beam_audio = AudioStreamPlayer2D.new()
	_beam_audio.max_distance = 2400.0
	_beam_audio.volume_db = -6.0
	var beam_stream: AudioStreamWAV = _sfx.get("doom_beam") as AudioStreamWAV
	if beam_stream:
		beam_stream.loop_mode = AudioStreamWAV.LOOP_FORWARD
		beam_stream.loop_end = beam_stream.data.size() / 2
		_beam_audio.stream = beam_stream
	add_child(_beam_audio)


# ── Actors ────────────────────────────────────────────────────────────────────

func register_actor(id: String, team: int, get_center: Callable, get_vel: Callable, is_alive: Callable, hurt: Callable, get_hp: Callable = Callable(), max_hp: int = 3, get_grounded: Callable = Callable(), push: Callable = Callable()) -> void:
	## get_center() -> Vector2 (px), get_vel() -> Vector2 (px/s),
	## is_alive() -> bool, hurt(dmg: int, dir: Vector2) -> void,
	## get_hp() -> int (floating HP bar), get_grounded() -> bool (landing
	## stuns), push(v: Vector2) -> void (parry launches)
	_actors[id] = {
		"team": team, "get_center": get_center, "get_vel": get_vel,
		"is_alive": is_alive, "hurt": hurt, "get_hp": get_hp, "max_hp": max_hp,
		"get_grounded": get_grounded, "push": push,
		"hit_radius": ACTOR_RADIUS, "no_pickup": false,
		"weapon": "", "cooldown": 0.0, "aim": Vector2.RIGHT,
		"weapon_left": -1.0, "beam_on": false, "beam_end": Vector2.ZERO, "beam_tick": 0.0,
		"cur_slot": 1, "super_left": -1.0, "loadout": false, "auto_equip": true,
		"abil_fly": 0.0, "abil_od": 0.0, "abil_regen": 0.0,
		"slot2_flash": 0.0, "beam_cut": -1.0,
		"dash_cd": 0.0, "dash_time": 0.0, "dash_dmg": 1,
		"charge": 0.0, "charging": false, "charge_fed": false,
		"shield_req": false, "shield_on": false, "shield_energy": SHIELD_MAX,
		"shield_broken": false, "shield_lock": 0.0, "shield_time": 999.0,
		"stun_left": 0.0, "stun_pending": false,
	}


func set_aim(id: String, dir: Vector2) -> void:
	if _actors.has(id) and dir.length() > 0.01:
		_actors[id].aim = dir.normalized()


func give_weapon(id: String, weapon: String) -> void:
	if not (_actors.has(id) and WEAPONS.has(weapon)):
		return
	var ga: Dictionary = _actors[id]
	if weapon == "doom":
		# The DOOM RAY loads into SLOT 2 — it never yanks you out of your
		# current kit (press 2 to unleash it). Bots draw it instantly.
		ga.super_left = WEAPONS.doom.get("duration", 10.0)
		ga.slot2_flash = 2.5  # Flash the slot bar so you KNOW it landed
		if ga.get("auto_equip", true) or ga.cur_slot == 2:
			ga.cur_slot = 2
			ga.weapon = "doom"
			ga.weapon_left = ga.super_left
			ga.cooldown = 0.15
		else:
			play_sfx("doom_spawn", ga.get_center.call(), 0.05, 1.8)
			spawn_ring(ga.get_center.call(), Color(1.0, 0.5, 0.2), 4.0, 26.0, 0.3)
		return
	ga.weapon = weapon
	ga.cur_slot = 2
	ga.cooldown = 0.15
	ga.weapon_left = WEAPONS[weapon].get("duration", -1.0)


func strip_weapon(id: String) -> void:
	if _actors.has(id):
		_actors[id].weapon = ""
		_actors[id].beam_on = false
		_actors[id]["super_left"] = -1.0
		_actors[id]["cur_slot"] = 1


func slot_weapon(id: String, slot: int) -> String:
	## What a slot holds: 1 = fists, 2 = DOOM RAY if charged else blaster,
	## 3 = scatter. Gun slots are empty without the permanent loadout
	## (fists-only mode) — except the doom, which always answers to 2.
	## Actors with a "slot_guns" dict (zombies mode: CoD two-gun limit)
	## carry ARBITRARY guns per slot instead of the fixed arena kit.
	if not _actors.has(id):
		return ""
	var a: Dictionary = _actors[id]
	if slot == 2:
		if a.get("super_left", 0.0) > 0.0:
			return "doom"
		if a.has("slot_guns"):
			return a.slot_guns.get(2, "")
		return "blaster" if a.get("loadout", false) else ""
	if slot == 3:
		if a.has("slot_guns"):
			return a.slot_guns.get(3, "")
		return "scatter" if a.get("loadout", false) else ""
	return ""


func set_slot_gun(id: String, slot: int, weapon: String) -> void:
	## Zombies mode: put a bought/box gun into a carry slot (2 or 3) and
	## draw it immediately. Creates the slot_guns dict on first use.
	if not _actors.has(id) or (weapon != "" and not WEAPONS.has(weapon)):
		return
	var a: Dictionary = _actors[id]
	if not a.has("slot_guns"):
		a["slot_guns"] = {2: "", 3: ""}
	a.slot_guns[slot] = weapon
	a.cur_slot = slot
	a.weapon = weapon
	a.beam_on = false
	a.cooldown = 0.25  # draw time
	a.weapon_left = -1.0
	if weapon != "":
		play_sfx("pickup", a.get_center.call(), 0.05, 1.35)


func select_slot(id: String, slot: int) -> void:
	## Permanent inventory: 1 = fists, 2 = blaster/DOOM, 3 = scatter.
	## Idempotent — safe to call every frame while the key is held.
	if not _actors.has(id):
		return
	var a: Dictionary = _actors[id]
	if a.cur_slot == slot:
		return
	var w: String = slot_weapon(id, slot)
	if slot != 1 and w == "":
		return  # Empty gun slot (fists-only mode without a stored doom)
	a.cur_slot = slot
	a.weapon = w
	a.beam_on = false
	a.cooldown = 0.18  # Draw time
	a.weapon_left = a.super_left if w == "doom" else -1.0
	play_sfx("pickup", a.get_center.call(), 0.04, 0.65 if slot == 1 else 1.25)


func is_super_available() -> bool:
	return _super_state == 2


func is_super_hot() -> bool:
	## Materializing OR on the field — worth racing for already.
	return _super_state >= 1


func get_super_status() -> String:
	match _super_state:
		0: return "DOOM RAY in %ds" % int(ceil(_super_timer))
		1: return "DOOM RAY INCOMING!"
		_: return "DOOM RAY ON THE FIELD!"


func get_weapon(id: String) -> String:
	return _actors[id].weapon if _actors.has(id) else ""


func get_weapon_color(id: String) -> Color:
	var w: String = get_weapon(id)
	return WEAPONS[w].color if WEAPONS.has(w) else Color.WHITE


func try_shoot(id: String) -> bool:
	if not _actors.has(id):
		return false
	var a: Dictionary = _actors[id]
	if a.weapon == "" or a.cooldown > 0.0 or not a.is_alive.call():
		return false
	if a.stun_left > 0.0 or a.stun_pending:
		return false  # Parried — no shooting while stunned
	var w: Dictionary = WEAPONS[a.weapon]
	if w.get("beam", false):
		# Beam weapons fire continuously: request the beam for this frame
		a.beam_on = true
		return true
	# Finite ammo (zombies mode): actors with an "ammo" dict spend a round
	# per trigger pull; an empty pool dry-clicks. Beams are time-fueled.
	if a.has("ammo"):
		var pool: int = int(a.ammo.get(a.weapon, -1))
		if pool == 0:
			a.cooldown = 0.22
			play_sfx("bonk", a.get_center.call(), 0.02, 2.4)  # dry click
			return false
		if pool > 0:
			a.ammo[a.weapon] = pool - 1
	# OVERDRIVE: guns fire twice as fast while it lasts
	a.cooldown = w.cooldown * (0.5 if a.get("abil_od", 0.0) > 0.0 else 1.0)
	var center: Vector2 = a.get_center.call()
	var muzzle: Vector2 = center + a.aim * 18.0
	for i in range(w.count):
		var ang: float = a.aim.angle() + randfn(0.0, 0.0001 + w.spread)
		var dir: Vector2 = Vector2.from_angle(ang)
		_projectiles.append({
			"pos": muzzle, "vel": dir * w.speed * randf_range(0.95, 1.05),
			"team": a.team, "dmg": w.dmg, "life": w.life,
			"color": w.color, "size": w.size,
		})
	# Muzzle flash sparks
	for _i in range(7):
		var sdir: Vector2 = a.aim.rotated(randf_range(-0.55, 0.55))
		_fx.append({
			"pos": muzzle, "vel": sdir * randf_range(120.0, 340.0),
			"life": randf_range(0.05, 0.14), "max_life": 0.14,
			"color": w.color, "size": randf_range(1.5, 3.0),
		})
	_fx.append({
		"pos": muzzle, "vel": Vector2.ZERO, "life": 0.06, "max_life": 0.06,
		"color": Color(1, 1, 1), "size": 7.0,
	})
	play_sfx(w.sfx, muzzle)
	GameState.cam_shake += w.shake
	return true


func get_kick(id: String) -> float:
	## Recoil impulse (EE speed units) for the actor's current weapon.
	var w: String = get_weapon(id)
	return WEAPONS[w].kick if WEAPONS.has(w) else 0.0


# ── Unarmed melee: dash punch + parry shield ─────────────────────────────────

func try_dash(id: String) -> bool:
	## Instant quick dash (zero charge). Caller applies the movement impulse.
	if _actors.has(id):
		_actors[id].charge = 0.0
	return release_dash(id).ok


func charge_dash(id: String, delta: float) -> void:
	## Hold to wind up a heavy dash: 1.5s = full power. Call every held frame.
	if not _actors.has(id):
		return
	var a: Dictionary = _actors[id]
	if a.weapon != "" or a.dash_cd > 0.0 or a.stun_left > 0.0 or a.stun_pending or not a.is_alive.call():
		return
	a.charge_fed = true
	a.charging = true
	var was: float = a.charge
	a.charge = minf(1.0, a.charge + delta / 1.5)
	# Charge-up: energy converges into the ball, denser as it builds
	if randf() < delta * (14.0 + 60.0 * a.charge):
		var c: Vector2 = a.get_center.call()
		var ang: float = randf() * TAU
		var p: Vector2 = c + Vector2.from_angle(ang) * randf_range(14.0, 28.0)
		_fx.append({
			"pos": p, "vel": (c - p) * 4.0, "life": 0.2, "max_life": 0.2,
			"color": Color(0.6, 0.9, 1.0).lerp(Color(1.0, 0.92, 0.6), a.charge),
			"size": 1.5 + a.charge * 1.8,
		})
	if was < 1.0 and a.charge >= 1.0:
		play_sfx("pickup", a.get_center.call(), 0.02, 1.9)  # MAX POWER ding
		spawn_ring(a.get_center.call(), Color(1.0, 0.92, 0.6), 4.0, 20.0, 0.22)


func release_dash(id: String) -> Dictionary:
	## Launch the (possibly charged) dash. Returns {ok, power 0..1}; the
	## caller applies impulse scaled by power. Full power hits for 2.
	var out: Dictionary = {"ok": false, "power": 0.0}
	if not _actors.has(id):
		return out
	var a: Dictionary = _actors[id]
	var power: float = a.charge
	a.charging = false
	a.charge = 0.0
	if a.weapon != "" or a.dash_cd > 0.0 or a.stun_left > 0.0 or a.stun_pending or not a.is_alive.call():
		return out
	# OVERDRIVE: dash cooldown nearly gone while it lasts
	a.dash_cd = (0.3 if a.get("abil_od", 0.0) > 0.0 else DASH_CD) + 0.5 * power
	a.dash_time = DASH_WINDOW + 0.15 * power
	a.dash_dmg = 2 if power > 0.65 else 1
	# Attacking drops the shield — no turtling while punching
	a.shield_on = false
	a.shield_lock = 0.45
	var c: Vector2 = a.get_center.call()
	var streaks: int = 10 + int(power * 18.0)
	for _i in range(streaks):
		var side: Vector2 = Vector2(-a.aim.y, a.aim.x) * randf_range(-4.0, 4.0)
		_fx.append({
			"pos": c - a.aim * randf_range(2.0, 10.0) + side,
			"vel": -a.aim * randf_range(60.0, 180.0 + power * 220.0),
			"life": randf_range(0.08, 0.2 + power * 0.1), "max_life": 0.3,
			"color": Color(0.6, 0.9, 1.0).lerp(Color(1.0, 0.92, 0.6), power),
			"size": randf_range(1.2, 2.6 + power * 1.5),
		})
	if power > 0.65:
		spawn_ring(c, Color(1.0, 0.92, 0.6), 5.0, 26.0, 0.22)
	play_sfx("shoot_scatter", c, 0.05, 1.7 - 0.55 * power)
	GameState.cam_shake += 1.4 + 3.2 * power
	out.ok = true
	out.power = power
	return out


func set_shield(id: String, want: bool) -> void:
	if _actors.has(id):
		_actors[id].shield_req = want


func is_shielded(id: String) -> bool:
	return _actors.has(id) and _actors[id].shield_on


func is_stunned(id: String) -> bool:
	return _actors.has(id) and (_actors[id].stun_left > 0.0 or _actors[id].stun_pending)


func _stun_team(team: int, at: Vector2, on_landing: bool = false) -> void:
	## Parry payoff: stun every enemy-team actor (1v1: the attacker).
	## on_landing: the stun starts when they next touch the ground (melee
	## parries launch the striker first — they crash, THEN sit stunned).
	for id in _actors:
		var a: Dictionary = _actors[id]
		if a.team == team:
			if on_landing:
				a.stun_pending = true
			else:
				a.stun_left = STUN_TIME
			a.beam_on = false
	for _i in range(16):
		var ang: float = randf() * TAU
		_fx.append({
			"pos": at, "vel": Vector2.from_angle(ang) * randf_range(90.0, 260.0),
			"life": randf_range(0.1, 0.3), "max_life": 0.3,
			"color": Color(0.7, 0.95, 1.0), "size": randf_range(1.4, 3.0),
		})
	# PARRY! Double shockwave ring + flash
	spawn_ring(at, Color(0.6, 0.95, 1.0), 6.0, 34.0, 0.3)
	spawn_ring(at, Color(1.0, 1.0, 1.0), 3.0, 20.0, 0.18)
	_fx.append({
		"pos": at, "vel": Vector2.ZERO, "life": 0.08, "max_life": 0.08,
		"color": Color(1, 1, 1), "size": 12.0,
	})
	play_sfx("pickup", at, 0.03, 1.7)
	GameState.cam_shake += 4.5


# ── Pickups ───────────────────────────────────────────────────────────────────

func add_pad(pos: Vector2, weapon: String) -> void:
	_pads.append({"pos": pos, "weapon": weapon, "respawn_left": 0.0, "phase": randf() * TAU})


func damage_block(tx: int, ty: int, amount: float) -> bool:
	## Terrain destruction: beams cook blocks over BLOCK_BREAK_TIME seconds,
	## boss impacts chip them in halves. Cracks glow as damage builds, then
	## the block shatters with debris and re-materializes BLOCK_RESPAWN
	## later. The arena shell (outer 2 tiles) is indestructible — nothing
	## ever escapes the world. Returns true when the block shatters.
	if tx <= 1 or ty <= 1 or tx >= WorldManager.world_width - 2 or ty >= WorldManager.world_height - 2:
		return false
	if not WorldManager.is_solid_at(tx, ty):
		return false
	var key: Vector2i = Vector2i(tx, ty)
	var dmg: float = _block_dmg.get(key, 0.0) + amount
	_cooked_now[key] = true
	var cpos: Vector2 = Vector2(tx * 16.0 + 8.0, ty * 16.0 + 8.0)
	if randf() < amount * 30.0:
		_fx.append({
			"pos": cpos + Vector2(randf_range(-7.0, 7.0), randf_range(-7.0, 7.0)),
			"vel": Vector2(randf_range(-30.0, 30.0), randf_range(-70.0, -20.0)),
			"life": randf_range(0.12, 0.3), "max_life": 0.3,
			"color": Color(1.0, randf_range(0.35, 0.6), 0.15), "size": randf_range(1.0, 2.2),
		})
	if dmg < BLOCK_BREAK_TIME:
		_block_dmg[key] = dmg
		return false
	_block_dmg.erase(key)
	var old_id: int = WorldManager.get_tile(tx, ty)
	if old_id <= 0:
		return false
	WorldManager.fg_tiles[ty][tx] = 0
	WorldManager.tile_changed.emit(tx, ty, 0)
	_broken.append({"x": tx, "y": ty, "id": old_id, "respawn": BLOCK_RESPAWN})
	if net_break_cb.is_valid():
		net_break_cb.call("tile", float(tx), float(ty))
	play_sfx("explode", cpos, 0.1, 1.5)
	spawn_ring(cpos, Color(1.0, 0.55, 0.2), 3.0, 22.0, 0.22)
	for _i in range(12):
		var dang: float = randf() * TAU
		_fx.append({
			"pos": cpos, "vel": Vector2.from_angle(dang) * randf_range(40.0, 220.0),
			"life": randf_range(0.15, 0.4), "max_life": 0.4,
			"color": Color(0.25, 0.18, 0.2).lerp(Color(1.0, 0.5, 0.2), randf() * 0.7),
			"size": randf_range(1.5, 3.2),
		})
	GameState.cam_shake += 1.5
	return true


func damage_free_block(idx: int, amount: float) -> bool:
	## Beams cook free-placed blocks exactly like grid tiles: crack FX while
	## damage builds, shatter with debris, respawn later. Damage lives inside
	## the block dict itself (indices shift when others are removed).
	if idx < 0 or idx >= WorldManager.free_blocks.size():
		return false
	var fb: Dictionary = WorldManager.free_blocks[idx]
	fb["_dmg"] = float(fb.get("_dmg", 0.0)) + amount
	fb["_cooked_now"] = true
	var c: Vector2 = (fb.pos as Vector2) + Vector2(8, 8)
	if randf() < amount * 30.0:
		_fx.append({
			"pos": c + Vector2(randf_range(-7.0, 7.0), randf_range(-7.0, 7.0)),
			"vel": Vector2(randf_range(-30.0, 30.0), randf_range(-70.0, -20.0)),
			"life": randf_range(0.12, 0.3), "max_life": 0.3,
			"color": Color(1.0, randf_range(0.35, 0.6), 0.15), "size": randf_range(1.0, 2.2),
		})
	if float(fb["_dmg"]) < BLOCK_BREAK_TIME:
		return false
	var copy: Dictionary = fb.duplicate()
	copy.erase("_dmg")
	copy.erase("_cooked_now")
	WorldManager.free_blocks.remove_at(idx)
	WorldManager.free_blocks_changed.emit()
	_broken_free.append({"fb": copy, "respawn": BLOCK_RESPAWN})
	if net_break_cb.is_valid():
		net_break_cb.call("fb", (copy.pos as Vector2).x, (copy.pos as Vector2).y)
	play_sfx("explode", c, 0.1, 1.5)
	spawn_ring(c, Color(1.0, 0.55, 0.2), 3.0, 22.0, 0.22)
	for _i in range(12):
		var dang: float = randf() * TAU
		_fx.append({
			"pos": c, "vel": Vector2.from_angle(dang) * randf_range(40.0, 220.0),
			"life": randf_range(0.15, 0.4), "max_life": 0.4,
			"color": Color(0.25, 0.18, 0.2).lerp(Color(1.0, 0.5, 0.2), randf() * 0.7),
			"size": randf_range(1.5, 3.2),
		})
	GameState.cam_shake += 1.5
	return true


func damage_curve(idx: int, at: Vector2, amount: float) -> bool:
	## Beams cook CURVES too — they're terrain. A whole curve takes
	## CURVE_BREAK_TIME of sustained fire, then shatters along its full
	## length (debris down the spline) and re-materializes later.
	if idx < 0 or idx >= WorldManager.polylines.size():
		return false
	var poly: Dictionary = WorldManager.polylines[idx]
	var pts: PackedVector2Array = poly.points
	if pts.size() < 2:
		return false
	var ckey: Vector2i = Vector2i(pts[0])  # stable identity across index shifts
	var dmg: float = float(_curve_dmg.get(ckey, 0.0)) + amount
	_curve_cooked_now[ckey] = true
	if randf() < amount * 30.0:
		_fx.append({
			"pos": at + Vector2(randf_range(-6.0, 6.0), randf_range(-6.0, 6.0)),
			"vel": Vector2(randf_range(-30.0, 30.0), randf_range(-70.0, -20.0)),
			"life": randf_range(0.12, 0.3), "max_life": 0.3,
			"color": Color(1.0, randf_range(0.35, 0.6), 0.15), "size": randf_range(1.0, 2.2),
		})
	if dmg < CURVE_BREAK_TIME:
		_curve_dmg[ckey] = dmg
		return false
	_curve_dmg.erase(ckey)
	var data: Dictionary = WorldManager.shatter_polyline(idx)
	if data.is_empty():
		return false
	data["respawn"] = BLOCK_RESPAWN
	_broken_curves.append(data)
	if net_break_cb.is_valid():
		net_break_cb.call("curve", at.x, at.y)
	# Debris storm down the whole spline
	var ap: PackedVector2Array = data.get("all_points", PackedVector2Array())
	for pi in range(0, ap.size(), 8):
		var dp: Vector2 = ap[pi]
		_fx.append({
			"pos": dp, "vel": Vector2(randf_range(-120.0, 120.0), randf_range(-200.0, -30.0)),
			"life": randf_range(0.2, 0.5), "max_life": 0.5,
			"color": Color(0.25, 0.18, 0.2).lerp(Color(1.0, 0.5, 0.2), randf() * 0.7),
			"size": randf_range(1.5, 3.4),
		})
	play_sfx("explode", at, 0.12, 1.1)
	spawn_ring(at, Color(1.0, 0.55, 0.2), 4.0, 30.0, 0.3)
	GameState.cam_shake += 4.0
	return true


func draw_player_slots(ci: CanvasItem, origin: Vector2) -> void:
	## The 1-2-3 inventory bar: current slot highlighted, the DOOM RAY
	## flashes slot 2 when it lands so you always KNOW what you're carrying.
	if not _actors.has("player"):
		return
	var a: Dictionary = _actors["player"]
	var font: Font = ThemeDB.fallback_font
	var bw: float = 40.0
	var bh: float = 32.0
	var gap: float = 6.0
	for k in range(3):
		var slot: int = k + 1
		var r: Rect2 = Rect2(origin.x + float(k) * (bw + gap), origin.y, bw, bh)
		var cur: bool = a.get("cur_slot", 1) == slot
		var w: String = "fists" if slot == 1 else slot_weapon("player", slot)
		var col: Color
		if w == "doom":
			col = WEAPONS.doom.color
		elif w == "blaster":
			col = WEAPONS.blaster.color
		elif w == "scatter":
			col = WEAPONS.scatter.color
		elif w == "fists":
			col = Color(0.65, 0.7, 0.85)
		else:
			col = Color(0.3, 0.32, 0.4)
		ci.draw_rect(r, Color(0.06, 0.06, 0.1, 0.88))
		if cur:
			ci.draw_rect(Rect2(r.position + Vector2(2, 2), r.size - Vector2(4, 4)), Color(col.r, col.g, col.b, 0.14))
			ci.draw_rect(r, Color(1, 1, 1, 0.95), false, 2.0)
		else:
			ci.draw_rect(r, Color(col.r, col.g, col.b, 0.55 if w != "" else 0.25), false, 1.0)
		if slot == 2 and a.get("slot2_flash", 0.0) > 0.0:
			var fl: float = 0.5 + 0.5 * sin(_time * 18.0)
			ci.draw_rect(Rect2(r.position - Vector2(2, 2), r.size + Vector2(4, 4)), Color(1.0, 0.45, 0.15, 0.4 + 0.5 * fl), false, 2.5)
		ci.draw_string(font, r.position + Vector2(3.0, 10.0), str(slot), HORIZONTAL_ALIGNMENT_LEFT, -1, 9, Color(0.75, 0.78, 0.9, 0.9))
		var cctr: Vector2 = r.get_center() + Vector2(2.0, 2.0)
		if w == "fists":
			ci.draw_circle(cctr, 5.0, Color(0.85, 0.88, 1.0))
			for j in range(3):
				var ja: float = -0.5 + float(j) * 0.5
				ci.draw_line(cctr + Vector2(6, 0).rotated(ja), cctr + Vector2(10, 0).rotated(ja), Color(0.85, 0.88, 1.0, 0.8), 1.5)
		elif w == "doom":
			ci.draw_line(cctr + Vector2(-9, 0), cctr + Vector2(9, 0), Color(1.0, 0.3, 0.1, 0.5), 7.0)
			ci.draw_line(cctr + Vector2(-9, 0), cctr + Vector2(9, 0), Color(1.0, 0.7, 0.3), 3.0)
			var frac: float = clampf(a.get("super_left", 0.0) / WEAPONS.doom.get("duration", 10.0), 0.0, 1.0)
			ci.draw_rect(Rect2(r.position.x + 3.0, r.end.y - 5.0, (bw - 6.0) * frac, 2.5), Color(1.0, 0.55, 0.2))
		elif w != "":
			ci.draw_line(cctr + Vector2(-8, 2), cctr + Vector2(6, 2), col, 3.0)
			ci.draw_line(cctr + Vector2(2, 2), cctr + Vector2(2, -3), col, 2.0)
			if w == "scatter":
				for j in range(3):
					ci.draw_line(cctr + Vector2(6, 2), cctr + Vector2(11, -2 + float(j) * 4.0), Color(col.r, col.g, col.b, 0.8), 1.2)
		else:
			ci.draw_line(cctr + Vector2(-4, 0), cctr + Vector2(4, 0), Color(0.4, 0.42, 0.5), 1.5)


func _hashf(n: int) -> float:
	return fmod(absf(sin(float(n) * 12.9898) * 43758.5453), 1.0)


func _draw_block_cracks() -> void:
	## Damage overlay on cooking blocks: heat glow + jagged cracks that
	## multiply and ignite as the block nears shattering.
	for key in _block_dmg:
		var f: float = clampf(_block_dmg[key] / BLOCK_BREAK_TIME, 0.0, 1.0)
		var bx: float = key.x * 16.0
		var by: float = key.y * 16.0
		var cpos: Vector2 = Vector2(bx + 8.0, by + 8.0)
		draw_rect(Rect2(bx, by, 16, 16), Color(1.0, 0.35, 0.12, 0.1 + 0.3 * f))
		var n: int = 2 + int(f * 3.0)
		for k in range(n):
			var h1: float = _hashf(key.x * 7 + key.y * 13 + k * 31)
			var h2: float = _hashf(key.x * 17 + key.y * 5 + k * 47)
			var h3: float = _hashf(key.x * 29 + key.y * 23 + k * 11)
			var a0: float = h1 * TAU
			var p0: Vector2 = cpos + Vector2.from_angle(a0) * 1.5
			var p1: Vector2 = cpos + Vector2.from_angle(a0 + (h2 - 0.5) * 1.2) * (4.5 + 4.0 * h3)
			var p2: Vector2 = cpos + Vector2.from_angle(a0 + (h2 - 0.5) * 2.2) * 8.5
			var ccol: Color = Color(0.06, 0.02, 0.02, 0.5 + 0.45 * f)
			draw_line(p0, p1, ccol, 1.3)
			draw_line(p1, p2, ccol, 1.0)
			if f > 0.6:
				draw_line(p0, p1, Color(1.0, 0.55, 0.2, (f - 0.6) * 1.8), 0.7)
		if f > 0.85:
			draw_rect(Rect2(bx, by, 16, 16), Color(1.0, 0.9, 0.7, (f - 0.85) * 2.2), false, 1.5)


# ── FX helpers ────────────────────────────────────────────────────────────────

func spawn_explosion(pos: Vector2, color: Color) -> void:
	for _i in range(46):
		var ang: float = randf() * TAU
		var spd: float = randf_range(60.0, 420.0)
		_fx.append({
			"pos": pos, "vel": Vector2.from_angle(ang) * spd,
			"life": randf_range(0.15, 0.55), "max_life": 0.55,
			"color": color.lerp(Color(1, 0.9, 0.5), randf() * 0.6),
			"size": randf_range(1.5, 4.0),
		})
	_fx.append({
		"pos": pos, "vel": Vector2.ZERO, "life": 0.1, "max_life": 0.1,
		"color": Color(1, 1, 1), "size": 16.0,
	})
	play_sfx("explode", pos)
	GameState.cam_shake += 7.0


func spawn_hit(pos: Vector2, color: Color, dir: Vector2) -> void:
	for _i in range(10):
		var sdir: Vector2 = (-dir).rotated(randf_range(-0.8, 0.8))
		_fx.append({
			"pos": pos, "vel": sdir * randf_range(80.0, 280.0),
			"life": randf_range(0.08, 0.22), "max_life": 0.22,
			"color": color, "size": randf_range(1.2, 2.6),
		})


func spawn_trail_dot(pos: Vector2, vel: Vector2, color: Color) -> void:
	_fx.append({
		"pos": pos, "vel": vel, "life": randf_range(0.08, 0.2), "max_life": 0.2,
		"color": color, "size": randf_range(1.0, 2.2),
	})


func spawn_ring(pos: Vector2, color: Color, r0: float = 6.0, r1: float = 30.0, life: float = 0.25) -> void:
	## Expanding shockwave ring (parries, impacts, materializations).
	_fx.append({
		"pos": pos, "vel": Vector2.ZERO, "life": life, "max_life": life,
		"color": color, "size": 0.0, "ring": true, "r0": r0, "r1": r1,
	})


func play_sfx(name: String, pos: Vector2, pitch_jitter: float = 0.08, pitch_base: float = 1.0) -> void:
	if not _sfx.has(name):
		return
	var p: AudioStreamPlayer2D = _sfx_pool[_sfx_next]
	_sfx_next = (_sfx_next + 1) % _sfx_pool.size()
	p.stream = _sfx[name]
	p.global_position = pos
	p.pitch_scale = pitch_base + randf_range(-pitch_jitter, pitch_jitter)
	p.play()


# ── Simulation ────────────────────────────────────────────────────────────────

func _process(delta: float) -> void:
	_time += delta
	# Cracked-but-unbroken blocks slowly heal once nothing is cooking them
	for key in _block_dmg.keys():
		if not _cooked_now.has(key):
			_block_dmg[key] -= delta * 0.25
			if _block_dmg[key] <= 0.0:
				_block_dmg.erase(key)
	_cooked_now.clear()
	# Cooked curves + free blocks heal the same way
	for ck in _curve_dmg.keys():
		if not _curve_cooked_now.has(ck):
			_curve_dmg[ck] -= delta * 0.25
			if _curve_dmg[ck] <= 0.0:
				_curve_dmg.erase(ck)
	_curve_cooked_now.clear()
	for cfb in WorldManager.free_blocks:
		if cfb is Dictionary and cfb.has("_dmg"):
			if cfb.get("_cooked_now", false):
				cfb.erase("_cooked_now")
			else:
				cfb["_dmg"] = float(cfb["_dmg"]) - delta * 0.25
				if float(cfb["_dmg"]) <= 0.0:
					cfb.erase("_dmg")
	# Shattered terrain re-materializes — but never inside a ball
	for bi in range(_broken.size() - 1, -1, -1):
		var br: Dictionary = _broken[bi]
		br.respawn -= delta
		if br.respawn > 0.0:
			continue
		var rc: Vector2 = Vector2(br.x * 16.0 + 8.0, br.y * 16.0 + 8.0)
		var blocked: bool = false
		for aid in _actors:
			var ar: Dictionary = _actors[aid]
			if ar.is_alive.call() and ar.get_center.call().distance_to(rc) < ar.get("hit_radius", ACTOR_RADIUS) + 14.0:
				blocked = true
				break
		if blocked:
			br.respawn = 0.4
			continue
		if WorldManager.get_tile(br.x, br.y) == 0:
			WorldManager.fg_tiles[br.y][br.x] = br.id
			WorldManager.tile_changed.emit(br.x, br.y, br.id)
			spawn_ring(rc, Color(0.6, 0.9, 1.0), 2.0, 15.0, 0.25)
			for _i in range(6):
				var sang: float = randf() * TAU
				_fx.append({
					"pos": rc + Vector2.from_angle(sang) * 10.0, "vel": Vector2.from_angle(sang) * -42.0,
					"life": 0.2, "max_life": 0.2, "color": Color(0.6, 0.9, 1.0), "size": 1.5,
				})
		_broken.remove_at(bi)
	# Shattered free blocks re-materialize — same never-inside-a-ball rule
	for fi in range(_broken_free.size() - 1, -1, -1):
		var bf: Dictionary = _broken_free[fi]
		bf.respawn -= delta
		if bf.respawn > 0.0:
			continue
		var fc: Vector2 = (bf.fb.pos as Vector2) + Vector2(8, 8)
		var fblocked: bool = false
		for aid2 in _actors:
			var ar2: Dictionary = _actors[aid2]
			if ar2.is_alive.call() and ar2.get_center.call().distance_to(fc) < ar2.get("hit_radius", ACTOR_RADIUS) + 14.0:
				fblocked = true
				break
		if fblocked:
			bf.respawn = 0.4
			continue
		WorldManager.free_blocks.append(bf.fb)
		WorldManager.free_blocks_changed.emit()
		spawn_ring(fc, Color(0.6, 0.9, 1.0), 2.0, 15.0, 0.25)
		_broken_free.remove_at(fi)
	# Shattered curves re-materialize (never onto a ball anywhere along them)
	for ci2 in range(_broken_curves.size() - 1, -1, -1):
		var bc: Dictionary = _broken_curves[ci2]
		bc.respawn -= delta
		if bc.respawn > 0.0:
			continue
		var cblocked: bool = false
		var capts: PackedVector2Array = bc.get("all_points", PackedVector2Array())
		for aid3 in _actors:
			var ar3: Dictionary = _actors[aid3]
			if not ar3.is_alive.call():
				continue
			var acp: Vector2 = ar3.get_center.call()
			var rad: float = ar3.get("hit_radius", ACTOR_RADIUS) + 14.0
			for pi2 in range(0, capts.size(), 4):
				if capts[pi2].distance_to(acp) < rad:
					cblocked = true
					break
			if cblocked:
				break
		if cblocked:
			bc.respawn = 0.4
			continue
		for pd in bc.polys:
			WorldManager.add_polyline(pd.points, pd.side, pd.block_id, pd.uv_offset)
		if capts.size() > 0:
			var midp: Vector2 = capts[capts.size() >> 1]
			spawn_ring(midp, Color(0.6, 0.9, 1.0), 4.0, 24.0, 0.3)
			play_sfx("pickup", midp, 0.04, 0.9)
		_broken_curves.remove_at(ci2)
	# Random ability drops: spawn an orb, let the PLAYER claim it
	if ability_spots.size() > 0:
		if _abil_orb.is_empty():
			_abil_timer -= delta
			if _abil_timer <= 0.0:
				_abil_timer = randf_range(16.0, 24.0)
				var kinds: Array = ABILITIES.keys()
				_abil_orb = {
					"pos": ability_spots[randi() % ability_spots.size()],
					"kind": kinds[randi() % kinds.size()], "life": 12.0,
				}
				spawn_ring(_abil_orb.pos, ABILITIES[_abil_orb.kind].color, 4.0, 30.0, 0.35)
				play_sfx("pickup", _abil_orb.pos, 0.05, 1.6)
		else:
			_abil_orb.life -= delta
			if _abil_orb.life <= 0.0:
				spawn_ring(_abil_orb.pos, Color(0.5, 0.5, 0.6), 12.0, 2.0, 0.3)
				_abil_orb = {}
			elif _actors.has("player"):
				var pab: Dictionary = _actors["player"]
				if pab.is_alive.call() and pab.get_center.call().distance_to(_abil_orb.pos) < 20.0:
					var kind: String = _abil_orb.kind
					var dur: float = ABILITIES[kind].dur
					if kind == "zerog":
						pab.abil_fly = dur
					elif kind == "overdrive":
						pab.abil_od = dur
					else:
						pab.abil_regen = dur
					spawn_explosion(_abil_orb.pos, ABILITIES[kind].color)
					spawn_ring(_abil_orb.pos, ABILITIES[kind].color, 6.0, 44.0, 0.35)
					play_sfx("pickup", _abil_orb.pos, 0.03, 1.3)
					ability_picked.emit(kind)
					_abil_orb = {}
	# Cooldowns + timed weapons (the DOOM RAY expires)
	for id in _actors:
		var a: Dictionary = _actors[id]
		if a.cooldown > 0.0:
			a.cooldown = maxf(0.0, a.cooldown - delta)
		# Timed weapons: the DOOM RAY burns out after exactly 10s.
		# (This block previously sat inside the dash-contact loop, whose
		# early `continue` skipped it for anyone not mid-dash — the doom
		# never expired at all.)
		# The DOOM RAY's 10s is FIRE TIME — it only burns while the beam is
		# actually on. Stow it or hold your fire to SAVE it for the moment.
		if a.get("super_left", 0.0) > 0.0:
			if a.weapon == "doom" and a.get("beam_draw", false):
				a.super_left -= delta
			if a.weapon == "doom":
				a.weapon_left = a.super_left
			if a.super_left <= 0.0:
				var fizzle_c: Vector2 = a.get_center.call()
				for _i in range(16):
					var fang: float = randf() * TAU
					_fx.append({
						"pos": fizzle_c, "vel": Vector2.from_angle(fang) * randf_range(30.0, 140.0),
						"life": randf_range(0.1, 0.3), "max_life": 0.3,
						"color": WEAPONS.doom.color, "size": randf_range(1.0, 2.4),
					})
				play_sfx("pickup", fizzle_c, 0.02)
				if a.weapon == "doom":
					# Slot 2 reverts to its base gun (or fists without loadout)
					a.beam_on = false
					a.weapon = slot_weapon(id, 2)
					a.weapon_left = -1.0
					if a.weapon == "":
						a.cur_slot = 1
		if a.get("slot2_flash", 0.0) > 0.0:
			a.slot2_flash = maxf(0.0, a.slot2_flash - delta)
		# Ability timers
		if a.get("abil_fly", 0.0) > 0.0:
			a.abil_fly = maxf(0.0, a.abil_fly - delta)
		if a.get("abil_od", 0.0) > 0.0:
			a.abil_od = maxf(0.0, a.abil_od - delta)
		if a.get("abil_regen", 0.0) > 0.0:
			a.abil_regen = maxf(0.0, a.abil_regen - delta)
		# Melee kit timers
		if a.dash_cd > 0.0:
			a.dash_cd = maxf(0.0, a.dash_cd - delta)
		if a.dash_time > 0.0:
			a.dash_time = maxf(0.0, a.dash_time - delta)
		if a.stun_left > 0.0:
			a.stun_left = maxf(0.0, a.stun_left - delta)
		if a.shield_lock > 0.0:
			a.shield_lock = maxf(0.0, a.shield_lock - delta)
		# Charge decays instantly if not held this frame — except on online
		# mirror actors, whose charge is replicated at 20Hz (not per-frame)
		if a.charging and not a.charge_fed and not a.get("net_mirror", false):
			a.charging = false
			a.charge = 0.0
		a.charge_fed = false
		# Delayed parry stun: kicks in when the launched striker hits the floor
		if a.stun_pending and not a.get_grounded.is_null() and a.get_grounded.call():
			a.stun_pending = false
			a.stun_left = STUN_TIME
			spawn_ring(a.get_center.call(), Color(1.0, 0.9, 0.3), 3.0, 15.0, 0.2)
			play_sfx("hit", a.get_center.call(), 0.05, 0.75)
		# Shield: only while unarmed, drains on use, regens when down.
		# BREAKS at empty and needs a FULL recharge (2s) before it can come
		# back up. Attacking (dash) drops it and locks it briefly.
		var was_shielded: bool = a.shield_on
		if a.shield_broken and a.shield_energy >= SHIELD_MAX:
			a.shield_broken = false
		a.shield_on = a.shield_req and not a.shield_broken and a.shield_lock <= 0.0 and a.stun_left <= 0.0 and not a.stun_pending and a.shield_energy > 0.0 and a.is_alive.call()
		if a.shield_on and not was_shielded:
			a.shield_time = 0.0  # Fresh raise — the timed-parry window starts now
			play_sfx("pickup", a.get_center.call(), 0.03, 0.7)  # Shield hum-up
			spawn_ring(a.get_center.call(), Color(0.5, 0.9, 1.0), 4.0, 15.0, 0.15)
		if a.shield_on:
			a.shield_time += delta
			a.shield_energy = maxf(0.0, a.shield_energy - delta)
			if a.shield_energy <= 0.0:
				a.shield_broken = true
				a.shield_on = false
				play_sfx("hit", a.get_center.call(), 0.05, 0.55)  # Shield SHATTERS
				spawn_ring(a.get_center.call(), Color(0.4, 0.6, 0.8), 14.0, 4.0, 0.22)
				for _i in range(8):
					var shard_ang: float = randf() * TAU
					_fx.append({
						"pos": a.get_center.call(), "vel": Vector2.from_angle(shard_ang) * randf_range(50.0, 150.0),
						"life": randf_range(0.1, 0.25), "max_life": 0.25,
						"color": Color(0.5, 0.8, 1.0), "size": randf_range(1.2, 2.4),
					})
		else:
			a.shield_energy = minf(SHIELD_MAX, a.shield_energy + delta * (1.8 if a.get("abil_od", 0.0) > 0.0 else 0.6))
		# Dash afterimages: a bright motion trail while the punch window is live
		if a.dash_time > 0.0 and a.is_alive.call():
			var dc: Vector2 = a.get_center.call()
			_fx.append({
				"pos": dc, "vel": Vector2.ZERO, "life": 0.16, "max_life": 0.16,
				"color": Color(0.55, 0.85, 1.0), "size": 6.0,
			})
	# Dash contact: damage on touch, or get PARRIED by a raised shield
	for id in _actors:
		var a: Dictionary = _actors[id]
		if a.dash_time <= 0.0 or not a.is_alive.call():
			continue
		var ac: Vector2 = a.get_center.call()
		for vid in _actors:
			var v: Dictionary = _actors[vid]
			if v.team == a.team or not v.is_alive.call():
				continue
			# Big actors (the boss) resolve dash contact in their own mode code
			if v.get("hit_radius", ACTOR_RADIUS) > 20.0:
				continue
			var vc: Vector2 = v.get_center.call()
			# 20px, NOT 16: the body-collision separation holds balls at
			# exactly 16px apart, which kept dash punches permanently out of
			# range — every landed dash was a 0-damage shove.
			if ac.distance_to(vc) < 20.0:
				a.dash_time = 0.0
				if v.shield_on:
					# The shield ALWAYS takes the whole dash and throws it
					# straight back — full momentum redirect off the shield
					# face (with a lift). But only a TIMED parry (shield went
					# up within PARRY_WINDOW) stuns the attacker. A pre-held
					# shield is just a wall: the dash bounces off and the
					# BLOCK costs the holder a big chunk of shield energy —
					# holding shield and walking into people is defense now,
					# not a free-stun button (that was pure cheese).
					var away: Vector2 = (ac - vc).normalized()
					if not a.push.is_null():
						var vel_ee: Vector2 = a.get_vel.call() / (EEPhysics.EE_TICK_FRAC * EEPhysics.TPS)
						var mag: float = maxf(vel_ee.length() * 1.2, 8.0)
						a.push.call(away * mag + Vector2(0.0, -3.0) - vel_ee)
					if v.get("shield_time", 999.0) <= PARRY_WINDOW:
						_stun_team(a.team, (ac + vc) * 0.5, true)
					else:
						v.shield_energy = maxf(0.0, v.shield_energy - 1.0)
						spawn_hit((ac + vc) * 0.5, Color(0.6, 0.95, 1.0), away)
						spawn_ring((ac + vc) * 0.5, Color(0.6, 0.95, 1.0), 4.0, 14.0, 0.14)
						play_sfx("bonk", (ac + vc) * 0.5, 0.08, 1.55)
				else:
					v.hurt.call(a.dash_dmg, (vc - ac).normalized())
					spawn_hit((ac + vc) * 0.5, Color(0.7, 0.95, 1.0), (vc - ac).normalized())
					spawn_ring((ac + vc) * 0.5, Color(0.7, 0.95, 1.0), 4.0, 20.0 + a.dash_dmg * 6.0, 0.2)
					play_sfx("hit", vc)
					GameState.cam_shake += 3.0 + a.dash_dmg * 1.5
				break
	# Super weapon cycle: countdown -> materialize animation -> pad on field
	if super_pos != Vector2.ZERO:
		if _super_state == 0:
			_super_timer -= delta
			if _super_timer <= 0.0:
				_super_state = 1
				_super_anim = SUPER_ANIM_TIME
				play_sfx("doom_spawn", super_pos, 0.0)
		elif _super_state == 1:
			_super_anim -= delta
			# Converging energy: particles spiral into the spawn point
			var burst: int = clampi(int(delta * 260.0), 2, 14)
			for _i in range(burst):
				var sang: float = randf() * TAU
				var r: float = randf_range(50.0, 150.0)
				var p: Vector2 = super_pos + Vector2.from_angle(sang) * r
				_fx.append({
					"pos": p, "vel": (super_pos - p) / maxf(_super_anim, 0.25),
					"life": randf_range(0.15, minf(_super_anim + 0.1, 0.5)), "max_life": 0.5,
					"color": Color(1.0, 0.25, 0.15).lerp(Color(1, 0.8, 0.4), randf()),
					"size": randf_range(1.2, 3.0),
				})
			GameState.cam_shake = maxf(GameState.cam_shake, 1.5 * (1.0 - _super_anim / SUPER_ANIM_TIME))
			if _super_anim <= 0.0:
				_super_state = 2
				_pads.append({"pos": super_pos, "weapon": "doom", "respawn_left": 0.0, "phase": 0.0, "super": true})
				spawn_explosion(super_pos, Color(1.0, 0.3, 0.15))
				spawn_ring(super_pos, Color(1.0, 0.4, 0.2), 8.0, 60.0, 0.45)
				spawn_ring(super_pos, Color(1.0, 0.8, 0.5), 4.0, 34.0, 0.3)
	# Pickups
	for pi in range(_pads.size() - 1, -1, -1):
		var pad: Dictionary = _pads[pi]
		if pad.respawn_left > 0.0:
			pad.respawn_left = maxf(0.0, pad.respawn_left - delta)
			continue
		for id in _actors:
			var a: Dictionary = _actors[id]
			if not a.is_alive.call() or a.get("no_pickup", false):
				continue
			var c: Vector2 = a.get_center.call()
			if c.distance_to(pad.pos) < PICKUP_RADIUS:
				give_weapon(id, pad.weapon)
				play_sfx("pickup", pad.pos, 0.03)
				var wcol: Color = WEAPONS[pad.weapon].color
				for _i in range(14):
					var ang: float = randf() * TAU
					_fx.append({
						"pos": pad.pos, "vel": Vector2.from_angle(ang) * randf_range(50.0, 180.0),
						"life": randf_range(0.15, 0.35), "max_life": 0.35,
						"color": wcol, "size": randf_range(1.2, 2.6),
					})
				if pad.get("super", false):
					# Supers don't refill in place — restart the 60s cycle
					_pads.remove_at(pi)
					_super_state = 0
					_super_timer = SUPER_PERIOD
				else:
					pad.respawn_left = PICKUP_RESPAWN
				break
	# DOOM RAY beams: raycast, continuous damage ticks, heavy presence.
	# beam_on is a per-frame request (re-issued by holders every frame);
	# beam_draw is what _draw renders this frame.
	var any_beam: bool = false
	for id in _actors:
		_actors[id]["beam_draw"] = false
	for id in _actors:
		var a: Dictionary = _actors[id]
		if not a.beam_on:
			continue
		a.beam_on = false
		if a.weapon == "" or not WEAPONS[a.weapon].get("beam", false) or not a.is_alive.call():
			continue
		a.beam_draw = true
		any_beam = true
		var w: Dictionary = WEAPONS[a.weapon]
		var from: Vector2 = a.get_center.call() + a.aim * 16.0
		var beam_end: Vector2 = from
		var victim: Dictionary = {}
		var shielded_victim: Dictionary = {}
		var shielded_vid: String = ""
		var steps: int = int(w.range / 6.0)
		# Beam-vs-beam: if the Warden's laser crossed this ray last frame,
		# the two annihilate — this ray stops at the crossing
		var cut_d: float = a.get("beam_cut", -1.0)
		for s in range(steps):
			if cut_d > 0.0 and s * 6.0 >= cut_d:
				beam_end = from + a.aim * cut_d
				break
			beam_end = from + a.aim * (s * 6.0)
			var mtx: int = int(floor(beam_end.x / 16.0))
			var mty: int = int(floor(beam_end.y / 16.0))
			if WorldManager.is_solid_at(mtx, mty):
				damage_block(mtx, mty, delta)  # The ray COOKS the wall it hits
				break
			# The ray is stopped by ALL terrain — free blocks and curves too
			# (it used to sail straight through them), and cooks them the
			# same way it cooks grid tiles.
			var fbi: int = WorldManager.free_block_at_point(beam_end)
			if fbi >= 0:
				damage_free_block(fbi, delta)
				break
			var cvi: int = WorldManager.curve_at_point(beam_end)
			if cvi >= 0:
				damage_curve(cvi, beam_end, delta)
				break
			for vid in _actors:
				var v: Dictionary = _actors[vid]
				if v.team == a.team or not v.is_alive.call():
					continue
				# Fat beam: ~3 smiley widths — generous hit corridor (scales
				# up for big-bodied actors like the boss)
				var corr: float = 16.0 + v.get("hit_radius", ACTOR_RADIUS)
				if v.get_center.call().distance_squared_to(beam_end) < corr * corr:
					if v.shield_on:
						# The ray SHATTERS on a raised shield: it stops at the
						# clash point and a deflected column splits off it
						shielded_victim = v
						shielded_vid = vid
					else:
						victim = v
			if not victim.is_empty() or not shielded_victim.is_empty():
				break
		# SHIELD SPLIT: reflect the ray off the shield bubble. WHERE the beam
		# axis strikes the bubble decides the deflection — edge grazes carom
		# off shallow, a dead-center hit fires the ray STRAIGHT BACK at the
		# shooter. The deflected column is live and hurts anyone in it.
		var split_from: Vector2 = Vector2.ZERO
		var split_to: Vector2 = Vector2.ZERO
		var split_dir: Vector2 = Vector2.ZERO
		if not shielded_victim.is_empty():
			var svc0: Vector2 = shielded_victim.get_center.call()
			var srad: float = 15.0
			var oc: Vector2 = from - svc0
			var bq: float = oc.dot(a.aim)
			var disc: float = bq * bq - (oc.length_squared() - srad * srad)
			var hit_pt: Vector2
			var nrm: Vector2
			if disc > 0.0:
				var t_hit: float = maxf(-bq - sqrt(disc), 0.0)
				hit_pt = from + a.aim * t_hit
				nrm = (hit_pt - svc0).normalized()
			else:
				# The axis skims past the bubble — deflect outward off the near side
				var t_c: float = clampf((svc0 - from).dot(a.aim), 0.0, w.range)
				hit_pt = from + a.aim * t_c
				nrm = (hit_pt - svc0).normalized()
			if nrm == Vector2.ZERO:
				nrm = -a.aim
			split_dir = (a.aim - 2.0 * a.aim.dot(nrm) * nrm).normalized()
			beam_end = hit_pt
			split_from = hit_pt
			split_to = hit_pt
			for s2 in range(steps):
				split_to = hit_pt + split_dir * (s2 * 6.0)
				var stx: int = int(floor(split_to.x / 16.0))
				var sty: int = int(floor(split_to.y / 16.0))
				if WorldManager.is_solid_at(stx, sty):
					damage_block(stx, sty, delta)  # The deflected column cooks too
					break
				var sfbi: int = WorldManager.free_block_at_point(split_to)
				if sfbi >= 0:
					damage_free_block(sfbi, delta)
					break
				var scvi: int = WorldManager.curve_at_point(split_to)
				if scvi >= 0:
					damage_curve(scvi, split_to, delta)
					break
		a.beam_end = beam_end
		a["beam_pin"] = shielded_victim.get_center.call() if not shielded_victim.is_empty() else Vector2.ZERO
		a["beam_split_from"] = split_from
		a["beam_split_to"] = split_to
		# The ray VAPORIZES enemy projectiles caught in the column
		for pi2 in range(_projectiles.size() - 1, -1, -1):
			var prj: Dictionary = _projectiles[pi2]
			if prj.team == a.team:
				continue
			var bseg2: Vector2 = beam_end - from
			if bseg2.length_squared() < 1.0:
				continue
			var pt2: float = clampf((prj.pos - from).dot(bseg2) / bseg2.length_squared(), 0.0, 1.0)
			if prj.pos.distance_squared_to(from + bseg2 * pt2) < 676.0:
				spawn_hit(prj.pos, prj.color, Vector2.UP)
				spawn_ring(prj.pos, prj.color, 2.0, 12.0, 0.15)
				_projectiles.remove_at(pi2)
		# Sparks along the beam + at the impact point
		if randf() < delta * 240.0:
			var bt: float = randf()
			_fx.append({
				"pos": from.lerp(beam_end, bt), "vel": Vector2(randf_range(-40, 40), randf_range(-40, 40)),
				"life": randf_range(0.05, 0.14), "max_life": 0.14,
				"color": Color(1.0, randf_range(0.3, 0.8), 0.2), "size": randf_range(1.0, 2.4),
			})
		spawn_hit(beam_end, Color(1.0, 0.4, 0.2), a.aim)
		GameState.cam_shake = maxf(GameState.cam_shake, 2.5)
		# UNSHIELDED target under the ray: SENT FLYING — continuous blast
		# force with an upward tumble bias, plus a storm of embers blown off
		# them down-beam. They ragdoll into the wall while burning.
		if not victim.is_empty():
			if not victim.push.is_null():
				victim.push.call((a.aim + Vector2(0.0, -0.22)).normalized() * delta * 30.0)
			var vc2: Vector2 = victim.get_center.call()
			if randf() < delta * 420.0:
				var ember_ang: float = randf() * TAU
				_fx.append({
					"pos": vc2 + Vector2.from_angle(ember_ang) * randf_range(2.0, 10.0),
					"vel": a.aim * randf_range(120.0, 320.0) + Vector2.from_angle(ember_ang) * 50.0,
					"life": randf_range(0.08, 0.22), "max_life": 0.22,
					"color": Color(1.0, randf_range(0.3, 0.7), 0.15), "size": randf_range(1.4, 3.2),
				})
			GameState.cam_shake = maxf(GameState.cam_shake, 4.5)
		# Shielded target under the beam: NO damage, NO stun — they HOLD the
		# clash point (light pressure only) while their shield cooks off, and
		# the ray fractures off the shield face as a live deflected column
		if not shielded_victim.is_empty():
			if not shielded_victim.push.is_null():
				shielded_victim.push.call(a.aim * delta * 12.0)
			shielded_victim.shield_energy = maxf(0.0, shielded_victim.shield_energy - delta * 1.2)
			if randf() < delta * 380.0:
				_fx.append({
					"pos": split_from,
					"vel": split_dir.rotated(randf_range(-0.55, 0.55)) * randf_range(140.0, 380.0),
					"life": randf_range(0.06, 0.18), "max_life": 0.18,
					"color": Color(0.7, 0.95, 1.0) if randf() < 0.5 else Color(1.0, 0.6, 0.25),
					"size": randf_range(1.2, 2.8),
				})
			GameState.cam_shake = maxf(GameState.cam_shake, 4.0)
			# Continuous blast force along the deflected column — anyone else
			# standing in it (the shooter included!) gets swept down-beam
			var sseg: Vector2 = split_to - split_from
			if sseg.length_squared() > 36.0:
				for vid2 in _actors:
					if vid2 == shielded_vid:
						continue
					var v2: Dictionary = _actors[vid2]
					if not v2.is_alive.call() or v2.push.is_null():
						continue
					var v2c: Vector2 = v2.get_center.call()
					var st: float = clampf((v2c - split_from).dot(sseg) / sseg.length_squared(), 0.0, 1.0)
					if v2c.distance_squared_to(split_from + sseg * st) < 676.0:
						v2.push.call((split_dir + Vector2(0.0, -0.22)).normalized() * delta * 30.0)
		a.beam_tick -= delta
		if a.beam_tick <= 0.0:
			a.beam_tick = w.tick
			if not victim.is_empty():
				victim.hurt.call(w.dmg, a.aim)
				var hitc: Vector2 = victim.get_center.call()
				play_sfx("hit", hitc)
				# Every damage tick is a mini-detonation on the victim
				spawn_ring(hitc, Color(1.0, 0.5, 0.2), 4.0, 24.0, 0.22)
				_fx.append({
					"pos": hitc, "vel": Vector2.ZERO, "life": 0.07, "max_life": 0.07,
					"color": Color(1, 1, 1), "size": 11.0,
				})
				for _bd in range(6):
					_fx.append({
						"pos": hitc, "vel": a.aim.rotated(randf_range(-0.7, 0.7)) * randf_range(140.0, 380.0),
						"life": randf_range(0.1, 0.24), "max_life": 0.24,
						"color": Color(1.0, 0.6, 0.2), "size": randf_range(1.5, 3.0),
					})
				GameState.cam_shake += 2.5
			# Deflected-column damage ticks: the defender's counter-ray cooks
			# anyone caught in it — including the original shooter
			if not shielded_victim.is_empty():
				var sseg2: Vector2 = split_to - split_from
				if sseg2.length_squared() > 36.0:
					for vid3 in _actors:
						if vid3 == shielded_vid:
							continue
						var v3: Dictionary = _actors[vid3]
						if not v3.is_alive.call():
							continue
						var v3c: Vector2 = v3.get_center.call()
						var st3: float = clampf((v3c - split_from).dot(sseg2) / sseg2.length_squared(), 0.0, 1.0)
						if v3c.distance_squared_to(split_from + sseg2 * st3) < 676.0:
							v3.hurt.call(w.dmg, split_dir)
							play_sfx("hit", v3c)
							spawn_ring(v3c, Color(1.0, 0.5, 0.2), 4.0, 24.0, 0.22)
							GameState.cam_shake += 2.0
	if _beam_audio and _beam_audio.stream:
		if any_beam and not _beam_audio.playing:
			_beam_audio.play()
		elif not any_beam and _beam_audio.playing:
			_beam_audio.stop()
	if any_beam:
		# Position the hum at the first active beam's muzzle
		for id in _actors:
			if _actors[id].get("beam_draw", false):
				_beam_audio.global_position = _actors[id].get_center.call()
				break
	# Projectiles (substepped so fast shots can't skip through walls/players)
	var world_max: Vector2 = Vector2(WorldManager.world_width * 16.0 + 64.0, WorldManager.world_height * 16.0 + 64.0)
	var i: int = _projectiles.size() - 1
	while i >= 0:
		var pr: Dictionary = _projectiles[i]
		pr.life -= delta
		var alive: bool = pr.life > 0.0
		if alive:
			var move: Vector2 = pr.vel * delta
			var steps: int = maxi(1, int(ceil(move.length() / 4.0)))
			for s in range(steps):
				pr.pos += move / float(steps)
				# Trail glow
				if randf() < 0.5:
					spawn_trail_dot(pr.pos, -pr.vel * 0.05, pr.color)
				# World bounds
				if pr.pos.x < -64.0 or pr.pos.y < -64.0 or pr.pos.x > world_max.x or pr.pos.y > world_max.y:
					alive = false
					break
				# Grid tiles
				if WorldManager.is_solid_at(int(floor(pr.pos.x / 16.0)), int(floor(pr.pos.y / 16.0))):
					spawn_hit(pr.pos, pr.color, pr.vel.normalized())
					play_sfx("hit", pr.pos)
					alive = false
					break
				# Curves
				if WorldManager.polylines.size() > 0 and WorldManager.dist_to_nearest_polyline(pr.pos.x, pr.pos.y) < CURVE_HIT_DIST:
					spawn_hit(pr.pos, pr.color, pr.vel.normalized())
					play_sfx("hit", pr.pos)
					alive = false
					break
				# Actors (enemy team only)
				for id in _actors:
					var a: Dictionary = _actors[id]
					if a.team == pr.team or not a.is_alive.call():
						continue
					var c: Vector2 = a.get_center.call()
					var hit_r: float = 14.0 if a.shield_on else a.get("hit_radius", ACTOR_RADIUS)
					if c.distance_squared_to(pr.pos) < hit_r * hit_r:
						if a.shield_on:
							# DEFLECT: bullets ricochet off shields — energized
							# (faster, longer-lived) and they SWITCH SIDES: a
							# deflected shot belongs to the defender and can hit
							# the one who fired it. No stun (dash parries only).
							var nrm: Vector2 = (pr.pos - c).normalized()
							if nrm.length() < 0.5:
								nrm = -pr.vel.normalized()
							pr.vel = pr.vel.bounce(nrm) * 1.35
							pr.pos = c + nrm * 18.0
							pr.life = minf(pr.life, 1.0)
							pr.team = a.team
							spawn_hit(pr.pos, Color(0.7, 0.95, 1.0), nrm)
							play_sfx("hit", pr.pos, 0.05, 1.35)
						elif pr.get("ghost", false):
							# Online replay: pops on contact, never damages —
							# the shooter's client owns the authoritative hit
							spawn_hit(pr.pos, pr.color, pr.vel.normalized())
							alive = false
						else:
							a.hurt.call(pr.dmg, pr.vel.normalized())
							spawn_hit(pr.pos, pr.color, pr.vel.normalized())
							play_sfx("hit", pr.pos)
							GameState.cam_shake += 2.0
							alive = false
						break
				if not alive:
					break
		if not alive:
			_projectiles.remove_at(i)
		i -= 1
	# FX particles
	var j: int = _fx.size() - 1
	while j >= 0:
		var f: Dictionary = _fx[j]
		f.life -= delta
		if f.life <= 0.0:
			_fx.remove_at(j)
		else:
			f.pos += f.vel * delta
			f.vel *= pow(0.04, delta)  # Strong drag, embers hang briefly
		j -= 1
	if _fx.size() > 1600:
		_fx.resize(1600)
	queue_redraw()


# ── Rendering ────────────────────────────────────────────────────────────────

func _draw() -> void:
	# Terrain damage overlay first — everything else layers above it
	_draw_block_cracks()
	# Ability orb: pulsing pickup with a kind-glyph
	if not _abil_orb.is_empty():
		var ap: Vector2 = _abil_orb.pos + Vector2(0.0, 3.0 * sin(_time * 3.2))
		var acol: Color = ABILITIES[_abil_orb.kind].color
		var apulse: float = 0.6 + 0.4 * sin(_time * 6.0)
		var fade: float = clampf(_abil_orb.life / 2.0, 0.25, 1.0)
		draw_circle(ap, 14.0 + 3.0 * apulse, Color(acol.r, acol.g, acol.b, 0.14 * fade))
		draw_arc(ap, 11.0, _time * 3.0, _time * 3.0 + TAU * 0.75, 20, Color(acol.r, acol.g, acol.b, 0.9 * fade), 2.0)
		draw_circle(ap, 7.0, Color(acol.r * 0.4, acol.g * 0.4, acol.b * 0.4, 0.9 * fade))
		if _abil_orb.kind == "zerog":
			for k in range(3):
				var da: float = _time * 2.0 + TAU * float(k) / 3.0
				draw_circle(ap + Vector2.from_angle(da) * 3.5, 1.6, Color(1, 1, 1, fade))
		elif _abil_orb.kind == "overdrive":
			draw_line(ap + Vector2(-3, -4), ap + Vector2(1, 0), Color(1, 1, 1, fade), 1.6)
			draw_line(ap + Vector2(1, 0), ap + Vector2(-1, 0), Color(1, 1, 1, fade), 1.6)
			draw_line(ap + Vector2(-1, 0), ap + Vector2(3, 4), Color(1, 1, 1, fade), 1.6)
		else:
			draw_line(ap + Vector2(-3.5, 0), ap + Vector2(3.5, 0), Color(1, 1, 1, fade), 2.0)
			draw_line(ap + Vector2(0, -3.5), ap + Vector2(0, 3.5), Color(1, 1, 1, fade), 2.0)
	# Super weapon materialization: growing ring + light pillar
	if _super_state == 1 and super_pos != Vector2.ZERO:
		var prog: float = 1.0 - _super_anim / SUPER_ANIM_TIME
		var scol: Color = Color(1.0, 0.3, 0.15)
		draw_arc(super_pos, 40.0 - 26.0 * prog, 0, TAU, 32, Color(scol.r, scol.g, scol.b, 0.25 + 0.6 * prog), 2.0 + 3.0 * prog)
		draw_rect(Rect2(super_pos.x - 1.5 - 2.0 * prog, super_pos.y - 220.0, 3.0 + 4.0 * prog, 220.0), Color(1.0, 0.5, 0.3, 0.12 + 0.3 * prog))
		draw_circle(super_pos, 4.0 + 8.0 * prog, Color(1, 0.8, 0.6, 0.5 * prog))
	# Pickup pads
	for pad in _pads:
		var w: Dictionary = WEAPONS[pad.weapon]
		var col: Color = w.color
		if pad.get("super", false):
			# The DOOM RAY pad: big double ring, fast pulse, light pillar
			var spulse: float = 0.5 + 0.5 * sin(_time * 7.0)
			draw_arc(pad.pos, 16.0 + spulse * 4.0, 0, TAU, 32, Color(1.0, 0.25, 0.15, 0.5 + 0.4 * spulse), 2.5)
			draw_arc(pad.pos, 24.0 + spulse * 2.0, 0, TAU, 32, Color(1.0, 0.6, 0.2, 0.25), 1.5)
			draw_rect(Rect2(pad.pos.x - 1.0, pad.pos.y - 180.0, 2.0, 180.0), Color(1.0, 0.4, 0.2, 0.1 + 0.1 * spulse))
			_draw_gun(pad.pos + Vector2(0, -8 + sin(_time * 3.0) * 3.0), Vector2.RIGHT, "doom", 1.1 + spulse * 0.15)
			continue
		if pad.respawn_left > 0.0:
			# Refilling: dim ring with progress arc
			var frac: float = 1.0 - pad.respawn_left / PICKUP_RESPAWN
			draw_arc(pad.pos, 11.0, 0, TAU, 24, Color(col.r, col.g, col.b, 0.18), 1.5)
			draw_arc(pad.pos, 11.0, -PI / 2.0, -PI / 2.0 + TAU * frac, 24, Color(col.r, col.g, col.b, 0.5), 1.5)
		else:
			var pulse: float = 0.6 + 0.4 * sin(_time * 4.0 + pad.phase)
			var bob: float = sin(_time * 2.4 + pad.phase) * 3.0
			draw_arc(pad.pos, 11.0 + pulse * 2.0, 0, TAU, 24, Color(col.r, col.g, col.b, 0.35 + 0.3 * pulse), 1.8)
			draw_circle(pad.pos, 3.0 + pulse * 1.5, Color(col.r, col.g, col.b, 0.25))
			_draw_gun(pad.pos + Vector2(0, -6 + bob), Vector2.RIGHT, pad.weapon, 1.0 + pulse * 0.12)
	# Guns held by actors
	for id in _actors:
		var a: Dictionary = _actors[id]
		if a.weapon == "" or not a.is_alive.call():
			continue
		var c: Vector2 = a.get_center.call()
		var gun_pos: Vector2 = c + a.aim * 14.0
		_draw_gun(gun_pos, a.aim, a.weapon, 1.0)
		# Charge glow while cooling down (rail feels chunky)
		if a.cooldown > 0.0 and WEAPONS[a.weapon].cooldown > 0.5:
			var readiness: float = 1.0 - a.cooldown / WEAPONS[a.weapon].cooldown
			var wcol: Color = WEAPONS[a.weapon].color
			draw_arc(c, 13.0, -PI / 2.0, -PI / 2.0 + TAU * readiness, 20, Color(wcol.r, wcol.g, wcol.b, 0.5), 1.2)
	# DOOM RAY beams: a ~3-smiley-wide annihilation column
	for id in _actors:
		var a: Dictionary = _actors[id]
		if not a.get("beam_draw", false):
			continue
		var from: Vector2 = a.get_center.call() + a.aim * 16.0
		var to: Vector2 = a.beam_end
		var flicker: float = 0.85 + 0.15 * sin(_time * 60.0)
		draw_line(from, to, Color(1.0, 0.15, 0.08, 0.28), 48.0 * flicker)
		draw_line(from, to, Color(1.0, 0.4, 0.12, 0.6), 27.0 * flicker)
		draw_line(from, to, Color(1.0, 0.75, 0.4, 0.9), 15.0 * flicker)
		draw_line(from, to, Color(1, 1, 0.92), 7.0)
		draw_circle(to, 13.0 + 6.0 * flicker, Color(1.0, 0.6, 0.3, 0.75))
		draw_circle(to, 7.0, Color(1, 1, 0.9))
		draw_circle(from, 8.0, Color(1, 1, 0.92))
		# Shielded target engulfed in the ray: anime-style silhouette — you
		# can see them holding on inside the column
		var pin: Vector2 = a.get("beam_pin", Vector2.ZERO)
		if pin != Vector2.ZERO:
			draw_circle(pin, 12.0, Color(1.0, 0.5, 0.2, 0.55))
			draw_arc(pin, 13.5, 0, TAU, 24, Color(1, 1, 1, 0.95), 2.5)
			draw_arc(pin, 17.0 + 2.0 * sin(_time * 22.0), 0, TAU, 24, Color(0.7, 0.95, 1.0, 0.8), 1.8)
			draw_circle(pin, 8.0, Color(0.08, 0.04, 0.06, 0.85))
		# Deflected branch off a shield: the split ray, slightly thinner, with
		# a white-hot clash flare where it fractures
		var sfrom: Vector2 = a.get("beam_split_from", Vector2.ZERO)
		var sto: Vector2 = a.get("beam_split_to", Vector2.ZERO)
		if sfrom.distance_squared_to(sto) > 36.0:
			draw_line(sfrom, sto, Color(1.0, 0.18, 0.1, 0.24), 36.0 * flicker)
			draw_line(sfrom, sto, Color(1.0, 0.45, 0.15, 0.55), 20.0 * flicker)
			draw_line(sfrom, sto, Color(1.0, 0.8, 0.45, 0.85), 11.0 * flicker)
			draw_line(sfrom, sto, Color(1, 1, 0.95), 5.0)
			draw_circle(sto, 10.0 + 5.0 * flicker, Color(1.0, 0.6, 0.3, 0.7))
			draw_circle(sto, 5.5, Color(1, 1, 0.9))
			draw_circle(sfrom, 10.0 + 3.0 * sin(_time * 40.0), Color(1.0, 1.0, 0.95, 0.9))
			draw_arc(sfrom, 15.0 + 3.0 * flicker, 0, TAU, 24, Color(0.7, 0.95, 1.0, 0.85), 2.2)
	# Shields and stun stars
	for id in _actors:
		var a: Dictionary = _actors[id]
		if not a.is_alive.call():
			continue
		var c: Vector2 = a.get_center.call()
		if a.shield_on:
			var sp: float = 0.6 + 0.4 * sin(_time * 10.0)
			var energy_frac: float = a.shield_energy / SHIELD_MAX
			draw_arc(c, 13.0, 0, TAU, 24, Color(0.5, 0.9, 1.0, 0.35 + 0.25 * sp), 2.2)
			draw_arc(c, 13.0, _time * 5.0, _time * 5.0 + TAU * 0.3, 10, Color(0.8, 1.0, 1.0, 0.8), 2.2)
			draw_arc(c, 16.0, -PI / 2.0, -PI / 2.0 + TAU * energy_frac, 20, Color(0.5, 0.9, 1.0, 0.4), 1.2)
		if a.stun_left > 0.0:
			for k in range(3):
				var sa: float = _time * 6.0 + k * TAU / 3.0
				var sp2: Vector2 = c + Vector2(cos(sa) * 11.0, -14.0 + sin(sa * 2.0) * 2.0)
				draw_circle(sp2, 1.6, Color(1.0, 0.9, 0.3))
		if a.charging and a.charge > 0.04:
			# Wind-up: an arc that fills with the charge, gold at full power
			var ccol: Color = Color(0.6, 0.9, 1.0).lerp(Color(1.0, 0.92, 0.55), a.charge)
			var wob: float = 1.0 + 0.15 * sin(_time * (8.0 + 14.0 * a.charge))
			draw_arc(c, 12.0 * wob, -PI / 2.0, -PI / 2.0 + TAU * a.charge, 22, Color(ccol.r, ccol.g, ccol.b, 0.75), 2.4)
			if a.charge >= 1.0:
				draw_arc(c, 16.0 * wob, 0, TAU, 24, Color(1.0, 0.92, 0.55, 0.35 + 0.25 * sin(_time * 12.0)), 1.6)
	# Floating shield meters (thin cyan bar above the ball whenever the
	# shield isn't full — red while broken/recharging). Armed actors have
	# shields too now, so the meter shows for everyone.
	for id in _actors:
		var a: Dictionary = _actors[id]
		if not a.is_alive.call():
			continue
		if a.shield_energy >= SHIELD_MAX - 0.01 and not a.shield_broken:
			continue
		var sc: Vector2 = a.get_center.call()
		var frac: float = a.shield_energy / SHIELD_MAX
		var scol: Color = Color(1.0, 0.35, 0.3) if a.shield_broken else Color(0.45, 0.85, 1.0)
		draw_rect(Rect2(sc.x - 10.0, sc.y - 23.0, 20.0, 2.5), Color(0.05, 0.05, 0.08, 0.75))
		draw_rect(Rect2(sc.x - 10.0, sc.y - 23.0, 20.0 * frac, 2.5), scol)
	# Floating HP bars (small, above each living actor)
	for id in _actors:
		var a: Dictionary = _actors[id]
		if a.get_hp.is_null() or not a.is_alive.call():
			continue
		var hp: int = a.get_hp.call()
		var mx: int = a.max_hp
		if hp >= mx:
			continue  # Full HP: keep the screen clean
		var c: Vector2 = a.get_center.call()
		var bar_w: float = 18.0
		var seg_w: float = bar_w / float(mx)
		draw_rect(Rect2(c.x - bar_w * 0.5 - 1.0, c.y - 18.0, bar_w + 2.0, 5.0), Color(0.05, 0.05, 0.08, 0.75))
		for s in range(mx):
			var seg_col: Color
			if s < hp:
				seg_col = Color(1.0, 0.3, 0.2) if hp == 1 else Color(0.3, 1.0, 0.45)
			else:
				seg_col = Color(0.22, 0.22, 0.28)
			draw_rect(Rect2(c.x - bar_w * 0.5 + s * seg_w, c.y - 17.0, seg_w - 1.0, 3.0), seg_col)
	# Projectiles: bright core + colored glow
	for pr in _projectiles:
		var col: Color = pr.color
		var dir: Vector2 = pr.vel.normalized()
		draw_line(pr.pos - dir * pr.size * 3.0, pr.pos, Color(col.r, col.g, col.b, 0.5), pr.size * 1.4)
		draw_circle(pr.pos, pr.size, col)
		draw_circle(pr.pos, pr.size * 0.55, Color(1, 1, 1))
	# FX particles (opaque bright — same style as the fire trail)
	for f in _fx:
		var t: float = f.life / f.max_life
		if f.get("ring", false):
			# Expanding shockwave ring
			var radius: float = f.r0 + (f.r1 - f.r0) * (1.0 - t)
			var rc: Color = f.color
			draw_arc(f.pos, radius, 0, TAU, 28, Color(rc.r, rc.g, rc.b, t * 0.85), 2.0 + 2.0 * t)
			continue
		var col: Color = f.color
		if t > 0.66:
			col = col.lerp(Color(1, 1, 1), (t - 0.66) * 2.0)
		else:
			col = col.lerp(Color(0.25, 0.1, 0.08), (0.66 - t) * 0.9)
		var s: float = f.size * (0.5 + 0.5 * t)
		draw_rect(Rect2(f.pos - Vector2(s, s) * 0.5, Vector2(s, s)), col)


func _draw_gun(pos: Vector2, aim: Vector2, weapon: String, scale_f: float) -> void:
	## Neon vector gun, rotated to aim. Flips vertically when aiming left so it
	## never renders upside-down on a rolling ball.
	var w: Dictionary = WEAPONS[weapon]
	var col: Color = w.color
	var ang: float = aim.angle()
	var flip: float = -1.0 if absf(ang) > PI / 2.0 else 1.0
	draw_set_transform(pos, ang, Vector2(scale_f, scale_f * flip))
	var dark: Color = Color(col.r * 0.25, col.g * 0.25, col.b * 0.3)
	match weapon:
		"blaster":
			draw_rect(Rect2(-6, -3, 9, 6), dark)                    # body
			draw_rect(Rect2(3, -1.6, 8, 3.2), dark)                 # barrel
			draw_rect(Rect2(3, -0.9, 8, 1.8), col)                  # barrel glow
			draw_rect(Rect2(-5, -2, 6, 1.6), col * 0.8)             # top stripe
			draw_circle(Vector2(11, 0), 1.6, Color(1, 1, 0.85))     # tip
		"scatter":
			draw_rect(Rect2(-7, -3.5, 10, 7), dark)
			draw_rect(Rect2(3, -3.0, 7, 2.4), dark)                 # twin barrels
			draw_rect(Rect2(3, 0.6, 7, 2.4), dark)
			draw_rect(Rect2(3, -2.6, 7, 1.6), col)
			draw_rect(Rect2(3, 1.0, 7, 1.6), col)
			draw_circle(Vector2(-4, 0), 2.0, col * 0.7)             # drum
		"rail":
			draw_rect(Rect2(-8, -2.6, 12, 5.2), dark)
			draw_rect(Rect2(4, -1.2, 11, 2.4), dark)
			draw_rect(Rect2(4, -0.6, 11, 1.2), col)
			for k in range(3):                                       # coil rings
				draw_rect(Rect2(5.5 + k * 3.0, -2.2, 1.2, 4.4), col * 0.9)
			draw_circle(Vector2(15, 0), 1.8, Color(1, 1, 1))
		"doom":
			draw_rect(Rect2(-9, -4.5, 13, 9), dark)                  # heavy body
			draw_rect(Rect2(4, -3.0, 12, 6.0), dark)                 # wide barrel
			draw_rect(Rect2(4, -1.8, 12, 3.6), col)                  # burning core
			draw_rect(Rect2(4, -0.7, 12, 1.4), Color(1, 0.9, 0.7))   # white-hot center
			for k in range(2):                                       # vents
				draw_rect(Rect2(-6 + k * 4.0, -6.0, 2.0, 2.0), col * 0.9)
				draw_rect(Rect2(-6 + k * 4.0, 4.0, 2.0, 2.0), col * 0.9)
			draw_circle(Vector2(16.5, 0), 2.6, Color(1, 1, 0.9))
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
