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
# A DEBATE card ("Debate a rival", "Choose a rival - publicly challenge them"; effect `debate` in the card data) changes the
# middle: the performer challenges a rival (debate_challenge, a rival of theirs if they have any, with a topic), the
# performer speaks for debateSeconds (30) and then the rival does (each may end their side early with debate_finish), and the
# table votes for the winner (debate_vote; everyone but the two debaters; Loyalists vote with their owner). A performer who
# doesn't challenge in time is given a rival at random. The winner moves +swing, the loser -swing (both of them). The
# PERFORMER draws a Settlement card if they win and a Scandal card if they lose; a tie draws nothing. The rival draws none.
# (Assumed: the challenged rival can't refuse, and the debate takes the place of the Good/Bad vote on the performance.)
#   act["debate"] = { "rival": id (0 until challenged), "topic": text, "side": -1 until challenged, 0 the performer speaks, 1 the rival }
#
# The state of the performance is state.term["act"] while it lasts:
#   { "phase": ActPhase, "player": id, "card": n, "deadline": clock_ms, "votes": { voter: bool } }
# The votes are SECRET until the result (see Views). Time is GameState.clock_ms (whole milliseconds), moved by Game.tick.
#
# The drawn card is announced to everyone. If its effect is only about the player's own money and
# popularity, the game applies it (see CardEffects); any other card is carried out by the table,
# like the highlighted words of the Constitution the game doesn't read.
#
# Every event this file creates is logged here, once.

const GameStateScript = preload("res://scripts/game_state.gd")
const GameDataScript = preload("res://scripts/game_data.gd")
const PopularityScript = preload("res://scripts/popularity.gd")
const CardsScript = preload("res://scripts/cards.gd")
const CardEffectsScript = preload("res://scripts/card_effects.gd")
const UnionsScript = preload("res://scripts/unions.gd")
const RivalsScript = preload("res://scripts/rivals.gd")
const RngScript = preload("res://scripts/rng.gd")
const LoyalistsScript = preload("res://scripts/loyalists.gd")
const EventsScript = preload("res://scripts/events.gd")

const PERFORMING := GameStateScript.ActPhase.PERFORMING
const VOTING := GameStateScript.ActPhase.VOTING
const DONE := GameStateScript.ActPhase.DONE


# --- commands ----------------------------------------------------------------------------
#   { "type": "finish_performance" }     the performer is done acting
#   { "type": "performance_vote", "good": bool }
#   { "type": "debate_challenge", "rival": id, "topic": text }   the performer, on a debate card
#   { "type": "debate_finish" }                                   whoever is speaking has said enough
#   { "type": "debate_vote", "winner": id }                       the performer or the rival

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
			if act.has("debate"):
				return [_reject(player_id, "This is a debate: challenge a rival (debate_challenge) and debate.")]
			return _open_voting(state)
		"performance_vote":
			if act.has("debate"):
				return [_reject(player_id, "This is a debate: vote for the winner (debate_vote).")]
			return _vote(state, act, player_id, command)
		"debate_challenge":
			return _challenge(state, act, player_id, command)
		"debate_finish":
			return _debate_finish(state, act, player_id)
		"debate_vote":
			return _debate_vote(state, act, player_id, command)
	return [_reject(player_id, "Unknown command.")]


static func _vote(state: GameStateScript, act: Dictionary, player_id: int, command: Dictionary) -> Array:
	if act["phase"] != VOTING:
		return [_reject(player_id, "It isn't time to vote.")]
	if not player_id in _voters(state, act):
		return [_reject(player_id, "You can't vote on this performance.")]
	if act["votes"].has(player_id):
		return [_reject(player_id, "You have already voted.")]
	var may: Callable = func(id): return id in _voters(state, act)
	var blocked: String = LoyalistsScript.problem_voting(state, player_id, act["votes"], may)
	if blocked != "":
		return [_reject(player_id, blocked)]
	var good = command.get("good", null)
	if typeof(good) != TYPE_BOOL:
		return [_reject(player_id, "Vote Good or Bad.")]
	good = LoyalistsScript.vote_for(state, player_id, good, act["votes"], may)   # a Loyalist votes as their owner did
	act["votes"][player_id] = good
	var events: Array = [_log(state, "performance_vote_cast", {"voter": player_id})]   # that they voted, never how
	for pair in LoyalistsScript.mirror(state, player_id, good, act["votes"], may):
		events.append(_log(state, "performance_vote_cast", {"voter": pair[0], "with": pair[1]}))
	return events


