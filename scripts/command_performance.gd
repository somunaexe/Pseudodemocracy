class_name CommandPerformance

# Command Performance (handbook Articles 16 and 17): a union (Activists) or mob (Agberos) scripts a scenario and a
# player performs it, and the table judges them.
#
#   { "type": "union_command", "union_id": id, "scenario": text, "target": id }    the Unionizer or Capon
#   { "type": "command_finish" }                                                  the performer is done early
#   { "type": "command_vote", "good": bool }                                      everyone but the performer
#
#   - It needs the group to have unionMin (2) members and the leader not sick, and it can only happen on the
#     Unionizer's or Capon's OWN turn (not on the Leader's turn, even when the Leader is a member).
#   - The scenario is free text written by the group's leader, 1 to scenarioMax characters.
#   - The target is any player in the game who is not a member of the group, regular players and the Leader alike.
#     The Unionizer (or Capon) has the final say on the target, even when the Leader is a member of the group.
#   - The commanding group's total popularity vote is DOUBLED: each of its members' votes counts commandVoteMultiplier
#     (2) times, whether it is a union or a mob, even if the mob has dispersed by the time the votes are cast.
#   - The target performs for performanceSeconds (60), they may finish early. Then everyone except the performer
#     votes Good or Bad for performanceVoteSeconds (15). The performer's popularity moves by +swing (more Good) or
#     -swing (more Bad). A tie changes nothing. There are no Settlement or Scandal cards.
#   - It starts only once the leader has finished their own performance, and the turn can't end until it is over.
#     One at a time, and a group may do it once per turn.
#   - An Agbero mob disperses the instant it acts (Article 13), as soon as the command is made. An Activist union
#     lingers (Article 12). ("Shared" and "personal" describe how the two relate; they add no rule.)
#   - If the term ends (a coup, the Leader eliminated) or the target leaves the game, it is void.
#
# Every event this file creates is logged here, once (the dispersal of a mob is logged here too).

const GameStateScript = preload("res://scripts/game_state.gd")
const GameDataScript = preload("res://scripts/game_data.gd")
const PopularityScript = preload("res://scripts/popularity.gd")
const UnionsScript = preload("res://scripts/unions.gd")
const LawScript = preload("res://scripts/law.gd")
const LoyalistsScript = preload("res://scripts/loyalists.gd")
const EventsScript = preload("res://scripts/events.gd")

const PERFORMING := GameStateScript.CommandPhase.PERFORMING
const VOTING := GameStateScript.CommandPhase.VOTING


# --- commands ----------------------------------------------------------------------------

static func handle(state: GameStateScript, player_id: int, command: Dictionary) -> Array:
	match str(command.get("type", "")):
		"union_command":
			return _start(state, player_id, command)
		"command_finish":
			return _finish(state, player_id)
		"command_vote":
			return _vote(state, player_id, command)
	return [_reject(player_id, "Unknown command.")]


