class_name TermLoop

# The rhythm of one term (handbook, Part 3), after the Leader has been chosen:
#
#   INAUGURATION  the Leader may amend one article, or pass
#      |          then the levy is collected from every player
#   TURNS         every player takes one turn (income, then a performance), carrying on round the table from where the last
#      |          term stopped (after a coup the new Leader goes first instead)
#      |          the Mid-term amendment opens once half have played (see Permissions)
#   FAREWELL      the Leader may amend one article, or pass
#      |
#   the term ends: the levy band may shift (LevyBand), the Leader is credited, and Election.begin("term_ended") starts the next election
#
# Nothing here waits on a timer. Every step that needs no decision from a player happens by
# itself in settle(), which looks at the state and advances as far as it can, so it is safe to
# call at any time and as often as you like. A step that needs a decision waits for a command:
#   { "type": "pass_window" }   the Leader, at the Inauguration or the Farewell, chooses not to amend
#   { "type": "end_turn" }      the player whose turn it is, once their performance is over
#   { "type": "finish_performance" } / { "type": "performance_vote", "good": bool }   see PerformanceTurn
#
# A Leader who can't amend (a Commander, or sick, or CANCELLED) has both windows skipped.
# Sick players still take their turn. Eliminated players are skipped.
#
# Each turn starts with the player's income (see Income), then is a performance (see PerformanceTurn).
# Not built yet: dealing roles, the effects of Settlement and Scandal cards, coups.
#
# Every event this file creates is logged here, once. Events from the modules it calls are
# logged by those modules.

const GameStateScript = preload("res://scripts/game_state.gd")
const LawScript = preload("res://scripts/law.gd")
const DebtScript = preload("res://scripts/debt.gd")
const PermissionsScript = preload("res://scripts/permissions.gd")
const ElectionScript = preload("res://scripts/election.gd")
const LevyBandScript = preload("res://scripts/levy_band.gd")
const IncomeScript = preload("res://scripts/income.gd")
const CardEffectsScript = preload("res://scripts/card_effects.gd")
const CommandPerformanceScript = preload("res://scripts/command_performance.gd")
const UnionsScript = preload("res://scripts/unions.gd")
const WillsScript = preload("res://scripts/wills.gd")
const DoctorScript = preload("res://scripts/doctor.gd")
const PerformanceTurnScript = preload("res://scripts/performance.gd")
const TurnEndScript = preload("res://scripts/turn_end.gd")
const EventsScript = preload("res://scripts/events.gd")

# More steps than a term can possibly take; settle() fails loudly instead of looping forever.
const MAX_STEPS := 50

const ALLOWED_COMMANDS = {
	GameStateScript.TermPhase.NONE: [],
	GameStateScript.TermPhase.INAUGURATION: ["pass_window"],
	GameStateScript.TermPhase.TURNS: ["end_turn", "finish_performance", "performance_vote"],
	GameStateScript.TermPhase.FAREWELL: ["pass_window"],
}


# --- commands ----------------------------------------------------------------------------

static func handle(state: GameStateScript, player_id: int, command: Dictionary) -> Array:
	var type: String = str(command.get("type", ""))
	var phase: int = state.term.get("phase", GameStateScript.TermPhase.NONE)
	if not ALLOWED_COMMANDS[phase].has(type):
		return [_reject(player_id, "'%s' isn't possible at this stage." % type)]
	match type:
		"pass_window":
			return _pass_window(state, player_id, phase)
		"end_turn":
			return _end_turn(state, player_id)
		"finish_performance", "performance_vote":
			return PerformanceTurnScript.handle(state, player_id, command)
	return [_reject(player_id, "Unknown command.")]


static func _pass_window(state: GameStateScript, player_id: int, phase: int) -> Array:
	if player_id != state.leader_id:
		return [_reject(player_id, "Only the Leader decides whether to amend.")]
	if not state.amend.is_empty():
		return [_reject(player_id, "An amendment is already under way.")]
	var window: int = GameStateScript.AmendWindow.INAUGURATION if phase == GameStateScript.TermPhase.INAUGURATION else GameStateScript.AmendWindow.FAREWELL
	state.windows_used[window] = true   # a window that is passed is gone
	return [_log(state, "window_passed", {"leader": player_id, "window": window})]


static func _end_turn(state: GameStateScript, player_id: int) -> Array:
	var waiting: Array = state.term["waiting"]
	if waiting.is_empty() or player_id != waiting[0]:
		return [_reject(player_id, "It isn't your turn.")]
	if state.term.get("act", {}).get("phase", -1) != GameStateScript.ActPhase.DONE:
		return [_reject(player_id, "Finish your performance first.")]
	if not state.choice.is_empty() and state.choice["player"] == player_id:
		return [_reject(player_id, "Make your choice first.")]
	if not state.command.is_empty():
		return [_reject(player_id, "A Command Performance is under way.")]
	state.term.erase("act")
	waiting.pop_front()
	state.term["played"].append(player_id)
	_sync_counts(state)
	state.last_turn_player = player_id   # the next term carries on from here
	var events: Array = [_log(state, "turn_ended", {"player": player_id})]
	events.append_array(TurnEndScript.end_turn(state, player_id))   # a debt term, a Nepo step; may eliminate
	return events


# --- the automatic steps -----------------------------------------------------------------

# Advance every step that needs no player's decision. Returns the events.
static func settle(state: GameStateScript) -> Array:
	var events: Array = []
	for i in MAX_STEPS:
		var step: Array = _step(state)
		if step.is_empty():
			return events
		events.append_array(step)
	assert(false, "the term loop did not settle after %d steps" % MAX_STEPS)
	return events