# --- debates -----------------------------------------------------------------------------

static func _challenge(state: GameStateScript, act: Dictionary, player_id: int, command: Dictionary) -> Array:
	var debate: Dictionary = act.get("debate", {})
	if debate.is_empty() or act["phase"] != PERFORMING:
		return [_reject(player_id, "There is no debate to challenge anyone to.")]
	if player_id != act["player"]:
		return [_reject(player_id, "Only the performer challenges.")]
	if debate["rival"] != 0:
		return [_reject(player_id, "You have already challenged someone.")]
	var rival = command.get("rival", null)
	var candidates: Array = RivalsScript.candidates(state, player_id)
	if typeof(rival) != TYPE_INT or not rival in candidates:
		return [_reject(player_id, "Choose one of your rivals%s." % ("" if not RivalsScript.of(state, player_id).is_empty() else " (any other player, as you have none)")) ]
	var topic = command.get("topic", "")
	if typeof(topic) != TYPE_STRING or topic.length() > GameDataScript.get_int("debateTopicMax"):
		return [_reject(player_id, "The topic must be text of at most %d characters." % GameDataScript.get_int("debateTopicMax"))]
	return _begin_debate(state, act, rival, topic.strip_edges())


static func _begin_debate(state: GameStateScript, act: Dictionary, rival: int, topic: String) -> Array:
	var debate: Dictionary = act["debate"]
	debate["rival"] = rival
	debate["topic"] = topic
	debate["side"] = 0
	var seconds: int = GameDataScript.get_int("debateSeconds")
	act["deadline"] = state.clock_ms + seconds * 1000
	var events: Array = []
	for event in RivalsScript.name_rival(state, act["player"], rival):
		state.event_log.append(event)
		events.append(event)
	events.append(_log(state, "debate_started", {"player": act["player"], "rival": rival, "topic": topic, "speaker": act["player"], "seconds": seconds, "ends_at_ms": int(act["deadline"])}))
	return events


static func _debate_finish(state: GameStateScript, act: Dictionary, player_id: int) -> Array:
	var debate: Dictionary = act.get("debate", {})
	if debate.is_empty() or act["phase"] != PERFORMING or debate["side"] < 0:
		return [_reject(player_id, "Nobody is debating.")]
	var speaker: int = act["player"] if debate["side"] == 0 else debate["rival"]
	if player_id != speaker:
		return [_reject(player_id, "It isn't your turn to speak.")]
	return _debate_next(state, act)


# The clock ran out while the performer was to challenge (a rival is given them) or while someone was speaking.
static func _debate_clock(state: GameStateScript, act: Dictionary) -> Array:
	var debate: Dictionary = act["debate"]
	if debate["rival"] == 0:
		var candidates: Array = RivalsScript.candidates(state, act["player"])
		if candidates.is_empty():
			act.erase("debate")   # nobody to debate: the performance is voted on as usual
			return _open_voting(state)
		return _begin_debate(state, act, RngScript.pick(state, candidates), "")
	return _debate_next(state, act)


static func _debate_next(state: GameStateScript, act: Dictionary) -> Array:
	var debate: Dictionary = act["debate"]
	if debate["side"] == 0:
		debate["side"] = 1
		var seconds: int = GameDataScript.get_int("debateSeconds")
		act["deadline"] = state.clock_ms + seconds * 1000
		return [_log(state, "debate_turn", {"player": act["player"], "rival": debate["rival"], "speaker": debate["rival"], "seconds": seconds, "ends_at_ms": int(act["deadline"])})]
	debate["side"] = 2
	return _open_voting(state)


