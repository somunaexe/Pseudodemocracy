extends SceneTree

const GameScript = preload("res://scripts/game.gd")
const GameStateScript = preload("res://scripts/game_state.gd")
const CardsScript = preload("res://scripts/cards.gd")
const CardEffectsScript = preload("res://scripts/card_effects.gd")
const CorruptionScript = preload("res://scripts/corruption.gd")
const RoundEndScript = preload("res://scripts/round_end.gd")
const RolesScript = preload("res://scripts/roles.gd")
const IncomeScript = preload("res://scripts/income.gd")
const PopularityScript = preload("res://scripts/popularity.gd")
const EliminationScript = preload("res://scripts/elimination.gd")
const SerializerScript = preload("res://scripts/serializer.gd")
const ViewsScript = preload("res://scripts/views.gd")
const PlayScript = preload("res://tests/play.gd")

const PRESIDENT = GameStateScript.LeaderType.PRESIDENT

var failures: int = 0


func _init() -> void:
	markers_and_the_third()
	what_frozen_means()
	paying_the_fine()
	waiting_it_out()
	the_box_runs_out()
	the_cards()
	the_leader_decides()
	the_leader_decides_in_a_real_turn()
	leaving_the_game()
	views_and_saves()
	print("%d failure(s)" % failures)
	quit(1 if failures > 0 else 0)


func markers_and_the_third() -> void:
	var s := new_turn()
	var paid: int = card_number("scandal", "You paid an official")
	var cash: int = s.psd[3]
	var pop: int = PopularityScript.base(s, 3)
	var ev := CardEffectsScript.apply(s, 3, "scandal", paid)
	expect("a card that says gain a corruption marker gives one", [CorruptionScript.held(s, 3), s.psd[3] - cash, types(ev)], [1, -100, ["card_applied", "marker_gained"]])
	expect("... the marker is public and logged once", [ev[1]["audience"], s.event_log.back() == ev.back(), ev[1]["markers"]], [[], true, 1])
	expect("... nobody is frozen by one", [CorruptionScript.is_frozen(s, 3), PopularityScript.base(s, 3)], [false, pop])
	CardEffectsScript.apply(s, 3, "scandal", paid)
	ev = CardEffectsScript.apply(s, 3, "scandal", paid)
	expect("the third marker freezes the player", [CorruptionScript.held(s, 3), CorruptionScript.is_frozen(s, 3), types(ev)], [3, true, ["card_applied", "marker_gained", "player_frozen"]])
	expect("... they lose 30 popularity, remembered", [PopularityScript.base(s, 3) - pop, s.frozen[3]], [-30, {"left": 3, "drop": 30, "since": 1}])
	expect("... and the freeze says for how long", [ev[2]["rounds"], ev[2]["popularity_lost"]], [3, 30])

	# The popularity that was really lost is what comes back, not the 30.
	s = new_turn()
	PopularityScript.change_base(s, 3, -40)   # base is now 40 below the start; the track stops at the bottom
	var low: int = PopularityScript.base(s, 3)
	s.markers[3] = 2
	CorruptionScript.give(s, 3)
	expect("the drop is only what the track allowed", s.frozen[3]["drop"], low - PopularityScript.base(s, 3))


