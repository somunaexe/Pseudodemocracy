# The app's entry: joins the connection, the session model and the screens together.
extends Node

const ConnectionScript = preload("res://client/connection.gd")
const LobbyScreenScript = preload("res://client/lobby_screen.gd")

var connection
var lobby


func _ready() -> void:
	connection = ConnectionScript.new()
	add_child(connection)
	lobby = LobbyScreenScript.new()
	lobby.model = connection.model
	add_child(lobby)
	var args: PackedStringArray = OS.get_cmdline_user_args()
	for i in args.size():
		if args[i] == "--server" and i + 1 < args.size():
			connection.url = args[i + 1]
	lobby.server_field.text = connection.url
	lobby.connect_requested.connect(_on_connect)
	lobby.create_requested.connect(func(name, gender): connection.send_text(connection.model.make_create_room(name, gender)))
	lobby.join_requested.connect(func(room_code, name, gender): connection.send_text(connection.model.make_join_room(room_code, name, gender)))
	lobby.start_requested.connect(func(): connection.send_text(connection.model.make_start_game()))
	lobby.leave_requested.connect(func(): connection.send_text(connection.model.make_leave()))
	connection.received.connect(func(_message): lobby.refresh())
	connection.state_changed.connect(lobby.refresh)
	if connection.model.has_saved_seat() or args.has("--server"):
		connection.connect_to_server(connection.url)   # back into the game we were in
	lobby.refresh()


func _on_connect(address: String) -> void:
	lobby.show_message("")
	connection.connect_to_server(address)
