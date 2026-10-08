# The server's brain, with no network in it: rooms, seats, reconnect tokens and who is told what.
#
# The transport (ws_server.gd) hands every message that arrives to receive() together with the id of the connection it came
# from, and sends back whatever comes out: a list of { "to": connection id, "text": JSON }. Nothing here opens a socket,
# reads a clock or rolls a die by itself, so the whole thing is tested headless with pretend connections.
#
# THE RULES OF THE ROAD
#  - The server owns every GameState. A client only ever ASKS (a command); it never says who it is: the connection's seat
#    decides that, so nobody can act as another player.
#  - A client is sent the events it may see (Views.deliver) and its own view of the state (Views.state_view), never the state.
#  - Every message is checked: size, shape, rate. A bad one gets an "error" and changes nothing.
#
# Client to server (JSON objects, "type" first):
#   { "type": "create_room", "name": "Ada", "gender": "female" }      gender is optional
#   { "type": "join_room", "code": "KQTZ", "name": "Bola", "gender": "male" }
#   { "type": "resume", "token": "..." }                                a dropped connection picks its seat up again
#   { "type": "start_game" }                                            the host, with 3 to 10 players
#   { "type": "command", "command": { "type": "cast_vote", ... } }      anything the game understands
#   { "type": "sync" }                                                  send me the whole picture again
#   { "type": "leave" }                                                 leave a room that has not started
# Server to client:
#   welcome { token, code, you }   room { code, host, started, members:[{seat, name, connected}] }
#   events { events }   state { view, full }   error { reason }

const GameScript = preload("res://scripts/game.gd")
const GameDataScript = preload("res://scripts/game_data.gd")
const SerializerScript = preload("res://scripts/serializer.gd")
const ViewsScript = preload("res://scripts/views.gd")
const GendersScript = preload("res://scripts/genders.gd")

const CODE_LETTERS := "ABCDEFGHJKLMNPQRSTUVWXYZ"   # no I or O: they read as 1 and 0
const CODE_LENGTH := 4
const NAME_MAX := 24
const MAX_ROOMS := 200
const BURST := 20              # a connection may send this many messages at once...
const REFILL_PER_SECOND := 8   # ...and gets this many more every second
const PRUNE_EVERY_MS := 60000
const LOBBY_IDLE_MS := 1800000          # a room that never started and has nobody in it is dropped after 30 minutes
const FINISHED_KEEP_MS := 3600000       # a finished game is kept for an hour (long enough to look at the result and rematch)
const ABANDONED_KEEP_MS := 10800000     # a running game with nobody connected for 3 hours is dropped. A game left alone normally
										# ends long before: absent players are eliminated after two missed turns (see Absence)
const SAVE_VERSION := 1
const CLIENT_TYPES := ["create_room", "join_room", "resume", "start_game", "command", "sync", "leave"]

var rooms: Dictionary = {}     # code -> room
var members: Dictionary = {}   # token -> member { token, name, gender, code, seat, conn }
var conns: Dictionary = {}     # connection id -> { "token": String, "tokens": float, "at": int }
var rng: RandomNumberGenerator = RandomNumberGenerator.new()
var now_ms: int = 0
var store = null                  # where rooms are saved after every change (DiskStore or MemoryStore); null = nowhere
var last_prune_ms: int = 0
var secure_tokens: bool = false   # a real server draws tokens from the operating system; a seeded test server does not


# A server with its own dice; give a seed to make a test repeatable.
func _init(seed_value: int = 0) -> void:
	if seed_value == 0:
		rng.randomize()
		secure_tokens = true
	else:
		rng.seed = seed_value


# --- connections --------------------------------------------------------------------------

func connect_peer(conn: int, now: int) -> void:
	now_ms = maxi(now_ms, now)
	conns[conn] = {"token": "", "tokens": float(BURST), "at": now_ms}


