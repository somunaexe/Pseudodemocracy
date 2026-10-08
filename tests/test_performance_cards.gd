extends SceneTree

const GameScript = preload("res://scripts/game.gd")
const GameStateScript = preload("res://scripts/game_state.gd")
const CardsScript = preload("res://scripts/cards.gd")
const ModifiersScript = preload("res://scripts/modifiers.gd")
const RoundEndScript = preload("res://scripts/round_end.gd")
const PopularityScript = preload("res://scripts/popularity.gd")
const UnionsScript = preload("res://scripts/unions.gd")
const PerformanceCardsScript = preload("res://scripts/performance_cards.gd")
const PlayScript = preload("res://tests/play.gd")

const PRESIDENT = GameStateScript.LeaderType.PRESIDENT
const SWING := 6

var failures: int = 0


func _init() -> void:
	the_cards()
	selling_a_product()
	a_dispute_the_leader_judges()
	a_dispute_the_table_judges()
	custody()
	a_loan()
	fraud_and_excuses()
	mediation()
	pitching_a_union()
	a_word_wrestle()
	print("%d failure(s)" % failures)
	quit(1 if failures > 0 else 0)


func the_cards() -> void:
	for pair in [["You have a useless product", "sell_product"], ["Your neighbour (on your right)", "neighbour_dispute"], ["You and the 4th player", "custody"], ["You need a loan", "loan_pitch"],
			["You're accused of election fraud", "fraud"], ["Mediate a live dispute", "mediation"], ["Pitch your union/mob", "pitch_union"], ["Choose a player — try to recruit them", "pitch_union"],
			["Choose a player — challenge them to a public arm-wrestle", "word_wrestle"], ["Your Doctor gave you a convenient", "excuse"]]:
		expect("'%s' is the '%s' card" % [pair[0], pair[1]], CardsScript.effects("performance", card_number(pair[0])), {"special": pair[1]})
	var known: Array = []
	for card in CardsScript.count("performance"):
		var name: String = CardsScript.effects("performance", card).get("special", "")
		if name != "":
			known.append(name)
			expect("performance card %d's special '%s' is known" % [card, name], name in PerformanceCardsScript.NAMES, true)
	for name in PerformanceCardsScript.NAMES:
		expect("the special '%s' is used by a card" % name, name in known, true)


func selling_a_product() -> void:
	var s := turn_with("You have a useless product", 3)
	expect("the performer is asked whom to sell to", [s.choice["kind"], s.choice["player"], s.choice["candidates"]], ["player", 3, [1, 2, 4, 5]])
	send(s, 3, {"type": "choose", "choice": 4})
	expect("... then for a price", [s.choice["kind"], s.choice["min"], s.choice["max"]], ["number", 0, 500])
	var cash3: int = s.psd[3]
	var cash4: int = s.psd[4]
	send(s, 3, {"type": "choose", "choice": 150})
	expect("the buyer is asked, and only the buyer", [s.polls[0]["targets"], s.polls[0]["labels"], s.polls[0]["default"]], [[4], ["Buy it for 150 PSD", "Refuse"], 1])
	send(s, 4, {"type": "poll_answer", "poll": s.polls[0]["id"], "option": 0})
	expect("a buyer who buys pays the price to the performer", [s.psd[3] - cash3, cash4 - s.psd[4], last_of(s, "product_sold")["price"]], [150, 150, 150])
	s = turn_with("You have a useless product", 3)
	send(s, 3, {"type": "choose", "choice": 4})
	send(s, 3, {"type": "choose", "choice": 150})
	cash3 = s.psd[3]
	GameScript.tick(s, int(s.polls[0]["deadline"]))
	expect("silence is a refusal", [s.psd[3] - cash3, last_of(s, "product_refused").is_empty()], [0, false])
	s = turn_with("You have a useless product", 3)
	send(s, 3, {"type": "choose", "choice": 4})
	expect("a price over 500 is refused", send(s, 3, {"type": "choose", "choice": 501})[0]["type"], "rejected")


