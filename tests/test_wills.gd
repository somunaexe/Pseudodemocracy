extends SceneTree

const GameScript = preload("res://scripts/game.gd")
const RolesScript = preload("res://scripts/roles.gd")
const WillsScript = preload("res://scripts/wills.gd")
const RoundEndScript = preload("res://scripts/round_end.gd")
const ElimScript = preload("res://scripts/elimination.gd")
const DebtScript = preload("res://scripts/debt.gd")
const ViewsScript = preload("res://scripts/views.gd")
const SerializerScript = preload("res://scripts/serializer.gd")
const GameStateScript = preload("res://scripts/game_state.gd")
const PlayScript = preload("res://tests/play.gd")

const PRESIDENT = GameStateScript.LeaderType.PRESIDENT
const LAWYER := 2
const TESTATOR := 3

var failures: int = 0


func _init() -> void:
	proposing()
	who_sees_what()
	the_lawyer_answers()
	signing()
	upkeep_and_arrears()
	catching_up()
	replacing_and_revoking()
	in_a_real_term()
	elimination_and_the_lawyer()
	saving_with_a_pending_will()
	print("%d failure(s)" % failures)
	quit(1 if failures > 0 else 0)


func proposing() -> void:
	var s := table()
	expect("a valid proposal is accepted", types(propose(s)), ["will_proposed"])
	expect("... and waits for the Lawyer", s.will_offers[3]["lawyer"], 2)
	expect("only one will waiting at a time", propose(s)[0]["reason"], "You already have a will waiting for a Lawyer.")

	s = table()
	expect("a stranger can't propose", send(s, 9, proposal())[0]["reason"], "You are not in the game.")
	for bad in [null, "2", true, 2.0, 0, 9]:
		expect("lawyer %s is refused" % str(bad), propose(s, {"lawyer": bad})[0]["reason"], "Choose a Lawyer who is in the game.")
	expect("you can't be your own Lawyer", send(s, 2, proposal({"lawyer": 2}))[0]["reason"], "You can't be your own Lawyer.")
	expect("the Lawyer must be a Lawyer", propose(s, {"lawyer": 1})[0]["reason"], "That player is not a Lawyer.")
	s.eliminated[2] = true
	expect("an eliminated Lawyer is refused", propose(s)[0]["reason"], "Choose a Lawyer who is in the game.")

	s = table()
	for bad in [null, "4", true, 4.5]:
		expect("psd_heir %s is refused" % str(bad), propose(s, {"psd_heir": bad})[0]["reason"], "Name an heir by their player number.")
	expect("an heir must be in the game", propose(s, {"psd_heir": 9})[0]["reason"], "That heir is not in the game.")
	expect("... and not be you", propose(s, {"psd_heir": 3})[0]["reason"], "You can't be your own heir.")
	expect("... nor have 0 as the PSD heir", propose(s, {"psd_heir": 0})[0]["reason"], "That heir is not in the game.")
	s.eliminated[5] = true
	expect("... nor be eliminated", propose(s, {"psd_heir": 5})[0]["reason"], "That heir is not in the game.")
	var command := proposal()
	command.erase("psd_heir")
	expect("the PSD heir can't be left out", send(s, 3, command)[0]["reason"], "Name an heir by their player number.")
	expect("a role heir of 0 means nobody", types(propose(s, {"role_heir": 0})), ["will_proposed"])
	s = table()
	expect("a role heir who is you is refused", propose(s, {"role_heir": 3})[0]["reason"], "You can't be your own heir.")
	expect("... and one who isn't there", propose(s, {"role_heir": 9})[0]["reason"], "That heir is not in the game.")
	expect("... and one who isn't a number", propose(s, {"role_heir": "5"})[0]["reason"], "Name an heir by their player number.")
	for key in ["fee", "upkeep"]:
		for bad in [null, -1, 5001, 1.5, "10", true]:
			expect("%s %s is refused" % [key, str(bad)], propose(s, {key: bad})[0]["reason"], "The %s must be a whole number from 0 to 5000." % key)
	expect("a fee and upkeep of 0 are allowed", types(propose(s, {"fee": 0, "upkeep": 0})), ["will_proposed"])


func who_sees_what() -> void:
	var s := table()
	var ev := propose(s)
	expect("the proposal goes only to the testator and the Lawyer", ev[0]["audience"], [3, 2])
	expect("... and says nothing about the heirs", [ev[0].has("psd_heir"), ev[0].has("role_heir")], [false, false])
	expect("a third player is shown nothing of it", ViewsScript.visible_events(s.event_log, 1).filter(func(e): return e["type"] == "will_proposed"), [])
	expect("the Lawyer sees it", ViewsScript.visible_events(s.event_log, 2).filter(func(e): return e["type"] == "will_proposed").size(), 1)
	var view: Dictionary = ViewsScript.state_view(s, 1)
	expect("pending wills are server-only", [view.has("will_offers"), view.has("wills")], [false, false])
	expect("... nor in the JSON", ViewsScript.state_view_json(s, 1).contains("will_offers"), false)


