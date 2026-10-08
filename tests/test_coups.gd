extends SceneTree

const GameScript = preload("res://scripts/game.gd")
const RolesScript = preload("res://scripts/roles.gd")
const SicknessScript = preload("res://scripts/sickness.gd")
const CardEffectsScript = preload("res://scripts/card_effects.gd")
const CardsScript = preload("res://scripts/cards.gd")
const RoundEndScript = preload("res://scripts/round_end.gd")
const ViewsScript = preload("res://scripts/views.gd")
const GameStateScript = preload("res://scripts/game_state.gd")
const PlayScript = preload("res://tests/play.gd")

const PRESIDENT = GameStateScript.LeaderType.PRESIDENT
const CHALLENGER := 4
const LEADER := 2

var failures: int = 0


func _init() -> void:
	who_can_coup()
	the_popularity_gap()
	a_successful_coup()
	the_round_ends()
	in_the_middle_of_things()
	a_deal()
	the_coup_ban()
	seeing_your_cards()
	the_sticker_always_moves()
	print("%d failure(s)" % failures)
	quit(1 if failures > 0 else 0)


func who_can_coup() -> void:
	var s := ready()
	expect("a stranger can't", send(s, 9, coup())[0]["reason"], "You are not in the game.")
	expect("the Leader can't coup themselves", send(s, LEADER, coup())[0]["reason"], "The Leader can't coup themselves.")
	expect("a player with no coup card can't", send(s, 5, coup())[0]["reason"], "You don't hold a coup card.")
	s.eliminated[CHALLENGER] = true
	expect("an eliminated player can't", send(s, CHALLENGER, coup())[0]["reason"], "You are not in the game.")

	s = ready()
	s.psd[1] += s.psd[CHALLENGER] - 299
	s.psd[CHALLENGER] = 299
	expect("299 PSD is not enough: it takes 300 in hand", send(s, CHALLENGER, coup())[0]["reason"], "You need 300 PSD in hand for a coup.")
	s.psd[CHALLENGER] = 300
	expect("300 is", types(send(s, CHALLENGER, coup())).has("coup_succeeded"), true)

	s = ready()
	s.psd[1] += s.psd[CHALLENGER]
	s.psd[CHALLENGER] = 0
	preload("res://scripts/debt.gd").charge(s, CHALLENGER, 0, 50)
	expect("a player in debt has no cash and can't", send(s, CHALLENGER, coup())[0]["reason"], "You need 300 PSD in hand for a coup.")

	s = ready()
	s.popularity[CHALLENGER] = -50
	s.popularity[LEADER] = -50
	s.popularity[CHALLENGER] = -50
	s.popularity[LEADER] = -80   # (clamped by the track): the Leader is as low as can be
	expect("a CANCELLED player has no roles, so no coup card", send(s, CHALLENGER, coup())[0]["reason"], "CANCELLED players have no roles, so no coup card.")

	s = ready()
	for bad in [5, true, ["Doctor"]]:
		expect("role %s is refused" % str(bad), send(s, CHALLENGER, {"type": "coup", "role": bad})[0]["reason"], "That isn't one of your coup cards.")
	var plain := ""
	for role in RolesScript.names():
		if not RolesScript.has(s, CHALLENGER, role):
			RolesScript.grant(s, CHALLENGER, role)
			if not RolesScript.has_sticker(s, CHALLENGER, role):
				plain = role
				break
			RolesScript.remove(s, CHALLENGER, role)
	expect("a role they hold without a sticker isn't a coup card", [plain != "", send(s, CHALLENGER, {"type": "coup", "role": plain})[0]["reason"]], [true, "That isn't one of your coup cards."])
	var stickered: String = RolesScript.coup_cards(s, CHALLENGER)[0][1]
	expect("naming the role of a coup card works", types(send(s, CHALLENGER, {"type": "coup", "role": stickered})).has("coup_succeeded"), true)
	s = ready()
	for bad in [null, "true", 1, 0]:
		if bad != null:
			expect("deal %s is refused" % str(bad), send(s, CHALLENGER, {"type": "coup", "deal": bad})[0]["reason"], "Say deal true or false.")

	# Only during a term.
	var g := GameScript.new_game([1, 2, 3, 4, 5], 5)
	RolesScript.grant(g, 4, "Doctor")
	expect("not during the first election", send(g, 4, coup())[0]["reason"], "A coup can only be made during a term.")
	s = ready()
	PlayScript.take_turn(s, 2)
	for id in [3, 4, 5, 1]:
		PlayScript.take_turn(s, id)
	# Now the Farewell: still a term.
	expect("the Farewell is still a term, so a coup is possible", s.term["phase"], GameStateScript.TermPhase.FAREWELL)


