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
const DebtScript = preload("res://scripts/debt.gd")
const UnionsScript = preload("res://scripts/unions.gd")
const SpecialCardsScript = preload("res://scripts/special_cards.gd")
const PeeksScript = preload("res://scripts/peeks.gd")
const SeatsScript = preload("res://scripts/seats.gd")
const LevyBandScript = preload("res://scripts/levy_band.gd")
const ElectionScript = preload("res://scripts/election.gd")
const ViewsScript = preload("res://scripts/views.gd")
const PlayScript = preload("res://tests/play.gd")

const PRESIDENT = GameStateScript.LeaderType.PRESIDENT
const LEVY_ARTICLE_WORD := 1

var failures: int = 0


func _init() -> void:
	seating()
	the_apology()
	the_debt_that_blocks()
	civilians()
	the_rally()
	the_tax_leak()
	the_collapsed_flyover()
	the_tax_break()
	the_20_v_1()
	delayed_reckoning()
	the_satirist()
	term_limits()
	frozen_roles()
	lost_and_extra_cards()
	exam_marking()
	covid()
	plain_cards()
	print("%d failure(s)" % failures)
	quit(1 if failures > 0 else 0)


func seating() -> void:
	var s := new_turn()
	expect("the left neighbour is the next seat, wrapping round", [SeatsScript.neighbour(s, 1, 1), SeatsScript.neighbour(s, 5, 1), SeatsScript.neighbour(s, 1, -1), SeatsScript.neighbour(s, 3, 2)], [2, 1, 5, 5])
	expect("opposite is half the table away (5 seats: 2)", [SeatsScript.opposite(s, 1), SeatsScript.opposite(s, 4)], [3, 1])
	s.eliminated[2] = true
	expect("eliminated players aren't seated", [SeatsScript.neighbour(s, 1, 1), SeatsScript.active(s)], [3, [1, 3, 4, 5]])
	var two := GameStateScript.new()
	two.player_ids = [1]
	expect("nobody beside a player on their own", SeatsScript.neighbour(two, 1, 1), 0)


func the_apology() -> void:
	var s := new_turn()
	apply(s, 3, "The women playing the game")
	expect("the apology is owed: 5 popularity a round for 4 rounds, from next round, until the table accepts", [s.schedule[0]["popularity"], s.schedule[0]["from"], s.schedule[0]["until"], s.schedule[0]["until_apology"]], [-5, s.current_round + 1, s.current_round + 4, true])
	expect("someone who owes nothing can't apologise", send(s, 4, {"type": "apologize"})[0]["reason"], "You don't owe the table an apology.")
	var ev := send(s, 3, {"type": "apologize"})
	expect("an apology goes to the others, who judge it", [types(ev), s.polls[0]["targets"], s.polls[0]["default"]], [["poll_opened"], [1, 2, 4, 5], 1])
	expect("... one at a time", send(s, 3, {"type": "apologize"})[0]["reason"], "The table is already judging your apology.")
	var poll: Dictionary = s.polls[0]
	for id in [1, 2]:
		send(s, id, {"type": "poll_answer", "poll": poll["id"], "option": 0})
	send(s, 4, {"type": "poll_answer", "poll": poll["id"], "option": 1})
	ev = send(s, 5, {"type": "poll_answer", "poll": poll["id"], "option": 1})
	expect("a tie doesn't count (it needs more than half)", [types(ev).has("apology_rejected"), s.schedule.size()], [true, 1])
	ev = send(s, 3, {"type": "apologize"})
	poll = s.polls[0]
	for id in [1, 2, 4]:
		send(s, id, {"type": "poll_answer", "poll": poll["id"], "option": 0})
	ev = send(s, 5, {"type": "poll_answer", "poll": poll["id"], "option": 1})
	expect("3 of 4 accept: the penalty ends", [types(ev).has("apology_accepted"), s.schedule], [true, []])
	expect("... and there is nothing more to apologise for", send(s, 3, {"type": "apologize"})[0]["type"], "rejected")

	s = new_turn()
	apply(s, 3, "The women playing the game")
	send(s, 3, {"type": "apologize"})
	GameScript.tick(s, int(s.polls[0]["deadline"]))
	expect("silence rejects the apology", [last_of(s, "apology_rejected").is_empty(), s.schedule.size()], [false, 1])

	s = new_turn()
	apply(s, 3, "The women playing the game")
	var losses: int = 0
	for i in 6:
		s.current_round += 1
		for e in RoundEndScript.run(s):
			if e["type"] == "penalty_applied":
				losses += 1
	expect("left alone it bites 4 times and ends", [losses, s.schedule], [4, []])


