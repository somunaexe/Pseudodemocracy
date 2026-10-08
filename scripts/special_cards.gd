class_name SpecialCards

# Cards with a rule of their own (the card data says `special: "name"`). A card applies (apply), may ask the drawer questions
# (answered), may put a question to several players (poll_closed, see Polls), and may leave things behind that other files look at:
# modifiers (Modifiers), payments and penalties for later rounds (Schedule), a card in the hand. Each section below is one card or a
# few that belong together. The rules are in docs/design_decisions.md, section "The remaining cards".
#
# Every event this file creates is logged here, once. (Events of helpers it calls are logged here too.)

const GameStateScript = preload("res://scripts/game_state.gd")
const GameDataScript = preload("res://scripts/game_data.gd")
const CardsScript = preload("res://scripts/cards.gd")
const ChoicesScript = preload("res://scripts/choices.gd")
const PollsScript = preload("res://scripts/polls.gd")
const ModifiersScript = preload("res://scripts/modifiers.gd")
const ScheduleScript = preload("res://scripts/schedule.gd")
const DebtScript = preload("res://scripts/debt.gd")
const PopularityScript = preload("res://scripts/popularity.gd")
const RolesScript = preload("res://scripts/roles.gd")
const PeeksScript = preload("res://scripts/peeks.gd")
const LoyalistsScript = preload("res://scripts/loyalists.gd")
const UnionsScript = preload("res://scripts/unions.gd")
const SicknessScript = preload("res://scripts/sickness.gd")
const RngScript = preload("res://scripts/rng.gd")
const EventsScript = preload("res://scripts/events.gd")

# The names a card may use (the card exporter checks against this list).
const NAMES := [
	"old_boys", "diaspora", "hospital", "flyover", "statue", "levy_cut", "heckler", "youth_wing", "free_settlement", "fundraiser",
	"exam_pass", "salary", "deck_peek", "loan", "halve_loss", "fee_bonus", "vote_with", "reroll", "pop_floor", "petrol", "hero",
	"benefits", "holiday",
]


static func apply(state: GameStateScript, drawer: int, deck: String, card: int, name: String) -> Array:
	match name:
		"old_boys":
			return _ask(state, drawer, deck, card, {"kind": "players", "who": "male", "max": 3, "prompt": "Choose up to 3 men at the table."}, name, 0)
		"diaspora":
			return _diaspora(state, drawer)
		"hospital":
			return _hospital(state, drawer)
		"flyover":
			return _flyover(state, drawer, deck, card)
		"statue":
			return _statue(state, drawer, deck, card)
		"heckler":
			return _ask(state, drawer, deck, card, {"kind": "player", "prompt": "Choose your designated heckler."}, name, 0)
		"free_settlement":
			ModifiersScript.give(state, drawer, "free_settlement", {"rounds": -1, "uses": 1})
			return [_log(state, "modifier_given", {"player": drawer, "name": "free_settlement"})]
		"fundraiser":
			return _fundraiser(state, drawer)
		"exam_pass":
			ModifiersScript.give(state, drawer, "exam_pass", {"rounds": -1, "uses": 1})
			return [_log(state, "modifier_given", {"player": drawer, "name": "exam_pass"})]
		"salary":
			return _salary(state, drawer, deck, card)
		"deck_peek":
			return _deck_peek(state, drawer, deck, card)
		"loan":
			return _ask(state, drawer, deck, card, {"kind": "player", "prompt": "Choose a player to lend you 15 PSD."}, name, 0)
		"halve_loss":
			ModifiersScript.give(state, drawer, "halve_loss", {"starts": 1, "rounds": 1})
			return [_log(state, "modifier_given", {"player": drawer, "name": "halve_loss", "from_round": state.current_round + 1})]
		"fee_bonus":
			return _fee_bonus(state, drawer, deck, card)
		"vote_with":
			return _ask(state, drawer, deck, card, {"kind": "players", "who": "", "max": 2, "prompt": "Choose up to 2 players to vote with you."}, name, 0)
		"reroll":
			ModifiersScript.give(state, drawer, "reroll", {"starts": 1, "rounds": 1, "uses": 1})
			return [_log(state, "modifier_given", {"player": drawer, "name": "reroll", "from_round": state.current_round + 1})]
		"pop_floor":
			ModifiersScript.give(state, drawer, "pop_floor", {"starts": 1, "rounds": 1, "value": PopularityScript.base(state, drawer)})
			return [_log(state, "modifier_given", {"player": drawer, "name": "pop_floor", "value": PopularityScript.base(state, drawer), "from_round": state.current_round + 1})]
		"petrol":
			ScheduleScript.stipend(state, drawer, "treasury", 60, 1, 2)
			return [_log(state, "stipend_set", {"player": drawer, "amount": 60, "rounds": 2})]
		"hero":
			return _hero(state, drawer)
		"benefits":
			ModifiersScript.give(state, drawer, "skip_tax", {"rounds": -1, "uses": 1})
			return [_log(state, "modifier_given", {"player": drawer, "name": "skip_tax"})]
		"holiday":
			return _holiday(state, drawer)
	return []


