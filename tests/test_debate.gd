extends SceneTree

const GameScript = preload("res://scripts/game.gd")
const GameStateScript = preload("res://scripts/game_state.gd")
const CardsScript = preload("res://scripts/cards.gd")
const RivalsScript = preload("res://scripts/rivals.gd")
const LoyalistsScript = preload("res://scripts/loyalists.gd")
const PopularityScript = preload("res://scripts/popularity.gd")
const SerializerScript = preload("res://scripts/serializer.gd")
const ViewsScript = preload("res://scripts/views.gd")
const PlayScript = preload("res://tests/play.gd")

const PRESIDENT = GameStateScript.LeaderType.PRESIDENT
const SWING := 6

var failures: int = 0


func _init() -> void:
	the_cards()
	challenging()
	speaking()
	voting()
	the_result()
	slow_performers()
	loyalists_and_views()
	print("%d failure(s)" % failures)
	quit(1 if failures > 0 else 0)


func the_cards() -> void:
	for prefix in ["Debate a rival", "Choose a rival — publicly challenge"]:
		expect("'%s' is a debate card" % prefix, CardsScript.effects("performance", card_number(prefix)), {"debate": true})
	var s := debating()
	expect("the performance starts as a debate with nobody challenged yet", s.term["act"]["debate"], {"rival": 0, "topic": "", "side": -1})
	expect("an ordinary card has no debate", plain_turn().term["act"].has("debate"), false)


func challenging() -> void:
	var s := debating()
	expect("the performer can't just finish a debate", send(s, 3, {"type": "finish_performance"})[0]["reason"], "This is a debate: challenge a rival (debate_challenge) and debate.")
	expect("nobody can vote yet", send(s, 4, {"type": "debate_vote", "winner": 3})[0]["reason"], "It isn't time to vote on a debate.")
	expect("... nor finish a debate that hasn't started", send(s, 3, {"type": "debate_finish"})[0]["reason"], "Nobody is debating.")
	expect("only the performer challenges", send(s, 4, {"type": "debate_challenge", "rival": 5})[0]["reason"], "Only the performer challenges.")
	for bad in [null, "4", 3, 9, true]:
		expect("rival %s is refused" % str(bad), send(s, 3, {"type": "debate_challenge", "rival": bad})[0]["type"], "rejected")
	expect("a topic must be text", send(s, 3, {"type": "debate_challenge", "rival": 4, "topic": 5})[0]["type"], "rejected")
	expect("... and not too long", send(s, 3, {"type": "debate_challenge", "rival": 4, "topic": "x".repeat(141)})[0]["type"], "rejected")
	var ev := send(s, 3, {"type": "debate_challenge", "rival": 4, "topic": "  Should jollof be banned?  "})
	expect("a challenge starts the debate, naming the topic, and makes the challenged player a rival", [types(ev), ev[1]["topic"], ev[1]["speaker"], ev[1]["seconds"], RivalsScript.of(s, 3)], [["rival_named", "debate_started"], "Should jollof be banned?", 3, 30, [4]])
	expect("... only once", send(s, 3, {"type": "debate_challenge", "rival": 5})[0]["reason"], "You have already challenged someone.")

	# With rivals the challenge must be to one of them.
	s = debating()
	RivalsScript.name_rival(s, 3, 5)
	expect("a performer with a rival must challenge a rival", send(s, 3, {"type": "debate_challenge", "rival": 4})[0]["reason"], "Choose one of your rivals.")
	expect("... the rival", types(send(s, 3, {"type": "debate_challenge", "rival": 5})), ["debate_started"])


func speaking() -> void:
	var s := challenged(4)
	expect("the performer speaks first; the rival can't speak yet", send(s, 4, {"type": "debate_finish"})[0]["reason"], "It isn't your turn to speak.")
	expect("... nobody else can end their side", send(s, 5, {"type": "debate_finish"})[0]["reason"], "It isn't your turn to speak.")
	var ev := send(s, 3, {"type": "debate_finish"})
	expect("the performer ends their side and the rival speaks for 30 seconds", [types(ev), ev[0]["speaker"], ev[0]["seconds"], s.term["act"]["debate"]["side"]], [["debate_turn"], 4, 30, 1])
	expect("... now the performer can't", send(s, 3, {"type": "debate_finish"})[0]["reason"], "It isn't your turn to speak.")
	ev = send(s, 4, {"type": "debate_finish"})
	expect("the rival ends theirs and the table votes, the two debaters excluded", [types(ev), ev[0]["voters"], s.term["act"]["phase"]], [["performance_voting_opened"], [1, 2, 5], GameStateScript.ActPhase.VOTING])

	# The clock.
	s = challenged(4)
	var clock := GameScript.tick(s, int(s.term["act"]["deadline"]))
	expect("30 seconds and the performer's side is over", [types(clock), s.term["act"]["debate"]["side"]], [["debate_turn"], 1])
	clock = GameScript.tick(s, int(s.term["act"]["deadline"]))
	expect("30 more and the voting opens", [types(clock), s.term["act"]["phase"]], [["performance_voting_opened"], GameStateScript.ActPhase.VOTING])


