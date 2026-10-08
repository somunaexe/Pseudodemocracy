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
	amending_together()
	agreeing()
	consequences_are_shared()
	confronting()
	recruiting()
	after_a_coup()
	leaving_the_game()
	views_and_saves()
	print("%d failure(s)" % failures)
	quit(1 if failures > 0 else 0)


func appointing() -> void:
	var s := new_turn()
	expect("there is no Vice to start with", [s.vice_id, ViceScript.is_vice(s, 3), ViceScript.is_leader_or_vice(s, LEADER), ViceScript.is_leader_or_vice(s, 3)], [-1, false, true, false])
	var ev := ViceScript.appoint(s, 3)
	expect("a Vice is appointed", [ev[0]["type"], s.vice_id, ev[0]["vice"], ev[0]["replaced"]], ["vice_appointed", 3, 3, -1])
	expect("... and is a Leader in the usual sense", [ViceScript.is_vice(s, 3), ViceScript.is_leader_or_vice(s, 3)], [true, true])
	ev = ViceScript.appoint(s, 4)
	expect("a new Vice replaces the old one", [s.vice_id, ev[0]["replaced"]], [4, 3])
	ev = ViceScript.appoint(s, 4)
	expect("appointing the same Vice again replaces nobody", ev[0]["replaced"], -1)


func the_keys_to_the_city() -> void:
	var card: int = card_number("settlement", "You've obtained the keys to the city")
	var s := new_turn()
	s.popularity[3] = 0
	s.popularity[LEADER] = 10
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
	var type_before: int = s.leader_type
	ev = CardEffectsScript.apply(s, 3, "settlement", card)
	expect("a more popular drawer takes the Leader's role and the Leader is demoted to Vice", [types(ev), s.leader_id, s.vice_id], [["card_applied", "leader_swapped", "vice_appointed"], 3, LEADER])
	expect("... the new Leader keeps the Leader card of the role they took", [s.leader_type, ev[1]["leader_type"]], [type_before, type_before])
	expect("... the swap event names both", [ev[1]["new_leader"], ev[1]["old_leader"]], [3, LEADER])

	s = new_turn()
	ev = CardEffectsScript.apply(s, LEADER, "settlement", card)
	expect("the Leader drawing the keys gets nothing", [types(ev), s.vice_id, s.leader_id], [["card_applied", "keys_no_effect"], -1, LEADER])

	s = new_turn()
	ViceScript.appoint(s, 3)
	s.popularity[3] = 0
	s.popularity[LEADER] = 10
	ev = CardEffectsScript.apply(s, 3, "settlement", card)
	expect("a Vice who draws it, not more popular, stays Vice", [types(ev), s.vice_id], [["card_applied", "keys_no_effect"], 3])
	s.popularity[3] = 30
	ev = CardEffectsScript.apply(s, 3, "settlement", card)
	expect("... more popular, the Vice and the Leader swap", [s.leader_id, s.vice_id], [3, LEADER])

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
	expect("... and the Vice ends with the term", s.vice_id, -1)

	s = new_turn()
	var card: int = card_number("settlement", "You've obtained the keys to the city")
	s.popularity[3] = 30
	CardEffectsScript.apply(s, 3, "settlement", card)
	s.term = {}
	ElectionScript.begin(s, "term_ended")
	expect("the ousted Leader scores 1/2 for the term, the new Leader a full round", [s.half_rounds.get(LEADER, 0), s.half_rounds.get(3, 0)], [1, 2])

	s = new_turn()
	ViceScript.appoint(s, 3)
	GameScript.handle(s, 0, {"type": "finish_game"})
	expect("a game stopped mid-term credits the Vice half a round as well", [s.half_rounds.get(3, 0), s.half_rounds.get(LEADER, 0)], [1, 2])


