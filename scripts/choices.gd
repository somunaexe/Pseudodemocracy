class_name Choices

# The questions a card asks a player (state.choice): what is asked, who may answer, what counts as an answer, and what the server
# answers when the clock runs out. Kinds:
#   option    one of a list of labelled options, by number
#   role      a role the player can be given
#   player    one other player (`who` narrows it: has_role, rival, loyalist, male, female, union_member)
#   players   up to `max` players from the same list, as an array
#   number    a whole number from `min` to `max`
# The pending question sits in state.choice and the player's turn can't end while it is there (see CardEffects, which applies the
# answers; a `special` card's answers go to SpecialCards). Anything a client sends is checked here first.
#
# Every event this file creates is logged here, once.

const GameStateScript = preload("res://scripts/game_state.gd")
const GameDataScript = preload("res://scripts/game_data.gd")
const RolesScript = preload("res://scripts/roles.gd")
const RivalsScript = preload("res://scripts/rivals.gd")
const LoyalistsScript = preload("res://scripts/loyalists.gd")
const UnionsScript = preload("res://scripts/unions.gd")
const GendersScript = preload("res://scripts/genders.gd")
const RngScript = preload("res://scripts/rng.gd")
const EventsScript = preload("res://scripts/events.gd")


# Ask the question. `parent` is the option that led to a second question; `extra` is kept in the pending question (for
# special cards: which one, and which step). Returns the events (the question, or that there is nobody to ask about).
static func ask(state: GameStateScript, player_id: int, deck: String, card: int, spec: Dictionary, parent: int = -1, extra: Dictionary = {}) -> Array:
	var kind: String = spec["kind"]
	var seconds: int = GameDataScript.get_int("choiceSeconds")
	var ends_at: int = state.clock_ms + seconds * 1000
	var chooser: int = player_id
	if spec.get("chooser", "") == "leader":
		chooser = state.leader_id
		if chooser == player_id or chooser == -1 or state.eliminated.get(chooser, false):
			return [_log(state, "choice_unavailable", {"player": player_id, "deck": deck, "card": card, "kind": kind})]
	var pending: Dictionary = {"player": chooser, "subject": player_id, "deck": deck, "card": card, "kind": kind, "deadline": ends_at}
	var shown: Dictionary = {"player": chooser, "subject": player_id, "deck": deck, "card": card, "kind": kind, "seconds": seconds, "ends_at_ms": ends_at}
	if parent >= 0:
		pending["parent"] = parent   # the second question of an option that was chosen
		shown["parent"] = parent
	for key in extra:
		pending[key] = extra[key]
	if extra.has("special"):
		shown["special"] = extra["special"]
		shown["step"] = extra.get("step", 0)
	if spec.has("prompt"):
		shown["prompt"] = spec["prompt"]
	match kind:
		"option":
			var labels: Array = []
			for option in spec["options"]:
				labels.append(option["label"])
			pending["labels"] = labels
			shown["labels"] = labels
		"role":
			pending["candidates"] = role_candidates(state, player_id)
			shown["candidates"] = pending["candidates"]
		"player", "players":
			pending["candidates"] = player_candidates(state, player_id, str(spec.get("who", "")))
			shown["candidates"] = pending["candidates"]
			if kind == "players":
				pending["max"] = int(spec["max"])
				shown["max"] = pending["max"]
		"number":
			pending["min"] = int(spec["min"])
			pending["max"] = int(spec["max"])
			shown["min"] = pending["min"]
			shown["max"] = pending["max"]
	if pending.has("candidates") and pending["candidates"].is_empty():
		return [_log(state, "choice_unavailable", {"player": player_id, "deck": deck, "card": card, "kind": kind})]
	if not state.choice.is_empty():
		state.choice_queue.append({"pending": pending, "shown": shown})   # another question is open: this one waits its turn
		return []
	state.choice = pending
	return [_log(state, "choice_needed", shown)]


