extends SceneTree

const GameScript = preload("res://scripts/game.gd")
const GameStateScript = preload("res://scripts/game_state.gd")
const CardsScript = preload("res://scripts/cards.gd")
const CardEffectsScript = preload("res://scripts/card_effects.gd")
const RivalsScript = preload("res://scripts/rivals.gd")
const RoundEndScript = preload("res://scripts/round_end.gd")
const RolesScript = preload("res://scripts/roles.gd")
const UnionsScript = preload("res://scripts/unions.gd")
const PopularityScript = preload("res://scripts/popularity.gd")
const EliminationScript = preload("res://scripts/elimination.gd")
const SerializerScript = preload("res://scripts/serializer.gd")
const ViewsScript = preload("res://scripts/views.gd")
const PlayScript = preload("res://tests/play.gd")

const PRESIDENT = GameStateScript.LeaderType.PRESIDENT
const CHALLENGER := 4
const LEADER := 2

var failures: int = 0


func _init() -> void:
	naming_rivals()
	a_rival_scandal()
	a_truce()
	a_peace_accord()
	losing_the_next_draw()
	a_mob_caught_on_camera()
	leaving_the_game()
	views_and_saves()
	print("%d failure(s)" % failures)
	quit(1 if failures > 0 else 0)


func naming_rivals() -> void:
	var s := new_turn()
	expect("nobody has rivals to start with", [RivalsScript.of(s, 3), RivalsScript.is_rival(s, 3, 4)], [[], false])
	expect("with no rivals a card offers every other player", RivalsScript.candidates(s, 3), [1, 2, 4, 5])
	var ev := RivalsScript.name_rival(s, 3, 4)
	expect("naming a rival is said once", [ev[0]["type"], ev[0]["owner"], ev[0]["rival"], RivalsScript.of(s, 3)], ["rival_named", 3, 4, [4]])
	expect("naming them again does nothing", RivalsScript.name_rival(s, 3, 4), [])
	expect("you can't be your own rival", RivalsScript.name_rival(s, 3, 3), [])
	expect("a rival is one-way: 4 has none", [RivalsScript.is_rival(s, 4, 3), RivalsScript.of(s, 4)], [false, []])
	expect("a card then offers only the rivals you have", RivalsScript.candidates(s, 3), [4])
	RivalsScript.name_rival(s, 3, 5)
	expect("... all of them, in the order named", RivalsScript.candidates(s, 3), [4, 5])


func a_rival_scandal() -> void:
	var card: int = card_number("settlement", "A rival's scandal breaks")
	var s := new_turn()
	var mine: int = PopularityScript.effective(s, 3)
	var theirs: int = PopularityScript.effective(s, 4)
	CardEffectsScript.apply(s, 3, "settlement", card)
	expect("the drawer is offered every other player when they have no rival", [s.choice["kind"], s.choice["candidates"]], ["player", [1, 2, 4, 5]])
	expect("... and gains 5 popularity at once", PopularityScript.effective(s, 3) - mine, 5)
	var ev := send(s, 3, {"type": "choose", "choice": 4})
	expect("the player chosen loses 15 and becomes the drawer's rival", [PopularityScript.effective(s, 4) - theirs, RivalsScript.of(s, 3), types(ev)], [-15, [4], ["choice_made", "rival_named"]])

	CardEffectsScript.apply(s, 3, "settlement", card)
	expect("with a rival, only the rival is offered", s.choice["candidates"], [4])
	expect("... a stranger to the label is refused", send(s, 3, {"type": "choose", "choice": 1})[0]["type"], "rejected")
	send(s, 3, {"type": "choose", "choice": 4})
	expect("... and the rival loses another 15", PopularityScript.effective(s, 4) - theirs, -30)
	expect("... without being named twice", RivalsScript.of(s, 3), [4])