func the_lawyer_answers() -> void:
	var s := table()
	propose(s)
	expect("only the named Lawyer answers", send(s, 1, respond(3, true))[0]["reason"], "There is no will waiting for you from that player.")
	expect("... and for the right testator", send(s, 2, respond(4, true))[0]["reason"], "There is no will waiting for you from that player.")
	for bad in [null, "3", true, 3.0]:
		expect("testator %s is refused" % str(bad), send(s, 2, {"type": "will_respond", "testator": bad, "accept": true})[0]["type"], "rejected")
	for bad in [null, "yes", 1]:
		expect("answer %s is refused" % str(bad), send(s, 2, {"type": "will_respond", "testator": 3, "accept": bad})[0]["reason"], "Accept or reject.")
	var cash: int = s.psd[3]
	var ev := send(s, 2, respond(3, false))
	expect("a refusal costs nothing and ends the offer", [types(ev), ev[0]["audience"], s.will_offers.has(3), s.psd[3] - cash, s.wills.has(3)], [["will_refused"], [3, 2], false, 0, false])

	s = table()
	propose(s)
	s.sick[2] = true
	expect("a sick Lawyer can't sign", send(s, 2, respond(3, true))[0]["reason"], "Sick players can't use pledges.")
	expect("... and the offer is still waiting", s.will_offers.has(3), true)

	s = table()
	propose(s)
	expect("before the time is up the offer stays", types(GameScript.tick(s, int(s.will_offers[3]["deadline"]) - 1)), [])
	var ev2 := GameScript.tick(s, int(s.will_offers[3]["deadline"]))
	expect("a will nobody signs in 30 seconds expires", [types(ev2), ev2[0]["audience"], s.will_offers.has(3)], [["will_expired"], [3, 2], false])

	s = table()
	propose(s)
	RolesScript.remove(s, 2, "Lawyer")
	var ev3 := send(s, 2, respond(3, true))
	expect("a Lawyer who is no longer a Lawyer can't sign: void", ev3[0]["type"], "will_void")


func signing() -> void:
	var s := table()
	propose(s, {"fee": 80, "upkeep": 20, "psd_heir": 4, "role_heir": 5})
	var lawyer_cash: int = s.psd[2]
	var cash: int = s.psd[3]
	var total: int = total_money(s)
	var ev := send(s, 2, respond(3, true))
	expect("signing pays the Lawyer the fee", [s.psd[3] - cash, s.psd[2] - lawyer_cash], [-80, 80])
	expect("... that a will exists is public", [ev[0]["type"], ev[0]["audience"], ev[0].has("psd_heir")], ["will_signed", [], false])
	expect("... its terms go to the testator and the Lawyer only", [ev[1]["type"], ev[1]["audience"], ev[1]["psd_heir"], ev[1]["role_heir"], ev[1]["upkeep"]], ["will_terms", [3, 2], 4, 5, 20])
	expect("the will is kept by that Lawyer", s.wills[3], {"psd_heir": 4, "role_heir": 5, "on_hold": false, "lawyer": 2, "upkeep": 20, "arrears": 0})
	expect("the offer is gone and each event logged once", [s.will_offers.has(3), count(s.event_log, "will_signed"), count(s.event_log, "will_terms")], [false, 1, 1])
	expect("money is conserved", total_money(s), total)

	# By default the roles go to the same heir.
	s = table()
	propose(s)
	send(s, 2, respond(3, true))
	expect("without a role heir the roles go to the PSD heir", s.wills[3]["role_heir"], 4)
	s = table()
	propose(s, {"role_heir": 0})
	send(s, 2, respond(3, true))
	expect("a role heir of 0 is kept: the roles are rescinded", s.wills[3]["role_heir"], 0)

	# A fee the player can't afford becomes debt to the Lawyer, like any agreed payment.
	s = table()
	s.psd[1] += s.psd[3] - 10
	s.psd[3] = 10
	propose(s, {"fee": 50})
	ev = send(s, 2, respond(3, true))
	expect("a fee that can't be paid becomes debt to the Lawyer", [s.psd[3], DebtScript.total_debt(s, 3), ev[1]["new_debt"]], [0, 40, 40])

	# The views.
	s = table()
	propose(s, {"psd_heir": 4, "role_heir": 5})
	send(s, 2, respond(3, true))
	expect("the testator sees their own will", ViewsScript.state_view(s, 3)["my_will"]["psd_heir"], 4)
	expect("the Lawyer sees the wills they keep", ViewsScript.state_view(s, 2)["kept_wills"][3]["role_heir"], 5)
	expect("nobody else sees any will", [ViewsScript.state_view(s, 1)["my_will"], ViewsScript.state_view(s, 1)["kept_wills"]], [{}, {}])
	expect("... and a player who isn't a Lawyer keeps none", ViewsScript.state_view(s, 4)["kept_wills"], {})
	var json: String = ViewsScript.state_view_json(s, 1)
	expect("the heirs are not in the JSON a bystander gets", [json.contains("psd_heir"), json.contains("\"wills\":")], [false, false])
	var view: Dictionary = ViewsScript.state_view(s, 3)
	view["my_will"]["psd_heir"] = 99
	expect("the view is a copy", s.wills[3]["psd_heir"], 4)


