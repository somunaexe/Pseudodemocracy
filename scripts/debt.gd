class_name Debt

const GameStateScript = preload("res://scripts/game_state.gd")
const GameDataScript = preload("res://scripts/game_data.gd")

# Player ids start at 1, so 0 can mean "the treasury".
const TREASURY_ID := 0


static func total_debt(state: GameStateScript, player_id: int) -> int:
	var total: int = 0
	for entry in state.debts.get(player_id, []):
		total += entry["amount"]
	return total


# Cash minus debt. Negative means the player is in debt.
static func net_psd(state: GameStateScript, player_id: int) -> int:
	return int(state.psd.get(player_id, 0)) - total_debt(state, player_id)


# Make a payment. Partial payments are allowed: the player pays what they have and
# the rest becomes a debt to the same creditor. Returns the amount that became debt.
static func charge(state: GameStateScript, payer_id: int, creditor_id: int, amount: int) -> int:
	assert(amount >= 0, "can't charge a negative amount")
	var cash: int = int(state.psd.get(payer_id, 0))
	var paid: int = mini(cash, amount)
	state.psd[payer_id] = cash - paid
	_credit(state, creditor_id, paid)
	var owed: int = amount - paid
	if owed > 0:
		_add_debt(state, payer_id, creditor_id, owed)
	return owed


# Pay down a debt from cash, up to what the player has and what they owe that creditor.
# Returns how much was repaid. Clearing every debt resets the debt-term count.
static func repay(state: GameStateScript, debtor_id: int, creditor_id: int, amount: int) -> int:
	var cash: int = int(state.psd.get(debtor_id, 0))
	var entries: Array = state.debts.get(debtor_id, [])
	for i in entries.size():
		if entries[i]["creditor"] != creditor_id:
			continue
		var paid: int = mini(mini(cash, amount), entries[i]["amount"])
		entries[i]["amount"] -= paid
		state.psd[debtor_id] = cash - paid
		_credit(state, creditor_id, paid)
		if entries[i]["amount"] == 0:
			entries.remove_at(i)
		if total_debt(state, debtor_id) == 0:
			state.debt_terms[debtor_id] = 0
		return paid
	return 0


# Call at the END of a debtor's own turn. Counts one debt term if they still owe anything,
# and eliminates them when the count reaches the limit. Returns true if they were eliminated.
static func end_of_turn(state: GameStateScript, player_id: int) -> bool:
	if total_debt(state, player_id) == 0:
		state.debt_terms[player_id] = 0
		return false
	var terms: int = int(state.debt_terms.get(player_id, 0)) + 1
	state.debt_terms[player_id] = terms
	if terms >= GameDataScript.get_int("debtMaxTerms"):
		state.eliminated[player_id] = true
		return true
	return false


static func _credit(state: GameStateScript, creditor_id: int, amount: int) -> void:
	if creditor_id == TREASURY_ID:
		state.treasury += amount
	else:
		state.psd[creditor_id] = int(state.psd.get(creditor_id, 0)) + amount


static func _add_debt(state: GameStateScript, debtor_id: int, creditor_id: int, amount: int) -> void:
	if not state.debts.has(debtor_id):
		state.debts[debtor_id] = []
	for entry in state.debts[debtor_id]:
		if entry["creditor"] == creditor_id:
			entry["amount"] += amount
			return
	state.debts[debtor_id].append({"creditor": creditor_id, "amount": amount})