func voting() -> void:
	var s := voting_s(4)
	expect("the performer and the rival can't vote", [send(s, 3, {"type": "debate_vote", "winner": 3})[0]["reason"], send(s, 4, {"type": "debate_vote", "winner": 3})[0]["reason"]], ["You can't vote on this debate.", "You can't vote on this debate."])
	expect("an ordinary Good/Bad vote isn't possible", send(s, 5, {"type": "performance_vote", "good": true})[0]["reason"], "This is a debate: vote for the winner (debate_vote).")
	for bad in [null, "3", 5, 9, true]:
		expect("winner %s is refused" % str(bad), send(s, 5, {"type": "debate_vote", "winner": bad})[0]["reason"], "Vote for the performer or for the rival.")
	var ev := send(s, 5, {"type": "debate_vote", "winner": 4})
	expect("a vote is cast, and the event says that, never for whom", [types(ev), ev[0].has("winner")], [["debate_vote_cast"], false])
	expect("... once", send(s, 5, {"type": "debate_vote", "winner": 3})[0]["reason"], "You have already voted.")
	expect("... and not before the voting opens", send(challenged(4), 5, {"type": "debate_vote", "winner": 3})[0]["reason"], "It isn't time to vote on a debate.")


func the_result() -> void:
	# The performer wins 2 to 1.
	var s := voting_s(4)
	s.decks["settlement"] = [5]
	var pop3: int = PopularityScript.base(s, 3)
	var pop4: int = PopularityScript.base(s, 4)
	send(s, 1, {"type": "debate_vote", "winner": 3})
	send(s, 2, {"type": "debate_vote", "winner": 3})
	var ev := send(s, 5, {"type": "debate_vote", "winner": 4})
	var done: Dictionary = last_of(s, "performance_resolved")
	expect("the table's winner gets the swing and the loser loses it", [PopularityScript.base(s, 3) - pop3, PopularityScript.base(s, 4) - pop4], [SWING, -SWING])
	expect("... the performer won, so draws a Settlement card; the rival none", [done["outcome"], done["deck"], done["debate_rival"], done["rival_popularity_delta"], done["good"], done["bad"]], ["good", "settlement", 4, -SWING, 2, 1])
	expect("... and the turn is done", s.term["act"]["phase"], GameStateScript.ActPhase.DONE)
	expect("the votes are revealed in the result, as winners' ids", done["votes"], {1: 3, 2: 3, 5: 4})

	# The rival wins.
	s = voting_s(4)
	s.decks["scandal"] = [5]
	pop3 = PopularityScript.base(s, 3)
	pop4 = PopularityScript.base(s, 4)
	for id in [1, 2, 5]:
		send(s, id, {"type": "debate_vote", "winner": 4})
	done = last_of(s, "performance_resolved")
	expect("if the rival wins the performer loses popularity and draws a Scandal card", [PopularityScript.base(s, 3) - pop3, PopularityScript.base(s, 4) - pop4, done["outcome"], done["deck"]], [-SWING, SWING, "bad", "scandal"])

	# A tie: nothing.
	s = voting_s(4)
	send(s, 1, {"type": "debate_vote", "winner": 3})
	send(s, 2, {"type": "debate_vote", "winner": 4})
	GameScript.tick(s, int(s.term["act"]["deadline"]))
	done = last_of(s, "performance_resolved")
	expect("a tie moves nobody and draws nothing", [done["outcome"], done.has("card"), done["rival_popularity_delta"]], ["tie", false, 0])

	# Nobody votes.
	s = voting_s(4)
	GameScript.tick(s, int(s.term["act"]["deadline"]))
	expect("a debate nobody votes on is a tie", last_of(s, "performance_resolved")["outcome"], "tie")

	# The performer's turn can end after it.
	expect("the turn ends afterwards as usual", types(send(s, 3, {"type": "end_turn"}))[0], "turn_ended")


