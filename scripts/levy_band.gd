class_name LevyBand

# The Levy Band Shift (Article 5). When a term ends, the Leader's popularity moves the band:
#   below -X  the band rises by the shift      above +X  the band falls by the shift
# Both ends move together. The low end never drops below the floor; if the floor stops it, the
# high end moves by the same (smaller) amount, so the band keeps its width. If the levy is then
# outside the band it moves to the closest value inside it.
#
# X is a word of Article 5 that Leaders can amend (levyRaiseBelow, levyLowerAbove), so it is read
# through Law. The shift (10) and the floor (25) are fixed words of the article, read from data.
# Popularity is the effective popularity, Nepo debuff included.

const GameStateScript = preload("res://scripts/game_state.gd")
const LawScript = preload("res://scripts/law.gd")
const PopularityScript = preload("res://scripts/popularity.gd")
const GameDataScript = preload("res://scripts/game_data.gd")
const EventsScript = preload("res://scripts/events.gd")


# Returns the events (also logged here, once). Nothing happens if there is no Leader.
static func shift_at_term_end(state: GameStateScript) -> Array:
	if state.leader_id == -1:
		return []
	var popularity: int = PopularityScript.effective(state, state.leader_id)
	var direction: int = 0
	if popularity < -LawScript.get_int(state, "levyRaiseBelow"):
		direction = 1
	elif popularity > LawScript.get_int(state, "levyLowerAbove"):
		direction = -1
	if direction == 0:
		return []
	var low: int = state.levy_band["low"]
	var high: int = state.levy_band["high"]
	var delta: int = direction * GameDataScript.get_nested_int("levy", "shift")
	delta = maxi(delta, GameDataScript.get_nested_int("levy", "floor") - low)   # the floor stops the low end
	if delta == 0:
		return []   # already at the floor: nothing moves
	var levy_before: int = LawScript.get_int(state, "levy")
	state.levy_band = {"low": low + delta, "high": high + delta}
	var levy_after: int = clampi(levy_before, state.levy_band["low"], state.levy_band["high"])
	if levy_after != levy_before:
		LawScript.set_int(state, "levy", levy_after)
	var event: Dictionary = EventsScript.make("levy_band_shifted", {
		"leader": state.leader_id, "popularity": popularity,
		"old_band": [low, high], "new_band": [state.levy_band["low"], state.levy_band["high"]],
		"old_levy": levy_before, "new_levy": levy_after,
	})
	state.event_log.append(event)
	return [event]
