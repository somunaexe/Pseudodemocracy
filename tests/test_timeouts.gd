extends SceneTree

const GameScript = preload("res://scripts/game.gd")
const GameStateScript = preload("res://scripts/game_state.gd")
const PlayScript = preload("res://tests/play.gd")
const ViceScript = preload("res://scripts/vice.gd")

const PRESIDENT = GameStateScript.LeaderType.PRESIDENT
const LEADER := 2
const TAX := 2

var failures: int = 0


func _init() -> void:
	exam_writing()
	exam_answering()
	voting()
	windows()
	amendment_votes()
	no_grammar_referee()
	absent_after_a_performance()
	print("%d failure(s)" % failures)
	quit(1 if failures > 0 else 0)


func exam_writing() -> void:
	var s := at_exam()
	expect("the exam begins with the Leader writing it, on a clock", [s.election["phase"], s.election["deadline"] > s.clock_ms], [GameStateScript.ElectionPhase.EXAM_WRITING, true])
	var started: Dictionary = last_of(s, "election_started")
	expect("... the event says when it runs out", started["ends_at_ms"], s.election["deadline"])
	GameScript.tick(s, int(s.election["deadline"]) - 1)
	expect("a second before the time is up nothing happens", s.election["phase"], GameStateScript.ElectionPhase.EXAM_WRITING)
	var ev := GameScript.tick(s, int(s.election["deadline"]))
	expect("when it is up the exam is skipped and everyone votes", [types(ev)[0], ev[0]["reason"], s.election["phase"]], ["exam_skipped", "the Leader ran out of time", GameStateScript.ElectionPhase.VOTING])
	expect("... with a ballot clock of its own", last_of(s, "vote_started")["ends_at_ms"], s.election["deadline"])


func exam_answering() -> void:
	var s := at_exam()
	send(s, LEADER, exam())
	var written: Dictionary = last_of(s, "exam_written")
	expect("the takers have a clock", [written["ends_at_ms"], s.election["phase"]], [s.election["deadline"], GameStateScript.ElectionPhase.EXAM_ANSWERING])
	send(s, 3, {"type": "answer_exam", "answers": [0, 0, 0, 0, 0]})   # all right
	var ev := GameScript.tick(s, int(s.election["deadline"]))
	expect("when the time is up those who didn't answer have failed, and the exam is marked", [types(ev)[0], ev[0]["missing"], last_of(s, "exam_revealed")["passed"]], ["exam_timeout", [1, 4, 5], [LEADER, 3]])
	expect("... and the voting begins among those who passed", s.election["voters"], [LEADER, 3])

	s = at_exam()
	send(s, LEADER, exam())
	ev = GameScript.tick(s, int(s.election["deadline"]))
	expect("if nobody answered the exam decided nothing: skipped, everyone votes", [types(ev)[0], ev[0]["reason"], s.election["voters"].size()], ["exam_skipped", "nobody answered in time", 5])


func voting() -> void:
	var s := at_exam()
	GameScript.tick(s, int(s.election["deadline"]))   # skipped: straight to the ballot
	send(s, 1, {"type": "cast_vote", "candidate": 3})
	send(s, 3, {"type": "cast_vote", "candidate": 3})
	send(s, 4, {"type": "cast_vote", "candidate": 5})
	var ev := GameScript.tick(s, int(s.election["deadline"]))
	expect("when the time is up the voters who didn't vote abstain, and the votes cast are counted", [types(ev)[0], ev[0]["missing"], last_of(s, "leader_elected")["winner"]], ["vote_timeout", [LEADER, 5], 3])

	# Nobody votes at all: tie, runoffs, then lot. It always ends.
	s = at_exam()
	GameScript.tick(s, int(s.election["deadline"]))
	for i in 8:
		if s.election.is_empty():
			break
		GameScript.tick(s, int(s.election["deadline"]))
	expect("an election nobody votes in still ends (runoffs, then lot)", [s.election.is_empty(), s.leader_id != -1, count(s.event_log, "election_tied") >= 1], [true, true, true])