func a_dispute_the_leader_judges() -> void:
	var s := turn_with("Your neighbour (on your right)", 4)
	expect("the neighbour on the right of player 4 is 3", s.term["act"]["card_data"]["opponent"], 3)
	send(s, 4, {"type": "finish_performance"})
	expect("when the performance ends the Leader (not one of the two) is asked who is telling the truth", [s.choice["player"], s.choice["subject"], s.choice["labels"]], [2, 4, ["The performer", "The other player"]])
	var c4: int = s.psd[4]
	var c3: int = s.psd[3]
	send(s, 2, {"type": "choose", "choice": 0})
	expect("the winner collects 100 PSD from the loser", [s.psd[4] - c4, c3 - s.psd[3]], [100, 100])
	s = turn_with("Your neighbour (on your right)", 4)
	send(s, 4, {"type": "finish_performance"})
	c4 = s.psd[4]
	c3 = s.psd[3]
	send(s, 2, {"type": "choose", "choice": 1})
	expect("... or the other way round", [c4 - s.psd[4], s.psd[3] - c3], [100, 100])
	s = turn_with("Your neighbour (on your right)", 4)
	send(s, 4, {"type": "finish_performance"})
	c4 = s.psd[4]
	GameScript.tick(s, int(s.choice["deadline"]))
	expect("if the Leader says nothing the performer is believed", s.psd[4] - c4, 100)


func a_dispute_the_table_judges() -> void:
	var s := turn_with("Your neighbour (on your right)", 3)
	expect("player 3's neighbour on the right is the Leader (2)", s.term["act"]["card_data"]["opponent"], 2)
	send(s, 3, {"type": "finish_performance"})
	expect("the Leader is one of the two, so nobody is asked", s.choice.is_empty(), true)
	var c3: int = s.psd[3]
	var c2: int = s.psd[2]
	for id in [1, 4, 5]:
		send(s, id, {"type": "performance_vote", "good": true})
	send(s, 2, {"type": "performance_vote", "good": false})
	expect("the table's vote decides: Good means the performer wins 100 from the Leader", [s.psd[3] - c3 >= 100, c2 - s.psd[2] >= 100], [true, true])
	s = turn_with("Your neighbour (on your right)", 3)
	send(s, 3, {"type": "finish_performance"})
	c3 = s.psd[3]
	for id in [1, 2, 4, 5]:
		send(s, id, {"type": "performance_vote", "good": false})
	expect("Bad means the neighbour wins", last_of(s, "dispute_settled")["winner"], 2)
	s = turn_with("Your neighbour (on your right)", 3)
	send(s, 3, {"type": "finish_performance"})
	GameScript.tick(s, int(s.term["act"]["deadline"]))
	expect("a tie settles nothing", last_of(s, "dispute_settled").is_empty(), true)


func custody() -> void:
	var s := turn_with("You and the 4th player", 3)
	expect("the 4th player of the round (order 2, 3, 4, 5, 1) is 5", s.term["act"]["card_data"]["opponent"], 5)
	send(s, 3, {"type": "finish_performance"})
	var c3: int = s.psd[3]
	var c5: int = s.psd[5]
	var treasury: int = s.treasury
	send(s, 2, {"type": "choose", "choice": 0})
	expect("the winner gets 150 from the treasury, the loser pays 50 costs", [s.psd[3] - c3, c5 - s.psd[5], s.treasury - treasury], [150, 50, -100])
	s = turn_with("You and the 4th player", 5)
	expect("if the performer is the 4th player they face the 1st (2, the Leader)", s.term["act"]["card_data"]["opponent"], 2)


