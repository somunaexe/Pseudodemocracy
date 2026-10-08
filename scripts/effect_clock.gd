class_name EffectClock

# "For 3 rounds" means 3 FURTHER rounds: the round an effect begins in is not one of them. Effects that last a number of
# rounds (sickness, immunity from a card, a coup ban; also freezes, loyalties and accords, which carry a "since" round of
# their own) count down at the end of each round, except the round they began in. This is the one place that remembers it.
# The "left" numbers stay what they say: rounds still to go after the current one.

const GameStateScript = preload("res://scripts/game_state.gd")


static func began(state: GameStateScript, kind: String, player_id: int) -> void:
	state.effect_round["%s:%d" % [kind, player_id]] = state.current_round


# True if this effect began in the round that is ending, so it doesn't count down now. Otherwise forgets it and returns false.
static func skips(state: GameStateScript, kind: String, player_id: int) -> bool:
	var key: String = "%s:%d" % [kind, player_id]
	if int(state.effect_round.get(key, -1)) == state.current_round:
		return true
	state.effect_round.erase(key)
	return false


static func forget(state: GameStateScript, kind: String, player_id: int) -> void:
	state.effect_round.erase("%s:%d" % [kind, player_id])
