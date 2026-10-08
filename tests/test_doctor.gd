extends SceneTree

const GameScript = preload("res://scripts/game.gd")
const RolesScript = preload("res://scripts/roles.gd")
const SicknessScript = preload("res://scripts/sickness.gd")
const RoundEndScript = preload("res://scripts/round_end.gd")
const DoctorScript = preload("res://scripts/doctor.gd")
const DebtScript = preload("res://scripts/debt.gd")
const ViewsScript = preload("res://scripts/views.gd")
const SerializerScript = preload("res://scripts/serializer.gd")
const GameStateScript = preload("res://scripts/game_state.gd")

const PRESIDENT = GameStateScript.LeaderType.PRESIDENT
const DOCTOR := 3
const PATIENT := 4

var failures: int = 0


func _init() -> void:
	offering()
	the_secret_bead()
	answering()
	paying()
	guessing()
	curing()
	sabotage()
	right_guess()
	wrong_guess()
	the_handbook_example()
	sickening()
	charges()
	people_leaving()
	saving_mid_dose()
	print("%d failure(s)" % failures)
	quit(1 if failures > 0 else 0)


func offering() -> void:
	var s := new_game()
	expect("a valid offer is announced to everyone, with the price", [types(offer(s)), s.dose["phase"], s.dose["price"]], [["dose_offered"], DoctorScript.OFFERED, 40])
	var ev: Dictionary = last_of(s, "dose_offered")
	expect("... who, what, how much and for how long", [ev["doctor"], ev["patient"], ev["kind"], ev["dose"], ev["price"], ev["seconds"], ev["audience"]], [3, 4, "heal", "Agbo", 40, 30, []])
	expect("only one dose at a time", send(s, 3, offer_command()).front()["reason"], "Another dose is already being given.")

	s = new_game()
	expect("a player who isn't a Doctor can't offer", send(s, 1, offer_command(1))[0]["reason"], "You don't hold the Doctor role.")
	s.sick[3] = true
	expect("a sick Doctor can't", send(s, 3, offer_command())[0]["reason"], "Sick players can't use pledges.")
	s.sick[3] = false
	s.popularity[3] = -50
	expect("a CANCELLED Doctor can't", send(s, 3, offer_command())[0]["reason"], "CANCELLED players have no roles until they climb back.")
	s.popularity[3] = 0
	for bad in [null, "4", true, 4.0, 0, 9, 3]:
		expect("patient %s is refused" % str(bad), send(s, 3, offer_command(3, {"patient": bad}))[0]["type"], "rejected")
	expect("a Doctor can't treat themselves", send(s, 3, offer_command(3, {"patient": 3}))[0]["reason"], "A Doctor can't treat themselves.")
	s.eliminated[5] = true
	expect("an eliminated patient is refused", send(s, 3, offer_command(3, {"patient": 5}))[0]["reason"], "Choose a patient who is in the game.")
	for bad in [null, "cure", 1, "Heal"]:
		expect("kind %s is refused" % str(bad), send(s, 3, offer_command(3, {"kind": bad}))[0]["reason"], "Choose heal or sicken.")
	for bad in [null, "agbo", "Tablet", 2]:
		expect("dose %s is refused" % str(bad), send(s, 3, offer_command(3, {"dose": bad}))[0]["reason"], "Choose Agbo, Concoction or Surgery.")
	for bad in [null, -1, 5001, 1.5, "40", true]:
		expect("price %s is refused" % str(bad), send(s, 3, offer_command(3, {"price": bad}))[0]["reason"], "The price must be a whole number from 0 to 5000.")
	expect("a price of 0 and of 5000 are allowed", [types(send(s, 3, offer_command(3, {"price": 0}))), types(answer(s, false)), types(send(s, 3, offer_command(3, {"price": 5000})))], [["dose_offered"], ["dose_rejected"], ["dose_offered"]])

	s = new_game()
	s.sick[4] = false
	s.sick_left.erase(4)
	expect("only a sick player can be healed", send(s, 3, offer_command())[0]["reason"], "Only a sick player can be healed.")
	s = new_game()
	for bad in [null, "true", 1, 0]:
		var command := offer_command()
		if bad == null:
			command.erase("poison")
		else:
			command["poison"] = bad
		expect("a heal needs the bead as true or false: %s refused" % str(bad), send(s, 3, command)[0]["reason"], "Say which bead is in your hand: poison true or false.")

	s = new_game()
	var empty := GameScript.new_game([1, 2, 3, 4, 5], 5)
	expect("no doses outside a term", send(empty, 3, offer_command())[0]["type"], "rejected")


