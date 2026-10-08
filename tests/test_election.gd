extends SceneTree

const ElectionScript = preload("res://scripts/election.gd")
const ElimScript = preload("res://scripts/elimination.gd")
const RngScript = preload("res://scripts/rng.gd")
const ViewsScript = preload("res://scripts/views.gd")
const PopularityScript = preload("res://scripts/popularity.gd")
const PermissionsScript = preload("res://scripts/permissions.gd")
const FlowScript = preload("res://scripts/amendment_flow.gd")
const ScoringScript = preload("res://scripts/scoring.gd")
const SerializerScript = preload("res://scripts/serializer.gd")
const GameStateScript = preload("res://scripts/game_state.gd")
const ConstitutionScript = preload("res://scripts/constitution.gd")

const EXAM_WRITING = GameStateScript.ElectionPhase.EXAM_WRITING
const EXAM_ANSWERING = GameStateScript.ElectionPhase.EXAM_ANSWERING
const VOTING = GameStateScript.ElectionPhase.VOTING
const INAUG = GameStateScript.AmendWindow.INAUGURATION
const SERVER := 0

var failures: int = 0


func _init() -> void:
	the_first_election()
	writing_the_exam()
	sitting_and_marking_the_exam()
	who_can_take_part()
	ties_and_lots()
	the_role_card_draw()
	a_cancelled_leader_keeps_the_seat()
	vacancies_and_eliminations()
	secrets_and_saves()
	print("%d failure(s)" % failures)
	quit(1 if failures > 0 else 0)


func the_first_election() -> void:
	var s := make_state()
	s.leader_id = -1
	var ev := ElectionScript.begin(s, "first")
	expect("no exam in the first election", types(ev), ["election_started", "vote_started"])
	expect("... everyone votes and everyone can stand", [ev[1]["voters"], ev[1]["candidates"]], [[1, 2, 3, 4, 5], [1, 2, 3, 4, 5]])
	expect("the vote is open", s.election["phase"], VOTING)
	expect("the events were logged", s.event_log.size(), 2)

	vote_all(s, {1: 2, 2: 2, 3: 2, 4: 3})
	expect("ballots are in server state", s.election["votes"].size(), 4)
	var out := send(s, 5, {"type": "cast_vote", "candidate": 3})
	expect("the last ballot decides it", types(out), ["ballot_cast", "leader_elected", "leader_installed"])
	expect("the ballot event says that, not for whom", out[0].has("candidate"), false)
	expect("the result reveals the tally", out[1]["tally"], {1: 0, 2: 3, 3: 2, 4: 0, 5: 0})
	expect("... and who voted for whom", out[1]["votes"][4], 3)
	expect("player 2 is Leader", s.leader_id, 2)
	expect("... by a vote", out[1]["how"], "vote")
	expect("a new term starts at 0 turns", s.turns_played, 0)
	expect("the election is over", s.election.is_empty(), true)
	expect("the first term is round 1", s.current_round, 1)
	expect("a Leader role card was drawn", s.leader_type in [GameStateScript.LeaderType.DICTATOR, GameStateScript.LeaderType.PRESIDENT, GameStateScript.LeaderType.COMMANDER], true)
	expect("... and announced", out[2]["leader_type"], s.leader_type)
	expect("the inauguration window is open", [s.windows_used[0], s.windows_used[1], s.windows_used[2]], [false, false, false])

	# Voting for yourself is allowed.
	s = make_state()
	s.leader_id = -1
	ElectionScript.begin(s, "first")
	vote_all(s, {1: 1, 2: 1, 3: 1, 4: 1})
	expect("you can vote for yourself", types(send(s, 5, {"type": "cast_vote", "candidate": 1})).has("leader_installed"), true)
	expect("player 1 wins", s.leader_id, 1)


