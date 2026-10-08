extends SceneTree

const GameScript = preload("res://scripts/game.gd")
const CardsScript = preload("res://scripts/cards.gd")
const GameStateScript = preload("res://scripts/game_state.gd")
const ViewsScript = preload("res://scripts/views.gd")
const SerializerScript = preload("res://scripts/serializer.gd")
const PopularityScript = preload("res://scripts/popularity.gd")
const PlayScript = preload("res://tests/play.gd")

const PRESIDENT = GameStateScript.LeaderType.PRESIDENT
const PERFORMING = GameStateScript.ActPhase.PERFORMING
const VOTING = GameStateScript.ActPhase.VOTING
const DONE = GameStateScript.ActPhase.DONE
const SWING := 6   # the swing for a table of 5

var failures: int = 0


func _init() -> void:
	the_decks()
	a_performance_starts()
	the_clock()
	finishing_early()
	who_may_vote()
	a_good_performance()
	a_bad_performance()
	ties_and_missing_votes()
	ending_the_turn()
	what_each_player_sees()
	saving_in_the_middle()
	print("%d failure(s)" % failures)
	quit(1 if failures > 0 else 0)


func the_decks() -> void:
	var s := GameScript.new_game([1, 2, 3], 5)
	expect("each deck has cards", [CardsScript.count("performance") > 0, CardsScript.count("settlement") > 0, CardsScript.count("scandal") > 0], [true, true, true])
	var seen: Dictionary = {}
	var n: int = CardsScript.count("performance")
	for i in n:
		seen[CardsScript.draw(s, "performance")] = true
	expect("a whole pass through a deck draws every card once", seen.size(), n)
	expect("... then the pile is empty", s.decks["performance"], [])
	var again: int = CardsScript.draw(s, "performance")
	expect("an empty pile is reshuffled from the whole deck", [again >= 0 and again < n, s.decks["performance"].size()], [true, n - 1])

	var a := GameScript.new_game([1, 2, 3], 9)
	var b := GameScript.new_game([1, 2, 3], 9)
	expect("the same seed deals the same cards", CardsScript.draw(a, "scandal"), CardsScript.draw(b, "scandal"))
	expect("a card has text", CardsScript.text("settlement", 0).length() > 10, true)


func a_performance_starts() -> void:
	var s := new_turn()
	var act: Dictionary = s.term["act"]
	expect("the Leader's turn starts with a performance", [act["phase"], act["player"]], [PERFORMING, 2])
	expect("... the player has 60 seconds on the server's clock", act["deadline"], s.clock_ms + 60000)
	var started: Dictionary = last_of(s, "performance_started")
	expect("... everyone is told the card and the time", [started["player"], started["text"], started["seconds"], started["audience"]], [2, CardsScript.text("performance", act["card"]), 60, []])
	expect("... and a card was drawn from the secret pile", s.decks["performance"].size(), CardsScript.count("performance") - 1)


func the_clock() -> void:
	var s := new_turn()
	var deadline: int = int(s.term["act"]["deadline"])
	expect("before the deadline nothing happens", [types(GameScript.tick(s, deadline - 1)), s.term["act"]["phase"]], [[], PERFORMING])
	var ev := GameScript.tick(s, deadline)
	expect("when the minute is up, voting opens by itself", [types(ev), s.term["act"]["phase"]], [["performance_voting_opened"], VOTING])
	expect("... for everyone but the performer", ev[0]["voters"], [1, 3, 4, 5])
	expect("... for 15 seconds", [ev[0]["seconds"], s.term["act"]["deadline"]], [15, deadline + 15000])
	var deadline2: int = int(s.term["act"]["deadline"])
	var ev2 := GameScript.tick(s, deadline2)
	expect("when the voting time is up with no votes, the result is a tie", [types(ev2), ev2[0]["outcome"]], [["performance_resolved"], "tie"])
	expect("... the performance is done", s.term["act"]["phase"], DONE)
	GameScript.tick(s, 1)
	expect("the clock never goes backwards", s.clock_ms, deadline2)
	expect("a tick with no time given leaves the clock alone", [types(GameScript.tick(s)), s.clock_ms], [[], deadline2])


func finishing_early() -> void:
	var s := new_turn()
	expect("only the performer can finish", send(s, 3, {"type": "finish_performance"})[0]["reason"], "Only the performer can finish the performance.")
	var ev := send(s, 2, {"type": "finish_performance"})
	expect("the performer finishing opens the voting at once", [types(ev), s.term["act"]["phase"]], [["performance_voting_opened"], VOTING])
	expect("... and can't finish twice", send(s, 2, {"type": "finish_performance"})[0]["reason"], "The performance is over.")


