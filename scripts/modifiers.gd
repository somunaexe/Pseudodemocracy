class_name Modifiers

# Temporary rules on a player, put there by cards ("halve your losses next term", "skip your next income"). state.mods maps
# a player to their modifiers by name; each is a record:
#   { "from": first round it applies in, "until": last round it applies in (-1 = no end), "uses": uses left (-1 = unlimited),
#     plus whatever data the modifier needs }
# "Next term" is from = current round + 1 and until = the same; "this term" is the current round; "until used" has no end and one use;
# "for the next 2 terms" is from = current round + 1, until = current round + 2 (3 rounds means 3 FURTHER rounds, as for every
# duration in the game). A modifier is active in a round that lies between from and until.
# The rest of the game asks active() / get() / use(); only this file looks inside the records. RoundEnd calls end_of_round.
# Public: everyone can see who has which modifier (nothing a card does to a player is secret).

const GameStateScript = preload("res://scripts/game_state.gd")


# Give the player a modifier. opts: rounds (how many rounds it lasts, -1 for no end), starts (0 = this round, 1 = next round),
# uses (-1 unlimited), and any other keys, which are kept as the modifier's data. Replaces one of the same name.
static func give(state: GameStateScript, player_id: int, name: String, opts: Dictionary = {}) -> Dictionary:
	var starts: int = int(opts.get("starts", 0))
	var rounds: int = int(opts.get("rounds", 1))
	var record: Dictionary = {}
	for key in opts:
		if not key in ["starts", "rounds"]:
			record[key] = opts[key]
	record["from"] = state.current_round + starts
	record["until"] = -1 if rounds < 0 else state.current_round + starts + rounds - 1
	record["uses"] = int(opts.get("uses", -1))
	if not state.mods.has(player_id):
		state.mods[player_id] = {}
	state.mods[player_id][name] = record
	return record


static func get_record(state: GameStateScript, player_id: int, name: String) -> Dictionary:
	return state.mods.get(player_id, {}).get(name, {})


static func has(state: GameStateScript, player_id: int, name: String) -> bool:
	return state.mods.get(player_id, {}).has(name)


# Does the modifier apply now?
static func active(state: GameStateScript, player_id: int, name: String) -> bool:
	var record: Dictionary = get_record(state, player_id, name)
	if record.is_empty() or int(record["uses"]) == 0:
		return false
	return int(record["from"]) <= state.current_round and (int(record["until"]) == -1 or state.current_round <= int(record["until"]))


# One use is spent (a modifier with uses runs out when they do).
static func use(state: GameStateScript, player_id: int, name: String) -> void:
	var record: Dictionary = get_record(state, player_id, name)
	if record.is_empty() or int(record["uses"]) < 0:
		return
	record["uses"] = int(record["uses"]) - 1
	if record["uses"] <= 0:
		remove(state, player_id, name)


static func remove(state: GameStateScript, player_id: int, name: String) -> void:
	if state.mods.has(player_id):
		state.mods[player_id].erase(name)
		if state.mods[player_id].is_empty():
			state.mods.erase(player_id)


# A round ends: modifiers whose last round it was are gone.
static func end_of_round(state: GameStateScript) -> void:
	for id in state.mods.keys():
		for name in state.mods[id].keys():
			var until: int = int(state.mods[id][name]["until"])
			if until != -1 and until <= state.current_round:
				state.mods[id].erase(name)
		if state.mods[id].is_empty():
			state.mods.erase(id)


# A player leaves the game.
static func remove_player(state: GameStateScript, player_id: int) -> void:
	state.mods.erase(player_id)


# The names of the player's modifiers that apply now, for views and tests.
static func names_of(state: GameStateScript, player_id: int) -> Array:
	var result: Array = []
	for name in state.mods.get(player_id, {}):
		if active(state, player_id, name):
			result.append(name)
	result.sort()
	return result
