extends SceneTree

const GameScript = preload("res://scripts/game.gd")
const GameStateScript = preload("res://scripts/game_state.gd")
const CardsScript = preload("res://scripts/cards.gd")
const CardEffectsScript = preload("res://scripts/card_effects.gd")
const ModifiersScript = preload("res://scripts/modifiers.gd")
const ScheduleScript = preload("res://scripts/schedule.gd")
const RoundEndScript = preload("res://scripts/round_end.gd")
const RolesScript = preload("res://scripts/roles.gd")
const PopularityScript = preload("res://scripts/popularity.gd")
const IncomeScript = preload("res://scripts/income.gd")
const DebtScript = preload("res://scripts/debt.gd")
const ViceScript = preload("res://scripts/vice.gd")
const LoyalistsScript = preload("res://scripts/loyalists.gd")
const SpecialCardsScript = preload("res://scripts/special_cards.gd")
const ViewsScript = preload("res://scripts/views.gd")
const SerializerScript = preload("res://scripts/serializer.gd")
const ElectionScript = preload("res://scripts/election.gd")
const PlayScript = preload("res://tests/play.gd")

const PRESIDENT = GameStateScript.LeaderType.PRESIDENT

var failures: int = 0


func _init() -> void:
	money_cards()
	the_hospital()
	modifier_cards()
	income_cards()
	the_old_boys()
	the_flyover()
	the_statue()
	the_levy_cut()
	selling_a_card()
	the_heckler()
	the_youth_wing()
	free_and_rerolled_cards()
	the_exam_excuse()
	looking_at_the_decks()
	the_loan()
	the_fee()
	voting_with_you()
	print("%d failure(s)" % failures)
	quit(1 if failures > 0 else 0)


# --- simple money -------------------------------------------------------------------------

func money_cards() -> void:
	var s := new_turn()
	var cash: int = s.psd[3]
	var total: int = total_money(s)
	s.popularity[3] = 10
	var ev := apply(s, 3, "A diaspora relative")
	expect("a diaspora relative pays 150 now", [s.psd[3] - cash, types(ev), total_money(s)], [150, ["card_applied", "diaspora_set"], total])
	expect("... and starts 50 a round for as long as the player stays above 0, from the next round", [s.schedule.size(), s.schedule[0]["from"], s.schedule[0]["until"], s.schedule[0]["while_popular"]], [1, s.current_round + 1, -1, true])
	cash = s.psd[3]
	var ended: Array = RoundEndScript.run(s)
	expect("the round it was drawn in pays nothing more", [s.psd[3] - cash, types(ended).has("stipend_paid")], [0, false])
	s.current_round += 1
	ended = RoundEndScript.run(s)
	expect("the next round end pays 50", [s.psd[3] - cash, ended[0]["amount"]], [50, 50])
	s.popularity[3] = 0
	s.current_round += 1
	ended = RoundEndScript.run(s)
	expect("when popularity falls to 0 the money stops for good", [types(ended), s.schedule], [["stipend_stopped"], []])
	s.popularity[3] = 30
	s.current_round += 1
	expect("... and doesn't come back", types(RoundEndScript.run(s)).has("stipend_paid"), false)

	s = new_turn()
	cash = s.psd[3]
	apply(s, 3, "Petrol subsidy windfall")
	var paid: int = 0
	for i in 4:
		s.current_round += 1
		for e in RoundEndScript.run(s):
			if e["type"] == "stipend_paid":
				paid += e["amount"]
	expect("the petrol subsidy pays 60 for the next 2 rounds only", [paid, s.schedule], [120, []])

	s = new_turn()
	cash = s.psd[3]
	var pop: int = PopularityScript.effective(s, 3)
	apply(s, 3, "You're declared a national hero")
	expect("a national hero gains 20 popularity and can't be CANCELLED this term", [PopularityScript.effective(s, 3) - pop, ModifiersScript.active(s, 3, "cancel_shield")], [20, true])
	s.popularity[3] = -50
	expect("... even at -50", [PopularityScript.is_cancelled(s, 3), RolesScript.is_cancelled(s, 3)], [false, false])
	RoundEndScript.run(s)
	s.current_round += 1
	expect("... but not afterwards", PopularityScript.is_cancelled(s, 3), true)

	s = new_turn()
	var holiday := apply(s, 3, "You declared a public holiday")
	expect("a public holiday makes everyone else skip their next income", [holiday[1]["skipped"], ModifiersScript.has(s, 3, "skip_income")], [[1, 2, 4, 5], false])

	s = new_turn()
	var pops: Array = [PopularityScript.effective(s, 3), PopularityScript.effective(s, 4)]
	var treasury: int = s.treasury
	cash = s.psd[3]
	apply(s, 3, "Your appointee turns out to be under investigation. ASK")
	send(s, 3, {"type": "choose", "choice": 4})
	expect("the investigated appointee: both gain 20 popularity and 100 PSD from the treasury", [PopularityScript.effective(s, 3) - pops[0], PopularityScript.effective(s, 4) - pops[1], s.psd[3] - cash, treasury - s.treasury], [20, 20, 100, 200])