# --- questions to the drawer -------------------------------------------------------------

static func _ask(state: GameStateScript, drawer: int, deck: String, card: int, spec: Dictionary, name: String, step: int, extra: Dictionary = {}) -> Array:
	var tagged: Dictionary = extra.duplicate()
	tagged["special"] = name
	tagged["step"] = step
	return ChoicesScript.ask(state, drawer, deck, card, spec, -1, tagged)


# The drawer (or whoever was asked) has answered.
static func answered(state: GameStateScript, pending: Dictionary, value: Variant, auto: bool) -> Array:
	var drawer: int = pending.get("subject", pending["player"])
	var data: Dictionary = {"player": pending["player"], "subject": drawer, "deck": pending["deck"], "card": pending["card"], "kind": pending["kind"], "choice": value, "auto": auto, "special": pending["special"], "step": pending["step"]}
	var events: Array = [_log(state, "choice_made", data)]
	match pending["special"]:
		"old_boys":
			events.append_array(PollsScript.open(state, "old_boys", drawer, value, ["Give 50 PSD", "Show a role card", "Refuse (lose 10 popularity)"], 0, {}, "each", pending["deck"], pending["card"]))
		"heckler":
			events.append_array(_heckler(state, value))
		"statue":
			events.append_array(_statue_answered(state, drawer, int(value)))
		"salary":
			events.append_array(_salary_answered(state, drawer, int(value)))
		"loan":
			events.append_array(_loan(state, drawer, int(value)))
		"fee_bonus":
			events.append_array(_fee_answered(state, drawer, str(value)))
		"vote_with":
			events.append_array(PollsScript.open(state, "vote_with", drawer, value, ["Vote with them for the rest of the term", "Refuse (lose 5 popularity)"], 0, {}, "each", pending["deck"], pending["card"]))
		"deck_peek":
			events.append_array(_bury_answered(state, drawer, pending, int(value)))
		"reroll":
			events.append_array(_reroll_answered(state, drawer, pending, value))
	return events


# Every target of a poll has answered (or run out of time): what each answer does.
static func poll_closed(state: GameStateScript, poll: Dictionary, answers: Dictionary) -> Array:
	var drawer: int = poll["drawer"]
	var events: Array = []
	match poll["special"]:
		"old_boys":
			for id in answers:
				match answers[id]:
					0:
						var owed: int = DebtScript.charge(state, id, drawer, 50)
						events.append(_log(state, "old_boys_gave", {"player": id, "drawer": drawer, "amount": 50 - owed, "new_debt": owed}))
					1:
						events.append(_log(state, "old_boys_showed", {"player": id, "drawer": drawer}))
						events.append(_log_private(state, "peek_report", {"target": id, "kind": "coup", "cards": PeeksScript.cards_of(state, id)}, [drawer]))
					2:
						events.append(_pop(state, id, -10, "old_boys_refused"))
		"flyover":
			var share: int = int(poll["data"]["share"])
			for id in answers:
				match answers[id]:
					0:
						var owed: int = DebtScript.charge(state, id, drawer, share)
						events.append(_log(state, "flyover_gave", {"player": id, "drawer": drawer, "amount": share - owed, "new_debt": owed}))
					1:
						var owed2: int = DebtScript.charge(state, id, DebtScript.TREASURY_ID, share)
						events.append(_log(state, "flyover_redirected", {"player": id, "amount": share - owed2, "new_debt": owed2}))
					2:
						events.append(_pop(state, id, -10, "flyover_refused"))
		"vote_with":
			for id in answers:
				if answers[id] == 0:
					events.append_array(_log_all(state, LoyalistsScript.appoint_for_term(state, drawer, id)))
				else:
					events.append(_pop(state, id, -5, "vote_with_refused"))
	return events


