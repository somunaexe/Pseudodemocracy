class_name TurnEnd

# Everything that happens at the END of a player's own turn, in order:
#   1. a debt term is counted, and the player is eliminated if it was their last
#   2. a Nepo Baby's debuff moves on a step (an eliminated player has none left)
# Returns the events.

const GameStateScript = preload("res://scripts/game_state.gd")
const ElimScript = preload("res://scripts/elimination.gd")
const NepoScript = preload("res://scripts/nepo.gd")


static func end_turn(state: GameStateScript, player_id: int) -> Array:
	var events: Array = ElimScript.end_turn(state, player_id)
	if not state.eliminated.get(player_id, false):
		var nepo: Array = NepoScript.advance(state, player_id)
		state.event_log.append_array(nepo)   # the elimination above logged its own events
		events.append_array(nepo)
	return events