# The question that was open has been answered: the next one in the queue (if any) is asked, its clock starting now.
static func next(state: GameStateScript) -> Array:
	if not state.choice.is_empty() or state.choice_queue.is_empty():
		return []
	var entry: Dictionary = state.choice_queue.pop_front()
	var seconds: int = GameDataScript.get_int("choiceSeconds")
	entry["pending"]["deadline"] = state.clock_ms + seconds * 1000
	entry["shown"]["ends_at_ms"] = int(entry["pending"]["deadline"])
	state.choice = entry["pending"]
	return [_log(state, "choice_needed", entry["shown"])]


# Is this player's turn held up by a question about their card, open or waiting?
static func blocks(state: GameStateScript, player_id: int) -> bool:
	if not state.choice.is_empty() and state.choice.get("subject", state.choice["player"]) == player_id:
		return true
	for entry in state.choice_queue:
		if entry["pending"].get("subject", entry["pending"]["player"]) == player_id:
			return true
	return false


static func role_candidates(state: GameStateScript, player_id: int) -> Array:
	var result: Array = []
	for role in RolesScript.names():
		if RolesScript.problem_granting(state, player_id, role) == "":
			result.append(role)
	return result


static func player_candidates(state: GameStateScript, player_id: int, who: String) -> Array:
	var result: Array = []
	for id in state.player_ids:
		if id == player_id or state.eliminated.get(id, false):
			continue
		if who == "has_role" and RolesScript.is_civilian(state, id):
			continue
		if who in ["male", "female"] and GendersScript.of(state, id) != who:
			continue
		result.append(id)
	if who == "rival":
		return RivalsScript.candidates(state, player_id)
	if who == "loyalist":
		return result.filter(func(id): return LoyalistsScript.problem_appointing(state, player_id, id) == "")
	if who == "union_member":
		var union_id: int = UnionsScript.union_of(state, player_id)
		if union_id == -1:
			return []
		return result.filter(func(id): return id in state.unions[union_id]["members"])
	return result


# Why this answer is not acceptable, or "" if it is. The answer comes from a client: check its type
# and that it is one of the choices offered. Nothing else about it is trusted.
static func problem_with(pending: Dictionary, value: Variant) -> String:
	match pending["kind"]:
		"option":
			if typeof(value) != TYPE_INT or value < 0 or value >= pending["labels"].size():
				return "Choose one of the %d options by its number." % pending["labels"].size()
		"role":
			if typeof(value) != TYPE_STRING or not value in pending["candidates"]:
				return "Choose one of: %s." % ", ".join(pending["candidates"])
		"player":
			if typeof(value) != TYPE_INT or not value in pending["candidates"]:
				return "Choose one of the players offered."
		"players":
			if typeof(value) != TYPE_ARRAY or value.size() > pending["max"]:
				return "Choose up to %d of the players offered." % pending["max"]
			var seen: Array = []
			for id in value:
				if typeof(id) != TYPE_INT or not id in pending["candidates"] or id in seen:
					return "Choose up to %d different players from those offered." % pending["max"]
				seen.append(id)
		"number":
			if typeof(value) != TYPE_INT or value < pending["min"] or value > pending["max"]:
				return "Choose a whole number from %d to %d." % [pending["min"], pending["max"]]
	return ""


# What the server answers for a player who ran out of time: a special card's own default if it has one, otherwise a random valid
# answer (nobody, for "players"; the smallest number).
static func default_answer(state: GameStateScript, pending: Dictionary) -> Variant:
	if pending.has("default"):
		return pending["default"]
	match pending["kind"]:
		"option":
			return RngScript.below(state, pending["labels"].size())
		"role", "player":
			return RngScript.pick(state, pending["candidates"])
		"players":
			return []
		"number":
			return int(pending["min"])
	return 0


static func _log(state: GameStateScript, type: String, data: Dictionary) -> Dictionary:
	var event: Dictionary = EventsScript.make(type, data)
	state.event_log.append(event)
	return event
