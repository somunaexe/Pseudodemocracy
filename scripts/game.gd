class_name Game

# The front door. A game is created with new_game(); after that EVERYTHING a player or the server
# does goes through handle(), which sends the command to the right part of the game and then lets
# the term loop move on by itself as far as it can. Returns the events; a refused command comes
# back as a single "rejected" event and changes nothing.
#
# Commands, by who sends them:
#   any player, during a term    propose, rule_grammar (server only), confront, vote   (amending)
#   the Leader, in an election   write_exam;  skip_exam (server only)
#   players, in an election      answer_exam, cast_vote
#   the Leader                   pass_window       (decline to amend at the Inauguration or Farewell)
#   the player whose turn it is  end_turn
#   the server                   finish_game       (the group has decided to stop)
#
# The server calls tick() after anything it did itself (a timer running out, say), so the loop
# can move on.

const GameStateScript = preload("res://scripts/game_state.gd")
const DoctorScript = preload("res://scripts/doctor.gd")
const RolesScript = preload("res://scripts/roles.gd")
const CardEffectsScript = preload("res://scripts/card_effects.gd")
const SecretAgentScript = preload("res://scripts/secret_agent.gd")
const CommandPerformanceScript = preload("res://scripts/command_performance.gd")
const GendersScript = preload("res://scripts/genders.gd")
const UnionsScript = preload("res://scripts/unions.gd")
const WillsScript = preload("res://scripts/wills.gd")
const GameDataScript = preload("res://scripts/game_data.gd")
const ConstitutionScript = preload("res://scripts/constitution.gd")
const AmendmentFlowScript = preload("res://scripts/amendment_flow.gd")
const ElectionScript = preload("res://scripts/election.gd")
const TermLoopScript = preload("res://scripts/term_loop.gd")
const ScoringScript = preload("res://scripts/scoring.gd")
const RngScript = preload("res://scripts/rng.gd")
const PopularityScript = preload("res://scripts/popularity.gd")
const EventsScript = preload("res://scripts/events.gd")

const SERVER_ID := 0

const AMENDMENT_COMMANDS := ["propose", "rule_grammar", "confront", "vote"]
const ELECTION_COMMANDS := ["write_exam", "skip_exam", "answer_exam", "cast_vote"]
const COMMAND_COMMANDS := ["union_command", "command_target", "command_finish", "command_vote"]
const GENDER_COMMANDS := ["set_gender"]
const UNION_COMMANDS := ["union_recruit", "union_respond", "union_leave", "union_kick", "union_disperse", "union_reform"]
const CARD_COMMANDS := ["choose", "play_card"]
const AGENT_COMMANDS := ["agent_check"]
const WILL_COMMANDS := ["will_propose", "will_respond", "will_catch_up", "will_revoke"]
const DOSE_COMMANDS := ["dose_offer", "dose_respond", "dose_guess"]
const TERM_COMMANDS := ["pass_window", "end_turn", "finish_performance", "performance_vote"]


# A new game for 3 to 10 players with ids 1, 2, 3, ... in seat order. Everyone starts with the
# starting money, the rest of the box goes to the treasury, and the first election begins (no
# exam: there is no Leader yet). seed_value 0 seeds the random numbers from the clock.
# genders (optional): player id -> "female", "male" or "other", as entered in the lobby; players can also say
# theirs with set_gender until the first Leader is installed.
static func new_game(player_ids: Array, seed_value: int = 0, genders: Dictionary = {}) -> GameStateScript:
	assert(player_ids.size() >= GameDataScript.get_int("minPlayers") and player_ids.size() <= GameDataScript.get_int("boxPlayers"),
		"a game needs %d to %d players" % [GameDataScript.get_int("minPlayers"), GameDataScript.get_int("boxPlayers")])
	var state: GameStateScript = GameStateScript.new()
	var start: int = GameDataScript.get_int("startMoney")
	state.player_ids = player_ids.duplicate()
	state.player_count = player_ids.size()
	for id in player_ids:
		assert(id >= 1, "player ids start at 1")
		state.psd[id] = start
		PopularityScript.change_base(state, id, 0)   # everyone starts at 0
		state.sick[id] = false
	state.treasury = GameDataScript.get_int("boxTotal") - start * player_ids.size()
	state.articles = ConstitutionScript.initial_articles()
	state.levy_band = {"low": GameDataScript.get_nested_int("levy", "bandLow"), "high": GameDataScript.get_nested_int("levy", "bandHigh")}
	if seed_value == 0:
		RngScript.seed_from_clock(state)
	else:
		RngScript.seed_with(state, seed_value)
	for id in genders:
		assert(id in player_ids and genders[id] in GendersScript.names(), "a gender for a player who isn't at the table, or one that doesn't exist")
		state.genders[id] = genders[id]
	RolesScript.setup(state)   # the 25 role cards, with their coup stickers, are dealt out of sight
	ElectionScript.begin(state, "first")
	return state


