extends SceneTree

const ScoringScript = preload("res://scripts/scoring.gd")

var failures: int = 0


func _init() -> void:
	# --- The score itself
	expect("91 x 100 = 9100", ScoringScript.tie_break_score(40, 100), 9100)
	expect("cancelled still scores 1 x PSD", ScoringScript.tie_break_score(-50, 5000), 5000)
	expect("broke scores 0", ScoringScript.tie_break_score(0, 0), 0)
	better("same PSD: more popular wins", ScoringScript.tie_break_score(40, 100), ScoringScript.tie_break_score(-40, 100))
	better("cancelled: richer beats poorer", ScoringScript.tie_break_score(-50, 500), ScoringScript.tie_break_score(-50, 100))
	better("any non-debtor beats any debtor", ScoringScript.tie_break_score(-50, 0), ScoringScript.tie_break_score(50, -1))
	better("smaller debt beats bigger debt", ScoringScript.tie_break_score(-40, -50), ScoringScript.tie_break_score(40, -100))
	expect("popularity doesn't flip debtors", ScoringScript.tie_break_score(40, -100), ScoringScript.tie_break_score(-40, -100))

	# --- Who wins: rounds first, then the score, then popularity
	ids("more rounds beat a better score",
		ScoringScript.winners([p(1, 6, -50, 10), p(2, 4, 50, 9000)]), [1])
	ids("a debtor with more rounds beats a rich player with fewer",
		ScoringScript.winners([p(1, 6, 0, -100), p(2, 4, 50, 9000)]), [1])
	ids("half rounds count: 3 rounds beat 2.5",
		ScoringScript.winners([p(1, 5, 50, 9000), p(2, 6, 0, 0)]), [2])
	ids("level on rounds: higher score wins",
		ScoringScript.winners([p(1, 6, 40, 100), p(2, 6, 40, 200)]), [2])
	ids("non-debtor beats debtor on a level count",
		ScoringScript.winners([p(1, 6, 50, -10), p(2, 6, -50, 0)]), [2])
	ids("smaller debt wins on a level count",
		ScoringScript.winners([p(1, 6, 50, -100), p(2, 6, -50, -20)]), [2])

	# --- The cases a plain product can't separate
	ids("both at 0 PSD: popularity decides",
		ScoringScript.winners([p(1, 6, -20, 0), p(2, 6, 10, 0)]), [2])
	ids("equal debts: popularity decides",
		ScoringScript.winners([p(1, 6, -20, -80), p(2, 6, 30, -80)]), [2])
	ids("equal products (91 x 100 = 70 x 130): popularity decides",
		ScoringScript.winners([p(1, 6, 19, 130), p(2, 6, 40, 100)]), [2])

	# --- Genuine ties and edges
	ids("identical entries share the win",
		ScoringScript.winners([p(1, 6, 10, 100), p(2, 6, 10, 100)]), [1, 2])
	ids("only the tied-for-first are returned",
		ScoringScript.winners([p(1, 6, 10, 100), p(2, 4, 50, 900), p(3, 6, 10, 100)]), [1, 3])
	ids("input order doesn't matter",
		ScoringScript.winners([p(3, 6, 10, 100), p(2, 4, 50, 900), p(1, 6, 10, 100)]), [1, 3])
	ids("one player wins", ScoringScript.winners([p(7, 2, 0, 0)]), [7])
	ids("nobody, nobody wins", ScoringScript.winners([]), [])

	print("%d failure(s)" % failures)
	quit(1 if failures > 0 else 0)


func p(id: int, half_rounds: int, popularity: int, net_psd: int) -> Dictionary:
	return {"id": id, "half_rounds": half_rounds, "popularity": popularity, "net_psd": net_psd}


func expect(label: String, actual: int, wanted: int) -> void:
	var ok: bool = actual == wanted
	if not ok:
		failures += 1
	print(("PASS " if ok else "FAIL ") + label + " -> " + str(actual))


func better(label: String, winner: int, loser: int) -> void:
	var ok: bool = winner > loser
	if not ok:
		failures += 1
	print(("PASS " if ok else "FAIL ") + label + " -> " + str(winner) + " > " + str(loser))


func ids(label: String, actual: Array, wanted: Array) -> void:
	var a: Array = actual.duplicate()
	a.sort()
	var ok: bool = a == wanted
	if not ok:
		failures += 1
	print(("PASS " if ok else "FAIL ") + label + " -> " + str(a))
