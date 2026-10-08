extends SceneTree

const GameScript = preload("res://scripts/game.gd")
const LawScript = preload("res://scripts/law.gd")
const TermLoopScript = preload("res://scripts/term_loop.gd")
const ElimScript = preload("res://scripts/elimination.gd")
const DebtScript = preload("res://scripts/debt.gd")
const RngScript = preload("res://scripts/rng.gd")
const GameStateScript = preload("res://scripts/game_state.gd")
const ConstitutionScript = preload("res://scripts/constitution.gd")

const PRESIDENT = GameStateScript.LeaderType.PRESIDENT
const COMMANDER = GameStateScript.LeaderType.COMMANDER
const INAUGURATION = GameStateScript.TermPhase.INAUGURATION
const TURNS = GameStateScript.TermPhase.TURNS
const FAREWELL = GameStateScript.TermPhase.FAREWELL
const INAUG = GameStateScript.AmendWindow.INAUGURATION
const MID = GameStateScript.AmendWindow.MID_TERM
const FAREW = GameStateScript.AmendWindow.FAREWELL
const SERVER := 0
const TREASURY := 0

var failures: int = 0


func _init() -> void:
	a_term_from_start_to_finish()
	the_inauguration_comes_before_the_levy()
	the_levy()
	a_leader_who_cannot_amend()
	the_order_of_turns()
	when_players_leave_mid_term()
	when_the_leader_leaves()
	stopping_the_game()
	commands_out_of_turn()
	every_event_is_logged_once()
	print("%d failure(s)" % failures)
	quit(1 if failures > 0 else 0)


func a_term_from_start_to_finish() -> void:
	var s := new_term(PRESIDENT)
	expect("player 2 won the first election", s.leader_id, 2)
	expect("the new term opens with the Inauguration", s.term["phase"], INAUGURATION)
	expect("the money is all there: treasury 7550 + 5 x 1000", total_money(s), 12550)

	expect("only the Leader can pass the Inauguration", send(s, 3, {"type": "pass_window"})[0]["reason"], "Only the Leader decides whether to amend.")
	expect("nobody can end a turn yet", send(s, 2, {"type": "end_turn"})[0]["reason"], "'end_turn' isn't possible at this stage.")

	var ev := send(s, 2, {"type": "pass_window"})
	expect("passing the Inauguration collects the levy and starts the first turn", types(ev), ["window_passed", "levy_collected", "turn_started"])
	expect("the first Leader takes the first turn of the first term", ev[2]["player"], 2)
	expect("the levy is 25 from everyone", [ev[1]["levy"], s.psd[1], s.psd[2], s.psd[5]], [25, 975, 975, 975])
	expect("... it goes to the treasury", s.treasury, 7550 + 125)
	expect("... and no money was made or lost", total_money(s), 12550)
	expect("everyone had enough, so nobody owes", ev[1]["unpaid"], {})
	expect("turn order: round the table from the Leader", [s.term["waiting"], s.term["played"]], [[2, 3, 4, 5, 1], []])
	expect("the Inauguration window is gone", s.windows_used[INAUG], true)

	expect("player 3 can't end player 2's turn", send(s, 3, {"type": "end_turn"})[0]["reason"], "It isn't your turn.")
	var first := send(s, 2, {"type": "end_turn"})
	expect("a turn ends and the next starts", types(first), ["turn_ended", "turn_started"])
	expect("... player 3 is next", first[1]["player"], 3)
	expect("turns played is counted", s.turns_played, 1)
	send(s, 3, {"type": "end_turn"})
	expect("2 of 5 played: the Mid-term window is still closed", Dictionary(send(s, 2, propose(s, 2, MID, "30%"))[0])["reason"], "This amendment window isn't open yet.")

	send(s, 4, {"type": "end_turn"})
	expect("3 of 5 played (half, rounded up): the Mid-term window is open", types(send(s, 2, propose(s, 2, MID, "30%"))), ["amendment_proposed"])
	expect("... and the turns carry on while it is voted on", types(send(s, 5, {"type": "end_turn"})), ["turn_ended", "turn_started"])
	send(s, SERVER, {"type": "rule_grammar", "ok": true})
	for id in [1, 3, 4, 5]:
		send(s, id, {"type": "vote", "keep": true})
	expect("the Mid-term amendment stood", ConstitutionScript.to_text(s.articles[2]), "Tax: 30% of income goes to the treasury every round.")

	expect("the Farewell window isn't open before the last turn", types(send(s, 2, propose(s, 2, FAREW, "35%"))), ["rejected"])
	var last := send(s, 1, {"type": "end_turn"})
	expect("the last turn opens the Farewell", types(last), ["turn_ended", "farewell_opened"])
	expect("... the term is in its Farewell phase", s.term["phase"], FAREWELL)
	expect("... everyone has played", [s.turns_played, s.player_count], [5, 5])

	var ended := send(s, 2, {"type": "pass_window"})
	expect("passing the Farewell ends the term and starts the next election", types(ended), ["window_passed", "term_ended", "election_started"])
	expect("... the Leader is credited a full term (2 half-rounds)", s.half_rounds[2], 2)
	expect("... the election starts with an exam", [ended[2]["reason"], ended[2]["exam"]], ["term_ended", true])
	expect("... and no term is running", s.term.is_empty(), true)
	expect("nobody can amend between terms", types(send(s, 2, propose(s, 2, FAREW, "35%"))), ["rejected"])

	# The Farewell window can also be used.
	s = new_term(PRESIDENT)
	send(s, 2, {"type": "pass_window"})
	for id in [2, 3, 4, 5, 1]:
		send(s, id, {"type": "end_turn"})
	expect("in the Farewell the Leader may amend", types(send(s, 2, propose(s, 2, FAREW, "35%"))), ["amendment_proposed"])
	expect("... and the term waits for that amendment", s.term["phase"], FAREWELL)
	send(s, SERVER, {"type": "rule_grammar", "ok": true})
	for id in [1, 3, 4]:
		send(s, id, {"type": "vote", "keep": true})
	var done := send(s, 5, {"type": "vote", "keep": true})
	expect("once it is decided the term ends by itself", types(done), ["vote_cast", "amendment_resolved", "article_changed", "term_ended", "election_started"])


