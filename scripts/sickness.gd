class_name Sickness

# Sickness (handbook Part 6, Doctor & Health, and Article 21). A sick player can't use pledges,
# write exams, vote or be voted for (the rest of the code checks state.sick for that).
#
#   - Sickness lasts a number of ROUNDS (a round is a term). It counts down at the end of each round.
#   - NO STACKING: a player who is already sick can't be sickened again, however they became sick.
#   - When a sick player recovers they are IMMUNE for as many rounds as their ORIGINAL sickness lasted.
#     Sabotage lengthens the sickness but not the immunity (Doctor "Right/Wrong guess" example).
#   - A card can give immunity too.
#
# Like Roles and Nepo, nothing here writes to the event log: every function returns its events and the
# caller logs them.

const GameStateScript = preload("res://scripts/game_state.gd")
const EventsScript = preload("res://scripts/events.gd")


static func is_sick(state: GameStateScript, player_id: int) -> bool:
	return state.sick.get(player_id, false)


static func is_immune(state: GameStateScript, player_id: int) -> bool:
	return state.immune_left.get(player_id, 0) > 0


# Why this player can't be sickened now, or "" if they can.
static func problem_sickening(state: GameStateScript, player_id: int) -> String:
	if not player_id in state.player_ids or state.eliminated.get(player_id, false):
		return "That player is not in the game."
	if is_sick(state, player_id):
		return "A sick player can't be sickened again."
	if is_immune(state, player_id):
		return "They are immune for %d more round(s)." % state.immune_left[player_id]
	return ""


# Make the player sick for this many rounds. The caller checks problem_sickening first.
static func sicken(state: GameStateScript, player_id: int, rounds: int) -> Array:
	assert(problem_sickening(state, player_id) == "", "sicken() needs a player who can be sickened")
	assert(rounds > 0, "sickness lasts at least one round")
	state.sick[player_id] = true
	state.sick_left[player_id] = rounds
	state.sick_original[player_id] = rounds
	return [EventsScript.make("sickened", {"player": player_id, "rounds": rounds})]


# Sabotage: the sickness gets longer, the immunity afterwards does not.
static func lengthen(state: GameStateScript, player_id: int, rounds: int) -> Array:
	if not is_sick(state, player_id):
		return []
	state.sick_left[player_id] = int(state.sick_left.get(player_id, 0)) + rounds
	return [EventsScript.make("sickness_lengthened", {"player": player_id, "rounds": rounds, "left": state.sick_left[player_id]})]


# A cure: the sickness gets shorter, and ends if nothing is left.
static func shorten(state: GameStateScript, player_id: int, rounds: int) -> Array:
	if not is_sick(state, player_id):
		return []
	var left: int = int(state.sick_left.get(player_id, 0)) - rounds
	if left <= 0:
		return recover(state, player_id)
	state.sick_left[player_id] = left
	return [EventsScript.make("sickness_shortened", {"player": player_id, "rounds": rounds, "left": left})]


# The sickness ends now. The player is immune for as long as it first lasted.
static func recover(state: GameStateScript, player_id: int) -> Array:
	if not is_sick(state, player_id):
		return []
	var immune_for: int = int(state.sick_original.get(player_id, 0))
	state.sick[player_id] = false
	state.sick_left.erase(player_id)
	state.sick_original.erase(player_id)
	if immune_for > 0:
		state.immune_left[player_id] = maxi(int(state.immune_left.get(player_id, 0)), immune_for)
	return [EventsScript.make("recovered", {"player": player_id, "immune_for": immune_for})]


# A card makes the player immune for this many rounds (never shortening an immunity they already have).
static func grant_immunity(state: GameStateScript, player_id: int, rounds: int) -> Array:
	state.immune_left[player_id] = maxi(int(state.immune_left.get(player_id, 0)), rounds)
	return [EventsScript.make("immunity_granted", {"player": player_id, "rounds": state.immune_left[player_id]})]


# A round is over. Immunity counts down first, so a player who recovers now keeps their full immunity;
# then every sickness counts down, and those that reach 0 end. Players in id order, so it is repeatable.
static func end_of_round(state: GameStateScript) -> Array:
	var events: Array = []
	var immune: Array = state.immune_left.keys()
	immune.sort()
	for id in immune:
		state.immune_left[id] -= 1
		if state.immune_left[id] <= 0:
			state.immune_left.erase(id)
			events.append(EventsScript.make("immunity_ended", {"player": id}))
	var sick: Array = state.sick_left.keys()
	sick.sort()
	for id in sick:
		if not is_sick(state, id):
			continue
		state.sick_left[id] -= 1
		if state.sick_left[id] <= 0:
			events.append_array(recover(state, id))
	return events
