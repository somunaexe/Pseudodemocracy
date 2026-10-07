extends SceneTree

const PermissionsScript = preload("res://scripts/permissions.gd")
const GameStateScript = preload("res://scripts/game_state.gd")

const INAUG = GameStateScript.Window.INAUGURATION
const MID = GameStateScript.Window.MID_TERM
const FAREWELL = GameStateScript.Window.FAREWELL

var failures: int = 0


func _init() -> void:
	var s: GameStateScript

	s = make_state()
	check("leader, open inauguration", s, 1, INAUG, true)

	s = make_state()
	check("not the leader", s, 2, INAUG, false)

	s = make_state()
	s.leader_type = GameStateScript.LeaderType.COMMANDER
	check("commander", s, 1, INAUG, false)

	s = make_state()
	s.sick[1] = true
	check("sick leader", s, 1, INAUG, false)

	s = make_state()
	s.popularity[1] = -50
	check("cancelled at -50", s, 1, INAUG, false)

	s = make_state()
	s.popularity[1] = -49
	check("not cancelled at -49", s, 1, INAUG, true)

	s = make_state()
	s.windows_used[INAUG] = true
	check("window already used", s, 1, INAUG, false)

	s = make_state()
	s.turns_played = 2
	check("mid-term, 5 players, 2 turns", s, 1, MID, false)

	s = make_state()
	s.turns_played = 3
	check("mid-term, 5 players, 3 turns", s, 1, MID, true)

	s = make_state()
	s.player_count = 4
	s.turns_played = 2
	check("mid-term, 4 players, 2 turns", s, 1, MID, true)

	s = make_state()
	s.turns_played = 4
	check("farewell, 4 of 5 turns", s, 1, FAREWELL, false)

	s = make_state()
	s.turns_played = 5
	check("farewell, 5 of 5 turns", s, 1, FAREWELL, true)

	# Order: a stranger must get the "not the Leader" message, not the Leader's condition.
	s = make_state()
	s.sick[1] = true
	var msg: String = PermissionsScript.can_amend(s, 2, INAUG)
	report("stranger sees identity message first", msg.begins_with("Only the Leader"), msg)

	print("%d failure(s)" % failures)
	quit(1 if failures > 0 else 0)


func make_state() -> GameStateScript:
	var s: GameStateScript = GameStateScript.new()
	s.player_count = 5
	s.turns_played = 0
	s.leader_id = 1
	s.leader_type = GameStateScript.LeaderType.PRESIDENT
	s.popularity = {1: 0, 2: 0}
	s.sick = {1: false, 2: false}
	return s


func check(label: String, s: GameStateScript, player_id: int, window: int, should_pass: bool) -> void:
	var result: String = PermissionsScript.can_amend(s, player_id, window)
	report(label, result.is_empty() == should_pass, result)


func report(label: String, ok: bool, detail: String) -> void:
	if not ok:
		failures += 1
	print(("PASS " if ok else "FAIL ") + label + " -> '" + detail + "'")
