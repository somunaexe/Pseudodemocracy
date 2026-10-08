class_name Roles

# Role cards: Doctor, Lawyer, Secret Agent, Activist, Agbero (data/game_data.json). There are
# roleCopies (5) of each, so at most 5 players can hold a given role at once. A player can hold
# several different roles (they stack, and each earns its own income, see Income) but never two of
# the same. A player with no role is a Civilian: there is no Civilian card.
#
# Everyone can see who holds which roles (see Views). What stays hidden is whether a role card has a
# coup sticker. Each of the 25 cards has an identity (GameState.role_cards): its role, a hidden sticker flag
# (coupStickers of them are stickered at the start, at random) and who holds it. The card moves with the role
# when it is granted, taken, swapped or inherited; the sticker stays on the card.
#
# This file only holds and moves the cards. What each role can DO is not built yet (see
# docs/design_decisions.md): the one rule shared by all of them is can_use_pledge().
#
# Like Nepo, nothing here writes to the event log: every function returns its events and the caller
# logs them, so each event is logged exactly once, by whoever is running the larger step.

const GameStateScript = preload("res://scripts/game_state.gd")
const GameDataScript = preload("res://scripts/game_data.gd")
const PopularityScript = preload("res://scripts/popularity.gd")
const RngScript = preload("res://scripts/rng.gd")
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

# --- the physical cards ------------------------------------------------------------------

# Make the 25 role cards, all in the box, and put the coup stickers on coupStickers of them at random.
# Cards already held (state.roles set by hand, older saves) are handed to those players.
static func setup(state: GameStateScript) -> void:
	state.role_cards = {}
	var id: int = 0
	for role in names():
		for copy in copies():
			state.role_cards[id] = {"role": role, "sticker": false, "holder": 0}
			id += 1
	var order: Array = range(id)
	for i in range(id - 1, 0, -1):   # shuffle with the game's own generator
		var j: int = RngScript.below(state, i + 1)
		var held_id: int = order[i]
		order[i] = order[j]
		order[j] = held_id
	var stickers: int = int(GameDataScript.values()["components"]["coupStickers"])
	for i in mini(stickers, id):
		state.role_cards[order[i]]["sticker"] = true
	for player in state.roles:
		for role in state.roles[player]:
			_take_card(state, player, role)


static func _ensure_cards(state: GameStateScript) -> void:
	if state.role_cards.is_empty():
		setup(state)


# A random card of this role from the box goes to the player.
static func _take_card(state: GameStateScript, player_id: int, role: String) -> void:
	var choices: Array = []
	for id in state.role_cards:
		if state.role_cards[id]["role"] == role and state.role_cards[id]["holder"] == 0:
			choices.append(id)
	if choices.is_empty():
		return   # roles set by hand beyond the 5 copies: no card to follow
	choices.sort()
	state.role_cards[RngScript.pick(state, choices)]["holder"] = player_id


# The card of this role the player holds, or -1 (also when their roles were set by hand).
static func card_of(state: GameStateScript, player_id: int, role: String) -> int:
	for id in state.role_cards:
		if state.role_cards[id]["role"] == role and state.role_cards[id]["holder"] == player_id:
			return id
	return -1


static func _release_card(state: GameStateScript, player_id: int, role: String) -> void:
	var id: int = card_of(state, player_id, role)
	if id != -1:
		state.role_cards[id]["holder"] = 0   # back in the box; the sticker stays on the card


# Does the card this player holds for the role carry a coup sticker? (Secret: only the server, and a
# Secret Agent who checks, may know.) False when there is no such card.
static func has_sticker(state: GameStateScript, player_id: int, role: String) -> bool:
	var id: int = card_of(state, player_id, role)
	return id != -1 and state.role_cards[id]["sticker"]


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
	_ensure_cards(state)
	if not state.roles.has(player_id):
		state.roles[player_id] = []
	state.roles[player_id].append(role)
	_take_card(state, player_id, role)
	return [EventsScript.make("role_gained", {"player": player_id, "role": role})]


# Take one role card from the player (it goes back in the box). Does nothing if they don't hold it.
static func remove(state: GameStateScript, player_id: int, role: String) -> Array:
	if not has(state, player_id, role):
		return []
	_release_card(state, player_id, role)
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
	for id in state.role_cards:   # the cards change hands with the roles
		var holder: int = state.role_cards[id]["holder"]
		if holder == a:
			state.role_cards[id]["holder"] = b
		elif holder == b:
			state.role_cards[id]["holder"] = a
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
		for role in roles:
			_release_card(state, dead_id, role)
		return [EventsScript.make("roles_rescinded", {"player": dead_id, "roles": roles})]
	var received: Array = []
	var returned: Array = []
	for role in roles:
		if has(state, heir, role):
			_release_card(state, dead_id, role)   # the heir can't hold two: that card goes back in the box
			returned.append(role)
		else:
			var card: int = card_of(state, dead_id, role)
			if card != -1:
				state.role_cards[card]["holder"] = heir
			if not state.roles.has(heir):
				state.roles[heir] = []
			state.roles[heir].append(role)
			received.append(role)
	return [EventsScript.make("roles_inherited", {"testator": dead_id, "heir": heir, "roles": received, "returned_to_box": returned})]


# --- powers ------------------------------------------------------------------------------

# Why this player can't use this role's power now, or "" if they can. Every role shares these rules:
# you must hold it, be in the game, and not be sick (Article 17: sick players can't use pledges).
# and not be CANCELLED. Later: a role card frozen by a card or by corruption.
static func can_use_pledge(state: GameStateScript, player_id: int, role: String) -> String:
	if not has(state, player_id, role):
		return "You don't hold the %s role." % role
	if state.eliminated.get(player_id, false):
		return "You are out of the game."
	if state.sick.get(player_id, false):
		return "Sick players can't use pledges."
	if is_cancelled(state, player_id):
		return "CANCELLED players have no roles until they climb back."
	return ""


# At -50 or lower a player is CANCELLED: they keep their cards but have no roles, so no powers and no role
# income, until their popularity climbs back above the line.
static func is_cancelled(state: GameStateScript, player_id: int) -> bool:
	return PopularityScript.effective(state, player_id) <= GameDataScript.get_int("cancelledAt")