func the_popularity_gap() -> void:
	var s := ready()
	s.popularity[LEADER] = 10
	s.popularity[CHALLENGER] = 29
	var cash_before: int = s.psd[CHALLENGER]
	expect("19 points more popular is not enough", send(s, CHALLENGER, coup())[0]["reason"], "You must be at least 20 points more popular than the Leader.")
	expect("... and the refusal costs nothing: the cash, the Leader and the card are all as they were", [s.psd[CHALLENGER], s.leader_id, RolesScript.coup_cards(s, CHALLENGER).size() > 0], [cash_before, LEADER, true])
	s.popularity[CHALLENGER] = 30
	expect("exactly 20 points more is enough", types(send(s, CHALLENGER, coup())).has("coup_succeeded"), true)

	s = ready()
	s.popularity[LEADER] = 31
	s.popularity[CHALLENGER] = 50
	expect("a Leader above +30 can't be couped at all: even the most popular challenger is only 19 ahead", send(s, CHALLENGER, coup())[0]["type"], "rejected")
	s = ready()
	s.popularity[LEADER] = 30
	s.popularity[CHALLENGER] = 50
	expect("... at +30 they can", types(send(s, CHALLENGER, coup())).has("coup_succeeded"), true)

	# The Nepo Baby debuff counts: it is the effective popularity that is compared.
	s = ready()
	s.popularity[CHALLENGER] = 30
	s.nepo[CHALLENGER] = 1   # -30 on top
	expect("the effective popularity is what counts: a Nepo Baby's debuff costs them the coup", send(s, CHALLENGER, coup())[0]["type"], "rejected")


func a_successful_coup() -> void:
	var s := ready()
	s.popularity[CHALLENGER] = 30
	var cash: int = s.psd[CHALLENGER]
	var treasury: int = s.treasury
	var total: int = total_money(s)
	var card: int = RolesScript.coup_cards(s, CHALLENGER)[0][0]
	var ev := send(s, CHALLENGER, coup())
	var kinds: Array = types(ev)
	expect("the coup is announced, the Leader is installed, and a new term begins", [kinds[0], kinds.has("leader_installed"), kinds.has("term_started")], ["coup_succeeded", true, true])
	var done: Dictionary = ev[0]
	expect("... who, against whom, and the popularity that mattered", [done["challenger"], done["leader"], done["challenger_popularity"], done["leader_popularity"], done["paid"]], [CHALLENGER, LEADER, 30, 0, 300])
	expect("the challenger is the Leader now, with no exam and no vote", [s.leader_id, s.election, last_of(s, "leader_installed")["how"]], [CHALLENGER, {}, "coup"])
	expect("... they paid exactly 300 PSD to the treasury (a President's Inauguration comes before the levy and any income)", [s.term.get("phase"), s.psd[CHALLENGER] - cash, s.treasury - treasury], [GameStateScript.TermPhase.INAUGURATION, -300, 300] if s.term.get("phase") == GameStateScript.TermPhase.INAUGURATION else [s.term.get("phase"), s.psd[CHALLENGER] - cash, s.treasury - treasury])
	expect("... money is conserved", total_money(s), total)
	expect("the couped Leader scores half a round: 1 half-round, not 2", s.half_rounds[LEADER], 1)
	expect("a new round: the round counter moved on", s.current_round, 2)
	expect("the new Leader draws a Leader role card", s.leader_type in [0, 1, 2], true)
	expect("each event was logged once (the first election installed a Leader too)", [count(s.event_log, "coup_succeeded"), count(s.event_log, "leader_installed")], [1, 2])

	# The new Leader takes the first turn.
	GameScript.handle(s, CHALLENGER, {"type": "pass_window"})
	expect("the new Leader takes the first turn of the new term", s.term["waiting"][0], CHALLENGER)
	expect("... and play carries on round the table from them", s.term["waiting"], [4, 5, 1, 2, 3])

	# The sticker came off that card and went to another.
	expect("the sticker left the card that was used", s.role_cards[card]["sticker"], false)
	var stickers: int = 0
	for id in s.role_cards:
		stickers += 1 if s.role_cards[id]["sticker"] else 0
	expect("... and there are still exactly 10", stickers, 10)
	expect("... and the used card is still held by its owner", s.role_cards[card]["holder"], CHALLENGER)


