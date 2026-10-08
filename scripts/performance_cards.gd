class_name PerformanceCards

# Performance cards with a consequence beyond the table's vote (the card data says `special`). A performance is acted out and the table
# votes Good or Bad as usual (see PerformanceTurn); these cards also involve other players or money. The rest of the Performance deck is
# pure acting, judged by the table's vote alone, which already decides the Settlement or Scandal card.
#
#   sell_product        the performer chooses a buyer and a price; the buyer is asked (a poll) whether to buy: they pay the price
#   neighbour_dispute   against the player to the performer's right: the Leader decides who is telling the truth, the winner gets 100 PSD from the loser
#   custody             against the 4th player of the round: the Leader judges: the winner gets 150 PSD (treasury), the loser pays 50 PSD costs
#   loan_pitch          the performer chooses a lender, who chooses the interest (0%, 10%, 25%, 50% or refusing) and lends 200 PSD, repaid with interest in 3 rounds
#   fraud               believed (a Good vote): +10 popularity; not (a Bad vote): -15
#   mediation           the performer chooses two players; if the table votes Good both pay them 25 PSD
#   pitch_union         the performer's union or mob invites a player who is in none (they answer union_respond)
#   word_wrestle        against a chosen player: whoever concedes first (concede) loses 20 PSD to the treasury
#   excuse              a Good vote excuses the performer from their next exam
# Where the Leader would judge and is one of the two (or there is none) the table's vote decides instead: Good means the performer wins.
# The state of the card is in state.term["act"]["card_data"]. Every event this file creates is logged here, once.

const GameStateScript = preload("res://scripts/game_state.gd")
const GameDataScript = preload("res://scripts/game_data.gd")
const ChoicesScript = preload("res://scripts/choices.gd")
const PollsScript = preload("res://scripts/polls.gd")
const SeatsScript = preload("res://scripts/seats.gd")
const DebtScript = preload("res://scripts/debt.gd")
const ScheduleScript = preload("res://scripts/schedule.gd")
const ModifiersScript = preload("res://scripts/modifiers.gd")
const PopularityScript = preload("res://scripts/popularity.gd")
const UnionsScript = preload("res://scripts/unions.gd")
const EventsScript = preload("res://scripts/events.gd")

const NAMES := ["sell_product", "neighbour_dispute", "custody", "loan_pitch", "fraud", "mediation", "pitch_union", "word_wrestle", "excuse"]
const LOAN_RATES := [0, 10, 25, 50]
const PRICE_MAX := 500


# --- the performance begins ---------------------------------------------------------------------

static func started(state: GameStateScript, performer: int, name: String) -> Array:
	var act: Dictionary = state.term["act"]
	act["special"] = name
	act["card_data"] = {}
	match name:
		"sell_product":
			return _ask(state, performer, {"kind": "player", "prompt": "Choose the player you will sell your product to."}, name, 0)
		"neighbour_dispute":
			var opponent: int = SeatsScript.neighbour(state, performer, -1)
			act["card_data"]["opponent"] = opponent
			return [_log(state, "dispute_started", {"player": performer, "opponent": opponent, "stake": 100})]
		"custody":
			var order: Array = state.term.get("played", []) + state.term.get("waiting", [])
			var opponent2: int = order[3] if order.size() > 3 else 0
			if opponent2 == performer:
				opponent2 = order[0]
			act["card_data"]["opponent"] = opponent2
			return [_log(state, "dispute_started", {"player": performer, "opponent": opponent2, "stake": 150})]
		"loan_pitch":
			return _ask(state, performer, {"kind": "player", "prompt": "Choose the player you will ask for 200 PSD."}, name, 0)
		"mediation":
			return _ask(state, performer, {"kind": "players", "who": "", "max": 2, "prompt": "Choose the two players whose dispute you will mediate."}, name, 0)
		"pitch_union":
			var union_id: int = UnionsScript.union_of(state, performer)
			if union_id == -1:
				return [_log(state, "union_pitch_unavailable", {"player": performer, "reason": "they are in no union or mob"})]
			return _ask(state, performer, {"kind": "player", "who": "unaffiliated", "prompt": "Choose a player in no union or mob to pitch to."}, name, 0)
		"word_wrestle":
			return _ask(state, performer, {"kind": "player", "prompt": "Choose the player you challenge."}, name, 0)
	return []


