extends SceneTree

const CoreScript = preload("res://server/server_core.gd")
const ModelScript = preload("res://client/session_model.gd")
const TurnScript = preload("res://client/turn_model.gd")
const CardsScript = preload("res://scripts/cards.gd")
const SerializerScript = preload("res://scripts/serializer.gd")

var failures: int = 0
var core
var phones: Dictionary = {}   # connection (= seat) -> SessionModel
var code: String = ""


func _init() -> void:
	performing_and_voting()
	countdown()
	choices()
	debate()
	print("%d failure(s)" % failures)
	quit(1 if failures > 0 else 0)


# Four phones at a started game, the first election over (player 2 is Leader) and the first turn begun, with plain cards.
func table(deck: Array = [20, 20, 20, 20, 20, 20]) -> void:
	core = CoreScript.new(31)
	phones = {}
	for conn in [1, 2, 3, 4]:
		var model = ModelScript.new()
		model.connected = true
		phones[conn] = model
		core.connect_peer(conn, 0)
	send(1, ModelScript.make_create_room("Ada", ""))
	code = phones[1].code
	for conn in [2, 3, 4]:
		send(conn, ModelScript.make_join_room(code, ["", "Bola", "Chi", "Dayo"][conn - 1], ""))
	send(1, ModelScript.make_start_game())
	for conn in [1, 2, 3, 4]:
		send(conn, ModelScript.make_command({"type": "cast_vote", "candidate": 2}))
	core.rooms[code]["state"].decks["performance"] = deck.duplicate()
	send(2, ModelScript.make_command({"type": "pass_window"}))


func send(conn: int, text: String) -> void:
	for item in core.receive(conn, text, 0):
		var errors: Array = []
		if phones.has(item["to"]):
			phones[item["to"]].apply(SerializerScript.from_json(item["text"], errors))


func see(conn: int, input: Dictionary = {}, elapsed: int = 0) -> Dictionary:
	return TurnScript.describe(phones[conn].view, phones[conn].seat, phones[conn].members, elapsed, input)


func press(conn: int, mode_button: int = 0, input: Dictionary = {}) -> void:
	var shown: Dictionary = see(conn, input)
	send(conn, ModelScript.make_command(shown["buttons"][mode_button]["command"]))


func performer() -> int:
	return int(phones[1].view["term"]["waiting"][0])


func tick_to(ms: int) -> void:
	for item in core.tick(ms):
		var errors: Array = []
		if phones.has(item["to"]):
			phones[item["to"]].apply(SerializerScript.from_json(item["text"], errors))


func performing_and_voting() -> void:
	table()
	var who: int = performer()
	var others: Array = [1, 2, 3, 4].filter(func(c): return c != who)
	var mine: Dictionary = see(who)
	expect("the performer sees their card and a single button to finish", [mine["mode"], mine["card"] != "", mine["buttons"].size(), mine["buttons"][0]["label"]], ["perform", true, 1, "I'm done"])
	expect("everyone else just watches the same card", [see(others[0])["mode"], see(others[0])["card"] == mine["card"], see(others[0])["buttons"]], ["watch", true, []])
	press(who)   # "I'm done" goes through the real server
	expect("after 'I'm done' the table is voting: others get Good and Bad", [see(others[0])["mode"], see(others[0])["buttons"].map(func(b): return b["label"])], ["vote", ["Good", "Bad"]])
	expect("the performer is told the table is voting on them, with no buttons", [see(who)["mode"], see(who)["buttons"]], ["watch", []])
	press(others[0], 0)
	expect("a voter who has voted gets no more buttons and a note", [see(others[0])["mode"], see(others[0])["buttons"]], ["voted", []])
	expect("everyone sees how many have voted", see(who)["lines"], ["1 have voted"])
	press(others[1], 1)
	press(others[2], 0)
	expect("when all have voted the result shows, with the vote count", [see(others[0])["mode"], see(others[0])["title"].contains("Good")], ["result", true])
	expect("only the performer gets the End my turn button", [see(who)["mode"], see(who)["buttons"][0]["label"], see(others[0])["buttons"]], ["end_turn", "End my turn", []])
	press(who)
	expect("pressing it passes the turn", performer() != who, true)
	expect("a game with no cards in the view is quiet", TurnScript.describe({}, 1, [])["mode"], "none")


func countdown() -> void:
	table()
	var act: Dictionary = phones[1].view["term"]["act"]
	var left: int = see(1)["seconds"]
	expect("the performance clock starts at 60", left, 60)
	expect("it runs down with the phone's own time", see(1, {}, 10000)["seconds"], 50)
	expect("it stops at zero", see(1, {}, 999999)["seconds"], 0)
	expect("the model reports local time since the view came", [phones[1].elapsed_ms(phones[1].view_received_ms + 2500), phones[1].elapsed_ms(phones[1].view_received_ms - 5)], [2500, 0])
	var who: int = performer()
	press(who)
	tick_to(3000000)   # nobody votes: the game closes the vote on its clock
	expect("after the vote closes the clock for ending the turn is shown", see(who)["mode"] == "end_turn" or performer() != who, true)


