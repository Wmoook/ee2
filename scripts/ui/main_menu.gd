extends Control
## Main menu - Host/Join/Quit flow with Cloudflare Tunnel support

@onready var name_input: LineEdit = $VBox/NameInput
@onready var smiley_input: SpinBox = $VBox/SmileyInput
@onready var host_btn: Button = $VBox/HostBtn
@onready var join_btn: Button = $VBox/JoinBtn
@onready var quit_btn: Button = $VBox/QuitBtn
@onready var ip_input: LineEdit = $VBox/HBoxJoin/IPInput
@onready var port_input: LineEdit = $VBox/HBoxJoin/PortInput
@onready var status_label: Label = $VBox/StatusLabel

func _ready() -> void:
	host_btn.pressed.connect(_on_host)
	join_btn.pressed.connect(_on_join)
	quit_btn.pressed.connect(_on_quit)
	NetworkManager.connection_succeeded.connect(_on_connected)
	NetworkManager.connection_failed.connect(_on_connect_failed)
	NetworkManager.server_disconnected.connect(_on_server_dc)
	NetworkManager.tunnel_ready.connect(_on_tunnel_ready)

	name_input.text = GameState.player_name
	smiley_input.value = GameState.player_smiley_id

func _on_host() -> void:
	_apply_settings()
	var port := int(port_input.text) if port_input.text.is_valid_int() else 7777
	status_label.text = "Starting server on port %d..." % port
	var err := NetworkManager.host_game(port)
	if err != OK:
		status_label.text = "Failed to host: %s" % error_string(err)
		return
	status_label.text = "Hosting! Starting tunnel..."
	var load_err := WorldManager.load_from_file("user://world_save.json")
	if load_err != OK:
		WorldManager.build_sample_room()
	get_tree().change_scene_to_file("res://scenes/world/game.tscn")

func _on_join() -> void:
	_apply_settings()
	var address := ip_input.text.strip_edges()
	if address.is_empty():
		address = "127.0.0.1"
	var port := int(port_input.text) if port_input.text.is_valid_int() else 7777
	# Detect if it's a tunnel URL or direct IP
	if address.contains("trycloudflare.com") or address.begins_with("wss://"):
		status_label.text = "Connecting to tunnel..."
	else:
		status_label.text = "Connecting to %s:%d..." % [address, port]
	var err := NetworkManager.join_game(address, port)
	if err != OK:
		status_label.text = "Failed to connect: %s" % error_string(err)

func _on_connected() -> void:
	status_label.text = "Connected! Waiting for world data..."
	host_btn.disabled = true
	join_btn.disabled = true
	WorldManager.world_loaded.connect(_on_world_received, CONNECT_ONE_SHOT)

func _on_world_received() -> void:
	status_label.text = "World loaded! Entering..."
	get_tree().change_scene_to_file("res://scenes/world/game.tscn")

func _on_tunnel_ready(url: String) -> void:
	status_label.text = "Tunnel: " + url

func _on_connect_failed() -> void:
	status_label.text = "Connection failed! Is the server running?"
	host_btn.disabled = false
	join_btn.disabled = false

func _on_server_dc() -> void:
	status_label.text = "Disconnected from server."
	host_btn.disabled = false
	join_btn.disabled = false

func _on_quit() -> void:
	get_tree().quit()

func _apply_settings() -> void:
	GameState.player_name = name_input.text.strip_edges()
	if GameState.player_name.is_empty():
		GameState.player_name = "Player"
	GameState.player_smiley_id = int(smiley_input.value)
