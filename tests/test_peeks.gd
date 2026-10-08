extends SceneTree

const GameScript = preload("res://scripts/game.gd")
const GameStateScript = preload("res://scripts/game_state.gd")
const CardsScript = preload("res://scripts/cards.gd")
const CardEffectsScript = preload("res://scripts/card_effects.gd")
const PeeksScript = preload("res://scripts/peeks.gd")
const RivalsScript = preload("res://scripts/rivals.gd")
const RolesScript = preload("res://scripts/roles.gd")
const RoundEndScript = preload("res://scripts/round_end.gd")
const EliminationScript = preload("res://scripts/elimination.gd")
const SerializerScript = preload("res://scripts/serializer.gd")
const ViewsScript = preload("res://scripts/views.gd")

const PRESIDENT = GameStateScript.LeaderType.PRESIDENT

var failures: int = 0


func _init() -> void:
	a_rival_has_your_number()
	using_a_permit()
	the_bead()
	a_rival_checks_once()
	the_agents_favor()
	secrecy()
	leaving_and_saving()
	print("%d failure(s)" % failures)
	quit(1 if failures > 0 else 0)


func a_rival_has_your_number() -> void:
	var s := new_turn()
	var card: int = card_number("scandal", "A rival now has your number")
	var ev := CardEffectsScript.apply(s, 3, "scandal", card)
	expect("the card asks the drawer to choose a player", [s.choice["kind"], s.choice["candidates"]], ["player", [1, 2, 4, 5]])
	ev = send(s, 3, {"type": "choose", "choice": 4})
	expect("the chosen player gets a free check of the drawer, for the rest of the round", [types(ev), s.peeks], [["choice_made", "peek_granted"], [{"holder": 4, "target": 3, "kinds": ["bead", "coup"], "round_only": true}]])
	expect("... the grant is public (the card is read out)", ev[1]["audience"], [])


func using_a_permit() -> void:
	var s := with_permit(4, 3, ["bead", "coup"], true)
	RolesScript.grant(s, 3, "Doctor")
	RolesScript.grant(s, 3, "Lawyer")
	var expected: Array = PeeksScript.cards_of(s, 3)
	expect("cards_of lists each role with its sticker", [expected.size(), expected[0]["role"], typeof(expected[0]["sticker"])], [2, "Doctor", TYPE_BOOL])
	expect("a player with no permit can't check", send(s, 5, {"type": "peek", "target": 3, "kind": "coup"})[0]["reason"], "You have no free check of that.")
	expect("... nor the wrong target", send(s, 4, {"type": "peek", "target": 5, "kind": "coup"})[0]["reason"], "You have no free check of that.")
	for bad in [{"target": "3", "kind": "coup"}, {"target": 3, "kind": "will"}, {"target": 3}, {"kind": "coup"}]:
		bad["type"] = "peek"
		expect("a malformed request %s is refused" % str(bad), send(s, 4, bad)[0]["reason"], "Say whose coup cards or bead to check.")
	var ev := send(s, 4, {"type": "peek", "target": 3, "kind": "coup"})
	expect("the holder checks and is told, privately", [types(ev), ev[0]["audience"], ev[0]["cards"]], [["peek_report"], [4], expected])
	expect("... the permit is used up (one check, whichever kind)", [s.peeks, send(s, 4, {"type": "peek", "target": 3, "kind": "bead"})[0]["type"]], [[], "rejected"])
	expect("the report is in the log for the holder only", s.event_log.back()["audience"], [4])

	# Sticker flags are the real ones.
	var stickered: Array = RolesScript.coup_cards(s, 3).map(func(c): return c[1])
	var shown: Array = expected.filter(func(c): return c["sticker"]).map(func(c): return c["role"])
	expect("the stickers shown are the stickers the cards carry", shown, stickered)

	# The round ends the permit.
	s = with_permit(4, 3, ["coup"], true)
	RoundEndScript.run(s)
	expect("a permit for the rest of the round ends with it", s.peeks, [])
	s = with_permit(4, 3, ["coup"], false)
	RoundEndScript.run(s)
	expect("one without a limit stays until used", s.peeks.size(), 1)


func the_bead() -> void:
	var s := with_permit(4, 3, ["bead", "coup"], true)
	expect("no cure under way: nothing to see, and the permit is kept", [send(s, 4, {"type": "peek", "target": 3, "kind": "bead"})[0]["reason"], s.peeks.size()], ["That player is not handing over a bead right now.", 1])
	s.dose = {"phase": GameStateScript.DosePhase.GUESSING, "doctor": 3, "patient": 5, "kind": "heal", "dose": "Agbo", "price": 40, "deadline": 99000, "guesser": 0}
	s.dose_secret = {"poison": true}
	var ev := send(s, 4, {"type": "peek", "target": 3, "kind": "bead"})
	expect("while the target is handing over a cure the holder sees the bead", [ev[0]["bead"], ev[0]["patient"], ev[0]["audience"], s.peeks], ["red", 5, [4], []])
	s = with_permit(4, 3, ["bead"], true)
	s.dose = {"phase": GameStateScript.DosePhase.GUESSING, "doctor": 2, "patient": 5, "kind": "heal", "dose": "Agbo", "price": 40, "deadline": 99000, "guesser": 0}
	expect("a cure by someone else is not theirs to see", send(s, 4, {"type": "peek", "target": 3, "kind": "bead"})[0]["type"], "rejected")


