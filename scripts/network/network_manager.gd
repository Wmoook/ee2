extends Node

signal player_connected(peer_id: int)
signal player_disconnected(peer_id: int)
signal connection_succeeded()
signal connection_failed()
signal server_disconnected()
signal tunnel_ready(url: String)
signal chat_received(sender_name: String, message: String)

var players: Dictionary = {}  # peer_id -> {name, smiley_id}
var is_host: bool = false
var is_dedicated: bool = false  # this instance is the Railway headless server
var _peer: WebSocketMultiplayerPeer = null
var _tunnel_pid: int = -1
var tunnel_url: String = ""

func _ready() -> void:
	pass

## Railway headless server: listen for browser/desktop clients. No tunnel,
## no local player. NetPlay owns rooms; world pushes happen on world-join.
func start_dedicated(port: int) -> Error:
	_peer = WebSocketMultiplayerPeer.new()
	_peer.outbound_buffer_size = 64 * 1024 * 1024
	_peer.inbound_buffer_size = 64 * 1024 * 1024
	_peer.max_queued_packets = 4096
	var err: Error = _peer.create_server(port)
	if err != OK:
		_peer = null
		return err
	multiplayer.multiplayer_peer = _peer
	is_host = true
	is_dedicated = true
	multiplayer.peer_connected.connect(_on_peer_connected)
	multiplayer.peer_disconnected.connect(_on_peer_disconnected)
	return OK

## Relay recipients for a message from `sender`: room-mates on the dedicated
## server, everyone-but-sender on a classic player-hosted (LAN/tunnel) game.
func _relay_ids(sender: int) -> Array:
	if is_dedicated:
		return NetPlay.relay_targets(sender)
	var out: Array = []
	for pid in players:
		if pid != 1 and pid != sender:
			out.append(pid)
	return out

## Dedicated server: drop world edits from peers who aren't in the world room.
func _world_edit_ok(sender: int) -> bool:
	if not is_dedicated:
		return true
	if not NetPlay.is_world_peer(sender):
		return false
	NetPlay.world_dirty = true
	return true

func host_game(port: int) -> Error:
	_peer = WebSocketMultiplayerPeer.new()
	_peer.outbound_buffer_size = 64 * 1024 * 1024  # 64MB buffer for large worlds
	_peer.inbound_buffer_size = 64 * 1024 * 1024
	_peer.max_queued_packets = 4096
	var err: Error = _peer.create_server(port)
	if err != OK:
		_peer = null
		return err
	multiplayer.multiplayer_peer = _peer
	is_host = true
	players[1] = {"name": GameState.player_name, "smiley_id": GameState.player_smiley_id}
	multiplayer.peer_connected.connect(_on_peer_connected)
	multiplayer.peer_disconnected.connect(_on_peer_disconnected)
	# Start cloudflare tunnel in background
	_start_tunnel(port)
	return OK

func join_game(address: String, port: int) -> Error:
	_peer = WebSocketMultiplayerPeer.new()
	_peer.outbound_buffer_size = 64 * 1024 * 1024
	_peer.inbound_buffer_size = 64 * 1024 * 1024
	_peer.max_queued_packets = 4096
	var url: String
	if address.begins_with("wss://") or address.begins_with("ws://"):
		url = address
	elif address.contains(".") and not address.contains(":"):
		# Looks like a hostname (tunnel URL without protocol)
		url = "wss://" + address
	else:
		url = "ws://" + address + ":" + str(port)
	var err: Error = _peer.create_client(url)
	if err != OK:
		_peer = null
		return err
	multiplayer.multiplayer_peer = _peer
	is_host = false
	multiplayer.connected_to_server.connect(_on_connected_to_server)
	multiplayer.connection_failed.connect(_on_connection_failed)
	multiplayer.server_disconnected.connect(_on_server_disconnected)
	multiplayer.peer_connected.connect(_on_peer_connected)
	multiplayer.peer_disconnected.connect(_on_peer_disconnected)
	return OK

func disconnect_game() -> void:
	if is_dedicated:
		return  # the server never disconnects itself
	_stop_tunnel()
	if _peer:
		multiplayer.multiplayer_peer = null
		_peer = null
	players.clear()
	is_host = false
	NetPlay.online = false
	NetPlay.connecting = false
	NetPlay.my_room = ""
	NetPlay.room_info = {}

func get_player_info(peer_id: int) -> Dictionary:
	return players.get(peer_id, {"name": "Player", "smiley_id": 0})