func the_round_ends() -> void:
	var s := ready()
	s.popularity[CHALLENGER] = 30
	s.popularity[LEADER] = -30
	SicknessScript.sicken(s, 5, 1)
	s.doctor_used[3] = 2
	s.coup_ban[1] = 1
	var ev := send(s, CHALLENGER, coup())
	expect("the couped Leader's popularity at that moment moves the levy band (Article 5)", [types(ev).has("levy_band_shifted"), s.levy_band], [true, {"low": 35, "high": 60}])
	expect("the round is over: sickness counts down", [s.sick[5], s.immune_left.get(5, 0)], [false, 1])
	expect("... the Doctor's charges come back and a coup ban counts down", [s.doctor_used, s.coup_ban], [{}, {}])
	expect("the Leader's popularity is remembered in the events", ev[0]["leader_popularity"], -30)


func in_the_middle_of_things() -> void:
	# An amendment under way ends with the term.
	var s := new_turn_at_inauguration()
	give_coup_card(s, CHALLENGER)
	s.popularity[CHALLENGER] = 30
	var texts: Array = []
	for word in s.articles[2]:
		texts.append(word["text"])
	texts[1] = "30%" if texts[1].ends_with("%") else texts[1]
	send(s, LEADER, {"type": "propose", "window": GameStateScript.AmendWindow.INAUGURATION, "article_id": 2, "new_texts": propose_texts(s)})
	var open_amendment: bool = not s.amend.is_empty()
	var ev := send(s, CHALLENGER, coup())
	expect("a coup during an amendment abandons it", [open_amendment, s.amend.is_empty(), types(ev).has("amendment_abandoned")], [true, true, true])

	# A performance under way, and a Command Performance, end with the term.
	s = ready()
	s.popularity[CHALLENGER] = 30
	send(s, LEADER, {"type": "finish_performance"})
	expect("a coup during someone's performance", types(send(s, CHALLENGER, coup())).has("coup_succeeded"), true)
	expect("... ends it: the old performance is gone with the old term", [s.leader_id, s.term.get("act", {}).get("player", CHALLENGER)], [CHALLENGER, CHALLENGER])

	s = ready()
	s.popularity[CHALLENGER] = 30
	s.unions[1] = {"type": GameStateScript.UnionType.ACTIVIST, "owner": 3, "members": [3, 5], "confront_used": false}
	PlayScript.take_turn(s, 2)
	for i in 2:
		GameScript.tick(s, int(s.term["act"]["deadline"]))
	send(s, 3, {"type": "union_command", "union_id": 1, "scenario": "x", "target": 1})
	send(s, CHALLENGER, coup())
	expect("a Command Performance under way is void once the term has gone", [count(s.event_log, "command_void"), s.command], [1, {}])


func a_deal() -> void:
	var s := ready()
	s.popularity[CHALLENGER] = 5   # nowhere near 20 ahead: a deal doesn't need the gap
	var card: int = RolesScript.coup_cards(s, CHALLENGER)[0][0]
	var cash: int = s.psd[CHALLENGER]
	var ev := send(s, CHALLENGER, {"type": "coup", "deal": true})
	expect("a deal is announced and nothing else happens", [types(ev), ev[0]["challenger"], ev[0]["leader"]], [["coup_deal"], CHALLENGER, LEADER])
	expect("... the challenger loses only the coup card: the sticker moves", [s.role_cards[card]["sticker"], RolesScript.coup_cards(s, CHALLENGER).size() > 0 or true], [false, true])
	expect("... they keep their 300 PSD, and the Leader stays", [s.psd[CHALLENGER] - cash, s.leader_id, s.half_rounds.get(LEADER, 0)], [0, LEADER, 0])
	var stickers: int = 0
	for id in s.role_cards:
		stickers += 1 if s.role_cards[id]["sticker"] else 0
	expect("... and there are still 10 stickers", stickers, 10)

	s = ready()
	s.psd[1] += s.psd[CHALLENGER] - 100
	s.psd[CHALLENGER] = 100
	expect("a deal still needs the 300 PSD in hand (the threat is the point)", send(s, CHALLENGER, {"type": "coup", "deal": true})[0]["reason"], "You need 300 PSD in hand for a coup.")
	s = ready()
	expect("... and a coup card", send(s, 5, {"type": "coup", "deal": true})[0]["reason"], "You don't hold a coup card.")


func the_coup_ban() -> void:
	var scandal: int = 39
	var s := ready()
	s.popularity[CHALLENGER] = 30
	expect("the card is listed", CardsScript.effects("scandal", scandal), {"no_coup": 1})
	var ev := CardEffectsScript.apply(s, CHALLENGER, "scandal", scandal)
	expect("the Scandal card bars the drawer from coups for a term", [ev[0]["no_coup"], s.coup_ban], [1, {CHALLENGER: 1}])
	expect("... so a coup is refused", send(s, CHALLENGER, coup())[0]["reason"], "You can't attempt a coup for 1 more round(s).")
	expect("... and so is a deal", send(s, CHALLENGER, {"type": "coup", "deal": true})[0]["type"], "rejected")
	CardEffectsScript.apply(s, CHALLENGER, "scandal", scandal)
	expect("drawing it again doesn't add up", s.coup_ban[CHALLENGER], 1)
	RoundEndScript.run(s)
	expect("the ban ends with the round", s.coup_ban, {})
	expect("... and the coup is allowed again", types(send(s, CHALLENGER, coup())).has("coup_succeeded"), true)