# --- the Settlement cards ----------------------------------------------------------------

static func _diaspora(state: GameStateScript, drawer: int) -> Array:
	var paid: int = mini(150, state.treasury)
	state.treasury -= paid
	DebtScript.receive(state, drawer, paid)
	ScheduleScript.stipend(state, drawer, "treasury", 50, 1, -1, true)   # every round after this one, for as long as they stay above 0
	return [_log(state, "diaspora_set", {"player": drawer, "now": paid, "per_round": 50})]


# "You are now a doctor and cut the ribbon on a hospital": the drawer becomes a Doctor if they can, collects 150, and passes 50 on
# to each other Doctor. Three Doctors share the 150 (the drawer counts as one if they are one); each Doctor beyond the third is
# paid 50 out of the drawer's own pocket.
static func _hospital(state: GameStateScript, drawer: int) -> Array:
	var events: Array = []
	if RolesScript.problem_granting(state, drawer, "Doctor") == "":
		events.append_array(_log_all(state, RolesScript.grant(state, drawer, "Doctor")))
	var paid: int = mini(150, state.treasury)
	state.treasury -= paid
	DebtScript.receive(state, drawer, paid)
	var others: Array = RolesScript.holders(state, "Doctor").filter(func(id): return id != drawer and not state.eliminated.get(id, false))
	others.sort()
	var pool_slots: int = 3 - (1 if RolesScript.has(state, drawer, "Doctor") else 0)
	var from_pool: Array = []
	var from_pocket: Array = []
	for i in others.size():
		if i < pool_slots:
			from_pool.append(others[i])
		else:
			from_pocket.append(others[i])
	var owed: int = 0
	for id in from_pool + from_pocket:
		owed += DebtScript.charge(state, drawer, id, 50)
	events.append(_log(state, "hospital_opened", {"player": drawer, "collected": paid, "doctors_paid": from_pool, "doctors_paid_from_pocket": from_pocket, "new_debt": owed}))
	return events


static func _flyover(state: GameStateScript, drawer: int, deck: String, card: int) -> Array:
	var others: Array = state.player_ids.filter(func(id): return id != drawer and not state.eliminated.get(id, false))
	if others.is_empty():
		return []
	var share: int = ceili(200.0 / others.size())
	return PollsScript.open(state, "flyover", drawer, others, ["Give your share (%d PSD) to them" % share, "Pay it to the treasury instead", "Lose 10 popularity instead"], 0, {"share": share}, "each", deck, card)


static func _statue(state: GameStateScript, drawer: int, deck: String, card: int) -> Array:
	if drawer == state.leader_id or state.leader_id == -1:
		return _statue_answered(state, drawer, 1)   # nobody to blackmail: the treasury pays
	return _ask(state, drawer, deck, card, {"kind": "option", "options": [{"label": "Blackmail the Leader: 100 PSD a term from them for 2 terms"}, {"label": "Take 100 PSD a term from the treasury for 2 terms (outs the Leader: -15 popularity)"}]}, "statue", 0)