func who_may_vote() -> void:
	var s := new_turn()
	expect("no voting while the player is still performing", send(s, 3, vote(true))[0]["reason"], "It isn't time to vote.")
	send(s, 2, {"type": "finish_performance"})
	expect("the performer can't vote on their own performance", send(s, 2, vote(true))[0]["reason"], "You can't vote on this performance.")
	expect("a stranger can't vote", send(s, 9, vote(true))[0]["reason"], "You can't vote on this performance.")
	expect("the server can't vote", send(s, 0, vote(true))[0]["reason"], "You can't vote on this performance.")
	expect("a vote must be Good or Bad: a string is refused", send(s, 3, {"type": "performance_vote", "good": "yes"})[0]["reason"], "Vote Good or Bad.")
	expect("... a number is refused", send(s, 3, {"type": "performance_vote", "good": 1})[0]["reason"], "Vote Good or Bad.")
	expect("... a missing answer is refused", send(s, 3, {"type": "performance_vote"})[0]["reason"], "Vote Good or Bad.")
	var ev := send(s, 3, vote(true))
	expect("a vote is counted, and the event says THAT but not HOW", [types(ev), ev[0]], [["performance_vote_cast"], {"type": "performance_vote_cast", "audience": [], "voter": 3}])
	expect("you can't vote twice", send(s, 3, vote(false))[0]["reason"], "You have already voted.")
	expect("... and the first vote stands", s.term["act"]["votes"][3], true)

	s = new_turn()
	s.eliminated[5] = true
	send(s, 2, {"type": "finish_performance"})
	expect("an eliminated player can't vote", send(s, 5, vote(true))[0]["reason"], "You can't vote on this performance.")
	expect("... and isn't waited for: three votes decide it", [types(send(s, 1, vote(true))), types(send(s, 3, vote(true))), types(send(s, 4, vote(false)))], [["performance_vote_cast"], ["performance_vote_cast"], ["performance_vote_cast", "performance_resolved"]])


func a_good_performance() -> void:
	var s := new_turn()
	var before: int = PopularityScript.effective(s, 2)
	send(s, 2, {"type": "finish_performance"})
	send(s, 1, vote(true))
	send(s, 3, vote(true))
	send(s, 4, vote(true))
	var ev := send(s, 5, vote(false))
	var done: Dictionary = ev[1]
	expect("the last vote ends the voting at once, without waiting for the clock", [types(ev), s.term["act"]["phase"]], [["performance_vote_cast", "performance_resolved"], DONE])
	expect("3 Good against 1 Bad: a win is exactly +swing, not one swing per vote", [done["good"], done["bad"], done["popularity_delta"], PopularityScript.effective(s, 2) - before], [3, 1, SWING, SWING])
	expect("... a Settlement card is drawn", [done["outcome"], done["deck"], done["text"]], ["good", "settlement", CardsScript.text("settlement", done["card"])])
	expect("... and the votes are shown at last", done["votes"], {1: true, 3: true, 4: true, 5: false})
	expect("... from a secret pile that is now one card shorter", s.decks["settlement"].size(), CardsScript.count("settlement") - 1)


func a_bad_performance() -> void:
	var s := new_turn()
	var before: int = PopularityScript.effective(s, 2)
	send(s, 2, {"type": "finish_performance"})
	send(s, 1, vote(false))
	send(s, 3, vote(false))
	send(s, 4, vote(false))
	var done: Dictionary = send(s, 5, vote(true))[1]
	expect("1 Good against 3 Bad: a loss is exactly -swing", [done["popularity_delta"], PopularityScript.effective(s, 2) - before], [-SWING, -SWING])
	expect("... a Scandal card is drawn", [done["outcome"], done["deck"], done["text"]], ["bad", "scandal", CardsScript.text("scandal", done["card"])])
	expect("... and no Settlement card", s.decks.has("settlement"), false)


