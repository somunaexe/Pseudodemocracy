class_name Elimination

# What happens when a player is eliminated. Today the only cause is debt, but every cause
# goes through eliminate().
#
# The estate (their cash and their debts) goes to the heir named in their will, whole and
# without a say: an heir cannot refuse. Without a usable will, the cash goes to the treasury
# (Article 29) and their debts disappear with them, so their creditors lose the money.
# A usable will is one that exists, is not on hold (Article 27), and names a living player
# other than the owner.
#
# Debts owed TO the dead player go to the heir too, or are cleared if there is no heir.
# Their union memberships end (Article 25).
#
# If the eliminated player is the Leader the seat becomes vacant (a new Leader is voted for).
#
# Not built yet: roles, the Nepo Baby debuff, and the election itself.
# See docs/design_decisions.md.

const GameStateScript = preload("res://scripts/game_state.gd")
const DebtScript = preload("res://scripts/debt.gd")
const LawScript = preload("res://scripts/law.gd")
const EventsScript = preload("res://scripts/events.gd")
const FlowScript = preload("res://scripts/amendment_flow.gd")


# Call at the END of a player's own turn. Counts a debt term and eliminates them if it was
# their last. Returns the events (empty when nothing happened).
static func end_turn(state: GameStateScript, player_id: int) -> Array:
	if DebtScript.end_of_turn(state, player_id):
		return eliminate(state, player_id, "debt")
	return []


static func eliminate(state: GameStateScript, player_id: int, reason: String) -> Array:
	var events: Array = [EventsScript.make("player_eliminated", {"player": player_id, "reason": reason})]
	state.eliminated[player_id] = true

	var will: Dictionary = state.wills.get(player_id, {})
	var heir: int = 0   # 0 = nobody (0 is the treasury's id, never a player)
	var void_reason: String = ""
	if not will.is_empty():
		heir = int(will["psd_heir"])
		if will["on_hold"]:
			void_reason = "the will was on hold"
		elif heir == player_id or not heir in state.player_ids or state.eliminated.get(heir, false):
			void_reason = "the named heir is not available"
		if void_reason != "":
			heir = 0
	state.wills.erase(player_id)
	if heir != 0:
		state.heirs[player_id] = heir
		events.append(EventsScript.make("will_read", {"testator": player_id, "heir": heir}))
	elif not will.is_empty():
		events.append(EventsScript.make("will_void", {"testator": player_id, "reason": void_reason}))

	# Debts owed TO them first, so no money is ever paid to a dead player.
	var claims_cleared: int = _reassign_claims(state, player_id, heir)

	var cash: int = int(state.psd.get(player_id, 0))
	state.psd[player_id] = 0
	var inherited: Array = state.debts.get(player_id, [])
	state.debts.erase(player_id)
	state.debt_terms[player_id] = 0

	var debt_taken: int = 0
	var debt_cleared: int = 0
	if heir != 0:
		if not state.debts.has(heir):
			state.debts[heir] = []
		for entry in inherited:
			if entry["creditor"] == heir:
				debt_cleared += entry["amount"]   # they would owe themselves
			else:
				state.debts[heir].append(entry)
				debt_taken += entry["amount"]
		DebtScript.receive(state, heir, cash)   # collects at once: cash pays the oldest debt first
	else:
		state.treasury += cash
		for entry in inherited:
			debt_cleared += entry["amount"]

	events.append(EventsScript.make("estate_settled", {
		"testator": player_id,
		"heir": heir,
		"cash": cash,
		"debt_taken_by_heir": debt_taken,
		"debt_cleared": debt_cleared,
		"claims_cleared": claims_cleared,
	}))
	events.append_array(_leave_unions(state, player_id))
	if player_id == state.leader_id:
		events.append_array(_vacate_seat(state))
	events.append_array(FlowScript.recheck(state))   # an amendment vote may now be complete
	return events


# The Leader is eliminated: the seat is empty until a new Leader is voted for (the election
# itself is not built yet) and an amendment in progress is abandoned. Its window stays used.
static func _vacate_seat(state: GameStateScript) -> Array:
	var events: Array = []
	if not state.amend.is_empty():
		state.amendment_record.append({
			"round": state.current_round, "leader": state.leader_id, "article_id": state.amend["article_id"],
			"outcome": "abandoned", "for": 0, "against": 0, "text": "",
		})
		state.amend = {}
		events.append(EventsScript.make("amendment_abandoned", {"reason": "the Leader was eliminated"}))
	state.leader_id = -1
	events.append(EventsScript.make("leader_vacant", {}))
	return events


# Debts that others owe the dead player move to the heir, or are cleared. Returns the amount cleared.
static func _reassign_claims(state: GameStateScript, dead_id: int, heir: int) -> int:
	var cleared: int = 0
	for debtor_id in state.debts:
		var entries: Array = state.debts[debtor_id]
		for i in range(entries.size() - 1, -1, -1):
			if entries[i]["creditor"] != dead_id:
				continue
			if heir == 0 or debtor_id == heir:
				cleared += entries[i]["amount"]   # no heir, or the heir would owe themselves
				entries.remove_at(i)
			else:
				entries[i]["creditor"] = heir
		if entries.is_empty():
			state.debt_terms[debtor_id] = 0
	return cleared


# Memberships end. A union left with one member dissolves (Article 11). Assumption: a union
# also dissolves if its unionizer is the one eliminated.
static func _leave_unions(state: GameStateScript, player_id: int) -> Array:
	var events: Array = []
	for union_id in state.unions.keys():
		var union: Dictionary = state.unions[union_id]
		if not player_id in union["members"]:
			continue
		union["members"].erase(player_id)
		if union["members"].size() <= LawScript.get_int(state, "unionDissolveAt") or union["owner"] == player_id:
			state.unions.erase(union_id)
			events.append(EventsScript.make("union_dissolved", {"union_id": union_id}))
	return events