# The performer says they are done: the table is about to vote. Where the Leader judges a dispute, they are asked now.
static func finished(state: GameStateScript, act: Dictionary) -> Array:
	var name: String = act.get("special", "")
	if name in ["neighbour_dispute", "custody"]:
		var opponent: int = int(act["card_data"].get("opponent", 0))
		var judge: int = state.leader_id
		if opponent == 0 or judge == -1 or judge == act["player"] or judge == opponent or state.eliminated.get(judge, false):
			return []   # no judge: the table's vote decides
		act["card_data"]["judged"] = true
		return _ask(state, act["player"], {"kind": "option", "chooser": "leader", "prompt": "Who is telling the truth?", "options": [{"label": "The performer"}, {"label": "The other player"}]}, name, 1, {"default": 0})
	return []


# The vote is counted. outcome: "good", "bad" or "tie".
static func resolved(state: GameStateScript, act: Dictionary, outcome: String) -> Array:
	var performer: int = act["player"]
	var name: String = act.get("special", "")
	match name:
		"fraud":
			if outcome == "good":
				return [_pop(state, performer, 10, "fraud_believed")]
			if outcome == "bad":
				return [_pop(state, performer, -15, "fraud_disbelieved")]
		"mediation":
			var mediated: Array = act["card_data"].get("mediated", [])
			if outcome == "good" and mediated.size() == 2:
				var events: Array = []
				for id in mediated:
					var owed: int = DebtScript.charge(state, id, performer, 25)
					events.append(_log(state, "mediation_paid", {"player": id, "mediator": performer, "amount": 25 - owed, "new_debt": owed}))
				return events
		"excuse":
			if outcome == "good":
				ModifiersScript.give(state, performer, "exam_pass", {"rounds": -1, "uses": 1})
				return [_log(state, "modifier_given", {"player": performer, "name": "exam_pass"})]
		"neighbour_dispute", "custody":
			if not act["card_data"].get("judged", false) and act["card_data"].get("opponent", 0) != 0 and outcome != "tie":
				return _settle_dispute(state, name, performer, int(act["card_data"]["opponent"]), outcome == "good")
	return []


# --- answers -------------------------------------------------------------------------------------

static func answered(state: GameStateScript, pending: Dictionary, value: Variant, auto: bool) -> Array:
	var performer: int = pending.get("subject", pending["player"])
	var name: String = pending["special"]
	var data: Dictionary = {"player": pending["player"], "subject": performer, "deck": pending["deck"], "card": pending["card"], "kind": pending["kind"], "choice": value, "auto": auto, "special": name, "step": pending["step"]}
	var events: Array = [_log(state, "choice_made", data)]
	var act: Dictionary = state.term.get("act", {})
	match name:
		"sell_product":
			if pending["step"] == 0:
				act["card_data"]["buyer"] = value
				events.append_array(_ask(state, performer, {"kind": "number", "min": 0, "max": PRICE_MAX, "prompt": "Name your price."}, name, 1, {"default": 100}))
			else:
				var price: int = int(value)
				events.append_array(PollsScript.open(state, "sell_product", performer, [int(act["card_data"]["buyer"])], ["Buy it for %d PSD" % price, "Refuse"], 1, {"price": price}, "each", pending["deck"], pending["card"]))
		"neighbour_dispute", "custody":
			var opponent: int = int(act["card_data"].get("opponent", 0))
			events.append_array(_settle_dispute(state, name, performer, opponent, int(value) == 0))
		"loan_pitch":
			act["card_data"]["lender"] = value
			var labels: Array = []
			for rate in LOAN_RATES:
				labels.append("Lend 200 PSD at %d%% interest" % rate)
			labels.append("Refuse")
			events.append_array(PollsScript.open(state, "loan_pitch", performer, [int(value)], labels, LOAN_RATES.size(), {}, "each", pending["deck"], pending["card"]))
		"mediation":
			act["card_data"]["mediated"] = value if (typeof(value) == TYPE_ARRAY and value.size() == 2) else []
		"pitch_union":
			var union_id: int = UnionsScript.union_of(state, performer)
			for event in UnionsScript.invite(state, union_id, performer, int(value)):
				state.event_log.append(event)
				events.append(event)
		"word_wrestle":
			act["card_data"]["opponent"] = value
			events.append(_log(state, "wrestle_started", {"player": performer, "opponent": value, "stake": 20}))
	return events


