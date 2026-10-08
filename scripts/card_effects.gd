class_name CardEffects

# What a Settlement or Scandal card does to the player who drew it, for the cards listed in
# data/source/cards.js. Every other card is read out to the table, which carries it out.
#
# Plain effects happen at once:
#   psd > 0   the treasury pays the player (what it has, if it is short); debts are paid first
#   psd < 0   the player pays the treasury; whatever they can't cover becomes debt
#   popularity   moves the base popularity (it stays on the track)
#
# A card with "choose" stops the turn until the player chooses (command "choose", see choose()):
#   option   one of the card's options, each its own psd/popularity
#   role     any role the player can be given; they gain it
#   player   another player in the game (with who = has_role, one who holds a role card). The card
#            can then move the chosen player's popularity (target), swap all roles with them
#            (swap_with) and give the drawer a role (gain_role).
# The pending choice sits in state.term["act"]["choice"]; the turn can't end while it is there.
# The player has choiceSeconds (10) on the server clock. If they let it run out, the server chooses at
# random among the valid answers, with the game's own generator, and says so (auto = true).
# What can't be done any more (a role card that has run out) is skipped and said so in the event.
# Total money never changes.
#
# Every event this file creates is logged here, once.

const GameStateScript = preload("res://scripts/game_state.gd")
const CardsScript = preload("res://scripts/cards.gd")
const DebtScript = preload("res://scripts/debt.gd")
const PopularityScript = preload("res://scripts/popularity.gd")
const RolesScript = preload("res://scripts/roles.gd")
const GameDataScript = preload("res://scripts/game_data.gd")
const RngScript = preload("res://scripts/rng.gd")
const EventsScript = preload("res://scripts/events.gd")


# Apply a drawn card to the player. Returns the events.
static func apply(state: GameStateScript, player_id: int, deck: String, card: int) -> Array:
	var effect: Dictionary = CardsScript.effects(deck, card)
	var data: Dictionary = {"player": player_id, "deck": deck, "card": card, "by_table": effect.is_empty()}
	_apply_money(state, player_id, effect, data)
	data["asks_choice"] = effect.has("choose")
	var events: Array = [_log(state, "card_applied", data)]
	if effect.has("choose"):
		events.append_array(_ask(state, player_id, deck, card, effect["choose"]))
	return events


# psd and popularity, onto the data of the event.
static func _apply_money(state: GameStateScript, player_id: int, effect: Dictionary, data: Dictionary, prefix: String = "") -> void:
	if effect.has("psd"):
		var amount: int = int(effect["psd"])
		if amount > 0:
			var paid: int = mini(amount, state.treasury)
			state.treasury -= paid
			DebtScript.receive(state, player_id, paid)
			data[prefix + "psd"] = paid
			if paid < amount:
				data[prefix + "short"] = amount - paid
		else:
			data[prefix + "psd"] = amount
			var owed: int = DebtScript.charge(state, player_id, DebtScript.TREASURY_ID, -amount)
			if owed > 0:
				data[prefix + "new_debt"] = owed
	if effect.has("popularity"):
		var before: int = PopularityScript.effective(state, player_id)
		PopularityScript.change_base(state, player_id, int(effect["popularity"]))
		data[prefix + "popularity"] = PopularityScript.effective(state, player_id) - before   # what actually changed


# --- asking ------------------------------------------------------------------------------

static func _ask(state: GameStateScript, player_id: int, deck: String, card: int, spec: Dictionary) -> Array:
	var kind: String = spec["kind"]
	var seconds: int = GameDataScript.get_int("choiceSeconds")
	var ends_at: int = state.clock_ms + seconds * 1000
	var pending: Dictionary = {"player": player_id, "deck": deck, "card": card, "kind": kind, "deadline": ends_at}
	var shown: Dictionary = {"player": player_id, "deck": deck, "card": card, "kind": kind, "seconds": seconds, "ends_at_ms": ends_at}
	match kind:
		"option":
			var labels: Array = []
			for option in spec["options"]:
				labels.append(option["label"])
			pending["labels"] = labels
			shown["labels"] = labels
		"role":
			pending["candidates"] = _role_candidates(state, player_id)
			shown["candidates"] = pending["candidates"]
		"player":
			pending["candidates"] = _player_candidates(state, player_id, str(spec.get("who", "")))
			shown["candidates"] = pending["candidates"]
	if pending.has("candidates") and pending["candidates"].is_empty():
		return [_log(state, "choice_unavailable", {"player": player_id, "deck": deck, "card": card, "kind": kind})]
	state.term["act"]["choice"] = pending
	return [_log(state, "choice_needed", shown)]