func windows() -> void:
	var s := new_turn_at_inauguration()
	expect("the Inauguration has a clock", s.term["window_deadline"] > s.clock_ms, true)
	var started: Dictionary = last_of(s, "term_started")
	expect("... told in the event", started["window_ends_at_ms"], s.term["window_deadline"])
	GameScript.tick(s, int(s.term["window_deadline"]) - 1)
	expect("a second early: still open", s.term["phase"], GameStateScript.TermPhase.INAUGURATION)
	var ev := GameScript.tick(s, int(s.term["window_deadline"]))
	expect("when it is up the window is passed for the Leader and the turns begin", [types(ev)[0], ev[0]["timed_out"], s.windows_used[GameStateScript.AmendWindow.INAUGURATION], s.term["phase"]], ["window_passed", true, true, GameStateScript.TermPhase.TURNS])

	# An amendment under way is not cut off by the window clock.
	s = new_turn_at_inauguration()
	send(s, LEADER, propose(s, GameStateScript.AmendWindow.INAUGURATION, {1: "30%"}))
	GameScript.tick(s, int(s.amend["deadline"]) - 1)
	expect("the window is used by the proposal; the vote has its own clock", [s.term["phase"], s.amend.is_empty(), s.windows_used[GameStateScript.AmendWindow.INAUGURATION]], [GameStateScript.TermPhase.INAUGURATION, false, true])

	# The Farewell too.
	s = new_turn_at_inauguration()
	GameScript.handle(s, LEADER, {"type": "pass_window"})
	for id in [2, 3, 4, 5, 1]:
		PlayScript.take_turn(s, id)
	expect("the Farewell has a clock", [s.term["phase"], s.term["window_deadline"] > s.clock_ms, last_of(s, "farewell_opened")["window_ends_at_ms"] == s.term["window_deadline"]], [GameStateScript.TermPhase.FAREWELL, true, true])
	GameScript.tick(s, int(s.term["window_deadline"]))
	expect("... and when it is up the term ends and the next election begins", [s.term.is_empty(), s.election.is_empty()], [true, false])

	# A proposal waiting for the Vice is not passed over.
	s = new_turn_at_inauguration()
	ViceScript.appoint(s, 4)
	send(s, LEADER, propose(s, GameStateScript.AmendWindow.INAUGURATION, {1: "30%"}))
	expect("a proposal is waiting for agreement", s.amend_offer.is_empty(), false)
	GameScript.tick(s, int(s.amend_offer["deadline"]) - 1)
	expect("the window waits while the proposal does, and the proposal has a clock of its own", [s.term["phase"], s.amend_offer.is_empty()], [GameStateScript.TermPhase.INAUGURATION, false])
	GameScript.tick(s, int(s.term["window_deadline"]))
	expect("silence refuses it, and then the window runs out too", [s.amend_offer.is_empty(), s.term["phase"]], [true, GameStateScript.TermPhase.TURNS])


func amendment_votes() -> void:
	var s := new_turn_at_inauguration()
	send(s, LEADER, propose(s, GameStateScript.AmendWindow.INAUGURATION, {1: "30%"}))
	expect("with no referee the vote opens at once, on a clock", [s.amend["phase"], s.amend["deadline"] > s.clock_ms], [GameStateScript.AmendPhase.VOTING, true])
	send(s, 1, {"type": "vote", "keep": true})
	send(s, 3, {"type": "vote", "keep": true})
	send(s, 4, {"type": "vote", "keep": false})
	var ev := GameScript.tick(s, int(s.amend["deadline"]) - 1)
	expect("a second early nothing happens", s.amend.is_empty(), false)
	ev = GameScript.tick(s, int(s.amend["deadline"]))
	expect("when the time is up the rest abstain and the votes cast decide: 2 for, 1 against", [types(ev)[0], ev[1]["for"], ev[1]["against"], ev[1]["stands"]], ["amendment_vote_timeout", 2, 1, true])

	# Nobody votes: a tie.
	s = new_turn_at_inauguration()
	send(s, LEADER, propose(s, GameStateScript.AmendWindow.INAUGURATION, {1: "30%"}))
	ev = GameScript.tick(s, int(s.amend["deadline"]))
	expect("nobody voting: 0 to 0 and a President's amendment needs more for than against", [ev[1]["for"], ev[1]["against"], ev[1]["stands"]], [0, 0, false])


func no_grammar_referee() -> void:
	var s := new_turn_at_inauguration()
	expect("new games have no grammar referee", s.grammar_referee, false)
	var ev := send(s, LEADER, propose(s, GameStateScript.AmendWindow.INAUGURATION, {1: "30%"}))
	expect("so a proposal is accepted and goes straight to the vote", [types(ev), ev[1]["ok"], ev[1]["referee"]], [["amendment_proposed", "grammar_ruled"], true, false])
	expect("... and a server ruling is not needed (or possible)", send(s, 0, {"type": "rule_grammar", "ok": false})[0]["type"], "rejected")
	s = new_turn_at_inauguration()
	s.grammar_referee = true
	ev = send(s, LEADER, propose(s, GameStateScript.AmendWindow.INAUGURATION, {1: "30%"}))
	expect("with the referee switched on it waits for the ruling, as before", [types(ev), s.amend["phase"]], [["amendment_proposed"], GameStateScript.AmendPhase.PROPOSED])


