class_name CardEffects

# What a Settlement or Scandal card does to the player who drew it, for the cards listed in
# data/source/cards.js. Every other card is read out to the table, which carries it out.
#
# Plain effects happen at once:
#   psd > 0   the treasury pays the player (what it has, if it is short); debts are paid first
#   psd < 0   the player pays the treasury; whatever they can't cover becomes debt
#   popularity   moves the base popularity (it stays on the track)
#
#   sick > 0     the player is sick for that many rounds (unless already sick or immune: skipped, and said)
#   immune > 0   the player can't be sickened for that many rounds
#   no_coup > 0  the player can't attempt a coup for that many rounds
#   collect_each   every other player of a gender pays the drawer an amount (what they can't pay becomes debt)
#   marker       the player gets a corruption marker (see Corruption)
#   disband      the player's union or mob disperses and its other members become the player's rivals (see Rivals)
# A card with "keep" goes into the player's hand instead (state.hands), to be played later with the command
# "play_card" (see play()). The union cards do that: playing one founds a union (see Unions).
# A card with "choose" stops the turn until the player chooses (command "choose", see choose()):
#   option   one of the card's options, each its own psd/popularity
#   role     any role the player can be given; they gain it
#   player   another player in the game (with who = has_role, one who holds a role card). The card
#            can then move the chosen player's popularity (target), swap all roles with them
#            (swap_with), give the drawer a role (gain_role), take money from the drawer for them (pay_chosen, debt if
#            the drawer can't cover it) and give them a corruption marker (target.marker).
#            With who = "rival" the choice is among the drawer's rivals (anyone, if they have none) and the one chosen
#            becomes their rival; the card can then make a truce (the two can't coup each other this round), an accord
#            (if either is couped within some rounds the other loses popularity) or skip the chosen player's next draw.
#   option with chooser "leader"   the Leader chooses, not the drawer: stay quiet, share (the Leader takes half of the card's
#            money from the drawer) or expose (the drawer gets a marker). The drawer's turn waits for it. (Assumed: if the
#            drawer IS the Leader, or the seat is empty, nobody chooses and the drawer keeps it all.)
# The pending choice sits in state.choice; its player's turn can't end while it is there. (A card played from the hand
# can ask for one too, outside any turn.)
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
const SicknessScript = preload("res://scripts/sickness.gd")
const GendersScript = preload("res://scripts/genders.gd")
const UnionsScript = preload("res://scripts/unions.gd")
const CorruptionScript = preload("res://scripts/corruption.gd")
const RivalsScript = preload("res://scripts/rivals.gd")
const RolesScript = preload("res://scripts/roles.gd")
const GameDataScript = preload("res://scripts/game_data.gd")
const RngScript = preload("res://scripts/rng.gd")
const EventsScript = preload("res://scripts/events.gd")


# Apply a drawn card to the player. Returns the events.
static func apply(state: GameStateScript, player_id: int, deck: String, card: int) -> Array:
	var effect: Dictionary = CardsScript.effects(deck, card)
	var data: Dictionary = {"player": player_id, "deck": deck, "card": card, "by_table": effect.is_empty()}
	if effect.has("keep"):
		if not state.hands.has(player_id):
			state.hands[player_id] = []
		state.hands[player_id].append({"deck": deck, "card": card})   # kept to play later; nothing happens yet
		data["kept"] = true
		return [_log(state, "card_applied", data)]
	_apply_money(state, player_id, effect, data)
	if effect.has("collect_each"):
		_collect_each(state, player_id, effect["collect_each"], data)
	var extra: Array = _apply_status(state, player_id, effect, data)
	if effect.has("disband"):
		extra.append_array(_disband(state, player_id, data))
	data["asks_choice"] = effect.has("choose")
	var events: Array = [_log(state, "card_applied", data)]
	events.append_array(_log_all(state, extra))
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


# "Collect 5 PSD from every woman at the table": each other player of that gender pays the drawer.
static func _collect_each(state: GameStateScript, player_id: int, spec: Dictionary, data: Dictionary) -> void:
	var payers: Array = []
	var owing: Dictionary = {}
	var total: int = 0
	for payer in GendersScript.players(state, str(spec["gender"])):
		if payer == player_id:
			continue
		var owed: int = DebtScript.charge(state, payer, player_id, int(spec["amount"]))
		payers.append(payer)
		total += int(spec["amount"]) - owed
		if owed > 0:
			owing[payer] = owed
	data["collected_from"] = payers
	data["collected"] = total   # what was actually paid at once; the rest is debt owed to the drawer
	if not owing.is_empty():
		data["new_debts"] = owing


