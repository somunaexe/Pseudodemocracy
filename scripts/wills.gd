class_name Wills

# Wills and the Lawyer (handbook Part 6, Wills & Inheritance, Articles 26 to 31).
#
#   - A player asks a Lawyer to keep their will. The will names an heir for the PSD and, separately if they
#     like, an heir for the roles (Article 28). They agree a fee (paid once, when the Lawyer signs) and an
#     upkeep (paid to the Lawyer at the end of every round).
#   - "Miss a payment and the will goes on hold. Reactivate it anytime by catching up. Die while it is on
#     hold and the will doesn't count" (Article 27). A payment is missed when the player has less cash than the
#     upkeep; the unpaid upkeep builds up as arrears, and will_catch_up pays them all.
#   - The WILL'S CONTENTS ARE SECRET: only the testator and the Lawyer know the heirs. That a will exists is
#     public. The state holds the whole will (GameState.wills) on the server; a view shows a player their own
#     will, and a Lawyer the wills they keep (see Views).
#   - Heirs cannot refuse (your ruling, which the handbook file predates). Whoever inherits is a Nepo Baby.
#   - The Lawyer reads the will out when its owner is eliminated, so a will whose Lawyer is no longer a Lawyer
#     (eliminated, or lost the role) cannot be carried out and does not count. (Assumed.)
#
# Commands:
#   { "type": "will_propose", "lawyer": id, "psd_heir": id, "role_heir": id or 0 (optional: same as psd_heir),
#     "fee": whole number, "upkeep": whole number }
#   { "type": "will_respond", "testator": id, "accept": bool }       the Lawyer (several players may have asked them)
#   { "type": "will_catch_up" }                       pay the arrears and reactivate
#   { "type": "will_revoke" }                         tear the will up (nothing is refunded)
#
# Events about a will's terms go only to the testator and the Lawyer. Every event this file creates is logged
# here, once, except end_of_round, whose events (like Sickness) the caller logs.

const GameStateScript = preload("res://scripts/game_state.gd")
const GameDataScript = preload("res://scripts/game_data.gd")
const DebtScript = preload("res://scripts/debt.gd")
const RolesScript = preload("res://scripts/roles.gd")
const EventsScript = preload("res://scripts/events.gd")


# --- commands ----------------------------------------------------------------------------

static func handle(state: GameStateScript, player_id: int, command: Dictionary) -> Array:
	match str(command.get("type", "")):
		"will_propose":
			return _propose(state, player_id, command)
		"will_respond":
			return _respond(state, player_id, command)
		"will_catch_up":
			return _catch_up(state, player_id)
		"will_revoke":
			return _revoke(state, player_id)
	return [_reject(player_id, "Unknown command.")]


static func _propose(state: GameStateScript, testator: int, command: Dictionary) -> Array:
	if not testator in state.player_ids or state.eliminated.get(testator, false):
		return [_reject(testator, "You are not in the game.")]
	if state.will_offers.has(testator):
		return [_reject(testator, "You already have a will waiting for a Lawyer.")]
	var lawyer = command.get("lawyer", null)
	if typeof(lawyer) != TYPE_INT or not lawyer in state.player_ids or state.eliminated.get(lawyer, false):
		return [_reject(testator, "Choose a Lawyer who is in the game.")]
	if lawyer == testator:
		return [_reject(testator, "You can't be your own Lawyer.")]
	if not RolesScript.has(state, lawyer, "Lawyer"):
		return [_reject(testator, "That player is not a Lawyer.")]
	var psd_heir = command.get("psd_heir", null)
	var problem: String = _heir_problem(state, testator, psd_heir, false)
	if problem != "":
		return [_reject(testator, problem)]
	var role_heir = psd_heir
	if command.has("role_heir"):
		role_heir = command["role_heir"]
		problem = _heir_problem(state, testator, role_heir, true)
		if problem != "":
			return [_reject(testator, problem)]
	var maximum: int = GameDataScript.get_int("willPriceMax")
	for key in ["fee", "upkeep"]:
		var value = command.get(key, null)
		if typeof(value) != TYPE_INT or value < 0 or value > maximum:
			return [_reject(testator, "The %s must be a whole number from 0 to %d." % [key, maximum])]
	var seconds: int = GameDataScript.get_int("willOfferSeconds")
	var ends_at: int = state.clock_ms + seconds * 1000
	state.will_offers[testator] = {"lawyer": lawyer, "psd_heir": psd_heir, "role_heir": role_heir, "fee": command["fee"], "upkeep": command["upkeep"], "deadline": ends_at}
	return [_log(state, "will_proposed", {"testator": testator, "lawyer": lawyer, "fee": command["fee"], "upkeep": command["upkeep"], "seconds": seconds, "ends_at_ms": ends_at}, [testator, lawyer])]