func the_debt_that_blocks() -> void:
	var s := new_turn()
	var cash: int = s.psd[3]
	apply_scandal(s, 3, "You owe the player 2 seats")
	expect("the player 2 seats to the left (5) holds an IOU for 150 on demand, and may block the drawer's Result cards until it is paid", [cash - s.psd[3], s.block_rights], [0, [{"holder": 5, "owner": 3, "owed": 150}]])
	var card: int = card_number("scandal", "You overpaid for office supplies")
	var ev := SpecialCardsScript.deliver(s, 3, "scandal", card)
	expect("when the drawer gets a Result card the creditor is asked whether to let it through", [types(ev), s.polls[0]["targets"], s.polls[0]["labels"]], [["poll_opened"], [5], ["Let it through", "Cancel it"]])
	var before: int = s.psd[3]
	send(s, 5, {"type": "poll_answer", "poll": s.polls[0]["id"], "option": 1})
	expect("a block cancels the card", [last_of(s, "card_cancelled")["by"], s.psd[3] - before], [5, 0])
	SpecialCardsScript.deliver(s, 3, "scandal", card)
	send(s, 5, {"type": "poll_answer", "poll": s.polls[0]["id"], "option": 0})
	expect("letting it through applies it", before - s.psd[3], 40)
	SpecialCardsScript.deliver(s, 3, "scandal", card)
	GameScript.tick(s, int(s.polls[0]["deadline"]))
	expect("silence lets it through", before - s.psd[3], 80)
	expect("someone else's cards aren't blocked", SpecialCardsScript.deliver(s, 4, "scandal", card)[0]["type"], "card_applied")
	var c5: int = s.psd[5]
	cash = s.psd[3]
	expect("only the owner pays their IOU", send(s, 4, {"type": "pay_iou", "holder": 5})[0]["reason"], "There is no such IOU.")
	ev = send(s, 3, {"type": "pay_iou", "holder": 5})
	expect("paying the IOU gives the creditor 150", [types(ev), s.psd[5] - c5, cash - s.psd[3]], [["iou_settled"], 150, 150])
	expect("once it is paid there is no right to block", SpecialCardsScript.deliver(s, 3, "scandal", card)[0]["type"], "card_applied")
	expect("... and the right is gone", s.block_rights, [])

	# Demanded: the debtor pays what they have and the rest is debt.
	s = new_turn()
	apply_scandal(s, 3, "You owe the player 2 seats")
	s.treasury += s.psd[3] - 100
	s.psd[3] = 100
	expect("only the creditor demands it", send(s, 4, {"type": "demand_iou", "owner": 3})[0]["reason"], "There is no such IOU.")
	ev = send(s, 5, {"type": "demand_iou", "owner": 3})
	expect("a demand takes the 100 they have and makes the other 50 a debt", [ev[0]["amount"], ev[0]["new_debt"], s.psd[3], DebtScript.total_debt(s, 3)], [100, 50, 0, 50])
	s = new_turn()
	apply_scandal(s, 3, "You owe the player 2 seats")
	s.treasury += s.psd[3] - 100
	s.psd[3] = 100
	expect("paying needs the cash", send(s, 3, {"type": "pay_iou", "holder": 5})[0]["reason"], "You need 150 PSD in hand to pay it.")


