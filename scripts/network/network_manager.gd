extends Node

signal player_connected(peer_id: int)
signal player_disconnected(peer_id: int)
signal connection_succeeded()
signal connection_failed()
signal server_disconnected()

var players: Dictionary = {}
var is_host: bool = false

func _ready() -> void:
	pass

func get_player_info(peer_id: int) -> Dictionary:
	return players.get(peer_id, {"name": "Player", "smiley_id": 0})