static func _debate_vote(state: GameStateScript, act: Dictionary, player_id: int, command: Dictionary) -> Array:
	var debate: Dictionary = act.get("debate", {})
	if debate.is_empty() or act["phase"] != VOTING:
		return [_reject(player_id, "It isn't time to vote on a debate.")]
	if not player_id in _voters(state, act):
		return [_reject(player_id, "You can't vote on this debate.")]
	if act["votes"].has(player_id):
		return [_reject(player_id, "You have already voted.")]
	var may: Callable = func(id): return id in _voters(state, act)
	var blocked: String = LoyalistsScript.problem_voting(state, player_id, act["votes"], may)
	if blocked != "":
		return [_reject(player_id, blocked)]
	var winner = command.get("winner", null)
	if typeof(winner) != TYPE_INT or not (winner == act["player"] or winner == debate["rival"]):
		return [_reject(player_id, "Vote for the performer or for the rival.")]
	winner = LoyalistsScript.vote_for(state, player_id, winner, act["votes"], may)   # a Loyalist votes as their owner did
	act["votes"][player_id] = winner
	var events: Array = [_log(state, "debate_vote_cast", {"voter": player_id})]   # that they voted, never for whom
	for pair in LoyalistsScript.mirror(state, player_id, winner, act["votes"], may):
		events.append(_log(state, "debate_vote_cast", {"voter": pair[0], "with": pair[1]}))
	return events


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
				if act.has("debate"):
					return _debate_clock(state, act)
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
	var events: Array = [_log(state, "performance_started", {"player": performer, "card": card, "text": CardsScript.text("performance", card), "seconds": seconds, "ends_at_ms": ends_at})]
	if CardsScript.effects("performance", card).has("debate"):
		state.term["act"]["debate"] = {"rival": 0, "topic": "", "side": -1}
	if CardsScript.effects("performance", card).has("pitch"):
		# "A rival union wants your backing": the performer is pitched and decides (union_respond) while they perform.
		for event in UnionsScript.pitch(state, performer):
			state.event_log.append(event)
			events.append(event)
	return events


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
	var debate: Dictionary = act.get("debate", {})
	for voter in act["votes"]:
		var for_performer: bool
		if debate.is_empty():
			for_performer = act["votes"][voter]
		else:
			for_performer = act["votes"][voter] != debate["rival"]   # a debate vote is the winner's id
		if for_performer:
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
		if not debate.is_empty():
			PopularityScript.change_base(state, debate["rival"], -delta)   # the other debater gets the opposite
	var outcome: String = "tie"
	var data: Dictionary = {"player": act["player"], "good": good, "bad": bad, "popularity_delta": delta, "votes": act["votes"].duplicate()}
	if not debate.is_empty():
		data["debate_rival"] = debate["rival"]
		data["rival_popularity_delta"] = -delta
	if good != bad:
		outcome = "good" if good > bad else "bad"
		var deck: String = "settlement" if good > bad else "scandal"
		if deck == "settlement" and state.frozen.has(act["player"]):
			data["frozen"] = true   # corruption: no Settlement cards for them
		elif state.skip_draw.has(act["player"]):
			state.skip_draw.erase(act["player"])
			data["draw_skipped"] = true   # a card made them lose this draw entirely
		else:
			var card: int = CardsScript.draw(state, deck)
			data["deck"] = deck
			data["card"] = card
			data["text"] = CardsScript.text(deck, card)
	data["outcome"] = outcome
	act["phase"] = DONE
	var events: Array = [_log(state, "performance_resolved", data)]
	if data.has("card"):
		events.append_array(CardEffectsScript.apply(state, act["player"], data["deck"], data["card"]))   # logs its own event
	return events


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
	if act.has("debate"):
		result.erase(act["debate"]["rival"])   # in a debate the two debaters don't vote
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
