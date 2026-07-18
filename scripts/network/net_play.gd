extends Node
## NetPlay — EE COMBAT online layer (rooms + lobbies) over the dedicated server.
##
## One Godot headless instance runs on Railway as peer 1 ("the server"). It is
## NOT a player: it holds the persistent sandbox world and a room registry, and
## relays room-scoped traffic. Browser + desktop clients connect to the same
## server; a lobby's HOST (a normal client) simulates the mode and everyone
## else runs puppets.
##
## Rooms:  ""       = menu / just connected
##         "world"  = the shared persistent sandbox
##         "lob_N"  = one mode lobby (battle / boss / zombies / survivors)
##
## All RPCs live on this autoload so node paths are identical on every peer.

signal connected_ok()
signal connect_failed()
signal server_lost()
signal lobbies_updated(list: Array)
signal room_updated(info: Dictionary)
signal left_room()
signal match_starting(mode: String, opts: Dictionary)
signal mode_msg(from_id: int, data: Dictionary)
signal world_joined()

const PROD_URL: String = "wss://ee-combat-production.up.railway.app/ws"
const MODES: Array[String] = ["battle", "boss", "zombies", "survivors"]
const MAX_LOBBY: int = 8
const COUNTDOWN: float = 3.0

# ---- client state ----
var online: bool = false          # connected to the dedicated server
var connecting: bool = false
var my_room: String = ""
var room_info: Dictionary = {}    # last sv_room payload {room, mode, host, opts, started, members:{id:{name,smiley_id}}}
var match_active: bool = false    # an online mode match is running
var match_countdown: float = 0.0  # 3-2-1-GO handled by game_scene
var _want_world_after_connect: bool = false
var _browse_mode: String = ""     # lobby list filter while browsing
var _ping_accum: float = 0.0
var _beat_accum: float = 0.0

# ---- server state ----
var server_active: bool = false
var world_dirty: bool = false
var _rooms: Dictionary = {}       # peer_id -> room string
var _peers: Dictionary = {}       # peer_id -> {name, smiley_id}
var _lobbies: Dictionary = {}     # lobby_id -> {id, mode, host, members:Array, opts, started}
var _next_lobby_id: int = 1

func _ready() -> void:
	NetworkManager.connection_succeeded.connect(_on_conn_ok)
	NetworkManager.connection_failed.connect(_on_conn_fail)
	NetworkManager.server_disconnected.connect(_on_server_dc)

func _process(delta: float) -> void:
	# Keepalive so proxies don't drop idle menu connections
	if online:
		_ping_accum += delta
		if _ping_accum >= 20.0:
			_ping_accum = 0.0
			rq_ping.rpc_id(1)
	# Server heartbeat: Railway's edge closes a WebSocket after ~87s with NO
	# server->client data. A solo player in the world receives NOTHING after
	# the snapshot (client pings are one-way), so every session died at ~87s
	# ("keeps resetting to menu"). A tiny broadcast every 10s keeps every
	# connection warm.
	if server_active:
		_beat_accum += delta
		if _beat_accum >= 10.0:
			_beat_accum = 0.0
			if multiplayer.get_peers().size() > 0:
				sv_beat.rpc()

# ==================== URL resolution ====================

func server_url() -> String:
	for a: String in OS.get_cmdline_user_args():
		if a.begins_with("--connect="):
			return a.trim_prefix("--connect=")
	var env: String = OS.get_environment("EE2_SERVER")
	if not env.is_empty():
		return env
	if OS.has_feature("web"):
		var host: Variant = JavaScriptBridge.eval("location.host")
		var proto: Variant = JavaScriptBridge.eval("location.protocol")
		if host is String and not str(host).is_empty():
			var scheme: String = "wss://" if str(proto) == "https:" else "ws://"
			return scheme + str(host) + "/ws"
	return PROD_URL

# ==================== client API ====================

func connect_to_server() -> Error:
	if online:
		connected_ok.emit()
		return OK
	if connecting:
		return OK
	connecting = true
	var err: Error = NetworkManager.join_game(server_url(), 0)
	if err != OK:
		connecting = false
	return err

