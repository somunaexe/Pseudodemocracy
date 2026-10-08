extends SceneTree

const FlowScript = preload("res://scripts/amendment_flow.gd")
const GameStateScript = preload("res://scripts/game_state.gd")
const ConstitutionScript = preload("res://scripts/constitution.gd")
const DebtScript = preload("res://scripts/debt.gd")

const INAUG = GameStateScript.AmendWindow.INAUGURATION
const MID = GameStateScript.AmendWindow.MID_TERM
const PROPOSED = GameStateScript.AmendPhase.PROPOSED
const VOTING = GameStateScript.AmendPhase.VOTING
const ACTIVIST = GameStateScript.UnionType.ACTIVIST
const AGBERO = GameStateScript.UnionType.AGBERO

const SERVER := 0
const TAX := 2   # "Tax: 20% of income goes to the treasury every round."
const TAX_20 := "Tax: 20% of income goes to the treasury every round."
const TAX_30 := "Tax: 30% of income goes to the treasury every round."

var failures: int = 0


func _init() -> void:
	happy_path_and_secrecy()
	president_dictator_and_ties()
	failed_checks()
	rejections_change_nothing()
	agbero_confront()
	activist_confront()
	confront_rules()
	voter_rules()
	edge_cases()
	print("%d failure(s)" % failures)
	quit(1 if failures > 0 else 0)


func happy_path_and_secrecy() -> void:
	var s := make_state()
	var ev := send(s, 1, propose(s, INAUG, {1: "30%"}))
	expect("propose is announced", types(ev), ["amendment_proposed"])
	expect("announcement is public", ev[0]["audience"], [])
	expect("window is used", s.windows_used[INAUG], true)
	expect("phase is PROPOSED", s.amend["phase"], PROPOSED)
	expect("article keeps its wording until voted", tax_text(s), TAX_20)

	ev = send(s, SERVER, {"type": "rule_grammar", "ok": true})
	expect("grammar ruling accepted", types(ev), ["grammar_ruled"])
	expect("phase is VOTING", s.amend["phase"], VOTING)

	for id in [2, 3, 4]:
		ev = send(s, id, {"type": "vote", "keep": true})
		expect("vote %d cast" % id, types(ev), ["vote_cast"])
		expect("vote event does not reveal the choice", ev[0].has("keep"), false)
	expect("votes stay in server state", s.amend["votes"].size(), 3)
	ev = send(s, 5, {"type": "vote", "keep": false})
	expect("last vote resolves", types(ev), ["vote_cast", "amendment_resolved", "article_changed"])
	expect("for / against", [ev[1]["for"], ev[1]["against"]], [3, 1])
	expect("result reveals who voted how", ev[1]["votes"][5], false)
	expect("popularity +6 x (3 - 1)", s.popularity[1], 12)
	expect("the amendment stands", tax_text(s), TAX_30)
	expect("flow is back to NONE", s.amend.is_empty(), true)
	expect("record has one entry", s.amendment_record.size(), 1)
	expect("record outcome", s.amendment_record[0]["outcome"], "stood")
	expect("event log is in order", types(s.event_log), [
		"amendment_proposed", "grammar_ruled", "vote_cast", "vote_cast", "vote_cast", "vote_cast",
		"amendment_resolved", "article_changed"])

	ev = send(s, 1, propose(s, INAUG, {1: "40%"}))
	expect("same window can't be used twice", types(ev), ["rejected"])


func president_dictator_and_ties() -> void:
	var s := open_vote(make_state())
	vote_all(s, {2: true, 3: false, 4: false, 5: false})
	expect("President: 1 for, 3 against: popularity -12", s.popularity[1], -12)
	expect("President: rejected wording is not applied", tax_text(s), TAX_20)
	expect("record says rejected", s.amendment_record[0]["outcome"], "rejected")

	s = open_vote(make_state())
	vote_all(s, {2: true, 3: true, 4: false, 5: false})
	expect("President: a tie does not stand", tax_text(s), TAX_20)
	expect("tie: popularity unchanged", s.popularity[1], 0)

	s = make_state()
	s.leader_type = GameStateScript.LeaderType.DICTATOR
	open_vote(s)
	vote_all(s, {2: false, 3: false, 4: false, 5: false})
	expect("Dictator stands with 0 for, 4 against", tax_text(s), TAX_30)
	expect("Dictator still loses popularity: 6 x -4", s.popularity[1], -24)

	s = make_state()
	s.popularity[1] = 48
	open_vote(s)
	vote_all(s, {2: true, 3: true, 4: true, 5: true})
	expect("popularity is capped at the maximum", s.popularity[1], 50)


