extends SceneTree

const GameScript = preload("res://scripts/game.gd")
const GameStateScript = preload("res://scripts/game_state.gd")
const CardsScript = preload("res://scripts/cards.gd")
const CardEffectsScript = preload("res://scripts/card_effects.gd")
const ViceScript = preload("res://scripts/vice.gd")
const IncomeScript = preload("res://scripts/income.gd")
const ElectionScript = preload("res://scripts/election.gd")
const PermissionsScript = preload("res://scripts/permissions.gd")
const PopularityScript = preload("res://scripts/popularity.gd")
const EliminationScript = preload("res://scripts/elimination.gd")
const UnionsScript = preload("res://scripts/unions.gd")
const RolesScript = preload("res://scripts/roles.gd")
const SerializerScript = preload("res://scripts/serializer.gd")
const ViewsScript = preload("res://scripts/views.gd")
const ScoringScript = preload("res://scripts/scoring.gd")
const PlayScript = preload("res://tests/play.gd")

const PRESIDENT = GameStateScript.LeaderType.PRESIDENT
const DICTATOR = GameStateScript.LeaderType.DICTATOR
const COMMANDER = GameStateScript.LeaderType.COMMANDER
const INAUG = GameStateScript.AmendWindow.INAUGURATION
const MID = GameStateScript.AmendWindow.MID_TERM
const FAREWELL = GameStateScript.AmendWindow.FAREWELL
const TAX := 2
const LEADER := 2

var failures: int = 0


func _init() -> void:
	appointing()
	the_keys_to_the_city()
	income()
	scoring_and_the_end_of_the_term()
	amending_permissions()
	the_windows()
	an_amendment_by_the_vice()
	confronting()
	recruiting()
	leaving_the_game()
	views_and_saves()
	print("%d failure(s)" % failures)
	quit(1 if failures > 0 else 0)


func appointing() -> void:
	var s := new_turn()
	expect("there is no Vice to start with", [s.vice_id, ViceScript.is_vice(s, 3), ViceScript.is_leader_or_vice(s, LEADER), ViceScript.is_leader_or_vice(s, 3)], [-1, false, true, false])
	var ev := ViceScript.appoint(s, 3)
	expect("a Vice is appointed with a Leader card of their own", [ev[0]["type"], s.vice_id, ev[0]["vice"], ev[0]["vice_type"] == s.vice_type, ev[0]["replaced"]], ["vice_appointed", 3, 3, true, -1])
	expect("... and is a Leader in the usual sense", [ViceScript.is_vice(s, 3), ViceScript.is_leader_or_vice(s, 3)], [true, true])
	expect("... their windows start fresh, the Inauguration already over (the term is under way)", s.vice_windows_used, {INAUG: true, MID: false, FAREWELL: false})
	s.vice_windows_used[MID] = true
	ev = ViceScript.appoint(s, 4)
	expect("a new Vice replaces the old one, with fresh windows", [s.vice_id, ev[0]["replaced"], s.vice_windows_used[MID]], [4, 3, false])
	ev = ViceScript.appoint(s, 4)
	expect("appointing the same Vice again replaces nobody", ev[0]["replaced"], -1)
	expect("the type of the Vice, not the Leader, is the Vice's", [ViceScript.type_of(s, 4) == s.vice_type, ViceScript.type_of(s, LEADER) == s.leader_type], [true, true])

	# Types: the draw uses the Leader cards, so over many draws every kind appears.
	var kinds := {}
	for seed_value in 60:
		var g := new_turn()
		g.rng_state = seed_value * 7919 + 12345
		ViceScript.appoint(g, 3)
		kinds[g.vice_type] = true
	expect("Vice cards are drawn like Leader cards: all three kinds turn up", kinds.keys().size(), 3)

	# A new Leader ends the Vice.
	s = new_turn()
	ViceScript.appoint(s, 3)
	s.term = {}
	ElectionScript.install_leader(s, 5, "coup")
	expect("installing a Leader clears the Vice and their windows", [s.vice_id, s.vice_windows_used], [-1, {INAUG: false, MID: false, FAREWELL: false}])