func join_world() -> void:
	if online:
		rq_join_world.rpc_id(1)
	else:
		_want_world_after_connect = true
		connect_to_server()

func browse(mode: String) -> void:
	_browse_mode = mode
	if online:
		rq_lobbies.rpc_id(1)

func create_lobby(mode: String, opts: Dictionary) -> void:
	if online:
		rq_create_lobby.rpc_id(1, mode, opts)

func join_lobby(lobby_id: int) -> void:
	if online:
		rq_join_lobby.rpc_id(1, lobby_id)

func set_lobby_opts(opts: Dictionary) -> void:
	if online:
		rq_set_opts.rpc_id(1, opts)

func start_match() -> void:
	if online:
		rq_start.rpc_id(1)

func leave_room() -> void:
	match_active = false
	match_countdown = 0.0
	GameState.net_freeze = false
	if online:
		rq_leave_room.rpc_id(1)
	my_room = ""
	room_info = {}

func my_id() -> int:
	return multiplayer.get_unique_id() if NetworkManager._peer != null else 1

func i_am_host() -> bool:
	return int(room_info.get("host", -1)) == my_id()

func host_id() -> int:
	return int(room_info.get("host", -1))

func member_ids() -> Array:
	var out: Array = []
	for k in room_info.get("members", {}):
		out.append(int(k))
	out.sort()
	return out

func member_count() -> int:
	return room_info.get("members", {}).size()

func in_lobby() -> bool:
	return my_room.begins_with("lob_")

## Reliable mode-scoped message to everyone else in my lobby.
func send_mode(data: Dictionary) -> void:
	if online and in_lobby():
		_rx_mode_r.rpc_id(1, data)

## Unreliable (ordered) mode-scoped message — for high-rate state snapshots.
func send_mode_u(data: Dictionary) -> void:
	if online and in_lobby():
		_rx_mode_u.rpc_id(1, data)

## Player state pump (called from player_controller when online).
func send_pstate(data: Dictionary) -> void:
	if online:
		_rx_pstate.rpc_id(1, data)

## Tile edits pump (world room).
func send_tiles(tiles: Array) -> void:
	if online:
		_rx_tiles.rpc_id(1, tiles)

# ==================== connection glue ====================

func _on_conn_ok() -> void:
	if not connecting:
		return  # LAN flow (main_menu handles it)
	connecting = false
	online = true
	rq_hello.rpc_id(1, {"name": GameState.player_name, "smiley_id": GameState.player_smiley_id})
	if _want_world_after_connect:
		_want_world_after_connect = false
		rq_join_world.rpc_id(1)
	if not _browse_mode.is_empty():
		rq_lobbies.rpc_id(1)
	connected_ok.emit()

func _on_conn_fail() -> void:
	if connecting or online:
		connecting = false
		online = false
		_want_world_after_connect = false
		connect_failed.emit()

func _on_server_dc() -> void:
	if not online:
		return
	online = false
	connecting = false
	my_room = ""
	room_info = {}
	match_active = false
	GameState.net_freeze = false
	server_lost.emit()

# ==================== server bootstrap ====================

func start_server() -> void:
	server_active = true
	multiplayer.server_relay = false  # all forwarding is explicit + room-scoped
	print("[NetPlay] server active — rooms + lobbies online")

func server_peer_connected(id: int) -> void:
	_rooms[id] = ""
	_peers[id] = {"name": "Player", "smiley_id": -1}
	print("[NetPlay] peer %d connected (%d online)" % [id, _peers.size()])

func server_peer_left(id: int) -> void:
	_server_leave_room(id, true)
	_rooms.erase(id)
	_peers.erase(id)
	print("[NetPlay] peer %d left (%d online)" % [id, _peers.size()])

func _server_hello(id: int, info: Dictionary) -> void:
	_peers[id] = {
		"name": str(info.get("name", "Player")).substr(0, 20),
		"smiley_id": clampi(int(info.get("smiley_id", -1)), -1, 375),
	}

## Peers that should receive a relay of a message sent by `sender`
## (their room-mates, excluding the server and the sender).
func relay_targets(sender: int) -> Array:
	var room: String = _rooms.get(sender, "")
	var out: Array = []
	if room.is_empty():
		return out
	for pid in _rooms:
		if pid != sender and _rooms[pid] == room:
			out.append(pid)
	return out

