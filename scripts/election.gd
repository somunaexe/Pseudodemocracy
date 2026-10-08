class_name Election

# Choosing the next Leader: Exam, Vote, Role card draw (handbook, Part 3). Same pattern as the
# amendment flow: commands in, events out, a state machine in between.
#
#   begin(reason) --> EXAM_WRITING --write_exam--> EXAM_ANSWERING --last answer--> VOTING
#   begin(reason) --> VOTING                 (no exam: the first election, a vacant seat, or no exam ready)
#   EXAM_WRITING --skip_exam--> VOTING       (server only: the Leader didn't write one in time)
#   VOTING --last ballot--> a winner (or a runoff) --> the role card draw --> NONE
#
# Every step has a clock (the digital version; Game.tick moves it, see step()): the Leader has examWriteSeconds to write the
# exam or it is skipped; the takers have examAnswerSeconds and those who haven't answered fail it; the voters have
# electionVoteSeconds and those who haven't voted abstain (a tie is still run again, and then decided by lot).
#
# Reasons: "first" (no exam), "term_ended" (the Leader writes the exam), "vacancy" (the Leader
# was eliminated: no exam, because there is nobody to write it).
#
# Secrets: the answer key, everyone's answers and everyone's ballot live in state.election and
# never leave the server until the result is announced (Views removes them).
#
# Assumptions the handbook leaves open (see docs/design_decisions.md): the most votes wins; a
# tie is re-run among the tied candidates, and a second tie is decided by lot; anyone eligible
# can be voted for (there is no separate "running" step); a CANCELLED player can vote but not
# stand; the Leader who wrote the exam is counted as having passed it.

const GameStateScript = preload("res://scripts/game_state.gd")
const GameDataScript = preload("res://scripts/game_data.gd")
const LawScript = preload("res://scripts/law.gd")
const PopularityScript = preload("res://scripts/popularity.gd")
const RngScript = preload("res://scripts/rng.gd")
const RoundEndScript = preload("res://scripts/round_end.gd")
const LoyalistsScript = preload("res://scripts/loyalists.gd")
const ViceScript = preload("res://scripts/vice.gd")
const LeaderCardsScript = preload("res://scripts/leader_cards.gd")
const EventsScript = preload("res://scripts/events.gd")

# Only the server may skip the exam (it knows the Leader ran out of time).
const SERVER_ID := 0

const ALLOWED_COMMANDS = {
	GameStateScript.ElectionPhase.NONE: [],
	GameStateScript.ElectionPhase.EXAM_WRITING: ["write_exam", "skip_exam"],
	GameStateScript.ElectionPhase.EXAM_ANSWERING: ["answer_exam"],
	GameStateScript.ElectionPhase.VOTING: ["cast_vote"],
}


# --- starting ----------------------------------------------------------------------------

# Start an election. reason: "first", "term_ended" or "vacancy" (see above). When a term ends
# normally the outgoing Leader is credited a full term (2 half-rounds).
static func begin(state: GameStateScript, reason: String) -> Array:
	assert(state.election.is_empty(), "an election is already under way")
	assert(reason in ["first", "term_ended", "vacancy"], "unknown election reason '%s'" % reason)
	var events: Array = []
	var leader: int = state.leader_id
	if reason != "first":
		events.append_array(RoundEndScript.run(state))   # the round is over: sickness counts down, charges come back
	if reason == "term_ended" and leader != -1:
		state.half_rounds[leader] = int(state.half_rounds.get(leader, 0)) + 2
		if state.vice_id != -1:
			state.half_rounds[state.vice_id] = int(state.half_rounds.get(state.vice_id, 0)) + 1   # a term as Vice is half a round
	ViceScript.clear(state)   # the Vice serves until the end of the term

	state.election = {"phase": GameStateScript.ElectionPhase.NONE, "reason": reason, "runoff": 0}
	var exam: bool = reason == "term_ended" and leader != -1 and _can_use_pledges(state, leader)
	events.append(EventsScript.make("election_started", {"reason": reason, "exam": exam}))
	if exam:
		state.election["phase"] = GameStateScript.ElectionPhase.EXAM_WRITING
		events[events.size() - 1]["ends_at_ms"] = _start_clock(state, "examWriteSeconds")
	else:
		events.append_array(_start_voting(state, _eligible_voters(state), _eligible_candidates(state, _eligible_voters(state))))
	state.event_log.append_array(events)
	return events