static func _statue_answered(state: GameStateScript, drawer: int, option: int) -> Array:
	if option == 0:
		ScheduleScript.stipend(state, drawer, "leader", 100, 1, 2)
		return [_log(state, "statue_blackmail", {"player": drawer, "leader": state.leader_id, "amount": 100, "rounds": 2})]
	ScheduleScript.stipend(state, drawer, "treasury", 100, 1, 2)
	var events: Array = [_log(state, "statue_treasury", {"player": drawer, "amount": 100, "rounds": 2})]
	if state.leader_id != -1 and state.leader_id != drawer:
		events.append(_pop(state, state.leader_id, -15, "leader_outed"))
	return events


static func _heckler(state: GameStateScript, chosen: int) -> Array:
	var events: Array = [_log(state, "heckler_named", {"player": chosen})]
	var scandal: int = CardsScript.draw(state, "scandal")
	var card_effects = load("res://scripts/card_effects.gd")   # loaded when needed (CardEffects uses this file)
	events.append_array(card_effects.apply(state, chosen, "scandal", scandal))
	return events


static func _fundraiser(state: GameStateScript, drawer: int) -> Array:
	var backers: int = 0
	var union_id: int = UnionsScript.union_of(state, drawer)
	if union_id != -1:
		backers = state.unions[union_id]["members"].size() - 1
	var paid: int = mini(20 * backers, state.treasury)
	state.treasury -= paid
	DebtScript.receive(state, drawer, paid)
	return [_log(state, "fundraiser", {"player": drawer, "backers": backers, "collected": paid})]


# "Lose 50 PSD or skip your next income if you have a role. Gain 20 popularity."
static func _salary(state: GameStateScript, drawer: int, deck: String, card: int) -> Array:
	var events: Array = [_pop(state, drawer, 20, "salary_cut")]
	if RolesScript.is_civilian(state, drawer):
		events.append_array(_salary_answered(state, drawer, 0))
		return events
	events.append_array(_ask(state, drawer, deck, card, {"kind": "option", "options": [{"label": "Lose 50 PSD"}, {"label": "Skip your next income"}]}, "salary", 0))
	return events


static func _salary_answered(state: GameStateScript, drawer: int, option: int) -> Array:
	if option == 0:
		var owed: int = DebtScript.charge(state, drawer, DebtScript.TREASURY_ID, 50)
		return [_log(state, "salary_paid", {"player": drawer, "amount": 50 - owed, "new_debt": owed})]
	ModifiersScript.give(state, drawer, "skip_income", {"rounds": -1, "uses": 1})
	return [_log(state, "modifier_given", {"player": drawer, "name": "skip_income"})]


# The top card of the Settlement deck and of the Scandal deck, for the drawer's eyes only; they may bury each at the bottom.
static func _deck_peek(state: GameStateScript, drawer: int, deck: String, card: int) -> Array:
	var tops: Dictionary = {}
	for name in ["settlement", "scandal"]:
		tops[name] = CardsScript.top(state, name)
	var events: Array = [_log_private(state, "deck_peek", {"player": drawer, "settlement": tops["settlement"], "scandal": tops["scandal"]}, [drawer])]
	events.append_array(_ask(state, drawer, deck, card, {"kind": "option", "prompt": "The top Settlement card:", "options": [{"label": "Leave it"}, {"label": "Bury it at the bottom"}]}, "deck_peek", 0, {"default": 0}))
	return events


static func _bury_answered(state: GameStateScript, drawer: int, pending: Dictionary, option: int) -> Array:
	var name: String = "settlement" if pending["step"] == 0 else "scandal"
	var events: Array = []
	if option == 1:
		CardsScript.bury_top(state, name)
		events.append(_log(state, "card_buried", {"player": drawer, "deck": name}))
	if pending["step"] == 0:
		events.append_array(_ask(state, drawer, pending["deck"], pending["card"], {"kind": "option", "prompt": "The top Scandal card:", "options": [{"label": "Leave it"}, {"label": "Bury it at the bottom"}]}, "deck_peek", 1, {"default": 0}))
	return events