func amending_together() -> void:
	var s := inaugurated()
	s.leader_type = PRESIDENT
	expect("a stranger still can't amend", PermissionsScript.leader_powers_problem(s, 3), "Only the Leader can amend the Constitution.")
	ViceScript.appoint(s, 3)
	expect("the Vice can propose (with the Leader)", PermissionsScript.leader_powers_problem(s, 3), "")
	s.leader_type = COMMANDER
	expect("... but not when the Leader is a Commander: nothing can be amended", [PermissionsScript.leader_powers_problem(s, LEADER), PermissionsScript.leader_powers_problem(s, 3)], ["A Commander can't amend.", "A Commander can't amend."])
	s.leader_type = PRESIDENT
	s.sick[3] = true
	expect("a sick Vice can't propose", PermissionsScript.leader_powers_problem(s, 3), "A sick Vice can't amend.")
	s.sick[3] = false
	s.popularity[3] = -50
	expect("a CANCELLED Vice can't", PermissionsScript.leader_powers_problem(s, 3), "A CANCELLED Vice can't amend.")
	s.popularity[3] = 0

	expect("who must agree: the other of the pair", [PermissionsScript.cosigner(s, LEADER), PermissionsScript.cosigner(s, 3)], [3, LEADER])
	s.sick[3] = true
	expect("a sick Vice isn't needed", PermissionsScript.cosigner(s, LEADER), 0)
	s.sick[3] = false
	s.popularity[3] = -50
	expect("nor a CANCELLED one", PermissionsScript.cosigner(s, LEADER), 0)
	s.popularity[3] = 0
	s.eliminated[3] = true
	expect("nor one who has left", PermissionsScript.cosigner(s, LEADER), 0)
	s = inaugurated()
	expect("with no Vice nobody has to agree", PermissionsScript.cosigner(s, LEADER), 0)