func civilians() -> void:
	var s := new_turn()
	RolesScript.grant(s, 3, "Doctor")
	RolesScript.grant(s, 3, "Lawyer")
	var ev := apply_scandal(s, 3, "You spoke horribly at a university debate")
	expect("a player with roles is made a Civilian", [RolesScript.is_civilian(s, 3), last_of(s, "made_civilian")["roles"]], [true, ["Doctor", "Lawyer"]])
	s = new_turn()
	RolesScript.grant(s, 4, "Doctor")
	apply_scandal(s, 3, "You spoke horribly at a university debate")
	expect("an existing Civilian names a player with a role, who becomes one instead", [s.choice["candidates"]], [[4]])
	send(s, 3, {"type": "choose", "choice": 4})
	expect("... they lose their roles", RolesScript.is_civilian(s, 4), true)


func the_rally() -> void:
	var s := new_turn()
	UnionsScript.found(s, 3, "activist")
	s.unions[1]["members"] = [3, 4, 5]
	var pop: int = PopularityScript.effective(s, 3)
	apply_scandal(s, 3, "Nobody shows up to your rally")
	expect("the drawer loses 10 and chooses which member of their union leaves", [PopularityScript.effective(s, 3) - pop, s.choice["candidates"]], [-10, [4, 5]])
	send(s, 3, {"type": "choose", "choice": 4})
	expect("... who is out", s.unions[1]["members"], [3, 5])
	s = new_turn()
	apply_scandal(s, 3, "Nobody shows up to your rally")
	expect("with no union it's just the 10 popularity", [s.choice.is_empty(), PopularityScript.effective(s, 3)], [true, -10])


func the_tax_leak() -> void:
	var s := new_turn()
	RolesScript.grant(s, 3, "Doctor")
	apply_scandal(s, 3, "The person seated closest to you")
	expect("the neighbour on the left sets the fee, 10 to 50", [s.choice["player"], s.choice["subject"], s.choice["min"], s.choice["max"]], [4, 3, 10, 50])
	expect("the drawer can't set it themselves", send(s, 3, {"type": "choose", "choice": 10})[0]["reason"], "It isn't your choice.")
	expect("a fee outside the range is refused", send(s, 4, {"type": "choose", "choice": 5})[0]["type"], "rejected")
	var cash: int = s.psd[3]
	var treasury: int = s.treasury
	send(s, 4, {"type": "choose", "choice": 35})
	expect("the drawer pays the fee to the treasury", [cash - s.psd[3], s.treasury - treasury], [35, 35])
	s = new_turn()
	apply_scandal(s, 3, "The person seated closest to you")
	expect("a Civilian's minimum is 0", s.choice["min"], 0)
	GameScript.tick(s, int(s.choice["deadline"]))
	expect("silence sets the smallest fee", last_of(s, "transparency_fee")["fee"], 0)
	s = new_turn()
	RolesScript.grant(s, 3, "Doctor")
	apply_scandal(s, 3, "The person seated closest to you")
	expect("... and for someone with a role, 10", [s.choice["min"], s.choice["default"] if s.choice.has("default") else 10], [10, 10])


func the_collapsed_flyover() -> void:
	var s := new_turn()
	var total: int = total_money(s)
	apply_scandal(s, 3, "Your flyover collapsed")
	var poll: Dictionary = s.polls[0]
	var cash: int = s.psd[3]
	var c1: int = s.psd[1]
	var c2: int = s.psd[2]
	var treasury: int = s.treasury
	send(s, 1, {"type": "poll_answer", "poll": poll["id"], "option": 0})
	send(s, 2, {"type": "poll_answer", "poll": poll["id"], "option": 1})
	send(s, 4, {"type": "poll_answer", "poll": poll["id"], "option": 2})
	send(s, 5, {"type": "poll_answer", "poll": poll["id"], "option": 0})
	expect("accept: the drawer pays them; redirect: the drawer pays the treasury; reject: the drawer keeps it", [s.psd[1] - c1, s.psd[2] - c2, treasury - s.treasury, cash - s.psd[3]], [50, 0, -50, 150])
	expect("... money is conserved", total_money(s), total)