func writing_the_exam() -> void:
	var s := make_state()
	var ev := ElectionScript.begin(s, "term_ended")
	expect("a finished term starts with the Leader writing an exam", types(ev), ["election_started"])
	expect("... which says an exam is coming", ev[0]["exam"], true)
	expect("phase EXAM_WRITING", s.election["phase"], EXAM_WRITING)
	expect("the outgoing Leader is credited a full term", s.half_rounds[1], 2)

	expect("only the Leader writes it", send(s, 2, write(exam())).front()["reason"], "Only the Leader writes the exam.")
	expect("a vote can't happen yet", types(send(s, 2, {"type": "cast_vote", "candidate": 1})), ["rejected"])
	expect("a player can't answer yet", types(send(s, 2, {"type": "answer_exam", "answers": []})), ["rejected"])
	expect("a player can't skip the exam", send(s, 2, {"type": "skip_exam"})[0]["reason"], "Only the server can skip the exam.")

	# What a valid exam looks like, and every way to break it.
	var good: Array = exam()
	for case in [
		["4 questions are too few", good.slice(0, 4)],
		["11 questions are too many", exam(11)],
		["not a list", "questions"],
		["a question that isn't an object", good.slice(0, 4) + [5]],
		["a blank question", mutated(good, 0, "text", "   ")],
		["a question that is too long", mutated(good, 0, "text", "x".repeat(201))],
		["a control character in a question", mutated(good, 0, "text", "bad\ttext")],
		["a question that isn't text", mutated(good, 0, "text", 7)],
		["one option", mutated(good, 0, "options", ["A"])],
		["four options are too many", mutated(good, 0, "options", ["A", "B", "C", "D"])],
		["a blank option", mutated(good, 0, "options", ["A", " ", "C"])],
		["the same option twice", mutated(good, 0, "options", ["A", "A", "C"])],
		["options that aren't a list", mutated(good, 0, "options", "ABC")],
		["an answer out of range", mutated(good, 0, "answer", 3)],
		["a negative answer", mutated(good, 0, "answer", -1)],
		["an answer that isn't a whole number", mutated(good, 0, "answer", "A")],
	]:
		var out := send(s, 1, {"type": "write_exam", "questions": case[1]})
		expect("refused: " + case[0], types(out), ["rejected"])
	expect("none of those changed anything", s.election["phase"], EXAM_WRITING)

	# The limits are 5 to 10 questions and 2 to 3 options, and both ends are allowed.
	for ok in [["5 questions", exam(5)], ["10 questions", exam(10)], ["2 options", mutated(good, 0, "options", ["A", "B"])], ["3 options", good]]:
		var fresh := make_state()
		ElectionScript.begin(fresh, "term_ended")
		expect(ok[0] + " is allowed", types(send(fresh, 1, write(ok[1]))), ["exam_written"])

	expect("a sick Leader can't write one", sick_leader_cannot_write(), true)
	var accepted := send(s, 1, write(exam()))
	expect("a valid exam is accepted", types(accepted), ["exam_written"])
	expect("... the questions are public", accepted[0]["questions"].size(), 5)
	expect("... the answer key is not in the event", accepted[0].has("key") or str(accepted[0]).contains("answer"), false)
	expect("... the key is kept by the server", s.election["key"], [0, 1, 2, 0, 1])
	expect("the exam is now being sat", s.election["phase"], EXAM_ANSWERING)
	expect("... by everyone but the Leader", s.election["takers"], [2, 3, 4, 5])
	expect("a second exam is refused", types(send(s, 1, write(exam()))), ["rejected"])

	# Spaces round the text are trimmed.
	s = make_state()
	ElectionScript.begin(s, "term_ended")
	send(s, 1, write(mutated(exam(), 0, "text", "  Padded?  ")))
	expect("question text is trimmed", s.election["exam"]["questions"][0]["text"], "Padded?")


