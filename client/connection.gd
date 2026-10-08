# The phone's socket to the server. It keeps the connection alive and, on every (re)connection, picks the seat up again with
# the saved token. It knows nothing about the game: it hands each message to SessionModel (via the `received` signal) and sends
# the text it is given.
extends Node

const SessionModelScript = preload("res://client/session_model.gd")
const SerializerScript = preload("res://scripts/serializer.gd")

signal received(message: Dictionary)
signal state_changed          # connected / not connected / trying again

const SAVE_PATH := "user://session.json"
const FIRST_RETRY_MS := 1000
const LONGEST_RETRY_MS := 15000

var model = SessionModelScript.new()
var url: String = "ws://127.0.0.1:9080"
var wanted: bool = false         # should we be connected? (false after quit / before connect_to_server)
var socket: WebSocketPeer = null
var retry_in_ms: int = FIRST_RETRY_MS
var next_try_ms: int = 0
var was_open: bool = false


func _ready() -> void:
	load_saved()


# Starts (or restarts) the connection to this address.
func connect_to_server(address: String) -> void:
	url = address.strip_edges()
	wanted = true
	retry_in_ms = FIRST_RETRY_MS
	_open()


func disconnect_from_server() -> void:
	wanted = false
	if socket != null:
		socket.close()


func send_text(text: String) -> bool:
	if socket == null or socket.get_ready_state() != WebSocketPeer.STATE_OPEN:
		return false
	socket.send_text(text)
	return true


func _process(_delta: float) -> void:
	if socket == null:
		if wanted and Time.get_ticks_msec() >= next_try_ms:
			_open()
		return
	socket.poll()
	match socket.get_ready_state():
		WebSocketPeer.STATE_OPEN:
			if not was_open:
				was_open = true
				retry_in_ms = FIRST_RETRY_MS
				model.connected = true
				state_changed.emit()
				if model.has_saved_seat():
					send_text(model.make_resume())   # back to our seat, if the server still has it
			while socket.get_available_packet_count() > 0:
				var packet: PackedByteArray = socket.get_packet()
				if socket.was_string_packet():
					_handle(packet.get_string_from_utf8())
		WebSocketPeer.STATE_CLOSED:
			socket = null
			var was: bool = was_open
			was_open = false
			model.connected = false
			state_changed.emit()
			if wanted:
				next_try_ms = Time.get_ticks_msec() + retry_in_ms
				retry_in_ms = mini(retry_in_ms * 2, LONGEST_RETRY_MS)
			if was:
				next_try_ms = Time.get_ticks_msec() + FIRST_RETRY_MS


func _open() -> void:
	socket = WebSocketPeer.new()
	was_open = false
	if socket.connect_to_url(url) != OK:
		socket = null
		next_try_ms = Time.get_ticks_msec() + retry_in_ms
		retry_in_ms = mini(retry_in_ms * 2, LONGEST_RETRY_MS)


func _handle(text: String) -> void:
	var errors: Array = []
	var message = SerializerScript.from_json(text, errors)
	if not errors.is_empty() or typeof(message) != TYPE_DICTIONARY:
		return   # the server only sends objects; anything else is ignored
	model.apply(message)
	if message.get("type", "") in ["welcome", "left"] or (message.get("type", "") == "error" and model.token == ""):
		save()
	received.emit(message)


func save() -> void:
	var file: FileAccess = FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	if file != null:
		var data: Dictionary = model.to_save()
		data["url"] = url
		file.store_string(JSON.stringify(data))


func load_saved() -> void:
	if not FileAccess.file_exists(SAVE_PATH):
		return
	var parsed = JSON.parse_string(FileAccess.get_file_as_string(SAVE_PATH))
	if typeof(parsed) == TYPE_DICTIONARY:
		model.from_save(parsed)
		url = str(parsed.get("url", url))
