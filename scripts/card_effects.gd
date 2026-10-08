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
#   popularity_per_loyalist   more popularity moved for each of the player's Loyalists of a gender (see Loyalists)
#   keys         the keys to the city: take the Leader's role if more popular than them (they become Vice), else become Vice (see Vice)
#   peek_rival   one of the player's rivals (either way), at random, gets a free check of them (see Peeks)
#   defect       one of the player's Loyalists, at random, leaves them
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
#            With who = "loyalist" it is among the players who can become the drawer's Loyalist, and the card can make them
#            one for some rounds (loyalist) and give them a random role card they can hold (target_role).
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
const EffectClockScript = preload("res://scripts/effect_clock.gd")
const PeeksScript = preload("res://scripts/peeks.gd")
const SpecialCardsScript = preload("res://scripts/special_cards.gd")
const ChoicesScript = preload("res://scripts/choices.gd")
const RivalsScript = preload("res://scripts/rivals.gd")
const LoyalistsScript = preload("res://scripts/loyalists.gd")
const ViceScript = preload("res://scripts/vice.gd")
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
		var kept_events: Array = [_log(state, "card_applied", data)]
		kept_events.append_array(SpecialCardsScript.refresh(state, player_id))   # a card for a seat works at once if they hold it
		return kept_events
	if effect.has("special"):
		# A card with a rule of its own (see SpecialCards).
		var special_events: Array = [_log(state, "card_applied", data)]
		special_events.append_array(SpecialCardsScript.apply(state, player_id, deck, card, str(effect["special"])))
		return special_events
	_apply_money(state, player_id, effect, data)
	if effect.has("collect_each"):
		_collect_each(state, player_id, effect["collect_each"], data)
	var extra: Array = _apply_status(state, player_id, effect, data)
	if effect.has("disband"):
		extra.append_array(_disband(state, player_id, data))
	if effect.has("popularity_per_loyalist"):
		var spec: Dictionary = effect["popularity_per_loyalist"]
		var each: int = LoyalistsScript.count_of_gender(state, player_id, str(spec["gender"]))
		var before: int = PopularityScript.effective(state, player_id)
		PopularityScript.change_base(state, player_id, each * int(spec["popularity"]))
		data["loyalists_counted"] = each
		data["popularity"] = data.get("popularity", 0) + PopularityScript.effective(state, player_id) - before
	if effect.has("defect"):
		extra.append_array(LoyalistsScript.defect_one(state, player_id))
	if effect.has("keys"):
		extra.append_array(ViceScript.keys_to_the_city(state, player_id))
	if effect.has("peek_rival"):
		extra.append_array(PeeksScript.grant_to_a_rival(state, player_id, effect["peek_rival"]["kinds"]))
	data["asks_choice"] = effect.has("choose")
	var events: Array = [_log(state, "card_applied", data)]
	events.append_array(_log_all(state, extra))
	if effect.has("choose"):
		events.append_array(ChoicesScript.ask(state, player_id, deck, card, effect["choose"]))
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
		EffectClockScript.began(state, "coup_ban", player_id)
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
	if effect.has("special"):
		return [_reject(player_id, "That card works by itself; it can't be played.")]
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
		events.append_array(ChoicesScript.ask(state, player_id, kept["deck"], kept["card"], effect["choose"]))   # which kind of union?
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
	var problem: String = ChoicesScript.problem_with(pending, value)
	if problem != "":
		return [_reject(player_id, problem)]
	var events: Array = _make_choice(state, pending, value, false)
	events.append_array(ChoicesScript.next(state))
	return events


# The time is up: choose at random for the player. Called from the game loop when the clock passes the
# deadline. Returns [] if there is no choice or time is left.
static func time_out(state: GameStateScript) -> Array:
	if state.choice.is_empty() or state.clock_ms < int(state.choice["deadline"]):
		return []
	var pending: Dictionary = state.choice
	var events: Array = _make_choice(state, pending, ChoicesScript.default_answer(state, pending), true)
	events.append_array(ChoicesScript.next(state))
	return events


