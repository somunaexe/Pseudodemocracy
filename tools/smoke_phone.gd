# Used by tools/smoke_server.sh: the phone's own Connection + SessionModel against the real server. Makes a room, then
# drops the socket and checks the phone gets the same seat back by itself.
extends SceneTree

const ConnectionScript = preload("res://client/connection.gd")

var connection
var step := 0
var frames := 0
var first_code := ""


func _init() -> void:
	DirAccess.remove_absolute("user://session.json")
	connection = ConnectionScript.new()
	get_root().add_child(connection)
	connection.connect_to_server("ws://127.0.0.1:" + OS.get_cmdline_user_args()[0])


func _process(_delta: float) -> bool:
	frames += 1
	var model = connection.model
	match step:
		0:
			if model.connected:
				connection.send_text(model.make_create_room("Ada", "female"))
				step = 1
		1:
			if model.stage() == model.Stage.LOBBY and model.seat == 1:
				first_code = model.code
				connection.socket.close()   # the network drops
				step = 2
		2:
			if model.connected and not model.resuming() and model.code == first_code and frames > 30:
				print("PHONE SMOKE OK: same seat %d in room %s after reconnecting" % [model.seat, model.code])
				DirAccess.remove_absolute("user://session.json")
				quit(0)
	if frames > 1500:
		print("PHONE SMOKE TIMEOUT at step %d" % step)
		DirAccess.remove_absolute("user://session.json")
		quit(1)
	return false
