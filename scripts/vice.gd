class_name Vice

# The Vice (handbook glossary): "A second Leader created by a card. A Vice is a Leader in every way, but each term
# served as Vice scores 1/2 round." The card is "the keys to the city" (Settlement).
#
# state.vice_id is the Vice (-1 for none). The rules, where the handbook is silent marked (assumed):
#   - There is at most one Vice. A new Vice replaces the old one. (assumed)
#   - The Vice draws a Leader card of their own (vice_type: President, Dictator or Commander), and it decides what the
#     Vice's amendments need, as for the Leader. (assumed)
#   - The Vice earns viceIncome (90) at the start of their own turn (the Leader earns 100). Both come on top of any role income.
#   - The Vice can amend the Constitution like the Leader but with windows of their own: they can propose in each window once
#     and pass it, and the Inauguration and Farewell wait for both of them. A Vice who arrives after the Inauguration has
#     lost that window. The Leader and the Vice are both left out of the vote on either's amendment. (assumed)
#   - A union, or a mob, can't recruit the Vice, as it can't recruit the Leader. (assumed)
#   - The Vice serves until the end of the term and then scores half a round (1 half-round; the Leader scores 2). The
#     Vice ends if the Leader is couped or eliminated, or the Vice is eliminated, and then scores nothing. (assumed)
#
# THE KEYS TO THE CITY: the player who draws it takes the Leader's role outright if their popularity is higher than the
# Leader's, and the ousted Leader is demoted to Vice (so scores 1/2 for the term, and the new Leader a full term at its
# end). Otherwise the drawer becomes Vice. The Leader themselves, or the Vice when they are not more popular, gets
# nothing. The new Leader keeps the Leader card (type) of the role they took.
#
# Like Roles and Sickness, nothing here logs: every function returns its events and the caller logs them.

const GameStateScript = preload("res://scripts/game_state.gd")
const PopularityScript = preload("res://scripts/popularity.gd")
const LeaderCardsScript = preload("res://scripts/leader_cards.gd")
const EventsScript = preload("res://scripts/events.gd")


static func is_vice(state: GameStateScript, player_id: int) -> bool:
	return player_id == state.vice_id and state.vice_id != -1


# Is the player the Leader or the Vice: someone with Leader powers.
static func is_leader_or_vice(state: GameStateScript, player_id: int) -> bool:
	return player_id == state.leader_id or is_vice(state, player_id)


# The Leader card (type) the player's Leader powers follow.
static func type_of(state: GameStateScript, player_id: int) -> int:
	return state.vice_type if is_vice(state, player_id) else state.leader_type


static func clear(state: GameStateScript) -> void:
	state.vice_id = -1
	for window in state.vice_windows_used:
		state.vice_windows_used[window] = false


# Make the player Vice, with a Leader card drawn for them. The caller checks that they are not the Leader.
static func appoint(state: GameStateScript, player_id: int) -> Array:
	assert(player_id != state.leader_id, "the Leader can't also be Vice")
	var replaced: int = state.vice_id if state.vice_id != player_id else -1
	clear(state)
	state.vice_id = player_id
	state.vice_type = LeaderCardsScript.draw(state)
	if state.term.get("phase", GameStateScript.TermPhase.NONE) != GameStateScript.TermPhase.INAUGURATION:
		state.vice_windows_used[GameStateScript.AmendWindow.INAUGURATION] = true   # it is over
	return [EventsScript.make("vice_appointed", {"vice": player_id, "vice_type": state.vice_type, "replaced": replaced})]


# The keys to the city, drawn by the player.
static func keys_to_the_city(state: GameStateScript, player_id: int) -> Array:
	var leader: int = state.leader_id
	if leader == -1 or player_id == leader:
		return [EventsScript.make("keys_no_effect", {"player": player_id, "reason": "they are the Leader" if player_id == leader else "there is no Leader"})]
	if PopularityScript.effective(state, player_id) > PopularityScript.effective(state, leader):
		var events: Array = [EventsScript.make("leader_swapped", {"new_leader": player_id, "old_leader": leader, "leader_type": state.leader_type})]
		state.vice_id = -1 if state.vice_id == player_id else state.vice_id   # the old Vice becomes the Leader: no longer Vice
		state.leader_id = player_id
		events.append_array(appoint(state, leader))
		return events
	if is_vice(state, player_id):
		return [EventsScript.make("keys_no_effect", {"player": player_id, "reason": "they are already Vice"})]
	return appoint(state, player_id)


# A player leaves the game. If they were the Vice there is none now. Returns whether they were.
static func remove_player(state: GameStateScript, player_id: int) -> bool:
	if not is_vice(state, player_id):
		return false
	clear(state)
	return true