static func _start(state: GameStateScript, leader: int, command: Dictionary) -> Array:
	var union_id = command.get("union_id", null)
	if typeof(union_id) != TYPE_INT or not state.unions.has(union_id):
		return [_reject(leader, "There is no such union or mob.")]
	var union: Dictionary = state.unions[union_id]
	if union["owner"] != leader:
		return [_reject(leader, "Only the %s decides for a %s." % [UnionsScript.head(union), UnionsScript.word(union)])]
	if state.sick.get(leader, false):
		return [_reject(leader, "Sick players can't use pledges.")]
	if not _on_their_own_turn(state, leader):
		return [_reject(leader, "A %s can only command a performance on the %s's own turn." % [UnionsScript.word(union), UnionsScript.head(union)])]
	if union["members"].size() < LawScript.get_int(state, "unionMin"):
		return [_reject(leader, "The %s is too small to act." % UnionsScript.word(union))]
	if not state.command.is_empty():
		return [_reject(leader, "A Command Performance is already under way.")]
	var act: Dictionary = state.term.get("act", {})
	if act.is_empty() or act["phase"] != GameStateScript.ActPhase.DONE:
		return [_reject(leader, "Wait until the performance of the player whose turn it is has finished.")]
	if union.get("commanded", -1) == _turn_key(state):
		return [_reject(leader, "This %s has already commanded a performance this turn." % UnionsScript.word(union))]
	var scenario = command.get("scenario", null)
	if typeof(scenario) != TYPE_STRING:
		return [_reject(leader, "Write the scenario as text.")]
	scenario = scenario.strip_edges()
	var maximum: int = GameDataScript.get_int("scenarioMax")
	if scenario.is_empty() or scenario.length() > maximum:
		return [_reject(leader, "The scenario must be from 1 to %d characters." % maximum)]
	var candidates: Array = _candidates(state, union)
	if candidates.is_empty():
		return [_reject(leader, "There is no one to command.")]

	var named = command.get("target", null)
	if typeof(named) != TYPE_INT or not named in candidates:
		return [_reject(leader, "Choose a player outside your %s." % UnionsScript.word(union))]
	union["commanded"] = _turn_key(state)
	state.command = {"union_id": union_id, "union_type": union["type"], "leader": leader, "scenario": scenario, "votes": {}, "target": named, "members": union["members"].duplicate()}
	var events: Array = [_log(state, "command_started", {"union_id": union_id, "union_type": union["type"], "leader": leader, "scenario": scenario, "target": named})]
	events.append_array(_begin_performance(state))
	if union["type"] == GameStateScript.UnionType.AGBERO:
		events.append_array(_log_all(state, UnionsScript.disperse(state, union_id, "the mob acted")))   # it disperses the instant it acts
	return events


static func _begin_performance(state: GameStateScript) -> Array:
	var seconds: int = GameDataScript.get_int("performanceSeconds")
	state.command["phase"] = PERFORMING
	state.command["deadline"] = state.clock_ms + seconds * 1000
	return [_log(state, "command_performance_started", {"union_id": state.command["union_id"], "target": state.command["target"], "scenario": state.command["scenario"], "seconds": seconds, "ends_at_ms": state.command["deadline"]})]


static func _finish(state: GameStateScript, player_id: int) -> Array:
	if state.command.is_empty() or state.command["phase"] != PERFORMING:
		return [_reject(player_id, "There is no performance to finish.")]
	if player_id != state.command["target"]:
		return [_reject(player_id, "Only the performer can finish the performance.")]
	return _open_voting(state)


static func _vote(state: GameStateScript, player_id: int, command: Dictionary) -> Array:
	if state.command.is_empty() or state.command["phase"] != VOTING:
		return [_reject(player_id, "It isn't time to vote.")]
	if not player_id in _voters(state):
		return [_reject(player_id, "You can't vote on this performance.")]
	if state.command["votes"].has(player_id):
		return [_reject(player_id, "You have already voted.")]
	var may: Callable = func(id): return id in _voters(state)
	var blocked: String = LoyalistsScript.problem_voting(state, player_id, state.command["votes"], may)
	if blocked != "":
		return [_reject(player_id, blocked)]
	var good = command.get("good", null)
	if typeof(good) != TYPE_BOOL:
		return [_reject(player_id, "Vote Good or Bad.")]
	good = LoyalistsScript.vote_for(state, player_id, good, state.command["votes"], may)   # a Loyalist votes as their owner did
	state.command["votes"][player_id] = good
	var events: Array = [_log(state, "command_vote_cast", {"voter": player_id})]   # that they voted, never how
	for pair in LoyalistsScript.mirror(state, player_id, good, state.command["votes"], may):
		events.append(_log(state, "command_vote_cast", {"voter": pair[0], "with": pair[1]}))
	return events


# --- the automatic steps -----------------------------------------------------------------