func failed_checks() -> void:
	var s := make_state()
	var ev := send(s, 1, propose(s, INAUG, {0: "Duty:"}))
	expect("changing a fixed word fails at once", types(ev), ["amendment_proposed", "amendment_failed"])
	expect("fine paid: 100", s.psd[1], 900)
	expect("fine went to the treasury", s.treasury, 100)
	expect("popularity -6 x 4", s.popularity[1], -24)
	expect("window stays used", s.windows_used[INAUG], true)
	expect("old wording kept", tax_text(s), TAX_20)
	expect("flow is back to NONE", s.amend.is_empty(), true)
	expect("record says failed_check", s.amendment_record[0]["outcome"], "failed_check")

	s = make_state()
	send(s, 1, propose(s, INAUG, {1: "30 %"}))
	expect("a two-word replacement fails", s.amendment_record[0]["outcome"], "failed_check")

	s = make_state()
	send(s, 1, propose(s, INAUG, {1: "30%"}))
	ev = send(s, SERVER, {"type": "rule_grammar", "ok": false})
	expect("a bad grammar ruling fails the amendment", types(ev), ["grammar_ruled", "amendment_failed"])
	expect("same fine", s.psd[1], 900)
	expect("same popularity loss", s.popularity[1], -24)
	expect("old wording kept after bad grammar", tax_text(s), TAX_20)

	s = make_state()
	s.eliminated[4] = true
	send(s, 1, propose(s, INAUG, {0: "Duty:"}))
	expect("4 active players: swing 7, so -7 x 3", s.popularity[1], -21)

	s = make_state()
	s.psd[1] = 30
	send(s, 1, propose(s, INAUG, {0: "Duty:"}))
	expect("can't cover the fine: pays what they have", s.treasury, 30)
	expect("the rest becomes debt", DebtScript.total_debt(s, 1), 70)

	s = open_vote(make_state(), {1: "  30%  "})
	vote_all(s, {2: true, 3: true, 4: true, 5: true})
	expect("surrounding spaces are trimmed before storing", tax_text(s), TAX_30)