func a_truce() -> void:
	var card: int = card_number("settlement", "You survived a vote of no confidence")
	var s := coup_ready()
	s.hands[CHALLENGER] = [{"deck": "settlement", "card": card}]
	var ev := send(s, CHALLENGER, {"type": "play_card", "index": 0})
	expect("a kept truce card asks whom", [types(ev), s.choice["player"], s.choice["candidates"]], [["card_played", "choice_needed"], CHALLENGER, [1, 2, 3, 5]])
	expect("... it needs no union", s.unions.is_empty(), true)
	ev = send(s, CHALLENGER, {"type": "choose", "choice": LEADER})
	expect("the two are in a truce and the Leader is a rival", [types(ev), RivalsScript.in_truce(s, CHALLENGER, LEADER), RivalsScript.in_truce(s, LEADER, CHALLENGER), RivalsScript.is_rival(s, CHALLENGER, LEADER)], [["choice_made", "rival_named", "truce_made"], true, true, true])
	expect("... the challenger can't coup the Leader", send(s, CHALLENGER, {"type": "coup"})[0]["reason"], "You and the Leader agreed not to coup each other this round.")
	expect("... nor deal", send(s, CHALLENGER, {"type": "coup", "deal": true})[0]["reason"], "You and the Leader agreed not to coup each other this round.")
	expect("a third player in no truce is not stopped", RivalsScript.in_truce(s, 5, LEADER), false)
	# The card isn't a union card: someone already in a union can still play it.
	var t := coup_ready()
	UnionsScript.found(t, 3, "activist")
	t.unions[1]["members"].append(CHALLENGER)
	t.hands[CHALLENGER] = [{"deck": "settlement", "card": card}]
	expect("a union member can play it too", types(send(t, CHALLENGER, {"type": "play_card", "index": 0})), ["card_played", "choice_needed"])
	RoundEndScript.run(s)
	expect("the truce ends with the round", [s.truces, types(send(s, CHALLENGER, {"type": "coup"})).has("coup_succeeded")], [[], true])


func a_peace_accord() -> void:
	var card: int = card_number("settlement", "Peace Accord")
	var s := coup_ready()
	CardEffectsScript.apply(s, 3, "settlement", card)
	var ev := send(s, 3, {"type": "choose", "choice": LEADER})
	expect("a Peace Accord with the Leader is recorded: 3 rounds, 10 popularity", [types(ev), s.accords], [["choice_made", "rival_named", "accord_made"], [{"a": 3, "b": LEADER, "left": 3, "loss": 10, "since": 1}]])
	var pop: int = PopularityScript.effective(s, 3)
	var other: int = PopularityScript.effective(s, 5)
	var coup := send(s, CHALLENGER, {"type": "coup"})
	expect("when the Leader is couped the player at peace with them loses 10", [types(coup).has("accord_penalty"), PopularityScript.effective(s, 3) - pop, PopularityScript.effective(s, 5) - other], [true, -10, 0])
	expect("... the accord carries on; the round it began in (ended by the coup) doesn't count", s.accords[0]["left"], 3)
	var ended: Array = []
	for i in 3:
		ended.append_array(RoundEndScript.run(s))
	expect("after 3 rounds it is over", [s.accords, count(ended, "accord_ended")], [[], 1])

	# Either of the two: the accord also protects the other way round.
	s = coup_ready()
	CardEffectsScript.apply(s, LEADER, "settlement", card)
	send(s, LEADER, {"type": "choose", "choice": 3})
	pop = PopularityScript.effective(s, 3)
	send(s, CHALLENGER, {"type": "coup"})
	expect("... and it works when the one who made it is the couped Leader", PopularityScript.effective(s, 3) - pop, -10)

	# A coup that fails costs nobody else anything.
	s = coup_ready()
	s.popularity[CHALLENGER] = 0
	CardEffectsScript.apply(s, 3, "settlement", card)
	send(s, 3, {"type": "choose", "choice": LEADER})
	pop = PopularityScript.effective(s, 3)
	send(s, CHALLENGER, {"type": "coup"})
	expect("a failed coup costs the partner nothing", PopularityScript.effective(s, 3) - pop, 0)