func the_keys_to_the_city() -> void:
	var card: int = card_number("settlement", "You've obtained the keys to the city")
	var s := new_turn()
	s.popularity[3] = 0
	s.popularity[LEADER] = 10
	var type_before: int = s.leader_type
	var ev := CardEffectsScript.apply(s, 3, "settlement", card)
	expect("a drawer less popular than the Leader becomes Vice", [types(ev), s.vice_id, s.leader_id], [["card_applied", "vice_appointed"], 3, LEADER])

	s = new_turn()
	s.popularity[3] = 10
	s.popularity[LEADER] = 10
	CardEffectsScript.apply(s, 3, "settlement", card)
	expect("equally popular is not more popular: Vice", [s.vice_id, s.leader_id], [3, LEADER])

	s = new_turn()
	s.popularity[3] = 20
	s.popularity[LEADER] = 10
	type_before = s.leader_type
	ev = CardEffectsScript.apply(s, 3, "settlement", card)
	expect("a more popular drawer takes the Leader's role and the Leader is demoted to Vice", [types(ev), s.leader_id, s.vice_id], [["card_applied", "leader_swapped", "vice_appointed"], 3, LEADER])
	expect("... the new Leader keeps the Leader card of the role they took", [s.leader_type, ev[1]["leader_type"]], [type_before, type_before])
	expect("... the swap event names both", [ev[1]["new_leader"], ev[1]["old_leader"]], [3, LEADER])

	# The Leader draws it: nothing.
	s = new_turn()
	ev = CardEffectsScript.apply(s, LEADER, "settlement", card)
	expect("the Leader drawing the keys gets nothing", [types(ev), s.vice_id, s.leader_id], [["card_applied", "keys_no_effect"], -1, LEADER])

	# The Vice draws it and is not more popular: nothing. If more popular, they swap with the Leader.
	s = new_turn()
	ViceScript.appoint(s, 3)
	s.popularity[3] = 0
	s.popularity[LEADER] = 10
	ev = CardEffectsScript.apply(s, 3, "settlement", card)
	expect("a Vice who draws it, not more popular, stays Vice", [types(ev), s.vice_id], [["card_applied", "keys_no_effect"], 3])
	s.popularity[3] = 30
	ev = CardEffectsScript.apply(s, 3, "settlement", card)
	expect("... more popular, the Vice and the Leader swap", [s.leader_id, s.vice_id], [3, LEADER])

	# Someone else takes over as Vice or Leader.
	s = new_turn()
	ViceScript.appoint(s, 4)
	s.popularity[3] = 0
	s.popularity[LEADER] = 10
	CardEffectsScript.apply(s, 3, "settlement", card)
	expect("a new Vice displaces the old", [s.vice_id], [3])
	s = new_turn()
	ViceScript.appoint(s, 4)
	s.popularity[3] = 40
	s.popularity[LEADER] = 10
	CardEffectsScript.apply(s, 3, "settlement", card)
	expect("when the Leader is ousted, they become the Vice and the old Vice is displaced", [s.leader_id, s.vice_id], [3, LEADER])


func income() -> void:
	var s := new_turn()
	ViceScript.appoint(s, 3)
	expect("the Vice earns 90 and the Leader 100", [IncomeScript.gross(s, 3), IncomeScript.gross(s, LEADER)], [90, 100])
	RolesScript.grant(s, 3, "Doctor")
	expect("role income stacks on top", IncomeScript.gross(s, 3), 160)
	var cash: int = s.psd[3]
	var treasury: int = s.treasury
	var ev := IncomeScript.pay(s, 3)
	expect("they are paid from the treasury less the 20% tax", [ev[0]["gross"], ev[0]["tax"], ev[0]["net"], s.psd[3] - cash, treasury - s.treasury], [160, 32, 128, 128, 128])
	expect("nobody else earns the Vice's pay", IncomeScript.gross(s, 4), 0)


