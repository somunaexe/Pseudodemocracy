extends SceneTree

const GameScript = preload("res://scripts/game.gd")
const GendersScript = preload("res://scripts/genders.gd")
const CardEffectsScript = preload("res://scripts/card_effects.gd")
const CardsScript = preload("res://scripts/cards.gd")
const DebtScript = preload("res://scripts/debt.gd")
const ViewsScript = preload("res://scripts/views.gd")
const SerializerScript = preload("res://scripts/serializer.gd")
const GameStateScript = preload("res://scripts/game_state.gd")

const PRESIDENT = GameStateScript.LeaderType.PRESIDENT
const MARKET_WOMEN := 0   # Settlement: collect 5 PSD from every woman at the table

var failures: int = 0


func _init() -> void:
	the_options()
	entering_it_in_the_lobby()
	saying_it_before_the_game()
	it_is_fixed_once_the_game_begins()
	the_market_women_card()
	views_and_saves()
	print("%d failure(s)" % failures)
	quit(1 if failures > 0 else 0)


func the_options() -> void:
	expect("there are three options", GendersScript.names(), ["female", "male", "other"])
	var s := GameScript.new_game([1, 2, 3], 5)
	expect("a new game has nobody's gender", [s.genders, GendersScript.of(s, 1), GendersScript.players(s, "female")], [{}, "", []])


func entering_it_in_the_lobby() -> void:
	var s := GameScript.new_game([1, 2, 3, 4], 5, {1: "female", 2: "male", 4: "other"})
	expect("genders can be given to a new game", [s.genders, GendersScript.of(s, 3)], [{1: "female", 2: "male", 4: "other"}, ""])
	expect("players of a gender, in seat order", [GendersScript.players(s, "female"), GendersScript.players(s, "male"), GendersScript.players(s, "other")], [[1], [2], [4]])
	s.eliminated[1] = true
	expect("eliminated players are not counted", GendersScript.players(s, "female"), [])


func saying_it_before_the_game() -> void:
	var s := GameScript.new_game([1, 2, 3, 4, 5], 5)
	var ev := send(s, 3, {"type": "set_gender", "gender": "female"})
	expect("a player says their gender in the lobby", [types(ev), s.genders[3], ev[0]["audience"]], [["gender_set"], "female", []])
	expect("... and can change their mind until the game begins", [types(send(s, 3, {"type": "set_gender", "gender": "male"})), s.genders[3]], [["gender_set"], "male"])
	expect("... each time it is logged", count(s.event_log, "gender_set"), 2)
	for bad in [null, "Female", "man", 1, true, ["male"]]:
		expect("gender %s is refused" % str(bad), send(s, 3, {"type": "set_gender", "gender": bad})[0]["reason"], "Choose one of: female, male, other.")
	expect("a stranger can't say one", send(s, 9, {"type": "set_gender", "gender": "male"})[0]["reason"], "You are not in the game.")
	expect("nothing was changed by the refusals", s.genders, {3: "male"})


func it_is_fixed_once_the_game_begins() -> void:
	var s := new_turn()
	expect("once the first Leader is installed it is fixed", send(s, 3, {"type": "set_gender", "gender": "female"})[0]["reason"], "Gender is fixed once the game has begun.")
	var g := GameScript.new_game([1, 2, 3, 4, 5], 5)
	for id in [1, 2, 3, 4, 5]:
		send(g, id, {"type": "cast_vote", "candidate": 2})
	expect("... as soon as the vote has chosen them", GendersScript.can_change(g), false)
	# A later election (a vacancy) doesn't reopen it.
	s = new_turn()
	preload("res://scripts/elimination.gd").eliminate(s, 2, "debt")
	expect("a vacancy election doesn't reopen it", GendersScript.can_change(s), false)


func the_market_women_card() -> void:
	var s := GameScript.new_game([1, 2, 3, 4, 5], 5, {1: "female", 2: "female", 3: "male", 4: "other"})
	expect("the card is listed", CardsScript.effects("settlement", MARKET_WOMEN), {"collect_each": {"gender": "female", "amount": 5}})
	var total: int = total_money(s)
	var ev := CardEffectsScript.apply(s, 2, "settlement", MARKET_WOMEN)
	expect("every other woman pays the drawer 5 PSD", [s.psd[1], s.psd[2], s.psd[3], s.psd[4], s.psd[5]], [995, 1005, 1000, 1000, 1000])
	expect("... men, others and players who haven't said pay nothing, and the drawer doesn't pay herself", [ev[0]["collected_from"], ev[0]["collected"], ev[0].has("new_debts")], [[1], 5, false])
	expect("... money is conserved and the event is logged once", [total_money(s), count(s.event_log, "card_applied")], [total, 1])

	# More women, and one who can't pay.
	s = GameScript.new_game([1, 2, 3, 4, 5], 5, {1: "female", 2: "male", 3: "female", 4: "female", 5: "female"})
	s.psd[2] += s.psd[3] - 2
	s.psd[3] = 2
	total = total_money(s)
	ev = CardEffectsScript.apply(s, 2, "settlement", MARKET_WOMEN)
	expect("a woman who can't pay owes the rest to the drawer", [s.psd[3], DebtScript.total_debt(s, 3), ev[0]["new_debts"]], [0, 3, {3: 3}])
	expect("... the others pay in full: 4 women, 17 PSD at once", [ev[0]["collected_from"], ev[0]["collected"]], [[1, 3, 4, 5], 17])
	expect("... and money is conserved", total_money(s), total)

	# The drawer is a woman: they collect from the others only.
	s = GameScript.new_game([1, 2, 3], 5, {1: "female", 2: "female", 3: "female"})
	ev = CardEffectsScript.apply(s, 1, "settlement", MARKET_WOMEN)
	expect("a woman drawing it collects from the other women, not herself", [ev[0]["collected_from"], s.psd[1]], [[2, 3], 1010])

	# Nobody to collect from.
	s = GameScript.new_game([1, 2, 3], 5, {1: "male"})
	ev = CardEffectsScript.apply(s, 1, "settlement", MARKET_WOMEN)
	expect("with no women at the table nothing is collected", [ev[0]["collected_from"], ev[0]["collected"], s.psd[1]], [[], 0, 1000])


func views_and_saves() -> void:
	var s := GameScript.new_game([1, 2, 3], 5, {1: "female", 2: "male"})
	expect("everyone sees every gender", [ViewsScript.state_view(s, 3)["genders"], ViewsScript.state_view(s, 1)["genders"]], [{1: "female", 2: "male"}, {1: "female", 2: "male"}])
	var errors: Array = []
	var restored: GameStateScript = SerializerScript.state_from_json(SerializerScript.state_to_json(s), errors)
	expect("a saved game remembers them", [errors, restored.genders], [[], {1: "female", 2: "male"}])


# --- helpers -----------------------------------------------------------------------------

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


func total_money(s: GameStateScript) -> int:
	var total: int = s.treasury
	for id in s.psd:
		total += s.psd[id]
	return total


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