static func _make_choice(state: GameStateScript, pending: Dictionary, value: Variant, auto: bool) -> Array:
	var chooser: int = pending["player"]
	var player_id: int = pending.get("subject", chooser)   # whose card it is; the Leader may be the one choosing
	state.choice = {}
	var effect: Dictionary = CardsScript.effects(pending["deck"], pending["card"])
	if pending.has("special"):
		return SpecialCardsScript.answered(state, pending, value, auto)
	if pending.has("parent"):
		return _second_answer(state, pending, value, auto)
	var data: Dictionary = {"player": chooser, "subject": player_id, "deck": pending["deck"], "card": pending["card"], "kind": pending["kind"], "choice": value, "auto": auto}
	var events: Array = []
	var skipped: Array = []
	match pending["kind"]:
		"option":
			var option: Dictionary = effect["choose"]["options"][value]
			if option.has("then"):
				# This option asks a second question (whom to snitch on); nothing happens until it is answered.
				var follow: Array = [_log(state, "choice_made", data)]
				follow.append_array(ChoicesScript.ask(state, player_id, pending["deck"], pending["card"], option["then"], int(value)))
				return follow
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
			if effect.has("target_role"):
				var roles: Array = ChoicesScript.role_candidates(state, value)
				if roles.is_empty():
					skipped.append("a random role: they can't be given one")
				else:
					_gain_role(state, value, str(RngScript.pick(state, roles)), events, skipped)
			if effect.has("loyalist"):
				var why_not: String = LoyalistsScript.problem_appointing(state, player_id, value)
				if why_not != "":
					skipped.append("a Loyalist: " + why_not)
				else:
					events.append_array(LoyalistsScript.appoint(state, player_id, value, int(effect["loyalist"]["rounds"])))
			if effect.has("peek"):
				events.append_array(PeeksScript.grant(state, value, player_id, effect["peek"]["kinds"], bool(effect["peek"]["round_only"])))
			if effect.has("favor"):
				events.append(_favor(state, player_id, value))
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


# "A Secret Agent owes you a favor": if some other player holds the Secret Agent role, the drawer is shown the chosen
# player's role cards (whether each has a coup sticker), in an event only they receive. Not the Agent's once-a-round check.
static func _favor(state: GameStateScript, drawer: int, chosen: int) -> Dictionary:
	var agent: int = 0
	for id in RolesScript.holders(state, "Secret Agent"):
		if id != drawer and not state.eliminated.get(id, false):
			agent = id
			break
	if agent == 0:
		return EventsScript.make("favor_unavailable", {"player": drawer, "reason": "there is no Secret Agent to ask"})
	return EventsScript.make("favor_report", {"player": drawer, "target": chosen, "cards": PeeksScript.cards_of(state, chosen)}, [drawer])


# The second question of an option ("snitch and split"): what the option says happens to the drawer and to the player named.
static func _second_answer(state: GameStateScript, pending: Dictionary, value: Variant, auto: bool) -> Array:
	var player_id: int = pending.get("subject", pending["player"])
	var effect: Dictionary = CardsScript.effects(pending["deck"], pending["card"])
	var each: Dictionary = effect["choose"]["options"][int(pending["parent"])]["each"]
	var data: Dictionary = {"player": pending["player"], "subject": player_id, "deck": pending["deck"], "card": pending["card"], "kind": pending["kind"], "choice": value, "parent": pending["parent"], "auto": auto}
	_apply_money(state, player_id, each, data)
	_apply_money(state, value, each, data, "target_")
	var events: Array = []
	if each.has("marker"):
		events.append_array(CorruptionScript.give(state, player_id))
		events.append_array(CorruptionScript.give(state, value))
	var result: Array = [_log(state, "choice_made", data)]
	for event in events:
		state.event_log.append(event)
		result.append(event)
	return result


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