func scoring_and_the_end_of_the_term() -> void:
	var s := new_turn()
	ViceScript.appoint(s, 3)
	s.term = {}
	ElectionScript.begin(s, "term_ended")
	expect("a term served as Vice scores half a round, the Leader's scores a full one", [s.half_rounds.get(3, 0), s.half_rounds.get(LEADER, 0)], [1, 2])
	expect("... and the Vice ends with the term", [s.vice_id, s.vice_windows_used[MID]], [-1, false])

	# After the keys swap, the ousted Leader scores a half, the new one a full term.
	s = new_turn()
	var card: int = card_number("settlement", "You've obtained the keys to the city")
	s.popularity[3] = 30
	CardEffectsScript.apply(s, 3, "settlement", card)
	s.term = {}
	ElectionScript.begin(s, "term_ended")
	expect("the ousted Leader scores 1/2 for the term, the new Leader a full round", [s.half_rounds.get(LEADER, 0), s.half_rounds.get(3, 0)], [1, 2])

	# The game stopped mid-term.
	s = new_turn()
	ViceScript.appoint(s, 3)
	GameScript.handle(s, 0, {"type": "finish_game"})
	expect("a game stopped mid-term credits the Vice half a round as well", [s.half_rounds.get(3, 0), s.half_rounds.get(LEADER, 0)], [1, 2])

	# A coup ends the term: the Vice scores nothing.
	s = new_turn()
	ViceScript.appoint(s, 3)
	for role in RolesScript.names():
		RolesScript.grant(s, 4, role)
		if RolesScript.has_sticker(s, 4, role):
			break
		RolesScript.remove(s, 4, role)
	s.popularity[4] = 30
	var ev := GameScript.handle(s, 4, {"type": "coup"})
	expect("a successful coup ends the Vice's term with nothing", [types(ev).has("coup_succeeded"), s.vice_id, s.half_rounds.get(3, 0)], [true, -1, 0])

	# The Leader is eliminated: no Vice either.
	s = new_turn()
	ViceScript.appoint(s, 3)
	EliminationScript.eliminate(s, LEADER, "debt")
	expect("when the Leader is eliminated the Vice ends too", [s.vice_id, s.half_rounds.get(3, 0)], [-1, 0])


func amending_permissions() -> void:
	var s := new_turn()
	s.leader_type = PRESIDENT
	expect("a stranger still can't amend", PermissionsScript.leader_powers_problem(s, 3), "Only the Leader can amend the Constitution.")
	ViceScript.appoint(s, 3)
	s.vice_type = PRESIDENT
	expect("the Vice can", PermissionsScript.leader_powers_problem(s, 3), "")
	s.vice_type = COMMANDER
	expect("a Vice with a Commander card can't, as for a Leader", PermissionsScript.leader_powers_problem(s, 3), "A Commander can't amend.")
	s.vice_type = PRESIDENT
	s.leader_type = COMMANDER
	expect("a Commander Leader doesn't stop a President Vice", [PermissionsScript.leader_powers_problem(s, LEADER), PermissionsScript.leader_powers_problem(s, 3)], ["A Commander can't amend.", ""])
	s.sick[3] = true
	expect("a sick Vice can't", PermissionsScript.leader_powers_problem(s, 3), "A sick Leader can't amend.")
	s.sick[3] = false
	s.popularity[3] = -50
	expect("a CANCELLED Vice can't", PermissionsScript.leader_powers_problem(s, 3), "A CANCELLED Leader can't amend.")


func the_windows() -> void:
	var s := new_turn()
	s.leader_type = PRESIDENT
	ViceScript.appoint(s, 3)
	s.vice_type = PRESIDENT
	s.turns_played = 5
	expect("the Vice's windows are their own: the Leader's used window doesn't block them", [PermissionsScript.can_amend(s, 3, MID)], [""])
	s.windows_used[MID] = true
	expect("... the Leader's used mid-term window leaves the Vice's open", [PermissionsScript.can_amend(s, LEADER, MID), PermissionsScript.can_amend(s, 3, MID)], ["This amendment window has already been used.", ""])
	s.vice_windows_used[MID] = true
	expect("... and the Vice's used window is theirs alone", PermissionsScript.can_amend(s, 3, MID), "This amendment window has already been used.")

	# The Inauguration and Farewell wait for both.
	s = inaugurated()
	ViceScript.appoint(s, 3)
	s.vice_type = PRESIDENT
	s.vice_windows_used[INAUG] = false   # a Vice present from the start of the term
	GameScript.handle(s, LEADER, {"type": "pass_window"})
	expect("when the Leader passes the Inauguration the term waits for the Vice", s.term["phase"], GameStateScript.TermPhase.INAUGURATION)
	expect("only the Leader and the Vice decide", GameScript.handle(s, 5, {"type": "pass_window"})[0]["reason"], "Only the Leader decides whether to amend.")
	var ev := GameScript.handle(s, 3, {"type": "pass_window"})
	expect("... then the Vice passes theirs and the turns begin", [types(ev).has("window_passed"), s.term["phase"], s.vice_windows_used[INAUG]], [true, GameStateScript.TermPhase.TURNS, true])

	# A Vice who can't amend is not waited for.
	s = inaugurated()
	ViceScript.appoint(s, 3)
	s.vice_windows_used[INAUG] = false
	s.vice_type = COMMANDER
	GameScript.handle(s, LEADER, {"type": "pass_window"})
	expect("a Commander Vice is not waited for", s.term["phase"], GameStateScript.TermPhase.TURNS)

	# The Farewell too.
	s = new_turn()
	ViceScript.appoint(s, 3)
	s.vice_type = PRESIDENT
	for id in [2, 3, 4, 5, 1]:
		PlayScript.take_turn(s, id)
	expect("the Farewell opens", s.term["phase"], GameStateScript.TermPhase.FAREWELL)
	GameScript.handle(s, LEADER, {"type": "pass_window"})
	expect("the Leader passes the Farewell and the term waits for the Vice", s.term["phase"], GameStateScript.TermPhase.FAREWELL)
	GameScript.handle(s, 3, {"type": "pass_window"})
	expect("... then it ends", s.term.is_empty() or s.term.get("phase", 0) == GameStateScript.TermPhase.NONE, true)