func sitting_and_marking_the_exam() -> void:
	var s := open_exam(make_state())
	expect("the wrong number of answers is refused", types(send(s, 2, {"type": "answer_exam", "answers": [0, 1]})), ["rejected"])
	expect("an answer out of range is refused", types(send(s, 2, {"type": "answer_exam", "answers": [0, 1, 2, 0, 9]})), ["rejected"])
	expect("an answer that isn't a number is refused", types(send(s, 2, {"type": "answer_exam", "answers": [0, 1, 2, 0, "1"]})), ["rejected"])
	expect("the Leader doesn't sit their own exam", types(send(s, 1, {"type": "answer_exam", "answers": answers(5, 5)})), ["rejected"])

	var ev := send(s, 2, {"type": "answer_exam", "answers": answers(5, 5)})
	expect("handing in answers is announced, without the answers", [types(ev), ev[0].has("answers")], [["exam_answered"], false])
	expect("answers are kept by the server", s.election["answers"][2], [0, 1, 2, 0, 1])
	expect("answering twice is refused", types(send(s, 2, {"type": "answer_exam", "answers": answers(5, 5)})), ["rejected"])
	send(s, 3, {"type": "answer_exam", "answers": answers(5, 3)})   # 3 of 5: more than 50%
	send(s, 4, {"type": "answer_exam", "answers": answers(5, 2)})   # 2 of 5: not enough
	var last := send(s, 5, {"type": "answer_exam", "answers": answers(5, 0)})
	expect("the last answers reveal the key and open the vote", types(last), ["exam_answered", "exam_revealed", "vote_started"])
	expect("the key is revealed", last[1]["key"], [0, 1, 2, 0, 1])
	expect("scores", last[1]["scores"], {2: 5, 3: 3, 4: 2, 5: 0})
	expect("more than 50% passes: players 2 and 3, and the Leader who wrote it", last[1]["passed"], [1, 2, 3])
	expect("only those who passed vote and stand", [last[2]["voters"], last[2]["candidates"]], [[1, 2, 3], [1, 2, 3]])
	expect("someone who failed can't vote", types(send(s, 4, {"type": "cast_vote", "candidate": 2})), ["rejected"])
	expect("... or be voted for", types(send(s, 2, {"type": "cast_vote", "candidate": 4})), ["rejected"])

	# Exactly 50% is not "more than" 50%.
	s = open_exam(make_state(), exam(6))
	send(s, 2, {"type": "answer_exam", "answers": answers(6, 3)})
	send(s, 3, {"type": "answer_exam", "answers": answers(6, 4)})
	send(s, 4, {"type": "answer_exam", "answers": answers(6, 3)})
	var six := send(s, 5, {"type": "answer_exam", "answers": answers(6, 3)})
	expect("3 of 6 is exactly 50%: not enough; 4 of 6 passes", six[1]["passed"], [1, 3])

	# The pass mark and the comparison are in the Constitution, so a Leader can change them.
	s = open_exam(make_state())
	set_rule_word(s, 1, 1, "80%")
	send(s, 2, {"type": "answer_exam", "answers": answers(5, 5)})
	send(s, 3, {"type": "answer_exam", "answers": answers(5, 4)})
	send(s, 4, {"type": "answer_exam", "answers": answers(5, 3)})
	var strict := send(s, 5, {"type": "answer_exam", "answers": answers(5, 2)})
	expect("with a pass mark of 80%, only 5 of 5 passes (4 of 5 is exactly 80%)", strict[1]["passed"], [1, 2])

	s = open_exam(make_state())
	set_rule_word(s, 1, 0, "less")
	send(s, 2, {"type": "answer_exam", "answers": answers(5, 5)})
	send(s, 3, {"type": "answer_exam", "answers": answers(5, 3)})
	send(s, 4, {"type": "answer_exam", "answers": answers(5, 2)})
	var less := send(s, 5, {"type": "answer_exam", "answers": answers(5, 0)})
	expect("'less than 50%' passes those who got fewer right", less[1]["passed"], [1, 4, 5])

	# Nobody but the Leader passes: the Leader stands unopposed and is re-elected.
	s = open_exam(make_state())
	for id in [2, 3, 4]:
		send(s, id, {"type": "answer_exam", "answers": answers(5, 0)})
	var all_fail := send(s, 5, {"type": "answer_exam", "answers": answers(5, 0)})
	expect("a rigged exam: the Leader is the only candidate", types(all_fail), ["exam_answered", "exam_revealed", "vote_started", "leader_elected", "leader_installed"])
	expect("... elected unopposed", all_fail[3]["how"], "unopposed")
	expect("... and still Leader, in a new term", [s.leader_id, s.current_round], [1, 2])

	# Nobody who passed can stand: the exam is void and everyone takes part.
	s = open_exam(make_state())
	for id in [2, 3, 4]:
		send(s, id, {"type": "answer_exam", "answers": answers(5, 0)})
	s.eliminated[1] = true
	var voided := send(s, 5, {"type": "answer_exam", "answers": answers(5, 0)})
	expect("with nobody left to stand the exam is void", types(voided), ["exam_answered", "exam_revealed", "exam_void", "vote_started"])
	expect("... and everyone alive may take part", voided[3]["candidates"], [2, 3, 4, 5])

	# A sick player doesn't sit the exam and isn't waited for.
	s = make_state()
	s.sick[3] = true
	ElectionScript.begin(s, "term_ended")
	send(s, 1, write(exam()))
	expect("a sick player isn't a taker", s.election["takers"], [2, 4, 5])
	expect("... and can't answer", types(send(s, 3, {"type": "answer_exam", "answers": answers(5, 5)})), ["rejected"])
	for id in [2, 4]:
		send(s, id, {"type": "answer_exam", "answers": answers(5, 5)})
	expect("the exam is complete without them", types(send(s, 5, {"type": "answer_exam", "answers": answers(5, 5)})).has("exam_revealed"), true)

	# The server can skip an exam the Leader never wrote.
	s = make_state()
	ElectionScript.begin(s, "term_ended")
	var skipped := send(s, SERVER, {"type": "skip_exam"})
	expect("skipping the exam opens the vote to everyone", types(skipped), ["exam_skipped", "vote_started"])
	expect("... all five may vote and stand", [skipped[1]["voters"], skipped[1]["candidates"]], [[1, 2, 3, 4, 5], [1, 2, 3, 4, 5]])