func the_secret_bead() -> void:
	var s := new_game()
	offer(s, {"poison": true})
	expect("the bead is kept in server state", s.dose_secret, {"poison": true})
	var ev: Dictionary = last_of(s, "dose_offered")
	expect("the offer says nothing about the bead", [ev.has("poison"), ev.has("bead")], [false, false])
	for viewer in [1, 3, 4]:
		var view: Dictionary = ViewsScript.state_view(s, viewer)
		expect("player %d can see the dose but not the bead" % viewer, [view.has("dose_secret"), view["dose"]["doctor"], view["dose"].has("poison")], [false, 3, false])
		expect("... nor in the JSON a phone gets", ViewsScript.state_view_json(s, viewer).contains("dose_secret"), false)
	var json: String = SerializerScript.state_to_json(s)
	expect("the server's own save does hold it", json.contains("dose_secret"), true)


func answering() -> void:
	var s := new_game()
	offer(s)
	expect("only the patient answers", send(s, 5, {"type": "dose_respond", "accept": true})[0]["reason"], "Only the patient answers.")
	expect("... not the Doctor", send(s, 3, {"type": "dose_respond", "accept": true})[0]["reason"], "Only the patient answers.")
	for bad in [null, "yes", 1, 0]:
		expect("answer %s is refused" % str(bad), send(s, 4, {"type": "dose_respond", "accept": bad})[0]["reason"], "Accept or reject.")
	var ev := answer(s, false)
	expect("the patient can reject any cure", [types(ev), s.dose, s.dose_secret, s.doctor_used.get(3, 0)], [["dose_rejected"], {}, {}, 0])
	expect("a rejected dose costs nothing", [s.psd[4], s.psd[3]], [s.psd[4], s.psd[3]])
	expect("nothing to answer now", send(s, 4, {"type": "dose_respond", "accept": true})[0]["reason"], "There is no dose on offer.")

	s = new_game()
	offer(s)
	expect("before the time is up nothing happens", types(GameScript.tick(s, int(s.dose["deadline"]) - 1)), [])
	var ev2 := GameScript.tick(s, int(s.dose["deadline"]))
	expect("silence for 30 seconds is a rejection", [types(ev2), s.dose, s.doctor_used.get(3, 0)], [["dose_expired"], {}, 0])


func paying() -> void:
	var s := new_game()
	offer(s, {"price": 40})
	var patient_cash: int = s.psd[4]
	var doctor_cash: int = s.psd[3]
	var total: int = total_money(s)
	var ev := answer(s, true)
	expect("accepting pays the Doctor at once", [types(ev), s.psd[4], s.psd[3]], [["dose_accepted"], patient_cash - 40, doctor_cash + 40])
	expect("... and spends a charge", s.doctor_used[3], 1)
	expect("... the guessing opens", [s.dose["phase"], s.dose["deadline"]], [DoctorScript.GUESSING, s.clock_ms + 10000])
	expect("... money is conserved", total_money(s), total)

	# A patient who can't afford it goes into debt to the Doctor, as agreed payments always do.
	s = new_game()
	s.psd[1] += s.psd[4] - 10
	s.psd[4] = 10
	offer(s, {"price": 40})
	ev = answer(s, true)
	expect("a patient who can't afford the price owes the Doctor the rest", [s.psd[4], DebtScript.total_debt(s, 4), ev[0]["new_debt"]], [0, 30, 30])


func guessing() -> void:
	var s := new_game()
	offer(s)
	expect("nothing can be guessed before the patient accepts", send(s, 5, {"type": "dose_guess"})[0]["reason"], "Nothing can be guessed now.")
	answer(s, true)
	expect("the Doctor can't guess", send(s, 3, {"type": "dose_guess"})[0]["reason"], "The Doctor can't guess.")
	expect("a stranger can't guess", send(s, 9, {"type": "dose_guess"})[0]["reason"], "You are not in the game.")
	var ev := send(s, 5, {"type": "dose_guess"})
	expect("anyone else may guess Sabotage, and it is announced", [types(ev), s.dose["guesser"], ev[0]["guesser"]], [["sabotage_guessed"], 5, 5])
	expect("one guess per dose", send(s, 1, {"type": "dose_guess"})[0]["reason"], "Somebody has already guessed Sabotage.")
	s = new_game()
	offer(s)
	answer(s, true)
	expect("the patient may guess too", types(send(s, 4, {"type": "dose_guess"})), ["sabotage_guessed"])
	s = new_game()
	s.eliminated[5] = true
	offer(s)
	answer(s, true)
	expect("an eliminated player can't guess", send(s, 5, {"type": "dose_guess"})[0]["reason"], "You are not in the game.")


