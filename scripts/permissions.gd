class_name Permissions

# Loaded by path (not by class_name) so this works in a fresh headless run
# before Godot has built its class cache.
const GameStateScript = preload("res://scripts/game_state.gd")

# TODO: load from the game data (cancelledAt in game_data.js) instead of typing it here.
const CANCELLED_AT := -50


# Returns "" if allowed, or the reason it isn't.
# Checks run from most basic to most specific: who you are, your role,
# your condition, then timing. So a stranger learns nothing about the Leader.
static func can_amend(state: GameStateScript, player_id: int, window: GameStateScript.AmendWindow) -> String:
	if player_id != state.leader_id:
		return "Only the Leader can amend the Constitution."
	if state.leader_type == GameStateScript.LeaderType.COMMANDER:
		return "A Commander can't amend."
	if state.sick.get(player_id, false):
		return "A sick Leader can't amend."
	if state.popularity.get(player_id, 0) <= CANCELLED_AT:
		return "A CANCELLED Leader can't amend."
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
