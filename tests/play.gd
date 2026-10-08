extends RefCounted

# Test helper: play the performance part of a turn without moving anyone's popularity, then end the turn.
# The clock is run out step by step (the performance, a debate's sides, the vote, any question a card asked the player or the table) and
# nobody votes: a tie. Returns the events of the end_turn command.

const GameScript = preload("res://scripts/game.gd")


# The next time something that holds up this player's turn is waiting for the clock: the performance, a question about their card, or
# a question they put to several players.
static func next_deadline(s, player_id: int) -> int:
	var deadlines: Array = []
	var act: Dictionary = s.term.get("act", {})
	if not act.is_empty() and act["phase"] != s.ActPhase.DONE:
		deadlines.append(int(act["deadline"]))
	if not s.choice.is_empty() and s.choice.get("subject", s.choice["player"]) == player_id:
		deadlines.append(int(s.choice["deadline"]))   # only what holds up THIS player's turn
	for poll in s.polls:
		if poll["drawer"] == player_id:
			deadlines.append(int(poll["deadline"]))
	return -1 if deadlines.is_empty() else deadlines.min()


static func take_turn(s, player_id: int) -> Array:
	for i in 40:
		var at: int = next_deadline(s, player_id)
		if at == -1:
			break
		GameScript.tick(s, at)
	return GameScript.handle(s, player_id, {"type": "end_turn"})


# The same, but returns every event of the whole turn: the ones the clock produced and the end of the turn.
static func take_turn_all(s, player_id: int) -> Array:
	var events: Array = []
	for i in 40:
		var at: int = next_deadline(s, player_id)
		if at == -1:
			break
		events.append_array(GameScript.tick(s, at))
	events.append_array(GameScript.handle(s, player_id, {"type": "end_turn"}))
	return events