func rejections_change_nothing() -> void:
	var s := make_state()
	var ev := send(s, 2, propose(s, INAUG, {1: "30%"}))
	expect("a non-Leader is refused", types(ev), ["rejected"])
	expect("... with the identity message", ev[0]["reason"], "Only the Leader can amend the Constitution.")
	expect("... shown only to the asker", ev[0]["audience"], [2])
	expect("nothing was used", s.windows_used[INAUG], false)
	expect("nothing was logged", s.event_log.size(), 0)

	s.sick[1] = true
	ev = send(s, 2, propose(s, INAUG, {1: "30%"}))
	expect("a stranger still hears the identity message when the Leader is sick", ev[0]["reason"], "Only the Leader can amend the Constitution.")
	ev = send(s, 1, propose(s, INAUG, {1: "30%"}))
	expect("a sick Leader is refused", ev[0]["reason"], "A sick Leader can't amend.")
	s.sick[1] = false

	ev = send(s, 1, propose(s, MID, {1: "30%"}))
	expect("a closed window is refused", ev[0]["reason"], "This amendment window isn't open yet.")
	expect("the closed window was not used", s.windows_used[MID], false)

	var bad := propose(s, INAUG, {1: "30%"})
	bad["window"] = 9
	expect("an unknown window is refused", types(send(s, 1, bad)), ["rejected"])
	bad = propose(s, INAUG, {1: "30%"})
	bad["window"] = "inauguration"
	expect("a window of the wrong type is refused", types(send(s, 1, bad)), ["rejected"])
	bad = propose(s, INAUG, {1: "30%"})
	bad["article_id"] = 999
	expect("an unknown article is refused", types(send(s, 1, bad)), ["rejected"])
	bad = propose(s, INAUG, {1: "30%"})
	bad["new_texts"][1] = 30
	expect("a non-text word is refused", types(send(s, 1, bad)), ["rejected"])
	bad = propose(s, INAUG, {1: "30%"})
	bad["new_texts"] = "30%"
	expect("wording that isn't a list is refused", types(send(s, 1, bad)), ["rejected"])
	expect("none of those used the window", s.windows_used[INAUG], false)
	expect("none of those was logged", s.event_log.size(), 0)

	send(s, 1, propose(s, INAUG, {1: "30%"}))
	var logged: int = s.event_log.size()
	expect("a vote before the grammar ruling is refused", types(send(s, 2, {"type": "vote", "keep": true})), ["rejected"])
	expect("a second proposal is refused", types(send(s, 1, propose(s, INAUG, {1: "40%"}))), ["rejected"])
	expect("a player can't rule on grammar", types(send(s, 2, {"type": "rule_grammar", "ok": true})), ["rejected"])
	expect("a grammar ruling must be a bool", types(send(s, SERVER, {"type": "rule_grammar", "ok": "yes"})), ["rejected"])
	expect("an unknown command is refused", types(send(s, 1, {"type": "bribe"})), ["rejected"])
	expect("refusals were not logged", s.event_log.size(), logged)
	expect("phase is unchanged", s.amend["phase"], PROPOSED)


func agbero_confront() -> void:
	var s := make_state()
	s.unions[10] = union(AGBERO, 2, [2, 3])
	send(s, 1, propose(s, INAUG, {1: "30%"}))
	var ev := send(s, 2, {"type": "confront", "union_id": 10})
	expect("Agbero confront blocks, and the mob disperses the instant it acts", types(ev), ["union_confronted", "amendment_blocked", "union_dispersed"])
	expect("Leader pays 50 to each member", [s.psd[1], s.psd[2], s.psd[3]], [900, 1050, 1050])
	expect("the window stays used", s.windows_used[INAUG], true)
	expect("flow is back to NONE", s.amend.is_empty(), true)
	expect("wording unchanged", tax_text(s), TAX_20)
	expect("popularity unchanged", s.popularity[1], 0)
	expect("the mob is gone, so it can't confront again", s.unions.has(10), false)
	expect("record says blocked", s.amendment_record[0]["outcome"], "blocked")

	s = make_state()
	s.psd[1] = 60
	s.unions[10] = union(AGBERO, 2, [2, 3])
	send(s, 1, propose(s, INAUG, {1: "30%"}))
	send(s, SERVER, {"type": "rule_grammar", "ok": true})
	ev = send(s, 2, {"type": "confront", "union_id": 10})
	expect("Agbero can also confront during the vote", types(ev), ["union_confronted", "amendment_blocked", "union_dispersed"])
	expect("first member is paid in full, the second gets the rest", [s.psd[2], s.psd[3]], [1050, 1010])
	expect("Leader is in debt for what they couldn't pay", DebtScript.total_debt(s, 1), 40)
	expect("the debt is owed to the second member", s.debts[1][0]["creditor"], 3)