func losing_the_next_draw() -> void:
	var card: int = card_number("settlement", "Choose a Rival")
	var s := new_turn()
	CardEffectsScript.apply(s, 3, "settlement", card)
	var ev := send(s, 3, {"type": "choose", "choice": 2})
	expect("the chosen player will lose their next draw", [types(ev), s.skip_draw], [["choice_made", "rival_named", "draw_skipped_next"], {2: true}])
	var deck_before: Array = s.decks.get("settlement", []).duplicate()
	s.decks["settlement"] = [5]
	send(s, 2, {"type": "finish_performance"})
	var votes: Array = []
	for id in [1, 3, 4, 5]:
		votes.append_array(send(s, id, {"type": "performance_vote", "good": true}))
	var resolved: Dictionary = last_of(s, "performance_resolved")
	expect("they still perform and win the vote, but no card is drawn", [resolved["outcome"], resolved.get("card", -1), resolved["draw_skipped"], count(votes, "card_applied")], ["good", -1, true, 0])
	expect("... the draw pile is untouched and the penalty is used up", [s.decks["settlement"], s.skip_draw], [[5], {}])
	PlayScript.take_turn(s, 2)
	send(s, 3, {"type": "finish_performance"})
	for id in [1, 2, 4, 5]:
		send(s, id, {"type": "performance_vote", "good": true})
	expect("other players' draws are not affected", last_of(s, "performance_resolved").has("card"), true)

	# A tie draws nothing, so the penalty waits.
	s = new_turn()
	s.skip_draw[2] = true
	PlayScript.take_turn(s, 2)
	expect("a performance with no card to draw keeps the penalty", s.skip_draw, {2: true})


func a_mob_caught_on_camera() -> void:
	var card: int = card_number("scandal", "Your mob got caught on camera")
	var s := new_turn()
	UnionsScript.found(s, 3, "agbero")
	s.unions[1]["members"] = [3, 4, 5]
	var ev := CardEffectsScript.apply(s, 3, "scandal", card)
	expect("the mob disperses and its other members become the drawer's rivals", [s.unions.is_empty(), RivalsScript.of(s, 3), types(ev)], [true, [4, 5], ["card_applied", "union_dispersed", "rival_named", "rival_named"]])
	expect("... the drawer's own mates can re-form (an Agbero card, as for any dispersed mob)", s.reform.has(3), false)

	# A member (not the Capon) who draws it is the one who disbands it, as the card says.
	s = new_turn()
	UnionsScript.found(s, 3, "activist")
	s.unions[1]["members"] = [3, 4, 5]
	CardEffectsScript.apply(s, 4, "scandal", card)
	expect("any member who draws it disperses the union; the rest, the Unionizer included, are their rivals", [s.unions.is_empty(), RivalsScript.of(s, 4)], [true, [3, 5]])

	s = new_turn()
	ev = CardEffectsScript.apply(s, 3, "scandal", card)
	expect("someone in no union is not affected", [types(ev), s.rivals], [["card_applied"], {}])


func leaving_the_game() -> void:
	var s := new_turn()
	RivalsScript.name_rival(s, 3, 4)
	RivalsScript.name_rival(s, 4, 3)
	RivalsScript.name_rival(s, 5, 4)
	RivalsScript.truce(s, 3, 4)
	RivalsScript.accord(s, 4, 5, 3, 10)
	RivalsScript.accord(s, 1, 5, 3, 10)
	s.skip_draw[4] = true
	EliminationScript.eliminate(s, 4, "debt")
	expect("an eliminated player is no one's rival, and has none", [s.rivals, s.truces, s.accords.size(), s.skip_draw], [{}, [], 1, {}])


func views_and_saves() -> void:
	var s := new_turn()
	RivalsScript.name_rival(s, 3, 4)
	RivalsScript.truce(s, 3, 4)
	RivalsScript.accord(s, 3, 5, 2, 10)
	s.skip_draw[1] = true
	var seen: Dictionary = ViewsScript.state_view(s, 5)
	expect("everyone sees the rivals, truces, accords and lost draws", [seen["rivals"], seen["truces"], seen["accords"].size(), seen["skip_draw"]], [{3: [4]}, [[3, 4]], 1, {1: true}])
	var errors: Array = []
	var restored: GameStateScript = SerializerScript.state_from_json(SerializerScript.state_to_json(s), errors)
	expect("a saved game keeps them", [errors, restored.rivals, restored.truces, restored.accords, restored.skip_draw], [[], {3: [4]}, [[3, 4]], s.accords, {1: true}])


# --- helpers -----------------------------------------------------------------------------

func coup_ready() -> GameStateScript:
	var s := new_turn()
	for role in RolesScript.names():
		if RolesScript.has(s, CHALLENGER, role):
			continue
		RolesScript.grant(s, CHALLENGER, role)
		if RolesScript.has_sticker(s, CHALLENGER, role):
			break
		RolesScript.remove(s, CHALLENGER, role)
	s.popularity[CHALLENGER] = 30
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