# --- helpers -----------------------------------------------------------------------------

# The term has been played to its end and the exam is being written by the Leader (player 2).
func absent_after_a_performance() -> void:
	var s := new_turn_at_inauguration()
	s.decks["performance"] = [20, 20, 20, 20, 20, 20]   # plain cards: nothing asks a question
	send(s, LEADER, {"type": "pass_window"})
	var first: int = s.term["waiting"][0]
	var at: int = PlayScript.next_deadline(s, first)
	while at != -1:
		GameScript.tick(s, at)   # the performance and its vote run out; the performer never presses end turn
		at = PlayScript.next_deadline(s, first)
	expect("the performance is over and it is still their turn", [s.term["act"]["phase"], s.term["waiting"][0]], [GameStateScript.ActPhase.DONE, first])
	GameScript.tick(s, s.clock_ms)
	var started_at: int = s.clock_ms
	expect("the clock starts when nothing else holds the turn up", s.term["act"]["end_by"], started_at + 15000)
	GameScript.tick(s, started_at + 14000)
	expect("14 seconds in, they still have their turn", s.term["waiting"][0], first)
	var ev := GameScript.tick(s, started_at + 15000)
	expect("at 15 seconds the server ends it for them", [types(ev).has("turn_ended"), last_of(s, "turn_ended")["auto"], last_of(s, "turn_ended")["player"]], [true, true, first])
	expect("... and the next player's turn has begun", s.term["waiting"][0] != first or s.term["waiting"].is_empty(), true)
	# A question waiting on them holds the count off.
	s = new_turn_at_inauguration()
	s.decks["performance"] = [20, 20, 20, 20, 20, 20]
	send(s, LEADER, {"type": "pass_window"})
	first = s.term["waiting"][0]
	at = PlayScript.next_deadline(s, first)
	while at != -1:
		GameScript.tick(s, at)
		at = PlayScript.next_deadline(s, first)
	s.choice = {"player": first, "kind": "option", "labels": ["a", "b"], "deadline": s.clock_ms + 1000000, "subject": first}
	GameScript.tick(s, s.clock_ms + 100000)
	expect("a pending choice stops the count", [s.term["waiting"][0], s.term["act"].has("end_by")], [first, false])


func at_exam() -> GameStateScript:
	var s := new_turn_at_inauguration()
	GameScript.handle(s, LEADER, {"type": "pass_window"})
	for id in [2, 3, 4, 5, 1]:
		PlayScript.take_turn(s, id)
	GameScript.handle(s, LEADER, {"type": "pass_window"})
	assert(s.election.get("phase", 0) == GameStateScript.ElectionPhase.EXAM_WRITING, "the Leader should be writing the exam")
	return s


func exam() -> Dictionary:
	var questions: Array = []
	for i in 5:
		questions.append({"text": "Q%d?" % i, "options": ["A", "B", "C"], "answer": 0})
	return {"type": "write_exam", "questions": questions}


func new_turn_at_inauguration() -> GameStateScript:
	for seed_value in range(1, 400):
		var s := GameScript.new_game([1, 2, 3, 4, 5], seed_value)
		for id in [1, 2, 3, 4, 5]:
			GameScript.handle(s, id, {"type": "cast_vote", "candidate": LEADER})
		if s.leader_type == PRESIDENT:
			return s
	assert(false, "no seed gave a President")
	return null


func propose(s: GameStateScript, window: int, changes: Dictionary) -> Dictionary:
	var words: Array = s.articles[TAX]
	var texts: Array = []
	for i in words.size():
		texts.append(changes.get(i, words[i]["text"]))
	return {"type": "propose", "window": window, "article_id": TAX, "new_texts": texts}


func last_of(s: GameStateScript, type: String) -> Dictionary:
	for i in range(s.event_log.size() - 1, -1, -1):
		if s.event_log[i]["type"] == type:
			return s.event_log[i]
	return {}


func count(events: Array, type: String) -> int:
	var n: int = 0
	for event in events:
		if event["type"] == type:
			n += 1
	return n


func send(s: GameStateScript, player_id: int, command: Dictionary) -> Array:
	return GameScript.handle(s, player_id, command)


func types(events: Array) -> Array:
	var result: Array = []
	for event in events:
		result.append(event["type"])
	return result


func expect(label: String, actual: Variant, wanted: Variant) -> void:
	var ok: bool = typeof(actual) == typeof(wanted) and actual == wanted
	if not ok:
		failures += 1
	print(("PASS " if ok else "FAIL ") + label + " -> " + str(actual).left(90))
