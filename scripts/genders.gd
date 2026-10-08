class_name Genders

# Gender, for the cards that name one ("Collect 5 PSD from every woman at the table"). The online version asks each
# player before the game. It is public (the cards name groups at the table) and is fixed once the first Leader is
# installed, so nobody can change it to dodge a card.
#
#   { "type": "set_gender", "gender": "female" | "male" }      only before the first Leader is installed
#
# There are two options. A player who hasn't said is in neither group the cards name.
#
# Every event this file creates is logged here, once.

const GameStateScript = preload("res://scripts/game_state.gd")
const GameDataScript = preload("res://scripts/game_data.gd")
const EventsScript = preload("res://scripts/events.gd")


static func names() -> Array:
	return GameDataScript.values()["genders"].duplicate()


static func of(state: GameStateScript, player_id: int) -> String:
	return state.genders.get(player_id, "")


# The players still in the game of this gender, in seat order.
static func players(state: GameStateScript, gender: String) -> Array:
	var result: Array = []
	for id in state.player_ids:
		if not state.eliminated.get(id, false) and of(state, id) == gender:
			result.append(id)
	return result


# Gender can be changed only while the very first election is running.
static func can_change(state: GameStateScript) -> bool:
	return state.leader_id == -1 and state.election.get("reason", "") == "first"


static func handle(state: GameStateScript, player_id: int, command: Dictionary) -> Array:
	if not player_id in state.player_ids:
		return [_reject(player_id, "You are not in the game.")]
	if not can_change(state):
		return [_reject(player_id, "Gender is fixed once the game has begun.")]
	var gender = command.get("gender", null)
	if typeof(gender) != TYPE_STRING or not gender in names():
		return [_reject(player_id, "Choose one of: %s." % ", ".join(names()))]
	state.genders[player_id] = gender
	var event: Dictionary = EventsScript.make("gender_set", {"player": player_id, "gender": gender})
	state.event_log.append(event)
	return [event]


static func _reject(player_id: int, reason: String) -> Dictionary:
	return EventsScript.make("rejected", {"reason": reason}, [player_id])