func the_hospital() -> void:
	var s := new_turn()
	var cash: int = s.psd[3]
	var total: int = total_money(s)
	var ev := apply(s, 3, "You are now a doctor")
	expect("with no other Doctor the drawer becomes one and keeps all 150", [RolesScript.has(s, 3, "Doctor"), s.psd[3] - cash, ev[1]["type"] == "role_gained"], [true, 150, true])
	s = new_turn()
	RolesScript.grant(s, 4, "Doctor")
	RolesScript.grant(s, 5, "Doctor")
	cash = s.psd[3]
	var c4: int = s.psd[4]
	var c5: int = s.psd[5]
	apply(s, 3, "You are now a doctor")
	expect("two other Doctors take 50 each; the drawer keeps 50", [s.psd[3] - cash, s.psd[4] - c4, s.psd[5] - c5], [50, 50, 50])
	s = new_turn()
	total = total_money(s)
	for id in [1, 2, 4, 5]:
		RolesScript.grant(s, id, "Doctor")
	cash = s.psd[3]
	var before: Dictionary = s.psd.duplicate()
	ev = apply(s, 3, "You are now a doctor")
	var hospital: Dictionary = last_of(s, "hospital_opened")
	expect("with four other Doctors three Doctors share the pool (the drawer is one) and the rest are paid from their own pocket", [hospital["doctors_paid"], hospital["doctors_paid_from_pocket"]], [[1, 2], [4, 5]])
	expect("... each of the four gets 50 and the drawer is 50 down overall", [s.psd[1] - before[1], s.psd[2] - before[2], s.psd[4] - before[4], s.psd[5] - before[5], s.psd[3] - cash], [50, 50, 50, 50, -50])
	expect("... money is conserved", total_money(s), total)
	s = new_turn()
	for id in [1, 2, 4, 5]:
		RolesScript.grant(s, id, "Doctor")
	expect("with four Doctors the fifth card is still there for the drawer", RolesScript.problem_granting(s, 3, "Doctor"), "")


# --- modifiers -----------------------------------------------------------------------------

func modifier_cards() -> void:
	var s := new_turn()
	apply(s, 3, "You survive a scandal unscathed")
	var pop: int = PopularityScript.base(s, 3)
	PopularityScript.change_base(s, 3, -10)
	expect("halving doesn't start until the next round", PopularityScript.base(s, 3), pop - 10)
	RoundEndScript.run(s)
	s.current_round += 1
	PopularityScript.change_base(s, 3, -10)
	expect("next round a loss of 10 is a loss of 5", PopularityScript.base(s, 3), pop - 15)
	PopularityScript.change_base(s, 3, 7)
	expect("... gains are not halved", PopularityScript.base(s, 3), pop - 8)
	RoundEndScript.run(s)
	s.current_round += 1
	PopularityScript.change_base(s, 3, -10)
	expect("it lasts one term only", PopularityScript.base(s, 3), pop - 18)

	s = new_turn()
	s.popularity[3] = 12
	apply(s, 3, "Your popularity floor")
	RoundEndScript.run(s)
	s.current_round += 1
	PopularityScript.change_base(s, 3, 8)   # 20
	PopularityScript.change_base(s, 3, -30)
	expect("the floor keeps popularity from going below what it was when the card was drawn", PopularityScript.base(s, 3), 12)
	s.popularity[3] = 5
	PopularityScript.change_base(s, 3, -3)
	expect("... and never lifts it", PopularityScript.base(s, 3), 2)
	RoundEndScript.run(s)
	s.current_round += 1
	PopularityScript.change_base(s, 3, -30)
	expect("the floor lasts one term", PopularityScript.base(s, 3), -28)