func upkeep_and_arrears() -> void:
	var s := signed(20)
	var lawyer_cash: int = s.psd[2]
	var cash: int = s.psd[3]
	var ev := RoundEndScript.run(s)
	expect("at the end of the round the testator pays the upkeep", [s.psd[3] - cash, s.psd[2] - lawyer_cash, types(ev)], [-20, 20, ["will_upkeep_paid"]])
	expect("... privately", ev[0]["audience"], [3, 2])
	expect("the will stays active", s.wills[3]["on_hold"], false)

	# A player who can't pay in full misses the payment.
	s = signed(20)
	s.psd[1] += s.psd[3] - 15
	s.psd[3] = 15
	cash = s.psd[3]
	ev = RoundEndScript.run(s)
	expect("with less cash than the upkeep the payment is missed: the will goes on hold", [types(ev), s.wills[3]["on_hold"], s.wills[3]["arrears"], s.psd[3] - cash], [["will_on_hold"], true, 20, 0])
	RoundEndScript.run(s)
	expect("each further round adds to the arrears and charges nothing", [s.wills[3]["arrears"], s.psd[3] - cash], [40, 0])

	# A player in debt has no cash, so misses it too.
	s = signed(20)
	s.psd[1] += s.psd[3]
	s.psd[3] = 0
	DebtScript.charge(s, 3, 0, 10)
	RoundEndScript.run(s)
	expect("a player in debt misses it too", s.wills[3]["on_hold"], true)

	# Nothing to pay, or nobody to pay.
	s = signed(0)
	expect("no upkeep, no event", RoundEndScript.run(s), [])
	s = signed(20)
	RolesScript.remove(s, 2, "Lawyer")
	cash = s.psd[3]
	expect("if the Lawyer is no longer a Lawyer nobody is paid", [RoundEndScript.run(s), s.psd[3] - cash], [[], 0])


func catching_up() -> void:
	var s := signed(20)
	expect("a will that isn't on hold can't be caught up", send(s, 3, {"type": "will_catch_up"})[0]["reason"], "You have no will on hold.")
	expect("... and nobody without a will", send(s, 1, {"type": "will_catch_up"})[0]["reason"], "You have no will on hold.")
	s.psd[1] += s.psd[3] - 15
	s.psd[3] = 15
	RoundEndScript.run(s)
	RoundEndScript.run(s)
	expect("catching up needs the whole arrears in hand", send(s, 3, {"type": "will_catch_up"})[0]["reason"], "You need 40 PSD in hand to catch up.")
	s.psd[3] = 100
	var lawyer_cash: int = s.psd[2]
	var total: int = total_money(s)
	var ev := send(s, 3, {"type": "will_catch_up"})
	expect("with the money the arrears are paid and the will is active again", [types(ev), s.psd[3], s.psd[2] - lawyer_cash, s.wills[3]["on_hold"], s.wills[3]["arrears"]], [["will_reactivated"], 60, 40, false, 0])
	expect("... privately, and money is conserved", [ev[0]["audience"], total_money(s)], [[3, 2], total])
	RoundEndScript.run(s)
	expect("... and upkeep is paid again from the next round", [s.psd[3], s.wills[3]["on_hold"]], [40, false])


func replacing_and_revoking() -> void:
	var s := signed(20)
	propose(s, {"psd_heir": 1, "role_heir": 0, "fee": 10})
	expect("a new will can be proposed while one is in force", s.will_offers.has(3), true)
	expect("... and the old one stands until it is signed", s.wills[3]["psd_heir"], 4)
	send(s, 2, respond(3, true))
	expect("signing replaces the old will", [s.wills[3]["psd_heir"], s.wills[3]["role_heir"]], [1, 0])

	var cash: int = s.psd[3]
	var ev := send(s, 3, {"type": "will_revoke"})
	expect("a will can be torn up, with no refund", [types(ev), s.wills.has(3), s.psd[3] - cash, ev[0]["audience"]], [["will_revoked"], false, 0, [3, 2]])
	expect("... only if there is one", send(s, 3, {"type": "will_revoke"})[0]["reason"], "You have no will.")