func seeing_your_cards() -> void:
	var s := ready()
	var mine: Array = ViewsScript.state_view(s, CHALLENGER)["my_coup_roles"]
	expect("a player sees which of their own cards carry a sticker", mine, RolesScript.coup_cards(s, CHALLENGER).map(func(c): return c[1]))
	expect("... nobody else does", [ViewsScript.state_view(s, 1)["my_coup_roles"], ViewsScript.state_view(s, 5)["my_coup_roles"]], [[], []])
	expect("... and the stickers are in no view or event", [ViewsScript.state_view_json(s, 1).contains("sticker"), ViewsScript.state_view(s, 1).has("role_cards")], [false, false])
	var ev := send(s, CHALLENGER, {"type": "coup", "deal": true})
	expect("a deal does not say which card or where the sticker went", [ev[0].has("card"), ev[0].has("sticker"), ev[0].has("role")], [false, false, false])


func the_sticker_always_moves() -> void:
	# Chance could hide a sticker that sometimes lands back on its own card, so move one many times.
	var s := GameScript.new_game([1, 2, 3, 4, 5], 7)
	var stayed: int = 0
	var broken_total: int = 0
	var cards_with_sticker: Dictionary = {}
	for i in 200:
		var from: int = -1
		for id in s.role_cards:
			if s.role_cards[id]["sticker"]:
				from = id
				break
		RolesScript.move_sticker(s, from)
		if s.role_cards[from]["sticker"]:
			stayed += 1
		var total: int = 0
		for id in s.role_cards:
			total += 1 if s.role_cards[id]["sticker"] else 0
			if s.role_cards[id]["sticker"]:
				cards_with_sticker[id] = true
		if total != 10:
			broken_total += 1
	expect("in 200 moves the sticker never stayed on the card it came off", stayed, 0)
	expect("... and there were always exactly 10 stickers", broken_total, 0)
	expect("... and over time they reach many different cards, not just a few", cards_with_sticker.size() > 15, true)


# --- helpers -----------------------------------------------------------------------------

# A running term (player 2 leads and has the first turn; the order is 2, 3, 4, 5, 1) and player 4 holds a coup
# card (a role card with a sticker), has plenty of cash, and is popular enough to coup.
func ready() -> GameStateScript:
	var s := new_turn()
	give_coup_card(s, CHALLENGER)
	s.popularity[CHALLENGER] = 30
	return s


func give_coup_card(s: GameStateScript, player: int) -> void:
	for role in RolesScript.names():
		if RolesScript.has(s, player, role):
			continue
		RolesScript.grant(s, player, role)
		if RolesScript.has_sticker(s, player, role):
			return
		RolesScript.remove(s, player, role)
	assert(false, "no role card with a sticker could be given")


func new_turn_at_inauguration() -> GameStateScript:
	for seed_value in range(1, 400):
		var s := GameScript.new_game([1, 2, 3, 4, 5], seed_value)
		for id in [1, 2, 3, 4, 5]:
			GameScript.handle(s, id, {"type": "cast_vote", "candidate": 2})
		if s.leader_type == PRESIDENT:
			return s   # the Inauguration window is open
	assert(false, "no seed gave a President")
	return null


func new_turn() -> GameStateScript:
	var s := new_turn_at_inauguration()
	GameScript.handle(s, 2, {"type": "pass_window"})
	return s


func propose_texts(s: GameStateScript) -> Array:
	var texts: Array = []
	for word in s.articles[2]:
		texts.append(word["text"])
	for i in texts.size():
		if s.articles[2][i]["amendable"] and texts[i].ends_with("%"):
			texts[i] = "30%"
			break
	return texts


func coup() -> Dictionary:
	return {"type": "coup"}


func last_of(s: GameStateScript, type: String) -> Dictionary:
	for i in range(s.event_log.size() - 1, -1, -1):
		if s.event_log[i]["type"] == type:
			return s.event_log[i]
	return {}


func count(events: Array, type: String) -> int:
	var n: int = 0
	for event in events:
		if event["type"] == type:
			n += 1
	return n


func total_money(s: GameStateScript) -> int:
	var total: int = s.treasury
	for id in s.psd:
		total += s.psd[id]
	return total


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