static func _loan(state: GameStateScript, drawer: int, lender: int) -> Array:
	var owed: int = DebtScript.charge(state, lender, drawer, 15)
	ScheduleScript.repay(state, drawer, lender, 15, 3)
	return [_log(state, "loan_made", {"lender": lender, "borrower": drawer, "amount": 15 - owed, "new_debt": owed, "due_round": state.current_round + 3})]


# "Quietly raise your own Doctor/Lawyer fee by 20 PSD for the next term. If you don't have either role, choose to become one."
static func _fee_bonus(state: GameStateScript, drawer: int, deck: String, card: int) -> Array:
	if RolesScript.has(state, drawer, "Doctor") or RolesScript.has(state, drawer, "Lawyer"):
		return _fee_answered(state, drawer, "")
	var options: Array = []
	for role in ["Doctor", "Lawyer"]:
		if RolesScript.problem_granting(state, drawer, role) == "":
			options.append(role)
	if options.is_empty():
		return [_log(state, "choice_unavailable", {"player": drawer, "deck": deck, "card": card, "kind": "role"})]
	return _ask(state, drawer, deck, card, {"kind": "role", "prompt": "Become a Doctor or a Lawyer."}, "fee_bonus", 0)


static func _fee_answered(state: GameStateScript, drawer: int, role: String) -> Array:
	var events: Array = []
	if role != "" and role in ["Doctor", "Lawyer"] and RolesScript.problem_granting(state, drawer, role) == "":
		events.append_array(_log_all(state, RolesScript.grant(state, drawer, role)))
	if RolesScript.has(state, drawer, "Doctor") or RolesScript.has(state, drawer, "Lawyer"):
		ModifiersScript.give(state, drawer, "fee_bonus", {"starts": 1, "rounds": 1, "amount": 20})
		events.append(_log(state, "modifier_given", {"player": drawer, "name": "fee_bonus", "from_round": state.current_round + 1}))
	return events


static func _hero(state: GameStateScript, drawer: int) -> Array:
	var events: Array = [_pop(state, drawer, 20, "national_hero")]
	ModifiersScript.give(state, drawer, "cancel_shield", {"rounds": 1})
	events.append(_log(state, "modifier_given", {"player": drawer, "name": "cancel_shield"}))
	return events


static func _holiday(state: GameStateScript, drawer: int) -> Array:
	var hit: Array = []
	for id in state.player_ids:
		if id != drawer and not state.eliminated.get(id, false):
			ModifiersScript.give(state, id, "skip_income", {"rounds": -1, "uses": 1})
			hit.append(id)
	return [_log(state, "public_holiday", {"player": drawer, "skipped": hit})]


# "You may reroll one Result card draw next term, once. The first card you picked goes to a player of your choice." The player is
# asked whether to keep the card they drew; if they reroll they name who gets the first card, then draw again for themselves.
static func reroll_offer(state: GameStateScript, drawer: int, deck: String, card: int) -> Array:
	var card_effects = load("res://scripts/card_effects.gd")
	var events: Array = _ask(state, drawer, deck, card, {"kind": "option", "prompt": "Keep the card you drew, or reroll?", "options": [{"label": "Keep it"}, {"label": "Reroll: the first card goes to a player of your choice"}]}, "reroll", 0, {"default": 0})
	if state.choice.is_empty() or state.choice.get("special", "") != "reroll":
		events.append_array(card_effects.apply(state, drawer, deck, card))   # nobody to ask: the card stands
	return events


static func _reroll_answered(state: GameStateScript, drawer: int, pending: Dictionary, value: Variant) -> Array:
	var card_effects = load("res://scripts/card_effects.gd")
	if pending["step"] == 0:
		if int(value) == 0:
			return card_effects.apply(state, drawer, pending["deck"], pending["card"])
		var asked: Array = _ask(state, drawer, pending["deck"], pending["card"], {"kind": "player", "prompt": "Who gets the first card?"}, "reroll", 1)
		if state.choice.is_empty() or state.choice.get("step", 0) != 1:
			asked.append_array(card_effects.apply(state, drawer, pending["deck"], pending["card"]))   # nobody to give it to: keep it
		return asked
	var events: Array = [_log(state, "card_passed_on", {"player": drawer, "to": value, "deck": pending["deck"], "card": pending["card"]})]
	events.append_array(card_effects.apply(state, int(value), pending["deck"], pending["card"]))
	var again: int = CardsScript.draw(state, pending["deck"])
	events.append(_log(state, "card_rerolled", {"player": drawer, "deck": pending["deck"], "card": again, "text": CardsScript.text(pending["deck"], again)}))
	events.append_array(card_effects.apply(state, drawer, pending["deck"], again))
	return events