func slow_performers() -> void:
	var s := debating()
	GameScript.tick(s, int(s.term["act"]["deadline"]))
	expect("a performer who doesn't challenge in time is given a rival at random", [s.term["act"]["debate"]["rival"] != 0, s.term["act"]["debate"]["side"], last_of(s, "debate_started")["topic"]], [true, 0, ""])
	var seen := {}
	for seed_value in 16:
		var g := debating()
		g.rng_state = seed_value * 7919 + 9
		GameScript.tick(g, int(g.term["act"]["deadline"]))
		seen[g.term["act"]["debate"]["rival"]] = true
	expect("... who it is varies", seen.keys().size() > 1, true)
	s = debating()
	RivalsScript.name_rival(s, 3, 5)
	GameScript.tick(s, int(s.term["act"]["deadline"]))
	expect("... but it is one of their rivals if they have any", s.term["act"]["debate"]["rival"], 5)


func loyalists_and_views() -> void:
	var s := voting_s(4)
	LoyalistsScript.appoint(s, 1, 2, 3)
	expect("a Loyalist waits for their owner in a debate vote", send(s, 2, {"type": "debate_vote", "winner": 3})[0]["reason"], "You vote with the player you are loyal to, once they have voted.")
	var ev := send(s, 1, {"type": "debate_vote", "winner": 4})
	expect("... and votes with them", [types(ev), s.term["act"]["votes"]], [["debate_vote_cast", "debate_vote_cast"], {1: 4, 2: 4}])
	s = voting_s(4)
	LoyalistsScript.appoint(s, 4, 2, 3)   # follows the rival, who can't vote
	expect("a Loyalist of the rival is free: the rival is not a voter", types(send(s, 2, {"type": "debate_vote", "winner": 3})), ["debate_vote_cast"])

	s = voting_s(4)
	send(s, 1, {"type": "debate_vote", "winner": 4})
	var seen: Dictionary = ViewsScript.state_view(s, 5)
	expect("others see that 1 voted but not for whom; the debate itself is public", [seen["term"]["act"]["voted"], seen["term"]["act"].has("votes"), seen["term"]["act"]["debate"]["rival"]], [[1], false, 4])
	var errors: Array = []
	var restored: GameStateScript = SerializerScript.state_from_json(SerializerScript.state_to_json(s), errors)
	expect("a saved game mid-debate carries on", [errors, restored.term["act"]["debate"], restored.term["act"]["votes"]], [[], s.term["act"]["debate"], {1: 4}])


# --- helpers -----------------------------------------------------------------------------

# Player 3's turn has begun with a debate card.
func debating() -> GameStateScript:
	var s := new_turn()
	s.decks["performance"] = [card_number("Debate a rival")]
	PlayScript.take_turn(s, 2)
	return s


func plain_turn() -> GameStateScript:
	var s := new_turn()
	s.decks["performance"] = [card_number("A rival union wants your backing")]
	PlayScript.take_turn(s, 2)
	return s


func challenged(rival: int) -> GameStateScript:
	var s := debating()
	send(s, 3, {"type": "debate_challenge", "rival": rival, "topic": "jollof"})
	return s


func voting_s(rival: int) -> GameStateScript:
	var s := challenged(rival)
	send(s, 3, {"type": "debate_finish"})
	send(s, rival, {"type": "debate_finish"})
	return s


func card_number(prefix: String) -> int:
	for i in CardsScript.count("performance"):
		if CardsScript.text("performance", i).begins_with(prefix):
			return i
	return -1


func new_turn() -> GameStateScript:
	for seed_value in range(1, 400):
		var s := GameScript.new_game([1, 2, 3, 4, 5], seed_value)
		for id in [1, 2, 3, 4, 5]:
			GameScript.handle(s, id, {"type": "cast_vote", "candidate": 2})
		if s.leader_type == PRESIDENT:
			GameScript.handle(s, 2, {"type": "pass_window"})
			return s
	assert(false, "no seed gave a President")
	return null


func last_of(s: GameStateScript, type: String) -> Dictionary:
	for i in range(s.event_log.size() - 1, -1, -1):
		if s.event_log[i]["type"] == type:
			return s.event_log[i]
	return {}


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
