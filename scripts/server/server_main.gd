extends Node
## EE COMBAT dedicated server — runs headless on Railway.
## Boots the WebSocket server, loads the persistent sandbox world from
## EE2_DATA_DIR (a mounted volume), autosaves it, and lets NetPlay manage
## rooms/lobbies. No player, no rendering.

const DEFAULT_PORT: int = 9801
const AUTOSAVE_SECS: float = 30.0
const STATS_SECS: float = 60.0

var _world_path: String = "user://world.json"
var _save_accum: float = 0.0
var _stats_accum: float = 0.0

func _ready() -> void:
	var port: int = DEFAULT_PORT
	var args: PackedStringArray = OS.get_cmdline_user_args()
	for i in range(args.size()):
		if args[i] == "--port" and i + 1 < args.size() and args[i + 1].is_valid_int():
			port = int(args[i + 1])

	var data_dir: String = OS.get_environment("EE2_DATA_DIR")
	if not data_dir.is_empty():
		_world_path = data_dir.rstrip("/") + "/world.json"

	var err: Error = NetworkManager.start_dedicated(port)
	if err != OK:
		printerr("[server] FAILED to listen on port %d: %s" % [port, error_string(err)])
		get_tree().quit(1)
		return
	NetPlay.start_server()
	_load_world()
	print("[server] EE COMBAT dedicated server on port %d — world: %s (%dx%d)" % [
		port, _world_path, WorldManager.world_width, WorldManager.world_height])

func _load_world() -> void:
	if FileAccess.file_exists(_world_path) and WorldManager.load_from_file(_world_path) == OK:
		print("[server] world loaded from %s" % _world_path)
		return
	WorldManager.build_sample_room()
	print("[server] no saved world — built the sample room")

func _process(delta: float) -> void:
	_save_accum += delta
	if _save_accum >= AUTOSAVE_SECS:
		_save_accum = 0.0
		if NetPlay.world_dirty:
			NetPlay.world_dirty = false
			var err: Error = WorldManager.save_to_file(_world_path)
			if err != OK:
				printerr("[server] world save FAILED: %s" % error_string(err))
			else:
				print("[server] world autosaved")
	_stats_accum += delta
	if _stats_accum >= STATS_SECS:
		_stats_accum = 0.0
		print("[server] peers=%d world=%d lobbies=%d" % [
			NetPlay._peers.size(),
			NetPlay._room_members_dict("world").size(),
			NetPlay._lobbies.size()])

func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST or what == NOTIFICATION_PREDELETE:
		if NetPlay.world_dirty:
			WorldManager.save_to_file(_world_path)
