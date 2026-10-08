extends SceneTree

const GameScript = preload("res://scripts/game.gd")
const CardsScript = preload("res://scripts/cards.gd")
const CardEffectsScript = preload("res://scripts/card_effects.gd")
const DebtScript = preload("res://scripts/debt.gd")
const PopularityScript = preload("res://scripts/popularity.gd")
const GameStateScript = preload("res://scripts/game_state.gd")

const PRESIDENT = GameStateScript.LeaderType.PRESIDENT
const TREASURY := 0
const SWING := 6

var failures: int = 0


func _init() -> void:
	the_table_of_effects()
	every_listed_card()
	collecting()
	paying()
	popularity()
	cards_the_table_carries_out()
	from_a_vote_to_an_effect()
	print("%d failure(s)" % failures)
	quit(1 if failures > 0 else 0)


func the_table_of_effects() -> void:
	expect("a collect card", CardsScript.effects("settlement", 19), {"psd": 75})
	expect("a pay card", CardsScript.effects("scandal", 20), {"psd": -40})
	expect("a card with both", CardsScript.effects("settlement", 37), {"psd": -50, "popularity": 10})
	expect("a card that needs other players isn't listed", CardsScript.effects("settlement", 0), {})
	expect("a Performance card has no effect", CardsScript.effects("performance", 0), {})


func every_listed_card() -> void:
	var listed: int = 0
	for deck in ["settlement", "scandal"]:
		for card in CardsScript.count(deck):
			var effect: Dictionary = CardsScript.effects(deck, card)
			if effect.is_empty():
				continue
			listed += 1
			var s := new_game()
			var total: int = total_money(s)
			var cash: int = s.psd[3]
			var pop: int = PopularityScript.effective(s, 3)
			var ev := CardEffectsScript.apply(s, 3, deck, card)
			var label: String = "%s %d" % [deck, card]
			expect(label + ": money is conserved", total_money(s), total)
			expect(label + ": the player's cash moved by exactly the card's amount", s.psd[3] - cash, int(effect.get("psd", 0)))
			expect(label + ": popularity moved by exactly the card's amount", PopularityScript.effective(s, 3) - pop, int(effect.get("popularity", 0)))
			expect(label + ": one public event, logged once, not left to the table", [ev.size(), ev[0]["audience"], ev[0]["by_table"], s.event_log.back() == ev[0]], [1, [], false, true])
	expect("22 cards are applied by the game", listed, 22)


func collecting() -> void:
	var s := new_game()
	var ev := CardEffectsScript.apply(s, 3, "settlement", 19)
	expect("Collect 75 PSD: the treasury pays it", [s.psd[3], s.treasury, ev[0]["psd"]], [1075, 7550 - 75, 75])

	s = new_game()
	s.psd[1] += s.treasury - 30
	s.treasury = 30
	ev = CardEffectsScript.apply(s, 3, "settlement", 19)
	expect("a short treasury pays what it has: 30 of 75", [s.psd[3], s.treasury, ev[0]["psd"], ev[0]["short"]], [1030, 0, 30, 45])

	s = new_game()
	s.treasury += s.psd[3]
	s.psd[3] = 0
	DebtScript.charge(s, 3, TREASURY, 60)
	var total: int = total_money(s)
	CardEffectsScript.apply(s, 3, "settlement", 19)
	expect("money collected pays debts first: 75 clears a 60 debt and leaves 15", [DebtScript.total_debt(s, 3), s.psd[3]], [0, 15])
	expect("... and money is conserved", total_money(s), total)


func paying() -> void:
	var s := new_game()
	var ev := CardEffectsScript.apply(s, 3, "scandal", 20)
	expect("Pay 40 PSD to the treasury", [s.psd[3], s.treasury, ev[0]["psd"], ev[0].has("new_debt")], [960, 7550 + 40, -40, false])

	s = new_game()
	s.psd[1] += s.psd[3] - 25
	s.psd[3] = 25
	var total: int = total_money(s)
	ev = CardEffectsScript.apply(s, 3, "scandal", 20)
	expect("a player who can't cover it pays what they have, and the rest is debt", [s.psd[3], DebtScript.total_debt(s, 3), ev[0]["new_debt"]], [0, 15, 15])
	expect("... and money is conserved", total_money(s), total)
	expect("... debt means no cash", s.psd[3], 0)


