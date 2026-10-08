extends SceneTree

const GameScript = preload("res://scripts/game.gd")
const RolesScript = preload("res://scripts/roles.gd")
const PopularityScript = preload("res://scripts/popularity.gd")
const SerializerScript = preload("res://scripts/serializer.gd")
const ViewsScript = preload("res://scripts/views.gd")
const GameStateScript = preload("res://scripts/game_state.gd")

const PRESIDENT = GameStateScript.LeaderType.PRESIDENT
const SWING := 6
# The Settlement cards that ask for a choice, by their number in the deck.
const SPEECH := 22   # gain 15 popularity or 70 PSD
const TALENTS := 23  # choose any role
const PRAISE := 30   # a player praises you (+5 popularity), you gain the Lawyer role
const SWAP := 36     # swap roles with a player who has a role (they lose 5 popularity)

var failures: int = 0


func _init() -> void:
	an_option()
	a_role()
	a_player_to_praise_you()
	a_swap()
	nothing_to_choose_from()
	who_may_choose()
	logging_views_and_saves()
	running_out_of_time()
	print("%d failure(s)" % failures)
	quit(1 if failures > 0 else 0)


func an_option() -> void:
	var s := win_with(SPEECH)
	var needed: Dictionary = last_of(s, "choice_needed")
	expect("a card that asks tells everyone what", [needed["player"], needed["kind"], needed["labels"]], [2, "option", ["Gain 15 popularity", "Gain 70 PSD"]])
	expect("... and the turn waits: it can't end", send(s, 2, {"type": "end_turn"})[0]["reason"], "Make your choice first.")
	for bad in [null, "1", true, 1.5, -1, 2, [1], {"a": 1}]:
		expect("option answer %s is refused" % str(bad), send(s, 2, {"type": "choose", "choice": bad})[0]["reason"], "Choose one of the 2 options by its number.")
	expect("... and the choice is still waiting", not s.choice.is_empty(), true)
	expect("a missing answer is refused too", send(s, 2, {"type": "choose"})[0]["type"], "rejected")

	var cash: int = s.psd[2]
	var treasury: int = s.treasury
	var ev := send(s, 2, {"type": "choose", "choice": 1})
	expect("the chosen option is applied: 70 PSD from the treasury", [types(ev), s.psd[2] - cash, treasury - s.treasury], [["choice_made"], 70, 70])
	expect("... the event says what was chosen and what happened", [ev[0]["kind"], ev[0]["choice"], ev[0]["psd"]], ["option", 1, 70])
	expect("... the choice is gone and the turn can end", [not s.choice.is_empty(), types(send(s, 2, {"type": "end_turn"}))[0]], [false, "turn_ended"])

	s = win_with(SPEECH)
	var pop: int = PopularityScript.effective(s, 2)
	cash = s.psd[2]
	send(s, 2, {"type": "choose", "choice": 0})
	expect("the other option is 15 popularity and no money", [PopularityScript.effective(s, 2) - pop, s.psd[2] - cash], [15, 0])
	expect("a choice can't be made twice", send(s, 2, {"type": "choose", "choice": 0})[0]["reason"], "There is nothing to choose.")


func a_role() -> void:
	var s := win_with(TALENTS)
	var needed: Dictionary = last_of(s, "choice_needed")
	expect("a role choice offers all five roles to a Civilian", needed["candidates"], ["Doctor", "Lawyer", "Secret Agent", "Activist", "Agbero"])
	for bad in [null, 3, "Banker", "doctor", ["Doctor"], true]:
		expect("role answer %s is refused" % str(bad), send(s, 2, {"type": "choose", "choice": bad})[0]["type"], "rejected")
	var ev := send(s, 2, {"type": "choose", "choice": "Secret Agent"})
	expect("the player gains the role they chose", [types(ev), RolesScript.held(s, 2)], [["choice_made", "role_gained"], ["Secret Agent"]])
	expect("... which now earns income", s.roles[2], ["Secret Agent"])

	# A role they already hold isn't offered.
	s = new_turn()
	RolesScript.grant(s, 2, "Doctor")
	RolesScript.grant(s, 2, "Lawyer")
	win(s, TALENTS)
	expect("roles already held are not offered", last_of(s, "choice_needed")["candidates"], ["Secret Agent", "Activist", "Agbero"])
	expect("... and can't be chosen", send(s, 2, {"type": "choose", "choice": "Doctor"})[0]["type"], "rejected")