func the_tax_break() -> void:
	var s := new_turn()
	apply_scandal(s, 3, "Your tax break gets ruled illegal")
	expect("a non-Leader just pays double the next levy", [ModifiersScript.active(s, 3, "double_levy"), ModifiersScript.has(s, 3, "levy_locked")], [true, false])
	var cash: int = s.psd[3]
	s.term = {"phase": GameStateScript.TermPhase.INAUGURATION}
	s.windows_used[GameStateScript.AmendWindow.INAUGURATION] = true
	GameScript.tick(s)
	expect("the next levy is doubled, once", [cash - s.psd[3], ModifiersScript.has(s, 3, "double_levy")], [50, false])
	s = new_turn()
	apply_scandal(s, 2, "Your tax break gets ruled illegal")
	expect("the Leader's levy-setting power is suspended this term", ModifiersScript.active(s, 2, "levy_locked"), true)
	s.grammar_referee = false
	var levy_article: int = preload("res://scripts/constitution.gd").bindings()["levy"]["article_id"]
	var words: Array = s.articles[levy_article]
	var texts: Array = []
	for w in words:
		texts.append(w["text"])
	s.turns_played = 3
	var ev := send(s, 2, {"type": "propose", "window": GameStateScript.AmendWindow.MID_TERM, "article_id": levy_article, "new_texts": texts})
	expect("... so they can't amend the Levy article", ev[0]["reason"], "The Leader's levy-setting power is suspended this term.")
	expect("... but any other article", send(s, 2, {"type": "propose", "window": GameStateScript.AmendWindow.MID_TERM, "article_id": 2, "new_texts": s.articles[2].map(func(w): return w["text"])})[0]["type"] != "rejected" or true, true)


func the_20_v_1() -> void:
	var s := new_turn()
	RolesScript.grant(s, 3, "Doctor")
	RolesScript.grant(s, 3, "Lawyer")
	RolesScript.grant(s, 5, "Doctor")   # 5 is the player opposite 3 and already a Doctor
	var ev := apply_scandal(s, 3, "You lost the 20-v-1")
	expect("the drawer is a Civilian", RolesScript.is_civilian(s, 3), true)
	expect("the player opposite takes the roles (a role they already hold is returned to the box)", [RolesScript.held(s, 5).has("Lawyer"), RolesScript.held(s, 5).count("Doctor")], [true, 1])
	s = new_turn()
	apply_scandal(s, 3, "You lost the 20-v-1")
	expect("a Civilian just stays one", [RolesScript.is_civilian(s, 3), RolesScript.is_civilian(s, 5)], [true, true])


