extends Node
## Probe v2: join the PRODUCTION world AND enter the real game scene like a
## browser client, then watch for the connection dying (reset-to-menu bug).
var t: float = 0.0
func _ready() -> void:
	var w: Node = Node.new()
	w.name = "ProbeWatch"
	w.set_script(preload("res://tests/world_probe_watch.gd"))
	get_tree().root.add_child.call_deferred(w)
	GameState.player_name = "Probe"
	NetPlay.world_joined.connect(func() -> void:
		print("PROBE world_joined fbs=%d polys=%d" % [WorldManager.free_blocks.size(), WorldManager.polylines.size()])
		get_tree().change_scene_to_file("res://scenes/world/game.tscn"))
	NetPlay.connect_failed.connect(func() -> void: print("PROBE CONNECT_FAILED"))
	NetPlay.join_world()
