class_name Doctor

# The Doctor (handbook Part 6, Doctor & Health, Articles 18 to 24). A Doctor has doctorCharges (2) a round
# to spend, openly, on doses: Agbo (1 round), Concoction (2 rounds) or Surgery (instant). A dose is
# a deal between the Doctor and a patient, at a price the Doctor names ("doses have no fixed prices"):
#
#   HEAL (the patient must be sick)
#     1. The Doctor offers a dose and a price, and SECRETLY chooses the bead in their hand: blue
#        (Cure) or red (Poison). The patient may reject it, or let the time run out.
#     2. If the patient accepts they pay at once (the payment is lost whatever happens) and a charge is
#        spent. For doseGuessSeconds anyone but the Doctor may guess "Sabotage"; one guess per dose.
#     3. Then the bead is revealed and the dose is given:
#          bead blue, no guess      the dose cures (Agbo -1 round, Concoction -2, Surgery at once)
#          bead red, no guess       SABOTAGE: Agbo +1 round, Concoction +2, Surgery eliminates the patient
#          bead red, right guess    the Doctor pays the guesser the price, gives a genuine Cure and loses
#                                   their licence (the Doctor role card) (Articles 19)
#          bead blue, wrong guess   the guesser pays the Doctor the price, and the dose cures (Article 20)
#   SICKEN (the patient must be able to be sickened; Surgery can't be used)
#     The Doctor offers a dose and a price; if the patient accepts and pays, they are sick for that dose's
#     rounds. No bead and no guess. (Assumed: the handbook doesn't say who may be sickened; a patient
#     who consents and pays fits the "convenient condition" Performance card.)
#
# Only one dose at a time. The Doctor can't treat themselves. A Doctor who is sick, CANCELLED or has lost
# the role can't offer (Roles.can_use_power). If the Doctor or patient leaves the game, or the Doctor loses
# the role, before the dose is given, it is void (the payment is not refunded).
#
# Commands (the Doctor offers; the patient answers; anyone else may guess):
#   { "type": "dose_offer", "patient": id, "kind": "heal"|"sicken", "dose": "Agbo"|"Concoction"|"Surgery",
#     "price": whole number, "poison": bool }      poison only with "heal": the bead in the Doctor's hand
#   { "type": "dose_respond", "accept": bool }
#   { "type": "dose_guess" }
#
# Every event this file creates is logged here, once (the Elimination a Surgery causes logs its own).

const GameStateScript = preload("res://scripts/game_state.gd")
const GameDataScript = preload("res://scripts/game_data.gd")
const DebtScript = preload("res://scripts/debt.gd")
const RolesScript = preload("res://scripts/roles.gd")
const SicknessScript = preload("res://scripts/sickness.gd")
const EliminationScript = preload("res://scripts/elimination.gd")
const EventsScript = preload("res://scripts/events.gd")

const OFFERED := GameStateScript.DosePhase.OFFERED
const GUESSING := GameStateScript.DosePhase.GUESSING
const DOSES := ["Agbo", "Concoction", "Surgery"]
const KINDS := ["heal", "sicken"]


# --- commands ----------------------------------------------------------------------------

static func handle(state: GameStateScript, player_id: int, command: Dictionary) -> Array:
	match str(command.get("type", "")):
		"dose_offer":
			return _offer(state, player_id, command)
		"dose_respond":
			return _respond(state, player_id, command)
		"dose_guess":
			return _guess(state, player_id)
	return [_reject(player_id, "Unknown command.")]


static func charges_left(state: GameStateScript, doctor_id: int) -> int:
	return GameDataScript.get_int("doctorCharges") - int(state.doctor_used.get(doctor_id, 0))