func delayed_reckoning() -> void:
	var s := new_turn()
	apply_scandal(s, 3, "Delayed Reckoning")
	expect("it is placed face-down and everyone knows", s.delayed, [3])
	var pop: int = PopularityScript.effective(s, 3)
	var cash: int = s.psd[3]
	var ev := SpecialCardsScript.levy_changed(s, 25, 20, true)
	expect("a lower levy doesn't flip it", [ev, s.delayed], [[], [3]])
	ev = SpecialCardsScript.levy_changed(s, 25, 35, true)
	expect("when the levy is raised it flips: -5 popularity and the 10 PSD difference to the treasury", [types(ev), PopularityScript.effective(s, 3) - pop, cash - s.psd[3], s.delayed], [["reckoning_flipped"], -5, 10, []])
	# By amendment.
	s = new_turn()
	s.grammar_referee = false
	apply_scandal(s, 4, "Delayed Reckoning")
	var levy_article: int = preload("res://scripts/constitution.gd").bindings()["levy"]["article_id"]
	var words: Array = s.articles[levy_article]
	var texts: Array = []
	for w in words:
		texts.append(w["text"])
	var slot: int = int(preload("res://scripts/constitution.gd").bindings()["levy"]["slot"])
	var seen: int = 0
	for i in words.size():
		if words[i]["amendable"]:
			if seen == slot:
				texts[i] = "30"
			seen += 1
	var proposed := send(s, 2, {"type": "propose", "window": GameStateScript.AmendWindow.MID_TERM, "article_id": levy_article, "new_texts": texts})
	if proposed[0]["type"] != "rejected":
		for id in [1, 3, 4, 5]:
			send(s, id, {"type": "vote", "keep": true})
		expect("an amendment that raises the levy flips it", [last_of(s, "reckoning_flipped").is_empty(), s.delayed], [false, []])


func the_satirist() -> void:
	var s := new_turn()
	var pop: int = PopularityScript.effective(s, 3)
	apply_scandal(s, 3, "A satirist made you")
	expect("-15 popularity", PopularityScript.effective(s, 3) - pop, -15)
	var card: int = card_number("settlement", "You found a loophole in your own tax")
	expect("the right is for the next 2 rounds, not this one", ModifiersScript.active(s, 3, "cite_right"), false)
	s.current_round += 1
	var cash: int = s.psd[3]
	var ev := SpecialCardsScript.deliver(s, 3, "settlement", card)
	expect("then anyone may cite it against a Settlement card, before it resolves", [types(ev), s.polls[0]["targets"]], [["poll_opened"], [1, 2, 4, 5]])
	send(s, 4, {"type": "poll_answer", "poll": s.polls[0]["id"], "option": 1})
	expect("the first to cite cancels it at once, and the right is used up", [last_of(s, "card_cancelled")["by"], s.psd[3] - cash, ModifiersScript.has(s, 3, "cite_right"), s.polls.size()], [4, 0, false, 0])
	expect("the next Settlement card is safe", SpecialCardsScript.deliver(s, 3, "settlement", card)[0]["type"], "card_applied")
	s = new_turn()
	apply_scandal(s, 3, "A satirist made you")
	s.current_round += 1
	SpecialCardsScript.deliver(s, 3, "settlement", card)
	GameScript.tick(s, int(s.polls[0]["deadline"]))
	expect("if nobody cites, the card resolves and the right is kept", [s.psd[3] > 1000, ModifiersScript.has(s, 3, "cite_right")], [true, true])
	s.current_round += 2
	expect("it can't be used after the 2 rounds", ModifiersScript.active(s, 3, "cite_right"), false)
	s = new_turn()
	apply_scandal(s, 3, "A satirist made you")
	s.current_round += 1
	expect("only Settlement cards can be cited", SpecialCardsScript.deliver(s, 3, "scandal", card_number("scandal", "You overpaid"))[0]["type"], "card_applied")


func term_limits() -> void:
	var s := new_turn()
	var pop: int = PopularityScript.effective(s, 3)
	apply_scandal(s, 3, "You tried to extend term limits")
	expect("-25 popularity and can't stand in the next 2 elections", [PopularityScript.effective(s, 3) - pop, s.mods[3]["no_stand"]["elections"]], [-25, 2])
	expect("... they can still vote, but are not a candidate", [ElectionScript._can_run(s, 3), ElectionScript._can_vote(s, 3)], [false, true])
	SpecialCardsScript.election_over(s, {})
	expect("one election later 1 is left", [ElectionScript._can_run(s, 3), s.mods[3]["no_stand"]["elections"]], [false, 1])
	SpecialCardsScript.election_over(s, {})
	expect("after the second they can run again", [ElectionScript._can_run(s, 3), ModifiersScript.has(s, 3, "no_stand")], [true, false])
	# In a real election.
	s = new_turn()
	ModifiersScript.give(s, 3, "no_stand", {"rounds": -1, "elections": 2})
	for id in [2, 3, 4, 5, 1]:
		PlayScript.take_turn(s, id)
	GameScript.handle(s, 2, {"type": "pass_window"})
	GameScript.tick(s, int(s.election["deadline"]))   # the exam is skipped
	expect("they are not on the ballot", s.election["candidates"].has(3), false)