func income_cards() -> void:
	var s := new_turn()
	RolesScript.grant(s, 3, "Doctor")
	apply(s, 3, "You qualified for benefits")
	var cash: int = s.psd[3]
	var ev := IncomeScript.pay(s, 3)
	expect("benefits skip the tax on the next income only", [ev[0]["tax"], ev[0]["net"], ev[0]["paid"]], [0, 70, 70])
	ev = IncomeScript.pay(s, 3)
	expect("... then the tax is back", ev[0]["tax"], 14)

	s = new_turn()
	RolesScript.grant(s, 3, "Doctor")
	apply(s, 3, "You cut your own salary")
	expect("a Civilian just loses 50, a Doctor chooses", [s.choice["kind"], s.choice["labels"]], ["option", ["Lose 50 PSD", "Skip your next income"]])
	cash = s.psd[3]
	send(s, 3, {"type": "choose", "choice": 1})
	ev = IncomeScript.pay(s, 3)
	expect("skipping the next income: nothing is paid, and it's said", [types(ev), s.psd[3] - cash, ModifiersScript.has(s, 3, "skip_income")], [["income_skipped"], 0, false])
	expect("... only once", IncomeScript.pay(s, 3)[0]["type"], "income_paid")


# --- the polls -----------------------------------------------------------------------------

func the_old_boys() -> void:
	var s := new_turn()
	s.genders = {1: "male", 2: "male", 3: "female", 4: "male", 5: "male"}
	apply(s, 3, "The Old Boys")
	expect("the card asks for up to 3 men", [s.choice["kind"], s.choice["candidates"], s.choice["max"]], ["players", [1, 2, 4, 5], 3])
	expect("a woman can't be chosen", send(s, 3, {"type": "choose", "choice": [3]})[0]["type"], "rejected")
	expect("... nor four men", send(s, 3, {"type": "choose", "choice": [1, 2, 4, 5]})[0]["type"], "rejected")
	expect("... nor the same man twice", send(s, 3, {"type": "choose", "choice": [1, 1]})[0]["type"], "rejected")
	var ev := send(s, 3, {"type": "choose", "choice": [1, 4, 5]})
	var poll: Dictionary = s.polls[0]
	expect("the men are asked together", [types(ev), poll["targets"], poll["labels"].size(), poll["default"]], [["choice_made", "poll_opened"], [1, 4, 5], 3, 0])
	var cash: int = s.psd[3]
	var pop5: int = PopularityScript.effective(s, 5)
	expect("a stranger can't answer", send(s, 2, {"type": "poll_answer", "poll": poll["id"], "option": 0})[0]["reason"], "That question isn't for you.")
	expect("a bad option is refused", send(s, 1, {"type": "poll_answer", "poll": poll["id"], "option": 3})[0]["type"], "rejected")
	send(s, 1, {"type": "poll_answer", "poll": poll["id"], "option": 0})
	expect("the answers are secret: others see only who answered", [ViewsScript.state_view(s, 5)["polls"][0]["answered"], ViewsScript.state_view(s, 5)["polls"][0].has("answers"), ViewsScript.state_view(s, 1)["polls"][0]["my_answer"]], [[1], false, 0])
	expect("... a second answer is refused", send(s, 1, {"type": "poll_answer", "poll": poll["id"], "option": 1})[0]["reason"], "You have already answered.")
	send(s, 4, {"type": "poll_answer", "poll": poll["id"], "option": 1})
	ev = send(s, 5, {"type": "poll_answer", "poll": poll["id"], "option": 2})
	expect("the poll closes when the last man answers, and shows everyone's answers", [types(ev).has("poll_closed"), s.polls.size(), last_of(s, "poll_closed")["answers"]], [true, 0, {1: 0, 4: 1, 5: 2}])
	expect("one gave 50 PSD, one showed a role card, one refused and lost 10 popularity", [s.psd[3] - cash, PopularityScript.effective(s, 5) - pop5], [50, -10])
	var report: Dictionary = last_of(s, "peek_report")
	expect("the one who showed a card: the drawer alone sees their role cards", [report["audience"], report["target"], report["cards"]], [[3], 4, [] ])

	s = new_turn()
	s.genders = {1: "male", 2: "male", 3: "female", 4: "male", 5: "male"}
	apply(s, 3, "The Old Boys")
	send(s, 3, {"type": "choose", "choice": [1, 4]})
	cash = s.psd[3]
	GameScript.tick(s, int(s.polls[0]["deadline"]))
	expect("silence gives the 50 PSD (the default), from each", [s.psd[3] - cash, last_of(s, "poll_closed")["silent"]], [100, [1, 4]])
	s = new_turn()
	s.genders = {1: "male", 2: "male", 3: "female", 4: "male", 5: "male"}
	apply(s, 3, "The Old Boys")
	ev = send(s, 3, {"type": "choose", "choice": []})
	expect("choosing nobody ends it", [types(ev), s.polls.size()], [["choice_made"], 0])

	# The drawer's turn waits for the answers.
	s = new_turn()
	s.genders = {1: "male", 2: "female", 3: "male", 4: "male", 5: "male"}
	apply(s, 2, "The Old Boys")
	send(s, 2, {"type": "choose", "choice": [1]})
	s.term["act"]["phase"] = GameStateScript.ActPhase.DONE
	expect("the drawer's turn can't end while the men haven't answered", send(s, 2, {"type": "end_turn"})[0]["reason"], "Wait for the others to answer your question.")