func who_can_take_part() -> void:
	# A sick Leader can't write an exam, so there is none.
	var s := make_state()
	s.sick[1] = true
	var ev := ElectionScript.begin(s, "term_ended")
	expect("a sick Leader means no exam", [ev[0]["exam"], types(ev)], [false, ["election_started", "vote_started"]])
	expect("... and the sick Leader isn't a voter or candidate", [ev[1]["voters"], ev[1]["candidates"]], [[2, 3, 4, 5], [2, 3, 4, 5]])
	expect("... but is still credited the term", s.half_rounds[1], 2)

	# A CANCELLED player can vote but can't stand.
	s = make_state()
	s.leader_id = -1
	s.popularity[3] = -50
	ev = ElectionScript.begin(s, "first")
	expect("CANCELLED: votes but doesn't stand", [ev[1]["voters"], ev[1]["candidates"]], [[1, 2, 3, 4, 5], [1, 2, 4, 5]])
	expect("... a ballot for them is refused", types(send(s, 1, {"type": "cast_vote", "candidate": 3})), ["rejected"])
	expect("... but they may cast one", types(send(s, 3, {"type": "cast_vote", "candidate": 4})), ["ballot_cast"])

	# Ballots are checked.
	s = make_state()
	s.leader_id = -1
	s.eliminated[5] = true
	s.sick[4] = true
	ElectionScript.begin(s, "first")
	expect("an eliminated player can't vote", types(send(s, 5, {"type": "cast_vote", "candidate": 1})), ["rejected"])
	expect("a sick player can't vote", types(send(s, 4, {"type": "cast_vote", "candidate": 1})), ["rejected"])
	expect("a ballot for nobody on the list is refused", types(send(s, 1, {"type": "cast_vote", "candidate": 9})), ["rejected"])
	expect("a ballot that isn't a number is refused", types(send(s, 1, {"type": "cast_vote", "candidate": "2"})), ["rejected"])
	expect("a sick player can't be voted for", types(send(s, 1, {"type": "cast_vote", "candidate": 4})), ["rejected"])
	send(s, 1, {"type": "cast_vote", "candidate": 2})
	expect("voting twice is refused", types(send(s, 1, {"type": "cast_vote", "candidate": 3})), ["rejected"])
	expect("an unknown command is refused", types(send(s, 1, {"type": "bribe"})), ["rejected"])

	# Only one person can stand: no ballots needed.
	s = make_state()
	s.leader_id = -1
	for id in [2, 3, 4, 5]:
		s.popularity[id] = -50
	var solo := ElectionScript.begin(s, "first")
	expect("one candidate wins unopposed", types(solo), ["election_started", "vote_started", "leader_elected", "leader_installed"])
	expect("... player 1", [s.leader_id, solo[2]["how"]], [1, "unopposed"])

	# Nobody can stand at all.
	s = make_state()
	s.leader_id = -1
	for id in s.player_ids:
		s.popularity[id] = -50
	var failed := ElectionScript.begin(s, "first")
	expect("if nobody can stand the election fails cleanly", types(failed), ["election_started", "election_failed"])
	expect("... and is cleared", s.election.is_empty(), true)