func activist_confront() -> void:
	# Four players have not voted yet when the union confronts; one early vote is ignored.
	var s := open_vote(make_state())
	s.unions[11] = union(ACTIVIST, 2, [2, 3])
	send(s, 2, {"type": "vote", "keep": true})
	send(s, 4, {"type": "vote", "keep": true})
	send(s, 5, {"type": "vote", "keep": true})
	expect("still waiting for player 3", s.amend["phase"], VOTING)
	var ev := send(s, 2, {"type": "confront", "union_id": 11})
	expect("confront resolves at once: nobody else is awaited", types(ev), ["union_confronted", "amendment_resolved"])
	expect("2 for, and the union's 2 members count double against", [ev[1]["for"], ev[1]["against"]], [2, 4])
	expect("popularity (2 - 4) x 6", s.popularity[1], -12)
	expect("the amendment does not stand", tax_text(s), TAX_20)
	expect("an Activist union lingers after acting (Article 12), but has used its one confront", [s.unions.has(11), s.unions[11]["confront_used"]], [true, true])

	# Confronting before the vote: members can't vote any more, their votes are automatic.
	s = make_state()
	s.unions[11] = union(ACTIVIST, 2, [2, 3])
	send(s, 1, propose(s, INAUG, {1: "30%"}))
	ev = send(s, 2, {"type": "confront", "union_id": 11})
	expect("Activist confront during PROPOSED is allowed", types(ev), ["union_confronted"])
	send(s, SERVER, {"type": "rule_grammar", "ok": true})
	expect("a member can't vote by hand", types(send(s, 3, {"type": "vote", "keep": true})), ["rejected"])
	send(s, 4, {"type": "vote", "keep": true})
	ev = send(s, 5, {"type": "vote", "keep": true})
	expect("result uses the automatic votes", [ev[1]["for"], ev[1]["against"], ev[1]["auto_against"]], [2, 4, 4])
	expect("an amendment the union opposed fails", tax_text(s), TAX_20)

	# An Activist union with only one voter left (the rest are sick) is still doubled.
	s = make_state()
	s.unions[11] = union(ACTIVIST, 2, [2, 3])
	s.sick[3] = true
	open_vote(s)
	send(s, 2, {"type": "confront", "union_id": 11})
	send(s, 4, {"type": "vote", "keep": true})
	ev = send(s, 5, {"type": "vote", "keep": true})
	expect("a sick member's vote doesn't count, even doubled", [ev[1]["for"], ev[1]["against"]], [2, 2])


func confront_rules() -> void:
	var s := open_vote(make_state())
	s.unions[12] = union(ACTIVIST, 2, [2])
	expect("a one-member union can't act", types(send(s, 2, {"type": "confront", "union_id": 12})), ["rejected"])
	s.unions[13] = union(ACTIVIST, 2, [2, 3])
	expect("only the unionizer decides", types(send(s, 3, {"type": "confront", "union_id": 13})), ["rejected"])
	s.unions[14] = union(ACTIVIST, 2, [1, 2])
	expect("a union with the Leader in it must name a rival", types(send(s, 2, {"type": "confront", "union_id": 14})), ["rejected"])
	expect("... who can't be one of its own members", types(send(s, 2, {"type": "confront", "union_id": 14, "rival": 2})), ["rejected"])
	var shamed := send(s, 2, {"type": "confront", "union_id": 14, "rival": 4})
	expect("an Activist union with the Leader shames the rival, and the amendment is untouched", [types(shamed), s.amend.get("phase", 0) != 0], [["union_confronted", "rival_shamed"], true])
	s.unions[16] = union(AGBERO, 3, [1, 3])
	var cash: int = s.psd[5]
	var robbed := send(s, 3, {"type": "confront", "union_id": 16, "rival": 5})
	expect("a mob with the Leader robs the rival, not the Leader, and disperses", [types(robbed), cash - s.psd[5], s.unions.has(16)], [["union_confronted", "rival_robbed", "union_dispersed"], 100, false])
	s.unions[15] = union(ACTIVIST, 4, [4, 5])
	s.sick[4] = true
	expect("a sick unionizer can't act", types(send(s, 4, {"type": "confront", "union_id": 15})), ["rejected"])
	expect("no such union", types(send(s, 2, {"type": "confront", "union_id": 99})), ["rejected"])
	expect("no confront was recorded", s.unions[13]["confront_used"], false)
	s.sick[4] = false
	send(s, 4, {"type": "confront", "union_id": 15})
	expect("once only", types(send(s, 4, {"type": "confront", "union_id": 15})), ["rejected"])


