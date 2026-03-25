extends Node

signal player_connected(peer_id: int)
signal player_disconnected(peer_id: int)
signal connection_succeeded()
signal connection_failed()
signal server_disconnected()

var players: Dictionary = {}  # peer_id -> {name, smiley_id}
var is_host: bool = false
var _peer: ENetMultiplayerPeer = null

func _ready() -> void:
	pass

func host_game(port: int) -> Error:
	_peer = ENetMultiplayerPeer.new()
	var err: Error = _peer.create_server(port, 16)
	if err != OK:
		_peer = null
		return err
	multiplayer.multiplayer_peer = _peer
	is_host = true
	# Register self
	players[1] = {"name": GameState.player_name, "smiley_id": GameState.player_smiley_id}
	# Connect signals
	multiplayer.peer_connected.connect(_on_peer_connected)
	multiplayer.peer_disconnected.connect(_on_peer_disconnected)
	return OK

func join_game(ip: String, port: int) -> Error:
	_peer = ENetMultiplayerPeer.new()
	var err: Error = _peer.create_client(ip, port)
	if err != OK:
		_peer = null
		return err
	multiplayer.multiplayer_peer = _peer
	is_host = false
	# Connect signals
	multiplayer.connected_to_server.connect(_on_connected_to_server)
	multiplayer.connection_failed.connect(_on_connection_failed)
	multiplayer.server_disconnected.connect(_on_server_disconnected)
	multiplayer.peer_connected.connect(_on_peer_connected)
	multiplayer.peer_disconnected.connect(_on_peer_disconnected)
	return OK

func disconnect_game() -> void:
	if _peer:
		multiplayer.multiplayer_peer = null
		_peer = null
	players.clear()
	is_host = false

func get_player_info(peer_id: int) -> Dictionary:
	return players.get(peer_id, {"name": "Player", "smiley_id": 0})

# --- Connection events ---

func _on_peer_connected(id: int) -> void:
	# When host: a new client connected. Send them the world + player list.
	if is_host:
		# Send world state
		WorldManager.send_world_to_peer(id)
		# Send existing player list to new peer
		var pl_json: String = JSON.stringify(players)
		_sync_player_list.rpc_id(id, pl_json)

func _on_peer_disconnected(id: int) -> void:
	players.erase(id)
	player_disconnected.emit(id)

func _on_connected_to_server() -> void:
	# Client connected — send our info to server
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
	# Server receives player info from a joining client
	var id: int = multiplayer.get_remote_sender_id()
	var info: Dictionary = JSON.parse_string(info_json)
	if info == null:
		info = {"name": "Player", "smiley_id": 0}
	players[id] = info
	# Broadcast updated player list to ALL peers
	var pl_json: String = JSON.stringify(players)
	_sync_player_list.rpc(pl_json)
	# Emit signal so game scene spawns the player
	player_connected.emit(id)

@rpc("authority", "reliable")
func _sync_player_list(players_json: String) -> void:
	# Client receives the full player list from server
	var data: Dictionary = JSON.parse_string(players_json)
	if data == null:
		return
	# Convert string keys back to int
	for key in data:
		var id: int = int(key)
		if not players.has(id):
			players[id] = data[key]
			player_connected.emit(id)
		else:
			players[id] = data[key]
