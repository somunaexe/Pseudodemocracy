extends SceneTree

# The point of the Law module: an amendment that STANDS changes how the game behaves.

const FlowScript = preload("res://scripts/amendment_flow.gd")
const ElimScript = preload("res://scripts/elimination.gd")
const LawScript = preload("res://scripts/law.gd")
const SerializerScript = preload("res://scripts/serializer.gd")
const GameStateScript = preload("res://scripts/game_state.gd")
const ConstitutionScript = preload("res://scripts/constitution.gd")

const INAUG = GameStateScript.AmendWindow.INAUGURATION
const MID = GameStateScript.AmendWindow.MID_TERM
const ACTIVIST = GameStateScript.UnionType.ACTIVIST
const AGBERO = GameStateScript.UnionType.AGBERO
const TAX := 2
const UNION_SIZE := 7
const DISSOLVING := 11
const ACTIVIST_CONFRONT := 14
const AGBERO_CONFRONT := 15
const SERVER := 0
const TAX_20 := "Tax: 20% of income goes to the treasury every round."

var failures: int = 0


func _init() -> void:
	words_the_game_cannot_apply()
	amendments_change_the_game()
	a_rejected_amendment_changes_nothing()
	the_amended_law_survives_a_save()
	an_eliminated_leader()
	print("%d failure(s)" % failures)
	quit(1 if failures > 0 else 0)


func words_the_game_cannot_apply() -> void:
	# The Leader chose to write a word the game can't apply, so it is a failed check.
	for bad in ["banana", "150%", "30", "-5%", "thirty%", "٣٠%"]:
		var s := make_state()
		var ev := send(s, 1, amend(s, TAX, {0: bad}, INAUG))
		expect("'%s' as a tax rate fails the check" % bad, types(ev), ["amendment_proposed", "amendment_failed"])
		expect("... 100 PSD fine", s.psd[1], 900)
		expect("... popularity -6 x 4", s.popularity[1], -24)
		expect("... the window is used up", s.windows_used[INAUG], true)
		expect("... the old wording stays, nothing in progress", [tax_text(s), s.amend.size()], [TAX_20, 0])

	var s := make_state()
	var ev := send(s, 1, amend(s, TAX, {0: "banana"}, INAUG))
	expect("the Leader is told what the game could have read", ev[1]["reason"].contains("whole percentage"), true)
	expect("... and the word they wrote", ev[1]["reason"].contains("'banana'"), true)
	expect("the window is gone: no second try", types(send(s, 1, amend(s, TAX, {0: "30%"}, INAUG))), ["rejected"])

	s = make_state()
	expect("a word the game doesn't enforce can be anything, with no fine", types(send(s, 1, amend(s, TAX, {3: "banana"}, INAUG))), ["amendment_proposed"])
	expect("... nothing was charged", s.psd[1], 1000)

	s = make_state()
	expect("a fixed word still costs the fine", types(send(s, 1, {"type": "propose", "window": INAUG, "article_id": TAX, "new_texts": changed_texts(s, TAX, 0, "Duty:")})), ["amendment_proposed", "amendment_failed"])
	s = make_state()
	expect("two words in one place still cost the fine", types(send(s, 1, amend(s, TAX, {0: "30 %"}, INAUG))), ["amendment_proposed", "amendment_failed"])
	s = make_state()
	expect("a blank word costs the fine", types(send(s, 1, amend(s, TAX, {0: ""}, INAUG))), ["amendment_proposed", "amendment_failed"])

	s = make_state()
	expect("a union that needs 0 members fails the check", types(send(s, 1, amend(s, UNION_SIZE, {1: "0"}, INAUG))), ["amendment_proposed", "amendment_failed"])
	s = make_state()
	expect("... but 1 is fine", types(send(s, 1, amend(s, UNION_SIZE, {1: "1"}, INAUG))), ["amendment_proposed"])
	s = make_state()
	expect("'quintuple' is not a multiplier", types(send(s, 1, amend(s, ACTIVIST_CONFRONT, {0: "quintuple"}, INAUG))), ["amendment_proposed", "amendment_failed"])
	s = make_state()
	expect("a sign must be a sign", types(send(s, 1, amend(s, 31, {0: "x"}, INAUG))), ["amendment_proposed", "amendment_failed"])

	# A bad word never reaches the vote or the Constitution.
	s = make_state()
	send(s, 1, amend(s, TAX, {0: "banana"}, INAUG))
	expect("the phase is back to NONE and the law is unchanged", [s.amend.is_empty(), LawScript.get_int(s, "taxRate")], [true, 20])


