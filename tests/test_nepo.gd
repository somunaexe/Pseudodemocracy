extends SceneTree

const NepoScript = preload("res://scripts/nepo.gd")
const PopularityScript = preload("res://scripts/popularity.gd")
const TurnEndScript = preload("res://scripts/turn_end.gd")
const ElimScript = preload("res://scripts/elimination.gd")
const DebtScript = preload("res://scripts/debt.gd")
const PermissionsScript = preload("res://scripts/permissions.gd")
const ScoringScript = preload("res://scripts/scoring.gd")
const FlowScript = preload("res://scripts/amendment_flow.gd")
const ViewsScript = preload("res://scripts/views.gd")
const LawScript = preload("res://scripts/law.gd")
const GameStateScript = preload("res://scripts/game_state.gd")
const ConstitutionScript = preload("res://scripts/constitution.gd")

const INAUG = GameStateScript.AmendWindow.INAUGURATION
const SERVER := 0
const TREASURY := 0
var failures: int = 0


func _init() -> void:
	the_lifecycle()
	what_counts_and_what_does_not()
	the_law_can_change_it()
	becoming_a_nepo_baby()
	print("%d failure(s)" % failures)
	quit(1 if failures > 0 else 0)


func the_lifecycle() -> void:
	expect("the steps come from the game data", NepoScript.magnitudes(), [30, 20, 10])

	var s := make_state()
	s.popularity[3] = 10
	expect("not a Nepo Baby: no change", PopularityScript.modifier(s, 3), 0)
	var ev := NepoScript.become(s, 3)
	expect("becoming one is announced, step 1, -30", [ev[0]["type"], ev[0]["step"], ev[0]["change"]], ["nepo_baby", 1, -30])
	expect("step 1: -30", PopularityScript.modifier(s, 3), -30)
	expect("... popularity is 10 - 30", PopularityScript.effective(s, 3), -20)

	ev = TurnEndScript.end_turn(s, 3)
	expect("end of their turn: step 2", [types(ev), ev[0]["change"]], [["nepo_baby_step"], -20])
	expect("step 2: popularity is 10 - 20", PopularityScript.effective(s, 3), -10)
	ev = TurnEndScript.end_turn(s, 3)
	expect("step 3: popularity is 10 - 10", PopularityScript.effective(s, 3), 0)
	ev = TurnEndScript.end_turn(s, 3)
	expect("the debuff is lifted", types(ev), ["nepo_baby_ended"])
	expect("... popularity comes back", PopularityScript.effective(s, 3), 10)
	expect("... they are no longer a Nepo Baby", s.nepo.has(3), false)
	expect("... nothing more happens", TurnEndScript.end_turn(s, 3), [])
	expect("their own popularity was never changed", s.popularity[3], 10)

	# Other players' turns don't move it on.
	s = make_state()
	NepoScript.become(s, 3)
	TurnEndScript.end_turn(s, 2)
	TurnEndScript.end_turn(s, 4)
	expect("only their own turn counts", s.nepo[3], 1)


func what_counts_and_what_does_not() -> void:
	# The track is -50 to +50 and the debuff can't take a score off it.
	var s := make_state()
	s.popularity[3] = -40
	NepoScript.become(s, 3)
	expect("-40 and -30 stays on the track at -50", PopularityScript.effective(s, 3), -50)
	s.popularity[4] = 45
	NepoScript.become(s, 4)
	s.nepo[4] = 1
	expect("a bonus can't go past +50 either", PopularityScript.effective(s, 4), 15)

	# CANCELLED is judged on the effective popularity.
	s = make_state()
	s.popularity[1] = -25
	expect("a Leader at -25 can amend", PermissionsScript.can_amend(s, 1, INAUG), "")
	NepoScript.become(s, 1)
	expect("... but as a Nepo Baby they are at -50: CANCELLED", PermissionsScript.can_amend(s, 1, INAUG), "A CANCELLED Leader can't amend.")
	TurnEndScript.end_turn(s, 1)
	expect("step 2 (-45): no longer cancelled", PermissionsScript.can_amend(s, 1, INAUG), "")

	# Votes move the base, never the debuff.
	s = make_state()
	NepoScript.become(s, 1)
	var words: Array = s.articles[2]
	var texts: Array = []
	for i in words.size():
		texts.append("30%" if i == 1 else words[i]["text"])
	FlowScript.handle(s, 1, {"type": "propose", "window": INAUG, "article_id": 2, "new_texts": texts})
	FlowScript.handle(s, SERVER, {"type": "rule_grammar", "ok": true})
	for id in [2, 3, 4, 5]:
		FlowScript.handle(s, id, {"type": "vote", "keep": true})
	expect("4 votes for, swing 6: base +24", s.popularity[1], 24)
	expect("effective is base + 24 - 30", PopularityScript.effective(s, 1), -6)

	# The final ranking uses what counts.
	s = make_state()
	s.half_rounds = {1: 4, 2: 4}
	s.player_ids = [1, 2]
	s.popularity = {1: 10, 2: -10}
	s.psd = {1: 100, 2: 100}
	expect("without a debuff the more popular player wins", ScoringScript.final_winners(s), [1])
	NepoScript.become(s, 1)
	expect("a Nepo Baby at 10 - 30 = -20 now ranks below -10", ScoringScript.final_winners(s), [2])

	# Players see what counts, plus the pieces.
	s = make_state()
	s.popularity[3] = 10
	NepoScript.become(s, 3)
	var view: Dictionary = ViewsScript.state_view(s, 4)
	expect("the view shows effective popularity", view["popularity"][3], -20)
	expect("... and the base next to it", view["popularity_base"][3], 10)
	expect("... and who the Nepo Babies are", view["nepo"], {3: 1})
	expect("others are unaffected", view["popularity"][2], 0)


