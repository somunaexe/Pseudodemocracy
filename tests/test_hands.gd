extends SceneTree

const GameScript = preload("res://scripts/game.gd")
const CardEffectsScript = preload("res://scripts/card_effects.gd")
const UnionsScript = preload("res://scripts/unions.gd")
const ElimScript = preload("res://scripts/elimination.gd")
const ViewsScript = preload("res://scripts/views.gd")
const SerializerScript = preload("res://scripts/serializer.gd")
const GameStateScript = preload("res://scripts/game_state.gd")
const PlayScript = preload("res://tests/play.gd")

const PRESIDENT = GameStateScript.LeaderType.PRESIDENT
const ACTIVIST_CARD := 7
const AGBERO_CARD := 8
const EITHER_CARD := 9
const ACTIVIST = GameStateScript.UnionType.ACTIVIST
const AGBERO = GameStateScript.UnionType.AGBERO

var failures: int = 0


func _init() -> void:
	keeping()
	playing_a_fixed_card()
	playing_the_either_card()
	the_card_stays_when_it_cannot_be_played()
	the_choice_is_global()
	hands_in_views_and_saves()
	print("%d failure(s)" % failures)
	quit(1 if failures > 0 else 0)


func keeping() -> void:
	var s := new_turn()
	win(s, ACTIVIST_CARD)
	var kept := last_of(s, "card_applied")
	expect("a union card is kept, not applied", [kept["kept"], kept["by_table"]], [true, false])
	expect("... it goes into the hand and nothing else happens", [s.hands[2], s.choice, s.unions], [[{"deck": "settlement", "card": ACTIVIST_CARD}], {}, {}])
	expect("... and the turn can end, as there is no choice", types(send(s, 2, {"type": "end_turn"}))[0], "turn_ended")

	s = new_turn()
	win(s, ACTIVIST_CARD)
	s.decks["settlement"] = [AGBERO_CARD]
	s.term["act"]["phase"] = GameStateScript.ActPhase.DONE
	CardEffectsScript.apply(s, 2, "settlement", AGBERO_CARD)
	expect("a second kept card joins the first, in order", s.hands[2].map(func(c): return c["card"]), [ACTIVIST_CARD, AGBERO_CARD])


func playing_a_fixed_card() -> void:
	var s := hand_of(3, [ACTIVIST_CARD])
	var ev := send(s, 3, play(0))
	expect("playing an Activist card founds an Activist union", [types(ev), s.unions[1]["type"], s.unions[1]["owner"], s.unions[1]["members"]], [["card_played", "union_founded"], ACTIVIST, 3, [3]])
	expect("... the player is its Unionizer and only member, and it is not yet confronting", s.unions[1]["confront_used"], false)
	expect("... the card has left the hand, and the empty hand is gone", [s.hands.has(3), ev[1]["unionizer"], ev[1]["union_id"], ev[1]["audience"]], [false, 3, 1, []])
	expect("... both events were logged once", [count(s.event_log, "card_played"), count(s.event_log, "union_founded")], [1, 1])

	s = hand_of(3, [AGBERO_CARD])
	send(s, 3, play(0))
	expect("an Agbero card founds a mob", [s.unions[1]["type"], s.unions[1]["owner"]], [AGBERO, 3])

	s = hand_of(3, [ACTIVIST_CARD, AGBERO_CARD])
	send(s, 3, play(1))
	expect("any card in the hand can be played, and the others stay", [s.unions[1]["type"], s.hands[3].map(func(c): return c["card"])], [AGBERO, [ACTIVIST_CARD]])
	s.unions[1]["members"] = [3]
	var other := hand_of(4, [ACTIVIST_CARD])
	other.unions = s.unions.duplicate(true)
	send(other, 4, play(0))
	expect("union ids don't clash: the next is 2", other.unions.keys().size(), 2)

	for bad in [null, "0", true, 0.0, 1.5, -1, 1, 99]:
		s = hand_of(3, [ACTIVIST_CARD])
		expect("card number %s is refused" % str(bad), send(s, 3, {"type": "play_card", "index": bad})[0]["reason"], "Choose a card in your hand by its number.")
	s = new_turn()
	expect("a player with no cards can't play one", send(s, 3, play(0))[0]["reason"], "Choose a card in your hand by its number.")
	s = hand_of(3, [ACTIVIST_CARD])
	expect("a stranger can't play", send(s, 9, play(0))[0]["reason"], "You are not in the game.")
	s.eliminated[3] = true
	expect("an eliminated player can't", send(s, 3, play(0))[0]["reason"], "You are not in the game.")