# --- Cloudflare Tunnel ---

func _start_tunnel(port: int) -> void:
	var cf_path: String = OS.get_executable_path().get_base_dir() + "/tools/cloudflared.exe"
	if not FileAccess.file_exists(cf_path):
		cf_path = ProjectSettings.globalize_path("res://tools/cloudflared.exe")
	if not FileAccess.file_exists(cf_path):
		push_warning("cloudflared not found at: " + cf_path)
		tunnel_url = "cloudflared not found"
		tunnel_ready.emit(tunnel_url)
		return
	# Write output to a temp log file so we can read the URL
	var log_path: String = OS.get_user_data_dir() + "/cf_tunnel.log"
	# Redirect stderr to log file so we can read the tunnel URL
	var cmd: String = '"' + cf_path + '" tunnel --url http://localhost:' + str(port) + ' 2> "' + log_path + '"'
	var args: PackedStringArray = ["/c", cmd]
	_tunnel_pid = OS.create_process("cmd.exe", args)
	if _tunnel_pid <= 0:
		push_warning("Failed to start cloudflared tunnel")
		tunnel_url = "Failed to start tunnel"
		tunnel_ready.emit(tunnel_url)
		return
	# Poll the log file for the tunnel URL
	_poll_tunnel_log(log_path)

func _poll_tunnel_log(log_path: String) -> void:
	var attempts: int = 0
	while attempts < 20:  # Try for 20 seconds
		await get_tree().create_timer(1.0).timeout
		attempts += 1
		if not FileAccess.file_exists(log_path):
			continue
		var f: FileAccess = FileAccess.open(log_path, FileAccess.READ)
		if f == null:
			continue
		var text: String = f.get_as_text()
		f.close()
		# Look for the tunnel URL: https://xxx.trycloudflare.com
		var idx: int = text.find(".trycloudflare.com")
		if idx >= 0:
			# Walk back to find https://
			var start: int = text.rfind("https://", idx)
			if start >= 0:
				var end: int = text.find("\n", idx)
				if end < 0:
					end = text.length()
				tunnel_url = text.substr(start, end - start).strip_edges()
				# Convert to wss:// for WebSocket
				tunnel_url = tunnel_url.replace("https://", "wss://")
				push_warning("Tunnel URL: " + tunnel_url)
				tunnel_ready.emit(tunnel_url)
				return
	tunnel_url = "Tunnel timed out — check cloudflared window"
	tunnel_ready.emit(tunnel_url)

func _stop_tunnel() -> void:
	if _tunnel_pid > 0:
		OS.kill(_tunnel_pid)
		_tunnel_pid = -1
	tunnel_url = ""

# --- Connection events ---

func _on_peer_connected(id: int) -> void:
	if is_dedicated:
		NetPlay.server_peer_connected(id)
		return
	if is_host:
		WorldManager.send_world_to_peer(id)
		var pl_json: String = JSON.stringify(players)
		_sync_player_list.rpc_id(id, pl_json)

func _on_peer_disconnected(id: int) -> void:
	if is_dedicated:
		NetPlay.server_peer_left(id)
		return
	players.erase(id)
	player_disconnected.emit(id)

func _on_connected_to_server() -> void:
	var info: Dictionary = {"name": GameState.player_name, "smiley_id": GameState.player_smiley_id}
	_register_player.rpc_id(1, JSON.stringify(info))
	connection_succeeded.emit()

func _on_connection_failed() -> void:
	connection_failed.emit()
	disconnect_game()

func _on_server_disconnected() -> void:
	server_disconnected.emit()
	disconnect_game()

# --- RPCs ---

@rpc("any_peer", "reliable")
func _register_player(info_json: String) -> void:
	var id: int = multiplayer.get_remote_sender_id()
	var info: Dictionary = JSON.parse_string(info_json)
	if info == null:
		info = {"name": "Player", "smiley_id": 0}
	if is_dedicated:
		# Rooms own the player registry on the dedicated server
		NetPlay._server_hello(id, info)
		return
	players[id] = info
	var pl_json: String = JSON.stringify(players)
	_sync_player_list.rpc(pl_json)
	player_connected.emit(id)

@rpc("authority", "reliable")
func _sync_player_list(players_json: String) -> void:
	var data: Dictionary = JSON.parse_string(players_json)
	if data == null:
		return
	for key in data:
		var id: int = int(key)
		if not players.has(id):
			players[id] = data[key]
			player_connected.emit(id)
		else:
			players[id] = data[key]