func curing() -> void:
	for case in [["Agbo", 3, 2, 3, 1], ["Concoction", 3, 1, 3, 3]]:
		var s := new_game(case[3])
		offer(s, {"dose": case[0], "poison": false})
		answer(s, true)
		var ev := finish(s)
		expect("%s with the blue bead and no guess cures: %d round(s) sooner" % [case[0], 1 if case[0] == "Agbo" else 2], [types(ev)[0], ev[0]["outcome"], ev[0]["bead"]], ["dose_given", "cure", "blue"])
		expect("... sick for %d now" % case[2], s.sick_left.get(4, 0), case[2] if case[2] > 0 else 0)
	var s2 := new_game(3)
	offer(s2, {"dose": "Surgery", "poison": false})
	answer(s2, true)
	var ev2 := finish(s2)
	expect("Surgery with the blue bead recovers at once, immune for the original 3", [types(ev2), s2.sick[4], s2.immune_left[4]], [["dose_given", "recovered"], false, 3])
	s2 = new_game(1)
	offer(s2, {"dose": "Concoction", "poison": false})
	answer(s2, true)
	finish(s2)
	expect("a cure bigger than the sickness just ends it", [s2.sick[4], s2.immune_left[4]], [false, 1])
	expect("the dose is finished and the secret is gone", [s2.dose, s2.dose_secret], [{}, {}])


func sabotage() -> void:
	var s := new_game(2)
	offer(s, {"dose": "Agbo", "poison": true})
	answer(s, true)
	var ev := finish(s)
	expect("unnoticed Poison in Agbo lengthens the sickness by 1", [ev[0]["outcome"], ev[0]["bead"], types(ev)[1], s.sick_left[4], s.sick_original[4]], ["sabotage", "red", "sickness_lengthened", 3, 2])
	s = new_game(2)
	offer(s, {"dose": "Concoction", "poison": true})
	answer(s, true)
	finish(s)
	expect("... and in Concoction by 2", s.sick_left[4], 4)

	# Surgery sabotaged kills.
	s = new_game(2)
	s.wills[4] = {"psd_heir": 5, "on_hold": false}
	offer(s, {"dose": "Surgery", "poison": true})
	answer(s, true)
	var total: int = total_money(s)
	ev = finish(s)
	expect("unnoticed Poison in Surgery eliminates the patient", [types(ev).has("player_eliminated"), s.eliminated[4], ev[0]["outcome"]], [true, true, "sabotage"])
	expect("... their will is carried out, and the events are logged once", [s.heirs[4], count(s.event_log, "player_eliminated"), count(s.event_log, "dose_given")], [5, 1, 1])
	expect("... with all the money still there", total_money(s), total)


func right_guess() -> void:
	var s := new_game(2)
	offer(s, {"dose": "Concoction", "price": 60, "poison": true})
	answer(s, true)
	send(s, 5, {"type": "dose_guess"})
	var doctor_cash: int = s.psd[3]
	var guesser_cash: int = s.psd[5]
	var total: int = total_money(s)
	var ev := finish(s)
	expect("a right guess: the Doctor pays the guesser the price", [ev[0]["outcome"], s.psd[3] - doctor_cash, s.psd[5] - guesser_cash], ["right_guess", -60, 60])
	expect("... the patient is given a genuine Cure (a Concoction cures 2 rounds: recovered, immune for 2)", [s.sick[4], s.immune_left[4]], [false, 2])
	expect("... and the Doctor loses their licence", [RolesScript.has(s, 3, "Doctor"), types(ev).has("role_lost"), types(ev).has("licence_lost")], [false, true, true])
	expect("... money is conserved", total_money(s), total)
	expect("... each event is logged once", [count(s.event_log, "dose_given"), count(s.event_log, "licence_lost"), count(s.event_log, "recovered")], [1, 1, 1])

	# A Doctor who can't pay owes the guesser.
	s = new_game(2)
	offer(s, {"price": 100, "poison": true})
	answer(s, true)
	send(s, 5, {"type": "dose_guess"})
	s.psd[1] += s.psd[3] - 30
	s.psd[3] = 30
	ev = finish(s)
	expect("a Doctor who can't afford the guesser owes the rest", [s.psd[3], DebtScript.total_debt(s, 3), ev[0]["doctor_new_debt"]], [0, 70, 70])


