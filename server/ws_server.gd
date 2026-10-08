# The network end of the server: accepts WebSocket connections and hands their messages to ServerCore.
#
#   godot --headless --script server/ws_server.gd -- --port 9080 --data /var/lib/pseudodemocracy
#
# --port   the TCP port (default 9080; PORT in the environment works too)
# --data   where rooms are saved after every move (default user://rooms; DATA_DIR in the environment works too)
# --max    most connections at once (default 500)
#
# It speaks plain ws:// . For the public internet put a TLS proxy (Caddy, nginx) in front and give players a wss:// address.
# Everything that matters (rooms, seats, rules, who sees what) is in server_core.gd; this file only moves bytes.
extends SceneTree

const CoreScript = preload("res://server/server_core.gd")
const DiskStoreScript = preload("res://server/disk_store.gd")

const DEFAULT_PORT := 9080
const MAX_PENDING := 64            # connections still shaking hands
const HANDSHAKE_TIMEOUT_MS := 5000
const DEFAULT_MAX_CONNECTIONS := 500
const MAX_FRAME_BYTES := 70000     # a little over the command limit; the core refuses what is too big

var core = CoreScript.new()
var tcp: TCPServer = TCPServer.new()
var pending: Array = []            # { "peer": WebSocketPeer, "since": int }
var peers: Dictionary = {}         # connection id -> WebSocketPeer
var next_id: int = 1
var max_connections: int = DEFAULT_MAX_CONNECTIONS


func _init() -> void:
	var port: int = int(OS.get_environment("PORT")) if OS.get_environment("PORT") != "" else DEFAULT_PORT
	var data_dir: String = OS.get_environment("DATA_DIR") if OS.get_environment("DATA_DIR") != "" else "user://rooms"
	var args: PackedStringArray = OS.get_cmdline_user_args()
	for i in args.size():
		if i + 1 >= args.size():
			break
		match args[i]:
			"--port": port = int(args[i + 1])
			"--data": data_dir = args[i + 1]
			"--max": max_connections = int(args[i + 1])
	core.store = DiskStoreScript.new(data_dir)
	var now: int = int(Time.get_unix_time_from_system() * 1000.0)
	print("%d saved room(s) restored from %s" % [core.load_saved(now), data_dir])
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
		if pending.size() >= MAX_PENDING or pending.size() + peers.size() >= max_connections:
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