func agreeing() -> void:
	var s := inaugurated()
	s.leader_type = PRESIDENT
	var ev := GameScript.handle(s, LEADER, propose(s, INAUG, {1: "30%"}))
	expect("with no Vice the Leader's proposal goes straight out", [types(ev), s.amend_offer], [["amendment_proposed"], {}])

	s = inaugurated()
	s.leader_type = PRESIDENT
	ViceScript.appoint(s, 4)
	ev = GameScript.handle(s, LEADER, propose(s, INAUG, {1: "30%"}))
	expect("with a Vice the proposal waits for them", [types(ev), s.amend.is_empty(), s.windows_used[INAUG], s.amend_offer["other"], s.amend_offer["by"]], [["amendment_offered"], true, false, 4, LEADER])
	expect("... the offer is public and says how long", [ev[0]["audience"], ev[0]["seconds"], ev[0]["ends_at_ms"] > s.clock_ms], [[], 30, true])
	expect("... only the Vice can answer", GameScript.handle(s, 5, {"type": "amend_agree", "accept": true})[0]["reason"], "There is no proposal waiting for your agreement.")
	expect("... the proposer can't answer for them", GameScript.handle(s, LEADER, {"type": "amend_agree", "accept": true})[0]["reason"], "There is no proposal waiting for your agreement.")
	expect("... a bad answer is refused", GameScript.handle(s, 4, {"type": "amend_agree", "accept": "yes"})[0]["reason"], "Accept or refuse.")
	expect("... a second proposal while one waits is refused", GameScript.handle(s, 4, propose(s, INAUG, {1: "35%"}))[0]["reason"], "A proposal is already waiting for agreement.")
	expect("... the Leader can't pass the window under it", GameScript.handle(s, LEADER, {"type": "pass_window"})[0]["reason"], "A proposal is waiting for the Vice's agreement.")
	ev = GameScript.handle(s, 4, {"type": "amend_agree", "accept": true})
	expect("when the Vice agrees it goes out as the Leader's amendment, using the window", [types(ev), s.amend_offer, s.windows_used[INAUG], s.amendment_record.size()], [["amendment_proposed"], {}, true, 0])
	expect("... the proposal event names the Leader", ev[0]["leader"], LEADER)

	# The Vice proposes, the Leader agrees.
	s = inaugurated()
	s.leader_type = PRESIDENT
	ViceScript.appoint(s, 4)
	ev = GameScript.handle(s, 4, propose(s, INAUG, {1: "30%"}))
	expect("a Vice's proposal waits for the Leader", [types(ev), s.amend_offer["other"]], [["amendment_offered"], LEADER])
	ev = GameScript.handle(s, LEADER, {"type": "amend_agree", "accept": true})
	expect("... and goes out when they agree", [types(ev), s.amend["article_id"]], [["amendment_proposed"], TAX])

	# Refusal: nothing is used up.
	s = inaugurated()
	s.leader_type = PRESIDENT
	ViceScript.appoint(s, 4)
	GameScript.handle(s, LEADER, propose(s, INAUG, {1: "30%"}))
	ev = GameScript.handle(s, 4, {"type": "amend_agree", "accept": false})
	expect("a refusal drops the proposal and the window is still open", [types(ev), s.amend_offer, s.windows_used[INAUG], s.amend], [["amendment_offer_refused"], {}, false, {}])
	ev = GameScript.handle(s, LEADER, propose(s, INAUG, {1: "35%"}))
	expect("... so they can propose again", types(ev), ["amendment_offered"])

	# Silence is a refusal.
	GameScript.tick(s, int(s.amend_offer["deadline"]) - 1)
	expect("before the time is up it waits", s.amend_offer.is_empty(), false)
	var ticked := GameScript.tick(s, int(s.amend_offer["deadline"]))
	expect("silence is a refusal", [types(ticked), s.amend_offer, s.windows_used[INAUG]], [["amendment_offer_expired"], {}, false])

	# Everything is checked again when they agree.
	s = inaugurated()
	s.leader_type = PRESIDENT
	ViceScript.appoint(s, 4)
	GameScript.handle(s, LEADER, propose(s, INAUG, {1: "30%"}))
	s.windows_used[INAUG] = true
	ev = GameScript.handle(s, 4, {"type": "amend_agree", "accept": true})
	expect("if the window was used meanwhile the offer is void", [types(ev)[0], s.amend.is_empty()], ["amendment_offer_void", true])

	# The pair breaks up.
	s = inaugurated()
	s.leader_type = PRESIDENT
	ViceScript.appoint(s, 4)
	GameScript.handle(s, LEADER, propose(s, INAUG, {1: "30%"}))
	ViceScript.appoint(s, 5)
	expect("a new Vice drops a proposal made to the old one", s.amend_offer.is_empty(), true)
	GameScript.handle(s, LEADER, propose(s, INAUG, {1: "30%"}))
	s.vice_id = 3
	ticked = GameScript.tick(s)
	expect("... and a proposal whose pair is no longer the pair is void", [types(ticked), s.amend_offer], [["amendment_offer_void"], {}])

	# The Inauguration window waits while the offer is out.
	s = inaugurated()
	s.leader_type = PRESIDENT
	ViceScript.appoint(s, 4)
	GameScript.handle(s, LEADER, propose(s, INAUG, {1: "30%"}))
	GameScript.tick(s, s.clock_ms + 1000)
	expect("the Inauguration doesn't move on while a proposal waits", s.term["phase"], GameStateScript.TermPhase.INAUGURATION)
	GameScript.tick(s, int(s.amend_offer["deadline"]))
	GameScript.handle(s, LEADER, {"type": "pass_window"})
	expect("... it does once it is dealt with", s.term["phase"], GameStateScript.TermPhase.TURNS)

	# A Commander Leader: nothing at all.
	s = inaugurated()
	s.leader_type = COMMANDER
	ViceScript.appoint(s, 4)
	expect("a Commander and a Vice can't amend", GameScript.handle(s, 4, propose(s, INAUG, {1: "30%"}))[0]["reason"], "A Commander can't amend.")

	# The Farewell too, mid-term too.
	s = new_turn()
	s.leader_type = PRESIDENT
	ViceScript.appoint(s, 3)
	s.turns_played = 5
	ev = GameScript.handle(s, 3, propose(s, MID, {1: "30%"}))
	expect("the Mid-term window works the same", [types(ev), s.amend_offer["by"]], [["amendment_offered"], 3])


