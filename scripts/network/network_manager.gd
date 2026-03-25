extends Node

signal player_connected(peer_id: int)
signal player_disconnected(peer_id: int)
signal connection_succeeded()
signal connection_failed()
signal server_disconnected()
signal tunnel_ready(url: String)

var players: Dictionary = {}  # peer_id -> {name, smiley_id}
var is_host: bool = false
var _peer: WebSocketMultiplayerPeer = null
var _tunnel_pid: int = -1
var tunnel_url: String = ""

func _ready() -> void:
	pass

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
	_stop_tunnel()
	if _peer:
		multiplayer.multiplayer_peer = null
		_peer = null
	players.clear()
	is_host = false

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
	if is_host:
		WorldManager.send_world_to_peer(id)
		var pl_json: String = JSON.stringify(players)
		_sync_player_list.rpc_id(id, pl_json)

func _on_peer_disconnected(id: int) -> void:
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

var _tile_debug_label: Label = null

@rpc("any_peer", "reliable", "call_remote")
func _net_sync_tile(x: int, y: int, block_id: int, layer: String) -> void:
	# DEBUG: show on screen that we received a tile
	if _tile_debug_label == null:
		var c: CanvasLayer = CanvasLayer.new()
		c.layer = 100
		add_child(c)
		_tile_debug_label = Label.new()
		_tile_debug_label.position = Vector2(10, 50)
		_tile_debug_label.add_theme_font_size_override("font_size", 16)
		_tile_debug_label.add_theme_color_override("font_color", Color(1, 1, 0))
		c.add_child(_tile_debug_label)
	_tile_debug_label.text = "TILE RPC: x=%d y=%d id=%d layer=%s" % [x, y, block_id, layer]
	if layer == "fg":
		WorldManager.set_fg_tile(x, y, block_id)
	elif layer == "bg":
		WorldManager.set_bg_tile(x, y, block_id)
	# If we are the server and this came from a client, relay to all other clients.
	# In Godot 4 SceneMultiplayer, a client's .rpc() only reaches the server —
	# the server must re-broadcast so other clients also receive the change.
	if is_host and multiplayer.get_remote_sender_id() != 0:
		_net_sync_tile.rpc(x, y, block_id, layer)
