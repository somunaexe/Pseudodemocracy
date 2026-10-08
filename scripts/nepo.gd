class_name Nepo

# The Nepo Baby debuff (Articles 30 and 31): an heir's popularity is temporarily reduced by
# 30, then 20, then 10, and then it is lifted.
#
# Only the STEP (1, 2 or 3) is stored. The size of the reduction is worked out whenever it is
# needed, from the magnitudes in the game data (fixed text in the article) and the sign in the
# current law (Article 31's highlighted "-" words), so an amendment that flips a sign takes
# effect at once. The player's own popularity is never changed: see Popularity.
#
# A step lasts until the end of the Nepo Baby's own turn (the same "term" as debt). Assumptions:
# the first step starts the moment they inherit, and inheriting again restarts at step 1.

const GameStateScript = preload("res://scripts/game_state.gd")
const GameDataScript = preload("res://scripts/game_data.gd")
const LawScript = preload("res://scripts/law.gd")
const EventsScript = preload("res://scripts/events.gd")


# The sizes of the three steps, e.g. [30, 20, 10].
static func magnitudes() -> Array:
	var result: Array = []
	for value in GameDataScript.values()["nepoDebuff"]:
		result.append(int(value))
	return result


# How much a given step (1, 2 or 3) changes popularity under the law as it stands now.
static func change_for_step(state: GameStateScript, step: int) -> int:
	return LawScript.get_int(state, "nepoSign%d" % step) * magnitudes()[step - 1]


# The current change to this player's popularity: 0 if they are not a Nepo Baby.
static func modifier(state: GameStateScript, player_id: int) -> int:
	var step: int = int(state.nepo.get(player_id, 0))
	if step == 0:
		return 0
	return change_for_step(state, step)


# An heir becomes a Nepo Baby, starting at step 1.
static func become(state: GameStateScript, player_id: int) -> Array:
	state.nepo[player_id] = 1
	return [EventsScript.make("nepo_baby", {"player": player_id, "step": 1, "change": change_for_step(state, 1)})]


# Call at the end of the Nepo Baby's own turn: on to the next step, or lifted after the last.
static func advance(state: GameStateScript, player_id: int) -> Array:
	var step: int = int(state.nepo.get(player_id, 0))
	if step == 0:
		return []
	if step >= magnitudes().size():
		state.nepo.erase(player_id)
		return [EventsScript.make("nepo_baby_ended", {"player": player_id})]
	state.nepo[player_id] = step + 1
	return [EventsScript.make("nepo_baby_step", {"player": player_id, "step": step + 1, "change": change_for_step(state, step + 1)})]