func consequences_are_shared() -> void:
	var s := inaugurated()
	s.leader_type = PRESIDENT
	ViceScript.appoint(s, 4)
	GameScript.handle(s, LEADER, propose(s, INAUG, {1: "30%"}))
	GameScript.handle(s, 4, {"type": "amend_agree", "accept": true})
	GameScript.handle(s, 0, {"type": "rule_grammar", "ok": true})
	expect("neither the Leader nor the Vice votes on it", [GameScript.handle(s, LEADER, {"type": "vote", "keep": true})[0]["reason"], GameScript.handle(s, 4, {"type": "vote", "keep": true})[0]["reason"]], ["You can't vote on this amendment.", "You can't vote on this amendment."])
	var leader_pop: int = PopularityScript.base(s, LEADER)
	var vice_pop: int = PopularityScript.base(s, 4)
	GameScript.handle(s, 1, {"type": "vote", "keep": true})
	GameScript.handle(s, 3, {"type": "vote", "keep": true})
	GameScript.handle(s, 5, {"type": "vote", "keep": false})
	expect("2 for and 1 against moves both their popularity, the same", [PopularityScript.base(s, LEADER) - leader_pop, PopularityScript.base(s, 4) - vice_pop], [6, 6])
	expect("... and it stands on the Leader's card (a President needs a majority)", last_of(s, "amendment_resolved")["stands"], true)

	s = inaugurated()
	s.leader_type = PRESIDENT
	ViceScript.appoint(s, 4)
	GameScript.handle(s, 4, propose(s, INAUG, {1: "30%"}))
	GameScript.handle(s, LEADER, {"type": "amend_agree", "accept": true})
	GameScript.handle(s, 0, {"type": "rule_grammar", "ok": true})
	for id in [1, 3, 5]:
		GameScript.handle(s, id, {"type": "vote", "keep": false})
	expect("voted down: both lose popularity and it fails", [last_of(s, "amendment_resolved")["stands"], PopularityScript.base(s, LEADER), PopularityScript.base(s, 4)], [false, -18, -18])
	expect("... the record says the Leader", s.amendment_record.back()["leader"], LEADER)

	# A failed check fines and costs both.
	s = inaugurated()
	s.leader_type = PRESIDENT
	ViceScript.appoint(s, 4)
	GameScript.handle(s, LEADER, propose(s, INAUG, {0: "Duty:"}))
	var cash: int = s.psd[4]
	var leader_cash: int = s.psd[LEADER]
	var pops: int = PopularityScript.base(s, 4)
	var ev := GameScript.handle(s, 4, {"type": "amend_agree", "accept": true})
	expect("a failed check fines both and costs both popularity", [s.psd[4] < cash, s.psd[LEADER] < leader_cash, PopularityScript.base(s, 4) < pops, types(ev).has("amendment_failed")], [true, true, true, true])
	var failed: Dictionary = last_of(s, "amendment_failed")
	expect("... each pays the 100 fine, and the event says what each lost", [failed["fine"], failed["fine_became_debt"], failed["popularity_lost"]], [100, 0, 24])

	# A Dictator Leader's amendment always stands.
	s = inaugurated()
	s.leader_type = DICTATOR
	ViceScript.appoint(s, 4)
	GameScript.handle(s, LEADER, propose(s, INAUG, {1: "30%"}))
	GameScript.handle(s, 4, {"type": "amend_agree", "accept": true})
	GameScript.handle(s, 0, {"type": "rule_grammar", "ok": true})
	for id in [1, 3, 5]:
		GameScript.handle(s, id, {"type": "vote", "keep": false})
	expect("the Leader's card decides: a Dictator's stands whatever the vote", last_of(s, "amendment_resolved")["stands"], true)


func confronting() -> void:
	var s := inaugurated()
	s.leader_type = PRESIDENT
	ViceScript.appoint(s, 4)
	s.unions[1] = {"type": GameStateScript.UnionType.AGBERO, "owner": 3, "members": [3, 5], "confront_used": false}
	GameScript.handle(s, LEADER, propose(s, INAUG, {1: "30%"}))
	GameScript.handle(s, 4, {"type": "amend_agree", "accept": true})
	GameScript.handle(s, 0, {"type": "rule_grammar", "ok": true})
	var leader_cash: int = s.psd[LEADER]
	var ev := GameScript.handle(s, 3, {"type": "confront", "union_id": 1})
	expect("an Agbero mob blocks it and the Leader pays", [types(ev).has("amendment_blocked"), s.psd[LEADER] < leader_cash], [true, true])

	s = inaugurated()
	ViceScript.appoint(s, 4)
	s.unions[1] = {"type": GameStateScript.UnionType.ACTIVIST, "owner": 3, "members": [3, 4], "confront_used": false}
	GameScript.handle(s, LEADER, propose(s, INAUG, {1: "30%"}))
	GameScript.handle(s, 4, {"type": "amend_agree", "accept": true})
	GameScript.handle(s, 0, {"type": "rule_grammar", "ok": true})
	expect("a union with the Vice in it can't confront their amendment either", GameScript.handle(s, 3, {"type": "confront", "union_id": 1})[0]["type"], "rejected")