# The connection dropped. Their seat stays: the game goes on (the clocks cover an absent player) and they may resume.
func disconnect_peer(conn: int, now: int) -> Array:
	now_ms = maxi(now_ms, now)
	var out: Array = []
	if not conns.has(conn):
		return out
	var token: String = conns[conn]["token"]
	conns.erase(conn)
	if token != "" and members.has(token) and members[token]["conn"] == conn:
		members[token]["conn"] = -1
		rooms[members[token]["code"]]["touched"] = now_ms
		_announce_room(out, rooms[members[token]["code"]])
	return out


# A message from a connection. Returns what to send.
func receive(conn: int, text: String, now: int) -> Array:
	now_ms = maxi(now_ms, now)
	var out: Array = []
	if not conns.has(conn):
		return out
	if not _allow(conn):
		_error(out, conn, "Too many messages. Slow down.")
		return out
	var errors: Array = []
	var message: Dictionary = SerializerScript.parse_command(text, errors)
	if not errors.is_empty():
		_error(out, conn, "Bad message: %s." % str(errors[0]))
		return out
	var type: String = message["type"]
	if not type in CLIENT_TYPES:
		_error(out, conn, "Unknown message '%s'." % type.left(40))
		return out
	match type:
		"create_room": _create_room(out, conn, message)
		"join_room": _join_room(out, conn, message)
		"resume": _resume(out, conn, message)
		"start_game": _start_game(out, conn)
		"command": _command(out, conn, message)
		"sync": _sync(out, conn)
		"leave": _leave(out, conn)
	return out


# Time passes: every running game moves on (deadlines pass, absent players are skipped). now is real milliseconds.
func tick(now: int) -> Array:
	now_ms = maxi(now_ms, now)
	var out: Array = []
	for code in rooms.keys():
		var room: Dictionary = rooms[code]
		if room["state"] != null and not room["state"].game_over:
			var events: Array = GameScript.tick(room["state"], now_ms - room["clock_base"])
			if not events.is_empty():   # (the clock moving the game is not "activity": only people touching it keeps a room alive)
				_save(room)
				_broadcast(out, room, events)
	if now_ms - last_prune_ms >= PRUNE_EVERY_MS:
		last_prune_ms = now_ms
		_prune()
	return out


# --- saving ---------------------------------------------------------------------------------

# One room as text. Connections are not saved: nobody is connected after a restart. Tokens are (they are the way back in).
func _room_text(room: Dictionary) -> String:
	var people: Array = []
	for token in room["members"]:
		var m: Dictionary = members[token]
		people.append({"token": token, "name": m["name"], "gender": m["gender"], "seat": m["seat"]})
	return SerializerScript.to_json({
		"version": SAVE_VERSION, "code": room["code"], "host": room["host"], "members": people,
		"started": room["started"], "touched": room["touched"],
		"state": SerializerScript.state_to_json(room["state"]) if room["state"] != null else "",
	})


func _save(room: Dictionary) -> void:
	if store == null:
		return
	if not store.save(room["code"], _room_text(room)):
		push_error("room %s could not be saved" % room["code"])


func _drop_room(room: Dictionary) -> void:
	for token in room["members"]:
		members.erase(token)
	rooms.erase(room["code"])
	if store != null:
		store.remove(room["code"])


