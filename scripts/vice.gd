class_name Vice

# The Vice (handbook glossary): "A second Leader created by a card. A Vice is a Leader in every way, but each term
# served as Vice scores 1/2 round." The card is "the keys to the city" (Settlement).
#
# state.vice_id is the Vice (-1 for none). Agreed with the designer unless marked (assumed):
#   - There is at most one Vice. A new Vice replaces the old one. (assumed)
#   - The Vice has no Leader card of their own. They share the Leader's amendment windows, and AMEND TOGETHER: a
#     proposal by either needs the other's agreement (see AmendmentFlow). Both sit out the vote on it, and the
#     result moves both their popularity. The Leader's card decides if it stands.
#   - The Vice earns viceIncome (90) at the start of their own turn (the Leader earns 100).
#   - The Vice ends with the term, scoring half a round (1 half-round; the Leader scores 2).
#   - If the Leader is eliminated the Vice takes over as Leader and the term goes on.
#   - If the Leader is couped the Vice stays Vice for the new term, unless the new Leader draws a Dictator card, or the
#     Vice is the one who couped (then they are Leader).
#   - A union, or a mob, can't recruit the Vice, as it can't recruit the Leader. (assumed)
#   - A Vice who is sick, CANCELLED or out of the game is not needed to agree. (assumed)
#
# THE KEYS TO THE CITY: the player who draws it takes the Leader's role outright if their popularity is higher than the
# Leader's, and the ousted Leader is demoted to Vice (so scores 1/2 for the term, and the new Leader a full term at its
# end). Otherwise (equal popularity too) the drawer becomes Vice. The Leader themselves, or the Vice when they are not
# more popular, gets nothing. The new Leader keeps the Leader card (type) of the role they took.
#
# Like Roles and Sickness, nothing here logs: every function returns its events and the caller logs them.

const GameStateScript = preload("res://scripts/game_state.gd")
const SpecialCardsScript = preload("res://scripts/special_cards.gd")
const PopularityScript = preload("res://scripts/popularity.gd")
const EventsScript = preload("res://scripts/events.gd")


static func is_vice(state: GameStateScript, player_id: int) -> bool:
	return player_id == state.vice_id and state.vice_id != -1


# Is the player the Leader or the Vice: someone with Leader powers.
static func is_leader_or_vice(state: GameStateScript, player_id: int) -> bool:
	return player_id == state.leader_id or is_vice(state, player_id)


static func clear(state: GameStateScript) -> void:
	state.vice_id = -1
	_drop_offer_of(state)


# A proposal waiting for agreement can't outlive the pair that made it.
static func _drop_offer_of(state: GameStateScript) -> void:
	state.amend_offer = {}


# Make the player Vice. The caller checks that they are not the Leader.
static func appoint(state: GameStateScript, player_id: int) -> Array:
	assert(player_id != state.leader_id, "the Leader can't also be Vice")
	var replaced: int = state.vice_id if state.vice_id != player_id else -1
	clear(state)
	state.vice_id = player_id
	return [EventsScript.make("vice_appointed", {"vice": player_id, "replaced": replaced})]


# The keys to the city, drawn by the player.
static func keys_to_the_city(state: GameStateScript, player_id: int) -> Array:
	var leader: int = state.leader_id
	if leader == -1 or player_id == leader:
		return [EventsScript.make("keys_no_effect", {"player": player_id, "reason": "they are the Leader" if player_id == leader else "there is no Leader"})]
	if PopularityScript.effective(state, player_id) > PopularityScript.effective(state, leader):
		var events: Array = [EventsScript.make("leader_swapped", {"new_leader": player_id, "old_leader": leader, "leader_type": state.leader_type})]
		state.vice_id = -1 if state.vice_id == player_id else state.vice_id   # the old Vice becomes the Leader: no longer Vice
		state.leader_id = player_id
		events.append_array(SpecialCardsScript.leader_changed(state, leader, player_id))
		events.append_array(appoint(state, leader))
		return events
	if is_vice(state, player_id):
		return [EventsScript.make("keys_no_effect", {"player": player_id, "reason": "they are already Vice"})]
	return appoint(state, player_id)


# The Leader has left the game and there is a Vice in it: the Vice becomes Leader and the term goes on.
static func succeed(state: GameStateScript) -> Array:
	var old: int = state.leader_id
	state.leader_id = state.vice_id
	clear(state)
	var events: Array = [EventsScript.make("vice_succeeded", {"leader": state.leader_id, "old_leader": old})]
	events.append_array(SpecialCardsScript.leader_changed(state, old, state.leader_id))
	return events


# The new Leader of a coup is in: the Vice stays, unless they are the new Leader or the card drawn is a Dictator.
static func after_coup(state: GameStateScript, winner: int) -> Array:
	if state.vice_id == -1:
		return []
	if winner == state.vice_id:
		clear(state)
		return [EventsScript.make("vice_removed", {"vice": winner, "reason": "they are the new Leader"})]
	if state.leader_type == GameStateScript.LeaderType.DICTATOR:
		var gone: int = state.vice_id
		clear(state)
		return [EventsScript.make("vice_removed", {"vice": gone, "reason": "the new Leader is a Dictator"})]
	return []


# A player leaves the game. If they were the Vice there is none now. Returns whether they were.
static func remove_player(state: GameStateScript, player_id: int) -> bool:
	if not is_vice(state, player_id):
		return false
	clear(state)
	return true
