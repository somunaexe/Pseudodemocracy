class_name Absence

# A player who is not there. The server ends a turn for a player who never does (turnEndSeconds); this counts those turns.
#   - A turn is MISSED if the server ended it and the player did nothing at all in it (no accepted command of theirs while it
#     was their turn). A player who acted but forgot to press "end turn" is not absent.
#   - Missed turns count IN A ROW: any turn they act in, or end themselves, starts the count again.
#   - missedTurnLimit (2) in a row and they are eliminated, reason "absent": their will is read, their cash and roles go as for
#     any elimination. This also keeps a table, and the server's memory, from filling with players who left.
# Called by TermLoop at the end of every turn.

const GameStateScript = preload("res://scripts/game_state.gd")
const GameDataScript = preload("res://scripts/game_data.gd")
const ElimScript = preload("res://scripts/elimination.gd")
const EventsScript = preload("res://scripts/events.gd")


# The player did something on their own turn.
static func acted(state: GameStateScript, player_id: int) -> void:
	var waiting: Array = state.term.get("waiting", [])
	if not waiting.is_empty() and waiting[0] == player_id:
		state.term["acted"] = player_id


# Their turn is ending (by themselves, or by the server: auto). Returns the events, logged.
static func turn_over(state: GameStateScript, player_id: int, auto: bool) -> Array:
	var did_something: bool = state.term.get("acted", -1) == player_id
	state.term.erase("acted")
	if not auto or did_something:
		state.missed_turns.erase(player_id)
		return []
	var missed: int = int(state.missed_turns.get(player_id, 0)) + 1
	state.missed_turns[player_id] = missed
	var limit: int = GameDataScript.get_int("missedTurnLimit")
	var event: Dictionary = EventsScript.make("turn_missed", {"player": player_id, "missed": missed, "limit": limit})
	state.event_log.append(event)
	var events: Array = [event]
	if missed >= limit:
		state.missed_turns.erase(player_id)
		events.append_array(ElimScript.eliminate(state, player_id, "absent"))
	return events
