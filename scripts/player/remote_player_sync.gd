extends RefCounted
class_name RemotePlayerSync
## Handles interpolation and state for remote (non-local) players.
## Keeps player_controller.gd clean per design principles.

var target_pos: Vector2 = Vector2.ZERO
var prev_pos: Vector2 = Vector2.ZERO
var interp_t: float = 1.0  # Start at 1 = at target
var speed: Vector2 = Vector2.ZERO
var anim_frame: int = 0  # 0=idle, 1=transition, 2=moving
var flip_h: bool = false
var rotation: float = 0.0
var is_god: bool = false
var is_grounded: bool = false
var is_dead: bool = false
var gz_death: bool = false
var gz_death_center: Vector2 = Vector2.ZERO

const SYNC_INTERVAL: float = 0.05  # 50ms = 20Hz

func receive_state(data: Dictionary) -> void:
	prev_pos = target_pos if interp_t < 1.5 else target_pos
	target_pos = Vector2(data.get("x", 0), data.get("y", 0))
	# Respawns and other teleports must SNAP — interpolating a cross-map jump
	# streaks the ball over everything ("teleporting around after death")
	if prev_pos.distance_to(target_pos) > 96.0:
		prev_pos = target_pos
	speed = Vector2(data.get("sx", 0), data.get("sy", 0))
	anim_frame = data.get("af", 0)
	flip_h = data.get("fh", false)
	rotation = data.get("r", 0.0)
	is_god = data.get("g", false)
	is_grounded = data.get("gr", false)
	is_dead = data.get("dead", false)
	gz_death = data.get("gzd", false)
	if gz_death:
		gz_death_center = Vector2(data.get("gzc_x", 0), data.get("gzc_y", 0))
	interp_t = 0.0

func get_interpolated_position(delta: float) -> Vector2:
	interp_t += delta / SYNC_INTERVAL
	interp_t = clampf(interp_t, 0.0, 2.6)
	if is_dead:
		return target_pos
	# Lead the last packet by half an interval and extrapolate a little past
	# it: pure interpolation rendered remote balls ~100ms in the PAST, so
	# contacts looked like hitting an invisible spot ahead of the other ball.
	# (EE speed units are px per 100Hz tick → px/s = speed * 100.)
	var vel_px: Vector2 = speed * 100.0
	var lead: Vector2 = target_pos + vel_px * (SYNC_INTERVAL * 0.5)
	if interp_t <= 1.0:
		return prev_pos.lerp(lead, interp_t)
	var extra: float = minf((interp_t - 1.0) * SYNC_INTERVAL, 0.08)
	return lead + vel_px * extra