func an_amendment_by_the_vice() -> void:
	var s := inaugurated()
	s.leader_type = PRESIDENT
	ViceScript.appoint(s, 4)
	s.vice_type = PRESIDENT
	s.vice_windows_used[INAUG] = false
	var ev := GameScript.handle(s, 4, propose(s, INAUG, {1: "30%"}))
	expect("the Vice proposes in their own Inauguration window", [types(ev), s.vice_windows_used[INAUG], s.windows_used[INAUG], s.amend["by"]], [["amendment_proposed"], true, false, 4])
	GameScript.handle(s, 0, {"type": "rule_grammar", "ok": true})
	expect("neither the Leader nor the Vice votes on it", [GameScript.handle(s, LEADER, {"type": "vote", "keep": true})[0]["reason"], GameScript.handle(s, 4, {"type": "vote", "keep": true})[0]["reason"]], ["You can't vote on this amendment.", "You can't vote on this amendment."])
	var pop: int = PopularityScript.base(s, 4)
	var leader_pop: int = PopularityScript.base(s, LEADER)
	GameScript.handle(s, 1, {"type": "vote", "keep": true})
	GameScript.handle(s, 3, {"type": "vote", "keep": true})
	ev = GameScript.handle(s, 5, {"type": "vote", "keep": false})
	expect("the result moves the VICE's popularity, not the Leader's", [PopularityScript.base(s, 4) > pop, PopularityScript.base(s, LEADER) == leader_pop], [true, true])
	expect("... and is recorded under the Vice", s.amendment_record.back()["leader"], 4)
	expect("a President Vice's amendment stands on a majority (2 to 1)", last_of(s, "amendment_resolved")["stands"], true)

	# The Vice's card decides, not the Leader's: a Dictator Vice's always stands, a President Leader's doesn't.
	s = inaugurated()
	s.leader_type = PRESIDENT
	ViceScript.appoint(s, 4)
	s.vice_type = DICTATOR
	s.vice_windows_used[INAUG] = false
	GameScript.handle(s, 4, propose(s, INAUG, {1: "30%"}))
	GameScript.handle(s, 0, {"type": "rule_grammar", "ok": true})
	for id in [1, 3, 5]:
		GameScript.handle(s, id, {"type": "vote", "keep": false})
	expect("a Dictator Vice's amendment stands whatever the vote", last_of(s, "amendment_resolved")["stands"], true)
	s = inaugurated()
	s.leader_type = DICTATOR
	ViceScript.appoint(s, 4)
	s.vice_type = PRESIDENT
	s.vice_windows_used[INAUG] = false
	GameScript.handle(s, 4, propose(s, INAUG, {1: "30%"}))
	GameScript.handle(s, 0, {"type": "rule_grammar", "ok": true})
	for id in [1, 3, 5]:
		GameScript.handle(s, id, {"type": "vote", "keep": false})
	expect("... and a President Vice's fails when the Leader would have been a Dictator", last_of(s, "amendment_resolved")["stands"], false)

	# A failed check fines and costs the Vice, not the Leader.
	s = inaugurated()
	ViceScript.appoint(s, 4)
	s.vice_type = PRESIDENT
	s.vice_windows_used[INAUG] = false
	var cash: int = s.psd[4]
	var leader_cash: int = s.psd[LEADER]
	var pops: int = PopularityScript.base(s, 4)
	GameScript.handle(s, 4, propose(s, INAUG, {0: "Duty:"}))
	expect("a failed check by the Vice fines the Vice", [s.psd[4] < cash, s.psd[LEADER], PopularityScript.base(s, 4) < pops, last_of(s, "amendment_failed").has("fine")], [true, leader_cash, true, true])
	expect("... and is recorded under the Vice", s.amendment_record.back()["leader"], 4)

	# The Leader and the Vice each get their own amendment in the same window (one after the other).
	s = inaugurated()
	s.leader_type = PRESIDENT
	ViceScript.appoint(s, 4)
	s.vice_type = PRESIDENT
	s.vice_windows_used[INAUG] = false
	GameScript.handle(s, LEADER, propose(s, INAUG, {1: "30%"}))
	expect("while the Leader's amendment is under way the Vice can't start another", GameScript.handle(s, 4, propose(s, INAUG, {1: "35%"}))[0]["type"], "rejected")