@rpc("any_peer", "reliable", "call_remote")
func _net_sync_tile(x: int, y: int, block_id: int, layer: String) -> void:
	var sender: int = multiplayer.get_remote_sender_id()
	if is_host and sender != 0 and not _world_edit_ok(sender):
		return
	if layer == "fg":
		WorldManager.set_fg_tile(x, y, block_id)
	elif layer == "bg":
		WorldManager.set_bg_tile(x, y, block_id)
	# In Godot 4 SceneMultiplayer, a client's .rpc() only reaches the server —
	# the server must re-broadcast so other clients also receive the change.
	if is_host and sender != 0:
		for pid in _relay_ids(sender):
			_net_sync_tile.rpc_id(pid, x, y, block_id, layer)

## --- World edit sync (all on autoload for stable RPC path) ---

func send_clear_world() -> void:
	if _peer == null:
		return
	_receive_clear_world.rpc()

@rpc("any_peer", "reliable", "call_remote")
func _receive_clear_world() -> void:
	var sender: int = multiplayer.get_remote_sender_id()
	if is_host and sender != 0 and not _world_edit_ok(sender):
		return
	WorldManager.free_blocks.clear()
	WorldManager.block_groups.clear()
	WorldManager.polylines.clear()
	WorldManager.lines.clear()
	WorldManager.gravity_zones.clear()
	for y in range(1, WorldManager.world_height - 1):
		for x in range(1, WorldManager.world_width - 1):
			WorldManager.set_fg_tile(x, y, 0)
			WorldManager.set_bg_tile(x, y, 0)
			WorldManager.set_rotation(x, y, 0)
	WorldManager.tile_changed.emit(0, 0, 0)
	WorldManager.polylines_changed.emit()
	if is_host and sender != 0:
		for pid in _relay_ids(sender):
			_receive_clear_world.rpc_id(pid)

func send_freeblocks(blocks: Array) -> void:
	if _peer == null:
		return
	_receive_freeblocks.rpc(blocks)

@rpc("any_peer", "reliable", "call_remote")
func _receive_freeblocks(blocks: Array) -> void:
	var sender: int = multiplayer.get_remote_sender_id()
	if is_host and sender != 0 and not _world_edit_ok(sender):
		return
	for b in blocks:
		WorldManager.free_blocks.append({"pos": Vector2(b.pos_x, b.pos_y), "id": b.id, "rotation": b.rot})
	WorldManager.tile_changed.emit(0, 0, 0)
	if is_host and sender != 0:
		for pid in _relay_ids(sender):
			_receive_freeblocks.rpc_id(pid, blocks)

func send_fb_replace(remove_count: int, blocks: Array) -> void:
	if _peer == null:
		return
	_receive_fb_replace.rpc(remove_count, blocks)

@rpc("any_peer", "reliable", "call_remote")
func _receive_fb_replace(remove_count: int, blocks: Array) -> void:
	var sender: int = multiplayer.get_remote_sender_id()
	if is_host and sender != 0 and not _world_edit_ok(sender):
		return
	if remove_count > 0 and remove_count <= WorldManager.free_blocks.size():
		WorldManager.free_blocks.resize(WorldManager.free_blocks.size() - remove_count)
	for b in blocks:
		WorldManager.free_blocks.append({"pos": Vector2(b.pos_x, b.pos_y), "id": b.id, "rotation": b.rot})
	WorldManager.tile_changed.emit(0, 0, 0)
	if is_host and sender != 0:
		for pid in _relay_ids(sender):
			_receive_fb_replace.rpc_id(pid, remove_count, blocks)

func send_polylines(polylines: Array) -> void:
	if _peer == null:
		return
	_receive_polylines.rpc(polylines)

@rpc("any_peer", "reliable", "call_remote")
func _receive_polylines(poly_data: Array) -> void:
	var sender: int = multiplayer.get_remote_sender_id()
	if is_host and sender != 0 and not _world_edit_ok(sender):
		return
	for pl in poly_data:
		var pts: PackedVector2Array = PackedVector2Array()
		for p in pl.pts:
			pts.append(Vector2(p.x, p.y))
		WorldManager.add_polyline(pts, pl.side, pl.bid)
	if is_host and sender != 0:
		for pid in _relay_ids(sender):
			_receive_polylines.rpc_id(pid, poly_data)