func a_loan() -> void:
	var s := turn_with("You need a loan", 3)
	send(s, 3, {"type": "choose", "choice": 4})
	expect("the lender is offered the rates and may refuse", [s.polls[0]["targets"], s.polls[0]["labels"].size(), s.polls[0]["default"]], [[4], 5, 4])
	var c3: int = s.psd[3]
	var c4: int = s.psd[4]
	send(s, 4, {"type": "poll_answer", "poll": s.polls[0]["id"], "option": 2})
	var agreed: Dictionary = last_of(s, "loan_agreed")
	expect("at 25% the lender hands over 200 and is owed 250 in 3 rounds", [s.psd[3] - c3, c4 - s.psd[4], agreed["interest"], agreed["repay"], agreed["due_round"]], [200, 200, 25, 250, s.current_round + 3])
	var repaid: int = 0
	for i in 4:
		s.current_round += 1
		for e in RoundEndScript.run(s):
			if e["type"] == "loan_repaid":
				repaid = e["amount"]
	expect("... repaid when due", repaid, 250)
	s = turn_with("You need a loan", 3)
	send(s, 3, {"type": "choose", "choice": 4})
	GameScript.tick(s, int(s.polls[0]["deadline"]))
	expect("silence refuses", last_of(s, "loan_refused").is_empty(), false)
	s = turn_with("You need a loan", 3)
	send(s, 3, {"type": "choose", "choice": 4})
	s.treasury += s.psd[4] - 100
	s.psd[4] = 100
	send(s, 4, {"type": "poll_answer", "poll": s.polls[0]["id"], "option": 0})
	expect("a lender without 200 in hand voids it", last_of(s, "loan_void")["reason"], "the lender hasn't 200 PSD in hand")


func fraud_and_excuses() -> void:
	var s := turn_with("You're accused of election fraud", 3)
	send(s, 3, {"type": "finish_performance"})
	var pop: int = PopularityScript.effective(s, 3)
	for id in [1, 2, 4, 5]:
		send(s, id, {"type": "performance_vote", "good": true})
	expect("believed: the usual swing and +10 more", PopularityScript.effective(s, 3) - pop, SWING + 10)
	s = turn_with("You're accused of election fraud", 3)
	send(s, 3, {"type": "finish_performance"})
	pop = PopularityScript.effective(s, 3)
	s.decks["scandal"] = [20]
	for id in [1, 2, 4, 5]:
		send(s, id, {"type": "performance_vote", "good": false})
	expect("not believed: the swing and -15 more", PopularityScript.effective(s, 3) - pop, -SWING - 15)
	s = turn_with("You're accused of election fraud", 3)
	send(s, 3, {"type": "finish_performance"})
	pop = PopularityScript.effective(s, 3)
	GameScript.tick(s, int(s.term["act"]["deadline"]))
	expect("a tie changes nothing", PopularityScript.effective(s, 3) - pop, 0)

	s = turn_with("Your Doctor gave you a convenient", 3)
	send(s, 3, {"type": "finish_performance"})
	s.decks["settlement"] = [19]
	for id in [1, 2, 4, 5]:
		send(s, id, {"type": "performance_vote", "good": true})
	expect("sold to the table, the excuse skips their next exam", ModifiersScript.active(s, 3, "exam_pass"), true)
	s = turn_with("Your Doctor gave you a convenient", 3)
	send(s, 3, {"type": "finish_performance"})
	s.decks["scandal"] = [20]
	for id in [1, 2, 4, 5]:
		send(s, id, {"type": "performance_vote", "good": false})
	expect("not sold: nothing", ModifiersScript.has(s, 3, "exam_pass"), false)


func mediation() -> void:
	var s := turn_with("Mediate a live dispute", 3)
	expect("the performer chooses the two players", [s.choice["kind"], s.choice["max"]], ["players", 2])
	send(s, 3, {"type": "choose", "choice": [4, 5]})
	send(s, 3, {"type": "finish_performance"})
	var c3: int = s.psd[3]
	var c4: int = s.psd[4]
	var c5: int = s.psd[5]
	s.decks["settlement"] = [19]
	for id in [1, 2, 4, 5]:
		send(s, id, {"type": "performance_vote", "good": true})
	expect("a Good vote: both pay the mediator 25 (before any card)", [c4 - s.psd[4] >= 25, c5 - s.psd[5] >= 25, last_of(s, "mediation_paid")["mediator"]], [true, true, 3])
	s = turn_with("Mediate a live dispute", 3)
	send(s, 3, {"type": "choose", "choice": [4]})
	send(s, 3, {"type": "finish_performance"})
	s.decks["settlement"] = [19]
	for id in [1, 2, 4, 5]:
		send(s, id, {"type": "performance_vote", "good": true})
	expect("with only one chosen nobody pays", last_of(s, "mediation_paid").is_empty(), true)
	s = turn_with("Mediate a live dispute", 3)
	send(s, 3, {"type": "choose", "choice": [4, 5]})
	send(s, 3, {"type": "finish_performance"})
	s.decks["scandal"] = [20]
	for id in [1, 2, 4, 5]:
		send(s, id, {"type": "performance_vote", "good": false})
	expect("a Bad vote: nobody pays", last_of(s, "mediation_paid").is_empty(), true)


