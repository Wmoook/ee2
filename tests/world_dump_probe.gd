extends Node
## Join the production world, dump the exact world state to a local JSON,
## and quit. Lets physics tests run against the REAL curves.
var t: float = 0.0
var done: bool = false
func _ready() -> void:
	GameState.player_name = "Probe"
	NetPlay.join_world()
func _process(delta: float) -> void:
	t += delta
	if NetPlay.my_room == "world" and not done and t > 3.0:
		done = true
		var f: FileAccess = FileAccess.open("user://world_dump.json", FileAccess.WRITE)
		f.store_string(JSON.stringify(WorldManager.serialize_world()))
		f.close()
		print("DUMP saved polys=%d fbs=%d" % [WorldManager.polylines.size(), WorldManager.free_blocks.size()])
		get_tree().quit(0)
	if t > 30.0:
		print("DUMP TIMEOUT")
		get_tree().quit(1)