# Brings every saved room back after a restart. The game's clock carries on from where it was, as if the downtime had not
# happened: otherwise every deadline would have passed and everyone would be skipped at once. Returns how many came back.
func load_saved(now: int) -> int:
	now_ms = maxi(now_ms, now)
	if store == null:
		return 0
	var loaded: int = 0
	for text in store.load_all():
		var errors: Array = []
		var data = SerializerScript.from_json(text, errors)
		if not errors.is_empty() or typeof(data) != TYPE_DICTIONARY or int(data.get("version", 0)) != SAVE_VERSION:
			push_error("a saved room was skipped: unreadable or from another version")
			continue
		var room: Dictionary = {"code": str(data["code"]), "host": str(data["host"]), "members": [], "started": bool(data["started"]), "state": null, "touched": now_ms, "clock_base": 0}   # downtime is not idle time
		if room["started"]:
			var state = SerializerScript.state_from_json(str(data["state"]), errors)
			if not errors.is_empty() or state == null:
				push_error("room %s was skipped: its game could not be read (%s)" % [room["code"], str(errors)])
				continue
			room["state"] = state
			room["clock_base"] = now_ms - state.clock_ms
		for person in data["members"]:
			var token: String = str(person["token"])
			room["members"].append(token)
			members[token] = {"token": token, "name": str(person["name"]), "gender": str(person["gender"]), "code": room["code"], "seat": int(person["seat"]), "conn": -1}
		rooms[room["code"]] = room
		loaded += 1
	return loaded


# Rooms nobody wants any more go, so the server does not fill up over weeks.
func _prune() -> void:
	for code in rooms.keys():
		var room: Dictionary = rooms[code]
		var idle: int = now_ms - int(room["touched"])
		var connected: bool = false
		for token in room["members"]:
			connected = connected or members[token]["conn"] != -1
		if connected:
			continue
		var over: bool = room["state"] != null and room["state"].game_over
		if (not room["started"] and idle > LOBBY_IDLE_MS) or (over and idle > FINISHED_KEEP_MS) or (idle > ABANDONED_KEEP_MS):
			_drop_room(room)


# --- the lobby ------------------------------------------------------------------------------

func _create_room(out: Array, conn: int, message: Dictionary) -> void:
	if conns[conn]["token"] != "":
		return _error(out, conn, "You are already in a room.")
	if rooms.size() >= MAX_ROOMS:
		return _error(out, conn, "The server is full. Try again later.")
	var who: Dictionary = _who(message)
	if who.has("error"):
		return _error(out, conn, who["error"])
	var code: String = _new_code()
	var room: Dictionary = {"code": code, "host": "", "members": [], "started": false, "state": null, "touched": now_ms, "clock_base": 0}
	rooms[code] = room
	_seat(out, conn, room, who)
	room["host"] = conns[conn]["token"]
	_announce_room(out, room)
	_save(room)


func _join_room(out: Array, conn: int, message: Dictionary) -> void:
	if conns[conn]["token"] != "":
		return _error(out, conn, "You are already in a room.")
	var code: String = str(message.get("code", "")).to_upper().strip_edges()
	if not rooms.has(code):
		return _error(out, conn, "There is no room with that code.")
	var room: Dictionary = rooms[code]
	if room["started"]:
		return _error(out, conn, "That game has already started. Use your resume token if you were in it.")
	if room["members"].size() >= GameDataScript.get_int("boxPlayers"):
		return _error(out, conn, "That room is full.")
	var who: Dictionary = _who(message)
	if who.has("error"):
		return _error(out, conn, who["error"])
	for token in room["members"]:
		if members[token]["name"].to_lower() == who["name"].to_lower():
			return _error(out, conn, "Someone in this room already has that name.")
	_seat(out, conn, room, who)
	_announce_room(out, room)
	_save(room)


func _resume(out: Array, conn: int, message: Dictionary) -> void:
	if conns[conn]["token"] != "":
		return _error(out, conn, "You are already in a room.")
	var token: String = str(message.get("token", ""))
	if not members.has(token):
		return _error(out, conn, "That token is not known. Join a room instead.")
	var member: Dictionary = members[token]
	var old: int = member["conn"]
	if old != -1 and conns.has(old):
		conns[old]["token"] = ""   # the old connection is dropped: the newest one is the player
		_error(out, old, "You signed in somewhere else.")
	member["conn"] = conn
	conns[conn]["token"] = token
	var room: Dictionary = rooms[member["code"]]
	room["touched"] = now_ms
	_send(out, conn, {"type": "welcome", "token": token, "code": room["code"], "you": member["seat"]})
	_announce_room(out, room)
	_send_state(out, room, member, true)