static func step(state: GameStateScript) -> Array:
	if state.command.is_empty():
		return []
	var cmd: Dictionary = state.command
	# The term is gone (a coup, the Leader eliminated), or the performer has left the game: nothing to judge.
	if state.term.is_empty() or not cmd["target"] in state.player_ids or state.eliminated.get(cmd["target"], false):
		state.command = {}
		return [_log(state, "command_void", {"union_id": cmd["union_id"], "target": cmd["target"]})]
	match cmd["phase"]:
		PERFORMING:
			if state.clock_ms >= int(cmd["deadline"]):
				return _open_voting(state)
		VOTING:
			if state.clock_ms >= int(cmd["deadline"]) or _everyone_voted(state):
				return _resolve(state)
	return []


static func _open_voting(state: GameStateScript) -> Array:
	var seconds: int = GameDataScript.get_int("performanceVoteSeconds")
	state.command["phase"] = VOTING
	state.command["deadline"] = state.clock_ms + seconds * 1000
	return [_log(state, "command_voting_opened", {"union_id": state.command["union_id"], "target": state.command["target"], "voters": _voters(state), "seconds": seconds, "ends_at_ms": state.command["deadline"]})]


static func _resolve(state: GameStateScript) -> Array:
	var cmd: Dictionary = state.command
	var good: int = 0   # the votes as they count: a member of the commanding group counts commandVoteMultiplier times
	var bad: int = 0
	var multiplier: int = GameDataScript.get_int("commandVoteMultiplier")
	for voter in cmd["votes"]:
		var weight: int = multiplier if voter in cmd["members"] else 1
		if cmd["votes"][voter]:
			good += weight
		else:
			bad += weight
	var swing: int = GameDataScript.base_swing(_active(state).size())
	var delta: int = 0
	if good > bad:
		delta = swing
	elif bad > good:
		delta = -swing
	if delta != 0:
		PopularityScript.change_base(state, cmd["target"], delta)
	var outcome: String = "tie"
	if good != bad:
		outcome = "good" if good > bad else "bad"
	state.command = {}
	return [_log(state, "command_performance_resolved", {"union_id": cmd["union_id"], "union_type": cmd["union_type"], "leader": cmd["leader"], "target": cmd["target"], "scenario": cmd["scenario"], "good": good, "bad": bad, "multiplier": multiplier, "popularity_delta": delta, "outcome": outcome, "votes": cmd["votes"].duplicate()})]


# --- who -----------------------------------------------------------------------------------

static func _active(state: GameStateScript) -> Array:
	var result: Array = []
	for id in state.player_ids:
		if not state.eliminated.get(id, false):
			result.append(id)
	return result


# Everyone still in the game except the performer.
static func _voters(state: GameStateScript) -> Array:
	var result: Array = _active(state)
	result.erase(state.command["target"])
	return result


static func _everyone_voted(state: GameStateScript) -> bool:
	for id in _voters(state):
		if not state.command["votes"].has(id):
			return false
	return true


# Anyone in the game who is not a member of the group.
static func _candidates(state: GameStateScript, union: Dictionary) -> Array:
	var result: Array = []
	for id in _active(state):
		if not id in union["members"]:
			result.append(id)
	return result


# Only on the leader's OWN turn (not on the Leader's, even if the Leader is a member).
static func _on_their_own_turn(state: GameStateScript, leader: int) -> bool:
	var waiting: Array = state.term.get("waiting", [])
	return state.term.get("phase", GameStateScript.TermPhase.NONE) == GameStateScript.TermPhase.TURNS and not waiting.is_empty() and waiting[0] == leader


# Which union turn is this: the round and how many turns have been played in it.
static func _turn_key(state: GameStateScript) -> int:
	return state.current_round * 1000 + state.turns_played


static func _log_all(state: GameStateScript, events: Array) -> Array:
	for event in events:
		state.event_log.append(event)
	return events


static func _log(state: GameStateScript, type: String, data: Dictionary) -> Dictionary:
	var event: Dictionary = EventsScript.make(type, data)
	state.event_log.append(event)
	return event


static func _reject(player_id: int, reason: String) -> Dictionary:
	return EventsScript.make("rejected", {"reason": reason}, [player_id])