func is_world_peer(id: int) -> bool:
	return _rooms.get(id, "") == "world"

func mark_world_dirty() -> void:
	world_dirty = true

func _room_members_dict(room: String) -> Dictionary:
	var out: Dictionary = {}
	for pid in _rooms:
		if _rooms[pid] == room:
			out[pid] = _peers.get(pid, {"name": "Player", "smiley_id": -1})
	return out

func _lobby_of(id: int) -> Dictionary:
	var room: String = _rooms.get(id, "")
	if not room.begins_with("lob_"):
		return {}
	return _lobbies.get(int(room.trim_prefix("lob_")), {})

func _rpc_ok(pid: int) -> bool:
	## Peer still connected? (cleanup paths can race a disconnect)
	return pid in multiplayer.get_peers()

func _push_room(room: String) -> void:
	## Send fresh room info to everyone in `room`.
	var members: Dictionary = _room_members_dict(room)
	var info: Dictionary = {"room": room, "members": members, "host": -1, "mode": "", "opts": {}, "started": false}
	if room.begins_with("lob_"):
		var lob: Dictionary = _lobbies.get(int(room.trim_prefix("lob_")), {})
		if not lob.is_empty():
			info.host = lob.host
			info.mode = lob.mode
			info.opts = lob.opts
			info.started = lob.started
	for pid in members:
		if _rpc_ok(pid):
			sv_room.rpc_id(pid, info)

func _push_lobby_list() -> void:
	## Lobby list to everyone still in the menu (room "").
	var list: Array = _public_lobbies()
	for pid in _rooms:
		if _rooms[pid] == "" and _rpc_ok(pid):
			sv_lobbies.rpc_id(pid, list)

func _public_lobbies() -> Array:
	var list: Array = []
	for lid in _lobbies:
		var lob: Dictionary = _lobbies[lid]
		if lob.started:
			continue
		list.append({
			"id": lid, "mode": lob.mode,
			"count": lob.members.size(), "max": MAX_LOBBY,
			"host_name": _peers.get(lob.host, {}).get("name", "Player"),
			"opts": lob.opts,
		})
	return list

func _server_leave_room(id: int, disconnected: bool) -> void:
	var room: String = _rooms.get(id, "")
	if room.is_empty():
		return
	_rooms[id] = ""
	if room == "world":
		for pid in _rooms:
			if _rooms[pid] == "world" and _rpc_ok(pid):
				sv_peer_left.rpc_id(pid, id)
		return
	# Lobby leave
	var lid: int = int(room.trim_prefix("lob_"))
	var lob: Dictionary = _lobbies.get(lid, {})
	if lob.is_empty():
		return
	lob.members.erase(id)
	if lob.members.is_empty():
		_lobbies.erase(lid)
		_push_lobby_list()
		return
	var was_host: bool = lob.host == id
	if was_host:
		lob.host = lob.members[0]
	for pid in lob.members:
		if _rpc_ok(pid):
			sv_peer_left.rpc_id(pid, id)
	if lob.started and was_host:
		# Mid-match host loss: tell survivors so modes can end gracefully
		for pid in lob.members:
			sv_mode_r.rpc_id(pid, id, {"m": "_host_left", "new_host": lob.host})
	_push_room(room)
	_push_lobby_list()
	if disconnected:
		return

# ==================== RPCs: client -> server ====================

@rpc("any_peer", "reliable")
func rq_ping() -> void:
	pass

@rpc("authority", "reliable")
func sv_beat() -> void:
	pass  # The traffic itself is the point (edge idle-timeout keepalive)

@rpc("any_peer", "reliable")
func rq_hello(info: Dictionary) -> void:
	if not server_active:
		return
	_server_hello(multiplayer.get_remote_sender_id(), info)