func the_flyover() -> void:
	var s := new_turn()
	var total: int = total_money(s)
	apply(s, 3, "You crowdfunded a new flyover")
	var poll: Dictionary = s.polls[0]
	expect("the 4 others are asked for 50 each", [poll["targets"], poll["data"]["share"]], [[1, 2, 4, 5], 50])
	var cash: int = s.psd[3]
	var c1: int = s.psd[1]
	var c2: int = s.psd[2]
	var pop4: int = PopularityScript.effective(s, 4)
	var treasury: int = s.treasury
	send(s, 1, {"type": "poll_answer", "poll": poll["id"], "option": 0})
	send(s, 2, {"type": "poll_answer", "poll": poll["id"], "option": 1})
	send(s, 4, {"type": "poll_answer", "poll": poll["id"], "option": 2})
	GameScript.tick(s, int(poll["deadline"]))
	expect("give to the drawer, give to the treasury, lose 10 popularity; and the silent one gives", [s.psd[3] - cash, c1 - s.psd[1], c2 - s.psd[2], PopularityScript.effective(s, 4) - pop4], [100, 50, 50, -10])
	expect("... 50 went to the treasury, and money is conserved", [s.treasury - treasury, total_money(s)], [50, total])
	s = new_turn()
	s.player_count = 5
	apply(s, 3, "You crowdfunded a new flyover")
	s.eliminated[5] = true
	expect("an eliminated player isn't waited for", ViewsScript.state_view(s, 1)["polls"].size(), 1)


func voting_with_you() -> void:
	var s := new_turn()
	apply(s, 3, "Choose up to 2 players")
	expect("up to 2 players are asked", [s.choice["kind"], s.choice["max"]], ["players", 2])
	send(s, 3, {"type": "choose", "choice": [4, 5]})
	var poll: Dictionary = s.polls[0]
	var pop5: int = PopularityScript.effective(s, 5)
	send(s, 4, {"type": "poll_answer", "poll": poll["id"], "option": 0})
	send(s, 5, {"type": "poll_answer", "poll": poll["id"], "option": 1})
	expect("one agrees and is a Loyalist for the rest of the term; the other loses 5 popularity", [LoyalistsScript.owner_of(s, 4), LoyalistsScript.owner_of(s, 5), PopularityScript.effective(s, 5) - pop5], [3, 0, -5])
	RoundEndScript.run(s)
	expect("the loyalty ends with the round", LoyalistsScript.owner_of(s, 4), 0)


