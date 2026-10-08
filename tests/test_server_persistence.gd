extends SceneTree

const CoreScript = preload("res://server/server_core.gd")
const MemoryStoreScript = preload("res://server/memory_store.gd")
const DiskStoreScript = preload("res://server/disk_store.gd")
const SerializerScript = preload("res://scripts/serializer.gd")

var failures: int = 0
var inbox: Dictionary = {}


func _init() -> void:
	saving_after_every_move()
	surviving_a_restart()
	the_clock_does_not_run_while_down()
	cleaning_up()
	seats_close_up()
	on_disk()
	print("%d failure(s)" % failures)
	quit(1 if failures > 0 else 0)


func say(core, conn: int, message: Dictionary, now: int = 0) -> void:
	for item in core.receive(conn, SerializerScript.to_json(message), now):
		var errors: Array = []
		if not inbox.has(item["to"]):
			inbox[item["to"]] = []
		inbox[item["to"]].append(SerializerScript.from_json(item["text"], errors))


func last(conn: int, type: String) -> Dictionary:
	var list: Array = inbox.get(conn, [])
	for i in range(list.size() - 1, -1, -1):
		if list[i]["type"] == type:
			return list[i]
	return {}


# Three players at a started game; returns the core. Tokens are in inbox under connections 1, 2, 3.
func started(store, seed_value: int = 5):
	var core = CoreScript.new(seed_value)
	core.store = store
	inbox = {}
	for id in [1, 2, 3]:
		core.connect_peer(id, 0)
	say(core, 1, {"type": "create_room", "name": "Ada"})
	var code: String = last(1, "welcome")["code"]
	say(core, 2, {"type": "join_room", "code": code, "name": "Bola"})
	say(core, 3, {"type": "join_room", "code": code, "name": "Chi"})
	say(core, 1, {"type": "start_game"})
	return core


func saving_after_every_move() -> void:
	var store = MemoryStoreScript.new()
	var core = started(store)
	var code: String = last(1, "welcome")["code"]
	var after_start: int = store.saves
	expect("the lobby changes and the start were saved", after_start >= 4, true)
	say(core, 1, {"type": "command", "command": {"type": "cast_vote", "candidate": 2}})
	expect("an accepted move is saved", store.saves, after_start + 1)
	say(core, 1, {"type": "command", "command": {"type": "cast_vote", "candidate": 2}})
	expect("a refused move is not", store.saves, after_start + 1)
	say(core, 1, {"type": "sync"})
	expect("neither is a look at the table", store.saves, after_start + 1)
	var saved: Dictionary = SerializerScript.from_json(store.files[code], [])
	expect("the save names the room, host and players", [saved["code"], saved["members"].size(), saved["started"]], [code, 3, true])
	expect("... and keeps no connection, only tokens", [saved["members"][0].has("token"), saved["members"][0].has("conn")], [true, false])


func surviving_a_restart() -> void:
	var store = MemoryStoreScript.new()
	var core = started(store)
	var code: String = last(1, "welcome")["code"]
	var token: String = last(2, "welcome")["token"]
	say(core, 1, {"type": "command", "command": {"type": "cast_vote", "candidate": 2}})
	say(core, 3, {"type": "command", "command": {"type": "cast_vote", "candidate": 2}})
	var before: String = SerializerScript.state_to_json(core.rooms[code]["state"])
	# The server restarts: a new core, the same store.
	var again = CoreScript.new(99)
	again.store = store
	expect("the room comes back", again.load_saved(1000), 1)
	expect("the game is exactly as it was", SerializerScript.state_to_json(again.rooms[code]["state"]), before)
	inbox = {}
	again.connect_peer(7, 1000)
	say(again, 7, {"type": "resume", "token": token}, 1000)
	expect("a player resumes with their old token, in their old seat, with the full picture", [last(7, "welcome")["you"], last(7, "state")["full"], last(7, "room")["code"]], [2, true, code])
	expect("the others show as away until they return", last(7, "room")["members"][0]["connected"], false)
	say(again, 7, {"type": "command", "command": {"type": "cast_vote", "candidate": 3}}, 1000)
	expect("and play carries on", last(7, "events")["events"][0]["type"], "ballot_cast")
	# A saved game from a different version, or garbage, is skipped, not fatal.
	store.files["XXXX"] = "not json"
	store.files["YYYY"] = SerializerScript.to_json({"version": 99})
	var third = CoreScript.new(3)
	third.store = store
	expect("unreadable saves are skipped", third.load_saved(0), 1)