func in_a_real_term() -> void:
	var s := new_turn()
	RolesScript.grant(s, 4, "Lawyer")
	propose(s, {"lawyer": 4})
	send(s, 4, respond(3, true))
	var upkeep_events_before: int = count(s.event_log, "will_upkeep_paid")
	for id in [2, 3, 4, 5, 1]:
		PlayScript.take_turn(s, id)
	GameScript.handle(s, 2, {"type": "pass_window"})
	expect("when the term ends the upkeep is charged, once", count(s.event_log, "will_upkeep_paid") - upkeep_events_before, 1)
	var seen: Array = ViewsScript.visible_events(s.event_log, 1).filter(func(e): return e["type"] == "will_upkeep_paid")
	expect("... and a bystander never sees it", seen, [])


func elimination_and_the_lawyer() -> void:
	# A will with a working Lawyer is carried out.
	var s := signed(0)
	ElimScript.eliminate(s, 3, "debt")
	expect("a will whose Lawyer is still a Lawyer is carried out", s.heirs.get(3, 0), 4)

	# On hold: it doesn't count (Article 27).
	s = signed(20)
	s.wills[3]["on_hold"] = true
	var ev := ElimScript.eliminate(s, 3, "debt")
	expect("a will on hold doesn't count", [s.heirs.has(3), find(ev, "will_void")["reason"]], [false, "the will was on hold"])

	# The Lawyer is gone: eliminated.
	s = signed(0)
	s.eliminated[2] = true
	ev = ElimScript.eliminate(s, 3, "debt")
	expect("a will whose Lawyer has been eliminated can't be carried out", [s.heirs.has(3), find(ev, "will_void")["reason"]], [false, "the Lawyer who kept the will can no longer carry it out"])

	# The Lawyer lost the role.
	s = signed(0)
	RolesScript.grant(s, 3, "Doctor")
	RolesScript.remove(s, 2, "Lawyer")
	ev = ElimScript.eliminate(s, 3, "debt")
	expect("... or has lost the Lawyer role", [s.heirs.has(3), RolesScript.holders(s, "Doctor")], [false, []])

	# Roles to a different heir through a signed will.
	s = table()
	RolesScript.grant(s, 3, "Doctor")
	propose(s, {"psd_heir": 4, "role_heir": 5})
	send(s, 2, respond(3, true))
	ElimScript.eliminate(s, 3, "debt")
	expect("a signed will sends the money and the roles to different heirs", [s.heirs[3], RolesScript.held(s, 5), RolesScript.held(s, 4)], [4, ["Doctor"], []])
	expect("... and both are Nepo Babies", [s.nepo.has(4), s.nepo.has(5)], [true, true])


func saving_with_a_pending_will() -> void:
	var s := table()
	propose(s, {"psd_heir": 4, "role_heir": 5})
	var errors: Array = []
	var restored: GameStateScript = SerializerScript.state_from_json(SerializerScript.state_to_json(s), errors)
	expect("a game saved with a will waiting loads, heirs included", [errors, restored.will_offers[3]["role_heir"]], [[], 5])
	for g in [s, restored]:
		send(g, 2, respond(3, true))
	expect("... and signs the same will", SerializerScript.state_to_json(s) == SerializerScript.state_to_json(restored), true)


# --- helpers -----------------------------------------------------------------------------

# Five players, player 2 a Lawyer.
func table() -> GameStateScript:
	var s := GameScript.new_game([1, 2, 3, 4, 5], 3)
	RolesScript.grant(s, LAWYER, "Lawyer")
	return s


# Player 3 has a signed will with Lawyer 2, with this upkeep and a fee of 0.
func signed(upkeep: int) -> GameStateScript:
	var s := table()
	propose(s, {"fee": 0, "upkeep": upkeep})
	send(s, 2, respond(3, true))
	return s


func proposal(overrides: Dictionary = {}) -> Dictionary:
	var command := {"type": "will_propose", "lawyer": 2, "psd_heir": 4, "fee": 30, "upkeep": 10}
	for key in overrides:
		command[key] = overrides[key]
	return command


func propose(s: GameStateScript, overrides: Dictionary = {}) -> Array:
	return send(s, 3, proposal(overrides))


func respond(testator: int, accept: bool) -> Dictionary:
	return {"type": "will_respond", "testator": testator, "accept": accept}


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


func find(events: Array, type: String) -> Dictionary:
	for event in events:
		if event["type"] == type:
			return event
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