static func _offer(state: GameStateScript, doctor_id: int, command: Dictionary) -> Array:
	if state.term.is_empty() or not state.election.is_empty():
		return [_reject(doctor_id, "Doses can only be given during a term.")]
	if not state.dose.is_empty():
		return [_reject(doctor_id, "Another dose is already being given.")]
	var power: String = RolesScript.can_use_power(state, doctor_id, "Doctor")
	if power != "":
		return [_reject(doctor_id, power)]
	if charges_left(state, doctor_id) <= 0:
		return [_reject(doctor_id, "You have used your %d charges this round." % GameDataScript.get_int("doctorCharges"))]
	var patient = command.get("patient", null)
	if typeof(patient) != TYPE_INT or not patient in state.player_ids or state.eliminated.get(patient, false):
		return [_reject(doctor_id, "Choose a patient who is in the game.")]
	if patient == doctor_id:
		return [_reject(doctor_id, "A Doctor can't treat themselves.")]
	var kind = command.get("kind", null)
	if typeof(kind) != TYPE_STRING or not kind in KINDS:
		return [_reject(doctor_id, "Choose heal or sicken.")]
	var dose = command.get("dose", null)
	if typeof(dose) != TYPE_STRING or not dose in DOSES:
		return [_reject(doctor_id, "Choose Agbo, Concoction or Surgery.")]
	var price = command.get("price", null)
	if typeof(price) != TYPE_INT or price < 0 or price > GameDataScript.get_int("dosePriceMax"):
		return [_reject(doctor_id, "The price must be a whole number from 0 to %d." % GameDataScript.get_int("dosePriceMax"))]
	var poison: bool = false
	if kind == "heal":
		if not SicknessScript.is_sick(state, patient):
			return [_reject(doctor_id, "Only a sick player can be healed.")]
		var bead = command.get("poison", null)
		if typeof(bead) != TYPE_BOOL:
			return [_reject(doctor_id, "Say which bead is in your hand: poison true or false.")]
		poison = bead
	else:
		if dose == "Surgery":
			return [_reject(doctor_id, "Surgery can't be used to sicken.")]
		if command.has("poison"):
			return [_reject(doctor_id, "There is no bead when sickening.")]
		var problem: String = SicknessScript.problem_sickening(state, patient)
		if problem != "":
			return [_reject(doctor_id, problem)]
	var seconds: int = GameDataScript.get_int("doseOfferSeconds")
	var ends_at: int = state.clock_ms + seconds * 1000
	state.dose = {"phase": OFFERED, "doctor": doctor_id, "patient": patient, "kind": kind, "dose": dose, "price": price, "deadline": ends_at, "guesser": 0}
	state.dose_secret = {"poison": poison}   # the bead stays in the server's hand until the dose is given
	return [_log(state, "dose_offered", {"doctor": doctor_id, "patient": patient, "kind": kind, "dose": dose, "price": price, "seconds": seconds, "ends_at_ms": ends_at})]


static func _respond(state: GameStateScript, player_id: int, command: Dictionary) -> Array:
	if state.dose.is_empty() or state.dose["phase"] != OFFERED:
		return [_reject(player_id, "There is no dose on offer.")]
	if player_id != state.dose["patient"]:
		return [_reject(player_id, "Only the patient answers.")]
	var accept = command.get("accept", null)
	if typeof(accept) != TYPE_BOOL:
		return [_reject(player_id, "Accept or reject.")]
	var dose: Dictionary = state.dose
	if not accept:
		_clear(state)
		return [_log(state, "dose_rejected", {"doctor": dose["doctor"], "patient": dose["patient"], "dose": dose["dose"]})]
	var gone: String = _problem_with_people(state, dose)
	if gone != "":
		return _void(state, gone)
	if dose["kind"] == "sicken":
		var problem: String = SicknessScript.problem_sickening(state, dose["patient"])
		if problem != "":
			return _void(state, problem)
	# The patient pays, and the payment is lost whatever the bead says.
	var owed: int = DebtScript.charge(state, dose["patient"], dose["doctor"], dose["price"])
	state.doctor_used[dose["doctor"]] = int(state.doctor_used.get(dose["doctor"], 0)) + 1
	var events: Array = []
	var data: Dictionary = {"doctor": dose["doctor"], "patient": dose["patient"], "dose": dose["dose"], "kind": dose["kind"], "price": dose["price"]}
	if owed > 0:
		data["new_debt"] = owed
	if dose["kind"] == "sicken":
		events.append(_log(state, "dose_accepted", data))
		var rounds: int = _rounds(dose["dose"])
		events.append_array(_log_all(state, SicknessScript.sicken(state, dose["patient"], rounds)))
		_clear(state)
		return events
	var seconds: int = GameDataScript.get_int("doseGuessSeconds")
	var ends_at: int = state.clock_ms + seconds * 1000
	dose["phase"] = GUESSING
	dose["deadline"] = ends_at
	data["seconds"] = seconds
	data["ends_at_ms"] = ends_at
	return [_log(state, "dose_accepted", data)]


static func _guess(state: GameStateScript, player_id: int) -> Array:
	if state.dose.is_empty() or state.dose["phase"] != GUESSING:
		return [_reject(player_id, "Nothing can be guessed now.")]
	if not player_id in state.player_ids or state.eliminated.get(player_id, false):
		return [_reject(player_id, "You are not in the game.")]
	if player_id == state.dose["doctor"]:
		return [_reject(player_id, "The Doctor can't guess.")]
	if state.dose["guesser"] != 0:
		return [_reject(player_id, "Somebody has already guessed Sabotage.")]
	state.dose["guesser"] = player_id
	return [_log(state, "sabotage_guessed", {"guesser": player_id, "doctor": state.dose["doctor"], "patient": state.dose["patient"]})]


