extends SceneTree

const GameStateScript = preload("res://scripts/game_state.gd")
const ModifiersScript = preload("res://scripts/modifiers.gd")
const PopularityScript = preload("res://scripts/popularity.gd")
const ScheduleScript = preload("res://scripts/schedule.gd")
const RoundEndScript = preload("res://scripts/round_end.gd")
const CardsScript = preload("res://scripts/cards.gd")
const SpecialCardsScript = preload("res://scripts/special_cards.gd")

var failures: int = 0


func _init() -> void:
	windows()
	uses()
	rounds_ending()
	popularity_hooks()
	the_schedule()
	every_special_is_a_card()
	print("%d failure(s)" % failures)
	quit(1 if failures > 0 else 0)


func table() -> GameStateScript:
	var s := GameStateScript.new()
	s.player_ids = [1, 2, 3]
	s.player_count = 3
	s.current_round = 4
	for id in s.player_ids:
		s.psd[id] = 1000
		s.popularity[id] = 0
		s.sick[id] = false
	s.treasury = 5000
	return s


func windows() -> void:
	var s := table()
	var record := ModifiersScript.give(s, 1, "halve_loss", {"starts": 1, "rounds": 2})
	expect("the next 2 rounds are rounds 5 and 6", [record["from"], record["until"]], [5, 6])
	expect("it isn't active in the round it was given", ModifiersScript.active(s, 1, "halve_loss"), false)
	s.current_round = 5
	expect("active in round 5", ModifiersScript.active(s, 1, "halve_loss"), true)
	s.current_round = 6
	expect("... and 6", ModifiersScript.active(s, 1, "halve_loss"), true)
	s.current_round = 7
	expect("... not 7", ModifiersScript.active(s, 1, "halve_loss"), false)
	ModifiersScript.give(s, 2, "x", {"rounds": -1})
	s.current_round = 99
	expect("a modifier with no end is active for ever", ModifiersScript.active(s, 2, "x"), true)
	expect("nothing for a player who has none", [ModifiersScript.active(s, 3, "x"), ModifiersScript.names_of(s, 3)], [false, []])
	expect("names_of lists the ones that apply", ModifiersScript.names_of(s, 2), ["x"])


func uses() -> void:
	var s := table()
	ModifiersScript.give(s, 1, "skip", {"rounds": -1, "uses": 2})
	ModifiersScript.use(s, 1, "skip")
	expect("a use is spent", [ModifiersScript.active(s, 1, "skip"), s.mods[1]["skip"]["uses"]], [true, 1])
	ModifiersScript.use(s, 1, "skip")
	expect("when the uses run out it is gone, with the player's entry", [ModifiersScript.has(s, 1, "skip"), s.mods.has(1)], [false, false])
	ModifiersScript.give(s, 1, "forever", {"rounds": -1})
	ModifiersScript.use(s, 1, "forever")
	expect("a modifier with unlimited uses is not used up", ModifiersScript.active(s, 1, "forever"), true)
	ModifiersScript.use(s, 2, "nothing")   # no crash


func rounds_ending() -> void:
	var s := table()
	ModifiersScript.give(s, 1, "a", {"starts": 1, "rounds": 1})   # round 5 only
	ModifiersScript.give(s, 1, "b", {"rounds": 1})                 # round 4 only
	ModifiersScript.give(s, 1, "c", {"rounds": -1})
	ModifiersScript.end_of_round(s)   # round 4 ends
	expect("what ended with this round is gone; the rest stays", [ModifiersScript.has(s, 1, "a"), ModifiersScript.has(s, 1, "b"), ModifiersScript.has(s, 1, "c")], [true, false, true])
	s.current_round = 5
	ModifiersScript.end_of_round(s)
	expect("round 5 ends: 'a' goes, the endless one stays", [ModifiersScript.has(s, 1, "a"), ModifiersScript.has(s, 1, "c")], [false, true])
	ModifiersScript.remove_player(s, 1)
	expect("a player who leaves has none", s.mods, {})


func popularity_hooks() -> void:
	var s := table()
	s.popularity[1] = 10
	ModifiersScript.give(s, 1, "halve_loss", {"rounds": 1})
	PopularityScript.change_base(s, 1, -9)
	expect("a halved loss of 9 is 4 (rounded down, in the player's favour)", PopularityScript.base(s, 1), 6)
	PopularityScript.change_base(s, 1, 4)
	expect("gains are whole", PopularityScript.base(s, 1), 10)
	ModifiersScript.give(s, 2, "pop_floor", {"rounds": 1, "value": 3})
	s.popularity[2] = 8
	PopularityScript.change_base(s, 2, -20)
	expect("a floor stops a loss at its value", PopularityScript.base(s, 2), 3)
	s.popularity[3] = -50
	expect("a shield: -50 is CANCELLED without it", PopularityScript.is_cancelled(s, 3), true)
	ModifiersScript.give(s, 3, "cancel_shield", {"rounds": 1})
	expect("... not with it", PopularityScript.is_cancelled(s, 3), false)


func the_schedule() -> void:
	var s := table()
	s.leader_id = 2
	ScheduleScript.stipend(s, 1, "leader", 100, 1, 2)
	ScheduleScript.penalty(s, 3, -5, 1, 4, true)
	ScheduleScript.repay(s, 1, 3, 40, 2)
	expect("three entries", s.schedule.size(), 3)
	expect("the round it was set in does nothing", ScheduleScript.end_of_round(s), [])
	s.current_round = 5
	var ev := ScheduleScript.end_of_round(s)
	expect("round 5: the Leader pays 100 and the penalty bites", [ev[0]["type"], ev[0]["payer"], ev[1]["type"], ev[1]["popularity"]], ["stipend_paid", 2, "penalty_applied", -5])
	expect("a stipend whose payer is the receiver is missed", ScheduleScript.end_of_round(table()), [])
	expect("an apology ends the penalty", [ScheduleScript.has_apology_penalty(s, 3), ScheduleScript.end_penalties(s, 3), ScheduleScript.has_apology_penalty(s, 3)], [true, 1, false])
	s.current_round = 6
	ev = ScheduleScript.end_of_round(s)
	expect("round 6: the second stipend and the repayment (round 4 + 2)", [ev[0]["type"], ev[1]["type"], s.schedule], ["stipend_paid", "loan_repaid", []])
	ScheduleScript.stipend(s, 1, "leader", 100, 0, 1)
	ScheduleScript.remove_player(s, 2)
	s.leader_id = 1
	expect("a player who leaves takes their entries with them", s.schedule.size(), 1)


# Every special name the engine knows is used by a card, and every card's special is one it knows.
func every_special_is_a_card() -> void:
	var used: Array = []
	for deck in ["settlement", "scandal"]:
		for card in CardsScript.count(deck):
			var name: String = CardsScript.effects(deck, card).get("special", "")
			if name != "":
				used.append(name)
				expect("%s card %d's special '%s' is known to the engine" % [deck, card, name], name in SpecialCardsScript.NAMES, true)
	for name in SpecialCardsScript.NAMES:
		expect("the special '%s' is used by a card" % name, name in used, true)


func expect(label: String, actual: Variant, wanted: Variant) -> void:
	var ok: bool = typeof(actual) == typeof(wanted) and actual == wanted
	if not ok:
		failures += 1
	print(("PASS " if ok else "FAIL ") + label + " -> " + str(actual).left(90))