@rpc("any_peer", "reliable")
func rq_join_world() -> void:
	if not server_active:
		return
	var id: int = multiplayer.get_remote_sender_id()
	_server_leave_room(id, false)
	_rooms[id] = "world"
	WorldManager.send_world_to_peer(id)
	var members: Dictionary = _room_members_dict("world")
	for pid in members:
		if pid == id:
			continue
		sv_peer_join.rpc_id(pid, id, _peers.get(id, {}))
	sv_room.rpc_id(id, {"room": "world", "members": members, "host": -1, "mode": "", "opts": {}, "started": false})
	sv_world_ok.rpc_id(id)

@rpc("any_peer", "reliable")
func rq_lobbies() -> void:
	if not server_active:
		return
	sv_lobbies.rpc_id(multiplayer.get_remote_sender_id(), _public_lobbies())

@rpc("any_peer", "reliable")
func rq_create_lobby(mode: String, opts: Dictionary) -> void:
	if not server_active or not mode in MODES:
		return
	var id: int = multiplayer.get_remote_sender_id()
	_server_leave_room(id, false)
	var lid: int = _next_lobby_id
	_next_lobby_id += 1
	_lobbies[lid] = {"id": lid, "mode": mode, "host": id, "members": [id], "opts": opts, "started": false}
	_rooms[id] = "lob_%d" % lid
	_push_room("lob_%d" % lid)
	_push_lobby_list()

@rpc("any_peer", "reliable")
func rq_join_lobby(lobby_id: int) -> void:
	if not server_active:
		return
	var id: int = multiplayer.get_remote_sender_id()
	var lob: Dictionary = _lobbies.get(lobby_id, {})
	if lob.is_empty() or lob.started or lob.members.size() >= MAX_LOBBY:
		sv_join_denied.rpc_id(id)
		return
	_server_leave_room(id, false)
	lob.members.append(id)
	_rooms[id] = "lob_%d" % lobby_id
	for pid in lob.members:
		if pid != id:
			sv_peer_join.rpc_id(pid, id, _peers.get(id, {}))
	_push_room("lob_%d" % lobby_id)
	_push_lobby_list()

@rpc("any_peer", "reliable")
func rq_set_opts(opts: Dictionary) -> void:
	if not server_active:
		return
	var id: int = multiplayer.get_remote_sender_id()
	var lob: Dictionary = _lobby_of(id)
	if lob.is_empty() or lob.host != id or lob.started:
		return
	lob.opts = opts
	_push_room("lob_%d" % lob.id)
	_push_lobby_list()

@rpc("any_peer", "reliable")
func rq_start() -> void:
	if not server_active:
		return
	var id: int = multiplayer.get_remote_sender_id()
	var lob: Dictionary = _lobby_of(id)
	if lob.is_empty() or lob.host != id or lob.started:
		return
	lob.started = true
	for pid in lob.members:
		sv_start.rpc_id(pid, lob.mode, lob.opts)
	_push_lobby_list()

@rpc("any_peer", "reliable")
func rq_leave_room() -> void:
	if not server_active:
		return
	_server_leave_room(multiplayer.get_remote_sender_id(), false)
	_push_lobby_list()
	sv_lobbies.rpc_id(multiplayer.get_remote_sender_id(), _public_lobbies())

@rpc("any_peer", "reliable")
func _rx_mode_r(data: Dictionary) -> void:
	if not server_active:
		return
	var sender: int = multiplayer.get_remote_sender_id()
	for pid in relay_targets(sender):
		sv_mode_r.rpc_id(pid, sender, data)

@rpc("any_peer", "unreliable_ordered")
func _rx_mode_u(data: Dictionary) -> void:
	if not server_active:
		return
	var sender: int = multiplayer.get_remote_sender_id()
	for pid in relay_targets(sender):
		sv_mode_u.rpc_id(pid, sender, data)

@rpc("any_peer", "unreliable_ordered")
func _rx_pstate(data: Dictionary) -> void:
	var sender: int = multiplayer.get_remote_sender_id()
	if server_active:
		data["pid"] = sender
		for pid in relay_targets(sender):
			sv_pstate.rpc_id(pid, data)
		return

@rpc("any_peer", "reliable")
func _rx_tiles(tiles: Array) -> void:
	var sender: int = multiplayer.get_remote_sender_id()
	if server_active:
		if not is_world_peer(sender):
			return
		_apply_tiles(tiles)
		world_dirty = true
		for pid in relay_targets(sender):
			sv_tiles.rpc_id(pid, tiles)
		return