# Call after anything that changes who can take part (an elimination): the exam or the vote
# may now be complete, or the Leader may no longer be able to write the exam.
static func recheck(state: GameStateScript) -> Array:
	var events: Array = []
	match state.election.get("phase", GameStateScript.ElectionPhase.NONE):
		GameStateScript.ElectionPhase.EXAM_WRITING:
			if not _can_use_pledges(state, state.leader_id):
				events.append(EventsScript.make("exam_skipped", {"reason": "the Leader can no longer write one"}))
				events.append_array(_start_voting(state, _eligible_voters(state), _eligible_candidates(state, _eligible_voters(state))))
		GameStateScript.ElectionPhase.EXAM_ANSWERING:
			events.append_array(_maybe_reveal(state))
		GameStateScript.ElectionPhase.VOTING:
			events.append_array(_maybe_finish_vote(state))
	state.event_log.append_array(events)
	return events


# Make this player the Leader: the role card draw, and a fresh term. Also what a successful
# coup will use (a coup skips the exam and the vote).
static func install_leader(state: GameStateScript, winner: int, how: String) -> Array:
	var reason: String = str(state.election.get("reason", "coup"))
	var leader_type: int = LeaderCardsScript.draw(state)
	state.leader_id = winner
	state.leader_type = leader_type
	state.turns_played = 0
	state.leader_goes_first = (how == "coup" or reason == "first")   # after a coup, and in the very first term, the Leader goes first
	state.amend = {}
	state.amend_offer = {}
	for window in state.windows_used:
		state.windows_used[window] = false
	if reason != "first":
		state.current_round += 1
	state.election = {}
	var events: Array = [EventsScript.make("leader_installed", {"leader": winner, "leader_type": leader_type, "how": how, "round": state.current_round})]
	events.append_array(ViceScript.after_coup(state, winner))   # after a coup the Vice stays, unless they are the new Leader or a Dictator is
	return events


# --- commands ----------------------------------------------------------------------------

# Commands:
#   { "type": "write_exam", "questions": [ { "text": String, "options": [String, ...], "answer": int } ] }
#   { "type": "skip_exam" }                       (server only)
#   { "type": "answer_exam", "answers": [int, ...] }
#   { "type": "cast_vote", "candidate": int }
static func handle(state: GameStateScript, player_id: int, command: Dictionary) -> Array:
	var type: String = str(command.get("type", ""))
	var phase: int = state.election.get("phase", GameStateScript.ElectionPhase.NONE)
	if not ALLOWED_COMMANDS[phase].has(type):
		return [_reject(player_id, "'%s' isn't possible at this stage." % type)]
	var events: Array = []
	match type:
		"write_exam":
			events = _write_exam(state, player_id, command)
		"skip_exam":
			events = _skip_exam(state, player_id)
		"answer_exam":
			events = _answer_exam(state, player_id, command)
		"cast_vote":
			events = _cast_vote(state, player_id, command)
	if events.is_empty() or events[0]["type"] != "rejected":
		state.event_log.append_array(events)
	return events


# --- the clock ---------------------------------------------------------------------------

# Start the clock of the step that is beginning; returns when it runs out.
static func _start_clock(state: GameStateScript, key: String) -> int:
	state.election["deadline"] = state.clock_ms + GameDataScript.get_int(key) * 1000
	return int(state.election["deadline"])


# The clock ran out on the step the election is in: the exam is skipped, the slow fail it, the voters who didn't vote
# abstain. Returns the events, or [] if there is nothing to do yet.
static func step(state: GameStateScript) -> Array:
	if state.election.is_empty() or not state.election.has("deadline") or state.clock_ms < int(state.election["deadline"]):
		return []
	var events: Array = []
	match state.election.get("phase", GameStateScript.ElectionPhase.NONE):
		GameStateScript.ElectionPhase.EXAM_WRITING:
			events = [EventsScript.make("exam_skipped", {"reason": "the Leader ran out of time"})]
			var voters: Array = _eligible_voters(state)
			events.append_array(_start_voting(state, voters, _eligible_candidates(state, voters)))
		GameStateScript.ElectionPhase.EXAM_ANSWERING:
			if state.election["answers"].is_empty():
				# Nobody handed in anything: the exam decided nothing, so it is skipped and everyone votes.
				events = [EventsScript.make("exam_skipped", {"reason": "nobody answered in time"})]
				var everyone: Array = _eligible_voters(state)
				events.append_array(_start_voting(state, everyone, _eligible_candidates(state, everyone)))
			else:
				events = [EventsScript.make("exam_timeout", {"missing": _active_takers(state).filter(func(id): return not state.election["answers"].has(id))})]
				events.append_array(_reveal(state))
		GameStateScript.ElectionPhase.VOTING:
			events = [EventsScript.make("vote_timeout", {"missing": state.election["voters"].filter(func(id): return _can_vote(state, id) and not state.election["votes"].has(id))})]
			events.append_array(_count(state))
		_:
			state.election.erase("deadline")
	state.event_log.append_array(events)
	return events