func what_frozen_means() -> void:
	var s := new_turn()
	RolesScript.grant(s, 3, "Doctor")
	var before: int = IncomeScript.gross(s, 3)
	freeze(s, 3)
	expect("a frozen player's role pays nothing", [before, IncomeScript.gross(s, 3)], [70, 0])
	freeze(s, 2)
	expect("... the Leader's own pay stays when the Leader is frozen", IncomeScript.gross(s, 2), 100)
	expect("... roles can't be used", RolesScript.can_use_pledge(s, 3, "Doctor"), "Your roles are frozen by corruption.")
	expect("... they keep the cards", RolesScript.held(s, 3), ["Doctor"])
	expect("... no coup", send(s, 3, {"type": "coup"})[0]["reason"], "Your roles are frozen by corruption, so you have no coup card.")
	expect("... no more markers", [types(CorruptionScript.give(s, 3)), CorruptionScript.held(s, 3)], [["marker_refused"], 3])

	# No Settlement card for a frozen performer: the vote still counts.
	s = new_turn()
	freeze(s, 2)
	var pop: int = PopularityScript.base(s, 2)
	s.decks["settlement"] = [5]
	send(s, 2, {"type": "finish_performance"})
	var ev: Array = []
	for id in [1, 3, 4, 5]:
		ev.append_array(send(s, id, {"type": "performance_vote", "good": true}))
	var resolved: Dictionary = last_of(s, "performance_resolved")
	expect("a frozen performer wins the vote but draws no Settlement card", [resolved["outcome"], resolved.get("card", -1), resolved["frozen"], count(ev, "card_applied"), s.decks["settlement"]], ["good", -1, true, 0, [5]])
	expect("... the popularity still moves", PopularityScript.base(s, 2) > pop, true)
	s = new_turn()
	freeze(s, 2)
	s.decks["scandal"] = [5]
	send(s, 2, {"type": "finish_performance"})
	for id in [1, 3, 4, 5]:
		send(s, id, {"type": "performance_vote", "good": false})
	expect("... a bad vote still draws a Scandal card", last_of(s, "performance_resolved").get("deck", ""), "scandal")


func paying_the_fine() -> void:
	var s := new_turn()
	RolesScript.grant(s, 3, "Doctor")
	expect("someone not frozen can't pay", send(s, 3, {"type": "pay_fine"})[0]["reason"], "You are not frozen.")
	freeze(s, 3)
	var pop: int = PopularityScript.base(s, 3)
	s.treasury += s.psd[3] - 150
	s.psd[3] = 150
	expect("the fine is 200 from cash: 150 is not enough", send(s, 3, {"type": "pay_fine"})[0]["reason"], "The fine is 200 PSD, from cash.")
	s.treasury -= 100
	s.psd[3] += 100
	var treasury: int = s.treasury
	var ev := send(s, 3, {"type": "pay_fine"})
	expect("paying lifts the freeze", [types(ev), CorruptionScript.is_frozen(s, 3), CorruptionScript.held(s, 3)], [["fine_paid"], false, 0])
	expect("... 200 PSD to the treasury, the popularity comes back, the roles with it", [s.treasury - treasury, s.psd[3], PopularityScript.base(s, 3) - pop, RolesScript.can_use_pledge(s, 3, "Doctor")], [200, 50, 30, ""])
	expect("... and it can't be paid twice", send(s, 3, {"type": "pay_fine"})[0]["reason"], "You are not frozen.")
	expect("the markers went back: the player can collect three more", [CorruptionScript.supply(s), types(CorruptionScript.give(s, 3))], [15, ["marker_gained"]])


func waiting_it_out() -> void:
	var s := new_turn()
	RolesScript.grant(s, 3, "Doctor")
	RolesScript.grant(s, 3, "Lawyer")
	freeze(s, 3)
	var pop: int = PopularityScript.base(s, 3)
	var ev: Array = RoundEndScript.run(s)
	expect("the round it began in doesn't count: 3 rounds means 3 further rounds", [s.frozen[3]["left"], count(ev, "freeze_expired")], [3, 0])
	s.current_round += 1
	ev = RoundEndScript.run(s)
	expect("one round passes: still frozen", [s.frozen[3]["left"], count(ev, "freeze_expired")], [2, 0])
	RoundEndScript.run(s)
	expect("two rounds: still frozen", s.frozen[3]["left"], 1)
	ev = RoundEndScript.run(s)
	expect("three rounds: the freeze ends", [CorruptionScript.is_frozen(s, 3), CorruptionScript.held(s, 3), count(ev, "freeze_expired")], [false, 0, 1])
	expect("... the roles are gone for good, cards back in the box", [RolesScript.held(s, 3), RolesScript.card_of(s, 3, "Doctor"), RolesScript.copies_left(s, "Doctor")], [[], -1, 5])
	expect("... the popularity drop stays", PopularityScript.base(s, 3), pop)
	expect("... and the event says which roles went", ev.filter(func(e): return e["type"] == "freeze_expired")[0]["roles_lost"], ["Doctor", "Lawyer"])