# --- the statue, the levy and selling cards -------------------------------------------------

func the_statue() -> void:
	var s := new_turn()
	apply(s, 3, "You commissioned a statue")
	expect("the statue asks: blackmail the Leader or take it from the treasury", s.choice["labels"].size(), 2)
	send(s, 3, {"type": "choose", "choice": 0})
	var paid: int = 0
	var leader_before: int = s.psd[2]
	var cash: int = s.psd[3]
	for i in 3:
		s.current_round += 1
		for e in RoundEndScript.run(s):
			if e["type"] == "stipend_paid":
				paid += e["amount"]
	expect("blackmail: the Leader pays 100 a round for 2 rounds", [paid, leader_before - s.psd[2], s.psd[3] - cash], [200, 200, 200])
	s = new_turn()
	apply(s, 3, "You commissioned a statue")
	var pop: int = PopularityScript.effective(s, 2)
	send(s, 3, {"type": "choose", "choice": 1})
	expect("the treasury way: the Leader loses 15 popularity", PopularityScript.effective(s, 2) - pop, -15)
	paid = 0
	var treasury: int = s.treasury
	for i in 3:
		s.current_round += 1
		for e in RoundEndScript.run(s):
			if e["type"] == "stipend_paid":
				paid += e["amount"]
	expect("... and the treasury pays 100 a round for 2 rounds", [paid, treasury - s.treasury], [200, 200])
	s = new_turn()
	var ev := apply(s, 2, "You commissioned a statue")
	expect("the Leader drawing it has nobody to blackmail: the treasury pays and nobody is outed", [s.choice.is_empty(), last_of(s, "statue_treasury").is_empty()], [true, false])


func the_levy_cut() -> void:
	var s := new_turn()
	var card: int = card_number("You have a 25% Levy reduction")
	apply(s, 3, "You have a 25% Levy reduction")
	expect("the levy card is kept, not played", [s.hands[3].size(), send(s, 3, {"type": "play_card", "index": 0})[0]["reason"]], [1, "That card works by itself; it can't be played."])
	expect("... and does nothing while they aren't Leader", ModifiersScript.has(s, 3, "levy_cut"), false)
	# 3 becomes the Leader.
	var ev := SpecialCardsScript.leader_changed(s, 2, 3)
	s.leader_id = 3
	expect("when they become Leader the card starts working and leaves the hand", [types(ev), ModifiersScript.active(s, 3, "levy_cut"), s.hands.has(3)], [["levy_cut_started"], true, false])
	var cash: int = s.psd[3]
	var cash4: int = s.psd[4]
	s.term = {"phase": GameStateScript.TermPhase.INAUGURATION}
	s.windows_used[GameStateScript.AmendWindow.INAUGURATION] = true
	GameScript.tick(s)
	expect("the Leader pays a 25% lower levy: 18 instead of 25 (18.75 rounded down, in the payer's favour); others the full 25", [cash - s.psd[3], cash4 - s.psd[4]], [18, 25])
	ev = SpecialCardsScript.leader_changed(s, 3, 2)
	s.leader_id = 2
	expect("when they lose the seat the reduction ends", [types(ev), ModifiersScript.has(s, 3, "levy_cut")], [["levy_cut_ended"], false])

	# Drawn by the Leader: at once.
	s = new_turn()
	ev = apply(s, 2, "You have a 25% Levy reduction")
	expect("drawn by the sitting Leader it works at once", [ModifiersScript.active(s, 2, "levy_cut"), s.hands.has(2)], [true, false])
	# After a coup or an election.
	s = new_turn()
	apply(s, 4, "You have a 25% Levy reduction")
	s.term = {}
	ElectionScript.install_leader(s, 4, "vote")
	expect("installing the holder as Leader starts it", ModifiersScript.active(s, 4, "levy_cut"), true)
	ElectionScript.install_leader(s, 5, "vote")
	expect("... and installing someone else ends it", ModifiersScript.has(s, 4, "levy_cut"), false)


