extends SceneTree

const ElimScript = preload("res://scripts/elimination.gd")
const DebtScript = preload("res://scripts/debt.gd")
const FlowScript = preload("res://scripts/amendment_flow.gd")
const ViewsScript = preload("res://scripts/views.gd")
const ScoringScript = preload("res://scripts/scoring.gd")
const GameStateScript = preload("res://scripts/game_state.gd")
const ConstitutionScript = preload("res://scripts/constitution.gd")
const ACTIVIST = GameStateScript.UnionType.ACTIVIST

const TREASURY := 0
const SERVER := 0
var failures: int = 0


func _init() -> void:
	cash_estates()
	void_wills()
	debt_estates()
	claims_on_the_dead()
	unions_and_votes()
	through_the_turn_end()
	print("%d failure(s)" % failures)
	quit(1 if failures > 0 else 0)


func cash_estates() -> void:
	var s := make_state()
	var money: int = total_money(s)
	var ev := ElimScript.eliminate(s, 3, "test")
	expect("no will: the events", types(ev), ["player_eliminated", "estate_settled"])
	expect("no will: cash goes to the treasury", s.treasury, 1000)
	expect("no will: they hold nothing", s.psd[3], 0)
	expect("marked eliminated", s.eliminated[3], true)
	expect("no money was created or lost", total_money(s), money)

	s = make_state()
	s.wills[3] = will(4)
	ev = ElimScript.eliminate(s, 3, "test")
	expect("will: the events", types(ev), ["player_eliminated", "will_read", "estate_settled", "nepo_baby"])
	expect("will: the heir gets the cash", s.psd[4], 2000)
	expect("will: the treasury gets nothing", s.treasury, 0)
	expect("will: the heir is recorded", s.heirs[3], 4)
	expect("will: it has been carried out, so it is gone", s.wills.has(3), false)
	expect("the will reading is public", ev[1]["audience"], [])
	expect("the estate event says what moved", [ev[2]["heir"], ev[2]["cash"]], [4, 1000])

	# The heir's own debt is paid first, oldest first (collection is immediate).
	s = make_state()
	s.psd[4] = 0
	DebtScript.charge(s, 4, TREASURY, 40)
	s.wills[3] = will(4)
	ElimScript.eliminate(s, 3, "test")
	expect("heir pays their own debt out of the inheritance", DebtScript.total_debt(s, 4), 0)
	expect("... and keeps the rest", s.psd[4], 960)
	expect("... the treasury was paid", s.treasury, 40)


func void_wills() -> void:
	var s := make_state()
	s.wills[3] = will(4)
	s.wills[3]["on_hold"] = true
	var ev := ElimScript.eliminate(s, 3, "test")
	expect("a will on hold doesn't count", types(ev), ["player_eliminated", "will_void", "estate_settled"])
	expect("... the reason is given", ev[1]["reason"], "the will was on hold")
	expect("... so the cash goes to the treasury", s.treasury, 1000)
	expect("... and nobody inherits", s.heirs.has(3), false)
	expect("... the spent will is removed", s.wills.has(3), false)

	s = make_state()
	s.wills[3] = will(3)
	expect("naming yourself is void", ElimScript.eliminate(s, 3, "test")[1]["type"], "will_void")
	s = make_state()
	s.wills[3] = will(99)
	expect("an heir who isn't playing is void", ElimScript.eliminate(s, 3, "test")[1]["type"], "will_void")
	s = make_state()
	s.eliminated[4] = true
	s.wills[3] = will(4)
	expect("an heir who is already eliminated is void", ElimScript.eliminate(s, 3, "test")[1]["type"], "will_void")
	expect("... the cash goes to the treasury", s.treasury, 1000)