func the_inauguration_comes_before_the_levy() -> void:
	# The Leader sets the levy to 40 at the Inauguration, so 40 is what is collected.
	var s := new_term(PRESIDENT)
	expect("the levy is 25 to begin with", LawScript.get_int(s, "levy"), 25)
	send(s, 2, propose(s, 3, INAUG, "40"))
	send(s, SERVER, {"type": "rule_grammar", "ok": true})
	for id in [1, 3, 4]:
		send(s, id, {"type": "vote", "keep": true})
	expect("the levy isn't collected while the amendment is being voted on", s.term["phase"], INAUGURATION)
	var ev := send(s, 5, {"type": "vote", "keep": true})
	expect("when it stands the levy follows, at the new rate", types(ev), ["vote_cast", "amendment_resolved", "article_changed", "levy_collected", "turn_started"])
	expect("... 40 from everyone", [ev[3]["levy"], s.psd[1], s.psd[2]], [40, 960, 960])
	expect("... the treasury has 5 x 40 more", s.treasury, 7550 + 200)

	# A failed amendment uses the window too, so the term moves on.
	s = new_term(PRESIDENT)
	var words: Array = s.articles[3]
	var texts: Array = []
	for word in words:
		texts.append(word["text"])
	texts[0] = "Everybody"   # changes a word that is not fixed? it is highlighted: use a fixed word instead
	texts[texts.size() - 1] = "changed"   # the last word is fixed text: a failed check
	var failed := send(s, 2, {"type": "propose", "window": INAUG, "article_id": 3, "new_texts": texts})
	expect("a failed Inauguration amendment still uses the window", types(failed), ["amendment_proposed", "amendment_failed", "levy_collected", "turn_started"])
	expect("... and the levy at the old rate is collected", [failed[2]["levy"], s.term["phase"]], [25, TURNS])

	# The Inauguration amendment can't be made later.
	s = new_term(PRESIDENT)
	send(s, 2, {"type": "pass_window"})
	expect("the Inauguration window is closed once passed", types(send(s, 2, propose(s, 2, INAUG, "30%"))), ["rejected"])
	s = new_term(PRESIDENT)
	expect("the Mid-term window can't be used at the Inauguration", send(s, 2, propose(s, 2, MID, "30%"))[0]["reason"], "The Mid-term amendment can't be made at the Inauguration.")