func pitching_a_union() -> void:
	var s := new_turn()
	UnionsScript.found(s, 3, "activist")
	s.unions[1]["members"] = [3, 1]
	s.decks["performance"] = [card_number("Pitch your union/mob")]
	PlayScript.take_turn(s, 2)
	expect("a performer in a union is asked whom to pitch to: players in no union, not the Leader", [s.choice["kind"], s.choice["candidates"]], ["player", [4, 5]])
	var ev := send(s, 3, {"type": "choose", "choice": 4})
	expect("the player is invited, and answers with union_respond", [types(ev).has("union_invited"), s.union_invites[4]["union_id"]], [true, 1])
	send(s, 4, {"type": "union_respond", "accept": true})
	expect("... who joins", s.unions[1]["members"].has(4), true)

	s = turn_with("Choose a player — try to recruit them", 3)
	expect("a performer in no union has nothing to pitch", [s.choice.is_empty(), last_of(s, "union_pitch_unavailable")["reason"]], [true, "they are in no union or mob"])


func a_word_wrestle() -> void:
	var s := turn_with("Choose a player — challenge them to a public arm-wrestle", 3)
	send(s, 3, {"type": "choose", "choice": 4})
	expect("the contest is on", last_of(s, "wrestle_started")["opponent"], 4)
	expect("a stranger can't concede", send(s, 5, {"type": "concede"})[0]["reason"], "You aren't in this contest.")
	var c4: int = s.psd[4]
	var treasury: int = s.treasury
	var ev := send(s, 4, {"type": "concede"})
	expect("whoever concedes first loses 20 PSD to the treasury", [types(ev), c4 - s.psd[4], s.treasury - treasury], [["conceded"], 20, 20])
	expect("... only once", send(s, 3, {"type": "concede"})[0]["reason"], "It is already over.")
	s = turn_with("You have a useless product", 3)
	expect("with no wrestle there is nothing to concede", send(s, 3, {"type": "concede"})[0]["reason"], "There is nothing to concede.")
	s = turn_with("Choose a player — challenge them to a public arm-wrestle", 3)
	send(s, 3, {"type": "choose", "choice": 4})
	send(s, 3, {"type": "finish_performance"})
	expect("after the performance it is too late", send(s, 3, {"type": "concede"})[0]["reason"], "There is nothing to concede.")


# --- helpers -----------------------------------------------------------------------------

# The performance of `player` has begun with the card (player 2, the Leader, goes first with a plain card).
func turn_with(prefix: String, player: int) -> GameStateScript:
	var s := new_turn()
	var order: Array = [2, 3, 4, 5, 1]
	var plain: Array = []
	# Player 2's card was drawn already; draws pop from the end, so the target's card sits under the plain ones.
	for id in order.slice(1, order.find(player)):
		plain.append(20)
	s.decks["performance"] = [card_number(prefix)] + plain
	for id in order.slice(0, order.find(player)):
		PlayScript.take_turn(s, id)
	assert(s.term["act"]["player"] == player, "it should be player %d's performance" % player)
	return s


func card_number(prefix: String) -> int:
	for i in CardsScript.count("performance"):
		if CardsScript.text("performance", i).begins_with(prefix):
			return i
	assert(false, "no performance card begins '%s'" % prefix)
	return -1


func new_turn() -> GameStateScript:
	for seed_value in range(1, 400):
		var s := GameScript.new_game([1, 2, 3, 4, 5], seed_value)
		for id in [1, 2, 3, 4, 5]:
			GameScript.handle(s, id, {"type": "cast_vote", "candidate": 2})
		if s.leader_type == PRESIDENT:
			s.decks["performance"] = [20, 20, 20, 20, 20, 20]
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