func ties_and_lots() -> void:
	# A tie is re-run among the tied candidates.
	var s := make_state()
	s.leader_id = -1
	s.player_ids = [1, 2, 3, 4]
	ElectionScript.begin(s, "first")
	vote_all(s, {1: 2, 2: 2, 3: 3})
	var tie := send(s, 4, {"type": "cast_vote", "candidate": 3})
	expect("2 votes each: a runoff", types(tie), ["ballot_cast", "election_tied", "vote_started"])
	expect("... between the tied only", tie[2]["candidates"], [2, 3])
	expect("... the first runoff", tie[2]["runoff"], 1)
	expect("... with fresh ballots", s.election["votes"].size(), 0)
	expect("the first round's ballots were revealed", tie[1]["votes"], {1: 2, 2: 2, 3: 3, 4: 3})
	expect("a vote for someone knocked out is refused", types(send(s, 1, {"type": "cast_vote", "candidate": 4})), ["rejected"])
	vote_all(s, {1: 2, 2: 2, 3: 3})
	var decided := send(s, 4, {"type": "cast_vote", "candidate": 2})
	expect("the runoff decides it", types(decided), ["ballot_cast", "leader_elected", "leader_installed"])
	expect("... player 2 wins 3 to 1", [s.leader_id, decided[1]["tally"][2]], [2, 3])

	# A three-way vote where two tie at the top.
	s = make_state()
	s.leader_id = -1
	ElectionScript.begin(s, "first")
	vote_all(s, {1: 2, 2: 2, 3: 3, 4: 3})
	var top2 := send(s, 5, {"type": "cast_vote", "candidate": 4})
	expect("only those tied for first go to the runoff", top2[2]["candidates"], [2, 3])

	# A second tie is decided by lot, and the lot can go either way.
	var winners: Dictionary = {}
	for seed_value in range(1, 31):
		s = make_state()
		s.leader_id = -1
		s.player_ids = [1, 2]
		RngScript.seed_with(s, seed_value)
		ElectionScript.begin(s, "first")
		vote_all(s, {1: 1})
		send(s, 2, {"type": "cast_vote", "candidate": 2})   # 1-1: runoff
		vote_all(s, {1: 1})
		var lot := send(s, 2, {"type": "cast_vote", "candidate": 2})   # 1-1 again: by lot
		if seed_value == 1:
			expect("a second tie goes to a lot", types(lot), ["ballot_cast", "election_tied", "leader_elected", "leader_installed"])
			expect("... announced as such", lot[2]["how"], "lot")
		winners[s.leader_id] = true
	expect("over 30 seeds both candidates win a lot at some point", winners.keys().size(), 2)

	s = make_state()
	s.leader_id = -1
	s.player_ids = [1, 2]
	RngScript.seed_with(s, 77)
	var again: GameStateScript = SerializerScript.state_from_json(SerializerScript.state_to_json(s), [])
	ElectionScript.begin(s, "first")
	ElectionScript.begin(again, "first")
	for state in [s, again]:
		vote_all(state, {1: 1})
		send(state, 2, {"type": "cast_vote", "candidate": 2})
		vote_all(state, {1: 1})
		send(state, 2, {"type": "cast_vote", "candidate": 2})
	expect("the same saved seed gives the same lot", s.leader_id, again.leader_id)