func _start_game(out: Array, conn: int) -> void:
	var member: Dictionary = _member_of(conn)
	if member.is_empty():
		return _error(out, conn, "You are not in a room.")
	var room: Dictionary = rooms[member["code"]]
	if room["host"] != member["token"]:
		return _error(out, conn, "Only the host can start the game.")
	if room["started"]:
		return _error(out, conn, "The game has already started.")
	var count: int = room["members"].size()
	if count < GameDataScript.get_int("minPlayers"):
		return _error(out, conn, "A game needs at least %d players." % GameDataScript.get_int("minPlayers"))
	var ids: Array = []
	var genders: Dictionary = {}
	for i in count:
		var m: Dictionary = members[room["members"][i]]
		m["seat"] = i + 1
		ids.append(i + 1)
		if m["gender"] != "":
			genders[i + 1] = m["gender"]
	room["started"] = true
	room["state"] = GameScript.new_game(ids, rng.randi_range(1, 2147483646), genders)
	room["clock_base"] = now_ms   # the game's own clock starts at 0 now
	_save(room)
	_announce_room(out, room)
	for token in room["members"]:
		_send(out, members[token]["conn"], {"type": "welcome", "token": token, "code": room["code"], "you": members[token]["seat"]})
		_send_state(out, room, members[token], true)


func _leave(out: Array, conn: int) -> void:
	var member: Dictionary = _member_of(conn)
	if member.is_empty():
		return _error(out, conn, "You are not in a room.")
	var room: Dictionary = rooms[member["code"]]
	if room["started"]:
		return _error(out, conn, "The game has started. You can only drop the connection and resume later.")
	room["members"].erase(member["token"])
	members.erase(member["token"])
	conns[conn]["token"] = ""
	if room["members"].is_empty():
		_drop_room(room)
	else:
		if room["host"] == member["token"]:
			room["host"] = room["members"][0]
		for i in room["members"].size():
			members[room["members"][i]]["seat"] = i + 1   # seats close up: they are only final once the game starts
		_announce_room(out, room)
		_save(room)
	_send(out, conn, {"type": "left"})


# --- the game -------------------------------------------------------------------------------

func _command(out: Array, conn: int, message: Dictionary) -> void:
	var member: Dictionary = _member_of(conn)
	if member.is_empty():
		return _error(out, conn, "You are not in a room.")
	var room: Dictionary = rooms[member["code"]]
	if not room["started"]:
		return _error(out, conn, "The game has not started.")
	var command = message.get("command", null)
	if typeof(command) != TYPE_DICTIONARY or typeof(command.get("type")) != TYPE_STRING:
		return _error(out, conn, "A command must be an object with a text 'type'.")
	var state = room["state"]
	room["touched"] = now_ms
	var events: Array = GameScript.handle(state, member["seat"], command)
	if events.size() == 1 and events[0]["type"] == "rejected":
		_send(out, conn, {"type": "events", "events": ViewsScript.visible_events(events, member["seat"])})   # only the asker hears a refusal
		return
	_save(room)   # after EVERY accepted move, before anyone is told about it
	_broadcast(out, room, events)


func _sync(out: Array, conn: int) -> void:
	var member: Dictionary = _member_of(conn)
	if member.is_empty():
		return _error(out, conn, "You are not in a room.")
	var room: Dictionary = rooms[member["code"]]
	_announce_room(out, room)
	if room["started"]:
		_send_state(out, room, member, true)


# Tell each player what they may hear and show them their own view.
func _broadcast(out: Array, room: Dictionary, events: Array) -> void:
	if events.is_empty():
		return
	var ids: Array = room["state"].player_ids
	var per_player: Dictionary = ViewsScript.deliver(events, ids)
	for token in room["members"]:
		var member: Dictionary = members[token]
		if member["conn"] == -1:
			continue
		var mine: Array = per_player.get(member["seat"], [])
		if not mine.is_empty():
			_send(out, member["conn"], {"type": "events", "events": mine})
		_send_state(out, room, member, false)


