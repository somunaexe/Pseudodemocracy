class_name Roles

# Role cards: Doctor, Lawyer, Secret Agent, Activist, Agbero (data/game_data.json). There are
# roleCopies (5) of each, so at most 5 players can hold a given role at once. A player can hold
# several different roles (they stack, and each earns its own income, see Income) but never two of
# the same. A player with no role is a Civilian: there is no Civilian card.
#
# Everyone can see who holds which roles (see Views). What stays hidden is whether a role card has a
# coup sticker; that is for coups to keep, server-only.
#
# This file only holds and moves the cards. What each role can DO is not built yet (see
# docs/design_decisions.md): the one rule shared by all of them is can_use_power().
#
# Like Nepo, nothing here writes to the event log: every function returns its events and the caller
# logs them, so each event is logged exactly once, by whoever is running the larger step.

const GameStateScript = preload("res://scripts/game_state.gd")
const GameDataScript = preload("res://scripts/game_data.gd")
const EventsScript = preload("res://scripts/events.gd")


static func names() -> Array:
	return GameDataScript.values()["components"]["roleCards"].duplicate()


static func copies() -> int:
	return int(GameDataScript.values()["components"]["roleCopies"])


# --- who holds what ----------------------------------------------------------------------

static func held(state: GameStateScript, player_id: int) -> Array:
	return state.roles.get(player_id, []).duplicate()


static func has(state: GameStateScript, player_id: int, role: String) -> bool:
	return role in state.roles.get(player_id, [])


static func is_civilian(state: GameStateScript, player_id: int) -> bool:
	return state.roles.get(player_id, []).is_empty()


static func holders(state: GameStateScript, role: String) -> Array:
	var result: Array = []
	for id in state.player_ids:
		if has(state, id, role):
			result.append(id)
	return result


static func copies_left(state: GameStateScript, role: String) -> int:
	return copies() - holders(state, role).size()


# --- giving and taking cards -------------------------------------------------------------

# Why this player can't be given this role right now, or "" if they can.
static func problem_granting(state: GameStateScript, player_id: int, role: String) -> String:
	if not role in names():
		return "There is no role called '%s'." % role
	if not player_id in state.player_ids or state.eliminated.get(player_id, false):
		return "That player is not in the game."
	if has(state, player_id, role):
		return "They already hold that role."
	if copies_left(state, role) <= 0:
		return "All %d %s cards are taken." % [copies(), role]
	return ""


# Give the player the role card. The caller checks problem_granting first.
static func grant(state: GameStateScript, player_id: int, role: String) -> Array:
	assert(problem_granting(state, player_id, role) == "", "grant() needs a role that can be granted")
	if not state.roles.has(player_id):
		state.roles[player_id] = []
	state.roles[player_id].append(role)
	return [EventsScript.make("role_gained", {"player": player_id, "role": role})]


# Take one role card from the player (it goes back in the box). Does nothing if they don't hold it.
static func remove(state: GameStateScript, player_id: int, role: String) -> Array:
	if not has(state, player_id, role):
		return []
	state.roles[player_id].erase(role)
	if state.roles[player_id].is_empty():
		state.roles.erase(player_id)
	return [EventsScript.make("role_lost", {"player": player_id, "role": role})]


# The player becomes a Civilian.
static func clear(state: GameStateScript, player_id: int) -> Array:
	var events: Array = []
	for role in held(state, player_id):
		events.append_array(remove(state, player_id, role))
	return events


# Two players exchange everything they hold (a card that says "swap roles").
static func swap(state: GameStateScript, a: int, b: int) -> Array:
	assert(a != b, "a player can't swap with themselves")
	var mine: Array = held(state, a)
	var theirs: Array = held(state, b)
	state.roles.erase(a)
	state.roles.erase(b)
	if not theirs.is_empty():
		state.roles[a] = theirs
	if not mine.is_empty():
		state.roles[b] = mine
	return [EventsScript.make("roles_swapped", {"a": a, "b": b, "a_now": held(state, a), "b_now": held(state, b)})]


# --- elimination -------------------------------------------------------------------------

# An eliminated player's roles go to their role heir, or are rescinded if there is none. A role the
# heir already holds can't be held twice: that card goes back in the box. heir 0 means nobody.
static func settle_estate(state: GameStateScript, dead_id: int, heir: int) -> Array:
	var roles: Array = held(state, dead_id)
	if roles.is_empty():
		return []
	state.roles.erase(dead_id)
	if heir == 0:
		return [EventsScript.make("roles_rescinded", {"player": dead_id, "roles": roles})]
	var received: Array = []
	var returned: Array = []
	for role in roles:
		if has(state, heir, role):
			returned.append(role)
		else:
			if not state.roles.has(heir):
				state.roles[heir] = []
			state.roles[heir].append(role)
			received.append(role)
	return [EventsScript.make("roles_inherited", {"testator": dead_id, "heir": heir, "roles": received, "returned_to_box": returned})]


# --- powers ------------------------------------------------------------------------------

# Why this player can't use this role's power now, or "" if they can. Every role shares these rules:
# you must hold it, be in the game, and not be sick (Article 17: sick players can't use role powers).
# Later: a role card frozen by a card or by corruption.
static func can_use_power(state: GameStateScript, player_id: int, role: String) -> String:
	if not has(state, player_id, role):
		return "You don't hold the %s role." % role
	if state.eliminated.get(player_id, false):
		return "You are out of the game."
	if state.sick.get(player_id, false):
		return "Sick players can't use role powers."
	return ""