func debt_estates() -> void:
	# An heir can't refuse. A poor heir inherits the debt in full.
	var s := make_state()
	s.psd[3] = 0
	s.psd[4] = 0
	DebtScript.charge(s, 3, TREASURY, 300)
	s.wills[3] = will(4)
	var ev := ElimScript.eliminate(s, 3, "test")
	expect("poor heir inherits the debt", DebtScript.total_debt(s, 4), 300)
	expect("the dead player owes nothing", DebtScript.total_debt(s, 3), 0)
	expect("the estate event says so", [ev[2]["debt_taken_by_heir"], ev[2]["debt_cleared"]], [300, 0])

	# A rich heir pays it at once, because debt is collected the moment it arrives.
	s = make_state()
	s.psd[3] = 0
	DebtScript.charge(s, 3, TREASURY, 300)
	s.wills[3] = will(4)
	var money: int = total_money(s)
	ElimScript.eliminate(s, 3, "test")
	expect("rich heir pays the inherited debt", DebtScript.total_debt(s, 4), 0)
	expect("... out of their own cash", s.psd[4], 700)
	expect("... to the original creditor", s.treasury, 300)
	expect("money is conserved", total_money(s), money)

	# The inherited debt keeps its place in the queue behind the heir's own debts.
	s = make_state()
	s.psd[3] = 0
	s.psd[4] = 0
	DebtScript.charge(s, 4, 5, 10)
	DebtScript.charge(s, 3, TREASURY, 300)
	s.wills[3] = will(4)
	ElimScript.eliminate(s, 3, "test")
	expect("heir's own debt stays first", s.debts[4][0]["creditor"], 5)
	expect("inherited debt joins behind it", s.debts[4][1]["creditor"], TREASURY)

	# No heir: the debt disappears with them and their creditors lose out.
	s = make_state()
	s.psd[3] = 0
	DebtScript.charge(s, 3, 5, 300)
	ev = ElimScript.eliminate(s, 3, "debt")
	expect("no heir: the debt is cleared", DebtScript.total_debt(s, 3), 0)
	expect("... the creditor is not paid", s.psd[5], 1000)
	expect("... and the event says 300 was cleared", ev[1]["debt_cleared"], 300)

	# If the dead player owed the heir, the heir doesn't inherit a debt to themselves.
	s = make_state()
	s.psd[3] = 0
	DebtScript.charge(s, 3, 4, 50)
	DebtScript.charge(s, 3, TREASURY, 20)
	s.wills[3] = will(4)
	s.psd[4] = 0
	ElimScript.eliminate(s, 3, "test")
	expect("only the debt to others is inherited", DebtScript.total_debt(s, 4), 20)
	expect("... never one to themselves", s.debts[4].size(), 1)


func claims_on_the_dead() -> void:
	# Player 2 owes player 3 money; player 3 is eliminated.
	var s := make_state()
	s.psd[2] = 0
	DebtScript.charge(s, 2, 3, 100)
	s.wills[3] = will(4)
	var ev := ElimScript.eliminate(s, 3, "test")
	expect("with an heir: player 2 now owes the heir", s.debts[2][0]["creditor"], 4)
	DebtScript.receive(s, 2, 100)
	expect("... and paying goes to the heir (1000 + 1000 inherited + 100), not the dead", [s.psd[4], s.psd[3]], [2100, 0])

	s = make_state()
	s.psd[2] = 0
	DebtScript.charge(s, 2, 3, 100)
	ev = ElimScript.eliminate(s, 3, "test")
	expect("no heir: the claim is cleared", DebtScript.total_debt(s, 2), 0)
	expect("... and the event says 100", ev[1]["claims_cleared"], 100)

	s = make_state()
	s.psd[4] = 0
	DebtScript.charge(s, 4, 3, 100)
	s.wills[3] = will(4)
	ElimScript.eliminate(s, 3, "test")
	expect("the heir owed the dead player: that debt is cancelled", DebtScript.total_debt(s, 4), 0)

	s = make_state()
	s.psd[2] = 0
	DebtScript.charge(s, 2, 3, 100)
	DebtScript.end_of_turn(s, 2)
	ElimScript.eliminate(s, 3, "test")
	expect("a debtor whose only debt was cleared starts again from 0 terms", s.debt_terms[2], 0)


