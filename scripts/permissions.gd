class_name Permissions

# Loaded by path (not by class_name) so this works in a fresh headless run
# before Godot has built its class cache.
const GameStateScript = preload("res://scripts/game_state.gd")
const PopularityScript = preload("res://scripts/popularity.gd")

const GameDataScript = preload("res://scripts/game_data.gd")


# Returns "" if this player may use Leader powers at all, or the reason they may not: they are
# not the Leader, they are a Commander, or they are sick or CANCELLED. Checks run from most basic
# to most specific, so a stranger learns nothing about the Leader.
static func leader_powers_problem(state: GameStateScript, player_id: int) -> String:
	if player_id == state.vice_id and state.vice_id != -1 and player_id != state.leader_id:
		# The Vice proposes with the Leader (they amend together), so the Leader must be able to amend too.
		var leaders: String = leader_powers_problem(state, state.leader_id)
		if leaders != "":
			return leaders
		if state.sick.get(player_id, false):
			return "A sick Vice can't amend."
		if PopularityScript.is_cancelled(state, player_id):
			return "A CANCELLED Vice can't amend."
		return ""
	if player_id != state.leader_id:
		return "Only the Leader can amend the Constitution."
	if state.leader_type == GameStateScript.LeaderType.COMMANDER:
		return "A Commander can't amend."
	if state.sick.get(player_id, false):
		return "A sick Leader can't amend."
	if PopularityScript.is_cancelled(state, player_id):
		return "A CANCELLED Leader can't amend."
	return ""


# Returns "" if allowed, or the reason it isn't: Leader powers first, then the timing.
static func can_amend(state: GameStateScript, player_id: int, window: GameStateScript.AmendWindow) -> String:
	var problem: String = leader_powers_problem(state, player_id)
	if problem != "":
		return problem
	if state.windows_used[window]:
		return "This amendment window has already been used."
	if not window_open(state, window):
		return "This amendment window isn't open yet."
	return ""


# Who must agree to a proposal by this player: the other of the Leader and the Vice, or 0 when nobody has to (there is no
# Vice, or the Vice is sick, CANCELLED or out of the game and so can't take part). The Leader and the Vice amend together.
static func cosigner(state: GameStateScript, proposer: int) -> int:
	if state.vice_id == -1 or state.leader_id == -1:
		return 0
	var other: int = state.vice_id if proposer == state.leader_id else state.leader_id
	if other == state.leader_id and (state.eliminated.get(other, false) or state.sick.get(other, false)):
		return 0
	if other == state.vice_id and (state.eliminated.get(other, false) or state.sick.get(other, false) or PopularityScript.is_cancelled(state, other)):
		return 0
	return other


# Amendments happen at set moments of a term: the Inauguration window at the Inauguration, the Mid-term window once half have
# played, the Farewell window at the Farewell. Returns why the window is not open now, or "".
static func timing_problem(state: GameStateScript, window: GameStateScript.AmendWindow) -> String:
	var phase: int = state.term.get("phase", GameStateScript.TermPhase.NONE)
	if phase == GameStateScript.TermPhase.NONE or not state.election.is_empty():
		return "The Constitution can only be amended during a term."
	if window == GameStateScript.AmendWindow.INAUGURATION and phase != GameStateScript.TermPhase.INAUGURATION:
		return "The Inauguration amendment can only be made at the Inauguration."
	if window == GameStateScript.AmendWindow.MID_TERM and phase == GameStateScript.TermPhase.INAUGURATION:
		return "The Mid-term amendment can't be made at the Inauguration."
	if window == GameStateScript.AmendWindow.FAREWELL and phase != GameStateScript.TermPhase.FAREWELL:
		return "The Farewell amendment can only be made at the Farewell."
	return ""


# Mid-term opens once half the players (rounded up) have played; Farewell once all have.
static func window_open(state: GameStateScript, window: GameStateScript.AmendWindow) -> bool:
	match window:
		GameStateScript.AmendWindow.INAUGURATION:
			return true
		GameStateScript.AmendWindow.MID_TERM:
			return state.turns_played >= ceili(state.player_count / 2.0)
		GameStateScript.AmendWindow.FAREWELL:
			return state.turns_played >= state.player_count
	return false
