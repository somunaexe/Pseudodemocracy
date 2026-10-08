extends SceneTree

const CoreScript = preload("res://server/server_core.gd")
const ModelScript = preload("res://client/session_model.gd")
const ExamModelScript = preload("res://client/exam_model.gd")
const ExamScreenScript = preload("res://client/exam_screen.gd")
const TurnScript = preload("res://client/turn_model.gd")
const ElectionScript = preload("res://scripts/election.gd")
const SerializerScript = preload("res://scripts/serializer.gd")

var failures: int = 0
var core
var phones: Dictionary = {}
var code: String = ""


func _init() -> void:
	building_an_exam()
	typed_questions()
	exam_through_the_server()
	screens()
	print("%d failure(s)" % failures)
	quit(1 if failures > 0 else 0)


# Four phones; player 2 is Leader; their term has ended and the exam is being written.
func table() -> void:
	core = CoreScript.new(41)
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
	var state = core.rooms[code]["state"]
	state.term = {}
	ElectionScript.begin(state, "term_ended")
	for conn in [1, 2, 3, 4]:
		send(conn, ModelScript.make_sync())


func send(conn: int, text: String) -> void:
	for item in core.receive(conn, text, 0):
		var errors: Array = []
		if phones.has(item["to"]):
			phones[item["to"]].apply(SerializerScript.from_json(item["text"], errors))


func building_an_exam() -> void:
	var picks: Array = []
	for id in 5:
		picks = ExamModelScript.toggle(picks, id)
	expect("tapping 5 bank questions puts them in the exam, unmarked", [picks.size(), picks[0]], [5, {"id": 0, "answer": -1}])
	expect("tapping one again takes it out", ExamModelScript.toggle(picks, 2).size(), 4)
	expect("the exam can't go over 10", ExamModelScript.toggle(ExamModelScript.toggle(ExamModelScript.toggle(ExamModelScript.toggle(ExamModelScript.toggle(picks, 5), 6), 7), 8), 9).size(), 10)
	var full: Array = []
	for id in 10:
		full = ExamModelScript.toggle(full, id)
	expect("... an eleventh tap does nothing", ExamModelScript.toggle(full, 20).size(), 10)
	expect("it is not ready until every question is marked", ExamModelScript.writer_state(picks)["ready"], false)
	for i in 5:
		picks = ExamModelScript.mark_at(picks, i, i % 3)
	var ready: Dictionary = ExamModelScript.writer_state(picks)
	expect("once all 5 are marked it is ready, with the lock command", [ready["ready"], ready["command"]["type"], ready["command"]["picks"][1]], [true, "write_exam", {"id": 1, "answer": 1}])
	expect("fewer than 5 is never ready", ExamModelScript.writer_state(picks.slice(0, 4))["ready"], false)
	expect("marking a position changes only that question", ExamModelScript.mark_at(picks, 0, 2)[0]["answer"], 2)


func typed_questions() -> void:
	expect("a typed question needs text", ExamModelScript.typed_problem("  ", ["A", "B"]), "Type the question.")
	expect("... and two options", ExamModelScript.typed_problem("Q?", ["A", "", ""]), "Give at least 2 options.")
	expect("... that differ", ExamModelScript.typed_problem("Q?", ["A", "A"]), "Two options are the same.")
	expect("... and not be too long", ExamModelScript.typed_problem("x".repeat(201), ["A", "B"]), "A question can be at most 200 characters.")
	expect("two options are enough, three are allowed", [ExamModelScript.typed_problem("Q?", ["A", "B"]), ExamModelScript.typed_problem("Q?", ["A", "B", "C"])], ["", ""])
	var picks: Array = ExamModelScript.add_typed([], "  Does the Leader snore?  ", ["Yes", " Loudly ", ""])
	expect("a typed question is added trimmed, blank options dropped, unmarked", picks, [{"text": "Does the Leader snore?", "options": ["Yes", "Loudly"], "answer": -1}])
	expect("a bad typed question is not added", ExamModelScript.add_typed(picks, "", ["A", "B"]), picks)
	picks = ExamModelScript.toggle(picks, 3)
	expect("typed and bank questions mix in the order added", [ExamModelScript.is_typed(picks[0]), ExamModelScript.is_typed(picks[1]), ExamModelScript.shown(picks[1])["text"].length() > 0], [true, false, true])
	expect("a typed question can be removed", ExamModelScript.remove_at(picks, 0).size(), 1)
	expect("a bank tap never removes a typed question that happens to share nothing", ExamModelScript.toggle(picks, 3).size(), 1)