# The Lawyer answers. The player who is asked is found from the offers: a Lawyer may be asked by several.
static func _respond(state: GameStateScript, lawyer: int, command: Dictionary) -> Array:
	var testator = command.get("testator", null)
	if typeof(testator) != TYPE_INT or not state.will_offers.has(testator) or state.will_offers[testator]["lawyer"] != lawyer:
		return [_reject(lawyer, "There is no will waiting for you from that player.")]
	var accept = command.get("accept", null)
	if typeof(accept) != TYPE_BOOL:
		return [_reject(lawyer, "Accept or reject.")]
	var offer: Dictionary = state.will_offers[testator]
	if not accept:
		state.will_offers.erase(testator)
		return [_log(state, "will_refused", {"testator": testator, "lawyer": lawyer}, [testator, lawyer])]
	var gone: String = _problem_with_people(state, testator, lawyer)
	if gone != "":
		state.will_offers.erase(testator)
		return [_log(state, "will_void", {"testator": testator, "lawyer": lawyer, "reason": gone}, [testator, lawyer])]
	var power: String = RolesScript.can_use_pledge(state, lawyer, "Lawyer")
	if power != "":
		return [_reject(lawyer, power)]
	# Signed: the fee is paid now; a new will replaces the old one.
	state.will_offers.erase(testator)
	var owed: int = DebtScript.charge(state, testator, lawyer, offer["fee"])
	state.wills[testator] = {"psd_heir": offer["psd_heir"], "role_heir": offer["role_heir"], "on_hold": false, "lawyer": lawyer, "upkeep": offer["upkeep"], "arrears": 0}
	var terms: Dictionary = {"testator": testator, "lawyer": lawyer, "fee": offer["fee"], "upkeep": offer["upkeep"], "psd_heir": offer["psd_heir"], "role_heir": offer["role_heir"]}
	if owed > 0:
		terms["new_debt"] = owed
	return [_log(state, "will_signed", {"testator": testator, "lawyer": lawyer}, []),   # that a will exists is public
			_log(state, "will_terms", terms, [testator, lawyer])]                        # what is in it is not


static func _catch_up(state: GameStateScript, testator: int) -> Array:
	var will: Dictionary = state.wills.get(testator, {})
	if will.is_empty() or not will.get("on_hold", false):
		return [_reject(testator, "You have no will on hold.")]
	var arrears: int = int(will["arrears"])
	if int(state.psd.get(testator, 0)) < arrears:
		return [_reject(testator, "You need %d PSD in hand to catch up." % arrears)]
	DebtScript.charge(state, testator, will["lawyer"], arrears)
	will["on_hold"] = false
	will["arrears"] = 0
	return [_log(state, "will_reactivated", {"testator": testator, "lawyer": will["lawyer"], "paid": arrears}, [testator, will["lawyer"]])]


static func _revoke(state: GameStateScript, testator: int) -> Array:
	if not state.wills.has(testator):
		return [_reject(testator, "You have no will.")]
	var lawyer: int = state.wills[testator].get("lawyer", 0)
	state.wills.erase(testator)
	return [_log(state, "will_revoked", {"testator": testator, "lawyer": lawyer}, [testator, lawyer] if lawyer != 0 else [testator])]