func popularity() -> void:
	var s := new_game()
	s.popularity[3] = 45
	var ev := CardEffectsScript.apply(s, 3, "settlement", 42)   # lose 30 PSD, gain 15 popularity
	expect("popularity stays on the track: 45 + 15 stops at 50", [PopularityScript.effective(s, 3), ev[0]["popularity"]], [50, 5])
	s = new_game()
	s.popularity[3] = -48
	ev = CardEffectsScript.apply(s, 3, "scandal", 37)   # lose 12
	expect("... and so does the bottom: -48 - 12 stops at -50", [PopularityScript.effective(s, 3), ev[0]["popularity"]], [-50, -2])


func cards_the_table_carries_out() -> void:
	var s := new_game()
	var before: String = JSON.stringify([s.psd, s.treasury, s.popularity])
	var ev := CardEffectsScript.apply(s, 3, "settlement", 0)
	expect("a card the game doesn't know is announced for the table", [ev[0]["by_table"], ev[0].has("psd"), ev[0].has("popularity")], [true, false, false])
	expect("... and nothing changes", JSON.stringify([s.psd, s.treasury, s.popularity]), before)


func from_a_vote_to_an_effect() -> void:
	# A won vote draws a Settlement card and the card is applied to the performer.
	var s := new_turn()
	s.decks["settlement"] = [19]   # the next Settlement card drawn is the one that pays 75
	var cash: int = s.psd[2]
	var pop: int = PopularityScript.effective(s, 2)
	send(s, 2, {"type": "finish_performance"})
	for id in [1, 3, 4]:
		send(s, id, vote(true))
	var ev := send(s, 5, vote(true))
	expect("a won vote ends the voting, draws the card and applies it", types(ev), ["performance_vote_cast", "performance_resolved", "card_applied"])
	expect("... the performer gets the 75 PSD and the +swing popularity", [s.psd[2] - cash, PopularityScript.effective(s, 2) - pop], [75, SWING])
	expect("... the card event names the card that was drawn", [ev[2]["deck"], ev[2]["card"], ev[1]["card"]], ["settlement", 19, 19])

	# A lost vote draws a Scandal card.
	s = new_turn()
	s.decks["scandal"] = [24]   # pay 70, lose 5 popularity
	cash = s.psd[2]
	pop = PopularityScript.effective(s, 2)
	send(s, 2, {"type": "finish_performance"})
	for id in [1, 3, 4, 5]:
		send(s, id, vote(false))
	expect("a lost vote costs the Scandal card's 70 PSD", s.psd[2] - cash, -70)
	expect("... and -swing plus the card's -5 popularity", PopularityScript.effective(s, 2) - pop, -SWING - 5)
	expect("... with all the money still in the game", total_money(s), 12550)

	# A tie draws nothing, so nothing is applied.
	s = new_turn()
	send(s, 2, {"type": "finish_performance"})
	send(s, 1, vote(true))
	send(s, 3, vote(true))
	send(s, 4, vote(false))
	expect("a tie applies no card", types(send(s, 5, vote(false))), ["performance_vote_cast", "performance_resolved"])


# --- helpers -----------------------------------------------------------------------------

func new_game() -> GameStateScript:
	var s := GameScript.new_game([1, 2, 3, 4, 5], 4)
	return s


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


func send(s: GameStateScript, player_id: int, command: Dictionary) -> Array:
	return GameScript.handle(s, player_id, command)


func total_money(s: GameStateScript) -> int:
	var total: int = s.treasury
	for id in s.psd:
		total += s.psd[id]
	return total


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