# ==================== RPCs: server -> client ====================

@rpc("authority", "reliable")
func sv_lobbies(list: Array) -> void:
	lobbies_updated.emit(list)

@rpc("authority", "reliable")
func sv_join_denied() -> void:
	lobbies_updated.emit([])
	rq_lobbies.rpc_id(1)

@rpc("authority", "reliable")
func sv_room(info: Dictionary) -> void:
	my_room = str(info.get("room", ""))
	room_info = info
	# Mirror members into NetworkManager.players so game_scene's existing
	# spawn logic sees exactly my room-mates.
	var mid: int = my_id()
	NetworkManager.players.clear()
	for k in info.get("members", {}):
		NetworkManager.players[int(k)] = info.members[k]
	if not NetworkManager.players.has(mid):
		NetworkManager.players[mid] = {"name": GameState.player_name, "smiley_id": GameState.player_smiley_id}
	room_updated.emit(info)

@rpc("authority", "reliable")
func sv_peer_join(id: int, info: Dictionary) -> void:
	if room_info.has("members"):
		room_info.members[id] = info
	NetworkManager.players[id] = info
	NetworkManager.player_connected.emit(id)
	room_updated.emit(room_info)

@rpc("authority", "reliable")
func sv_peer_left(id: int) -> void:
	if room_info.has("members"):
		room_info.members.erase(id)
	NetworkManager.players.erase(id)
	NetworkManager.player_disconnected.emit(id)
	room_updated.emit(room_info)

@rpc("authority", "reliable")
func sv_world_ok() -> void:
	world_joined.emit()

@rpc("authority", "reliable")
func sv_start(mode: String, opts: Dictionary) -> void:
	match_starting.emit(mode, opts)
	_launch_mode(mode, opts)

@rpc("authority", "reliable")
func sv_mode_r(from_id: int, data: Dictionary) -> void:
	mode_msg.emit(from_id, data)

@rpc("authority", "unreliable_ordered")
func sv_mode_u(from_id: int, data: Dictionary) -> void:
	mode_msg.emit(from_id, data)

@rpc("authority", "unreliable_ordered")
func sv_pstate(data: Dictionary) -> void:
	var pid: int = int(data.get("pid", -1))
	var tree: SceneTree = get_tree()
	if tree == null or tree.current_scene == null:
		return
	var scene: Node = tree.current_scene
	if scene.has_method("_get_player"):
		var p: Node = scene._get_player(pid)
		if p != null and p.get("_remote_sync") != null:
			p._remote_sync.receive_state(data)
			if data.has("sp"):
				p.set_speech(str(data.sp))

@rpc("authority", "reliable")
func sv_tiles(tiles: Array) -> void:
	_apply_tiles(tiles)

# ==================== shared helpers ====================

func _apply_tiles(tiles: Array) -> void:
	for tile in tiles:
		if not (tile is Dictionary and tile.has("x") and tile.has("y") and tile.has("id")):
			continue
		if str(tile.get("l", "fg")) == "fg":
			WorldManager.set_fg_tile(int(tile.x), int(tile.y), int(tile.id))
		else:
			WorldManager.set_bg_tile(int(tile.x), int(tile.y), int(tile.id))

func _launch_mode(mode: String, opts: Dictionary) -> void:
	GameState.battle_mode = true
	GameState.boss_fight = mode == "boss"
	GameState.survivors_mode = mode == "survivors"
	GameState.zombies_mode = mode == "zombies"
	GameState.battle_guns_enabled = bool(opts.get("guns", true))
	GameState.set_edit_mode(false)
	GameState.camera_offset = Vector2.ZERO
	GameState.net_freeze = true
	match_active = true
	match_countdown = COUNTDOWN
	match mode:
		"battle":
			BattleMap.build()
		"boss":
			BossMap.build()
		"survivors":
			SurvivorsMap.build()
		"zombies":
			ZombiesMap.build()
	get_tree().change_scene_to_file("res://scenes/world/game.tscn")