func selling_a_card() -> void:
	var s := new_turn()
	apply(s, 3, "You have a 25% Levy reduction")
	expect("only your own cards can be sold", send(s, 4, {"type": "sell_card", "index": 0, "buyer": 5, "price": 10})[0]["reason"], "Choose a card in your hand by its number.")
	expect("... to another player in the game", send(s, 3, {"type": "sell_card", "index": 0, "buyer": 3, "price": 10})[0]["reason"], "Choose another player who is in the game.")
	expect("... for a sensible price", send(s, 3, {"type": "sell_card", "index": 0, "buyer": 4, "price": -1})[0]["type"], "rejected")
	var ev := send(s, 3, {"type": "sell_card", "index": 0, "buyer": 4, "price": 200})
	expect("an offer is public and has a clock", [types(ev), ev[0]["ends_at_ms"] > s.clock_ms], [["card_offered"], true])
	expect("one offer at a time", send(s, 3, {"type": "sell_card", "index": 0, "buyer": 5, "price": 1})[0]["reason"], "You already have a card for sale.")
	expect("only the buyer answers", send(s, 5, {"type": "buy_card", "seller": 3, "accept": true})[0]["reason"], "Nobody is selling you a card.")
	var cash3: int = s.psd[3]
	var cash4: int = s.psd[4]
	ev = send(s, 4, {"type": "buy_card", "seller": 3, "accept": true})
	expect("the buyer pays and gets the card", [types(ev)[0], s.psd[3] - cash3, cash4 - s.psd[4], s.hands.has(3), s.hands[4].size()], ["card_sold", 200, 200, false, 1])

	s = new_turn()
	apply(s, 3, "You have a 25% Levy reduction")
	send(s, 3, {"type": "sell_card", "index": 0, "buyer": 2, "price": 0})
	ev = send(s, 2, {"type": "buy_card", "seller": 3, "accept": true})
	expect("sold to the sitting Leader it works at once", [ModifiersScript.active(s, 2, "levy_cut"), types(ev)], [true, ["card_sold", "levy_cut_started"]])

	s = new_turn()
	apply(s, 3, "You have a 25% Levy reduction")
	send(s, 3, {"type": "sell_card", "index": 0, "buyer": 4, "price": 200})
	ev = send(s, 4, {"type": "buy_card", "seller": 3, "accept": false})
	expect("a refusal changes nothing", [types(ev), s.hands[3].size(), s.card_offers], [["card_sale_refused"], 1, {}])
	send(s, 3, {"type": "sell_card", "index": 0, "buyer": 4, "price": 200})
	GameScript.tick(s, int(s.card_offers[3]["deadline"]))
	expect("silence is a refusal", [s.card_offers, s.hands[3].size()], [{}, 1])
	s.psd[1] += s.psd[4] - 50
	s.psd[4] = 50
	send(s, 3, {"type": "sell_card", "index": 0, "buyer": 4, "price": 200})
	ev = send(s, 4, {"type": "buy_card", "seller": 3, "accept": true})
	expect("a buyer who can't pay voids the sale", [types(ev), s.hands[3].size()], [["card_sale_void"], 1])


func the_heckler() -> void:
	var s := new_turn()
	apply(s, 3, "You spoke well at a 20-v-1")
	var ev := send(s, 3, {"type": "choose", "choice": 4})
	expect("the chosen heckler draws a Scandal card for themselves", [types(ev)[0], types(ev)[1], types(ev)[2], ev[2]["player"], ev[2]["deck"]], ["choice_made", "heckler_named", "card_applied", 4, "scandal"])


func the_youth_wing() -> void:
	var s := new_turn()
	apply(s, 3, "The youth wing backs you")
	expect("the card is kept", s.hands[3].size(), 1)
	s.half_rounds[4] = 2   # 4 has led before
	s.leader_id = 2
	var pops: Dictionary = {}
	for id in [1, 2, 4, 5]:
		pops[id] = PopularityScript.effective(s, id)
	var ev := SpecialCardsScript.election_over(s, {1: 3, 4: 3, 5: 2})
	expect("voters who never led and backed the holder get +5; the rest nothing", [PopularityScript.effective(s, 1) - pops[1], PopularityScript.effective(s, 4) - pops[4], PopularityScript.effective(s, 5) - pops[5]], [5, 0, 0])
	expect("... the card is used up", [s.hands.has(3), ev[0]["backers"]], [false, [1]])
	expect("without the card nothing happens", SpecialCardsScript.election_over(s, {1: 3}), [])