# One step, or [] if there is nothing to do until a player acts.
static func _step(state: GameStateScript) -> Array:
	if state.game_over:
		return []
	var dose: Array = DoctorScript.step(state)   # a dose in progress moves on with the clock, whatever the term is doing
	if not dose.is_empty():
		return dose
	var wills: Array = WillsScript.step(state)   # so does a will nobody signed in time
	if not wills.is_empty():
		return wills
	var command: Array = CommandPerformanceScript.step(state)   # a Command Performance moves on with the clock
	if not command.is_empty():
		return command
	var invites: Array = UnionsScript.step(state)   # and an invitation to join a union
	if not invites.is_empty():
		return invites
	var chosen: Array = CardEffectsScript.time_out(state)   # a card choice nobody made in time is made for them
	if not chosen.is_empty():
		return chosen
	match state.term.get("phase", GameStateScript.TermPhase.NONE):
		GameStateScript.TermPhase.NONE:
			# A Leader has been installed and no election is running: a new term begins.
			if state.election.is_empty() and state.leader_id != -1:
				return _start_term(state)
		GameStateScript.TermPhase.INAUGURATION:
			if _window_finished(state, GameStateScript.AmendWindow.INAUGURATION):
				return _begin_turns(state)
		GameStateScript.TermPhase.TURNS:
			return _advance_turns(state)
		GameStateScript.TermPhase.FAREWELL:
			if _window_finished(state, GameStateScript.AmendWindow.FAREWELL):
				return _end_term(state)
	return []


# The window is over once its amendment (if any) has been settled and the window has been used
# or passed, or the Leader couldn't have used it anyway.
static func _window_finished(state: GameStateScript, window: int) -> bool:
	if not state.amend.is_empty():
		return false
	return state.windows_used[window] or PermissionsScript.leader_powers_problem(state, state.leader_id) != ""


static func _start_term(state: GameStateScript) -> Array:
	state.term = {"phase": GameStateScript.TermPhase.INAUGURATION}
	return [_log(state, "term_started", {"leader": state.leader_id, "leader_type": state.leader_type, "round": state.current_round})]


# The Inauguration is over: collect the levy, then set the turn order.
static func _begin_turns(state: GameStateScript) -> Array:
	var events: Array = [_collect_levy(state)]
	state.term = {"phase": GameStateScript.TermPhase.TURNS, "played": [], "waiting": _turn_order(state), "announced": -1}
	_sync_counts(state)
	return events


# Every player pays the levy as it stands in the Constitution, whatever they earn. What a
# player can't cover becomes debt.
static func _collect_levy(state: GameStateScript) -> Dictionary:
	var levy: int = LawScript.get_int(state, "levy")
	var unpaid: Dictionary = {}
	for id in state.player_ids:
		if state.eliminated.get(id, false):
			continue
		var owed: int = DebtScript.charge(state, id, DebtScript.TREASURY_ID, levy)
		if owed > 0:
			unpaid[id] = owed
	return _log(state, "levy_collected", {"levy": levy, "unpaid": unpaid})


# The order of turns this term. Play carries on round the table from where the last term stopped:
# the first turn goes to the player after the one who took the last turn (the first seat in the very
# first term). Only after a coup does the new Leader go first, and play continues from them.
# Eliminated players are skipped. With nobody eliminated and no coup, every term therefore starts
# with the same player, because a term is one full lap.
static func _turn_order(state: GameStateScript) -> Array:
	var seats: Array = state.player_ids
	var start: int = 0
	if state.leader_goes_first:
		start = seats.find(state.leader_id)
	elif state.last_turn_player != 0:
		start = (seats.find(state.last_turn_player) + 1) % seats.size()
	state.leader_goes_first = false   # a coup affects one term only
	var order: Array = []
	for i in seats.size():
		var id: int = seats[(start + i) % seats.size()]
		if not state.eliminated.get(id, false):
			order.append(id)
	return order


static func _advance_turns(state: GameStateScript) -> Array:
	var waiting: Array = state.term["waiting"]
	if waiting.is_empty():
		state.term["phase"] = GameStateScript.TermPhase.FAREWELL
		return [_log(state, "farewell_opened", {"leader": state.leader_id})]
	if state.term["announced"] != waiting[0]:
		state.term["announced"] = waiting[0]
		return [_log(state, "turn_started", {"player": waiting[0]})]
	var events: Array = []
	if state.term.get("paid", -1) != waiting[0]:
		state.term["paid"] = waiting[0]
		events.append_array(IncomeScript.pay(state, waiting[0]))   # logs its own event
	events.append_array(PerformanceTurnScript.step(state, waiting[0]))   # the performance: start, vote, result; logs its own events
	return events


# The term is over: the Leader is credited and the next election begins.
static func _end_term(state: GameStateScript) -> Array:
	var events: Array = [_log(state, "term_ended", {"leader": state.leader_id, "round": state.current_round})]
	state.term = {}
	events.append_array(LevyBandScript.shift_at_term_end(state))   # logs its own event
	events.append_array(ElectionScript.begin(state, "term_ended"))   # credits the Leader; logs its own events
	return events


# turns_played and player_count are what Permissions uses to open the Mid-term and Farewell windows.
static func _sync_counts(state: GameStateScript) -> void:
	state.turns_played = state.term["played"].size()
	state.player_count = state.term["played"].size() + state.term["waiting"].size()


static func _log(state: GameStateScript, type: String, data: Dictionary) -> Dictionary:
	var event: Dictionary = EventsScript.make(type, data)
	state.event_log.append(event)
	return event


static func _reject(player_id: int, reason: String) -> Dictionary:
	return EventsScript.make("rejected", {"reason": reason}, [player_id])
