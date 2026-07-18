extends Node
## Probe v3: join production world, enter the game scene, then PLACE a small
## pinch-split (V-shape) curve with caps in a far empty corner — exactly what
## the user did before their connection died — then erase it, cleaning up.
var t: float = 0.0
var placed: bool = false
var erased: bool = false
func _ready() -> void:
	var w: Node = Node.new()
	w.name = "ProbeWatch"
	w.set_script(preload("res://tests/world_probe_watch.gd"))
	get_tree().root.add_child.call_deferred(w)
	var act: Node = Node.new()
	act.name = "ProbeActions"
	act.set_script(preload("res://tests/world_probe_actions.gd"))
	get_tree().root.add_child.call_deferred(act)
	GameState.player_name = "Probe"
	NetPlay.world_joined.connect(func() -> void:
		print("PROBE world_joined fbs=%d polys=%d" % [WorldManager.free_blocks.size(), WorldManager.polylines.size()])
		get_tree().change_scene_to_file("res://scenes/world/game.tscn"))
	NetPlay.join_world()