# --- the automatic steps -----------------------------------------------------------------

# A will nobody signed in time is refused.
static func step(state: GameStateScript) -> Array:
	var events: Array = []
	var waiting: Array = state.will_offers.keys()
	waiting.sort()
	for testator in waiting:
		var offer: Dictionary = state.will_offers[testator]
		if state.clock_ms >= int(offer["deadline"]):
			state.will_offers.erase(testator)
			events.append(_log(state, "will_expired", {"testator": testator, "lawyer": offer["lawyer"]}, [testator, offer["lawyer"]]))
	return events


# A round is over: every will is charged its upkeep. A player who can't pay in full misses the payment: the
# will goes on hold and the upkeep builds up as arrears. Returns the events; the caller logs them.
static func end_of_round(state: GameStateScript) -> Array:
	var events: Array = []
	var testators: Array = state.wills.keys()
	testators.sort()
	for testator in testators:
		var will: Dictionary = state.wills[testator]
		var upkeep: int = int(will.get("upkeep", 0))
		var lawyer: int = int(will.get("lawyer", 0))
		if upkeep <= 0 or lawyer == 0 or not is_kept(state, will):
			continue   # nobody to pay, or nothing to pay
		var audience: Array = [testator, lawyer]
		if will["on_hold"]:
			will["arrears"] = int(will["arrears"]) + upkeep
		elif int(state.psd.get(testator, 0)) >= upkeep:
			DebtScript.charge(state, testator, lawyer, upkeep)
			events.append(EventsScript.make("will_upkeep_paid", {"testator": testator, "lawyer": lawyer, "amount": upkeep}, audience))
		else:
			will["on_hold"] = true
			will["arrears"] = upkeep
			events.append(EventsScript.make("will_on_hold", {"testator": testator, "lawyer": lawyer, "arrears": upkeep}, audience))
	return events


# --- who keeps what ----------------------------------------------------------------------

# Is the Lawyer who keeps this will still able to carry it out? A will with no Lawyer recorded (older
# saves, hand-made test wills) counts as kept.
static func is_kept(state: GameStateScript, will: Dictionary) -> bool:
	if not will.has("lawyer"):
		return true
	var lawyer: int = int(will["lawyer"])
	return lawyer in state.player_ids and not state.eliminated.get(lawyer, false) and RolesScript.has(state, lawyer, "Lawyer")


# The wills this Lawyer keeps: testator id -> the will. For the Lawyer's own view.
static func kept_by(state: GameStateScript, lawyer: int) -> Dictionary:
	var result: Dictionary = {}
	for testator in state.wills:
		if int(state.wills[testator].get("lawyer", 0)) == lawyer:
			result[testator] = state.wills[testator].duplicate(true)
	return result


# --- helpers -----------------------------------------------------------------------------

static func _heir_problem(state: GameStateScript, testator: int, heir: Variant, nobody_ok: bool) -> String:
	if typeof(heir) != TYPE_INT:
		return "Name an heir by their player number."
	if heir == 0 and nobody_ok:
		return ""
	if not heir in state.player_ids or state.eliminated.get(heir, false):
		return "That heir is not in the game."
	if heir == testator:
		return "You can't be your own heir."
	return ""


static func _problem_with_people(state: GameStateScript, testator: int, lawyer: int) -> String:
	if not testator in state.player_ids or state.eliminated.get(testator, false):
		return "the testator left the game"
	if not lawyer in state.player_ids or state.eliminated.get(lawyer, false) or not RolesScript.has(state, lawyer, "Lawyer"):
		return "the Lawyer is no longer a Lawyer"
	return ""


static func _log(state: GameStateScript, type: String, data: Dictionary, audience: Array) -> Dictionary:
	var event: Dictionary = EventsScript.make(type, data, audience)
	state.event_log.append(event)
	return event


static func _reject(player_id: int, reason: String) -> Dictionary:
	return EventsScript.make("rejected", {"reason": reason}, [player_id])