func recruiting() -> void:
	var s := new_turn()
	ViceScript.appoint(s, 3)
	s.unions[1] = {"type": GameStateScript.UnionType.ACTIVIST, "owner": 4, "members": [4], "confront_used": false}
	PlayScript.take_turn(s, 2)
	PlayScript.take_turn(s, 3)
	expect("a union can't recruit the Vice", GameScript.handle(s, 4, {"type": "union_recruit", "union_id": 1, "target": 3})[0]["reason"], "A union can't recruit the Vice.")
	expect("... nor the Leader", GameScript.handle(s, 4, {"type": "union_recruit", "union_id": 1, "target": LEADER})[0]["reason"], "A union can't recruit the Leader.")
	s = new_turn()
	s.unions[1] = {"type": GameStateScript.UnionType.ACTIVIST, "owner": 4, "members": [4], "confront_used": false}
	s.union_invites[3] = {"union_id": 1, "deadline": 999999999}
	ViceScript.appoint(s, 3)
	var ev := GameScript.handle(s, 3, {"type": "union_respond", "accept": true})
	expect("an invitation answered after becoming Vice is void", [types(ev), s.unions[1]["members"]], [["union_invitation_void"], [4]])


func after_a_coup() -> void:
	# The rule itself.
	var s := new_turn()
	ViceScript.appoint(s, 3)
	s.leader_type = PRESIDENT
	expect("after a coup by a stranger and a President the Vice stays", [types(ViceScript.after_coup(s, 4)), s.vice_id], [[], 3])
	s.leader_type = COMMANDER
	expect("... and a Commander", [types(ViceScript.after_coup(s, 4)), s.vice_id], [[], 3])
	s.leader_type = DICTATOR
	var ev := ViceScript.after_coup(s, 4)
	expect("a Dictator removes the Vice", [types(ev), ev[0]["reason"], s.vice_id], [["vice_removed"], "the new Leader is a Dictator", -1])
	ViceScript.appoint(s, 3)
	s.leader_type = PRESIDENT
	ev = ViceScript.after_coup(s, 3)
	expect("a Vice who made the coup is Leader, not Vice", [types(ev), s.vice_id], [["vice_removed"], -1])

	# In a whole game: the Vice stays through the new term unless a Dictator is drawn.
	var stayed := 0
	var removed := 0
	for seed_value in range(1, 60):
		var g := coup_ready(seed_value)
		if g == null:
			continue
		ViceScript.appoint(g, 3)
		var out := GameScript.handle(g, 4, {"type": "coup"})
		if not types(out).has("coup_succeeded"):
			continue
		if g.leader_type == DICTATOR:
			removed += 1
			expect("a Dictator drawn by the coup removes the Vice (seed %d)" % seed_value, [g.vice_id, types(out).has("vice_removed")], [-1, true])
		else:
			stayed += 1
			expect("otherwise the Vice stays for the new term (seed %d)" % seed_value, [g.vice_id, g.half_rounds.get(3, 0)], [3, 0])
	expect("both outcomes were seen in the games", [stayed > 0, removed > 0], [true, true])

	# The Vice stays and then scores at the end of the NEW term.
	for seed_value in range(1, 60):
		var g := coup_ready(seed_value)
		if g == null:
			continue
		ViceScript.appoint(g, 3)
		GameScript.handle(g, 4, {"type": "coup"})
		if g.vice_id == 3:
			g.term = {}
			ElectionScript.begin(g, "term_ended")
			expect("the Vice who stayed scores half a round when the new term ends", [g.half_rounds.get(3, 0), g.half_rounds.get(4, 0), g.vice_id], [1, 2, -1])
			break

	# The Vice is the one who couped: they become Leader.
	for seed_value in range(1, 60):
		var g := coup_ready(seed_value)
		if g == null:
			continue
		ViceScript.appoint(g, 4)
		GameScript.handle(g, 4, {"type": "coup"})
		if g.leader_id == 4:
			expect("a Vice who overthrows the Leader is Leader, with no Vice", g.vice_id, -1)
			break


