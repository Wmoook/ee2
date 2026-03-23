extends Node
class_name GravityZoneManager
## Manages circular gravity zones where gravity pulls toward the center.
## Standalone module — keeps gravity zone logic separate from other systems.

# Each zone: {center: Vector2, radius: float, strength: float}
var zones: Array = []

signal zones_changed()

func add_zone(center: Vector2, radius: float, strength: float = 2.0, center_radius: float = 8.0) -> void:
	zones.append({"center": center, "radius": radius, "strength": strength, "center_radius": center_radius})
	zones_changed.emit()

func remove_zone_near(pos: Vector2, threshold: float = 24.0) -> void:
	var best_idx: int = -1
	var best_dist: float = threshold
	for i in range(zones.size()):
		var d: float = zones[i].center.distance_to(pos)
		if d < best_dist:
			best_dist = d
			best_idx = i
	if best_idx >= 0:
		zones.remove_at(best_idx)
		zones_changed.emit()

func get_gravity_at(px: float, py: float) -> Dictionary:
	## Returns {in_zone: bool, direction: Vector2} for the given pixel position.
	## Direction points toward zone center, scaled by strength.
	## Multiple overlapping zones sum their pull vectors.
	var result: Dictionary = {"in_zone": false, "direction": Vector2.ZERO}
	var pos: Vector2 = Vector2(px, py)
	for gz in zones:
		var to_center: Vector2 = gz.center - pos
		var dist: float = to_center.length()
		if dist < gz.radius and dist > 0.1:
			result.in_zone = true
			result.direction += to_center.normalized() * gz.strength
	return result

func serialize() -> Array:
	var data: Array = []
	for gz in zones:
		data.append({"cx": gz.center.x, "cy": gz.center.y, "r": gz.radius, "s": gz.strength, "cr": gz.get("center_radius", 8.0)})
	return data

func deserialize(data: Array) -> void:
	zones.clear()
	for gz in data:
		zones.append({
			"center": Vector2(gz.get("cx", 0), gz.get("cy", 0)),
			"radius": gz.get("r", 50),
			"strength": gz.get("s", 2.0),
			"center_radius": gz.get("cr", 8.0)
		})
	zones_changed.emit()

func clear() -> void:
	zones.clear()
	zones_changed.emit()

func duplicate_zones() -> Array:
	var copy: Array = []
	for gz in zones:
		copy.append(gz.duplicate())
	return copy

func restore_zones(data: Array) -> void:
	zones.clear()
	for gz in data:
		zones.append(gz)
	zones_changed.emit()