func the_levy() -> void:
	# A player who can't pay the whole levy pays what they have and owes the rest.
	var s := new_term(PRESIDENT)
	s.psd[4] = 10
	s.treasury += 990   # keep the books balanced
	var ev := send(s, 2, {"type": "pass_window"})
	expect("the levy is paid in part", [s.psd[4], DebtScript.total_debt(s, 4)], [0, 15])
	expect("... and the event says who couldn't pay", ev[1]["unpaid"], {4: 15})
	expect("... the treasury got what they had", s.treasury, 7550 + 990 + 4 * 25 + 10)
	expect("money is conserved", total_money(s), 12550)

	# Eliminated players don't pay.
	s = bare_term_state()
	s.eliminated[5] = true
	s.psd[5] = 0
	var ev2 := TermLoopScript.handle(s, 2, {"type": "pass_window"})
	TermLoopScript.settle(s)
	expect("the eliminated are not charged", s.psd[5], 0)
	expect("... but everyone else is", s.psd[1], 975)


func a_leader_who_cannot_amend() -> void:
	# A Commander can't amend, so the Inauguration is skipped and the term goes straight on.
	var s := new_term(COMMANDER)
	expect("a Commander's Inauguration is skipped, the levy collected and the turns begin", s.term["phase"], TURNS)
	expect("... the first Leader (a Commander) still goes first", s.term["waiting"][0], 2)
	expect("... the levy was collected", s.psd[1], 975)
	expect("... and the Inauguration window was never used", s.windows_used[INAUG], false)

	# A sick Leader likewise, and so is the Farewell.
	s = bare_term_state()
	s.sick[2] = true
	var ev := GameScript.tick(s)
	expect("a sick Leader's Inauguration is skipped", types(ev), ["levy_collected", "turn_started"])
	for id in [1, 2, 3, 4, 5]:
		TermLoopScript.handle(s, id, {"type": "end_turn"})
	var end := TermLoopScript.settle(s)
	expect("... and so is their Farewell: the term ends at once", types(end), ["farewell_opened", "term_ended", "election_started", "vote_started"])
	expect("... and the election has no exam, since a sick Leader can't write one", end[2]["exam"], false)

	# A CANCELLED Leader too.
	s = bare_term_state()
	s.popularity[2] = -50
	expect("a CANCELLED Leader's Inauguration is skipped", types(GameScript.tick(s)), ["levy_collected", "turn_started"])