func the_box_runs_out() -> void:
	var s := new_turn()
	s.markers = {1: 2, 2: 2, 3: 2, 4: 2, 5: 2, 99: 5}
	expect("with no markers left in the box none is given", [CorruptionScript.supply(s), types(CorruptionScript.give(s, 3)), CorruptionScript.held(s, 3)], [0, ["marker_refused"], 2])
	s.markers.erase(99)
	expect("... with one left, one is", [CorruptionScript.supply(s), CorruptionScript.give(s, 3).size() > 1], [5, true])
	expect("an eliminated player is given none", CorruptionScript.give(s, 7), [])


func the_cards() -> void:
	# "Your appointee turns out to be under investigation": you and whoever you choose.
	var s := new_turn()
	var appointee: int = card_number("scandal", "Your appointee turns out")
	CardEffectsScript.apply(s, 3, "scandal", appointee)
	expect("the drawer has their marker at once, and a player is asked for", [CorruptionScript.held(s, 3), s.choice["kind"], s.choice["player"]], [1, "player", 3])
	send(s, 3, {"type": "choose", "choice": 4})
	expect("the player they pick gets one too", [CorruptionScript.held(s, 3), CorruptionScript.held(s, 4), CorruptionScript.held(s, 1)], [1, 1, 0])

	# "Choose a player: they collect 70 PSD from you and gain a marker."
	s = new_turn()
	var comp: int = card_number("scandal", "Choose a player — they collect 70")
	var mine: int = s.psd[2]
	var theirs: int = s.psd[4]
	CardEffectsScript.apply(s, 2, "scandal", comp)
	var ev := send(s, 2, {"type": "choose", "choice": 4})
	expect("the chosen player is paid 70 by the drawer and gets the marker", [s.psd[2] - mine, s.psd[4] - theirs, CorruptionScript.held(s, 4), CorruptionScript.held(s, 2)], [-70, 70, 1, 0])
	expect("... the event says what was paid", ev[0]["paid_to_chosen"], 70)
	s = new_turn()
	s.treasury += s.psd[2] - 30
	s.psd[2] = 30
	var total: int = s.treasury
	for id in s.player_ids:
		total += s.psd[id]
	CardEffectsScript.apply(s, 2, "scandal", comp)
	ev = send(s, 2, {"type": "choose", "choice": 4})
	var after: int = s.treasury
	for id in s.player_ids:
		after += s.psd[id]
	expect("a drawer who can't pay it all pays what they have, the rest is debt to the chosen player", [ev[0]["paid_to_chosen"], ev[0]["new_debt"], s.psd[2], s.debts.get(2, []).size()], [30, 40, 0, 1])
	expect("... money is conserved", after, total)

	# The Settlement card with a loss of popularity and a marker.
	s = new_turn()
	var sold: int = card_number("settlement", "You quietly sold some government equipment")
	var cash: int = s.psd[3]
	var p: int = PopularityScript.effective(s, 3)
	CardEffectsScript.apply(s, 3, "settlement", sold)
	expect("selling equipment pays 90, costs 5 popularity and gives a marker", [s.psd[3] - cash, PopularityScript.effective(s, 3) - p, CorruptionScript.held(s, 3)], [90, -5, 1])