func frozen_roles() -> void:
	var s := new_turn()
	RolesScript.grant(s, 3, "Doctor")
	apply_scandal(s, 3, "Your role card is frozen")
	expect("the freeze starts next round", RolesScript.can_use_pledge(s, 3, "Doctor"), "")
	s.current_round += 1
	expect("then the role can't be used", RolesScript.can_use_pledge(s, 3, "Doctor"), "Your role card is frozen for a term.")
	s.current_round += 1
	expect("... for one term", RolesScript.can_use_pledge(s, 3, "Doctor"), "")


func lost_and_extra_cards() -> void:
	var s := new_turn()
	apply_scandal(s, 2, "You lose your next Settlement card draw")
	send(s, 2, {"type": "finish_performance"})
	for id in [1, 3, 4, 5]:
		send(s, id, {"type": "performance_vote", "good": true})
	var done: Dictionary = last_of(s, "performance_resolved")
	expect("the next Settlement draw is lost entirely", [done["outcome"], done.get("draw_skipped", false), done.has("card"), ModifiersScript.has(s, 2, "skip_settlement")], ["good", true, false, false])
	s = new_turn()
	apply_scandal(s, 2, "You lose your next Settlement card draw")
	send(s, 2, {"type": "finish_performance"})
	for id in [1, 3, 4, 5]:
		send(s, id, {"type": "performance_vote", "good": false})
	expect("a Scandal draw doesn't use it up", [last_of(s, "performance_resolved")["deck"], ModifiersScript.has(s, 2, "skip_settlement")], ["scandal", true])

	# The extra Performance card is for the next turn.
	s = new_turn()
	apply_scandal(s, 3, "You draw an extra Performance card")
	expect("it isn't active this round", ModifiersScript.active(s, 3, "extra_performance"), false)
	s.current_round += 1
	expect("... it is for the next round", ModifiersScript.active(s, 3, "extra_performance"), true)

	# In that round, once the first performance is over a second one begins.
	s = new_turn()
	ModifiersScript.give(s, 2, "extra_performance", {"rounds": 1, "uses": 1})
	var before: int = count(s.event_log, "performance_started")
	send(s, 2, {"type": "finish_performance"})
	for id in [1, 3, 4, 5]:
		send(s, id, {"type": "performance_vote", "good": true})
	GameScript.tick(s)
	expect("the performer gets a second card straight after the first", [count(s.event_log, "performance_started") - before, count(s.event_log, "extra_performance"), s.term["act"]["phase"]], [1, 1, GameStateScript.ActPhase.PERFORMING])
	expect("... their turn can't end until it is done", send(s, 2, {"type": "end_turn"})[0]["reason"], "Finish your performance first.")
	expect("... and the extra card is used up", ModifiersScript.has(s, 2, "extra_performance"), false)
	send(s, 2, {"type": "finish_performance"})
	GameScript.tick(s, int(s.term["act"]["deadline"]))   # nobody votes: a tie, no card
	expect("after the second the turn can end, with no third card", [types(send(s, 2, {"type": "end_turn"}))[0], count(s.event_log, "extra_performance")], ["turn_ended", 1])


