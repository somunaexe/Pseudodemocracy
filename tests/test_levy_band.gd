extends SceneTree

const GameScript = preload("res://scripts/game.gd")
const LawScript = preload("res://scripts/law.gd")
const LevyBandScript = preload("res://scripts/levy_band.gd")
const PopularityScript = preload("res://scripts/popularity.gd")
const GameStateScript = preload("res://scripts/game_state.gd")
const PlayScript = preload("res://tests/play.gd")

const PRESIDENT = GameStateScript.LeaderType.PRESIDENT
const INAUG = GameStateScript.AmendWindow.INAUGURATION
const SERVER := 0

var failures: int = 0


func _init() -> void:
	the_band_starts_where_the_data_says()
	the_levy_must_stay_in_the_band()
	the_band_rises()
	the_band_falls()
	the_floor_and_the_edges()
	amended_triggers_and_no_leader()
	a_term_ending_moves_the_band()
	print("%d failure(s)" % failures)
	quit(1 if failures > 0 else 0)


func the_band_starts_where_the_data_says() -> void:
	var s := new_term()
	expect("the band starts at 25 to 50", s.levy_band, {"low": 25, "high": 50})
	expect("the Article 5 triggers start at 20", [LawScript.get_int(s, "levyRaiseBelow"), LawScript.get_int(s, "levyLowerAbove")], [20, 20])


func the_levy_must_stay_in_the_band() -> void:
	# Article 3 is amended through the normal flow; a levy outside the band is a failed check.
	var s := new_term()
	var fine_before: int = s.psd[2]
	var ev := send(s, 2, propose(s, INAUG, "60"))
	expect("a levy above the band fails the check, and the term moves on", types(ev), ["amendment_proposed", "amendment_failed", "levy_collected", "turn_started", "income_paid", "performance_started"])
	expect("... with the reason", ev[1]["reason"], "The levy must stay within the levy band, 25 to 50 PSD.")
	expect("... the fine was paid", s.psd[2] < fine_before, true)
	expect("... the window is used and the levy unchanged", [s.windows_used[INAUG], LawScript.get_int(s, "levy")], [true, 25])

	s = new_term()
	expect("a levy below the band fails the check", send(s, 2, propose(s, INAUG, "24"))[1]["type"], "amendment_failed")
	s = new_term()
	expect("the top of the band is allowed", types(send(s, 2, propose(s, INAUG, "50"))), ["amendment_proposed"])
	s = new_term()
	expect("the bottom of the band is allowed", types(send(s, 2, propose(s, INAUG, "25"))), ["amendment_proposed"])
	s = new_term()
	s.levy_band = {"low": 35, "high": 60}
	expect("a shifted band moves the limits: 30 now fails", send(s, 2, propose(s, INAUG, "30"))[1]["type"], "amendment_failed")


func the_band_rises() -> void:
	var s := new_term()
	s.popularity[2] = -21
	var ev := LevyBandScript.shift_at_term_end(s)
	expect("a Leader below -20 raises the band by 10", s.levy_band, {"low": 35, "high": 60})
	expect("... the levy of 25 moves to the closest value inside, 35", LawScript.get_int(s, "levy"), 35)
	expect("... the Constitution reads 35", ConstitutionText(s, 3).contains("levy of 35 PSD"), true)
	expect("... one event, logged once", [types(ev), s.event_log.back() == ev[0]], [["levy_band_shifted"], true])
	expect("... telling everyone what moved", [ev[0]["old_band"], ev[0]["new_band"], ev[0]["old_levy"], ev[0]["new_levy"]], [[25, 50], [35, 60], 25, 35])

	s = new_term()
	s.popularity[2] = -21
	LawScript.set_int(s, "levy", 40)
	LevyBandScript.shift_at_term_end(s)
	expect("a levy already inside the new band stays put", LawScript.get_int(s, "levy"), 40)


func the_band_falls() -> void:
	var s := new_term()
	s.levy_band = {"low": 35, "high": 60}
	LawScript.set_int(s, "levy", 55)
	s.popularity[2] = 21
	LevyBandScript.shift_at_term_end(s)
	expect("a Leader above +20 lowers the band by 10", s.levy_band, {"low": 25, "high": 50})
	expect("... a levy of 55 moves down to 50", LawScript.get_int(s, "levy"), 50)