func the_leader_decides() -> void:
	var emb: int = card_number("scandal", "You embezzled funds")
	var deck: String = "scandal"
	var s := new_turn()
	var cash: int = s.psd[3]
	CardEffectsScript.apply(s, 3, deck, emb)
	expect("an embezzler collects 200 and the Leader is asked, not them", [s.psd[3] - cash, s.choice["player"], s.choice["subject"], s.choice["labels"]], [200, 2, 3, ["Stay quiet", "Split the money", "Expose them"]])
	expect("... the embezzler can't answer for the Leader", send(s, 3, {"type": "choose", "choice": 0})[0]["reason"], "It isn't your choice.")
	var ev := send(s, 2, {"type": "choose", "choice": 0})
	expect("staying quiet changes nothing", [s.psd[3] - cash, CorruptionScript.held(s, 3), ev[0]["player"], ev[0]["subject"]], [200, 0, 2, 3])

	s = new_turn()
	cash = s.psd[3]
	var leader: int = s.psd[2]
	CardEffectsScript.apply(s, 3, deck, emb)
	ev = send(s, 2, {"type": "choose", "choice": 1})
	expect("splitting gives the Leader half", [s.psd[3] - cash, s.psd[2] - leader, ev[0]["shared"], CorruptionScript.held(s, 3)], [100, 100, 100, 0])

	s = new_turn()
	cash = s.psd[3]
	CardEffectsScript.apply(s, 3, deck, emb)
	ev = send(s, 2, {"type": "choose", "choice": 2})
	expect("exposing them gives the embezzler a marker, and they keep the money", [s.psd[3] - cash, CorruptionScript.held(s, 3), types(ev)], [200, 1, ["choice_made", "marker_gained"]])

	# The Leader embezzling is nobody else's business.
	s = new_turn()
	cash = s.psd[2]
	var out := CardEffectsScript.apply(s, 2, deck, emb)
	expect("a Leader who embezzles keeps it all, with no choice", [s.psd[2] - cash, s.choice.is_empty(), types(out)], [200, true, ["card_applied", "choice_unavailable"]])

	# Too slow: the server chooses for the Leader, at random.
	s = new_turn()
	CardEffectsScript.apply(s, 3, deck, emb)
	var ticked := GameScript.tick(s, int(s.choice["deadline"]))
	expect("if the Leader says nothing the server chooses for them", [last_of(s, "choice_made")["auto"], last_of(s, "choice_made")["player"], s.choice.is_empty()], [true, 2, true])


func the_leader_decides_in_a_real_turn() -> void:
	var emb: int = card_number("scandal", "You embezzled funds")
	var s := new_turn()
	PlayScript.take_turn(s, 2)
	expect("it is player 3's turn", s.term["waiting"][0], 3)
	s.decks["scandal"] = [emb]
	send(s, 3, {"type": "finish_performance"})
	for id in [1, 2, 4, 5]:
		send(s, id, {"type": "performance_vote", "good": false})
	expect("the Leader's choice is waiting on player 3's card", [s.choice.get("player", -1), s.choice.get("subject", -1)], [2, 3])
	expect("... the embezzler's turn can't end until the Leader has chosen", send(s, 3, {"type": "end_turn"})[0]["reason"], "Make your choice first.")
	send(s, 2, {"type": "choose", "choice": 0})
	expect("... then it can", types(send(s, 3, {"type": "end_turn"}))[0], "turn_ended")


func leaving_the_game() -> void:
	var s := new_turn()
	freeze(s, 3)
	s.markers[4] = 1
	EliminationScript.eliminate(s, 3, "debt")
	expect("an eliminated player's markers go back in the box and their freeze ends", [CorruptionScript.supply(s), s.frozen.has(3), s.markers.has(3)], [14, false, false])


func views_and_saves() -> void:
	var s := new_turn()
	freeze(s, 3)
	s.markers[4] = 2
	var seen: Dictionary = ViewsScript.state_view(s, 1)
	expect("everyone sees the markers and who is frozen", [seen["markers"], seen["frozen"].keys()], [{3: 3, 4: 2}, [3]])
	var errors: Array = []
	var restored: GameStateScript = SerializerScript.state_from_json(SerializerScript.state_to_json(s), errors)
	expect("a saved game keeps them", [errors, restored.markers, restored.frozen], [[], {3: 3, 4: 2}, {3: {"left": 3, "drop": 30, "since": 1}}])


# --- helpers -----------------------------------------------------------------------------

# The player is frozen as if by three markers. Returns 0 so it can be used in an expression.
func freeze(s: GameStateScript, id: int) -> int:
	for i in 3:
		CorruptionScript.give(s, id)
	return 0


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
			s.decks["performance"] = [20, 20, 20, 20, 20, 20, 20, 20, 20, 20, 20, 20]   # plain performance cards: nothing asks a question
			GameScript.handle(s, 2, {"type": "pass_window"})
			return s
	assert(false, "no seed gave a President")
	return null


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
