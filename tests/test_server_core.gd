extends SceneTree

const CoreScript = preload("res://server/server_core.gd")
const SerializerScript = preload("res://scripts/serializer.gd")

var failures: int = 0
var core
var inbox: Dictionary = {}   # connection -> every message it was sent, decoded


func _init() -> void:
	lobby()
	starting()
	playing()
	reconnecting()
	abuse()
	print("%d failure(s)" % failures)
	quit(1 if failures > 0 else 0)


func fresh() -> void:
	core = CoreScript.new(42)
	inbox = {}


func connect_n(ids: Array) -> void:
	for id in ids:
		core.connect_peer(id, 0)


# Sends a message from a connection and files what comes out by recipient.
func say(conn: int, message: Variant, now: int = 0) -> Array:
	var text: String = message if message is String else SerializerScript.to_json(message)
	return file(core.receive(conn, text, now))


func file(out: Array) -> Array:
	var decoded: Array = []
	for item in out:
		var errors: Array = []
		var msg = SerializerScript.from_json(item["text"], errors)
		if not inbox.has(item["to"]):
			inbox[item["to"]] = []
		inbox[item["to"]].append(msg)
		decoded.append({"to": item["to"], "msg": msg})
	return decoded


func last(conn: int, type: String) -> Dictionary:
	var list: Array = inbox.get(conn, [])
	for i in range(list.size() - 1, -1, -1):
		if list[i]["type"] == type:
			return list[i]
	return {}


func lobby() -> void:
	fresh()
	connect_n([1, 2, 3])
	say(1, {"type": "create_room", "name": "Ada", "gender": "female"})
	var code: String = last(1, "welcome")["code"]
	expect("a room code is 4 letters", [code.length(), code == code.to_upper()], [4, true])
	expect("the creator is seat 1 and the host", [last(1, "welcome")["you"], last(1, "room")["host"]], [1, 1])
	say(2, {"type": "join_room", "code": code.to_lower(), "name": "Bola"})
	expect("a code works in lower case, and the next seat is 2", last(2, "welcome")["you"], 2)
	expect("everyone in the room is told who is in it", [last(1, "room")["members"].size(), last(2, "room")["members"][1]["name"]], [2, "Bola"])
	say(3, {"type": "join_room", "code": code, "name": "bola"})
	expect("a name already taken (any case) is refused", last(3, "error")["reason"], "Someone in this room already has that name.")
	say(3, {"type": "join_room", "code": "ZZZZ", "name": "Chi"})
	expect("an unknown room is refused", last(3, "error")["reason"], "There is no room with that code.")
	say(3, {"type": "join_room", "code": code, "name": "Chi", "gender": "robot"})
	expect("an unknown gender is refused", last(3, "error")["reason"].begins_with("Gender must be one of"), true)
	say(3, {"type": "join_room", "code": code, "name": "  "})
	expect("a blank name is refused", last(3, "error")["reason"], "Your name must be 1 to 24 characters.")
	say(3, {"type": "join_room", "code": code, "name": "x".repeat(25)})
	expect("a long name is refused", last(3, "error")["reason"], "Your name must be 1 to 24 characters.")
	say(3, {"type": "join_room", "code": code, "name": 7})
	expect("a name that isn't text is refused", last(3, "error")["reason"], "Give your name as text.")
	say(1, {"type": "join_room", "code": code, "name": "Again"})
	expect("someone already in a room can't make or join another", last(1, "error")["reason"], "You are already in a room.")
	say(2, {"type": "leave"})
	expect("a player may leave before the start", [core.rooms[code]["members"].size(), last(2, "left").is_empty()], [1, false])
	say(1, {"type": "leave"})
	expect("an empty room is closed", core.rooms.has(code), false)


func starting() -> void:
	fresh()
	connect_n([1, 2, 3, 4])
	say(1, {"type": "create_room", "name": "Ada"})
	var code: String = last(1, "welcome")["code"]
	say(2, {"type": "join_room", "code": code, "name": "Bola", "gender": "male"})
	say(2, {"type": "start_game"})
	expect("only the host starts", last(2, "error")["reason"], "Only the host can start the game.")
	say(1, {"type": "start_game"})
	expect("two players are too few", last(1, "error")["reason"], "A game needs at least 3 players.")
	say(3, {"type": "join_room", "code": code, "name": "Chi"})
	say(1, {"type": "start_game"})
	var view: Dictionary = last(1, "state")["view"]
	expect("the host starts a three-player game: everyone gets their view in full", [view["player_ids"], last(1, "state")["full"], last(3, "state")["full"]], [[1, 2, 3], true, true])
	expect("the lobby says it has started", last(2, "room")["started"], true)
	expect("the view carries an election and no secrets", [view.has("election"), view.has("rng_state"), view.has("wills")], [true, false, false])
	say(4, {"type": "join_room", "code": code, "name": "Dayo"})
	expect("a started game takes no new players", last(4, "error")["reason"].begins_with("That game has already started"), true)
	say(1, {"type": "start_game"})
	expect("it can't be started twice", last(1, "error")["reason"], "The game has already started.")
	say(1, {"type": "leave"})
	expect("nor left once it has started", last(1, "error")["reason"].begins_with("The game has started"), true)