# --- the automatic steps -----------------------------------------------------------------

# Time moves a dose on: an offer nobody answered is rejected; when the guessing is over the bead is revealed.
static func step(state: GameStateScript) -> Array:
	if state.dose.is_empty() or state.clock_ms < int(state.dose["deadline"]):
		return []
	var dose: Dictionary = state.dose
	if dose["phase"] == OFFERED:
		_clear(state)
		return [_log(state, "dose_expired", {"doctor": dose["doctor"], "patient": dose["patient"], "dose": dose["dose"]})]
	var gone: String = _problem_with_people(state, dose)
	if gone != "":
		return _void(state, gone)
	return _give(state, dose)


# The bead is revealed and the dose given.
static func _give(state: GameStateScript, dose: Dictionary) -> Array:
	var poison: bool = state.dose_secret.get("poison", false)
	var doctor: int = dose["doctor"]
	var patient: int = dose["patient"]
	var price: int = dose["price"]
	var guesser: int = dose["guesser"]
	if guesser != 0 and (state.eliminated.get(guesser, false) or not guesser in state.player_ids):
		guesser = 0   # a guesser who has left the game made no guess
	var outcome: String = "cure"
	var data: Dictionary = {"doctor": doctor, "patient": patient, "dose": dose["dose"], "price": price, "bead": "red" if poison else "blue", "guesser": guesser}
	var events: Array = []
	var sabotage: bool = false
	if guesser != 0 and poison:
		outcome = "right_guess"
		data["doctor_paid"] = price
		var owed: int = DebtScript.charge(state, doctor, guesser, price)
		if owed > 0:
			data["doctor_new_debt"] = owed
	elif guesser != 0:
		outcome = "wrong_guess"
		data["guesser_paid"] = price
		var owed2: int = DebtScript.charge(state, guesser, doctor, price)
		if owed2 > 0:
			data["guesser_new_debt"] = owed2
	elif poison:
		outcome = "sabotage"
		sabotage = true
	data["outcome"] = outcome
	events.append(_log(state, "dose_given", data))
	_clear(state)
	if sabotage:
		events.append_array(_poison(state, patient, dose["dose"]))
	else:
		events.append_array(_log_all(state, _cure(state, patient, dose["dose"])))
	if outcome == "right_guess":
		events.append_array(_log_all(state, RolesScript.remove(state, doctor, "Doctor")))   # the licence is lost
		events.append(_log(state, "licence_lost", {"doctor": doctor}))
	return events


static func _cure(state: GameStateScript, patient: int, dose: String) -> Array:
	match dose:
		"Surgery":
			return SicknessScript.recover(state, patient)
	return SicknessScript.shorten(state, patient, _rounds(dose))


static func _poison(state: GameStateScript, patient: int, dose: String) -> Array:
	if dose == "Surgery":
		return EliminationScript.eliminate(state, patient, "surgery")   # logs its own events
	return _log_all(state, SicknessScript.lengthen(state, patient, _rounds(dose)))


static func _rounds(dose: String) -> int:
	return GameDataScript.get_int("agboRounds") if dose == "Agbo" else GameDataScript.get_int("concoctionRounds")


# --- helpers -----------------------------------------------------------------------------

# Why the dose can't go ahead because of who is (no longer) in the game, or "".
static func _problem_with_people(state: GameStateScript, dose: Dictionary) -> String:
	for key in ["doctor", "patient"]:
		var id: int = dose[key]
		if not id in state.player_ids or state.eliminated.get(id, false):
			return "the %s left the game" % ("Doctor" if key == "doctor" else "patient")
	if not RolesScript.has(state, dose["doctor"], "Doctor"):
		return "the Doctor is no longer a Doctor"
	return ""


static func _void(state: GameStateScript, reason: String) -> Array:
	var dose: Dictionary = state.dose
	_clear(state)
	return [_log(state, "dose_void", {"doctor": dose["doctor"], "patient": dose["patient"], "dose": dose["dose"], "reason": reason})]


static func _clear(state: GameStateScript) -> void:
	state.dose = {}
	state.dose_secret = {}


static func _log_all(state: GameStateScript, events: Array) -> Array:
	for event in events:
		state.event_log.append(event)
	return events


static func _log(state: GameStateScript, type: String, data: Dictionary) -> Dictionary:
	var event: Dictionary = EventsScript.make(type, data)
	state.event_log.append(event)
	return event


static func _reject(player_id: int, reason: String) -> Dictionary:
	return EventsScript.make("rejected", {"reason": reason}, [player_id])