func a_player_to_praise_you() -> void:
	var s := win_with(PRAISE)
	expect("any other player in the game may be chosen", last_of(s, "choice_needed")["candidates"], [1, 3, 4, 5])
	var pop3: int = PopularityScript.effective(s, 3)
	var pop2: int = PopularityScript.effective(s, 2)
	var ev := send(s, 2, {"type": "choose", "choice": 3})
	expect("the chosen player gains 5 popularity", [PopularityScript.effective(s, 3) - pop3, ev[0]["target_popularity"]], [5, 5])
	expect("... and the drawer gains the Lawyer role", [types(ev), RolesScript.held(s, 2), PopularityScript.effective(s, 2) - pop2], [["choice_made", "role_gained"], ["Lawyer"], 0])

	# The Lawyer role the drawer already holds is skipped, not an error.
	s = new_turn()
	RolesScript.grant(s, 2, "Lawyer")
	win(s, PRAISE)
	ev = send(s, 2, {"type": "choose", "choice": 4})
	expect("a Lawyer who is already a Lawyer: the rest still happens, and the skip is said", [types(ev), ev[0]["skipped"], ev[0]["target_popularity"]], [["choice_made"], ["gain Lawyer: They already hold that role."], 5])

	# Who can't be chosen.
	for bad in [2, 0, 9, "3", 3.5, [3], null, true]:
		s = win_with(PRAISE)
		expect("player answer %s is refused" % str(bad), send(s, 2, {"type": "choose", "choice": bad})[0]["reason"], "Choose one of the players offered.")
	s = new_turn()
	s.eliminated[4] = true
	win(s, PRAISE)
	expect("an eliminated player isn't offered", last_of(s, "choice_needed")["candidates"], [1, 3, 5])
	expect("... and can't be chosen", send(s, 2, {"type": "choose", "choice": 4})[0]["type"], "rejected")


func a_swap() -> void:
	var s := new_turn()
	RolesScript.grant(s, 2, "Secret Agent")
	RolesScript.grant(s, 3, "Doctor")
	RolesScript.grant(s, 4, "Agbero")
	RolesScript.grant(s, 4, "Lawyer")
	win(s, SWAP)
	expect("only players who hold a role are offered", last_of(s, "choice_needed")["candidates"], [3, 4])
	expect("a Civilian can't be chosen", send(s, 2, {"type": "choose", "choice": 1})[0]["type"], "rejected")
	var pop4: int = PopularityScript.effective(s, 4)
	var total: int = total_money(s)
	var ev := send(s, 2, {"type": "choose", "choice": 4})
	expect("they swap everything they hold", [RolesScript.held(s, 2), RolesScript.held(s, 4)], [["Agbero", "Lawyer"], ["Secret Agent"]])
	expect("... the chosen player loses 5 popularity", [PopularityScript.effective(s, 4) - pop4, ev[0]["target_popularity"]], [-5, -5])
	expect("... the events are the choice and the swap", types(ev), ["choice_made", "roles_swapped"])
	expect("... and no money moved", total_money(s), total)


func nothing_to_choose_from() -> void:
	var s := new_turn()
	for role in RolesScript.names():
		RolesScript.grant(s, 2, role)
	win(s, TALENTS)
	expect("a player who holds every role has nothing to choose: said so, and not stuck", [types(s.event_log.slice(-3)).has("choice_unavailable"), not s.choice.is_empty()], [true, false])
	expect("... so the turn can end", types(send(s, 2, {"type": "end_turn"}))[0], "turn_ended")

	s = new_turn()
	win(s, SWAP)
	expect("a swap with nobody holding a role is unavailable too", [last_of(s, "choice_unavailable")["kind"], not s.choice.is_empty()], ["player", false])


func who_may_choose() -> void:
	var s := win_with(SPEECH)
	expect("only the player who drew the card chooses", send(s, 3, {"type": "choose", "choice": 0})[0]["reason"], "It isn't your choice.")
	expect("... not the server", send(s, 0, {"type": "choose", "choice": 0})[0]["reason"], "It isn't your choice.")
	expect("nothing changed", not s.choice.is_empty(), true)
	s = new_turn()
	expect("with nothing pending there is nothing to choose", send(s, 2, {"type": "choose", "choice": 0})[0]["reason"], "There is nothing to choose.")
	s = GameScript.new_game([1, 2, 3], 5)
	expect("a choice can be made at any time, so outside a turn there is just nothing to choose", send(s, 1, {"type": "choose", "choice": 0})[0]["reason"], "There is nothing to choose.")


func logging_views_and_saves() -> void:
	var s := win_with(PRAISE)
	var view: Dictionary = ViewsScript.state_view(s, 4)
	expect("everyone can see a choice that is waiting", [view["choice"]["player"], view["choice"]["kind"]], [2, "player"])
	var errors: Array = []
	var restored: GameStateScript = SerializerScript.state_from_json(SerializerScript.state_to_json(s), errors)
	expect("a game saved while a choice waits loads without errors", errors, [])
	for g in [s, restored]:
		send(g, 2, {"type": "choose", "choice": 3})
		send(g, 2, {"type": "end_turn"})
	expect("... and carries on exactly as the original does", SerializerScript.state_to_json(s) == SerializerScript.state_to_json(restored), true)
	expect("each event was logged once", [count(s.event_log, "choice_made"), count(s.event_log, "role_gained"), count(s.event_log, "choice_needed")], [1, 1, 1])