func exam_through_the_server() -> void:
	table()
	var view: Dictionary = phones[2].view
	expect("the Leader gets the writing sheet, the others do not", [ExamModelScript.mode(view, 2), ExamModelScript.mode(phones[1].view, 1)], ["write", ""])
	expect("the others see who is setting the exam, with a clock", [TurnScript.describe(phones[1].view, 1, phones[1].members)["title"], TurnScript.describe(phones[1].view, 1, phones[1].members)["seconds"]], ["Bola is setting the exam", 120])
	# A mixed exam: 3 prepared, 2 typed.
	var picks: Array = []
	for id in [0, 5, 9]:
		picks = ExamModelScript.toggle(picks, id)
	picks = ExamModelScript.add_typed(picks, "Does the Leader snore?", ["Yes", "Loudly", "Never"])
	picks = ExamModelScript.add_typed(picks, "Zobo or chapman?", ["Zobo", "Chapman"])
	for i in picks.size():
		picks = ExamModelScript.mark_at(picks, i, 1)
	send(2, ModelScript.make_command(ExamModelScript.writer_state(picks)["command"]))
	expect("the locked exam is accepted: the takers now have it", [phones[3].view["election"]["phase"], ExamModelScript.mode(phones[3].view, 3), ExamModelScript.mode(phones[2].view, 2)], [GameStateScriptPhase(), "answer", ""])
	expect("they see the questions, in the Leader's order, mixing prepared and typed", [ExamModelScript.questions(phones[3].view).size(), ExamModelScript.questions(phones[3].view)[3]["text"]], [5, "Does the Leader snore?"])
	expect("the answer key never reaches any phone", [phones[3].view["election"].has("key"), phones[2].view["election"].has("key"), str(phones[3].view).contains("\"key\"")], [false, false, false])
	send(2, ModelScript.make_command(ExamModelScript.writer_state(picks)["command"]))
	expect("the Leader can't send a second exam: it is locked", phones[2].take_error() != "" or phones[2].take_events().any(func(e): return e["type"] == "rejected"), true)
	var answers: Array = ExamModelScript.blank_answers(phones[3].view)
	expect("a taker can't hand in until every question is answered", ExamModelScript.taker_state(phones[3].view, answers)["ready"], false)
	var dock: Dictionary = TurnScript.describe(phones[2].view, 2, phones[2].members)
	expect("the Leader waits, told how many have handed in", [dock["mode"], dock["lines"]], ["watch", ["0 of 3 handed in"]])
	for conn in [1, 3, 4]:
		var mine: Array = ExamModelScript.blank_answers(phones[conn].view)
		for i in mine.size():
			mine[i] = 1 if conn != 4 else 0   # 1 and 3 know the Leader; 4 does not
		var state: Dictionary = ExamModelScript.taker_state(phones[conn].view, mine)
		expect("player %d has answered everything and may hand in" % conn, state["ready"], true)
		send(conn, ModelScript.make_command(state["command"]))
	expect("when all have handed in the exam is marked and the ballot opens", [phones[1].view["election"]["phase"], phones[1].view["election"].get("candidates", [])], [GameStateScriptVoting(), [1, 2, 3]])
	var ballot: Dictionary = TurnScript.describe(phones[1].view, 1, phones[1].members)
	expect("the ballot is buttons, one per candidate who passed, in the dock", [ballot["mode"], ballot["buttons"].map(func(b): return b["label"])], ["ballot", ["Ada", "Bola", "Chi"]])
	expect("a player who failed is told they can't vote", TurnScript.describe(phones[4].view, 4, phones[4].members)["title"], "You can't vote this time")
	send(1, ModelScript.make_command(ballot["buttons"][1]["command"]))
	expect("voting through the button is recorded and the buttons go", [TurnScript.describe(phones[1].view, 1, phones[1].members)["mode"], TurnScript.describe(phones[1].view, 1, phones[1].members)["buttons"]], ["voted", []])


