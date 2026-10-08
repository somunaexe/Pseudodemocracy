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
	if player_id != state.leader_id:
		return "Only the Leader can amend the Constitution."
	if state.leader_type == GameStateScript.LeaderType.COMMANDER:
		return "A Commander can't amend."
	if state.sick.get(player_id, false):
		return "A sick Leader can't amend."
	if PopularityScript.effective(state, player_id) <= GameDataScript.get_int("cancelledAt"):
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
