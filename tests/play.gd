extends RefCounted

# Test helper: play the performance part of a turn without moving anyone's popularity, then end the turn.
# The clock is run out twice, once on the performance and once on the vote, and nobody votes: a tie.
# Returns the events of the end_turn command.

const GameScript = preload("res://scripts/game.gd")


static func take_turn(s, player_id: int) -> Array:
	for i in 2:
		var act: Dictionary = s.term.get("act", {})
		if act.is_empty() or act["phase"] == s.ActPhase.DONE:
			break
		GameScript.tick(s, int(act["deadline"]))
	return GameScript.handle(s, player_id, {"type": "end_turn"})


# The same, but returns every event of the whole turn: the ones the clock produced and the end of the turn.
static func take_turn_all(s, player_id: int) -> Array:
	var events: Array = []
	for i in 2:
		var act: Dictionary = s.term.get("act", {})
		if act.is_empty() or act["phase"] == s.ActPhase.DONE:
			break
		events.append_array(GameScript.tick(s, int(act["deadline"])))
	events.append_array(GameScript.handle(s, player_id, {"type": "end_turn"}))
	return events