func leaving_the_game() -> void:
	var s := new_turn()
	ViceScript.appoint(s, 3)
	var ev := EliminationScript.eliminate(s, 3, "debt")
	expect("an eliminated Vice is gone", [s.vice_id, types(ev).has("vice_vacant"), s.leader_id], [-1, true, LEADER])

	# The Leader leaves: the Vice takes over and the term goes on.
	s = new_turn()
	ViceScript.appoint(s, 3)
	var type_before: int = s.leader_type
	var phase_before: int = s.term["phase"]
	ev = EliminationScript.eliminate(s, LEADER, "debt")
	expect("when the Leader is eliminated the Vice takes over", [s.leader_id, s.vice_id, types(ev).has("vice_succeeded"), types(ev).has("leader_vacant")], [3, -1, true, false])
	expect("... the term goes on, with no election, on the same Leader card", [s.term["phase"], s.election.is_empty(), s.leader_type], [phase_before, true, type_before])
	expect("... the eliminated Leader's cut-short term is recorded, nothing for the new Leader yet", [s.half_rounds.get(LEADER, 0), s.half_rounds.get(3, 0)], [1, 0])

	# Their amendment under way is abandoned.
	s = inaugurated()
	s.leader_type = PRESIDENT
	ViceScript.appoint(s, 3)
	GameScript.handle(s, LEADER, propose(s, INAUG, {1: "30%"}))
	GameScript.handle(s, 3, {"type": "amend_agree", "accept": true})
	GameScript.handle(s, 0, {"type": "rule_grammar", "ok": true})
	ev = EliminationScript.eliminate(s, LEADER, "debt")
	expect("an amendment under way when the Leader leaves is abandoned", [s.amend.is_empty(), types(ev).has("amendment_abandoned"), s.amendment_record.back()["outcome"], s.leader_id], [true, true, "abandoned", 3])

	# A waiting proposal goes with its pair.
	s = inaugurated()
	s.leader_type = PRESIDENT
	ViceScript.appoint(s, 3)
	GameScript.handle(s, LEADER, propose(s, INAUG, {1: "30%"}))
	EliminationScript.eliminate(s, 3, "debt")
	expect("when the Vice is eliminated the waiting proposal is dropped", [s.amend_offer.is_empty(), s.vice_id], [true, -1])

	# No Vice: the old rule stays, an election.
	s = new_turn()
	ev = EliminationScript.eliminate(s, LEADER, "debt")
	expect("with no Vice, a Leader who leaves means an election", [types(ev).has("leader_vacant"), s.election["reason"]], [true, "vacancy"])


func views_and_saves() -> void:
	var s := new_turn()
	ViceScript.appoint(s, 3)
	var seen: Dictionary = ViewsScript.state_view(s, 5)
	expect("everyone sees who is Vice", seen["vice_id"], 3)
	s = inaugurated()
	ViceScript.appoint(s, 4)
	GameScript.handle(s, LEADER, propose(s, INAUG, {1: "30%"}))
	seen = ViewsScript.state_view(s, 5)
	expect("... and a proposal waiting for agreement", [seen["amend_offer"]["by"], seen["amend_offer"]["other"]], [LEADER, 4])
	var errors: Array = []
	var restored: GameStateScript = SerializerScript.state_from_json(SerializerScript.state_to_json(s), errors)
	expect("a saved game keeps the Vice and the offer", [errors, restored.vice_id, restored.amend_offer["other"]], [[], 4, 4])
	var ev := GameScript.handle(restored, 4, {"type": "amend_agree", "accept": true})
	expect("... and the restored game carries on", types(ev), ["amendment_proposed"])

	s = new_turn()
	s.half_rounds = {3: 1}
	s.psd[5] += 5000
	expect("a half-round as Vice puts a player ahead of richer players with none", ScoringScript.final_winners(s), [3])


# --- helpers -----------------------------------------------------------------------------

# A running term where player 4 holds a coup card, is far ahead in popularity and has the cash. Null for seeds with no President.
func coup_ready(seed_value: int) -> GameStateScript:
	var s := GameScript.new_game([1, 2, 3, 4, 5], seed_value)
	for id in [1, 2, 3, 4, 5]:
		GameScript.handle(s, id, {"type": "cast_vote", "candidate": LEADER})
	if s.leader_type != PRESIDENT:
		return null
	GameScript.handle(s, LEADER, {"type": "pass_window"})
	for role in RolesScript.names():
		RolesScript.grant(s, 4, role)
		if RolesScript.has_sticker(s, 4, role):
			break
		RolesScript.remove(s, 4, role)
	s.popularity[4] = 30
	return s


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
