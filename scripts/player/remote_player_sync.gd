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

const SYNC_INTERVAL: float = 0.05  # 50ms = 20Hz

func receive_state(data: Dictionary) -> void:
	prev_pos = target_pos if interp_t < 1.5 else target_pos
	target_pos = Vector2(data.get("x", 0), data.get("y", 0))
	speed = Vector2(data.get("sx", 0), data.get("sy", 0))
	anim_frame = data.get("af", 0)
	flip_h = data.get("fh", false)
	rotation = data.get("r", 0.0)
	is_god = data.get("g", false)
	is_grounded = data.get("gr", false)
	interp_t = 0.0

func get_interpolated_position(delta: float) -> Vector2:
	interp_t += delta / SYNC_INTERVAL
	interp_t = clampf(interp_t, 0.0, 1.2)
	return prev_pos.lerp(target_pos, minf(interp_t, 1.0))
