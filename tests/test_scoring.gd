extends SceneTree

const ScoringScript = preload("res://scripts/scoring.gd")

var failures: int = 0


func _init() -> void:
	# Normal play: handbook formula (popularity + 50) x PSD.
	expect("90 x 100 = 9000", ScoringScript.tie_break_score(40, 100), 9000)
	expect("cancelled scores 0", ScoringScript.tie_break_score(-50, 5000), 0)
	expect("broke scores 0", ScoringScript.tie_break_score(0, 0), 0)
	better("same PSD: more popular wins", ScoringScript.tie_break_score(40, 100), ScoringScript.tie_break_score(-40, 100))

	# Debt: the case that was broken.
	better("any non-debtor beats any debtor", ScoringScript.tie_break_score(-50, 0), ScoringScript.tie_break_score(50, -1))
	better("smaller debt beats bigger debt", ScoringScript.tie_break_score(-40, -50), ScoringScript.tie_break_score(40, -100))
	expect("popularity no longer flips debtors", ScoringScript.tie_break_score(40, -100), ScoringScript.tie_break_score(-40, -100))

	print("%d failure(s)" % failures)
	quit(1 if failures > 0 else 0)


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