# --- cards drawn at results -----------------------------------------------------------------

func free_and_rerolled_cards() -> void:
	var s := new_turn()
	apply(s, 2, "You settled a scandal before the press")
	expect("the free card is waiting", ModifiersScript.active(s, 2, "free_settlement"), true)
	var before: int = count(s.event_log, "free_card")
	send(s, 2, {"type": "finish_performance"})
	for id in [1, 3, 4, 5]:
		send(s, id, {"type": "performance_vote", "good": false})
	expect("a lost vote still earns a free Settlement card (besides the Scandal)", [count(s.event_log, "free_card") - before, last_of(s, "performance_resolved")["deck"]], [1, "scandal"])
	expect("... once", ModifiersScript.has(s, 2, "free_settlement"), false)

	# The reroll.
	s = new_turn()
	apply(s, 2, "You may reroll one Result card")
	expect("not this round", ModifiersScript.active(s, 2, "reroll"), false)
	s = new_turn()
	ModifiersScript.give(s, 2, "reroll", {"rounds": 1, "uses": 1})
	s.decks["scandal"] = [5, 20]   # the top card is 20 (pay 40 PSD)
	send(s, 2, {"type": "finish_performance"})
	for id in [1, 3, 4, 5]:
		send(s, id, {"type": "performance_vote", "good": false})
	expect("with a reroll the player is asked whether to keep the card", [s.choice["labels"], s.choice["special"]], [["Keep it", "Reroll: the first card goes to a player of your choice"], "reroll"])
	send(s, 2, {"type": "choose", "choice": 1})
	expect("rerolling asks who gets the first card", [s.choice["kind"], s.choice["step"]], ["player", 1])
	var cash: int = s.psd[4]
	var cash2: int = s.psd[2]
	send(s, 2, {"type": "choose", "choice": 4})
	expect("the first card goes to that player (who pays its 40 PSD) and the player draws again", [last_of(s, "card_passed_on")["to"], last_of(s, "card_rerolled")["card"], cash - s.psd[4]], [4, 5, 40])
	expect("... the reroll is used up", ModifiersScript.has(s, 2, "reroll"), false)
	s = new_turn()
	ModifiersScript.give(s, 2, "reroll", {"rounds": 1, "uses": 1})
	s.decks["scandal"] = [5, 20]
	send(s, 2, {"type": "finish_performance"})
	for id in [1, 3, 4, 5]:
		send(s, id, {"type": "performance_vote", "good": false})
	var ev := send(s, 2, {"type": "choose", "choice": 0})
	expect("keeping it applies the card that was drawn", [types(ev)[0], types(ev)[1]], ["choice_made", "card_applied"])
	# Timing out keeps it.
	s = new_turn()
	ModifiersScript.give(s, 2, "reroll", {"rounds": 1, "uses": 1})
	send(s, 2, {"type": "finish_performance"})
	for id in [1, 3, 4, 5]:
		send(s, id, {"type": "performance_vote", "good": true})
	GameScript.tick(s, int(s.choice["deadline"]))
	expect("silence keeps the card", [s.choice.is_empty(), count(s.event_log, "card_rerolled")], [true, 0])


func the_exam_excuse() -> void:
	var s := at_exam()
	ModifiersScript.give(s, 3, "exam_pass", {"rounds": -1, "uses": 1})
	var questions: Array = []
	for i in 5:
		questions.append({"text": "Q%d?" % i, "options": ["A", "B", "C"], "answer": 0})
	send(s, 2, {"type": "write_exam", "questions": questions})
	for id in [1, 4, 5]:
		send(s, id, {"type": "answer_exam", "answers": [1, 1, 1, 1, 1]})   # all wrong
	var revealed: Dictionary = last_of(s, "exam_revealed")
	expect("a player excused by the card needn't answer and counts as having passed", [revealed["excused"], revealed["passed"]], [[3], [2, 3]])
	expect("... the card is used up", ModifiersScript.has(s, 3, "exam_pass"), false)