func send_deletions(deletions: Array) -> void:
	if _peer == null:
		return
	_receive_deletions.rpc(deletions)

@rpc("any_peer", "reliable", "call_remote")
func _receive_deletions(deletions: Array) -> void:
	var _rx_sender: int = multiplayer.get_remote_sender_id()
	if is_host and _rx_sender != 0 and not _world_edit_ok(_rx_sender):
		return
	for d in deletions:
		if d.type == "fb":
			for i in range(WorldManager.free_blocks.size() - 1, -1, -1):
				var fb: Dictionary = WorldManager.free_blocks[i]
				if fb.id == d.id and absf(fb.pos.x - d.x) < 2.0 and absf(fb.pos.y - d.y) < 2.0:
					WorldManager.free_blocks.remove_at(i)
					break
		elif d.type == "poly":
			WorldManager.remove_polyline_near(Vector2(d.x, d.y), d.r)
	WorldManager.tile_changed.emit(0, 0, 0)
	if is_host and _rx_sender != 0:
		for pid in _relay_ids(_rx_sender):
			_receive_deletions.rpc_id(pid, deletions)

func send_poly_fullsync() -> void:
	if _peer == null:
		return
	# Serialize all non-collision-only, non-render-only polylines
	var poly_data: Array = []
	for poly in WorldManager.polylines:
		if poly.get("collision_only", false):
			continue
		if poly.get("render_only", false):
			continue
		var pts_arr: Array = []
		for pt in poly.points:
			pts_arr.append({"x": pt.x, "y": pt.y})
		poly_data.append({"pts": pts_arr, "side": poly.side, "bid": poly.get("block_id", 9)})
	_receive_poly_fullsync.rpc(poly_data)

@rpc("any_peer", "reliable", "call_remote")
func _receive_poly_fullsync(poly_data: Array) -> void:
	var _fs_sender: int = multiplayer.get_remote_sender_id()
	if is_host and _fs_sender != 0 and not _world_edit_ok(_fs_sender):
		return
	# Replace ALL polylines with the received set
	WorldManager.polylines.clear()
	for pd in poly_data:
		var packed_pts: PackedVector2Array = PackedVector2Array()
		for pt in pd.pts:
			packed_pts.append(Vector2(pt.x, pt.y))
		WorldManager.add_polyline(packed_pts, pd.side, pd.get("bid", 9))
	WorldManager.polylines_changed.emit()
	# Server relays
	if is_host and _fs_sender != 0:
		for pid in _relay_ids(_fs_sender):
			_receive_poly_fullsync.rpc_id(pid, poly_data)

func send_gz_changes(gz_changes: Array) -> void:
	if _peer == null:
		return
	_receive_gz.rpc(gz_changes)

@rpc("any_peer", "reliable", "call_remote")
func _receive_gz(gz_changes: Array) -> void:
	var _gz_sender: int = multiplayer.get_remote_sender_id()
	if is_host and _gz_sender != 0 and not _world_edit_ok(_gz_sender):
		return
	for gz in gz_changes:
		var action: String = str(gz.get("action", ""))
		if action == "add":
			WorldManager.gravity_zones.add_zone(
				Vector2(gz.cx, gz.cy), gz.r, gz.get("s", 2.0), gz.get("cr", 8.0))
		elif action == "remove":
			WorldManager.gravity_zones.remove_zone_near(
				Vector2(gz.cx, gz.cy), gz.get("t", 24.0))
		elif action == "clear":
			WorldManager.gravity_zones.clear()
	# Server relays to other clients (not back to sender)
	if is_host and _gz_sender != 0:
		for pid in _relay_ids(_gz_sender):
			_receive_gz.rpc_id(pid, gz_changes)

func send_chat(message: String) -> void:
	if _peer == null:
		# Offline: just show locally
		chat_received.emit(GameState.player_name, message)
		return
	_receive_chat.rpc(GameState.player_name, message)
	# Also show locally (rpc call_remote doesn't call on self)
	chat_received.emit(GameState.player_name, message)

@rpc("any_peer", "reliable", "call_remote")
func _receive_chat(sender_name: String, message: String) -> void:
	var sender: int = multiplayer.get_remote_sender_id()
	if not is_dedicated:
		chat_received.emit(sender_name, message)
	# Server relays to the sender's room only (not back to sender)
	if is_host and sender != 0:
		for pid in _relay_ids(sender):
			_receive_chat.rpc_id(pid, sender_name, message)
