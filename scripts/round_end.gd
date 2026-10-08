class_name RoundEnd

# Everything that happens when a round (a term) ends: wills are charged their upkeep, sickness and immunity
# count down, the Doctor's charges and the Secret Agents' one check come back. One place, called when an election begins after a term (see Election.begin). Like
# Sickness and Roles, nothing here logs: the caller logs the events it returns.

const GameStateScript = preload("res://scripts/game_state.gd")
const SicknessScript = preload("res://scripts/sickness.gd")
const WillsScript = preload("res://scripts/wills.gd")


static func run(state: GameStateScript) -> Array:
	state.doctor_used = {}
	state.agent_used = {}
	var events: Array = WillsScript.end_of_round(state)   # upkeep first: a will on hold when the round ends
	events.append_array(SicknessScript.end_of_round(state))
	return events
