# Used by tools/smoke_server.sh: connects, makes a room and waits for the welcome and room messages.
extends SceneTree
var ws := WebSocketPeer.new()
var step := 0
var t := 0
func _init():
	ws.connect_to_url("ws://127.0.0.1:" + OS.get_cmdline_user_args()[0])
func _process(d):
	ws.poll()
	t += 1
	if ws.get_ready_state() == WebSocketPeer.STATE_OPEN:
		if step == 0:
			ws.send_text('{"type":"create_room","name":"Ada"}')
			step = 1
		while ws.get_available_packet_count() > 0:
			print("GOT ", ws.get_packet().get_string_from_utf8().left(120))
			step += 1
		if step >= 3:
			quit(0)
	if t > 600:
		print("TIMEOUT"); quit(1)
	return false
