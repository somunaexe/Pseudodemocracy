class_name Coup

# Coups (handbook Part 3, Coups). "A coup can happen at any point during any term."
#
#   { "type": "coup" }                    attempt a coup
#   { "type": "coup", "deal": true }      negotiate a deal instead
#   (either may add "role": "Doctor", to say which of their coup cards to use; otherwise the lowest-numbered)
#
# To attempt a coup a player (not the Leader) needs:
#   - 300 PSD in hand (coupCost) and a COUP CARD: a role card with a coup sticker (see Roles; only they can see
#     which of their cards have one). A CANCELLED player has no roles, so can't coup.
#   - not to be barred from coups for a term by a Scandal card (coup_ban), nor in a truce with the Leader (Rivals).
#   - to be at least coupGap (20) points more popular than the Leader (effective popularity) for the coup to SUCCEED. So
#     a Leader above +30 can't be couped at all.
# If it FAILS (they are not 20 ahead): they lose the coup card and the 300 PSD, and nothing else happens: the sticker
# moves and the 300 goes to the treasury.
# If it succeeds:
#   - the challenger pays the 300 to the treasury, and the sticker moves from the card they used to another role
#     card, chosen at random;
#   - the round stops at once: the couped Leader scores HALF a round (not a full one), a Peace Accord with them costs
#     its partner popularity (Rivals), the levy band shifts on
#     their popularity at that moment (Article 5), sickness and charges move on a round (RoundEnd), and anything
#     under way in the term (an amendment, a performance) ends with it;
#   - there is no exam and no vote: the challenger draws a Leader role card and starts a new term, and takes the
#     first turn of it (Election.install_leader with how = "coup").
# A DEAL: the challenger negotiates instead and loses ONLY the coup card: the sticker moves as above, they keep
# their 300 PSD, and there is no coup. (The deal itself is the table's.)
#
# Every event this file creates is logged here, once (the events of the larger steps it calls log themselves).

const GameStateScript = preload("res://scripts/game_state.gd")
const GameDataScript = preload("res://scripts/game_data.gd")
const DebtScript = preload("res://scripts/debt.gd")
const RolesScript = preload("res://scripts/roles.gd")
const RivalsScript = preload("res://scripts/rivals.gd")
const PopularityScript = preload("res://scripts/popularity.gd")
const ElectionScript = preload("res://scripts/election.gd")
const LevyBandScript = preload("res://scripts/levy_band.gd")
const RoundEndScript = preload("res://scripts/round_end.gd")
const EventsScript = preload("res://scripts/events.gd")


static func handle(state: GameStateScript, player_id: int, command: Dictionary) -> Array:
	var problem: String = _problem_with(state, player_id)
	if problem != "":
		return [_reject(player_id, problem)]
	var deal = command.get("deal", false)
	if typeof(deal) != TYPE_BOOL:
		return [_reject(player_id, "Say deal true or false.")]
	var card: int = _coup_card(state, player_id, command.get("role", null))
	if card == -1:
		return [_reject(player_id, "You don't hold a coup card." if not command.has("role") else "That isn't one of your coup cards.")]
	if deal:
		return _deal(state, player_id, card)
	var gap: int = GameDataScript.get_int("coupGap")
	var challenger_pop: int = PopularityScript.effective(state, player_id)
	var leader_pop: int = PopularityScript.effective(state, state.leader_id)
	if challenger_pop - leader_pop < gap:
		return _fail(state, player_id, card, challenger_pop, leader_pop)
	return _succeed(state, player_id, card, challenger_pop, leader_pop)