func wrong_guess() -> void:
	var s := new_game(2)
	offer(s, {"dose": "Agbo", "price": 50, "poison": false})
	answer(s, true)
	send(s, 5, {"type": "dose_guess"})
	var doctor_cash: int = s.psd[3]
	var guesser_cash: int = s.psd[5]
	var total: int = total_money(s)
	var ev := finish(s)
	expect("a wrong guess: the guesser pays the Doctor the price", [ev[0]["outcome"], s.psd[3] - doctor_cash, s.psd[5] - guesser_cash], ["wrong_guess", 50, -50])
	expect("... the patient is still cured and the Doctor keeps the licence", [s.sick_left[4], RolesScript.has(s, 3, "Doctor")], [1, true])
	expect("... money is conserved", total_money(s), total)
	s = new_game(2)
	offer(s, {"price": 50, "poison": false})
	answer(s, true)
	send(s, 5, {"type": "dose_guess"})
	s.psd[3] += s.psd[5] - 20
	s.psd[5] = 20
	ev = finish(s)
	expect("a guesser who can't pay goes into debt to the Doctor", [s.psd[5], DebtScript.total_debt(s, 5), ev[0]["guesser_new_debt"]], [0, 30, 30])


func the_handbook_example() -> void:
	# "A Concoction dose makes you sick for 2 rounds. A sabotaged cure adds 2 more, so you're sick for 4
	# rounds. When you recover, you're immune for 2 rounds, not 4."
	var s := new_game(2)
	offer(s, {"dose": "Concoction", "poison": true})
	answer(s, true)
	finish(s)
	expect("sick for 4 rounds after the sabotage", [s.sick_left[4], s.sick_original[4]], [4, 2])
	for i in 4:
		RoundEndScript.run(s)
	expect("... recovered after 4 rounds, immune for 2, not 4", [s.sick[4], s.immune_left[4]], [false, 2])


func sickening() -> void:
	var s := new_game()
	s.sick[5] = false
	offer(s, {"patient": 5, "kind": "sicken", "dose": "Concoction", "price": 30}, true)
	var cash: int = s.psd[5]
	var ev := answer(s, true, 5)
	expect("a patient who accepts and pays is sick for the dose's rounds", [types(ev), s.sick_left[5], s.psd[5] - cash, s.doctor_used[3]], [["dose_accepted", "sickened"], 2, -30, 1])
	expect("... straight away: no bead, no guessing", [s.dose, s.dose_secret], [{}, {}])
	s = new_game()
	expect("Surgery can't be used to sicken", send(s, 3, {"type": "dose_offer", "patient": 5, "kind": "sicken", "dose": "Surgery", "price": 10})[0]["reason"], "Surgery can't be used to sicken.")
	expect("there is no bead when sickening", send(s, 3, {"type": "dose_offer", "patient": 5, "kind": "sicken", "dose": "Agbo", "price": 10, "poison": false})[0]["reason"], "There is no bead when sickening.")
	expect("a sick player can't be sickened again", send(s, 3, {"type": "dose_offer", "patient": 4, "kind": "sicken", "dose": "Agbo", "price": 10})[0]["reason"], "A sick player can't be sickened again.")
	s.immune_left[5] = 2
	expect("nor an immune one", send(s, 3, {"type": "dose_offer", "patient": 5, "kind": "sicken", "dose": "Agbo", "price": 10})[0]["reason"], "They are immune for 2 more round(s).")
	s = new_game()
	send(s, 3, {"type": "dose_offer", "patient": 5, "kind": "sicken", "dose": "Agbo", "price": 10})
	SicknessScript.sicken(s, 5, 1)   # they fall sick some other way while the offer waits
	var ev2 := answer(s, true, 5)
	expect("if they became sick meanwhile the dose is void and costs nothing", [types(ev2), s.doctor_used.get(3, 0)], [["dose_void"], 0])