func the_role_card_draw() -> void:
	# Three Leader cards, one for each role. Each is kept by the Leader for their term and goes back
	# into the pile, shuffled, only when it is time to draw, so all three are in every draw.
	var s := make_state()
	RngScript.seed_with(s, 2024)
	var counts: Dictionary = {GameStateScript.LeaderType.DICTATOR: 0, GameStateScript.LeaderType.PRESIDENT: 0, GameStateScript.LeaderType.COMMANDER: 0}
	var repeats: int = 0
	var previous: int = -1
	for i in 6000:
		ElectionScript.install_leader(s, 1, "test")
		counts[s.leader_type] += 1
		if s.leader_type == previous:
			repeats += 1
		previous = s.leader_type
	var dictator: int = counts[GameStateScript.LeaderType.DICTATOR]
	var president: int = counts[GameStateScript.LeaderType.PRESIDENT]
	var commander: int = counts[GameStateScript.LeaderType.COMMANDER]
	expect("Dictator about 1 in 3 (%d of 6000)" % dictator, dictator > 1800 and dictator < 2200, true)
	expect("President about 1 in 3 (%d)" % president, president > 1800 and president < 2200, true)
	expect("Commander about 1 in 3 (%d)" % commander, commander > 1800 and commander < 2200, true)
	expect("the Leader's own card is back in the draw: the same card comes up again about 1 time in 3 (%d)" % repeats, repeats > 1800 and repeats < 2200, true)

	# A new term wipes the old one's state.
	s = make_state()
	s.turns_played = 5
	s.windows_used = {0: true, 1: true, 2: true}
	s.amend = {"phase": 1}
	s.current_round = 4
	s.election = {"reason": "term_ended"}
	var ev := ElectionScript.install_leader(s, 3, "vote")
	expect("the new Leader is in", [s.leader_id, ev[0]["leader"]], [3, 3])
	expect("a fresh term: no turns played, no windows used", [s.turns_played, s.windows_used], [0, {0: false, 1: false, 2: false}])
	expect("... nothing left of the old amendment", s.amend.is_empty(), true)
	expect("... the round counter moved on", s.current_round, 5)
	expect("a coup (no election) also installs a Leader and starts a term", [ElectionScript.install_leader(s, 2, "coup")[0]["how"], s.current_round], ["coup", 6])
	expect("... and after a coup the new Leader goes first", s.leader_goes_first, true)
	ElectionScript.install_leader(s, 2, "vote")
	expect("an ordinary election does not", s.leader_goes_first, false)


func a_cancelled_leader_keeps_the_seat() -> void:
	# Becoming CANCELLED (or sick) does not start an election: the Leader keeps the seat (Part 3).
	var s := make_state()
	PopularityScript.change_base(s, 1, -80)
	expect("the Leader is CANCELLED", PopularityScript.effective(s, 1), -50)
	expect("... and still the Leader", s.leader_id, 1)
	expect("... no election starts", [s.election.is_empty(), s.event_log.size()], [true, 0])
	expect("... they can't use Leader powers", PermissionsScript.can_amend(s, 1, INAUG), "A CANCELLED Leader can't amend.")

	# End to end: a failed amendment is what drives them to -50.
	s = make_state()
	s.popularity[1] = -26
	var words: Array = s.articles[2]
	var texts: Array = []
	for word in words:
		texts.append(word["text"])
	texts[0] = "Duty:"   # a fixed word: a failed check, -24 popularity
	var ev := FlowScript.handle(s, 1, {"type": "propose", "window": INAUG, "article_id": 2, "new_texts": texts})
	expect("the failed check drops them to -50", [types(ev), s.popularity[1]], [["amendment_proposed", "amendment_failed"], -50])
	expect("... and that starts no election", [s.election.is_empty(), s.leader_id], [true, 1])

	# When the term ends the election runs as normal: no exam, they may vote but cannot stand.
	var end := ElectionScript.begin(s, "term_ended")
	expect("at the end of the term there is no exam", end[0]["exam"], false)
	expect("... they can vote", 1 in end[1]["voters"], true)
	expect("... but not stand", end[1]["candidates"], [2, 3, 4, 5])