func a_rival_checks_once() -> void:
	var card: int = card_number("scandal", "A rival gets to check your coup-card status")
	var s := new_turn()
	var ev := CardEffectsScript.apply(s, 3, "scandal", card)
	expect("with no rival nothing happens, and it is said", [types(ev), s.peeks], [["card_applied", "peek_unavailable"], []])
	s = new_turn()
	RivalsScript.name_rival(s, 5, 3)   # 5 has named the drawer
	ev = CardEffectsScript.apply(s, 3, "scandal", card)
	expect("a player who named the drawer a rival gets one free check of coup-card status, which doesn't expire", [types(ev), s.peeks], [["card_applied", "peek_granted"], [{"holder": 5, "target": 3, "kinds": ["coup"], "round_only": false}]])
	s = new_turn()
	RivalsScript.name_rival(s, 3, 4)   # the drawer named 4
	CardEffectsScript.apply(s, 3, "scandal", card)
	expect("... the drawer's own rival counts too", s.peeks[0]["holder"], 4)
	var holders := {}
	for seed_value in 16:
		var g := new_turn()
		g.rng_state = seed_value * 7919 + 3
		RivalsScript.name_rival(g, 5, 3)
		RivalsScript.name_rival(g, 3, 4)
		CardEffectsScript.apply(g, 3, "scandal", card)
		holders[g.peeks[0]["holder"]] = true
	expect("with several, one is chosen at random", holders.keys().size(), 2)
	s = new_turn()
	RivalsScript.name_rival(s, 5, 3)
	s.eliminated[5] = true
	ev = CardEffectsScript.apply(s, 3, "scandal", card)
	expect("a rival who has left can't be the one", types(ev), ["card_applied", "peek_unavailable"])


func the_agents_favor() -> void:
	var card: int = card_number("settlement", "A Secret Agent owes you a favor")
	var s := new_turn()
	RolesScript.grant(s, 5, "Secret Agent")
	RolesScript.grant(s, 4, "Doctor")
	CardEffectsScript.apply(s, 3, "settlement", card)
	expect("the favor asks for a player with a role", s.choice["candidates"], [4, 5])
	var ev := send(s, 3, {"type": "choose", "choice": 4})
	var report: Dictionary = last_of(s, "favor_report")
	expect("with an Agent about, the drawer is shown the role cards of the player", [types(ev), report["audience"], report["cards"], report["target"]], [["choice_made", "favor_report"], [3], PeeksScript.cards_of(s, 4), 4])
	expect("... it uses nobody's once-a-round check", s.agent_used, {})
	s = new_turn()
	RolesScript.grant(s, 4, "Doctor")
	CardEffectsScript.apply(s, 3, "settlement", card)
	ev = send(s, 3, {"type": "choose", "choice": 4})
	expect("with no Secret Agent at the table there is no favor", types(ev), ["choice_made", "favor_unavailable"])
	s = new_turn()
	RolesScript.grant(s, 3, "Secret Agent")
	RolesScript.grant(s, 4, "Doctor")
	CardEffectsScript.apply(s, 3, "settlement", card)
	ev = send(s, 3, {"type": "choose", "choice": 4})
	expect("the drawer being the only Agent doesn't count", types(ev), ["choice_made", "favor_unavailable"])


func secrecy() -> void:
	var s := with_permit(4, 3, ["coup"], true)
	expect("the permit list is never in anyone's view", ViewsScript.state_view(s, 3).has("peeks"), false)
	expect("the holder sees their own permits", ViewsScript.state_view(s, 4)["my_peeks"], [{"target": 3, "kinds": ["coup"], "round_only": true}])
	expect("... the target and others see none", [ViewsScript.state_view(s, 3)["my_peeks"], ViewsScript.state_view(s, 5)["my_peeks"]], [[], []])
	var ev := send(s, 4, {"type": "peek", "target": 3, "kind": "coup"})
	expect("the report reaches the holder only", [ViewsScript.visible_events(ev, 4).size(), ViewsScript.visible_events(ev, 3).size(), ViewsScript.visible_events(ev, 5).size()], [1, 0, 0])
	var seen_by_target: Array = ViewsScript.state_view(s, 3)["event_log"].filter(func(e): return e["type"] == "peek_report")
	expect("... and the target's copy of the log has no trace of it", seen_by_target.size(), 0)


func leaving_and_saving() -> void:
	var s := with_permit(4, 3, ["coup"], false)
	PeeksScript.grant(s, 5, 3, ["coup"], false)
	PeeksScript.grant(s, 1, 2, ["coup"], false)
	EliminationScript.eliminate(s, 3, "debt")
	expect("when the target or the holder leaves, their permits go", s.peeks.size(), 1)
	var errors: Array = []
	var restored: GameStateScript = SerializerScript.state_from_json(SerializerScript.state_to_json(s), errors)
	expect("a saved game keeps the rest", [errors, restored.peeks], [[], s.peeks])


# --- helpers -----------------------------------------------------------------------------

func with_permit(holder: int, target: int, kinds: Array, round_only: bool) -> GameStateScript:
	var s := new_turn()
	PeeksScript.grant(s, holder, target, kinds, round_only)
	return s


func card_number(deck: String, prefix: String) -> int:
	for i in CardsScript.count(deck):
		if CardsScript.text(deck, i).begins_with(prefix):
			return i
	return -1


func new_turn() -> GameStateScript:
	for seed_value in range(1, 400):
		var s := GameScript.new_game([1, 2, 3, 4, 5], seed_value)
		for id in [1, 2, 3, 4, 5]:
			GameScript.handle(s, id, {"type": "cast_vote", "candidate": 2})
		if s.leader_type == PRESIDENT:
			GameScript.handle(s, 2, {"type": "pass_window"})
			return s
	assert(false, "no seed gave a President")
	return null


func last_of(s: GameStateScript, type: String) -> Dictionary:
	for i in range(s.event_log.size() - 1, -1, -1):
		if s.event_log[i]["type"] == type:
			return s.event_log[i]
	return {}


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