# sick and immune. Returns the sickness events (not yet logged); a sickness that can't happen is noted in data.
static func _apply_status(state: GameStateScript, player_id: int, effect: Dictionary, data: Dictionary) -> Array:
	var events: Array = []
	if effect.has("sick"):
		var problem: String = SicknessScript.problem_sickening(state, player_id)
		if problem != "":
			data["skipped"] = data.get("skipped", []) + ["sick: " + problem]
		else:
			events.append_array(SicknessScript.sicken(state, player_id, int(effect["sick"])))
			data["sick"] = int(effect["sick"])
	if effect.has("no_coup"):
		state.coup_ban[player_id] = maxi(int(state.coup_ban.get(player_id, 0)), int(effect["no_coup"]))
		data["no_coup"] = int(effect["no_coup"])
	if effect.has("immune"):
		events.append_array(SicknessScript.grant_immunity(state, player_id, int(effect["immune"])))
		data["immune"] = int(effect["immune"])
	if effect.has("marker"):
		events.append_array(CorruptionScript.give(state, player_id))
		data["marker"] = true
	return events


# "Your mob got caught on camera": the union or mob the player is in disperses; the others in it become their rivals.
static func _disband(state: GameStateScript, player_id: int, data: Dictionary) -> Array:
	var union_id: int = UnionsScript.union_of(state, player_id)
	if union_id == -1:
		return []
	var others: Array = state.unions[union_id]["members"].duplicate()
	others.erase(player_id)
	var events: Array = UnionsScript.disperse(state, union_id, "caught on camera")
	for other in others:
		events.append_array(RivalsScript.name_rival(state, player_id, other))
	data["disbanded"] = union_id
	return events


static func _log_all(state: GameStateScript, events: Array) -> Array:
	for event in events:
		state.event_log.append(event)   # events from helpers are logged here, once
	return events


# --- asking ------------------------------------------------------------------------------

static func _ask(state: GameStateScript, player_id: int, deck: String, card: int, spec: Dictionary) -> Array:
	var kind: String = spec["kind"]
	var seconds: int = GameDataScript.get_int("choiceSeconds")
	var ends_at: int = state.clock_ms + seconds * 1000
	var chooser: int = player_id
	if spec.get("chooser", "") == "leader":
		chooser = state.leader_id
		if chooser == player_id or chooser == -1 or state.eliminated.get(chooser, false):
			return [_log(state, "choice_unavailable", {"player": player_id, "deck": deck, "card": card, "kind": kind})]
	var pending: Dictionary = {"player": chooser, "subject": player_id, "deck": deck, "card": card, "kind": kind, "deadline": ends_at}
	var shown: Dictionary = {"player": chooser, "subject": player_id, "deck": deck, "card": card, "kind": kind, "seconds": seconds, "ends_at_ms": ends_at}
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
	state.choice = pending
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
	if who == "rival":
		return RivalsScript.candidates(state, player_id)
	return result


# --- commands ----------------------------------------------------------------------------

static func handle(state: GameStateScript, player_id: int, command: Dictionary) -> Array:
	match str(command.get("type", "")):
		"choose":
			return choose(state, player_id, command)
		"play_card":
			return play(state, player_id, command)
	return [_reject(player_id, "Unknown command.")]


# --- playing a kept card -----------------------------------------------------------------
#   { "type": "play_card", "index": the card's place in your hand, counting from 0 }

static func play(state: GameStateScript, player_id: int, command: Dictionary) -> Array:
	if not player_id in state.player_ids or state.eliminated.get(player_id, false):
		return [_reject(player_id, "You are not in the game.")]
	if not state.choice.is_empty():
		return [_reject(player_id, "Make your choice first.")]
	var hand: Array = state.hands.get(player_id, [])
	var index = command.get("index", null)
	if typeof(index) != TYPE_INT or index < 0 or index >= hand.size():
		return [_reject(player_id, "Choose a card in your hand by its number.")]
	var kept: Dictionary = hand[index]
	var effect: Dictionary = CardsScript.effects(kept["deck"], kept["card"])
	if not effect.has("truce"):   # the other kept cards found a union
		var problem: String = UnionsScript.problem_founding(state, player_id)
		if problem != "":
			return [_reject(player_id, problem)]   # the card stays in the hand
	hand.remove_at(index)
	if hand.is_empty():
		state.hands.erase(player_id)
	var events: Array = [_log(state, "card_played", {"player": player_id, "deck": kept["deck"], "card": kept["card"]})]
	if effect.has("found_union"):
		events.append_array(_log_all(state, UnionsScript.found(state, player_id, effect["found_union"])))
	else:
		events.append_array(_ask(state, player_id, kept["deck"], kept["card"], effect["choose"]))   # which kind of union?
	return events