# --- the kept cards ------------------------------------------------------------------------

# Do the player's kept cards include a card with this special?
static func holds(state: GameStateScript, player_id: int, name: String) -> bool:
	return not hand_index(state, player_id, name) == -1


static func hand_index(state: GameStateScript, player_id: int, name: String) -> int:
	var hand: Array = state.hands.get(player_id, [])
	for i in hand.size():
		if CardsScript.effects(hand[i]["deck"], hand[i]["card"]).get("special", "") == name:
			return i
	return -1


# A player has just got a kept card (drawn or bought): a card for a seat works at once if they are the Leader.
static func refresh(state: GameStateScript, player_id: int) -> Array:
	if player_id == state.leader_id:
		return leader_changed(state, -1, player_id)
	return []


# The Leader seat has changed hands: the card that cuts the levy works for as long as its holder leads, and is gone when they stop.
static func leader_changed(state: GameStateScript, old_leader: int, new_leader: int) -> Array:
	var events: Array = []
	if old_leader != -1 and old_leader != new_leader and ModifiersScript.has(state, old_leader, "levy_cut"):
		ModifiersScript.remove(state, old_leader, "levy_cut")
		events.append(_log(state, "levy_cut_ended", {"player": old_leader}))
	if new_leader != -1 and holds(state, new_leader, "levy_cut"):
		var index: int = hand_index(state, new_leader, "levy_cut")
		state.hands[new_leader].remove_at(index)
		if state.hands[new_leader].is_empty():
			state.hands.erase(new_leader)
		ModifiersScript.give(state, new_leader, "levy_cut", {"rounds": -1})
		events.append(_log(state, "levy_cut_started", {"player": new_leader}))
	return events


# The election is over (the exam and the ballot): "The youth wing backs you" pays 5 popularity to everyone who has never led and was
# seen voting for the holder, then the card is gone, whether the holder won or not.
static func election_over(state: GameStateScript, revealed: Dictionary) -> Array:
	var events: Array = []
	for holder in state.hands.keys():
		var index: int = hand_index(state, holder, "youth_wing")
		if index == -1:
			continue
		var paid: Array = []
		var voters: Array = revealed.keys()
		voters.sort()
		for voter in voters:
			if revealed[voter] == holder and voter != holder and int(state.half_rounds.get(voter, 0)) == 0 and voter != state.leader_id:
				PopularityScript.change_base(state, voter, 5)
				paid.append(voter)
		state.hands[holder].remove_at(index)
		if state.hands[holder].is_empty():
			state.hands.erase(holder)
		events.append(_log(state, "youth_wing_paid", {"holder": holder, "backers": paid}))
	return events


# --- helpers ------------------------------------------------------------------------------

static func _pop(state: GameStateScript, player_id: int, delta: int, kind: String) -> Dictionary:
	var before: int = PopularityScript.effective(state, player_id)
	PopularityScript.change_base(state, player_id, delta)
	return _log(state, kind, {"player": player_id, "popularity": PopularityScript.effective(state, player_id) - before})


static func _log_all(state: GameStateScript, events: Array) -> Array:
	for event in events:
		state.event_log.append(event)
	return events


static func _log(state: GameStateScript, type: String, data: Dictionary) -> Dictionary:
	var event: Dictionary = EventsScript.make(type, data)
	state.event_log.append(event)
	return event


static func _log_private(state: GameStateScript, type: String, data: Dictionary, audience: Array) -> Dictionary:
	var event: Dictionary = EventsScript.make(type, data, audience)
	state.event_log.append(event)
	return event