func amendments_change_the_game() -> void:
	# 1. The Agbero steal goes from 50 to 80, and the next confront takes 80 from the Leader.
	var s := make_state()
	s.unions[10] = union(AGBERO, 2, [2, 3])
	pass_amendment(s, AGBERO_CONFRONT, {0: "80"}, INAUG)
	expect("the steal is now 80", LawScript.get_int(s, "agberoSteal"), 80)
	s.turns_played = 3
	send(s, 1, amend(s, TAX, {3: "banana"}, MID))
	send(s, 2, {"type": "confront", "union_id": 10})
	expect("the Leader loses 80 to each of 2 members", [s.psd[1], s.psd[2], s.psd[3]], [840, 1080, 1080])

	# 2. Activist votes triple, not double.
	s = make_state()
	s.unions[11] = union(ACTIVIST, 2, [2, 3])
	pass_amendment(s, ACTIVIST_CONFRONT, {0: "triple"}, INAUG)
	s.turns_played = 3
	open_vote(s, TAX, {0: "30%"}, MID)
	send(s, 4, {"type": "vote", "keep": true})
	send(s, 5, {"type": "vote", "keep": true})
	var ev := send(s, 2, {"type": "confront", "union_id": 11})
	expect("the union's 2 members now count 3 each against", [ev[1]["for"], ev[1]["against"]], [2, 6])

	# 3. A union must now have 3 members to act.
	s = make_state()
	s.unions[12] = union(ACTIVIST, 2, [2, 3])
	pass_amendment(s, UNION_SIZE, {1: "3"}, INAUG)
	s.turns_played = 3
	send(s, 1, amend(s, TAX, {3: "banana"}, MID))
	var refused := send(s, 2, {"type": "confront", "union_id": 12})
	expect("2 members are no longer enough", refused[0]["reason"], "The union is too small to act.")
	s.unions[12]["members"].append(4)
	expect("3 members are", types(send(s, 2, {"type": "confront", "union_id": 12})).has("union_confronted"), true)

	# 4. Unions dissolve at a different size.
	s = make_state()
	s.unions[13] = union(ACTIVIST, 2, [2, 3])
	expect("by default a union left with 1 member dissolves", types(ElimScript.eliminate(s, 3, "test")).has("union_dissolved"), true)
	s = make_state()
	s.unions[13] = union(ACTIVIST, 2, [2, 3])
	pass_amendment(s, DISSOLVING, {0: "0"}, INAUG)
	var ev2 := ElimScript.eliminate(s, 3, "test")
	expect("after the amendment, 1 member is enough to survive", [types(ev2).has("union_dissolved"), s.unions.has(13)], [false, true])


func a_rejected_amendment_changes_nothing() -> void:
	var s := make_state()
	s.unions[10] = union(AGBERO, 2, [2, 3])
	open_vote(s, AGBERO_CONFRONT, {0: "80"}, INAUG)
	for id in [2, 3, 4, 5]:
		send(s, id, {"type": "vote", "keep": false})
	expect("the vote failed, so the steal is still 50", LawScript.get_int(s, "agberoSteal"), 50)
	expect("... and the text is unchanged", ConstitutionScript.to_text(s.articles[AGBERO_CONFRONT]).contains("steal 50"), true)

	# While an amendment is being voted on, the old law still applies.
	s = make_state()
	open_vote(s, AGBERO_CONFRONT, {0: "80"}, INAUG)
	expect("the old law applies until the amendment stands", LawScript.get_int(s, "agberoSteal"), 50)


