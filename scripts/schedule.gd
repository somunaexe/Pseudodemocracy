class_name Schedule

# Things cards set up that happen at the end of later rounds (state.schedule, public). Each entry has a "kind":
#   stipend   { "player", "source": "treasury" | "leader", "amount", "from", "until" (-1 = no end), "while_popular": bool }
#             paid at the end of each round from `from` to `until`. With while_popular the money stops for good the first time
#             the player's popularity is 0 or lower. A "leader" source is whoever leads at that moment (nothing if it is the
#             player, or nobody).
#   penalty   { "player", "popularity", "from", "until", "until_apology": bool }   popularity lost at the end of each round
#   repay     { "borrower", "lender", "amount", "due" }   at the end of round `due` the borrower pays the lender (debt if short)
# "from" and "until" are rounds, worked out when the card is drawn ("the next 2 terms" is the 2 rounds after this one).
# Like Roles and Sickness, nothing here logs: end_of_round returns its events and the caller (RoundEnd) logs them.

const GameStateScript = preload("res://scripts/game_state.gd")
const DebtScript = preload("res://scripts/debt.gd")
const PopularityScript = preload("res://scripts/popularity.gd")
const EventsScript = preload("res://scripts/events.gd")


static func add(state: GameStateScript, entry: Dictionary) -> void:
	state.schedule.append(entry)


static func stipend(state: GameStateScript, player_id: int, source: String, amount: int, starts: int, rounds: int, while_popular: bool = false) -> void:
	add(state, {"kind": "stipend", "player": player_id, "source": source, "amount": amount, "from": state.current_round + starts,
		"until": -1 if rounds < 0 else state.current_round + starts + rounds - 1, "while_popular": while_popular})


static func penalty(state: GameStateScript, player_id: int, popularity: int, starts: int, rounds: int, until_apology: bool) -> void:
	add(state, {"kind": "penalty", "player": player_id, "popularity": popularity, "from": state.current_round + starts,
		"until": state.current_round + starts + rounds - 1, "until_apology": until_apology})


static func repay(state: GameStateScript, borrower: int, lender: int, amount: int, rounds_from_now: int) -> void:
	add(state, {"kind": "repay", "borrower": borrower, "lender": lender, "amount": amount, "due": state.current_round + rounds_from_now})


# The penalty of this player ends (they apologised and the table accepted).
static func end_penalties(state: GameStateScript, player_id: int) -> int:
	var ended: int = 0
	var kept: Array = []
	for entry in state.schedule:
		if entry["kind"] == "penalty" and entry["player"] == player_id and entry["until_apology"]:
			ended += 1
		else:
			kept.append(entry)
	state.schedule = kept
	return ended


static func has_apology_penalty(state: GameStateScript, player_id: int) -> bool:
	for entry in state.schedule:
		if entry["kind"] == "penalty" and entry["player"] == player_id and entry["until_apology"]:
			return true
	return false


# A round ends (state.current_round is the round that is ending): whatever is due is done, in the order it was set up.
static func end_of_round(state: GameStateScript) -> Array:
	var events: Array = []
	var kept: Array = []
	var round_now: int = state.current_round
	for entry in state.schedule:
		var done: bool = false
		match entry["kind"]:
			"stipend":
				if round_now >= int(entry["from"]):
					events.append_array(_pay_stipend(state, entry))
				done = (int(entry["until"]) != -1 and round_now >= int(entry["until"])) or entry.get("stopped", false)
			"penalty":
				if round_now >= int(entry["from"]):
					var before: int = PopularityScript.effective(state, entry["player"])
					PopularityScript.change_base(state, entry["player"], int(entry["popularity"]))
					events.append(EventsScript.make("penalty_applied", {"player": entry["player"], "popularity": PopularityScript.effective(state, entry["player"]) - before}))
				done = round_now >= int(entry["until"])
			"repay":
				if round_now >= int(entry["due"]):
					var owed: int = DebtScript.charge(state, entry["borrower"], entry["lender"], int(entry["amount"]))
					events.append(EventsScript.make("loan_repaid", {"borrower": entry["borrower"], "lender": entry["lender"], "amount": entry["amount"], "new_debt": owed}))
					done = true
		if not done:
			kept.append(entry)
	state.schedule = kept
	return events


static func _pay_stipend(state: GameStateScript, entry: Dictionary) -> Array:
	var player: int = entry["player"]
	if state.eliminated.get(player, false):
		entry["stopped"] = true
		return []
	if entry["while_popular"] and PopularityScript.effective(state, player) <= 0:
		entry["stopped"] = true   # the money stops for good
		return [EventsScript.make("stipend_stopped", {"player": player, "amount": entry["amount"]})]
	var amount: int = int(entry["amount"])
	if entry["source"] == "treasury":
		var paid: int = mini(amount, state.treasury)
		state.treasury -= paid
		DebtScript.receive(state, player, paid)
		return [EventsScript.make("stipend_paid", {"player": player, "source": "treasury", "amount": paid, "short": amount - paid})]
	var leader: int = state.leader_id
	if leader == -1 or leader == player or state.eliminated.get(leader, false):
		return [EventsScript.make("stipend_missed", {"player": player, "reason": "there is no one else leading"})]
	var owed: int = DebtScript.charge(state, leader, player, amount)
	return [EventsScript.make("stipend_paid", {"player": player, "source": "leader", "payer": leader, "amount": amount - owed, "new_debt": owed})]


# A player leaves the game: nothing more is owed to or by them.
static func remove_player(state: GameStateScript, player_id: int) -> void:
	state.schedule = state.schedule.filter(func(entry): return entry.get("player", 0) != player_id and entry.get("borrower", 0) != player_id and entry.get("lender", 0) != player_id)