# --- the exam ----------------------------------------------------------------------------

static func _write_exam(state: GameStateScript, player_id: int, command: Dictionary) -> Array:
	if player_id != state.leader_id:
		return [_reject(player_id, "Only the Leader writes the exam.")]
	if not _can_use_pledges(state, player_id):
		return [_reject(player_id, "A sick or CANCELLED Leader can't write an exam.")]
	var parsed: Dictionary = _parse_exam(command.get("questions", null))
	if parsed["problem"] != "":
		return [_reject(player_id, parsed["problem"])]

	state.election["exam"] = {"questions": parsed["questions"]}
	state.election["key"] = parsed["key"]          # SECRET until everyone has answered
	state.election["answers"] = {}                 # SECRET until everyone has answered
	state.election["takers"] = _eligible_voters(state).filter(func(id): return id != state.leader_id)
	state.election["phase"] = GameStateScript.ElectionPhase.EXAM_ANSWERING
	var events: Array = [EventsScript.make("exam_written", {
		"leader": player_id,
		"questions": parsed["questions"],      # the questions are public; the key is not
		"ends_at_ms": _start_clock(state, "examAnswerSeconds"),
	})]
	events.append_array(_maybe_reveal(state))
	return events


static func _skip_exam(state: GameStateScript, player_id: int) -> Array:
	if player_id != SERVER_ID:
		return [_reject(player_id, "Only the server can skip the exam.")]
	var events: Array = [EventsScript.make("exam_skipped", {"reason": "no exam was ready"})]
	var voters: Array = _eligible_voters(state)
	events.append_array(_start_voting(state, voters, _eligible_candidates(state, voters)))
	return events


# Returns { "problem": String, "questions": Array, "key": Array }. Anything a Leader types is untrusted text.
static func _parse_exam(raw: Variant) -> Dictionary:
	var min_questions: int = GameDataScript.get_int("examQuestions")
	var max_questions: int = GameDataScript.get_int("examMaxQuestions")
	var min_options: int = GameDataScript.get_int("examOptions")
	var max_options: int = GameDataScript.get_int("examMaxOptions")
	var max_text: int = GameDataScript.get_int("examTextMax")
	var fail := func(problem: String) -> Dictionary: return {"problem": problem, "questions": [], "key": []}

	if typeof(raw) != TYPE_ARRAY:
		return fail.call("An exam is a list of questions.")
	if raw.size() < min_questions or raw.size() > max_questions:
		return fail.call("An exam needs %d to %d questions." % [min_questions, max_questions])
	var questions: Array = []
	var key: Array = []
	for i in raw.size():
		var item = raw[i]
		var label: String = "Question %d" % (i + 1)
		if typeof(item) != TYPE_DICTIONARY:
			return fail.call("%s must be an object." % label)
		var text: String = _clean_text(item.get("text", null), max_text)
		if text == "":
			return fail.call("%s needs some text (up to %d characters, no control characters)." % [label, max_text])
		var options_raw = item.get("options", null)
		if typeof(options_raw) != TYPE_ARRAY or options_raw.size() < min_options or options_raw.size() > max_options:
			return fail.call("%s needs %d to %d options." % [label, min_options, max_options])
		var options: Array = []
		for option_raw in options_raw:
			var option: String = _clean_text(option_raw, max_text)
			if option == "":
				return fail.call("Every option of %s needs some text." % label)
			if option in options:
				return fail.call("%s has the same option twice." % label)
			options.append(option)
		var answer = item.get("answer", null)
		if typeof(answer) != TYPE_INT or answer < 0 or answer >= options.size():
			return fail.call("%s needs the number of its right option, from 0 to %d." % [label, options.size() - 1])
		questions.append({"text": text, "options": options})
		key.append(answer)
	return {"problem": "", "questions": questions, "key": key}


# Trimmed text, or "" if it isn't text, is empty, too long, or has control characters.
static func _clean_text(value: Variant, max_length: int) -> String:
	if typeof(value) != TYPE_STRING:
		return ""
	var text: String = value.strip_edges()
	if text.is_empty() or text.length() > max_length:
		return ""
	for character in text:
		if character.unicode_at(0) < 32 or character.unicode_at(0) == 127:
			return ""
	return text