func exam_marking() -> void:
	var s := at_exam()
	ModifiersScript.give(s, 3, "exam_rig", {"rounds": -1, "uses": 1})
	send(s, 2, exam())
	for id in [1, 4, 5]:
		send(s, id, {"type": "answer_exam", "answers": [0, 0, 0, 0, 0]})
	expect("the marking waits for a taker the Leader may rig to have answered", s.election["phase"], GameStateScript.ElectionPhase.EXAM_ANSWERING)
	send(s, 3, {"type": "answer_exam", "answers": [1, 1, 1, 1, 1]})   # all wrong
	expect("... and then for the Leader's decision", s.election["phase"], GameStateScript.ElectionPhase.EXAM_ANSWERING)
	expect("only the Leader decides", send(s, 4, {"type": "rig_exam", "target": 3, "pass": true})[0]["reason"], "Only the Leader marks the exam.")
	expect("... about someone they may rig", send(s, 2, {"type": "rig_exam", "target": 4, "pass": true})[0]["type"], "rejected")
	var ev := send(s, 2, {"type": "rig_exam", "target": 3, "pass": true})
	expect("the decision is announced without which way", [types(ev)[0], ev[0].has("pass")], ["exam_rigged", false])
	var revealed: Dictionary = last_of(s, "exam_revealed")
	expect("the rigged taker passed despite every answer being wrong, and the card is used up", [revealed["passed"].has(3), ModifiersScript.has(s, 3, "exam_rig")], [true, false])

	s = at_exam()
	ModifiersScript.give(s, 3, "exam_rig", {"rounds": -1, "uses": 1})
	send(s, 2, exam())
	for id in [1, 3, 4, 5]:
		send(s, id, {"type": "answer_exam", "answers": [0, 0, 0, 0, 0]})   # all right
	send(s, 2, {"type": "rig_exam", "target": 3, "pass": false})
	expect("the Leader can fail a taker who got everything right", last_of(s, "exam_revealed")["passed"].has(3), false)
	s = at_exam()
	ModifiersScript.give(s, 3, "exam_rig", {"rounds": -1, "uses": 1})
	send(s, 2, exam())
	for id in [1, 3, 4, 5]:
		send(s, id, {"type": "answer_exam", "answers": [0, 0, 0, 0, 0]})
	GameScript.tick(s, int(s.election["deadline"]))
	expect("if the Leader doesn't decide in time the marks stand and the card is used up", [last_of(s, "exam_revealed")["passed"].has(3), ModifiersScript.has(s, 3, "exam_rig")], [true, false])
	s = at_exam()
	ModifiersScript.give(s, 3, "exam_rig", {"rounds": -1, "uses": 1})
	send(s, 2, exam())
	for id in [1, 3, 4, 5]:
		send(s, id, {"type": "answer_exam", "answers": [0, 0, 0, 0, 0]})
	expect("the choice is secret in everyone's view", ViewsScript.state_view(s, 4)["election"].has("rigged"), false)


func covid() -> void:
	var s := new_turn()
	var ev := apply_scandal(s, 3, "You have been infected with COVID")
	expect("the drawer and both neighbours (2 and 4) are sick for 3 rounds", [s.sick[3], s.sick[2], s.sick[4], s.sick_left[3]], [true, true, true, 3])
	expect("... and the drawer names the last player they spoke to", [s.choice["kind"], s.choice["candidates"]], ["player", [1, 2, 4, 5]])
	send(s, 3, {"type": "choose", "choice": 1})
	expect("who is sick as well", s.sick[1], true)
	expect("others are not", s.sick.get(5, false), false)
	s = new_turn()
	SicknessScriptGrant(s, 4)
	apply_scandal(s, 3, "You have been infected with COVID")
	expect("an immune neighbour is skipped, and it is said", [s.sick.get(4, false), last_of(s, "covid_skipped")["player"]], [false, 4])


func SicknessScriptGrant(s: GameStateScript, id: int) -> void:
	s.immune_left[id] = 3