func voter_rules() -> void:
	var s := open_vote(make_state())
	expect("the Leader can't vote", types(send(s, 1, {"type": "vote", "keep": true})), ["rejected"])
	expect("a vote must be a bool", types(send(s, 2, {"type": "vote", "keep": "yes"})), ["rejected"])
	send(s, 2, {"type": "vote", "keep": true})
	expect("no voting twice", types(send(s, 2, {"type": "vote", "keep": false})), ["rejected"])

	s = make_state()
	s.sick[3] = true
	open_vote(s)
	expect("a sick player can't vote", types(send(s, 3, {"type": "vote", "keep": true})), ["rejected"])
	send(s, 2, {"type": "vote", "keep": true})
	send(s, 4, {"type": "vote", "keep": true})
	var ev := send(s, 5, {"type": "vote", "keep": true})
	expect("the sick player is not waited for", types(ev), ["vote_cast", "amendment_resolved", "article_changed"])

	s = make_state()
	s.eliminated[4] = true
	open_vote(s)
	expect("an eliminated player can't vote", types(send(s, 4, {"type": "vote", "keep": true})), ["rejected"])
	vote_all(s, {2: true, 3: true, 5: true})
	expect("4 active players: swing 7 x 3 for", s.popularity[1], 21)


func edge_cases() -> void:
	var s := make_state()
	for id in [2, 3, 4, 5]:
		s.sick[id] = true
	send(s, 1, propose(s, INAUG, {1: "30%"}))
	var ev := send(s, SERVER, {"type": "rule_grammar", "ok": true})
	expect("nobody can vote: resolves at once", types(ev), ["grammar_ruled", "amendment_resolved"])
	expect("a President needs more for than against", tax_text(s), TAX_20)

	s = make_state()
	s.leader_type = GameStateScript.LeaderType.DICTATOR
	for id in [2, 3, 4, 5]:
		s.sick[id] = true
	send(s, 1, propose(s, INAUG, {1: "30%"}))
	send(s, SERVER, {"type": "rule_grammar", "ok": true})
	expect("a Dictator's amendment stands with no voters", tax_text(s), TAX_30)

	s = make_state()
	s.leader_type = GameStateScript.LeaderType.COMMANDER
	expect("a Commander can't propose", types(send(s, 1, propose(s, INAUG, {1: "30%"}))), ["rejected"])

	s = make_state()
	s.turns_played = 3
	expect("Mid-term opens after 3 of 5 turns", types(send(s, 1, propose(s, MID, {1: "30%"}))), ["amendment_proposed"])


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


func union(type: int, owner: int, members: Array) -> Dictionary:
	return {"type": type, "owner": owner, "members": members, "confront_used": false}


# The Tax article's words with some positions replaced: { index: new text }.
func propose(s: GameStateScript, window: int, changes: Dictionary) -> Dictionary:
	var words: Array = s.articles[TAX]
	var texts: Array = []
	for i in words.size():
		texts.append(changes.get(i, words[i]["text"]))
	return {"type": "propose", "window": window, "article_id": TAX, "new_texts": texts}


# Propose and pass the grammar check, leaving the amendment ready for votes.
func open_vote(s: GameStateScript, changes: Dictionary = {1: "30%"}) -> GameStateScript:
	send(s, 1, propose(s, INAUG, changes))
	send(s, SERVER, {"type": "rule_grammar", "ok": true})
	return s


func vote_all(s: GameStateScript, keeps: Dictionary) -> void:
	for id in keeps:
		send(s, id, {"type": "vote", "keep": keeps[id]})


func send(s: GameStateScript, player_id: int, command: Dictionary) -> Array:
	return FlowScript.handle(s, player_id, command)


func types(events: Array) -> Array:
	var result: Array = []
	for event in events:
		result.append(event["type"])
	return result


func tax_text(s: GameStateScript) -> String:
	return ConstitutionScript.to_text(s.articles[TAX])


func expect(label: String, actual: Variant, wanted: Variant) -> void:
	var ok: bool = actual == wanted
	if not ok:
		failures += 1
	print(("PASS " if ok else "FAIL ") + label + " -> " + str(actual))