func ties_and_missing_votes() -> void:
	var s := new_turn()
	var before: int = PopularityScript.effective(s, 2)
	send(s, 2, {"type": "finish_performance"})
	send(s, 1, vote(true))
	send(s, 3, vote(true))
	send(s, 4, vote(false))
	var done: Dictionary = send(s, 5, vote(false))[1]
	expect("2 Good and 2 Bad is a tie: no popularity change", [done["outcome"], done["popularity_delta"], PopularityScript.effective(s, 2) - before], ["tie", 0, 0])
	expect("... and no card is drawn", [done.has("card"), s.decks.has("settlement"), s.decks.has("scandal")], [false, false, false])

	# Votes that never come don't count: two Good votes and nobody else is a win.
	s = new_turn()
	send(s, 2, {"type": "finish_performance"})
	send(s, 1, vote(true))
	send(s, 3, vote(true))
	expect("with two of four voted the voting is still open", s.term["act"]["phase"], VOTING)
	var ev := GameScript.tick(s, int(s.term["act"]["deadline"]))
	expect("at the deadline only the votes cast count: 2 Good, 0 Bad", [ev[0]["good"], ev[0]["bad"], ev[0]["popularity_delta"], ev[0]["outcome"]], [2, 0, SWING, "good"])


func ending_the_turn() -> void:
	var s := new_turn()
	expect("a turn can't end during the performance", send(s, 2, {"type": "end_turn"})[0]["reason"], "Finish your performance first.")
	send(s, 2, {"type": "finish_performance"})
	expect("... or during the voting", send(s, 2, {"type": "end_turn"})[0]["reason"], "Finish your performance first.")
	GameScript.tick(s, int(s.term["act"]["deadline"]))
	expect("... but can once the result is in (and nobody else can end it)", send(s, 3, {"type": "end_turn"})[0]["reason"], "It isn't your turn.")
	var ev := send(s, 2, {"type": "end_turn"})
	expect("ending the turn starts the next player's performance", [types(ev), s.term["act"]["player"], s.term["act"]["phase"], s.term["act"]["votes"]], [["turn_ended", "turn_started", "performance_started"], 3, PERFORMING, {}])

	# A performance left over from a player who is no longer in the order is replaced, not reused.
	s = new_turn()
	s.term["act"]["player"] = 4
	GameScript.tick(s)
	expect("a performance that doesn't belong to the player whose turn it is is dropped", [s.term["act"]["player"], s.term["act"]["phase"]], [2, PERFORMING])


func what_each_player_sees() -> void:
	var s := new_turn()
	send(s, 2, {"type": "finish_performance"})
	send(s, 3, vote(true))
	send(s, 4, vote(false))
	var mine: Dictionary = ViewsScript.state_view(s, 3)
	expect("a voter sees who has voted, not how", [mine["term"]["act"].has("votes"), mine["term"]["act"]["voted"]], [false, [3, 4]])
	expect("... and sees their own vote", mine["term"]["act"]["my_vote"], true)
	var other: Dictionary = ViewsScript.state_view(s, 5)
	expect("someone who hasn't voted sees neither", [other["term"]["act"].has("my_vote"), other["term"]["act"].has("votes")], [false, false])
	var json: String = ViewsScript.state_view_json(s, 5)
	expect("nobody's performance vote is in the term a phone gets", SerializerScript.to_json(other["term"]).contains("votes"), false)
	expect("the deck piles never leave the server", [mine.has("decks"), json.contains("decks")], [false, false])
	expect("the clock is public so a phone can show the countdown", [mine["clock_ms"], mine["term"]["act"]["deadline"]], [s.clock_ms, s.term["act"]["deadline"]])
	expect("the view is a copy", mine["term"]["act"] == s.term["act"], false)


func saving_in_the_middle() -> void:
	var s := new_turn()
	send(s, 2, {"type": "finish_performance"})
	send(s, 1, vote(true))
	send(s, 4, vote(false))
	var errors: Array = []
	var restored: GameStateScript = SerializerScript.state_from_json(SerializerScript.state_to_json(s), errors)
	expect("a game saved mid-vote loads without errors", errors, [])
	expect("... with the votes, the deadline and the piles", [restored.term["act"] == s.term["act"], restored.clock_ms, restored.decks == s.decks], [true, s.clock_ms, true])
	for g in [s, restored]:
		send(g, 3, vote(true))
		GameScript.tick(g, int(g.term["act"]["deadline"]))
	expect("both carry on to the same result", SerializerScript.state_to_json(s) == SerializerScript.state_to_json(restored), true)


# --- helpers -----------------------------------------------------------------------------

# Player 2 is the Leader, the Inauguration has been passed, and player 2's performance has started.
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


func vote(good: bool) -> Dictionary:
	return {"type": "performance_vote", "good": good}


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
