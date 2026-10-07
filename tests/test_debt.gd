extends SceneTree

const DebtScript = preload("res://scripts/debt.gd")
const GameStateScript = preload("res://scripts/game_state.gd")

const TREASURY = 0
var failures: int = 0


func _init() -> void:
	var s: GameStateScript

	s = make_state(100)
	expect("charge within means: nothing owed", DebtScript.charge(s, 1, TREASURY, 25), 0)
	expect("cash reduced", s.psd[1], 75)
	expect("treasury received it", s.treasury, 25)
	expect("net PSD is cash when no debt", DebtScript.net_psd(s, 1), 75)

	s = make_state(10)
	expect("partial payment: 15 becomes debt", DebtScript.charge(s, 1, TREASURY, 25), 15)
	expect("partial: cash is spent", s.psd[1], 0)
	expect("partial: treasury got what they had", s.treasury, 10)
	expect("partial: net PSD is -15", DebtScript.net_psd(s, 1), -15)
	DebtScript.charge(s, 1, TREASURY, 5)
	expect("same creditor merges into one entry", s.debts[1].size(), 1)
	expect("merged debt is 20", DebtScript.total_debt(s, 1), 20)
	DebtScript.charge(s, 1, 2, 50)
	expect("a second creditor is a separate entry", s.debts[1].size(), 2)
	expect("total debt across creditors", DebtScript.total_debt(s, 1), 70)

	# Repaying: partial, then full.
	s = make_state(0)
	DebtScript.charge(s, 1, TREASURY, 25)
	DebtScript.charge(s, 1, 2, 50)
	s.psd[1] = 30
	expect("repay treasury in full", DebtScript.repay(s, 1, TREASURY, 25), 25)
	expect("treasury got repaid", s.treasury, 25)
	expect("partial repay to player 2 limited by cash", DebtScript.repay(s, 1, 2, 50), 5)
	expect("player 2 received it", s.psd[2], 5)
	expect("45 still owed to player 2", DebtScript.total_debt(s, 1), 45)
	expect("repay a creditor you don't owe", DebtScript.repay(s, 1, 3, 10), 0)

	# Debt terms: counted at the end of the debtor's own turn; 3 terms then eliminated.
	s = make_state(0)
	DebtScript.charge(s, 1, TREASURY, 25)
	expect("turn 1 in debt: not eliminated", DebtScript.end_of_turn(s, 1), false)
	expect("turn 2 in debt: not eliminated", DebtScript.end_of_turn(s, 1), false)
	expect("turn 3 in debt: eliminated", DebtScript.end_of_turn(s, 1), true)
	expect("marked eliminated", s.eliminated[1], true)

	# Paying off resets the count.
	s = make_state(0)
	DebtScript.charge(s, 1, TREASURY, 25)
	DebtScript.end_of_turn(s, 1)
	DebtScript.end_of_turn(s, 1)
	expect("two terms counted", s.debt_terms[1], 2)
	s.psd[1] = 25
	DebtScript.repay(s, 1, TREASURY, 25)
	expect("paying off resets to 0", s.debt_terms[1], 0)
	DebtScript.charge(s, 1, TREASURY, 25)
	expect("falling back in: first term, not eliminated", DebtScript.end_of_turn(s, 1), false)
	expect("count restarted at 1", s.debt_terms[1], 1)

	s = make_state(100)
	expect("no debt: end of turn is safe", DebtScript.end_of_turn(s, 1), false)

	print("%d failure(s)" % failures)
	quit(1 if failures > 0 else 0)


func make_state(cash: int) -> GameStateScript:
	var s: GameStateScript = GameStateScript.new()
	s.psd = {1: cash, 2: 0, 3: 0}
	return s


func expect(label: String, actual: Variant, wanted: Variant) -> void:
	var ok: bool = actual == wanted
	if not ok:
		failures += 1
	print(("PASS " if ok else "FAIL ") + label + " -> " + str(actual))
