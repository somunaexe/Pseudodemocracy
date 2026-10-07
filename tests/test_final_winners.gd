extends SceneTree

const ScoringScript = preload("res://scripts/scoring.gd")
const DebtScript = preload("res://scripts/debt.gd")
const GameStateScript = preload("res://scripts/game_state.gd")

var failures: int = 0


func _init() -> void:
	var s: GameStateScript

	s = make_state()
	ids("nobody eliminated: most rounds wins", ScoringScript.final_winners(s), [1])

	s = make_state()
	s.eliminated[1] = true
	ids("eliminated player with the most rounds can't win", ScoringScript.final_winners(s), [2])

	s = make_state()
	s.eliminated[1] = true
	s.eliminated[2] = true
	ids("next best takes it when two are out", ScoringScript.final_winners(s), [3])

	s = make_state()
	for id in [1, 2, 3]:
		s.eliminated[id] = true
	ids("everyone eliminated: no winner", ScoringScript.final_winners(s), [])

	# End to end: debt eliminates the front-runner, who then can't win.
	s = make_state()
	s.psd[1] = 0
	DebtScript.charge(s, 1, DebtScript.TREASURY_ID, 25)
	DebtScript.end_of_turn(s, 1)
	DebtScript.end_of_turn(s, 1)
	ids("still in the game after 2 debt terms", ScoringScript.final_winners(s), [1])
	DebtScript.end_of_turn(s, 1)
	ids("eliminated by debt after the 3rd term", ScoringScript.final_winners(s), [2])

	# Level on rounds: the debtor loses to the one with cash.
	s = make_state()
	s.half_rounds = {1: 6, 2: 6, 3: 0}
	s.psd = {1: 0, 2: 10, 3: 0}
	DebtScript.charge(s, 1, DebtScript.TREASURY_ID, 25)
	ids("level on rounds: debtor loses to the player with cash", ScoringScript.final_winners(s), [2])

	print("%d failure(s)" % failures)
	quit(1 if failures > 0 else 0)


func make_state() -> GameStateScript:
	var s: GameStateScript = GameStateScript.new()
	s.player_ids = [1, 2, 3]
	s.half_rounds = {1: 8, 2: 6, 3: 2}
	s.popularity = {1: 0, 2: 0, 3: 0}
	s.psd = {1: 100, 2: 100, 3: 100}
	return s


func ids(label: String, actual: Array, wanted: Array) -> void:
	var a: Array = actual.duplicate()
	a.sort()
	var ok: bool = a == wanted
	if not ok:
		failures += 1
	print(("PASS " if ok else "FAIL ") + label + " -> " + str(a))