func playing() -> void:
	fresh()
	connect_n([1, 2, 3])
	say(1, {"type": "create_room", "name": "Ada"})
	var code: String = last(1, "welcome")["code"]
	say(2, {"type": "join_room", "code": code, "name": "Bola"})
	say(3, {"type": "join_room", "code": code, "name": "Chi"})
	say(1, {"type": "command", "command": {"type": "cast_vote", "candidate": 2}})
	expect("a command before the start is refused", last(1, "error")["reason"], "The game has not started.")
	say(1, {"type": "start_game"})
	for conn in [1, 2, 3]:
		inbox[conn] = []
	say(1, {"type": "command", "command": {"type": "cast_vote", "candidate": 2}})
	var heard: Array = last(2, "events").get("events", [])
	expect("everyone hears that a ballot was cast", heard.size() > 0 and heard[0]["type"] == "ballot_cast", true)
	expect("... and gets their state, without the long log", [last(3, "state")["full"], last(3, "state")["view"].has("event_log")], [false, false])
	say(1, {"type": "command", "command": {"type": "cast_vote", "candidate": 2}})
	var refusal: Array = last(1, "events")["events"]
	expect("a refusal goes only to the asker", [refusal[0]["type"], last(2, "events")["events"].size()], ["rejected", heard.size()])
	say(1, {"type": "command", "command": {"type": "finish_game"}})
	expect("a player can't end the game: that is the server's", last(1, "events")["events"][0]["reason"], "Only the server can end the game.")
	say(1, {"type": "command", "command": {"type": "rule_grammar", "ok": true}})
	expect("nor rule on grammar", last(1, "events")["events"][0]["type"], "rejected")
	say(1, {"type": "command", "command": 5})
	expect("a command that is not an object is an error", last(1, "error")["reason"], "A command must be an object with a text 'type'.")
	say(1, {"type": "command", "command": {"type": "cast_vote", "candidate": 2, "player": 3}})
	expect("a claimed identity is ignored: the seat decides who acts", core.rooms[code]["state"].election["votes"].keys(), [1])
	say(2, {"type": "sync"})
	expect("sync sends the whole picture, log included", [last(2, "state")["full"], last(2, "state")["view"].has("event_log")], [true, true])
	# Time passes: the clock reaches the game.
	var before: int = core.rooms[code]["state"].clock_ms
	file(core.tick(5000))
	expect("the server's clock moves the game's clock", core.rooms[code]["state"].clock_ms > before, true)


func reconnecting() -> void:
	fresh()
	connect_n([1, 2, 3, 9])
	say(1, {"type": "create_room", "name": "Ada"})
	var code: String = last(1, "welcome")["code"]
	var token: String = last(1, "welcome")["token"]
	say(2, {"type": "join_room", "code": code, "name": "Bola"})
	say(3, {"type": "join_room", "code": code, "name": "Chi"})
	say(1, {"type": "start_game"})
	file(core.disconnect_peer(1, 10))
	expect("the others are told who is away", last(2, "room")["members"][0]["connected"], false)
	file(core.tick(20))
	say(2, {"type": "command", "command": {"type": "cast_vote", "candidate": 2}})
	connect_n([5])
	say(5, {"type": "resume", "token": "nope"})
	expect("an unknown token is refused", last(5, "error")["reason"], "That token is not known. Join a room instead.")
	say(5, {"type": "resume", "token": token})
	expect("the right token gets the seat back, with the full picture", [last(5, "welcome")["you"], last(5, "state")["full"], last(5, "state")["view"]["player_ids"]], [1, true, [1, 2, 3]])
	expect("the others see them return", last(2, "room")["members"][0]["connected"], true)
	connect_n([6])
	say(6, {"type": "resume", "token": token})
	expect("a newer connection takes over; the old one is told", [last(5, "error")["reason"], last(6, "welcome")["you"]], ["You signed in somewhere else.", 1])
	say(5, {"type": "command", "command": {"type": "cast_vote", "candidate": 2}})
	expect("the old connection can no longer act", last(5, "error")["reason"], "You are not in a room.")


func abuse() -> void:
	fresh()
	connect_n([1])
	expect("not JSON", say(1, "{nope")[0]["msg"]["reason"].begins_with("Bad message"), true)
	expect("not an object", say(1, "[1,2]")[0]["msg"]["reason"].begins_with("Bad message"), true)
	expect("an unknown type", say(1, {"type": "format_disk"})[0]["msg"]["reason"], "Unknown message 'format_disk'.")
	expect("a message too large", say(1, "{\"type\":\"command\",\"pad\":\"" + "a".repeat(70000) + "\"}")[0]["msg"]["reason"].begins_with("Bad message"), true)
	expect("a stranger's message is dropped", core.receive(77, "{\"type\":\"sync\"}", 0), [])
	fresh()
	connect_n([1])
	var refused: bool = false
	for i in 40:
		var out: Array = say(1, {"type": "sync"}, 0)
		if out[0]["msg"].get("reason", "") == "Too many messages. Slow down.":
			refused = true
	expect("a flood is cut off", refused, true)
	expect("... and forgiven after a while", say(1, {"type": "sync"}, 10000)[0]["msg"]["reason"], "You are not in a room.")
	fresh()
	for i in 200:
		connect_n([i])
		say(i, {"type": "create_room", "name": "P"})
	connect_n([999])
	say(999, {"type": "create_room", "name": "P"})
	expect("the number of rooms is capped", last(999, "error")["reason"], "The server is full. Try again later.")
	fresh()
	expect("tokens differ from room to room", core.call("_new_token") != core.call("_new_token"), true)


func expect(label: String, actual: Variant, wanted: Variant) -> void:
	var ok: bool = typeof(actual) == typeof(wanted) and actual == wanted
	if not ok:
		failures += 1
	print(("PASS " if ok else "FAIL ") + label + " -> " + str(actual).left(90))
