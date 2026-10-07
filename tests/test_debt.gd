extends SceneTree

const DebtScript = preload("res://scripts/debt.gd")
const GameStateScript = preload("res://scripts/game_state.gd")

const TREASURY = 0
var failures: int = 0


func _init() -> void:
	var s: GameStateScript

	# --- Paying, and partial payment
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

	s = make_state(20)
	expect("agreed payment to a player: 30 becomes debt", DebtScript.charge(s, 1, 2, 50), 30)
	expect("the player was paid what the debtor had", s.psd[2], 20)

	# --- FIFO: every debt is its own entry, oldest first
	s = make_state(0)
	DebtScript.charge(s, 1, TREASURY, 25)
	DebtScript.charge(s, 1, 2, 50)
	DebtScript.charge(s, 1, TREASURY, 5)
	expect("debts are not merged: three entries", s.debts[1].size(), 3)
	DebtScript.receive(s, 1, 30)
	expect("oldest debt (treasury 25) paid first", s.treasury, 25)
	expect("next debt (player 2) gets the rest", s.psd[2], 5)
	expect("50 still owed in total", DebtScript.total_debt(s, 1), 50)
	expect("player 2's debt is now the oldest", s.debts[1][0]["creditor"], 2)
	expect("no cash is kept while in debt", s.psd[1], 0)
	DebtScript.receive(s, 1, 200)
	expect("big payment clears everything", DebtScript.total_debt(s, 1), 0)
	expect("leftover cash is kept", s.psd[1], 150)

	# --- The bug that started this: cash must not sit beside debt
	s = make_state(0)
	DebtScript.charge(s, 1, TREASURY, 25)
	DebtScript.receive(s, 1, 500)
	expect("income clears the debt at once", DebtScript.total_debt(s, 1), 0)
	expect("rest of the income is kept", s.psd[1], 475)
	DebtScript.end_of_turn(s, 1)
	DebtScript.end_of_turn(s, 1)
	expect("rich player is never eliminated by old debt", DebtScript.end_of_turn(s, 1), false)

	# --- Chains and cycles
	s = make_state(0)
	DebtScript.charge(s, 1, 2, 10)
	DebtScript.charge(s, 2, 3, 10)
	DebtScript.receive(s, 1, 10)
	expect("chain: the money flows on to player 3", s.psd[3], 10)
	expect("chain: player 2 keeps nothing", s.psd[2], 0)
	expect("chain: all debts cleared", DebtScript.total_debt(s, 1) + DebtScript.total_debt(s, 2), 0)

	s = make_state(0)
	DebtScript.charge(s, 1, 2, 10)
	DebtScript.charge(s, 2, 1, 10)
	DebtScript.receive(s, 1, 10)
	expect("cycle ends: debts cleared", DebtScript.total_debt(s, 1) + DebtScript.total_debt(s, 2), 0)
	expect("cycle: player 1 ends with the 10", s.psd[1], 10)
	expect("cycle: player 2 ends with nothing", s.psd[2], 0)

	# --- Debt terms: counted at the end of the debtor's own turn; 3 then eliminated
	s = make_state(0)
	DebtScript.charge(s, 1, TREASURY, 25)
	expect("turn 1 in debt: not eliminated", DebtScript.end_of_turn(s, 1), false)
	expect("turn 2 in debt: not eliminated", DebtScript.end_of_turn(s, 1), false)
	expect("turn 3 in debt: the limit is reached", DebtScript.end_of_turn(s, 1), true)

	s = make_state(0)
	DebtScript.charge(s, 1, TREASURY, 25)
	DebtScript.end_of_turn(s, 1)
	DebtScript.end_of_turn(s, 1)
	expect("two terms counted", s.debt_terms[1], 2)
	DebtScript.receive(s, 1, 25)
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