func vacancies_and_eliminations() -> void:
	# An eliminated Leader: the seat is vacant and a new Leader is voted for with no exam.
	var s := make_state()
	var ev := ElimScript.eliminate(s, 1, "test")
	expect("the Leader's elimination starts an election", types(ev).has("election_started"), true)
	expect("... a vacancy election, with no exam", [s.election["reason"], ev[types(ev).find("election_started")]["exam"]], ["vacancy", false])
	expect("... the dead Leader can't be chosen", s.election["candidates"], [2, 3, 4, 5])
	expect("... and the cut-short term counts half a round (1 half-round)", s.half_rounds.get(1, 0), 1)
	vote_all(s, {2: 3, 3: 3, 4: 3})
	var done := send(s, 5, {"type": "cast_vote", "candidate": 4})
	expect("the vote installs a new Leader", [types(done).has("leader_installed"), s.leader_id], [true, 3])
	expect("a new term begins (round 2)", s.current_round, 2)

	# The credit is only for the record: an eliminated player never ranks, whatever they have.
	s = make_state()
	s.half_rounds = {1: 6, 2: 4, 3: 2}
	ElimScript.eliminate(s, 1, "test")
	expect("their rounds are kept for the record: 6 + 1", s.half_rounds[1], 7)
	expect("... but they can't win, so the next best does", ScoringScript.final_winners(s), [2])

	# A second elimination of a non-Leader adds nothing.
	s = make_state()
	ElimScript.eliminate(s, 3, "test")
	expect("an ordinary player's elimination credits no one", s.half_rounds.is_empty(), true)

	# Eliminating the Leader while an election is already under way doesn't start a second one.
	s = make_state()
	ElectionScript.begin(s, "term_ended")
	ElimScript.eliminate(s, 1, "test")
	expect("the exam can't be written now, so it is skipped and the vote opens", s.election["phase"], VOTING)
	expect("... still the same election", s.election["reason"], "term_ended")
	expect("... the Leader credited at the term's end stays credited", s.half_rounds[1], 2)

	# The last awaited voter is eliminated: the vote completes.
	s = make_state()
	s.leader_id = -1
	ElectionScript.begin(s, "first")
	vote_all(s, {1: 2, 2: 2, 3: 2, 4: 2})
	expect("waiting for player 5", s.election["phase"], VOTING)
	var gone := ElimScript.eliminate(s, 5, "test")
	expect("eliminating the last voter finishes the election", types(gone).has("leader_elected"), true)
	expect("... player 2 wins", s.leader_id, 2)

	# A candidate eliminated before the count: ballots for them are discarded.
	s = make_state()
	s.leader_id = -1
	ElectionScript.begin(s, "first")
	vote_all(s, {1: 2, 2: 2, 3: 2, 4: 3})
	s.eliminated[2] = true   # eliminated before the last ballot
	var dropped := send(s, 5, {"type": "cast_vote", "candidate": 3})
	expect("ballots for a dead candidate don't count; the other wins", [s.leader_id, dropped[1]["tally"].has(2)], [3, false])

	# The last exam-taker is eliminated: the exam is marked.
	s = open_exam(make_state())
	for id in [2, 3, 4]:
		send(s, id, {"type": "answer_exam", "answers": answers(5, 5)})
	var marked := ElimScript.eliminate(s, 5, "test")
	expect("eliminating the last taker marks the exam", types(marked).has("exam_revealed"), true)


func secrets_and_saves() -> void:
	var s := open_exam(make_state())
	send(s, 2, {"type": "answer_exam", "answers": answers(5, 5)})
	send(s, 3, {"type": "answer_exam", "answers": answers(5, 1)})
	for viewer in [1, 2, 3, 4, 99]:
		var view: Dictionary = ViewsScript.state_view(s, viewer)
		var text: String = ViewsScript.state_view_json(s, viewer)
		expect("player %d: no answer key in their view" % viewer, view["election"].has("key"), false)
		expect("player %d: no one's answers in their view" % viewer, view["election"].has("answers"), false)
		expect("player %d: the key never reaches the text sent" % viewer, text.contains("\"key\":"), false)
		expect("player %d: sees who has answered" % viewer, view["election"]["answered"], [2, 3])
		expect("player %d: the random generator never leaves the server" % viewer, view.has("rng_state") or text.contains("rng_state"), false)
		expect("player %d: the questions are public" % viewer, view["election"]["exam"]["questions"].size(), 5)
	expect("a player sees their own answers", ViewsScript.state_view(s, 2)["election"]["my_answers"], [0, 1, 2, 0, 1])
	expect("... not someone else's", ViewsScript.state_view(s, 4)["election"].has("my_answers"), false)

	s = make_state()
	s.leader_id = -1
	ElectionScript.begin(s, "first")
	vote_all(s, {1: 2, 2: 3})
	var voting_view: Dictionary = ViewsScript.state_view(s, 4)
	expect("ballots are hidden", [voting_view["election"].has("votes"), voting_view["election"]["voted"]], [false, [1, 2]])
	expect("... except your own", ViewsScript.state_view(s, 2)["election"]["my_vote"], 3)
	expect("... the text sent has no ballot table", ViewsScript.state_view_json(s, 4).contains("\"votes\":"), false)

	# Saved half way through the exam, the game carries on identically.
	s = open_exam(make_state())
	send(s, 2, {"type": "answer_exam", "answers": answers(5, 5)})
	var errors: Array = []
	var restored: GameStateScript = SerializerScript.state_from_json(SerializerScript.state_to_json(s), errors)
	expect("an election in progress is saved", errors, [])
	for state in [s, restored]:
		for id in [3, 4]:
			send(state, id, {"type": "answer_exam", "answers": answers(5, 4)})
	var a := send(s, 5, {"type": "answer_exam", "answers": answers(5, 1)})
	var b := send(restored, 5, {"type": "answer_exam", "answers": answers(5, 1)})
	expect("the restored exam finishes the same way", [types(a), a[1]["passed"]], [types(b), b[1]["passed"]])
	expect("... and so do the saves", SerializerScript.state_to_json(s), SerializerScript.state_to_json(restored))


