class_name PerformanceTurn

# What a player does with their turn, after the levy:
#
#   PERFORMING  a Performance card is drawn at random and read out to everyone; the player has
#      |        performanceSeconds (60) to act it out. The player may finish early.
#   VOTING      everyone else votes Good or Bad for performanceVoteSeconds (15). Voting ends when
#      |        the time is up or when every eligible voter has voted. A vote that never comes
#      |        doesn't count.
#   DONE        popularity moves by +swing (more Good) or -swing (more Bad), the swing for the table.
#               More Good: the player draws a Settlement card. More Bad: a Scandal card.
#               A tie (or nobody voting): no change and no card. The player may now end their turn.
#
# The state of the performance is state.term["act"] while it lasts:
#   { "phase": ActPhase, "player": id, "card": n, "deadline": clock_ms, "votes": { voter: bool } }
# The votes are SECRET until the result (see Views). Time is GameState.clock_ms (whole milliseconds), moved by Game.tick.
#
# A card's effect is announced to everyone and carried out by the table for now, like the
# highlighted words of the Constitution the game doesn't read. The game applies the popularity.
#
# Every event this file creates is logged here, once.

const GameStateScript = preload("res://scripts/game_state.gd")
const GameDataScript = preload("res://scripts/game_data.gd")
const PopularityScript = preload("res://scripts/popularity.gd")
const CardsScript = preload("res://scripts/cards.gd")
const EventsScript = preload("res://scripts/events.gd")

const PERFORMING := GameStateScript.ActPhase.PERFORMING
const VOTING := GameStateScript.ActPhase.VOTING
const DONE := GameStateScript.ActPhase.DONE


# --- commands ----------------------------------------------------------------------------
#   { "type": "finish_performance" }     the performer is done acting
#   { "type": "performance_vote", "good": bool }

static func handle(state: GameStateScript, player_id: int, command: Dictionary) -> Array:
	var act: Dictionary = state.term.get("act", {})
	if act.is_empty():
		return [_reject(player_id, "Nobody is performing.")]
	match str(command.get("type", "")):
		"finish_performance":
			if act["phase"] != PERFORMING:
				return [_reject(player_id, "The performance is over.")]
			if player_id != act["player"]:
				return [_reject(player_id, "Only the performer can finish the performance.")]
			return _open_voting(state)
		"performance_vote":
			return _vote(state, act, player_id, command)
	return [_reject(player_id, "Unknown command.")]


static func _vote(state: GameStateScript, act: Dictionary, player_id: int, command: Dictionary) -> Array:
	if act["phase"] != VOTING:
		return [_reject(player_id, "It isn't time to vote.")]
	if not player_id in _voters(state, act):
		return [_reject(player_id, "You can't vote on this performance.")]
	if act["votes"].has(player_id):
		return [_reject(player_id, "You have already voted.")]
	var good = command.get("good", null)
	if typeof(good) != TYPE_BOOL:
		return [_reject(player_id, "Vote Good or Bad.")]
	act["votes"][player_id] = good
	return [_log(state, "performance_vote_cast", {"voter": player_id})]   # that they voted, never how


# --- the automatic steps -----------------------------------------------------------------

# Advance the performance of the player whose turn it is, as far as the clock and the votes allow.
# Returns the events, or [] if there is nothing to do until a player acts or time passes.
static func step(state: GameStateScript, performer: int) -> Array:
	var act: Dictionary = state.term.get("act", {})
	if not act.is_empty() and act["player"] != performer:
		state.term.erase("act")   # the performer left the game mid-act; the next player starts fresh
		act = {}
	if act.is_empty():
		return _start(state, performer)
	match act["phase"]:
		PERFORMING:
			if state.clock_ms >= int(act["deadline"]):
				return _open_voting(state)
		VOTING:
			if state.clock_ms >= int(act["deadline"]) or _everyone_voted(state, act):
				return _resolve(state, act)
	return []


static func _start(state: GameStateScript, performer: int) -> Array:
	var card: int = CardsScript.draw(state, "performance")
	var seconds: int = GameDataScript.get_int("performanceSeconds")
	var ends_at: int = state.clock_ms + seconds * 1000
	state.term["act"] = {"phase": PERFORMING, "player": performer, "card": card, "deadline": ends_at, "votes": {}}
	return [_log(state, "performance_started", {"player": performer, "card": card, "text": CardsScript.text("performance", card), "seconds": seconds, "ends_at_ms": ends_at})]


static func _open_voting(state: GameStateScript) -> Array:
	var act: Dictionary = state.term["act"]
	var seconds: int = GameDataScript.get_int("performanceVoteSeconds")
	var ends_at: int = state.clock_ms + seconds * 1000
	act["phase"] = VOTING
	act["deadline"] = ends_at
	return [_log(state, "performance_voting_opened", {"player": act["player"], "voters": _voters(state, act), "seconds": seconds, "ends_at_ms": ends_at})]


static func _resolve(state: GameStateScript, act: Dictionary) -> Array:
	var good: int = 0
	var bad: int = 0
	for voter in act["votes"]:
		if act["votes"][voter]:
			good += 1
		else:
			bad += 1
	var swing: int = GameDataScript.base_swing(_active(state).size())
	var delta: int = 0   # a win moves popularity by +swing, a loss by -swing, a tie not at all
	if good > bad:
		delta = swing
	elif bad > good:
		delta = -swing
	if delta != 0:
		PopularityScript.change_base(state, act["player"], delta)
	var outcome: String = "tie"
	var data: Dictionary = {"player": act["player"], "good": good, "bad": bad, "popularity_delta": delta, "votes": act["votes"].duplicate()}
	if good != bad:
		outcome = "good" if good > bad else "bad"
		var deck: String = "settlement" if good > bad else "scandal"
		var card: int = CardsScript.draw(state, deck)
		data["deck"] = deck
		data["card"] = card
		data["text"] = CardsScript.text(deck, card)
	data["outcome"] = outcome
	act["phase"] = DONE
	return [_log(state, "performance_resolved", data)]


# --- who may vote ------------------------------------------------------------------------

static func _active(state: GameStateScript) -> Array:
	var result: Array = []
	for id in state.player_ids:
		if not state.eliminated.get(id, false):
			result.append(id)
	return result


# Everyone still in the game except the performer.
static func _voters(state: GameStateScript, act: Dictionary) -> Array:
	var result: Array = _active(state)
	result.erase(act["player"])
	return result


static func _everyone_voted(state: GameStateScript, act: Dictionary) -> bool:
	for id in _voters(state, act):
		if not act["votes"].has(id):
			return false
	return true


static func _log(state: GameStateScript, type: String, data: Dictionary) -> Dictionary:
	var event: Dictionary = EventsScript.make(type, data)
	state.event_log.append(event)
	return event


static func _reject(player_id: int, reason: String) -> Dictionary:
	return EventsScript.make("rejected", {"reason": reason}, [player_id])
