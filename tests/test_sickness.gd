extends SceneTree

const GameScript = preload("res://scripts/game.gd")
const SicknessScript = preload("res://scripts/sickness.gd")
const CardEffectsScript = preload("res://scripts/card_effects.gd")
const CardsScript = preload("res://scripts/cards.gd")
const RolesScript = preload("res://scripts/roles.gd")
const IncomeScript = preload("res://scripts/income.gd")
const PopularityScript = preload("res://scripts/popularity.gd")
const ViewsScript = preload("res://scripts/views.gd")
const GameStateScript = preload("res://scripts/game_state.gd")
const PlayScript = preload("res://tests/play.gd")

const PRESIDENT = GameStateScript.LeaderType.PRESIDENT

var failures: int = 0


func _init() -> void:
	becoming_sick()
	no_stacking()
	the_handbook_example()
	cures()
	rounds_passing()
	a_round_ending_in_a_game()
	cancelled_players_have_no_roles()
	sickness_cards()
	what_everyone_sees()
	print("%d failure(s)" % failures)
	quit(1 if failures > 0 else 0)


func becoming_sick() -> void:
	var s := table()
	expect("a healthy player can be sickened", SicknessScript.problem_sickening(s, 3), "")
	var ev := SicknessScript.sicken(s, 3, 2)
	expect("sickening is one public event", [ev[0]["type"], ev[0]["player"], ev[0]["rounds"], ev[0]["audience"]], ["sickened", 3, 2, []])
	expect("... the player is sick for 2 rounds, and that is how long it first was", [s.sick[3], s.sick_left[3], s.sick_original[3]], [true, 2, 2])
	expect("a stranger can't be sickened", SicknessScript.problem_sickening(s, 9), "That player is not in the game.")
	s.eliminated[4] = true
	expect("nor an eliminated player", SicknessScript.problem_sickening(s, 4), "That player is not in the game.")


func no_stacking() -> void:
	var s := table()
	SicknessScript.sicken(s, 3, 2)
	expect("a sick player can't be sickened again", SicknessScript.problem_sickening(s, 3), "A sick player can't be sickened again.")
	s.immune_left[4] = 2
	expect("an immune player can't be sickened", SicknessScript.problem_sickening(s, 4), "They are immune for 2 more round(s).")
	expect("... and a lengthening only touches someone who is sick", SicknessScript.lengthen(s, 5, 2), [])


func the_handbook_example() -> void:
	# A Concoction makes you sick for 2 rounds. A sabotaged "cure" adds 2 more: sick for 4. When you
	# recover you are immune for 2 rounds, not 4.
	var s := table()
	SicknessScript.sicken(s, 3, 2)
	var ev := SicknessScript.lengthen(s, 3, 2)
	expect("sabotage lengthens the sickness to 4 rounds", [ev[0]["type"], s.sick_left[3], s.sick_original[3]], ["sickness_lengthened", 4, 2])
	for i in 3:
		SicknessScript.end_of_round(s)
	expect("after three rounds one is left", [s.sick[3], s.sick_left[3]], [true, 1])
	var end := SicknessScript.end_of_round(s)
	expect("the fourth round ends it, and the player is immune for 2 rounds, not 4", [types(end), s.sick[3], s.immune_left[3]], [["recovered"], false, 2])
	expect("... the original length is forgotten", [s.sick_left.has(3), s.sick_original.has(3)], [false, false])
	expect("... and they can't be sickened while immune", SicknessScript.problem_sickening(s, 3) != "", true)
	SicknessScript.end_of_round(s)
	expect("immunity counts down: 1 round left", s.immune_left[3], 1)
	var last := SicknessScript.end_of_round(s)
	expect("... and ends after the second", [types(last), s.immune_left.has(3), SicknessScript.problem_sickening(s, 3)], [["immunity_ended"], false, ""])


func cures() -> void:
	var s := table()
	SicknessScript.sicken(s, 3, 2)
	var ev := SicknessScript.shorten(s, 3, 1)
	expect("a cure shortens the sickness", [ev[0]["type"], s.sick_left[3], s.sick[3]], ["sickness_shortened", 1, true])
	ev = SicknessScript.shorten(s, 3, 1)
	expect("a cure that takes it to 0 ends it, with immunity for the original 2", [ev[0]["type"], s.sick[3], s.immune_left[3]], ["recovered", false, 2])
	expect("curing a healthy player does nothing", SicknessScript.shorten(s, 4, 1), [])

	s = table()
	SicknessScript.sicken(s, 3, 1)
	SicknessScript.lengthen(s, 3, 2)
	SicknessScript.shorten(s, 3, 1)
	expect("a cure of 1 on a sabotaged 3 leaves 2", s.sick_left[3], 2)
	ev = SicknessScript.shorten(s, 3, 5)
	expect("a cure bigger than what is left just ends it; immunity is still the original 1", [s.sick[3], s.immune_left[3]], [false, 1])

	s = table()
	SicknessScript.sicken(s, 3, 3)
	ev = SicknessScript.recover(s, 3)
	expect("surgery recovers at once: immune for the original 3", [ev[0]["immune_for"], s.sick[3], s.immune_left[3]], [3, false, 3])
	expect("recovering twice does nothing", SicknessScript.recover(s, 3), [])

	s = table()
	s.immune_left[3] = 4
	SicknessScript.grant_immunity(s, 3, 2)
	expect("a card can't shorten an immunity you already have", s.immune_left[3], 4)
	SicknessScript.grant_immunity(s, 4, 2)
	expect("... but gives one to a player who has none", s.immune_left[4], 2)