func the_amended_law_survives_a_save() -> void:
	var s := make_state()
	pass_amendment(s, TAX, {0: "35%"}, INAUG)
	var errors: Array = []
	var back: GameStateScript = SerializerScript.state_from_json(SerializerScript.state_to_json(s), errors)
	expect("a saved game restores", errors, [])
	expect("the amended tax rate survives", LawScript.get_int(back, "taxRate"), 35)


func an_eliminated_leader() -> void:
	var s := open_vote(make_state(), TAX, {0: "30%"}, INAUG)
	send(s, 2, {"type": "vote", "keep": true})
	var ev := ElimScript.eliminate(s, 1, "test")
	expect("the amendment is abandoned, the seat is vacant, and a new Leader is voted for", types(ev), ["player_eliminated", "estate_settled", "amendment_abandoned", "leader_vacant", "election_started", "vote_started"])
	expect("no Leader", s.leader_id, -1)
	expect("nothing in progress", s.amend.is_empty(), true)
	expect("the wording is unchanged", ConstitutionScript.to_text(s.articles[TAX]), "Tax: 20% of income goes to the treasury every round.")
	expect("no fine for the abandoned amendment", s.popularity[1], 0)
	expect("it is in the record", s.amendment_record[0]["outcome"], "abandoned")
	expect("the window stays used", s.windows_used[INAUG], true)
	var ev2 := send(s, 2, amend(s, TAX, {0: "30%"}, MID))
	expect("nobody can amend until a Leader is chosen", ev2[0]["reason"], "Only the Leader can amend the Constitution.")

	s = make_state()
	ev = ElimScript.eliminate(s, 1, "test")
	expect("a Leader with no amendment under way: the vacancy and the election", types(ev), ["player_eliminated", "estate_settled", "leader_vacant", "election_started", "vote_started"])
	ev = ElimScript.eliminate(s, 2, "test")
	expect("an ordinary player leaves the seat alone", [types(ev).has("leader_vacant"), s.leader_id], [false, -1])


# --- helpers ---------------------------------------------------------------------------

func tax_text(s: GameStateScript) -> String:
	return ConstitutionScript.to_text(s.articles[TAX])


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


# Texts of an article with some highlighted words replaced: { slot number: new text }.
func changed_texts_by_slot(s: GameStateScript, article_id: int, changes: Dictionary) -> Array:
	var texts: Array = []
	var slot: int = 0
	for word in s.articles[article_id]:
		if word["amendable"]:
			texts.append(changes.get(slot, word["text"]))
			slot += 1
		else:
			texts.append(word["text"])
	return texts


# Texts with the word at plain position `index` replaced (to touch a fixed word).
func changed_texts(s: GameStateScript, article_id: int, index: int, text: String) -> Array:
	var texts: Array = []
	for word in s.articles[article_id]:
		texts.append(word["text"])
	texts[index] = text
	return texts


func amend(s: GameStateScript, article_id: int, changes: Dictionary, window: int) -> Dictionary:
	return {"type": "propose", "window": window, "article_id": article_id, "new_texts": changed_texts_by_slot(s, article_id, changes)}


func open_vote(s: GameStateScript, article_id: int, changes: Dictionary, window: int) -> GameStateScript:
	send(s, 1, amend(s, article_id, changes, window))
	send(s, SERVER, {"type": "rule_grammar", "ok": true})
	return s


# Propose, pass the grammar check and win the vote with every other player voting keep.
func pass_amendment(s: GameStateScript, article_id: int, changes: Dictionary, window: int) -> void:
	open_vote(s, article_id, changes, window)
	for id in s.player_ids:
		if id != s.leader_id:
			send(s, id, {"type": "vote", "keep": true})


func send(s: GameStateScript, player_id: int, command: Dictionary) -> Array:
	return FlowScript.handle(s, player_id, command)


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