func the_floor_and_the_edges() -> void:
	var s := new_term()
	s.levy_band = {"low": 30, "high": 55}
	s.popularity[2] = 30
	LevyBandScript.shift_at_term_end(s)
	expect("the floor stops the low end at 25 and the high end moves by the same 5", s.levy_band, {"low": 25, "high": 50})

	s = new_term()
	s.popularity[2] = 30
	expect("already at the floor: no change and no event", [types(LevyBandScript.shift_at_term_end(s)), s.levy_band], [[], {"low": 25, "high": 50}])

	for edge in [-20, 20, 0]:
		s = new_term()
		s.popularity[2] = edge
		expect("popularity %d is not past the trigger: no shift" % edge, [types(LevyBandScript.shift_at_term_end(s)), s.levy_band], [[], {"low": 25, "high": 50}])

	s = new_term()
	s.nepo[2] = 1   # a Nepo Baby: the debuff counts, not just the base
	expect("the Nepo debuff counts: the base is 0 but the effective popularity is below -20", PopularityScript.effective(s, 2) < -20, true)
	LevyBandScript.shift_at_term_end(s)
	expect("... so the band rises", s.levy_band, {"low": 35, "high": 60})


func amended_triggers_and_no_leader() -> void:
	var s := new_term()
	set_word(s, 5, 4, "30")   # Article 5: raise only below -30
	s.popularity[2] = -25
	expect("an amended trigger is obeyed: -25 is not below -30", [types(LevyBandScript.shift_at_term_end(s)), s.levy_band], [[], {"low": 25, "high": 50}])
	s.popularity[2] = -31
	LevyBandScript.shift_at_term_end(s)
	expect("... but -31 is", s.levy_band, {"low": 35, "high": 60})

	expect("a trigger the game can't read is refused at proposal", send(new_term(), 2, propose_slot(new_term(), 5, INAUG, 4, "lots"))[1]["type"], "amendment_failed")

	s = new_term()
	s.leader_id = -1
	expect("no Leader, no shift", types(LevyBandScript.shift_at_term_end(s)), [])


func a_term_ending_moves_the_band() -> void:
	# The real path: the Farewell is passed, the term ends, the band shifts before the next election.
	var s := new_term()
	send(s, 2, {"type": "pass_window"})
	for id in [2, 3, 4, 5, 1]:
		PlayScript.take_turn(s, id)
	s.popularity[2] = -40
	var ended := send(s, 2, {"type": "pass_window"})
	expect("the band shifts between the term ending and the election", types(ended), ["window_passed", "term_ended", "levy_band_shifted", "election_started"])
	expect("... and the new band stands", s.levy_band, {"low": 35, "high": 60})


# --- helpers -----------------------------------------------------------------------------

func new_term() -> GameStateScript:
	for seed_value in range(1, 400):
		var s := GameScript.new_game([1, 2, 3, 4, 5], seed_value)
		for id in [1, 2, 3, 4, 5]:
			GameScript.handle(s, id, {"type": "cast_vote", "candidate": 2})
		if s.leader_type == PRESIDENT:
			return s
	assert(false, "no seed gave a President")
	return null


func propose(s: GameStateScript, window: int, text: String) -> Dictionary:
	return propose_slot(s, 3, window, 3, text)


func propose_slot(s: GameStateScript, article_id: int, window: int, slot: int, text: String) -> Dictionary:
	var texts: Array = []
	var seen: int = 0
	for word in s.articles[article_id]:
		if word["amendable"]:
			texts.append(text if seen == slot else word["text"])
			seen += 1
		else:
			texts.append(word["text"])
	return {"type": "propose", "window": window, "article_id": article_id, "new_texts": texts}


func set_word(s: GameStateScript, article_id: int, slot: int, text: String) -> void:
	var seen: int = 0
	for word in s.articles[article_id]:
		if word["amendable"]:
			if seen == slot:
				word["text"] = text
				return
			seen += 1


func ConstitutionText(s: GameStateScript, article_id: int) -> String:
	return preload("res://scripts/constitution.gd").to_text(s.articles[article_id])


func send(s: GameStateScript, player_id: int, command: Dictionary) -> Array:
	return GameScript.handle(s, player_id, command)


func types(events: Array) -> Array:
	var result: Array = []
	for event in events:
		result.append(event["type"])
	return result


func expect(label: String, actual: Variant, wanted: Variant) -> void:
	var ok: bool = typeof(actual) == typeof(wanted) and actual == wanted
	if not ok:
		failures += 1
	print(("PASS " if ok else "FAIL ") + label + " -> " + str(actual).left(90))