func looking_at_the_decks() -> void:
	var s := new_turn()
	s.decks["settlement"] = [4, 9]
	s.decks["scandal"] = [3, 7]
	apply(s, 3, "You may look at the top card")
	var seen: Dictionary = last_of(s, "deck_peek")
	expect("the drawer privately sees the top of both decks", [seen["audience"], seen["settlement"], seen["scandal"]], [[3], 9, 7])
	send(s, 3, {"type": "choose", "choice": 1})
	expect("burying the top Settlement card puts it at the bottom", [s.decks["settlement"], s.choice["step"]], [[9, 4], 1])
	send(s, 3, {"type": "choose", "choice": 0})
	expect("leaving the Scandal card alone", [s.decks["scandal"], s.choice.is_empty()], [[3, 7], true])
	s = new_turn()
	s.decks["settlement"] = [4, 9]
	apply(s, 3, "You may look at the top card")
	GameScript.tick(s, int(s.choice["deadline"]))
	GameScript.tick(s, int(s.choice["deadline"]))
	expect("silence leaves both cards where they are", [s.decks["settlement"], s.choice.is_empty()], [[4, 9], true])


func the_loan() -> void:
	var s := new_turn()
	var total: int = total_money(s)
	apply(s, 3, "Choose a player — they must lend you")
	send(s, 3, {"type": "choose", "choice": 4})
	var cash3: int = s.psd[3]
	var cash4: int = s.psd[4]
	var repaid: int = 0
	for i in 4:
		s.current_round += 1
		for e in RoundEndScript.run(s):
			if e["type"] == "loan_repaid":
				repaid += 1
				expect("the loan is repaid when its 3 rounds are up", [e["borrower"], e["lender"], e["amount"], s.current_round], [3, 4, 15, 4])
	expect("... exactly once, and money is conserved", [repaid, total_money(s)], [1, total])


func the_fee() -> void:
	var s := new_turn()
	RolesScript.grant(s, 3, "Doctor")
	apply(s, 3, "You quietly raise your own")
	expect("a Doctor just raises the fee (from next round)", [s.choice.is_empty(), ModifiersScript.active(s, 3, "fee_bonus"), ModifiersScript.has(s, 3, "fee_bonus")], [true, false, true])
	s = new_turn()
	apply(s, 3, "You quietly raise your own")
	expect("someone with neither role chooses one to become", [s.choice["kind"], s.choice["candidates"]], ["role", ["Doctor", "Lawyer", "Secret Agent", "Activist", "Agbero"].filter(func(r): return r in s.choice["candidates"])])
	send(s, 3, {"type": "choose", "choice": "Lawyer"})
	expect("... and becomes it, with the fee bonus", [RolesScript.has(s, 3, "Lawyer"), ModifiersScript.has(s, 3, "fee_bonus")], [true, true])


# --- helpers -----------------------------------------------------------------------------

func at_exam() -> GameStateScript:
	var s := new_turn()
	for id in [2, 3, 4, 5, 1]:
		PlayScript.take_turn(s, id)
	GameScript.handle(s, 2, {"type": "pass_window"})
	assert(s.election.get("phase", 0) == GameStateScript.ElectionPhase.EXAM_WRITING, "the Leader should be writing the exam")
	return s


func apply(s: GameStateScript, player: int, prefix: String) -> Array:
	return CardEffectsScript.apply(s, player, "settlement", card_number(prefix))


func card_number(prefix: String) -> int:
	for i in CardsScript.count("settlement"):
		if CardsScript.text("settlement", i).begins_with(prefix):
			return i
	assert(false, "no settlement card begins '%s'" % prefix)
	return -1


func new_turn() -> GameStateScript:
	for seed_value in range(1, 400):
		var s := GameScript.new_game([1, 2, 3, 4, 5], seed_value)
		for id in [1, 2, 3, 4, 5]:
			GameScript.handle(s, id, {"type": "cast_vote", "candidate": 2})
		if s.leader_type == PRESIDENT:
			s.decks["performance"] = [1]   # a plain card
			GameScript.handle(s, 2, {"type": "pass_window"})
			return s
	assert(false, "no seed gave a President")
	return null


func total_money(s: GameStateScript) -> int:
	var total: int = s.treasury
	for id in s.psd:
		total += s.psd[id]
	return total


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