static func _answer_exam(state: GameStateScript, player_id: int, command: Dictionary) -> Array:
	if not player_id in state.election["takers"] or not player_id in _active_takers(state):
		return [_reject(player_id, "You aren't sitting this exam.")]
	if state.election["answers"].has(player_id):
		return [_reject(player_id, "You have already handed in your answers.")]
	var answers = command.get("answers", null)
	var questions: Array = state.election["exam"]["questions"]
	if typeof(answers) != TYPE_ARRAY or answers.size() != questions.size():
		return [_reject(player_id, "Give one answer for each of the %d questions." % questions.size())]
	for i in answers.size():
		if typeof(answers[i]) != TYPE_INT or answers[i] < 0 or answers[i] >= questions[i]["options"].size():
			return [_reject(player_id, "Answer %d must be the number of one of its options." % (i + 1))]
	state.election["answers"][player_id] = answers.duplicate()
	var events: Array = [EventsScript.make("exam_answered", {"player": player_id})]   # THAT, never WHAT
	events.append_array(_maybe_reveal(state))
	return events


# Everyone still able to sit the exam.
static func _active_takers(state: GameStateScript) -> Array:
	return state.election["takers"].filter(func(id): return _is_active(state, id))


static func _maybe_reveal(state: GameStateScript) -> Array:
	if state.election.get("phase", GameStateScript.ElectionPhase.NONE) != GameStateScript.ElectionPhase.EXAM_ANSWERING:
		return []
	for id in _active_takers(state):
		if not state.election["answers"].has(id):
			return []   # still waiting for someone
	return _reveal(state)


# Everyone has answered: the key is revealed and the exam is marked.
static func _reveal(state: GameStateScript) -> Array:
	var key: Array = state.election["key"]
	var total: int = key.size()
	var mark: int = LawScript.get_int(state, "passMark")
	var direction: int = LawScript.get_int(state, "passCompare")   # more than (1) or less than (-1)
	var scores: Dictionary = {}
	var passed: Array = []
	for id in state.election["answers"]:
		var correct: int = 0
		for i in total:
			if state.election["answers"][id][i] == key[i]:
				correct += 1
		scores[id] = correct
		var difference: int = correct * 100 - mark * total   # compared without fractions
		if direction * difference > 0:
			passed.append(id)
	# The Leader wrote the exam and is counted as having passed it.
	if state.leader_id != -1 and not state.leader_id in passed:
		passed.append(state.leader_id)
	passed.sort()
	var events: Array = [EventsScript.make("exam_revealed", {"key": key.duplicate(), "total": total, "scores": scores, "passed": passed.duplicate()})]
	var voters: Array = passed.filter(func(id): return _can_vote(state, id))
	var candidates: Array = _eligible_candidates(state, voters)
	if candidates.is_empty():
		# Nobody who passed can stand, so the exam can't decide anything: everyone may take part.
		events.append(EventsScript.make("exam_void", {"reason": "nobody who passed can stand"}))
		voters = _eligible_voters(state)
		candidates = _eligible_candidates(state, voters)
	events.append_array(_start_voting(state, voters, candidates))
	return events


# --- the vote ----------------------------------------------------------------------------

static func _start_voting(state: GameStateScript, voters: Array, candidates: Array) -> Array:
	if candidates.is_empty():
		state.election = {}
		return [EventsScript.make("election_failed", {"reason": "nobody is able to stand"})]
	state.election["phase"] = GameStateScript.ElectionPhase.VOTING
	state.election["voters"] = voters
	state.election["candidates"] = candidates
	state.election["votes"] = {}   # voter id -> candidate id. SECRET until the result.
	var events: Array = [EventsScript.make("vote_started", {"candidates": candidates.duplicate(), "voters": voters.duplicate(), "runoff": state.election["runoff"], "ends_at_ms": _start_clock(state, "electionVoteSeconds")})]
	if candidates.size() == 1:
		events.append_array(_elect(state, candidates[0], "unopposed", {}))   # nothing to decide
	else:
		events.append_array(_maybe_finish_vote(state))
	return events


