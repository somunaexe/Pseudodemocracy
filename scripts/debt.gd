class_name Debt

const GameStateScript = preload("res://scripts/game_state.gd")
const GameDataScript = preload("res://scripts/game_data.gd")

# Player ids start at 1, so 0 can mean "the treasury".
const TREASURY_ID := 0

# How debt works:
#  - Any payment a player can't cover becomes debt: they pay what they have, owe the rest.
#    (Forced charges and agreed ones behave the same, as in real life.)
#  - Every debt is its own entry, kept in the order it was incurred.
#  - Money is collected the moment it arrives, oldest debt first (FIFO).
#  - So a player with debt never holds cash: debt > 0 means cash == 0.
# All income must go through receive(), or it will skip collection.


static func total_debt(state: GameStateScript, player_id: int) -> int:
	var total: int = 0
	for entry in state.debts.get(player_id, []):
		total += entry["amount"]
	return total


# Cash minus debt. Negative means the player is in debt.
static func net_psd(state: GameStateScript, player_id: int) -> int:
	return int(state.psd.get(player_id, 0)) - total_debt(state, player_id)


# Make a payment. The player pays what they have; whatever is left becomes a new debt to
# that creditor, added at the back of their queue. Returns the amount that became debt.
static func charge(state: GameStateScript, payer_id: int, creditor_id: int, amount: int) -> int:
	assert(amount >= 0, "can't charge a negative amount")
	var cash: int = int(state.psd.get(payer_id, 0))
	var paid: int = mini(cash, amount)
	state.psd[payer_id] = cash - paid
	_credit(state, creditor_id, paid)
	var owed: int = amount - paid
	if owed > 0:
		if not state.debts.has(payer_id):
			state.debts[payer_id] = []
		state.debts[payer_id].append({"creditor": creditor_id, "amount": owed})
	return owed


# Give a player money (income, a card, a payment from someone else). Their debts are
# paid first, oldest to newest; only what is left stays in their hand.
static func receive(state: GameStateScript, player_id: int, amount: int) -> void:
	assert(amount >= 0, "can't receive a negative amount")
	state.psd[player_id] = int(state.psd.get(player_id, 0)) + amount
	_collect(state, player_id)


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


# Pay the oldest debt first until the cash or the debts run out. State is updated before
# each creditor is paid, because paying a creditor may in turn pay off the creditor's debts.
# That always ends: every step removes debt from the system.
static func _collect(state: GameStateScript, debtor_id: int) -> void:
	var entries: Array = state.debts.get(debtor_id, [])
	while not entries.is_empty() and int(state.psd.get(debtor_id, 0)) > 0:
		var entry: Dictionary = entries[0]
		var cash: int = int(state.psd[debtor_id])
		var paid: int = mini(cash, entry["amount"])
		var creditor_id: int = entry["creditor"]
		entry["amount"] -= paid
		state.psd[debtor_id] = cash - paid
		if entry["amount"] == 0:
			entries.remove_at(0)
		_credit(state, creditor_id, paid)
	if entries.is_empty():
		state.debt_terms[debtor_id] = 0


static func _credit(state: GameStateScript, creditor_id: int, amount: int) -> void:
	if creditor_id == TREASURY_ID:
		state.treasury += amount
	else:
		receive(state, creditor_id, amount)