func the_order_of_turns() -> void:
	# With nobody having played and no coup, the order falls back to the first seat.
	var s := bare_term_state()
	s.leader_id = 4
	start_turns(s)
	expect("no earlier turn and no flag: the first seat", s.term["waiting"], [1, 2, 3, 4, 5])

	# Later terms carry on round the table from the player who took the last turn.
	s = bare_term_state()
	s.last_turn_player = 3
	start_turns(s)
	expect("the next term starts with the player after the last one to play", s.term["waiting"], [4, 5, 1, 2, 3])

	s = bare_term_state()
	s.last_turn_player = 5
	start_turns(s)
	expect("after a full lap the same player starts again", s.term["waiting"], [1, 2, 3, 4, 5])

	# An interrupted term carries on from wherever it stopped.
	s = bare_term_state()
	s.last_turn_player = 2
	start_turns(s)
	expect("a term cut short carries on from the last turn that was played", s.term["waiting"], [3, 4, 5, 1, 2])

	# The player who took the last turn may since have been eliminated: the seat still counts.
	s = bare_term_state()
	s.last_turn_player = 3
	s.eliminated[3] = true
	start_turns(s)
	expect("an eliminated last player is skipped, and the next seat starts", s.term["waiting"], [4, 5, 1, 2])
	s = bare_term_state()
	s.last_turn_player = 2
	s.eliminated[3] = true
	s.eliminated[4] = true
	start_turns(s)
	expect("eliminated players are skipped wherever they sit", s.term["waiting"], [5, 1, 2])

	# After a coup the new Leader goes first, and play continues from them.
	s = bare_term_state()
	s.leader_id = 4
	s.last_turn_player = 2
	s.leader_goes_first = true
	start_turns(s)
	expect("after a coup the new Leader takes the first turn", s.term["waiting"], [4, 5, 1, 2, 3])
	expect("... for that term only", s.leader_goes_first, false)

	# Every turn that ends is remembered, so the next term knows where to carry on.
	s = bare_term_state()
	s.term = {"phase": TURNS, "played": [], "waiting": [3, 4, 5, 1, 2], "announced": 3}
	TermLoopScript.handle(s, 3, {"type": "end_turn"})
	expect("the last turn taken is remembered", s.last_turn_player, 3)
	TermLoopScript.handle(s, 4, {"type": "end_turn"})
	expect("... and moves on with each turn", s.last_turn_player, 4)

	# A whole second term, played through: it starts where the first one stopped.
	s = new_term(PRESIDENT)
	for lap in 2:
		var order: Array = []
		TermLoopScript.handle(s, s.leader_id, {"type": "pass_window"})
		TermLoopScript.settle(s)
		order = s.term["waiting"].duplicate()
		for id in order:
			send(s, id, {"type": "end_turn"})
		if lap == 0:
			expect("the first term ran from the Leader: 2, 3, 4, 5, 1", order, [2, 3, 4, 5, 1])
			send(s, s.leader_id, {"type": "pass_window"})
			skip_election(s)
		else:
			expect("the second term started after the last player: the same lap", order, [2, 3, 4, 5, 1])

	s = bare_term_state()
	start_turns(s)
	expect("the turn is announced once", types(GameScript.tick(s)), [])


func when_players_leave_mid_term() -> void:
	# A player in debt for the third turn is eliminated at the end of their own turn.
	var s := bare_term_state()
	s.term = {"phase": TURNS, "played": [], "waiting": [3, 4, 5, 1, 2], "announced": -1}
	s.psd[3] = 0
	DebtScript.charge(s, 3, TREASURY, 25)
	s.debt_terms[3] = 2
	s.treasury = 7550   # the books were balanced by hand above; see total_money below
	GameScript.tick(s)
	var ev := send(s, 3, {"type": "end_turn"})
	expect("the third turn in debt ends in elimination", types(ev).has("player_eliminated"), true)
	expect("... and the next player's turn starts", ev[ev.size() - 1], {"type": "turn_started", "audience": [], "player": 4})
	expect("the dead player is out of the order", [s.term["played"], s.term["waiting"]], [[], [4, 5, 1, 2]])
	expect("... and the table now has 4 players", [s.turns_played, s.player_count], [0, 4])

	# Someone who has not yet played is eliminated by other means.
	s = bare_term_state()
	s.term = {"phase": TURNS, "played": [2], "waiting": [3, 4, 5, 1], "announced": 3}
	s.turns_played = 1
	ElimScript.eliminate(s, 5, "test")
	expect("an eliminated player leaves the waiting list", s.term["waiting"], [3, 4, 1])
	expect("... and the counts follow", [s.turns_played, s.player_count], [1, 4])
	# Someone who HAS played.
	s = bare_term_state()
	s.term = {"phase": TURNS, "played": [3], "waiting": [4, 5, 1, 2], "announced": 4}
	s.turns_played = 1
	ElimScript.eliminate(s, 3, "test")
	expect("an eliminated player who had played stops counting as having played", [s.term["played"], s.turns_played, s.player_count], [[], 0, 4])

	# Everyone left has played: the term moves to the Farewell by itself.
	s = bare_term_state()
	s.term = {"phase": TURNS, "played": [2, 3, 4], "waiting": [5], "announced": 5}
	s.turns_played = 3
	ElimScript.eliminate(s, 5, "test")
	expect("when the last waiting player is eliminated the Farewell opens", types(GameScript.tick(s)), ["farewell_opened"])


