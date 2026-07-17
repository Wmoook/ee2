extends Node
## EE COMBAT net e2e driver. Run two headless instances against a local
## dedicated server:
##   godot --headless res://tests/net_test.tscn -- --connect=ws://127.0.0.1:9801 --role=a
##   godot --headless res://tests/net_test.tscn -- --connect=ws://127.0.0.1:9801 --role=b
## A: joins world, places tiles, creates a battle lobby, starts the match.
## B: joins world late (checks snapshot tile), checks live tile relay,
##    browses lobbies, joins A's lobby; both must receive match start.

var role: String = "a"
var t: float = 0.0
var fired: Dictionary = {}
var ok_world: bool = false
var ok_snapshot: bool = false
var ok_live: bool = false
var ok_start: bool = false
var ok_peers: bool = false

func _ready() -> void:
	for a: String in OS.get_cmdline_user_args():
		if a.begins_with("--role="):
			role = a.trim_prefix("--role=")
	GameState.player_name = "Test_" + role.to_upper()
	GameState.player_smiley_id = 3 if role == "a" else -1
	NetPlay.world_joined.connect(func() -> void: ok_world = true)
	NetPlay.match_starting.connect(func(_m: String, _o: Dictionary) -> void: ok_start = true)
	NetPlay.lobbies_updated.connect(_on_lobbies)
	if role == "a":
		NetPlay.join_world()

func _on_lobbies(list: Array) -> void:
	if role == "b" and not fired.has("join_lob") and list.size() > 0:
		fired["join_lob"] = true
		NetPlay.join_lobby(int(list[0].id))

func _process(delta: float) -> void:
	t += delta
	if role == "a":
		if t > 3.0 and not fired.has("t1"):
			fired["t1"] = true
			NetPlay.send_tiles([{"x": 5, "y": 5, "id": 5000, "l": "fg"}])
		if t > 6.0 and not fired.has("t2"):
			fired["t2"] = true
			NetPlay.send_tiles([{"x": 10, "y": 5, "id": 5001, "l": "fg"}])
		if t > 8.5 and not fired.has("lob"):
			fired["lob"] = true
			NetPlay.create_lobby("battle", {"guns": true})
		if t > 13.0 and not fired.has("start"):
			fired["start"] = true
			NetPlay.start_match()
	else:
		if t > 4.0 and not fired.has("bjoin"):
			fired["bjoin"] = true
			NetPlay.join_world()
		if t > 5.8 and not fired.has("chk1"):
			fired["chk1"] = true
			ok_snapshot = WorldManager.get_tile(5, 5) == 5000
			ok_peers = NetworkManager.players.size() >= 2
		if t > 8.0 and not fired.has("chk2"):
			fired["chk2"] = true
			ok_live = WorldManager.get_tile(10, 5) == 5001
		if t > 10.0 and not fired.has("browse"):
			fired["browse"] = true
			NetPlay.browse("battle")
	if t > 18.0 and not fired.has("done"):
		fired["done"] = true
		print("NET TEST [%s]: world=%s snap=%s live=%s peers=%s start=%s room=%s scene_ok=%s" % [
			role, ok_world, ok_snapshot, ok_live, ok_peers, ok_start, NetPlay.my_room,
			str(get_tree().current_scene != null)])
		var pass_all: bool = ok_world and ok_start
		if role == "b":
			pass_all = pass_all and ok_snapshot and ok_live and ok_peers
		print("NET TEST [%s] %s" % [role, "PASS" if pass_all else "FAIL"])
		get_tree().quit(0 if pass_all else 1)