func the_law_can_change_it() -> void:
	# Article 31's highlighted '-' words are signs. Flip one and the debuff becomes a bonus.
	var s := make_state()
	NepoScript.become(s, 3)
	set_rule_word(s, 31, 0, "+")
	expect("step 1 flipped to a bonus: +30 at once", PopularityScript.modifier(s, 3), 30)
	expect("... the other steps are unchanged", [NepoScript.change_for_step(s, 2), NepoScript.change_for_step(s, 3)], [-20, -10])
	TurnEndScript.end_turn(s, 3)
	expect("step 2 is still a reduction", PopularityScript.modifier(s, 3), -20)

	# Through a real amendment that stands.
	s = make_state()
	NepoScript.become(s, 3)
	var words: Array = s.articles[31]
	var texts: Array = []
	var slot: int = 0
	for word in words:
		if word["amendable"]:
			texts.append("+" if slot == 0 else word["text"])
			slot += 1
		else:
			texts.append(word["text"])
	FlowScript.handle(s, 1, {"type": "propose", "window": INAUG, "article_id": 31, "new_texts": texts})
	FlowScript.handle(s, SERVER, {"type": "rule_grammar", "ok": true})
	expect("while the vote is on, the old law applies", PopularityScript.modifier(s, 3), -30)
	for id in [2, 3, 4, 5]:
		FlowScript.handle(s, id, {"type": "vote", "keep": true})
	expect("once the amendment stands, the Nepo Baby gets +30", PopularityScript.modifier(s, 3), 30)


func becoming_a_nepo_baby() -> void:
	# Every heir becomes one (an heir can't refuse).
	var s := make_state()
	s.wills[3] = {"psd_heir": 4, "on_hold": false}
	var ev := ElimScript.eliminate(s, 3, "test")
	expect("the heir becomes a Nepo Baby", s.nepo, {4: 1})
	expect("... in the events", types(ev).has("nepo_baby"), true)
	s = make_state()
	ElimScript.eliminate(s, 3, "test")
	expect("no heir, no Nepo Baby", s.nepo.is_empty(), true)

	s = make_state()
	s.wills[3] = {"psd_heir": 4, "on_hold": false}
	s.nepo[4] = 3
	ElimScript.eliminate(s, 3, "test")
	expect("inheriting again restarts at step 1 (assumed)", s.nepo[4], 1)

	s = make_state()
	NepoScript.become(s, 3)
	ElimScript.eliminate(s, 3, "test")
	expect("an eliminated Nepo Baby loses the debuff", s.nepo.has(3), false)

	# End to end: three turns in debt, then the heir's own turns walk the debuff down.
	s = make_state()
	s.psd[3] = 0
	DebtScript.charge(s, 3, TREASURY, 25)
	s.wills[3] = {"psd_heir": 4, "on_hold": false}
	TurnEndScript.end_turn(s, 3)
	TurnEndScript.end_turn(s, 3)
	var out := TurnEndScript.end_turn(s, 3)
	expect("the third debt turn eliminates them", types(out).has("player_eliminated"), true)
	expect("a player eliminated at turn end gets no Nepo step", s.nepo.has(3), false)
	expect("their heir is a Nepo Baby at step 1", s.nepo[4], 1)
	expect("the heir's popularity is reduced", PopularityScript.effective(s, 4), -30)
	TurnEndScript.end_turn(s, 4)
	TurnEndScript.end_turn(s, 4)
	TurnEndScript.end_turn(s, 4)
	expect("after three of their own turns it is lifted", [s.nepo.has(4), PopularityScript.effective(s, 4)], [false, 0])


# --- helpers ---------------------------------------------------------------------------

func make_state() -> GameStateScript:
	var s: GameStateScript = GameStateScript.new()
	s.player_ids = [1, 2, 3, 4, 5]
	s.player_count = 5
	s.leader_id = 1
	s.leader_type = GameStateScript.LeaderType.PRESIDENT
	for id in s.player_ids:
		s.psd[id] = 1000
		s.popularity[id] = 0
		s.sick[id] = false
	s.articles = ConstitutionScript.initial_articles()
	return s


func set_rule_word(s: GameStateScript, article_id: int, slot: int, text: String) -> void:
	var seen: int = 0
	for word in s.articles[article_id]:
		if word["amendable"]:
			if seen == slot:
				word["text"] = text
				return
			seen += 1


func types(events: Array) -> Array:
	var result: Array = []
	for event in events:
		result.append(event["type"])
	return result


func expect(label: String, actual: Variant, wanted: Variant) -> void:
	var ok: bool = typeof(actual) == typeof(wanted) and actual == wanted
	if not ok:
		failures += 1
	print(("PASS " if ok else "FAIL ") + label + " -> " + str(actual).left(80))