static func _cast_vote(state: GameStateScript, player_id: int, command: Dictionary) -> Array:
	if not player_id in state.election["voters"] or not _can_vote(state, player_id):
		return [_reject(player_id, "You can't vote in this election.")]
	if state.election["votes"].has(player_id):
		return [_reject(player_id, "You have already voted.")]
	var may: Callable = func(id): return id in state.election["voters"] and _can_vote(state, id)
	var blocked: String = LoyalistsScript.problem_voting(state, player_id, state.election["votes"], may)
	if blocked != "":
		return [_reject(player_id, blocked)]
	var candidate = command.get("candidate", null)
	if typeof(candidate) != TYPE_INT or not candidate in state.election["candidates"]:
		return [_reject(player_id, "That isn't one of the candidates.")]
	candidate = LoyalistsScript.vote_for(state, player_id, candidate, state.election["votes"], may)   # a Loyalist votes as their owner did
	state.election["votes"][player_id] = candidate
	var events: Array = [EventsScript.make("ballot_cast", {"voter": player_id})]   # THAT, never FOR WHOM
	for pair in LoyalistsScript.mirror(state, player_id, candidate, state.election["votes"], may):
		events.append(EventsScript.make("ballot_cast", {"voter": pair[0], "with": pair[1]}))   # their Loyalists vote the same
	events.append_array(_maybe_finish_vote(state))
	return events


static func _maybe_finish_vote(state: GameStateScript) -> Array:
	if state.election.get("phase", GameStateScript.ElectionPhase.NONE) != GameStateScript.ElectionPhase.VOTING:
		return []
	for id in state.election["voters"]:
		if _can_vote(state, id) and not state.election["votes"].has(id):
			return []   # still waiting for someone
	return _count(state)


static func _count(state: GameStateScript) -> Array:
	var candidates: Array = state.election["candidates"].filter(func(id): return _can_stand(state, id))
	var tally: Dictionary = {}
	for id in candidates:
		tally[id] = 0
	var revealed: Dictionary = {}
	for voter in state.election["votes"]:
		var choice: int = state.election["votes"][voter]
		if _can_vote(state, voter) and tally.has(choice):
			tally[choice] += 1
			revealed[voter] = choice
	if candidates.is_empty():
		state.election = {}
		return [EventsScript.make("election_failed", {"reason": "nobody is able to stand"})]
	var best: int = -1
	for id in candidates:
		best = maxi(best, tally[id])
	var leaders: Array = candidates.filter(func(id): return tally[id] == best)
	leaders.sort()
	if leaders.size() == 1:
		return _elect(state, leaders[0], "vote", {"tally": tally, "votes": revealed})

	var events: Array = []
	if state.election["runoff"] < GameDataScript.get_int("electionRunoffs"):
		events.append(EventsScript.make("election_tied", {"tied": leaders.duplicate(), "tally": tally, "votes": revealed}))
		state.election["runoff"] += 1
		events.append_array(_start_voting(state, state.election["voters"], leaders))
		return events
	events.append(EventsScript.make("election_tied", {"tied": leaders.duplicate(), "tally": tally, "votes": revealed}))
	events.append_array(_elect(state, RngScript.pick(state, leaders), "lot", {"tally": tally, "votes": revealed}))
	return events


static func _elect(state: GameStateScript, winner: int, how: String, detail: Dictionary) -> Array:
	var data: Dictionary = detail.duplicate()
	data["winner"] = winner
	data["how"] = how
	var events: Array = [EventsScript.make("leader_elected", data)]
	events.append_array(install_leader(state, winner, how))
	return events


# --- who may take part ---------------------------------------------------------------------

static func _is_active(state: GameStateScript, id: int) -> bool:
	return id in state.player_ids and not state.eliminated.get(id, false)


# Sick players can't write exams, vote or be voted for (Article 21).
static func _can_vote(state: GameStateScript, id: int) -> bool:
	return _is_active(state, id) and not state.sick.get(id, false)


# A CANCELLED player can't hold a role, and being Leader is one.
static func _can_stand(state: GameStateScript, id: int) -> bool:
	return _can_vote(state, id) and PopularityScript.effective(state, id) > GameDataScript.get_int("cancelledAt")


static func _can_use_pledges(state: GameStateScript, id: int) -> bool:
	return _can_stand(state, id)


static func _eligible_voters(state: GameStateScript) -> Array:
	return state.player_ids.filter(func(id): return _can_vote(state, id))


static func _eligible_candidates(state: GameStateScript, voters: Array) -> Array:
	return voters.filter(func(id): return _can_stand(state, id))


static func _reject(player_id: int, reason: String) -> Dictionary:
	return EventsScript.make("rejected", {"reason": reason}, [player_id])