func charges() -> void:
	var s := new_game(9)
	for i in 2:
		offer(s, {"poison": false})
		answer(s, true)
		finish(s)
		if i == 0:
			SicknessScript.sicken(s, 4, 5) if SicknessScript.problem_sickening(s, 4) == "" else null
	expect("two doses use both charges", s.doctor_used[3], 2)
	SicknessScript.sicken(s, 5, 3)
	expect("a third dose is refused", send(s, 3, offer_command(3, {"patient": 5}))[0]["reason"], "You have used your 2 charges this round.")
	RoundEndScript.run(s)
	expect("the charges come back when the round ends", [s.doctor_used, DoctorScript.charges_left(s, 3)], [{}, 2])


func people_leaving() -> void:
	var s := new_game(3)
	offer(s)
	answer(s, true)
	s.eliminated[3] = true
	var ev := finish(s)
	expect("if the Doctor leaves the game before the dose is given it is void", [types(ev), ev[0]["reason"]], [["dose_void"], "the Doctor left the game"])
	expect("... and nothing happens to the patient", s.sick_left[4], 3)

	s = new_game(3)
	offer(s)
	answer(s, true)
	RolesScript.remove(s, 3, "Doctor")
	expect("so is a dose from someone who is no longer a Doctor", finish(s)[0]["reason"], "the Doctor is no longer a Doctor")

	s = new_game(3)
	offer(s)
	answer(s, true)
	s.eliminated[4] = true
	expect("so is a dose for a patient who has left", finish(s)[0]["reason"], "the patient left the game")

	s = new_game(2)
	offer(s, {"poison": true})
	answer(s, true)
	send(s, 5, {"type": "dose_guess"})
	s.eliminated[5] = true
	var ev2 := finish(s)
	expect("a guesser who has left made no guess: the Poison works", [ev2[0]["outcome"], ev2[0]["guesser"]], ["sabotage", 0])


func saving_mid_dose() -> void:
	var s := new_game(2)
	offer(s, {"dose": "Concoction", "poison": true})
	answer(s, true)
	send(s, 5, {"type": "dose_guess"})
	var errors: Array = []
	var restored: GameStateScript = SerializerScript.state_from_json(SerializerScript.state_to_json(s), errors)
	expect("a game saved mid-dose loads, secret bead included", [errors, restored.dose_secret], [[], {"poison": true}])
	for g in [s, restored]:
		GameScript.tick(g, int(g.dose["deadline"]))
	expect("... and gives the same dose", SerializerScript.state_to_json(s) == SerializerScript.state_to_json(restored), true)


# --- helpers -----------------------------------------------------------------------------

# Player 2 leads, a term is running, player 3 is a Doctor and player 4 is sick for `rounds`.
func new_game(rounds: int = 2) -> GameStateScript:
	for seed_value in range(1, 400):
		var s := GameScript.new_game([1, 2, 3, 4, 5], seed_value)
		for id in [1, 2, 3, 4, 5]:
			GameScript.handle(s, id, {"type": "cast_vote", "candidate": 2})
		if s.leader_type == PRESIDENT:
			GameScript.handle(s, 2, {"type": "pass_window"})
			RolesScript.grant(s, DOCTOR, "Doctor")
			SicknessScript.sicken(s, PATIENT, rounds)
			return s
	assert(false, "no seed gave a President")
	return null


func offer_command(doctor: int = 3, overrides: Dictionary = {}) -> Dictionary:
	var command := {"type": "dose_offer", "patient": PATIENT, "kind": "heal", "dose": "Agbo", "price": 40, "poison": false}
	for key in overrides:
		command[key] = overrides[key]
	return command


func offer(s: GameStateScript, overrides: Dictionary = {}, sicken: bool = false) -> Array:
	var command := offer_command(3, overrides)
	if sicken:
		command.erase("poison")
	return send(s, 3, command)


func answer(s: GameStateScript, accept: bool, patient: int = PATIENT) -> Array:
	return send(s, patient, {"type": "dose_respond", "accept": accept})


# Run the clock out on the guessing and return what happened.
func finish(s: GameStateScript) -> Array:
	return GameScript.tick(s, int(s.dose["deadline"]))


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
