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
var ok_rep_wpn: bool = false
var ok_rep_chg: bool = false
var ok_rep_death: bool = false

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
	# ── Battle replication phase (after the match starts) ──
	var bm: Node = null
	if ok_start and get_tree().current_scene != null:
		bm = get_tree().current_scene.get_node_or_null("BattleMode")
	if bm != null and bm.weapons != null and bm.weapons._actors.has("player"):
		if role == "a":
			# Host: hold a weapon + a real charge so the 20Hz state carries both
			# (generous windows — A and B clocks are offset by boot stagger)
			if t > 19.0 and t < 22.0:
				var pa: Dictionary = bm.weapons._actors["player"]
				if pa.weapon != "blaster":
					bm.weapons.give_weapon("player", "blaster")
			if t > 22.0 and t < 26.0:
				bm.weapons._actors["player"].weapon = ""  # fists so charge_dash works
				bm.weapons.charge_dash("player", delta)
			if t > 26.5 and not fired.has("die") and is_instance_valid(bm.player):
				fired["die"] = true
				bm._hurt_player(99, Vector2.RIGHT)
		else:
			var aid: int = NetPlay.host_id()
			var arid: String = "p%d" % aid
			if t > 20.5 and not fired.has("chk_wpn") and bm.weapons._actors.has(arid):
				fired["chk_wpn"] = true
				ok_rep_wpn = bm.weapons._actors[arid].weapon == "blaster"
			if t > 24.5 and not fired.has("chk_chg") and bm.weapons._actors.has(arid):
				fired["chk_chg"] = true
				ok_rep_chg = bm.weapons._actors[arid].charge > 0.4
			if t > 28.0 and not fired.has("chk_death"):
				fired["chk_death"] = true
				var scene: Node = get_tree().current_scene
				if scene.has_method("_get_player"):
					var an: Node = scene._get_player(aid)
					ok_rep_death = an != null and (an._is_dead or bool(an._remote_sync.is_dead))
	if t > 29.0 and not fired.has("done"):
		fired["done"] = true
		print("NET TEST [%s]: world=%s snap=%s live=%s peers=%s start=%s room=%s scene_ok=%s wpn=%s chg=%s death=%s" % [
			role, ok_world, ok_snapshot, ok_live, ok_peers, ok_start, NetPlay.my_room,
			str(get_tree().current_scene != null), ok_rep_wpn, ok_rep_chg, ok_rep_death])
		var pass_all: bool = ok_world and ok_start
		if role == "b":
			pass_all = pass_all and ok_snapshot and ok_live and ok_peers \
				and ok_rep_wpn and ok_rep_chg and ok_rep_death
		print("NET TEST [%s] %s" % [role, "PASS" if pass_all else "FAIL"])
		get_tree().quit(0 if pass_all else 1)