static func _role_candidates(state: GameStateScript, player_id: int) -> Array:
	var result: Array = []
	for role in RolesScript.names():
		if RolesScript.problem_granting(state, player_id, role) == "":
			result.append(role)
	return result


static func _player_candidates(state: GameStateScript, player_id: int, who: String) -> Array:
	var result: Array = []
	for id in state.player_ids:
		if id == player_id or state.eliminated.get(id, false):
			continue
		if who == "has_role" and RolesScript.is_civilian(state, id):
			continue
		result.append(id)
	return result


# --- choosing ----------------------------------------------------------------------------
#   { "type": "choose", "choice": <an option number, a role name or a player id> }

static func choose(state: GameStateScript, player_id: int, command: Dictionary) -> Array:
	var act: Dictionary = state.term.get("act", {})
	if not act.has("choice"):
		return [_reject(player_id, "There is nothing to choose.")]
	var pending: Dictionary = act["choice"]
	if player_id != pending["player"]:
		return [_reject(player_id, "It isn't your choice.")]
	var value = command.get("choice", null)
	var problem: String = _problem_with(pending, value)
	if problem != "":
		return [_reject(player_id, problem)]
	return _make_choice(state, pending, value, false)


# The time is up: choose at random for the player. Called by the performance when the clock passes the
# deadline. Returns [] if there is no choice or time is left.
static func time_out(state: GameStateScript) -> Array:
	var act: Dictionary = state.term.get("act", {})
	if not act.has("choice") or state.clock_ms < int(act["choice"]["deadline"]):
		return []
	var pending: Dictionary = act["choice"]
	var value: Variant = 0
	match pending["kind"]:
		"option":
			value = RngScript.below(state, pending["labels"].size())
		"role", "player":
			value = RngScript.pick(state, pending["candidates"])
	return _make_choice(state, pending, value, true)


static func _make_choice(state: GameStateScript, pending: Dictionary, value: Variant, auto: bool) -> Array:
	var player_id: int = pending["player"]
	state.term["act"].erase("choice")
	var effect: Dictionary = CardsScript.effects(pending["deck"], pending["card"])
	var data: Dictionary = {"player": player_id, "deck": pending["deck"], "card": pending["card"], "kind": pending["kind"], "choice": value, "auto": auto}
	var events: Array = []
	var skipped: Array = []
	match pending["kind"]:
		"option":
			_apply_money(state, player_id, effect["choose"]["options"][value], data)
		"role":
			_gain_role(state, player_id, str(value), events, skipped)
		"player":
			if effect.has("target"):
				var target_data: Dictionary = {}
				_apply_money(state, value, effect["target"], target_data)
				for key in target_data:
					data["target_" + key] = target_data[key]
			if effect.get("swap_with", "") == "$choice":
				events.append_array(RolesScript.swap(state, player_id, value))
			if effect.has("gain_role"):
				_gain_role(state, player_id, str(effect["gain_role"]), events, skipped)
	if not skipped.is_empty():
		data["skipped"] = skipped
	var result: Array = [_log(state, "choice_made", data)]
	for event in events:
		state.event_log.append(event)   # the role events are logged here, once
		result.append(event)
	return result


# Why this answer is not acceptable, or "" if it is. The answer comes from a client: check its type
# and that it is one of the choices offered. Nothing else about it is trusted.
static func _problem_with(pending: Dictionary, value: Variant) -> String:
	match pending["kind"]:
		"option":
			if typeof(value) != TYPE_INT or value < 0 or value >= pending["labels"].size():
				return "Choose one of the %d options by its number." % pending["labels"].size()
		"role":
			if typeof(value) != TYPE_STRING or not value in pending["candidates"]:
				return "Choose one of: %s." % ", ".join(pending["candidates"])
		"player":
			if typeof(value) != TYPE_INT or not value in pending["candidates"]:
				return "Choose one of the players offered."
	return ""


# Give the drawer a role if they still can; otherwise say why not. (The offer was made when the card
# was drawn, but the last card of a role can't be taken twice.)
static func _gain_role(state: GameStateScript, player_id: int, role: String, events: Array, skipped: Array) -> void:
	var problem: String = RolesScript.problem_granting(state, player_id, role)
	if problem != "":
		skipped.append("gain %s: %s" % [role, problem])
		return
	events.append_array(RolesScript.grant(state, player_id, role))


static func _log(state: GameStateScript, type: String, data: Dictionary) -> Dictionary:
	var event: Dictionary = EventsScript.make(type, data)
	state.event_log.append(event)
	return event


static func _reject(player_id: int, reason: String) -> Dictionary:
	return EventsScript.make("rejected", {"reason": reason}, [player_id])