static func handle(state: GameStateScript, player_id: int, command: Dictionary) -> Array:
	if state.game_over:
		return [_reject(player_id, "The game is over.")]
	var type: String = str(command.get("type", ""))
	var events: Array = []
	if type in AMENDMENT_COMMANDS:
		events = _amendment(state, player_id, command)
	elif type in ELECTION_COMMANDS:
		events = ElectionScript.handle(state, player_id, command)
	elif type in TERM_COMMANDS:
		events = TermLoopScript.handle(state, player_id, command)
	elif type in COMMAND_COMMANDS:
		events = CommandPerformanceScript.handle(state, player_id, command)
	elif type in GENDER_COMMANDS:
		events = GendersScript.handle(state, player_id, command)
	elif type in UNION_COMMANDS:
		events = UnionsScript.handle(state, player_id, command)
	elif type in CARD_COMMANDS:
		events = CardEffectsScript.handle(state, player_id, command)
	elif type in AGENT_COMMANDS:
		events = SecretAgentScript.handle(state, player_id, command)
	elif type in WILL_COMMANDS:
		events = WillsScript.handle(state, player_id, command)
	elif type in DOSE_COMMANDS:
		events = DoctorScript.handle(state, player_id, command)
	elif type == "finish_game":
		events = _finish(state, player_id)
	else:
		return [_reject(player_id, "Unknown command '%s'." % type)]
	if events.size() == 1 and events[0]["type"] == "rejected":
		return events
	events.append_array(TermLoopScript.settle(state))
	return events


# Let the game move on after something the server did itself. A server with a clock passes the
# time in milliseconds; the game's clock only ever moves forward. Deadlines (a performance, a vote)
# are checked against it here and nowhere else.
static func tick(state: GameStateScript, now_ms: int = -1) -> Array:
	if now_ms > state.clock_ms:
		state.clock_ms = now_ms
	return TermLoopScript.settle(state)


# Amendments happen at set moments of a term: the Inauguration window at the Inauguration, the
# Mid-term window once half have played, the Farewell window at the Farewell.
static func _amendment(state: GameStateScript, player_id: int, command: Dictionary) -> Array:
	if str(command.get("type", "")) == "propose":
		var window = command.get("window", -1)
		var phase: int = state.term.get("phase", GameStateScript.TermPhase.NONE)
		if typeof(window) == TYPE_INT and window in GameStateScript.AmendWindow.values():
			if phase == GameStateScript.TermPhase.NONE or not state.election.is_empty():
				return [_reject(player_id, "The Constitution can only be amended during a term.")]
			if window == GameStateScript.AmendWindow.INAUGURATION and phase != GameStateScript.TermPhase.INAUGURATION:
				return [_reject(player_id, "The Inauguration amendment can only be made at the Inauguration.")]
			if window == GameStateScript.AmendWindow.MID_TERM and phase == GameStateScript.TermPhase.INAUGURATION:
				return [_reject(player_id, "The Mid-term amendment can't be made at the Inauguration.")]
			if window == GameStateScript.AmendWindow.FAREWELL and phase != GameStateScript.TermPhase.FAREWELL:
				return [_reject(player_id, "The Farewell amendment can only be made at the Farewell.")]
	return AmendmentFlowScript.handle(state, player_id, command)


# The group has decided to stop (server only). A term still running counts as a full round
# (handbook, Part 1). Returns who won.
static func _finish(state: GameStateScript, player_id: int) -> Array:
	if player_id != SERVER_ID:
		return [_reject(player_id, "Only the server can end the game.")]
	if state.term.get("phase", GameStateScript.TermPhase.NONE) != GameStateScript.TermPhase.NONE and state.leader_id != -1:
		state.half_rounds[state.leader_id] = int(state.half_rounds.get(state.leader_id, 0)) + 2
	state.game_over = true
	var event: Dictionary = EventsScript.make("game_over", {"winners": ScoringScript.final_winners(state)})
	state.event_log.append(event)
	return [event]


static func _reject(player_id: int, reason: String) -> Dictionary:
	return EventsScript.make("rejected", {"reason": reason}, [player_id])