func GameStateScriptPhase() -> int:
	return ElectionScript.GameStateScript.ElectionPhase.EXAM_ANSWERING


func GameStateScriptVoting() -> int:
	return ElectionScript.GameStateScript.ElectionPhase.VOTING


func screens() -> void:
	table()
	var writer = ExamScreenScript.new()
	writer.model = phones[2]
	get_root().add_child(writer)
	writer.refresh()
	expect("the Leader's sheet shows, with one row for each of the 46 prepared questions", [writer.visible, writer.body.get_child_count() > 46], [true, true])
	expect("the lock button is off until the exam is complete", writer.footer.get_child(0).disabled, true)
	for id in 5:
		writer.picks = ExamModelScript.toggle(writer.picks, id)
		writer.picks = ExamModelScript.mark_at(writer.picks, writer.picks.size() - 1, 0)
	writer.refresh()
	expect("with 5 marked questions it can be pressed", writer.footer.get_child(0).disabled, false)
	var sent: Array = []
	writer.command_requested.connect(func(command): sent.append(command))
	writer.footer.get_child(0).pressed.emit()
	expect("pressing it asks 'are you sure?' and sends nothing yet", [sent, writer.confirming], [[], true])
	expect("the question is shown, with Back and Lock it", [writer.footer.get_child_count(), writer.footer.get_child(1).text], [2, "Lock it"])
	writer.footer.get_child(1).pressed.emit()
	expect("'Lock it' sends the exam, once", [sent.size(), sent[0]["type"], sent[0]["picks"].size()], [1, "write_exam", 5])
	writer.footer.get_child(0).pressed.emit()
	expect("'Back' returns to editing", writer.confirming, false)
	writer.typed_text.text = "Does the Leader snore?"
	writer.typed_draft["text"] = "Does the Leader snore?"
	writer.typed_options[0].text = "Yes"
	writer.typed_options[1].text = "No"
	writer._on_add_typed()
	expect("a typed question added on the sheet joins the exam", [writer.picks.size(), writer.picks[5]["text"]], [6, "Does the Leader snore?"])
	writer.typed_text.text = ""
	writer._on_add_typed()
	expect("a bad one says why", writer.typed_message.text, "Type the question.")
	# A taker's sheet.
	var asked: Array = []
	var m: Array = []
	for id in 5:
		m = ExamModelScript.toggle(m, id)
		m = ExamModelScript.mark_at(m, m.size() - 1, 1)
	send(2, ModelScript.make_command(ExamModelScript.writer_state(m)["command"]))
	var taker = ExamScreenScript.new()
	taker.model = phones[3]
	get_root().add_child(taker)
	taker.refresh()
	taker.command_requested.connect(func(command): asked.append(command))
	expect("a taker's sheet shows with the hand-in button off", [taker.visible, taker.footer.get_child(0).disabled, taker.title_label.text], [true, true, "The exam"])
	taker.answers = [1, 1, 1, 1, 1]
	taker.drawn_for = ""
	taker.refresh()
	taker.footer.get_child(0).pressed.emit()
	expect("with every question answered it hands in the answers", asked, [{"type": "answer_exam", "answers": [1, 1, 1, 1, 1]}])
	expect("a Leader whose exam is locked has no sheet, nor has an empty view", [ExamModelScript.mode({}, 1), ExamModelScript.mode(phones[2].view, 2)], ["", ""])
	writer.queue_free()
	taker.queue_free()


func expect(label: String, actual: Variant, wanted: Variant) -> void:
	var ok: bool = typeof(actual) == typeof(wanted) and actual == wanted
	if not ok:
		failures += 1
	print(("PASS " if ok else "FAIL ") + label + " -> " + str(actual).left(90))
