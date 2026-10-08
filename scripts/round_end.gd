class_name RoundEnd

# Everything that happens when a round (a term) ends: sickness and immunity count down, the Doctor's
# charges come back. One place, called when an election begins after a term (see Election.begin). Like
# Sickness and Roles, nothing here logs: the caller logs the events it returns.

const GameStateScript = preload("res://scripts/game_state.gd")
const SicknessScript = preload("res://scripts/sickness.gd")


static func run(state: GameStateScript) -> Array:
	state.doctor_used = {}
	return SicknessScript.end_of_round(state)
