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
# If the eliminated player is the Leader the seat becomes vacant and a new Leader is voted for
# (an election with no exam, because there is nobody to write it).
#
# Every heir becomes a Nepo Baby (see Nepo).
#
# Their roles go to the role heir named in the will (by default the heir of the money), or are
# rescinded (see Roles). A role heir who isn't also the money heir is not a Nepo Baby.
# See docs/design_decisions.md.

const GameStateScript = preload("res://scripts/game_state.gd")
const DebtScript = preload("res://scripts/debt.gd")
const LawScript = preload("res://scripts/law.gd")
const RolesScript = preload("res://scripts/roles.gd")
const NepoScript = preload("res://scripts/nepo.gd")
const EventsScript = preload("res://scripts/events.gd")
const FlowScript = preload("res://scripts/amendment_flow.gd")
const ElectionScript = preload("res://scripts/election.gd")


# Call at the END of a player's own turn. Counts a debt term and eliminates them if it was
# their last. Returns the events (empty when nothing happened).
static func end_turn(state: GameStateScript, player_id: int) -> Array:
	if DebtScript.end_of_turn(state, player_id):
		return eliminate(state, player_id, "debt")
	return []


static func eliminate(state: GameStateScript, player_id: int, reason: String) -> Array:
	var events: Array = [EventsScript.make("player_eliminated", {"player": player_id, "reason": reason})]
	state.eliminated[player_id] = true
	state.nepo.erase(player_id)

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
	# Roles go to the role heir, who may differ from the heir of the money (Article 56). Without a
	# usable will, or if the named role heir isn't available, the roles are rescinded.
	var role_heir: int = 0
	if not will.is_empty() and not will["on_hold"]:
		var wanted: int = int(will.get("role_heir", will["psd_heir"]))
		if wanted != player_id and wanted in state.player_ids and not state.eliminated.get(wanted, false):
			role_heir = wanted
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
	events.append_array(RolesScript.settle_estate(state, player_id, role_heir))
	if heir != 0:
		events.append_array(NepoScript.become(state, heir))   # an heir cannot refuse, so every heir is one (Article 30)
	events.append_array(_leave_unions(state, player_id))
	_leave_term(state, player_id)

	# Every event is logged exactly once, in order. The election and the re-checks log their own,
	# so ours are written to the log first.
	var logged: int = 0
	if player_id == state.leader_id:
		# If an election is already under way the term was credited when it ended. Otherwise it was
		# cut short, which counts half a round (1 half-round), like a coup. It is kept for the
		# record only: an eliminated player can never win, so it never ranks.
		var mid_term: bool = state.election.is_empty()
		if mid_term:
			state.half_rounds[player_id] = int(state.half_rounds.get(player_id, 0)) + 1
		events.append_array(_vacate_seat(state))
		if mid_term:
			state.event_log.append_array(events)
			logged = events.size()
			events.append_array(ElectionScript.begin(state, "vacancy"))   # a new Leader is voted for
			logged = events.size()
	state.event_log.append_array(events.slice(logged))
	events.append_array(FlowScript.recheck(state))        # an amendment vote may now be complete
	events.append_array(ElectionScript.recheck(state))    # so may an exam or an election
	return events


# The Leader is eliminated: the seat is empty until a new Leader is voted for, the term ends,
# and an amendment in progress is abandoned. Its window stays used.
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
	state.term = {}   # the term ends with its Leader; the next one starts when a new Leader is installed
	events.append(EventsScript.make("leader_vacant", {}))
	return events


# A player who is out no longer waits for, or counts as having had, a turn.
static func _leave_term(state: GameStateScript, player_id: int) -> void:
	if not state.term.has("waiting"):
		return
	state.term["waiting"].erase(player_id)
	state.term["played"].erase(player_id)
	state.turns_played = state.term["played"].size()
	state.player_count = state.term["played"].size() + state.term["waiting"].size()


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
