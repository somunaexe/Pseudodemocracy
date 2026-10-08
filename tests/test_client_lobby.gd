extends SceneTree

const CoreScript = preload("res://server/server_core.gd")
const ModelScript = preload("res://client/session_model.gd")
const LobbyScript = preload("res://client/lobby_screen.gd")
const SerializerScript = preload("res://scripts/serializer.gd")

var failures: int = 0
var core
var phones: Dictionary = {}   # connection id -> SessionModel


func _init() -> void:
	model_against_server()
	losing_and_regaining_a_seat()
	validation()
	screen()
	print("%d failure(s)" % failures)
	quit(1 if failures > 0 else 0)


func start_server() -> void:
	core = CoreScript.new(21)
	phones = {}


func phone(conn: int):
	var model = ModelScript.new()
	model.connected = true
	phones[conn] = model
	core.connect_peer(conn, 0)
	return model


# A phone sends text; the server answers; every answer is applied to the phone it is for.
func send(conn: int, text: String) -> void:
	for item in core.receive(conn, text, 0):
		_deliver(item)


func _deliver(item: Dictionary) -> void:
	var errors: Array = []
	if phones.has(item["to"]):
		phones[item["to"]].apply(SerializerScript.from_json(item["text"], errors))


func model_against_server() -> void:
	start_server()
	var ada = phone(1)
	var bola = phone(2)
	var chi = phone(3)
	expect("a phone starts at the entry stage", ada.stage(), ModelScript.Stage.ENTRY)
	send(1, ModelScript.make_create_room("Ada", "female"))
	expect("after creating a room the phone is in the lobby as seat 1 and the host", [ada.stage(), ada.seat, ada.is_host(), ada.code.length()], [ModelScript.Stage.LOBBY, 1, true, 4])
	send(2, ModelScript.make_join_room(" " + ada.code.to_lower() + " ", "Bola", ""))
	expect("a code typed in lower case with spaces still works", [bola.stage(), bola.seat, bola.is_host()], [ModelScript.Stage.LOBBY, 2, false])
	expect("everyone's list of members is the same and up to date", [ada.members.size(), bola.members.map(func(m): return m["name"])], [2, ["Ada", "Bola"]])
	expect("the host can't start with two", ada.can_start(), false)
	send(3, ModelScript.make_join_room(ada.code, "Chi", "male"))
	expect("with three the host can start, the guests can't", [ada.can_start(), bola.can_start(), chi.can_start()], [true, false, false])
	send(2, ModelScript.make_join_room(ada.code, "Again", ""))
	expect("a refusal is kept for the screen to show, once", [bola.take_error(), bola.take_error()], ["You are already in a room.", ""])
	send(1, ModelScript.make_start_game())
	expect("when the host starts, all three are PLAYING with their own view", [ada.stage(), bola.stage(), chi.stage(), chi.view["player_ids"]], [ModelScript.Stage.PLAYING, ModelScript.Stage.PLAYING, ModelScript.Stage.PLAYING, [1, 2, 3]])
	expect("the full picture came with the start, including the event log", ada.view.has("event_log"), true)
	send(1, ModelScript.make_command({"type": "cast_vote", "candidate": 2}))
	expect("a move updates every phone's view and event feed", [bola.view["election"]["voted"], bola.take_events().size() > 0], [[1], true])
	expect("the log stays in step as events arrive", chi.view["event_log"].size() > 0, true)
	send(1, ModelScript.make_command({"type": "cast_vote", "candidate": 2}))
	expect("a refused move is an error for the one who asked, not in the log", [ada.take_error() != "", chi.take_error()], [true, ""])


func losing_and_regaining_a_seat() -> void:
	start_server()
	var ada = phone(1)
	phone(2)
	phone(3)
	send(1, ModelScript.make_create_room("Ada", ""))
	send(2, ModelScript.make_join_room(ada.code, "Bola", ""))
	send(3, ModelScript.make_join_room(ada.code, "Chi", ""))
	send(1, ModelScript.make_start_game())
	# Ada's phone is killed and restarted: it only remembers what was saved.
	var saved: Dictionary = ada.to_save()
	core.disconnect_peer(1, 5)
	var again = ModelScript.new()
	again.from_save(saved)
	expect("a phone with a saved seat knows it is resuming until the server says so", [again.resuming(), again.has_saved_seat()], [true, true])
	again.connected = true
	phones[9] = again
	core.connect_peer(9, 10)
	send(9, again.make_resume())
	expect("the saved token gets the same seat back and the full picture", [again.resuming(), again.seat, again.stage(), again.view.has("event_log")], [false, 1, ModelScript.Stage.PLAYING, true])
	# A token the server has never heard of (it lost the room): back to the start, no loop.
	var stale = ModelScript.new()
	stale.from_save({"token": "deadbeef", "code": "ZZZZ"})
	stale.connected = true
	phones[10] = stale
	core.connect_peer(10, 10)
	send(10, stale.make_resume())
	expect("an unknown token sends the phone back to the entry screen", [stale.stage(), stale.has_saved_seat()], [ModelScript.Stage.ENTRY, false])
	# Leaving a lobby clears the seat on the phone.
	start_server()
	var solo = phone(1)
	send(1, ModelScript.make_create_room("Ada", ""))
	send(1, ModelScript.make_leave())
	expect("leaving a room empties the phone's seat", [solo.stage(), solo.has_saved_seat(), solo.members], [ModelScript.Stage.ENTRY, false, []])


