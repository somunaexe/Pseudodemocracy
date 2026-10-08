class_name Polls

# A question put to SEVERAL players at once by a card ("each of them may give their share, redirect it to the treasury, or lose
# 10 popularity"). state.polls holds the open ones:
#   { "id", "special": the card's name, "drawer", "targets": [ids], "labels": [...], "default": option used for silence,
#     "answers": { id: option }, "deadline", "mode": "each" | "any_cancels", "data": whatever the card needs, "deck", "card" }
# Each target answers once with { "type": "poll_answer", "poll": id, "option": n }. The poll ends when everyone has answered, or when the
# clock runs out (pollSeconds; silence is the poll's default option), or at once if its mode is "any_cancels" and someone picks the last
# option (a player citing a satirist's card, or a creditor blocking a card). Then SpecialCards decides what each answer does.
# The answers are SECRET until the poll ends (Views shows only who has answered). The drawer's turn can't end while their poll is open.
#
# Every event this file creates is logged here, once.

const GameStateScript = preload("res://scripts/game_state.gd")
const GameDataScript = preload("res://scripts/game_data.gd")
const EventsScript = preload("res://scripts/events.gd")


# Open a poll. Returns the events.
static func open(state: GameStateScript, special: String, drawer: int, targets: Array, labels: Array, default_option: int, data: Dictionary = {}, mode: String = "each", deck: String = "", card: int = -1) -> Array:
	targets = targets.filter(func(id): return not state.eliminated.get(id, false))
	if targets.is_empty():
		return []
	state.poll_counter += 1
	var seconds: int = GameDataScript.get_int("pollSeconds")
	var poll: Dictionary = {"id": state.poll_counter, "special": special, "drawer": drawer, "targets": targets.duplicate(), "labels": labels.duplicate(),
		"default": default_option, "answers": {}, "deadline": state.clock_ms + seconds * 1000, "mode": mode, "data": data, "deck": deck, "card": card}
	state.polls.append(poll)
	return [_log(state, "poll_opened", {"poll": poll["id"], "special": special, "drawer": drawer, "targets": targets.duplicate(), "labels": labels.duplicate(), "data": data.duplicate(true), "seconds": seconds, "ends_at_ms": int(poll["deadline"]), "deck": deck, "card": card})]


static func find(state: GameStateScript, poll_id: int) -> int:
	for i in state.polls.size():
		if state.polls[i]["id"] == poll_id:
			return i
	return -1


static func open_for(state: GameStateScript, drawer: int) -> bool:
	for poll in state.polls:
		if poll["drawer"] == drawer:
			return true
	return false


# --- the command --------------------------------------------------------------------------

static func handle(state: GameStateScript, player_id: int, command: Dictionary) -> Array:
	var poll_id = command.get("poll", null)
	var option = command.get("option", null)
	if typeof(poll_id) != TYPE_INT or find(state, poll_id) == -1:
		return [_reject(player_id, "There is no such question.")]
	var poll: Dictionary = state.polls[find(state, poll_id)]
	if not player_id in poll["targets"]:
		return [_reject(player_id, "That question isn't for you.")]
	if poll["answers"].has(player_id):
		return [_reject(player_id, "You have already answered.")]
	if typeof(option) != TYPE_INT or option < 0 or option >= poll["labels"].size():
		return [_reject(player_id, "Choose one of the %d options by its number." % poll["labels"].size())]
	poll["answers"][player_id] = option
	var events: Array = [_log(state, "poll_answered", {"poll": poll_id, "player": player_id})]   # THAT, never WHAT
	events.append_array(_maybe_finish(state, poll))
	return events


static func _maybe_finish(state: GameStateScript, poll: Dictionary) -> Array:
	if poll["mode"] == "any_cancels":
		for id in poll["answers"]:
			if poll["answers"][id] == poll["labels"].size() - 1:
				return _finish(state, poll)   # someone cited it: no need to wait
	for id in poll["targets"]:
		if not poll["answers"].has(id) and not state.eliminated.get(id, false):
			return []
	return _finish(state, poll)


# The clock: polls whose time is up end, silence counting as their default.
static func step(state: GameStateScript) -> Array:
	for poll in state.polls:
		if state.clock_ms >= int(poll["deadline"]):
			return _finish(state, poll)
	return []


static func _finish(state: GameStateScript, poll: Dictionary) -> Array:
	state.polls.erase(poll)
	var answers: Dictionary = {}
	var silent: Array = []
	for id in poll["targets"]:
		if state.eliminated.get(id, false):
			continue
		if poll["answers"].has(id):
			answers[id] = int(poll["answers"][id])
		else:
			answers[id] = int(poll["default"])
			silent.append(id)
	var events: Array = [_log(state, "poll_closed", {"poll": poll["id"], "special": poll["special"], "drawer": poll["drawer"], "answers": answers.duplicate(), "silent": silent})]
	var special = load("res://scripts/special_cards.gd")   # loaded when needed: SpecialCards opens polls, so it can't be preloaded here
	events.append_array(special.poll_closed(state, poll, answers))
	return events


# A player leaves the game: they are no longer asked, and a poll about them is over.
static func remove_player(state: GameStateScript, player_id: int) -> void:
	for poll in state.polls.duplicate():
		poll["targets"].erase(player_id)
		poll["answers"].erase(player_id)
		if poll["drawer"] == player_id or poll["targets"].is_empty():
			state.polls.erase(poll)


static func _log(state: GameStateScript, type: String, data: Dictionary) -> Dictionary:
	var event: Dictionary = EventsScript.make(type, data)
	state.event_log.append(event)
	return event


static func _reject(player_id: int, reason: String) -> Dictionary:
	return EventsScript.make("rejected", {"reason": reason}, [player_id])