func when_the_leader_leaves() -> void:
	var s := bare_term_state()
	s.term = {"phase": TURNS, "played": [2], "waiting": [3, 4, 5, 1], "announced": 3}
	ElimScript.eliminate(s, 2, "test")
	expect("the Leader's elimination ends the term", s.term.is_empty(), true)
	expect("... and starts a vacancy election", [s.election["reason"], s.leader_id], ["vacancy", -1])
	expect("... no new term starts until a Leader is chosen", GameScript.tick(s), [])
	for id in [3, 4, 5]:
		GameScript.handle(s, id, {"type": "cast_vote", "candidate": 4})
	var last := GameScript.handle(s, 1, {"type": "cast_vote", "candidate": 4})
	expect("the vote installs a Leader and the next term starts by itself", [types(last).has("leader_installed"), types(last).has("term_started")], [true, true])
	expect("... player 4 leads, in round 2", [s.leader_id, s.current_round], [4, 2])
	expect("... and the term is at its Inauguration or beyond", s.term.has("phase"), true)


func stopping_the_game() -> void:
	var s := new_term(PRESIDENT)
	expect("only the server can stop the game", send(s, 2, {"type": "finish_game"})[0]["reason"], "Only the server can end the game.")
	var ev := send(s, SERVER, {"type": "finish_game"})
	expect("stopping mid-term counts the running term as a full round", s.half_rounds[2], 2)
	expect("... the winner is announced", [types(ev), ev[0]["winners"]], [["game_over"], [2]])
	expect("... and the game is over", s.game_over, true)
	expect("nothing more can be done", send(s, 2, {"type": "pass_window"})[0]["reason"], "The game is over.")
	expect("... and the loop stands still", GameScript.tick(s), [])

	# Stopping during an election adds nothing: the term was credited when it ended.
	s = bare_term_state()
	s.term = {"phase": TURNS, "played": [], "waiting": [1, 2, 3, 4, 5], "announced": 1}
	for id in [1, 2, 3, 4, 5]:
		TermLoopScript.handle(s, id, {"type": "end_turn"})
	TermLoopScript.settle(s)
	TermLoopScript.handle(s, 2, {"type": "pass_window"})
	TermLoopScript.settle(s)
	expect("the term has ended and the Leader was credited once", s.half_rounds[2], 2)
	send(s, SERVER, {"type": "finish_game"})
	expect("stopping during an election adds nothing more", s.half_rounds[2], 2)

	# Before anyone is Leader.
	s = GameScript.new_game([1, 2, 3], 5)
	expect("the game can be stopped before a Leader exists", types(send(s, SERVER, {"type": "finish_game"})), ["game_over"])
	expect("... nobody has led, so everyone shares the win", s.event_log.back()["winners"], [1, 2, 3])


func commands_out_of_turn() -> void:
	var s := new_term(PRESIDENT)
	expect("an unknown command is refused", send(s, 2, {"type": "bribe"})[0]["reason"], "Unknown command 'bribe'.")
	expect("a command with no type is refused", types(send(s, 2, {})), ["rejected"])
	expect("an election command during a term is refused", types(send(s, 2, {"type": "cast_vote", "candidate": 3})), ["rejected"])

	s = GameScript.new_game([1, 2, 3, 4, 5], 9)
	expect("no amendments during an election", send(s, 1, propose(s, 2, INAUG, "30%"))[0]["reason"], "The Constitution can only be amended during a term.")
	expect("no turns during an election", types(send(s, 1, {"type": "end_turn"})), ["rejected"])
	expect("... and a rejected command changes nothing", s.event_log.size(), 2)