func rounds_passing() -> void:
	var s := table()
	SicknessScript.sicken(s, 3, 1)
	s.immune_left[4] = 1
	SicknessScript.sicken(s, 5, 3)
	var ev := SicknessScript.end_of_round(s)
	expect("when a round ends, immunity and sickness count down together", [s.sick[3], s.sick[5], s.sick_left[5], s.immune_left.has(4)], [false, true, 2, false])
	expect("... player 3, who has just recovered, keeps their full immunity of 1 round", s.immune_left[3], 1)
	expect("... in player order", types(ev), ["immunity_ended", "recovered"])
	expect("a round with nobody sick does nothing", SicknessScript.end_of_round(table()), [])

	# A sick flag set by hand with no length (older saves, tests) is left alone, not crashed on.
	s = table()
	s.sick[2] = true
	expect("sickness with no recorded length is left as it is", [SicknessScript.end_of_round(s), s.sick[2]], [[], true])


func a_round_ending_in_a_game() -> void:
	# The Leader is sick for 1 round. When the term ends the round is over, they recover, and they can
	# write the exam.
	var s := new_turn()
	SicknessScript.sicken(s, 2, 1)
	var ended: Array = []
	for id in [2, 3, 4, 5, 1]:
		ended = PlayScript.take_turn(s, id)
	ended = GameScript.handle(s, 2, {"type": "pass_window"}) if s.term.get("phase") == GameStateScript.TermPhase.FAREWELL else ended
	var seen: Array = types(s.event_log)
	var recovered_at: int = seen.rfind("recovered")
	expect("the term ending is the end of the round: the Leader recovers", recovered_at >= 0, true)
	expect("... before the election starts", recovered_at < seen.rfind("election_started"), true)
	expect("... so the Leader can write the exam", s.event_log[seen.rfind("election_started")]["exam"], true)
	expect("... the Leader is immune for the original 1 round", s.immune_left.get(2, 0), 1)
	expect("... and the recovery was logged once", count(s.event_log, "recovered"), 1)

	# A vacancy ends the round too.
	s = new_turn()
	SicknessScript.sicken(s, 3, 1)
	ElimScript_eliminate(s, 2)
	expect("a Leader eliminated mid-term ends the round: sickness counts down", [s.sick[3], s.immune_left.get(3, 0)], [false, 1])

	# The first election starts the game; it is not the end of a round.
	var g := GameScript.new_game([1, 2, 3], 5)
	expect("the very first election ends no round", g.immune_left, {})


func ElimScript_eliminate(s: GameStateScript, id: int) -> void:
	preload("res://scripts/elimination.gd").eliminate(s, id, "debt")


func cancelled_players_have_no_roles() -> void:
	var s := table()
	RolesScript.grant(s, 3, "Doctor")
	expect("a healthy, popular Doctor can use the power", RolesScript.can_use_power(s, 3, "Doctor"), "")
	s.popularity[3] = -50
	expect("a CANCELLED player has no roles: no power", RolesScript.can_use_power(s, 3, "Doctor"), "CANCELLED players have no roles until they climb back.")
	expect("... and no role income", IncomeScript.gross(s, 3), 0)
	expect("... but keeps the card", RolesScript.has(s, 3, "Doctor"), true)
	s.popularity[3] = -49
	expect("climbing back above the line restores both", [RolesScript.can_use_power(s, 3, "Doctor"), IncomeScript.gross(s, 3)], ["", 70])
	# The Leader's pay stays when CANCELLED (handbook: still collects income).
	s.leader_id = 3
	s.popularity[3] = -50
	expect("a CANCELLED Leader still collects the Leader's 100 but no role income", IncomeScript.gross(s, 3), 100)


func sickness_cards() -> void:
	var sick_card: int = 23
	var immune_card: int = 33
	var s := table()
	expect("the sickness cards are listed", [CardsScript.effects("scandal", sick_card), CardsScript.effects("settlement", immune_card)], [{"sick": 1}, {"immune": 2}])
	var ev := CardEffectsScript.apply(s, 3, "scandal", sick_card)
	expect("the Scandal card makes the drawer sick for 1 round", [types(ev), s.sick[3], s.sick_left[3], ev[0]["sick"]], [["card_applied", "sickened"], true, 1, 1])
	expect("... both events are logged, once each", [count(s.event_log, "card_applied"), count(s.event_log, "sickened")], [1, 1])
	ev = CardEffectsScript.apply(s, 3, "scandal", sick_card)
	expect("drawn again while sick: no stacking, and it is said", [types(ev), ev[0]["skipped"], s.sick_left[3]], [["card_applied"], ["sick: A sick player can't be sickened again."], 1])
	ev = CardEffectsScript.apply(s, 4, "settlement", immune_card)
	expect("the Settlement card makes the drawer immune for 2 rounds", [types(ev), s.immune_left[4]], [["card_applied", "immunity_granted"], 2])
	ev = CardEffectsScript.apply(s, 4, "scandal", sick_card)
	expect("an immune player isn't sickened by the card", [ev[0]["skipped"], s.sick.get(4, false)], [["sick: They are immune for 2 more round(s)."], false])


func what_everyone_sees() -> void:
	var s := table()
	SicknessScript.sicken(s, 3, 2)
	s.immune_left[4] = 3
	var view: Dictionary = ViewsScript.state_view(s, 1)
	expect("who is sick, for how long and who is immune is public", [view["sick_left"], view["immune_left"], view["sick"][3]], [{3: 2}, {4: 3}, true])
	view["sick_left"][3] = 99
	expect("the view is a copy", s.sick_left[3], 2)


# --- helpers -----------------------------------------------------------------------------

func table() -> GameStateScript:
	return GameScript.new_game([1, 2, 3, 4, 5], 3)


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


func count(events: Array, type: String) -> int:
	var n: int = 0
	for event in events:
		if event["type"] == type:
			n += 1
	return n


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