func playing_the_either_card() -> void:
	var s := hand_of(3, [EITHER_CARD])
	var ev := send(s, 3, play(0))
	expect("the either card asks which kind", [types(ev), s.choice["kind"], s.choice["labels"]], [["card_played", "choice_needed"], "option", ["Found an Activist union", "Found an Agbero mob"]])
	expect("... and no union exists yet", s.unions, {})
	var made := send(s, 3, {"type": "choose", "choice": 1})
	expect("choosing the second founds an Agbero mob", [types(made), s.unions[1]["type"], s.unions[1]["owner"]], [["choice_made", "union_founded"], AGBERO, 3])

	s = hand_of(3, [EITHER_CARD])
	send(s, 3, play(0))
	send(s, 3, {"type": "choose", "choice": 0})
	expect("choosing the first founds an Activist union", s.unions[1]["type"], ACTIVIST)

	# If they say nothing for 10 seconds the server chooses.
	s = hand_of(3, [EITHER_CARD])
	send(s, 3, play(0))
	var timed := GameScript.tick(s, int(s.choice["deadline"]))
	expect("a player who doesn't choose has it chosen for them, and a union is founded", [types(timed), s.unions.size(), timed[0]["auto"]], [["choice_made", "union_founded"], 1, true])

	# They joined a union meanwhile (they were recruited): the choice is skipped, not an error.
	s = hand_of(3, [EITHER_CARD])
	send(s, 3, play(0))
	s.unions[5] = {"type": ACTIVIST, "owner": 1, "members": [1, 3], "confront_used": false}
	var late := send(s, 3, {"type": "choose", "choice": 0})
	expect("if they have joined a union by then, nothing is founded and the skip is said", [types(late), late[0]["skipped"], s.unions.size()], [["choice_made"], ["found a union or mob: You are already in a union or mob."], 1])


func the_card_stays_when_it_cannot_be_played() -> void:
	var s := hand_of(3, [ACTIVIST_CARD])
	s.unions[5] = {"type": ACTIVIST, "owner": 1, "members": [1, 3], "confront_used": false}
	expect("a player already in a union can't found another", send(s, 3, play(0))[0]["reason"], "You are already in a union or mob.")
	expect("... and keeps the card", s.hands[3].size(), 1)
	s = hand_of(3, [EITHER_CARD])
	s.unions[5] = {"type": AGBERO, "owner": 3, "members": [3], "confront_used": false}
	expect("... even the either card, before it asks anything", [send(s, 3, play(0))[0]["reason"], s.choice], ["You are already in a union or mob.", {}])


func the_choice_is_global() -> void:
	# Player 3 plays a card in the middle of player 2's turn; the choice is theirs, so player 2 may still end their turn.
	var s := hand_of(3, [EITHER_CARD])
	win(s, 40)   # player 2 (the performer) gets a plain card (no choice)
	send(s, 3, play(0))
	expect("a card played during someone else's turn sets up their choice", [s.choice["player"], s.term["waiting"][0]], [3, 2])
	expect("... the performer can still end their turn", types(PlayScript.take_turn(s, 2)).has("turn_ended"), true)
	s.hands[4] = [{"deck": "settlement", "card": ACTIVIST_CARD}]
	expect("... and nobody else can play a card until it is made", send(s, 4, play(0))[0]["reason"], "Make your choice first.")
	send(s, 3, {"type": "choose", "choice": 0})
	expect("once made, others may play", types(send(s, 4, play(0))), ["card_played", "union_founded"])

	# If the chooser is the performer, their own turn waits.
	s = hand_of(2, [EITHER_CARD])
	win(s, 40)
	send(s, 2, play(0))
	expect("the player whose turn it is can't end it while their own choice waits", send(s, 2, {"type": "end_turn"})[0]["reason"], "Make your choice first.")

	# A card can be played between terms too (anytime).
	var g := GameScript.new_game([1, 2, 3, 4, 5], 5)
	g.hands[3] = [{"deck": "settlement", "card": ACTIVIST_CARD}]
	expect("kept cards can be played at any time, even during the first election", types(send(g, 3, play(0))), ["card_played", "union_founded"])


func hands_in_views_and_saves() -> void:
	var s := hand_of(3, [ACTIVIST_CARD, AGBERO_CARD])
	expect("a player sees their own cards", ViewsScript.state_view(s, 3)["my_hand"], [{"deck": "settlement", "card": ACTIVIST_CARD}, {"deck": "settlement", "card": AGBERO_CARD}])
	expect("... others see none of them, only how many", [ViewsScript.state_view(s, 4)["my_hand"], ViewsScript.state_view(s, 4)["hand_sizes"]], [[], {3: 2}])
	expect("... nor does the JSON a bystander gets name a kept card", ViewsScript.state_view_json(s, 4).contains("\"hands\""), false)
	var view: Dictionary = ViewsScript.state_view(s, 3)
	view["my_hand"].append({"deck": "x", "card": 0})
	expect("the view is a copy", s.hands[3].size(), 2)
	var errors: Array = []
	var restored: GameStateScript = SerializerScript.state_from_json(SerializerScript.state_to_json(s), errors)
	expect("a game saved with cards in a hand loads them back", [errors, restored.hands[3].size()], [[], 2])
	s.wills = {}
	ElimScript.eliminate(s, 3, "debt")
	expect("an eliminated player's kept cards are lost", s.hands.has(3), false)


# --- helpers -----------------------------------------------------------------------------

func play(index: int) -> Dictionary:
	return {"type": "play_card", "index": index}


# The performer (player 2) has won the vote and drawn this Settlement card.
func win(s: GameStateScript, card: int) -> void:
	s.decks["settlement"] = [card]
	send(s, 2, {"type": "finish_performance"})
	for id in [1, 3, 4, 5]:
		send(s, id, {"type": "performance_vote", "good": true})


# A running term, with this player holding these Settlement cards.
func hand_of(player: int, cards: Array) -> GameStateScript:
	var s := new_turn()
	s.hands[player] = cards.map(func(c): return {"deck": "settlement", "card": c})
	return s


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