# Why this player can't attempt a coup (or deal) now, or "".
static func _problem_with(state: GameStateScript, player_id: int) -> String:
	if not player_id in state.player_ids or state.eliminated.get(player_id, false):
		return "You are not in the game."
	if state.term.is_empty() or not state.election.is_empty() or state.leader_id == -1:
		return "A coup can only be made during a term."
	if player_id == state.leader_id:
		return "The Leader can't coup themselves."
	if RolesScript.is_cancelled(state, player_id):
		return "CANCELLED players have no roles, so no coup card."
	if state.frozen.has(player_id):
		return "Your roles are frozen by corruption, so you have no coup card."
	if state.coup_ban.get(player_id, 0) > 0:
		return "You can't attempt a coup for %d more round(s)." % state.coup_ban[player_id]
	if RivalsScript.in_truce(state, player_id, state.leader_id):
		return "You and the Leader agreed not to coup each other this round."
	var cost: int = GameDataScript.get_int("coupCost")
	if int(state.psd.get(player_id, 0)) < cost:
		return "You need %d PSD in hand for a coup." % cost
	return ""


# The card to use: the one of the role they name, or their lowest-numbered coup card. -1 if there is none.
static func _coup_card(state: GameStateScript, player_id: int, role: Variant) -> int:
	var cards: Array = RolesScript.coup_cards(state, player_id)
	if role != null:
		if typeof(role) != TYPE_STRING:
			return -1
		for entry in cards:
			if entry[1] == role:
				return entry[0]
		return -1
	return -1 if cards.is_empty() else cards[0][0]


static func _deal(state: GameStateScript, player_id: int, card: int) -> Array:
	RolesScript.move_sticker(state, card)
	return [_log(state, "coup_deal", {"challenger": player_id, "leader": state.leader_id})]


# The coup fails: the challenger loses the coup card (the sticker moves) and the 300 PSD (to the treasury). That's all.
static func _fail(state: GameStateScript, challenger: int, card: int, challenger_pop: int, leader_pop: int) -> Array:
	var cost: int = GameDataScript.get_int("coupCost")
	DebtScript.charge(state, challenger, DebtScript.TREASURY_ID, cost)   # they had the cash: nothing becomes debt
	RolesScript.move_sticker(state, card)
	return [_log(state, "coup_failed", {"challenger": challenger, "leader": state.leader_id, "challenger_popularity": challenger_pop, "leader_popularity": leader_pop, "paid": cost})]


static func _succeed(state: GameStateScript, challenger: int, card: int, challenger_pop: int, leader_pop: int) -> Array:
	var old_leader: int = state.leader_id
	var cost: int = GameDataScript.get_int("coupCost")
	DebtScript.charge(state, challenger, DebtScript.TREASURY_ID, cost)   # they had the cash: nothing becomes debt
	RolesScript.move_sticker(state, card)
	var events: Array = [_log(state, "coup_succeeded", {"challenger": challenger, "leader": old_leader, "challenger_popularity": challenger_pop, "leader_popularity": leader_pop, "paid": cost})]

	# The round stops. The couped Leader scores half a round instead of a full one.
	state.half_rounds[old_leader] = int(state.half_rounds.get(old_leader, 0)) + 1
	events.append_array(LevyBandScript.shift_at_term_end(state))   # logs its own event
	events.append_array(_log_all(state, RivalsScript.accord_penalties(state, old_leader)))   # a Peace Accord with the couped Leader
	events.append_array(_log_all(state, RoundEndScript.run(state)))
	if not state.amend.is_empty():
		state.amendment_record.append({"round": state.current_round, "leader": old_leader, "article_id": state.amend["article_id"], "outcome": "abandoned", "for": 0, "against": 0, "text": ""})
		events.append(_log(state, "amendment_abandoned", {"reason": "the Leader was couped"}))
	state.term = {}
	state.election = {}
	events.append_array(_log_all(state, ElectionScript.install_leader(state, challenger, "coup")))
	return events


static func _log_all(state: GameStateScript, events: Array) -> Array:
	for event in events:
		state.event_log.append(event)
	return events


static func _log(state: GameStateScript, type: String, data: Dictionary) -> Dictionary:
	var event: Dictionary = EventsScript.make(type, data)
	state.event_log.append(event)
	return event


static func _reject(player_id: int, reason: String) -> Dictionary:
	return EventsScript.make("rejected", {"reason": reason}, [player_id])
