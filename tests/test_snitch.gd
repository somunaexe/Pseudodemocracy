extends SceneTree

const GameScript = preload("res://scripts/game.gd")
const GameStateScript = preload("res://scripts/game_state.gd")
const CardsScript = preload("res://scripts/cards.gd")
const CardEffectsScript = preload("res://scripts/card_effects.gd")
const CorruptionScript = preload("res://scripts/corruption.gd")
const PopularityScript = preload("res://scripts/popularity.gd")

const PRESIDENT = GameStateScript.LeaderType.PRESIDENT

var failures: int = 0


func _init() -> void:
	taking_it_alone()
	snitching()
	timing_out()
	print("%d failure(s)" % failures)
	quit(1 if failures > 0 else 0)


func taking_it_alone() -> void:
	var s := new_turn()
	var card: int = card_number("scandal", "Your embezzlement was traced")
	var cash: int = s.psd[3]
	var treasury: int = s.treasury
	var pop: int = PopularityScript.effective(s, 3)
	var ev := CardEffectsScript.apply(s, 3, "scandal", card)
	expect("the card asks the drawer which way", [types(ev), s.choice["kind"], s.choice["labels"], s.choice["player"]], [["card_applied", "choice_needed"], "option", ["Snitch and split it", "Take it alone"], 3])
	expect("... and the turn waits for it", send(s, 3, {"type": "end_turn"})[0]["type"], "rejected")
	ev = send(s, 3, {"type": "choose", "choice": 1})
	expect("taking it alone: return 200, lose 20 popularity, one marker", [cash - s.psd[3], PopularityScript.effective(s, 3) - pop, CorruptionScript.held(s, 3), s.treasury - treasury], [200, -20, 1, 200])
	expect("... no one else is touched", [CorruptionScript.held(s, 4), s.choice.is_empty()], [0, true])


func snitching() -> void:
	var s := new_turn()
	var card: int = card_number("scandal", "Your embezzlement was traced")
	var cash: int = s.psd[3]
	var other_cash: int = s.psd[4]
	var pop: int = PopularityScript.effective(s, 3)
	var other_pop: int = PopularityScript.effective(s, 4)
	CardEffectsScript.apply(s, 3, "scandal", card)
	var ev := send(s, 3, {"type": "choose", "choice": 0})
	expect("snitching asks whom", [types(ev), s.choice["kind"], s.choice["parent"], s.choice["candidates"]], [["choice_made", "choice_needed"], "player", 0, [1, 2, 4, 5]])
	expect("... nothing happens yet", [s.psd[3], s.psd[4], CorruptionScript.held(s, 3)], [cash, other_cash, 0])
	expect("... only the drawer answers", send(s, 4, {"type": "choose", "choice": 5})[0]["reason"], "It isn't your choice.")
	expect("... a stranger to the table is refused", send(s, 3, {"type": "choose", "choice": 9})[0]["type"], "rejected")
	expect("... so is the drawer themselves", send(s, 3, {"type": "choose", "choice": 3})[0]["type"], "rejected")
	ev = send(s, 3, {"type": "choose", "choice": 4})
	expect("both return 100, lose 10 popularity and get a marker", [cash - s.psd[3], other_cash - s.psd[4], PopularityScript.effective(s, 3) - pop, PopularityScript.effective(s, 4) - other_pop], [100, 100, -10, -10])
	expect("... markers on both", [CorruptionScript.held(s, 3), CorruptionScript.held(s, 4), types(ev)], [1, 1, ["choice_made", "marker_gained", "marker_gained"]])
	expect("... the event says what each lost and the choice is over", [ev[0]["psd"], ev[0]["target_psd"], s.choice.is_empty()], [-100, -100, true])

	# Money is conserved, and a partner who can't pay goes into debt.
	s = new_turn()
	s.treasury += s.psd[4] - 30
	s.psd[4] = 30
	var total: int = s.treasury
	for id in s.player_ids:
		total += s.psd[id]
	CardEffectsScript.apply(s, 3, "scandal", card)
	send(s, 3, {"type": "choose", "choice": 0})
	ev = send(s, 3, {"type": "choose", "choice": 4})
	var after: int = s.treasury
	for id in s.player_ids:
		after += s.psd[id]
	expect("the partner pays what they have; the rest is debt, and money is conserved", [s.psd[4], ev[0]["target_new_debt"], after], [0, 70, total])


func timing_out() -> void:
	var s := new_turn()
	var card: int = card_number("scandal", "Your embezzlement was traced")
	CardEffectsScript.apply(s, 3, "scandal", card)
	GameScript.tick(s, int(s.choice["deadline"]))
	expect("if the drawer is slow the server chooses for them, at random", [s.choice.is_empty() or s.choice.has("parent")], [true])
	if s.choice.has("parent"):
		GameScript.tick(s, int(s.choice["deadline"]))
	expect("... and the second question is answered the same way, leaving no choice behind", s.choice.is_empty(), true)
	var seen := {}
	for seed_value in 20:
		var g := new_turn()
		g.rng_state = seed_value * 7919 + 1
		CardEffectsScript.apply(g, 3, "scandal", card)
		for i in 2:
			if not g.choice.is_empty():
				GameScript.tick(g, int(g.choice["deadline"]))
		seen[CorruptionScript.held(g, 4)] = true
	expect("random choices go both ways: sometimes a partner is dragged in, sometimes not", seen.keys().size(), 2)


func card_number(deck: String, prefix: String) -> int:
	for i in CardsScript.count(deck):
		if CardsScript.text(deck, i).begins_with(prefix):
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