func the_clock_does_not_run_while_down() -> void:
	var store = MemoryStoreScript.new()
	var core = started(store)
	var code: String = last(1, "welcome")["code"]
	core.tick(4000)
	var clock: int = core.rooms[code]["state"].clock_ms
	core.disconnect_peer(1, 4000)
	say(core, 2, {"type": "command", "command": {"type": "cast_vote", "candidate": 2}}, 4000)   # a save after the last tick
	var again = CoreScript.new(8)
	again.store = store
	var week: int = 7 * 24 * 3600 * 1000
	again.load_saved(week)
	var events: Array = again.tick(week + 10)
	expect("a week's downtime costs no deadlines: nobody is skipped", [events.size(), again.rooms[code]["state"].clock_ms - clock <= 10], [0, true])
	again.tick(week + 600000)
	expect("but the game's own time does run once it is back", again.rooms[code]["state"].clock_ms >= clock + 600000 - 10, true)


func cleaning_up() -> void:
	var minute: int = 60 * 1000
	var hour: int = 60 * minute
	var store = MemoryStoreScript.new()
	var core = CoreScript.new(4)
	core.store = store
	core.connect_peer(1, 0)
	say(core, 1, {"type": "create_room", "name": "Ada"})
	var code: String = last(1, "welcome")["code"]
	core.disconnect_peer(1, 0)
	core.tick(15 * minute)
	expect("a lobby nobody is in survives a quarter of an hour", core.rooms.has(code), true)
	core.tick(45 * minute)
	expect("... but not 45 minutes more: it is dropped, and its file", [core.rooms.has(code), store.files.has(code), core.members.size()], [false, false, 0])
	var busy = started(store)
	var busy_code: String = last(1, "welcome")["code"]
	busy.tick(5 * hour)
	expect("a game with people connected is never dropped", busy.rooms.has(busy_code), true)
	for id in [1, 2, 3]:
		busy.disconnect_peer(id, 5 * hour)
	busy.tick(7 * hour + 59 * minute)
	expect("a running game with nobody connected is kept for under 3 hours", busy.rooms.has(busy_code), true)
	busy.tick(8 * hour + 1 * minute)
	expect("... and dropped after 3", busy.rooms.has(busy_code), false)
	var done = started(store)
	var done_code: String = last(1, "welcome")["code"]
	done.rooms[done_code]["state"].game_over = true
	for id in [1, 2, 3]:
		done.disconnect_peer(id, 0)
	done.tick(30 * minute)
	expect("a finished game is kept for half an hour", done.rooms.has(done_code), true)
	done.tick(90 * minute)
	expect("... and dropped by two hours", done.rooms.has(done_code), false)


func seats_close_up() -> void:
	var core = CoreScript.new(6)
	inbox = {}
	for id in [1, 2, 3, 4]:
		core.connect_peer(id, 0)
	say(core, 1, {"type": "create_room", "name": "Ada"})
	var code: String = last(1, "welcome")["code"]
	for id in [2, 3, 4]:
		say(core, id, {"type": "join_room", "code": code, "name": "P%d" % id})
	say(core, 2, {"type": "leave"})
	say(core, 1, {"type": "leave"})
	expect("when players leave the lobby the seats close up and the host passes on", [last(3, "room")["members"].map(func(m): return m["seat"]), last(3, "room")["host"]], [[1, 2], 1])
	say(core, 3, {"type": "start_game"})
	expect("... so the remaining two can't start, and with a third they could", last(3, "error")["reason"], "A game needs at least 3 players.")


func on_disk() -> void:
	var dir: String = "user://test_rooms_%d" % Time.get_ticks_usec()
	var store = DiskStoreScript.new(dir)
	var core = started(store)
	var code: String = last(1, "welcome")["code"]
	say(core, 1, {"type": "command", "command": {"type": "cast_vote", "candidate": 2}})
	expect("a room is a file named after its code", FileAccess.file_exists("%s/%s.json" % [dir, code]), true)
	expect("no half-written temporary file is left", FileAccess.file_exists("%s/%s.json.tmp" % [dir, code]), false)
	var again = CoreScript.new(11)
	again.store = DiskStoreScript.new(dir)
	expect("a new server reads it back", [again.load_saved(0), again.rooms[code]["state"].election["votes"].keys()], [1, [1]])
	expect("a name that could point elsewhere is never written", store.save("../evil", "x"), false)
	expect("... nor read", store.load_all().size(), 1)
	again.store.remove(code)
	expect("removing a room removes the file", FileAccess.file_exists("%s/%s.json" % [dir, code]), false)
	DirAccess.remove_absolute(dir)


func expect(label: String, actual: Variant, wanted: Variant) -> void:
	var ok: bool = typeof(actual) == typeof(wanted) and actual == wanted
	if not ok:
		failures += 1
	print(("PASS " if ok else "FAIL ") + label + " -> " + str(actual).left(90))