func unions_and_votes() -> void:
	var s := make_state()
	s.unions[1] = {"type": ACTIVIST, "owner": 2, "members": [2, 3, 4], "confront_used": false}
	s.unions[2] = {"type": ACTIVIST, "owner": 5, "members": [3, 5], "confront_used": false}
	s.unions[3] = {"type": ACTIVIST, "owner": 3, "members": [3, 4, 5], "confront_used": false}
	var ev := ElimScript.eliminate(s, 3, "test")
	expect("a member leaves the union", s.unions[1]["members"], [2, 4])
	expect("a union left with one member dissolves", s.unions.has(2), false)
	expect("a union whose unionizer is eliminated dissolves (assumed)", s.unions.has(3), false)
	expect("both dissolutions are announced", types(ev).count("union_dissolved"), 2)

	# A vote that was waiting for the eliminated player is now complete.
	s = make_state()
	var words: Array = s.articles[2]
	var texts: Array = []
	for i in words.size():
		texts.append("30%" if i == 1 else words[i]["text"])
	FlowScript.handle(s, 1, {"type": "propose", "window": 0, "article_id": 2, "new_texts": texts})
	FlowScript.handle(s, SERVER, {"type": "rule_grammar", "ok": true})
	for id in [2, 3, 4]:
		FlowScript.handle(s, id, {"type": "vote", "keep": true})
	expect("still waiting for player 5", s.amend["phase"], GameStateScript.AmendPhase.VOTING)
	ev = ElimScript.eliminate(s, 5, "test")
	expect("eliminating the last voter finishes the vote", types(ev).has("amendment_resolved"), true)
	expect("... and the amendment stands", ConstitutionScript.to_text(s.articles[2]), "Tax: 30% of income goes to the treasury every round.")
	expect("... with 4 active players the swing is 7: 7 x 3", s.popularity[1], 21)

	# A dissolved union that had confronted doesn't crash the tally.
	s = make_state()
	s.unions[1] = {"type": ACTIVIST, "owner": 2, "members": [2, 3], "confront_used": false}
	FlowScript.handle(s, 1, {"type": "propose", "window": 0, "article_id": 2, "new_texts": texts})
	FlowScript.handle(s, SERVER, {"type": "rule_grammar", "ok": true})
	FlowScript.handle(s, 2, {"type": "confront", "union_id": 1})
	ElimScript.eliminate(s, 3, "test")
	expect("the union dissolved", s.unions.has(1), false)
	expect("player 2's automatic vote ended with the union: they vote by hand now", FlowScript.handle(s, 2, {"type": "vote", "keep": true})[0]["type"], "vote_cast")
	FlowScript.handle(s, 4, {"type": "vote", "keep": true})
	var done := FlowScript.handle(s, 5, {"type": "vote", "keep": true})
	expect("the vote still finishes, without crashing", types(done).has("amendment_resolved"), true)


func through_the_turn_end() -> void:
	var s := make_state()
	s.psd[3] = 0
	DebtScript.charge(s, 3, TREASURY, 25)
	s.wills[3] = will(4)
	expect("turn 1 in debt: nothing happens", ElimScript.end_turn(s, 3), [])
	expect("turn 2 in debt: nothing happens", ElimScript.end_turn(s, 3), [])
	var ev := ElimScript.end_turn(s, 3)
	expect("turn 3 in debt: eliminated", types(ev), ["player_eliminated", "will_read", "estate_settled", "nepo_baby"])
	expect("the reason is debt", ev[0]["reason"], "debt")
	expect("the heir paid the 25 out of their own cash", s.psd[4], 975)

	s.half_rounds = {1: 2, 2: 2, 3: 10, 4: 2, 5: 2}
	s.player_ids = [1, 2, 3, 4, 5]
	expect("an eliminated player can't win, whatever their rounds", ScoringScript.final_winners(s).has(3), false)

	# The will is a secret until it is read out.
	s = make_state()
	s.wills[3] = will(4)
	for viewer in [1, 2, 3, 4, 5]:
		expect("player %d cannot see wills" % viewer, ViewsScript.state_view(s, viewer).has("wills"), false)
	ElimScript.eliminate(s, 3, "test")
	expect("after elimination everyone sees who inherited", ViewsScript.state_view(s, 1)["heirs"], {3: 4})


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


func will(heir: int) -> Dictionary:
	return {"psd_heir": heir, "on_hold": false}


func total_money(s: GameStateScript) -> int:
	var total: int = s.treasury
	for id in s.psd:
		total += s.psd[id]
	return total


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