# --- choosing ----------------------------------------------------------------------------
#   { "type": "choose", "choice": <an option number, a role name or a player id> }

static func choose(state: GameStateScript, player_id: int, command: Dictionary) -> Array:
	if state.choice.is_empty():
		return [_reject(player_id, "There is nothing to choose.")]
	var pending: Dictionary = state.choice
	if player_id != pending["player"]:
		return [_reject(player_id, "It isn't your choice.")]
	var value = command.get("choice", null)
	var problem: String = _problem_with(pending, value)
	if problem != "":
		return [_reject(player_id, problem)]
	return _make_choice(state, pending, value, false)


# The time is up: choose at random for the player. Called from the game loop when the clock passes the
# deadline. Returns [] if there is no choice or time is left.
static func time_out(state: GameStateScript) -> Array:
	if state.choice.is_empty() or state.clock_ms < int(state.choice["deadline"]):
		return []
	var pending: Dictionary = state.choice
	var value: Variant = 0
	match pending["kind"]:
		"option":
			value = RngScript.below(state, pending["labels"].size())
		"role", "player":
			value = RngScript.pick(state, pending["candidates"])
	return _make_choice(state, pending, value, true)


static func _make_choice(state: GameStateScript, pending: Dictionary, value: Variant, auto: bool) -> Array:
	var chooser: int = pending["player"]
	var player_id: int = pending.get("subject", chooser)   # whose card it is; the Leader may be the one choosing
	state.choice = {}
	var effect: Dictionary = CardsScript.effects(pending["deck"], pending["card"])
	var data: Dictionary = {"player": chooser, "subject": player_id, "deck": pending["deck"], "card": pending["card"], "kind": pending["kind"], "choice": value, "auto": auto}
	var events: Array = []
	var skipped: Array = []
	match pending["kind"]:
		"option":
			var option: Dictionary = effect["choose"]["options"][value]
			_apply_money(state, player_id, option, data)
			if option.get("share", "") == "half":
				var half: int = int(effect["psd"]) / 2
				var owed: int = DebtScript.charge(state, player_id, chooser, half)
				data["shared"] = half
				if owed > 0:
					data["new_debt"] = owed
			if option.has("marker"):
				events.append_array(CorruptionScript.give(state, player_id))
			if option.has("found_union"):
				var union_problem: String = UnionsScript.problem_founding(state, player_id)
				if union_problem != "":
					skipped.append("found a union or mob: " + union_problem)
				else:
					events.append_array(UnionsScript.found(state, player_id, option["found_union"]))
		"role":
			_gain_role(state, player_id, str(value), events, skipped)
		"player":
			if effect.has("target"):
				var target_data: Dictionary = {}
				_apply_money(state, value, effect["target"], target_data)
				for key in target_data:
					data["target_" + key] = target_data[key]
				if effect["target"].has("marker"):
					events.append_array(CorruptionScript.give(state, value))
			if effect.get("choose", {}).get("who", "") == "rival":
				events.append_array(RivalsScript.name_rival(state, player_id, value))
			if effect.has("truce"):
				events.append_array(RivalsScript.truce(state, player_id, value))
			if effect.has("accord"):
				events.append_array(RivalsScript.accord(state, player_id, value, int(effect["accord"]["rounds"]), int(effect["accord"]["loss"])))
			if effect.has("skip_draw"):
				events.append_array(RivalsScript.skip_next_draw(state, value))
			if effect.has("pay_chosen"):
				var owes: int = DebtScript.charge(state, player_id, value, int(effect["pay_chosen"]))
				data["paid_to_chosen"] = int(effect["pay_chosen"]) - owes
				if owes > 0:
					data["new_debt"] = owes
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