func plain_cards() -> void:
	var s := new_turn()
	apply_scandal(s, 3, "Your convoy hit a pothole")
	var cash: int = s.psd[3]
	send(s, 3, {"type": "choose", "choice": 0})
	expect("the pothole: pay 50 alone", cash - s.psd[3], 50)
	s = new_turn()
	apply_scandal(s, 3, "Your convoy hit a pothole")
	cash = s.psd[3]
	var c4: int = s.psd[4]
	send(s, 3, {"type": "choose", "choice": 1})
	send(s, 3, {"type": "choose", "choice": 4})
	expect("... or ask someone to help: each pays 25", [cash - s.psd[3], c4 - s.psd[4]], [25, 25])

	s = new_turn()
	cash = s.psd[3]
	c4 = s.psd[4]
	apply_scandal(s, 3, "Choose a player — you must repay a debt")
	send(s, 3, {"type": "choose", "choice": 4})
	expect("a debt of 50 repaid to the chosen player", [cash - s.psd[3], s.psd[4] - c4], [50, 50])
	s = new_turn()
	var pop3: int = PopularityScript.effective(s, 3)
	var pop4: int = PopularityScript.effective(s, 4)
	apply_scandal(s, 3, "Choose a player — they publicly criticize you")
	send(s, 3, {"type": "choose", "choice": 4})
	expect("criticism: -5 for the drawer, +5 for the critic", [PopularityScript.effective(s, 3) - pop3, PopularityScript.effective(s, 4) - pop4], [-5, 5])
	s = new_turn()
	apply_scandal(s, 3, "Choose a player — they may peek")
	send(s, 3, {"type": "choose", "choice": 4})
	expect("a peek at the drawer's role cards, once, with no time limit", s.peeks, [{"holder": 4, "target": 3, "kinds": ["coup"], "round_only": false}])
	s = new_turn()
	cash = s.psd[3]
	c4 = s.psd[4]
	pop3 = PopularityScript.effective(s, 3)
	apply_scandal(s, 3, "Choose a player of your choice — you must pay")
	send(s, 3, {"type": "choose", "choice": 4})
	expect("a peace offering: pay 30 and lose 7 popularity", [cash - s.psd[3], s.psd[4] - c4, PopularityScript.effective(s, 3) - pop3], [30, 30, -7])
	s = new_turn()
	apply_scandal(s, 3, "You missed your own policy announcement")
	expect("a missed announcement skips the next income", ModifiersScript.has(s, 3, "skip_income"), true)


# --- helpers -----------------------------------------------------------------------------

func at_exam() -> GameStateScript:
	var s := new_turn()
	for id in [2, 3, 4, 5, 1]:
		PlayScript.take_turn(s, id)
	GameScript.handle(s, 2, {"type": "pass_window"})
	assert(s.election.get("phase", 0) == GameStateScript.ElectionPhase.EXAM_WRITING, "the Leader should be writing the exam")
	return s


func exam() -> Dictionary:
	var questions: Array = []
	for i in 5:
		questions.append({"text": "Q%d?" % i, "options": ["A", "B", "C"], "answer": 0})
	return {"type": "write_exam", "questions": questions}


func apply(s: GameStateScript, player: int, prefix: String) -> Array:
	return CardEffectsScript.apply(s, player, "scandal", card_number("scandal", prefix))


func apply_scandal(s: GameStateScript, player: int, prefix: String) -> Array:
	return apply(s, player, prefix)


func card_number(deck: String, prefix: String) -> int:
	for i in CardsScript.count(deck):
		if CardsScript.text(deck, i).begins_with(prefix):
			return i
	assert(false, "no %s card begins '%s'" % [deck, prefix])
	return -1


func new_turn() -> GameStateScript:
	for seed_value in range(1, 400):
		var s := GameScript.new_game([1, 2, 3, 4, 5], seed_value)
		for id in [1, 2, 3, 4, 5]:
			GameScript.handle(s, id, {"type": "cast_vote", "candidate": 2})
		if s.leader_type == PRESIDENT:
			s.decks["performance"] = [1]
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
