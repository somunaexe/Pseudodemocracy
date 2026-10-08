class_name LeaderCards

# The Leader role cards (Dictator, President, President, President, Commander) are drawn at
# random, one per new Leader (or Vice). Assumption: the card is put back, so every draw is independent.

const GameStateScript = preload("res://scripts/game_state.gd")
const GameDataScript = preload("res://scripts/game_data.gd")
const RngScript = preload("res://scripts/rng.gd")


static func draw(state: GameStateScript) -> int:
	var cards: Dictionary = GameDataScript.values()["components"]["leaderCards"]
	var names: Array = cards.keys()
	names.sort()
	var total: int = 0
	for name in names:
		total += int(cards[name])
	var roll: int = RngScript.below(state, total)
	for name in names:
		roll -= int(cards[name])
		if roll < 0:
			return GameStateScript.LeaderType[str(name).to_upper()]
	return GameStateScript.LeaderType.PRESIDENT   # unreachable