func every_event_is_logged_once() -> void:
	# Play a whole term, with an elimination in the middle, and compare what the commands
	# returned with what ended up in the log: the same events, once each, in the same order.
	var s := new_term(PRESIDENT)
	var start: int = s.event_log.size()
	var returned: Array = []
	s.psd[3] = 0
	s.treasury += 975
	s.wills[3] = {"psd_heir": 4, "on_hold": false}
	DebtScript.charge(s, 3, TREASURY, 25)
	s.debt_terms[3] = 2
	returned.append_array(send(s, 2, {"type": "pass_window"}))
	for id in [2, 3, 4, 5, 1]:
		if not s.eliminated.get(id, false):
			returned.append_array(send(s, id, {"type": "end_turn"}))
	returned.append_array(send(s, 2, {"type": "pass_window"}))
	expect("a whole term, with an elimination, returned events", returned.size() > 12, true)
	expect("the log holds exactly those events, in order", types(s.event_log.slice(start)), types(returned))
	expect("... including the elimination", types(returned).has("player_eliminated"), true)
	expect("... and the Nepo Baby", types(returned).has("nepo_baby"), true)


# --- helpers ---------------------------------------------------------------------------

# A real game, five players, the first election won by player 2 (everyone votes for them),
# retried with other seeds until the role card drawn is the one wanted.
func new_term(leader_type: int) -> GameStateScript:
	for seed_value in range(1, 400):
		var s := GameScript.new_game([1, 2, 3, 4, 5], seed_value)
		for id in [1, 2, 3, 4, 5]:
			GameScript.handle(s, id, {"type": "cast_vote", "candidate": 2})
		if s.leader_type == leader_type:
			return s
	assert(false, "no seed gave that role card")
	return null


# Five players, 1000 each, player 2 the President, a term waiting at its Inauguration.
func bare_term_state() -> GameStateScript:
	var s: GameStateScript = GameStateScript.new()
	s.player_ids = [1, 2, 3, 4, 5]
	s.player_count = 5
	s.leader_id = 2
	s.leader_type = PRESIDENT
	for id in s.player_ids:
		s.psd[id] = 1000
		s.popularity[id] = 0
		s.sick[id] = false
	s.treasury = 7550
	s.articles = ConstitutionScript.initial_articles()
	RngScript.seed_with(s, 321)
	s.term = {"phase": INAUGURATION}
	return s


# Pass the Inauguration so the levy is collected and the turn order is set.
func start_turns(s: GameStateScript) -> void:
	GameScript.tick(s)
	TermLoopScript.handle(s, s.leader_id, {"type": "pass_window"})
	GameScript.tick(s)


# Get through an election as fast as possible: the server skips any exam and everyone votes for
# the first candidate.
func skip_election(s: GameStateScript) -> void:
	if s.election.get("phase", 0) == GameStateScript.ElectionPhase.EXAM_WRITING:
		send(s, SERVER, {"type": "skip_exam"})
	var voters: Array = s.election["voters"].duplicate()
	var candidate: int = s.election["candidates"][0]
	for id in voters:
		send(s, id, {"type": "cast_vote", "candidate": candidate})


# Rewrite one highlighted word of an article. `slot` counts highlighted words from 0.
func propose(s: GameStateScript, article_id: int, window: int, text: String) -> Dictionary:
	return propose_slot(s, article_id, window, 0 if article_id == 2 else 3, text)


func propose_slot(s: GameStateScript, article_id: int, window: int, slot: int, text: String) -> Dictionary:
	var texts: Array = []
	var seen: int = 0
	for word in s.articles[article_id]:
		if word["amendable"]:
			texts.append(text if seen == slot else word["text"])
			seen += 1
		else:
			texts.append(word["text"])
	return {"type": "propose", "window": window, "article_id": article_id, "new_texts": texts}


func total_money(s: GameStateScript) -> int:
	var total: int = s.treasury
	for id in s.psd:
		total += s.psd[id]
	return total


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