func confronting() -> void:
	# An Agbero mob blocks the Vice's amendment and the Vice pays.
	var s := inaugurated()
	s.leader_type = PRESIDENT
	ViceScript.appoint(s, 4)
	s.vice_type = PRESIDENT
	s.vice_windows_used[INAUG] = false
	s.unions[1] = {"type": GameStateScript.UnionType.AGBERO, "owner": 3, "members": [3, 5], "confront_used": false}
	GameScript.handle(s, 4, propose(s, INAUG, {1: "30%"}))
	GameScript.handle(s, 0, {"type": "rule_grammar", "ok": true})
	var vice_cash: int = s.psd[4]
	var leader_cash: int = s.psd[LEADER]
	var ev := GameScript.handle(s, 3, {"type": "confront", "union_id": 1})
	expect("the mob blocks the Vice's amendment and the Vice, not the Leader, pays", [types(ev).has("amendment_blocked"), s.psd[4] < vice_cash, s.psd[LEADER]], [true, true, leader_cash])
	expect("... recorded under the Vice", s.amendment_record.back()["leader"], 4)

	# A union that includes the Vice can't confront the Vice's amendment.
	s = inaugurated()
	ViceScript.appoint(s, 4)
	s.vice_type = PRESIDENT
	s.vice_windows_used[INAUG] = false
	s.unions[1] = {"type": GameStateScript.UnionType.ACTIVIST, "owner": 3, "members": [3, 4], "confront_used": false}
	GameScript.handle(s, 4, propose(s, INAUG, {1: "30%"}))
	GameScript.handle(s, 0, {"type": "rule_grammar", "ok": true})
	expect("a union with the proposer in it can't confront", GameScript.handle(s, 3, {"type": "confront", "union_id": 1})[0]["type"], "rejected")


func recruiting() -> void:
	var s := new_turn()
	ViceScript.appoint(s, 3)
	s.unions[1] = {"type": GameStateScript.UnionType.ACTIVIST, "owner": 4, "members": [4], "confront_used": false}
	PlayScript.take_turn(s, 2)
	PlayScript.take_turn(s, 3)
	expect("a union can't recruit the Vice", GameScript.handle(s, 4, {"type": "union_recruit", "union_id": 1, "target": 3})[0]["reason"], "A union can't recruit the Vice.")
	expect("... nor the Leader", GameScript.handle(s, 4, {"type": "union_recruit", "union_id": 1, "target": LEADER})[0]["reason"], "A union can't recruit the Leader.")
	# An invitation sent before the player became Vice is void.
	s = new_turn()
	s.unions[1] = {"type": GameStateScript.UnionType.ACTIVIST, "owner": 4, "members": [4], "confront_used": false}
	s.union_invites[3] = {"union_id": 1, "deadline": 999999999}
	ViceScript.appoint(s, 3)
	var ev := GameScript.handle(s, 3, {"type": "union_respond", "accept": true})
	expect("an invitation answered after becoming Vice is void", [types(ev), s.unions[1]["members"]], [["union_invitation_void"], [4]])


