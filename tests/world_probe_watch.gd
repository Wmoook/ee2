extends Node
## Survives the scene change; reports connection health every 15s for 4 min.
var t: float = 0.0
func _ready() -> void:
	NetPlay.server_lost.connect(func() -> void: print("PROBE SERVER_LOST t=%.1f" % t))
func _process(delta: float) -> void:
	t += delta
	if int(t) != int(t - delta) and int(t) % 15 == 0:
		print("PROBE tick t=%.0f online=%s room=%s scene=%s" % [t, str(NetPlay.online), NetPlay.my_room, str(get_tree().current_scene != null and get_tree().current_scene.name)])
	if t > 240.0 or (t > 10.0 and not NetPlay.online):
		print("PROBE DONE t=%.0f online=%s" % [t, str(NetPlay.online)])
		get_tree().quit(0)