func running_out_of_time() -> void:
	var s := win_with(SPEECH)
	var needed: Dictionary = last_of(s, "choice_needed")
	var deadline: int = int(s.choice["deadline"])
	expect("a choice has 10 seconds on the server clock", [needed["seconds"], needed["ends_at_ms"], deadline - s.clock_ms], [10, deadline, 10000])
	expect("before the deadline the server does nothing", [types(GameScript.tick(s, deadline - 1)), not s.choice.is_empty()], [[], true])
	expect("... and the player can still choose in the last millisecond", types(send(s, 2, {"type": "choose", "choice": 1})), ["choice_made"])
	expect("... which is their own choice, not the server's", last_of(s, "choice_made")["auto"], false)

	# Each kind of choice is made at random from the valid answers.
	var cases: Array = [SPEECH, TALENTS, PRAISE, SWAP]
	for card in cases:
		s = new_turn()
		if card == SWAP:
			RolesScript.grant(s, 3, "Doctor")
			RolesScript.grant(s, 4, "Agbero")
		win(s, card)
		var offered: Dictionary = last_of(s, "choice_needed")
		var total: int = total_money(s)
		var ev := GameScript.tick(s, int(s.choice["deadline"]))
		var made: Dictionary = last_of(s, "choice_made")
		var valid: bool = (made["choice"] in range(offered["labels"].size())) if offered["kind"] == "option" else (made["choice"] in offered["candidates"])
		expect("card %d (%s): the server chooses a valid answer when time runs out" % [card, offered["kind"]], [types(ev).has("choice_made"), made["auto"], valid], [true, true, true])
		expect("... the choice is gone, the turn can end, and the event is logged once", [not s.choice.is_empty(), count(s.event_log, "choice_made"), types(send(s, 2, {"type": "end_turn"}))[0]], [false, 1, "turn_ended"])
		expect("... and all the money is still there", total_money(s), total)
	s = win_with(SPEECH)
	GameScript.tick(s, int(s.choice["deadline"]))
	expect("it is too late to answer once the server has chosen", send(s, 2, {"type": "choose", "choice": 0})[0]["reason"], "There is nothing to choose.")

	# At random, but reproducibly: the same game chooses the same, and the choices vary.
	var picks: Dictionary = {}
	var games: int = 0
	for seed_value in range(1, 400):
		if games >= 25:
			break
		var g := GameScript.new_game([1, 2, 3, 4, 5], seed_value)
		for id in [1, 2, 3, 4, 5]:
			GameScript.handle(g, id, {"type": "cast_vote", "candidate": 2})
		if g.leader_type != PRESIDENT:
			continue
		g.decks["performance"] = [1]   # a plain performance card, not a debate
		GameScript.handle(g, 2, {"type": "pass_window"})
		GameScript.handle(g, 2, {"type": "pass_window"})
		win(g, SPEECH)
		GameScript.tick(g, int(g.choice["deadline"]))
		picks[last_of(g, "choice_made")["choice"]] = true
	expect("across games the random choice takes both options", picks.keys().size(), 2)
	var a := win_with(TALENTS)
	var b := win_with(TALENTS)
	GameScript.tick(a, int(a.choice["deadline"]))
	GameScript.tick(b, int(b.choice["deadline"]))
	expect("the same game makes the same random choice", SerializerScript.state_to_json(a) == SerializerScript.state_to_json(b), true)

	# A game saved while the choice waits keeps its deadline.
	s = win_with(PRAISE)
	var errors: Array = []
	var restored: GameStateScript = SerializerScript.state_from_json(SerializerScript.state_to_json(s), errors)
	for g in [s, restored]:
		GameScript.tick(g, int(g.choice["deadline"]))
	expect("a restored game times out in the same way", [errors, SerializerScript.state_to_json(s) == SerializerScript.state_to_json(restored)], [[], true])


# --- helpers -----------------------------------------------------------------------------

# The performer (player 2, the Leader) has just won the vote and drawn this Settlement card.
func win_with(card: int) -> GameStateScript:
	var s := new_turn()
	win(s, card)
	return s


func win(s: GameStateScript, card: int) -> void:
	s.decks["settlement"] = [card]
	send(s, 2, {"type": "finish_performance"})
	for id in [1, 3, 4, 5]:
		send(s, id, {"type": "performance_vote", "good": true})


func new_turn() -> GameStateScript:
	for seed_value in range(1, 400):
		var s := GameScript.new_game([1, 2, 3, 4, 5], seed_value)
		for id in [1, 2, 3, 4, 5]:
			GameScript.handle(s, id, {"type": "cast_vote", "candidate": 2})
		if s.leader_type == PRESIDENT:
			s.decks["performance"] = [1]   # a plain performance card, not a debate
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
	print(("PASS " if ok else "FAIL ") + label + " -> " + str(actual).left(90))