# The player's view. The event log is the long part, so it is sent only when asked for (full).
func _send_state(out: Array, room: Dictionary, member: Dictionary, full: bool) -> void:
	if member["conn"] == -1:
		return
	var view: Dictionary = ViewsScript.state_view(room["state"], member["seat"])
	if not full:
		view.erase("event_log")
	_send(out, member["conn"], {"type": "state", "view": view, "full": full})


# --- small helpers --------------------------------------------------------------------------

func _seat(out: Array, conn: int, room: Dictionary, who: Dictionary) -> void:
	var token: String = _new_token()
	var seat: int = room["members"].size() + 1   # fixed for good when the game starts
	members[token] = {"token": token, "name": who["name"], "gender": who["gender"], "code": room["code"], "seat": seat, "conn": conn}
	room["members"].append(token)
	conns[conn]["token"] = token
	_send(out, conn, {"type": "welcome", "token": token, "code": room["code"], "you": seat})


func _announce_room(out: Array, room: Dictionary) -> void:
	var list: Array = []
	for i in room["members"].size():
		var m: Dictionary = members[room["members"][i]]
		list.append({"seat": i + 1, "name": m["name"], "connected": m["conn"] != -1})
	var host_seat: int = room["members"].find(room["host"]) + 1
	for token in room["members"]:
		var m: Dictionary = members[token]
		if m["conn"] != -1:
			_send(out, m["conn"], {"type": "room", "code": room["code"], "host": host_seat, "started": room["started"], "members": list})


# Name 1 to 24 characters with no control characters, and an optional gender the game knows.
func _who(message: Dictionary) -> Dictionary:
	var name = message.get("name", "")
	if typeof(name) != TYPE_STRING:
		return {"error": "Give your name as text."}
	name = name.strip_edges()
	if name.is_empty() or name.length() > NAME_MAX:
		return {"error": "Your name must be 1 to %d characters." % NAME_MAX}
	for i in name.length():
		if name.unicode_at(i) < 32 or name.unicode_at(i) == 127:
			return {"error": "Your name can't contain control characters."}
	var gender = message.get("gender", "")
	if typeof(gender) != TYPE_STRING or (gender != "" and not gender in GendersScript.names()):
		return {"error": "Gender must be one of: %s." % ", ".join(GendersScript.names())}
	return {"name": name, "gender": gender}


func _member_of(conn: int) -> Dictionary:
	var token: String = conns.get(conn, {}).get("token", "")
	return members.get(token, {})


# A token bucket per connection: BURST messages at once, REFILL_PER_SECOND more each second.
func _allow(conn: int) -> bool:
	var bucket: Dictionary = conns[conn]
	var elapsed: float = float(now_ms - bucket["at"]) / 1000.0
	bucket["tokens"] = minf(float(BURST), bucket["tokens"] + elapsed * REFILL_PER_SECOND)
	bucket["at"] = now_ms
	if bucket["tokens"] < 1.0:
		return false
	bucket["tokens"] -= 1.0
	return true


func _new_code() -> String:
	while true:
		var code: String = ""
		for i in CODE_LENGTH:
			code += CODE_LETTERS[rng.randi_range(0, CODE_LETTERS.length() - 1)]
		if not rooms.has(code):
			return code
	return ""


# 128 random bits: whoever holds it is that player, so it is never shown to anyone else.
func _new_token() -> String:
	if secure_tokens:
		return Crypto.new().generate_random_bytes(16).hex_encode()
	var token: String = ""
	for i in 4:
		token += "%08x" % rng.randi()
	return token


func _error(out: Array, conn: int, reason: String) -> void:
	_send(out, conn, {"type": "error", "reason": reason})


func _send(out: Array, conn: int, message: Dictionary) -> void:
	if conn >= 0 and conns.has(conn):
		out.append({"to": conn, "text": SerializerScript.to_json(message)})