func validation() -> void:
	expect("an empty name is caught on the phone", ModelScript.name_problem("   "), "Type your name.")
	expect("a long name is caught", ModelScript.name_problem("x".repeat(25)).begins_with("Your name can be at most"), true)
	expect("a good name passes", ModelScript.name_problem(" Ada "), "")
	expect("a code must be 4 letters", [ModelScript.code_problem("AB"), ModelScript.code_problem(" abcd ")], ["A room code has 4 letters.", ""])
	expect("gender choices start with 'not said'", ModelScript.gender_choices()[0], "")


func screen() -> void:
	var lobby = LobbyScript.new()
	lobby.model = ModelScript.new()
	get_root().add_child(lobby)   # runs _ready: the screen builds itself
	lobby.refresh()
	expect("not connected: the entry form shows, buttons off", [lobby.entry_box.visible, lobby.lobby_box.visible, lobby.create_button.disabled, lobby.status_label.text], [true, false, true, "Not connected"])
	lobby.model.connected = true
	lobby.refresh()
	expect("connected: the buttons are on", [lobby.create_button.disabled, lobby.status_label.text], [false, "Connected"])
	expect("every button is at least 96 px tall: easy to hit with a thumb", [lobby.create_button.custom_minimum_size.y >= 96, lobby.join_button.custom_minimum_size.y >= 96, lobby.start_button.custom_minimum_size.y >= 96], [true, true, true])
	var asked: Array = []
	lobby.create_requested.connect(func(name, gender): asked.append([name, gender]))
	lobby.name_field.text = ""
	lobby.create_button.pressed.emit()
	expect("pressing create without a name asks nothing and says why", [asked, lobby.message_label.text], [[], "Type your name."])
	lobby.name_field.text = "Ada"
	lobby.gender_menu.select(2)
	lobby.create_button.pressed.emit()
	expect("with a name it asks for a room, with the chosen gender", asked, [["Ada", ModelScript.gender_choices()[2]]])
	lobby.join_button.pressed.emit()
	expect("joining without a code says so", lobby.message_label.text, "A room code has 4 letters.")
	# The server puts us in a room as host with two others.
	lobby.model.apply({"type": "welcome", "token": "t", "code": "KQTZ", "you": 1})
	lobby.model.apply({"type": "room", "code": "KQTZ", "host": 1, "started": false, "members": [{"seat": 1, "name": "Ada", "connected": true}, {"seat": 2, "name": "Bola", "connected": false}]})
	lobby.refresh()
	expect("in a room the lobby shows: the code, the people, 'away' for the absent", [lobby.lobby_box.visible, lobby.entry_box.visible, lobby.room_code_label.text, lobby.members_box.get_child_count()], [true, false, "KQTZ", 2])
	expect("... the start button is there for the host but not yet usable with two", [lobby.start_button.visible, lobby.start_button.disabled], [true, true])
	lobby.model.apply({"type": "room", "code": "KQTZ", "host": 1, "started": false, "members": [{"seat": 1, "name": "Ada", "connected": true}, {"seat": 2, "name": "Bola", "connected": true}, {"seat": 3, "name": "Chi", "connected": true}]})
	lobby.refresh()
	expect("with three it can be pressed", lobby.start_button.disabled, false)
	lobby.model.host_seat = 2
	lobby.refresh()
	expect("a guest has no start button", lobby.start_button.visible, false)
	lobby.model.apply({"type": "error", "reason": "That room is full."})
	lobby.refresh()
	expect("a server refusal shows on screen", lobby.message_label.text, "That room is full.")
	lobby.model.apply({"type": "room", "code": "KQTZ", "host": 1, "started": true, "members": []})
	lobby.refresh()
	expect("when the game starts the lobby gives way", [lobby.lobby_box.visible, lobby.playing_label.visible], [false, true])
	var resuming = LobbyScript.new()
	resuming.model = ModelScript.new()
	resuming.model.from_save({"token": "x", "code": "ABCD"})
	get_root().add_child(resuming)
	resuming.refresh()
	expect("a phone waiting to get its seat back shows neither form", [resuming.entry_box.visible, resuming.lobby_box.visible, resuming.status_label.text], [false, false, "Connecting…"])
	lobby.queue_free()
	resuming.queue_free()


func expect(label: String, actual: Variant, wanted: Variant) -> void:
	var ok: bool = typeof(actual) == typeof(wanted) and actual == wanted
	if not ok:
		failures += 1
	print(("PASS " if ok else "FAIL ") + label + " -> " + str(actual).left(90))
