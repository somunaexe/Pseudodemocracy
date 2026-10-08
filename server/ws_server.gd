# The network end of the server: accepts WebSocket connections and hands their messages to ServerCore.
#
#   godot --headless --script server/ws_server.gd -- --port 9080
#
# It speaks plain ws:// . For the public internet put a TLS proxy (Caddy, nginx) in front and give players a wss:// address.
# Everything that matters (rooms, seats, rules, who sees what) is in server_core.gd; this file only moves bytes.
extends SceneTree

const CoreScript = preload("res://server/server_core.gd")

const DEFAULT_PORT := 9080
const MAX_PENDING := 64            # connections still shaking hands
const HANDSHAKE_TIMEOUT_MS := 5000
const MAX_FRAME_BYTES := 70000     # a little over the command limit; the core refuses what is too big

var core = CoreScript.new()
var tcp: TCPServer = TCPServer.new()
var pending: Array = []            # { "peer": WebSocketPeer, "since": int }
var peers: Dictionary = {}         # connection id -> WebSocketPeer
var next_id: int = 1


func _init() -> void:
	var port: int = DEFAULT_PORT
	var args: PackedStringArray = OS.get_cmdline_user_args()
	for i in args.size():
		if args[i] == "--port" and i + 1 < args.size():
			port = int(args[i + 1])
	var error: int = tcp.listen(port)
	if error != OK:
		push_error("can't listen on port %d (error %d)" % [port, error])
		quit(1)
		return
	print("Pseudodemocracy server listening on port %d" % port)


func _process(_delta: float) -> bool:
	var now: int = int(Time.get_unix_time_from_system() * 1000.0)
	_accept(now)
	_read(now)
	_flush(core.tick(now))
	return false


func _accept(now: int) -> void:
	while tcp.is_connection_available():
		var stream: StreamPeerTCP = tcp.take_connection()
		if pending.size() >= MAX_PENDING:
			stream.disconnect_from_host()
			continue
		var peer: WebSocketPeer = WebSocketPeer.new()
		peer.inbound_buffer_size = MAX_FRAME_BYTES * 2
		peer.max_queued_packets = 64
		peer.accept_stream(stream)
		pending.append({"peer": peer, "since": now})
	for entry in pending.duplicate():
		var peer: WebSocketPeer = entry["peer"]
		peer.poll()
		match peer.get_ready_state():
			WebSocketPeer.STATE_OPEN:
				pending.erase(entry)
				var id: int = next_id
				next_id += 1
				peers[id] = peer
				core.connect_peer(id, now)
			WebSocketPeer.STATE_CLOSING, WebSocketPeer.STATE_CLOSED:
				pending.erase(entry)
			_:
				if now - entry["since"] > HANDSHAKE_TIMEOUT_MS:
					peer.close()
					pending.erase(entry)


func _read(now: int) -> void:
	for id in peers.keys():
		var peer: WebSocketPeer = peers[id]
		peer.poll()
		while peer.get_ready_state() == WebSocketPeer.STATE_OPEN and peer.get_available_packet_count() > 0:
			var packet: PackedByteArray = peer.get_packet()
			if peer.was_string_packet():
				_flush(core.receive(id, packet.get_string_from_utf8(), now))
		if peer.get_ready_state() == WebSocketPeer.STATE_CLOSED:
			peers.erase(id)
			_flush(core.disconnect_peer(id, now))


func _flush(out: Array) -> void:
	for item in out:
		var peer: WebSocketPeer = peers.get(item["to"])
		if peer != null and peer.get_ready_state() == WebSocketPeer.STATE_OPEN:
			peer.send_text(item["text"])
