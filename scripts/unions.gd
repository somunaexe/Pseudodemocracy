class_name Unions

# Unions of Activists (peaceful) and Agberos (violent) (handbook Part 6, Activists & Agberos, Articles 7 to 17).
#
# A union is formed by playing a union card (a Settlement card kept in the hand). The player who plays it is the
# Unionizer (a Capon, for an Agbero mob) and its first member: it starts at 1, "recruiting".
#
# state.unions: union id -> { "type": UnionType, "owner": the Unionizer, "members": [ids, owner first],
#                              "confront_used": bool }
#
# A player is in at most one union ("can't recruit ... a member of another union", Article 8), so a player who
# already belongs to one can't found another.
#
# Like Roles, nothing here writes to the event log: every function returns its events and the caller logs them.

const GameStateScript = preload("res://scripts/game_state.gd")
const EventsScript = preload("res://scripts/events.gd")

const TYPES := {"activist": GameStateScript.UnionType.ACTIVIST, "agbero": GameStateScript.UnionType.AGBERO}


# The union this player belongs to (as Unionizer or member), or -1.
static func union_of(state: GameStateScript, player_id: int) -> int:
	for id in state.unions:
		if player_id in state.unions[id]["members"]:
			return id
	return -1


# Why this player can't found a union now, or "".
static func problem_founding(state: GameStateScript, player_id: int) -> String:
	if not player_id in state.player_ids or state.eliminated.get(player_id, false):
		return "You are not in the game."
	if union_of(state, player_id) != -1:
		return "You are already in a union."
	return ""


# Found a union of this type ("activist" or "agbero"). The caller checks problem_founding first.
static func found(state: GameStateScript, player_id: int, type_name: String) -> Array:
	assert(type_name in TYPES, "no such union type '%s'" % type_name)
	assert(problem_founding(state, player_id) == "", "found() needs a player who can found a union")
	var id: int = 1
	for existing in state.unions:
		id = maxi(id, int(existing) + 1)
	state.unions[id] = {"type": TYPES[type_name], "owner": player_id, "members": [player_id], "confront_used": false}
	return [EventsScript.make("union_founded", {"union_id": id, "type": state.unions[id]["type"], "unionizer": player_id})]
