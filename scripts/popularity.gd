class_name Popularity

# A player's popularity has two parts:
#   base      what votes, amendments and cards have done to it. Stored in GameState.popularity.
#   modifier  a temporary change on top (today: the Nepo Baby debuff), which lifts by itself.
# What counts, for being CANCELLED, for ranking and for what players see, is the EFFECTIVE
# popularity: base plus modifier, kept inside the track (-50 to +50).
#
# Nothing outside this file may read GameState.popularity directly (test_nepo.gd checks).

const GameStateScript = preload("res://scripts/game_state.gd")
const GameDataScript = preload("res://scripts/game_data.gd")
const NepoScript = preload("res://scripts/nepo.gd")
const ModifiersScript = preload("res://scripts/modifiers.gd")


static func base(state: GameStateScript, player_id: int) -> int:
	return int(state.popularity.get(player_id, 0))


# A copy of every player's base popularity (for views).
static func bases(state: GameStateScript) -> Dictionary:
	return state.popularity.duplicate(true)


static func modifier(state: GameStateScript, player_id: int) -> int:
	return NepoScript.modifier(state, player_id)


static func effective(state: GameStateScript, player_id: int) -> int:
	return clampi(base(state, player_id) + modifier(state, player_id), _low(), _high())


# Votes, fines and cards move the base, which also stays on the track.
# Cards can change what a loss does: "halve_loss" halves it (rounded down, in the player's favour) and "pop_floor" keeps
# the base from going below a value.
static func change_base(state: GameStateScript, player_id: int, delta: int) -> void:
	if delta < 0 and ModifiersScript.active(state, player_id, "halve_loss"):
		delta = -(-delta / 2)
	var result: int = clampi(base(state, player_id) + delta, _low(), _high())
	if delta < 0 and ModifiersScript.active(state, player_id, "pop_floor"):
		var floor_value: int = int(ModifiersScript.get_record(state, player_id, "pop_floor")["value"])
		if base(state, player_id) >= floor_value:
			result = maxi(result, floor_value)   # a player already below the floor gets no protection from it
	state.popularity[player_id] = result


# CANCELLED: at or below the line (cancelledAt), unless a card shields the player this term.
static func is_cancelled(state: GameStateScript, player_id: int) -> bool:
	if ModifiersScript.active(state, player_id, "cancel_shield"):
		return false
	return effective(state, player_id) <= GameDataScript.get_int("cancelledAt")


static func _low() -> int:
	return GameDataScript.get_int("popMin")


static func _high() -> int:
	return GameDataScript.get_int("popMax")