# --- helpers ---------------------------------------------------------------------------

func make_state() -> GameStateScript:
	var s: GameStateScript = GameStateScript.new()
	s.player_ids = [1, 2, 3, 4, 5]
	s.player_count = 5
	s.leader_id = 1
	s.leader_type = GameStateScript.LeaderType.PRESIDENT
	for id in s.player_ids:
		s.psd[id] = 1000
		s.popularity[id] = 0
		s.sick[id] = false
	s.articles = ConstitutionScript.initial_articles()
	RngScript.seed_with(s, 1234)
	return s


# n questions, each with options A, B, C; the right option of question i is i % 3.
func exam(count: int = 5) -> Array:
	var questions: Array = []
	for i in count:
		questions.append({"text": "Question %d?" % (i + 1), "options": ["A", "B", "C"], "answer": i % 3})
	return questions


# A copy of the exam with one field of one question replaced.
func mutated(questions: Array, index: int, field: String, value: Variant) -> Array:
	var copy: Array = questions.duplicate(true)
	copy[index][field] = value
	return copy


# Answers to an exam of `count` questions with the first `right` correct and the rest wrong.
func answers(count: int, right: int) -> Array:
	var result: Array = []
	for i in count:
		result.append(i % 3 if i < right else (i % 3 + 1) % 3)
	return result


func write(questions: Array) -> Dictionary:
	return {"type": "write_exam", "questions": questions}


# The Leader's term has ended and they have written an exam that now waits for answers.
func open_exam(s: GameStateScript, questions: Array = []) -> GameStateScript:
	ElectionScript.begin(s, "term_ended")
	send(s, 1, write(questions if not questions.is_empty() else exam()))
	return s


func sick_leader_cannot_write() -> bool:
	var s := make_state()
	ElectionScript.begin(s, "term_ended")
	s.sick[1] = true
	return send(s, 1, write(exam()))[0]["reason"] == "A sick or CANCELLED Leader can't write an exam."


func vote_all(s: GameStateScript, ballots: Dictionary) -> void:
	for voter in ballots:
		send(s, voter, {"type": "cast_vote", "candidate": ballots[voter]})


func set_rule_word(s: GameStateScript, article_id: int, slot: int, text: String) -> void:
	var seen: int = 0
	for word in s.articles[article_id]:
		if word["amendable"]:
			if seen == slot:
				word["text"] = text
				return
			seen += 1


func send(s: GameStateScript, player_id: int, command: Dictionary) -> Array:
	return ElectionScript.handle(s, player_id, command)


func types(events: Array) -> Array:
	var result: Array = []
	for event in events:
		result.append(event["type"])
	return result


func expect(label: String, actual: Variant, wanted: Variant) -> void:
	var ok: bool = typeof(actual) == typeof(wanted) and actual == wanted
	if not ok:
		failures += 1
	print(("PASS " if ok else "FAIL ") + label + " -> " + str(actual).left(80))