func choices() -> void:
	table()
	var who: int = performer()
	var state = core.rooms[code]["state"]
	var labels: Array = CardsScript.effects("settlement", 22)["choose"]["options"].map(func(o): return o["label"])
	state.choice = {"player": who, "subject": who, "deck": "settlement", "card": 22, "kind": "option", "labels": labels, "deadline": state.clock_ms + 10000, "prompt": "Which?"}
	for conn in [1, 2, 3, 4]:
		send(conn, ModelScript.make_sync())
	var q: Dictionary = see(who)
	expect("a question to you shows its options as buttons, with its clock", [q["mode"], q["buttons"].map(func(b): return b["label"]), q["seconds"], q["card"]], ["choice", labels, 10, "Which?"])
	expect("... and each carries the choose command with the option's number", [q["buttons"][1]["command"]], [{"type": "choose", "choice": 1}])
	var watcher: int = 1 if who != 1 else 3
	expect("others see who is choosing, with no buttons", [see(watcher)["mode"], see(watcher)["buttons"], see(watcher)["title"].ends_with("is choosing…")], ["watch_choice", [], true])
	press(who, 1)
	expect("the answer goes through the server and the question is gone", [phones[who].view["choice"], phones[who].take_error()], [{}, ""])
	phones[who].view["choice"] = {}
	state.choice = {"player": who, "subject": who, "deck": "settlement", "card": 22, "kind": "players", "candidates": [1, 2, 3, 4].filter(func(c): return c != who), "max": 2, "deadline": state.clock_ms + 10000}
	send(who, ModelScript.make_sync())
	var picked: Array = []
	var many: Dictionary = see(who, {"selection": picked})
	expect("a 'pick up to 2' question has a button per candidate plus Confirm", [many["buttons"].size(), many["buttons"][-1]["label"], many["lines"]], [4, "Confirm", ["Pick up to 2"]])
	expect("ticking a name shows a tick and Confirm sends the picks", [see(who, {"selection": [3]})["buttons"][1]["label"].begins_with("✓") or see(who, {"selection": [3]})["buttons"][0]["label"].begins_with("✓"), see(who, {"selection": [3]})["buttons"][-1]["command"]], [true, {"type": "choose", "choice": [3]}])
	state.choice = {"player": who, "subject": who, "deck": "settlement", "card": 22, "kind": "number", "min": 1, "max": 100, "deadline": state.clock_ms + 10000}
	send(who, ModelScript.make_sync())
	var numbers: Array = see(who)["buttons"]
	expect("a number question offers at most 8 values inside its range", [numbers.size() <= 8, numbers[0]["command"]["choice"], numbers[-1]["command"]["choice"] <= 100], [true, 1, true])


func debate() -> void:
	var debate_card: int = -1
	for i in CardsScript.count("performance"):
		if CardsScript.effects("performance", i).has("debate"):
			debate_card = i
			break
	table([debate_card])
	var who: int = performer()
	var others: Array = [1, 2, 3, 4].filter(func(c): return c != who)
	var ask: Dictionary = see(who, {"topic": "the price of garri"})
	expect("a debate card first asks the performer to pick a rival, with the topic they typed", [ask["mode"], ask["buttons"].size(), ask["lines"]], ["challenge", 3, ["Topic: the price of garri"]])
	expect("the others wait", see(others[0])["mode"], "watch")
	var rival: int = ask["buttons"][0]["command"]["rival"]
	send(who, ModelScript.make_command(ask["buttons"][0]["command"]))
	var speaker: Dictionary = see(who)
	expect("then the performer speaks first, and can say they have said enough", [speaker["mode"], speaker["buttons"][0]["command"]], ["debate_speak", {"type": "debate_finish"}])
	expect("... while the rival waits their turn", see(rival)["mode"], "watch")
	press(who)
	expect("the rival then gets the floor", see(rival)["mode"], "debate_speak")
	press(rival)
	var viewers: Array = others.filter(func(c): return c != rival)
	var vote: Dictionary = see(viewers[0])
	expect("the rest of the table votes for who won: two buttons, the debaters", [vote["mode"], vote["buttons"].size(), vote["buttons"].map(func(b): return b["command"]["winner"]).has(who)], ["debate_vote", 2, true])
	expect("the debaters just watch the vote", [see(who)["mode"], see(rival)["mode"]], ["watch", "watch"])
	press(viewers[0], 0)
	expect("a vote through the server is recorded", see(viewers[0])["mode"], "voted")


func expect(label: String, actual: Variant, wanted: Variant) -> void:
	var ok: bool = typeof(actual) == typeof(wanted) and actual == wanted
	if not ok:
		failures += 1
	print(("PASS " if ok else "FAIL ") + label + " -> " + str(actual).left(90))