static func poll_closed(state: GameStateScript, poll: Dictionary, answers: Dictionary) -> Array:
	var performer: int = poll["drawer"]
	match poll["special"]:
		"sell_product":
			var buyer: int = poll["targets"][0]
			if answers.get(buyer, 1) == 0:
				var owed: int = DebtScript.charge(state, buyer, performer, int(poll["data"]["price"]))
				return [_log(state, "product_sold", {"seller": performer, "buyer": buyer, "price": poll["data"]["price"], "new_debt": owed})]
			return [_log(state, "product_refused", {"seller": performer, "buyer": buyer})]
		"loan_pitch":
			var lender: int = poll["targets"][0]
			var option: int = int(answers.get(lender, LOAN_RATES.size()))
			if option >= LOAN_RATES.size():
				return [_log(state, "loan_refused", {"borrower": performer, "lender": lender})]
			if int(state.psd.get(lender, 0)) < 200:
				return [_log(state, "loan_void", {"borrower": performer, "lender": lender, "reason": "the lender hasn't 200 PSD in hand"})]
			var rate: int = LOAN_RATES[option]
			var repay: int = 200 + 200 * rate / 100
			DebtScript.charge(state, lender, performer, 200)
			ScheduleScript.repay(state, performer, lender, repay, 3)
			return [_log(state, "loan_agreed", {"borrower": performer, "lender": lender, "interest": rate, "repay": repay, "due_round": state.current_round + 3})]
	return []


# --- the command ---------------------------------------------------------------------------------

#   { "type": "concede" }   in a word wrestle, either of the two gives in: they lose 20 PSD to the treasury
static func handle(state: GameStateScript, player_id: int, command: Dictionary) -> Array:
	var act: Dictionary = state.term.get("act", {})
	if act.is_empty() or act.get("special", "") != "word_wrestle" or act["phase"] != GameStateScript.ActPhase.PERFORMING:
		return [_reject(player_id, "There is nothing to concede.")]
	var opponent: int = int(act["card_data"].get("opponent", 0))
	if opponent == 0 or not player_id in [act["player"], opponent]:
		return [_reject(player_id, "You aren't in this contest.")]
	if act["card_data"].get("conceded", false):
		return [_reject(player_id, "It is already over.")]
	act["card_data"]["conceded"] = true
	var owed: int = DebtScript.charge(state, player_id, DebtScript.TREASURY_ID, 20)
	return [_log(state, "conceded", {"player": player_id, "paid": 20 - owed, "new_debt": owed})]


# --- helpers ---------------------------------------------------------------------------------------

static func _settle_dispute(state: GameStateScript, name: String, performer: int, opponent: int, performer_wins: bool) -> Array:
	var winner: int = performer if performer_wins else opponent
	var loser: int = opponent if performer_wins else performer
	var events: Array = []
	if name == "neighbour_dispute":
		var owed: int = DebtScript.charge(state, loser, winner, 100)
		events.append(_log(state, "dispute_settled", {"winner": winner, "loser": loser, "amount": 100 - owed, "new_debt": owed}))
		return events
	var paid: int = mini(150, state.treasury)
	state.treasury -= paid
	DebtScript.receive(state, winner, paid)
	var costs: int = DebtScript.charge(state, loser, DebtScript.TREASURY_ID, 50)
	events.append(_log(state, "dispute_settled", {"winner": winner, "loser": loser, "amount": paid, "costs": 50 - costs, "new_debt": costs}))
	return events


static func _ask(state: GameStateScript, performer: int, spec: Dictionary, name: String, step: int, extra: Dictionary = {}) -> Array:
	var tagged: Dictionary = extra.duplicate()
	tagged["special"] = name
	tagged["step"] = step
	return ChoicesScript.ask(state, performer, "performance", int(state.term["act"]["card"]), spec, -1, tagged)


static func _pop(state: GameStateScript, player_id: int, delta: int, kind: String) -> Dictionary:
	var before: int = PopularityScript.effective(state, player_id)
	PopularityScript.change_base(state, player_id, delta)
	return _log(state, kind, {"player": player_id, "popularity": PopularityScript.effective(state, player_id) - before})


static func _log(state: GameStateScript, type: String, data: Dictionary) -> Dictionary:
	var event: Dictionary = EventsScript.make(type, data)
	state.event_log.append(event)
	return event


static func _reject(player_id: int, reason: String) -> Dictionary:
	return EventsScript.make("rejected", {"reason": reason}, [player_id])