func leaving_the_game() -> void:
	var s := new_turn()
	ViceScript.appoint(s, 3)
	var ev := EliminationScript.eliminate(s, 3, "debt")
	expect("an eliminated Vice is gone", [s.vice_id, types(ev).has("vice_vacant"), s.leader_id], [-1, true, LEADER])

	# Their amendment under way is abandoned.
	s = inaugurated()
	ViceScript.appoint(s, 3)
	s.vice_type = PRESIDENT
	s.vice_windows_used[INAUG] = false
	GameScript.handle(s, 3, propose(s, INAUG, {1: "30%"}))
	GameScript.handle(s, 0, {"type": "rule_grammar", "ok": true})
	ev = EliminationScript.eliminate(s, 3, "debt")
	expect("the Vice's amendment is abandoned when they leave", [s.amend.is_empty(), types(ev).has("amendment_abandoned"), s.amendment_record.back()["outcome"], s.amendment_record.back()["leader"]], [true, true, "abandoned", 3])
	expect("... the Leader carries on", [s.leader_id, s.term["phase"]], [LEADER, GameStateScript.TermPhase.INAUGURATION])

	# The Leader leaves while the Vice's amendment is under way.
	s = inaugurated()
	ViceScript.appoint(s, 3)
	s.vice_type = PRESIDENT
	s.vice_windows_used[INAUG] = false
	GameScript.handle(s, 3, propose(s, INAUG, {1: "30%"}))
	GameScript.handle(s, 0, {"type": "rule_grammar", "ok": true})
	EliminationScript.eliminate(s, LEADER, "debt")
	expect("the amendment is abandoned and recorded under whoever proposed it", [s.amend.is_empty(), s.amendment_record.back()["leader"], s.vice_id], [true, 3, -1])


func views_and_saves() -> void:
	var s := new_turn()
	ViceScript.appoint(s, 3)
	var seen: Dictionary = ViewsScript.state_view(s, 5)
	expect("everyone sees who is Vice and their card", [seen["vice_id"], seen["vice_type"] == s.vice_type, seen["vice_windows_used"].size()], [3, true, 3])
	var errors: Array = []
	var restored: GameStateScript = SerializerScript.state_from_json(SerializerScript.state_to_json(s), errors)
	expect("a saved game keeps the Vice, their card and windows", [errors, restored.vice_id, restored.vice_type == s.vice_type, restored.vice_windows_used], [[], 3, true, s.vice_windows_used])

	# The ranking counts the half-rounds a Vice earned: one is enough to beat players with none, however rich.
	s = new_turn()
	s.half_rounds = {3: 1}
	s.psd[5] += 5000
	expect("a half-round as Vice puts a player ahead of richer players with none", ScoringScript.final_winners(s), [3])


# --- helpers -----------------------------------------------------------------------------

# The first election is over and the term is at its Inauguration, with player 2 as Leader.
func inaugurated() -> GameStateScript:
	for seed_value in range(1, 400):
		var s := GameScript.new_game([1, 2, 3, 4, 5], seed_value)
		for id in [1, 2, 3, 4, 5]:
			GameScript.handle(s, id, {"type": "cast_vote", "candidate": LEADER})
		if s.leader_type == PRESIDENT:
			return s
	assert(false, "no seed gave a President")
	return null


func propose(s: GameStateScript, window: int, changes: Dictionary) -> Dictionary:
	var words: Array = s.articles[TAX]
	var texts: Array = []
	for i in words.size():
		texts.append(changes.get(i, words[i]["text"]))
	return {"type": "propose", "window": window, "article_id": TAX, "new_texts": texts}


func card_number(deck: String, prefix: String) -> int:
	for i in CardsScript.count(deck):
		if CardsScript.text(deck, i).begins_with(prefix):
			return i
	return -1


func new_turn() -> GameStateScript:
	for seed_value in range(1, 400):
		var s := GameScript.new_game([1, 2, 3, 4, 5], seed_value)
		for id in [1, 2, 3, 4, 5]:
			GameScript.handle(s, id, {"type": "cast_vote", "candidate": LEADER})
		if s.leader_type == PRESIDENT:
			GameScript.handle(s, LEADER, {"type": "pass_window"})
			return s
	assert(false, "no seed gave a President")
	return null


func last_of(s: GameStateScript, type: String) -> Dictionary:
	for i in range(s.event_log.size() - 1, -1, -1):
		if s.event_log[i]["type"] == type:
			return s.event_log[i]
	return {}


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
