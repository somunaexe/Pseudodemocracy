# The app's entry: joins the connection, the session model and the screens together.
extends Node

const ConnectionScript = preload("res://client/connection.gd")
const LobbyScreenScript = preload("res://client/lobby_screen.gd")
const TableScreenScript = preload("res://client/table_screen.gd")
const SessionModelScript = preload("res://client/session_model.gd")

var connection
var lobby
var table


func _ready() -> void:
	connection = ConnectionScript.new()
	add_child(connection)
	lobby = LobbyScreenScript.new()
	lobby.model = connection.model
	add_child(lobby)
	table = TableScreenScript.new()
	table.model = connection.model
	add_child(table)
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
	table.command_requested.connect(func(command): connection.send_text(connection.model.make_command(command)))
	connection.received.connect(func(_message): _refresh())
	connection.state_changed.connect(_refresh)
	if connection.model.has_saved_seat() or args.has("--server"):
		connection.connect_to_server(connection.url)   # back into the game we were in
	_refresh()


# Whichever screen the session is at, and only that one.
func _refresh() -> void:
	var playing: bool = connection.model.stage() == SessionModelScript.Stage.PLAYING and not connection.model.resuming()
	lobby.visible = not playing
	table.visible = playing
	if playing:
		table.refresh()
	else:
		lobby.refresh()


func _on_connect(address: String) -> void:
	lobby.show_message("")
	connection.connect_to_server(address)
