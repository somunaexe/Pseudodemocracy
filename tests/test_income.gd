extends SceneTree

const GameScript = preload("res://scripts/game.gd")
const IncomeScript = preload("res://scripts/income.gd")
const DebtScript = preload("res://scripts/debt.gd")
const GameStateScript = preload("res://scripts/game_state.gd")
const ViewsScript = preload("res://scripts/views.gd")
const PlayScript = preload("res://tests/play.gd")

const PRESIDENT = GameStateScript.LeaderType.PRESIDENT
const TREASURY := 0

var failures: int = 0


func _init() -> void:
	what_each_player_earns()
	tax_and_the_treasury()
	debts_are_paid_first()
	income_arrives_on_your_own_turn()
	roles_stay_secret()
	print("%d failure(s)" % failures)
	quit(1 if failures > 0 else 0)


func what_each_player_earns() -> void:
	var s := new_term()
	expect("the Leader earns 100", IncomeScript.gross(s, 2), 100)
	expect("a player with no role earns nothing", IncomeScript.gross(s, 1), 0)
	s.roles = {1: ["Doctor"], 3: ["Lawyer"], 4: ["Secret Agent"], 5: ["Activist"]}
	expect("a Doctor earns 70, a Lawyer 50, a Secret Agent 80", [IncomeScript.gross(s, 1), IncomeScript.gross(s, 3), IncomeScript.gross(s, 4)], [70, 50, 80])
	expect("an Activist earns nothing", IncomeScript.gross(s, 5), 0)
	s.roles = {1: ["Doctor", "Lawyer"], 2: ["Secret Agent"], 3: ["Agbero", "Activist"], 4: ["Activist", "Doctor"]}
	expect("roles stack: a Doctor and a Lawyer earn 120", IncomeScript.gross(s, 1), 120)
	expect("... and the Leader's 100 stacks with a role: 180", IncomeScript.gross(s, 2), 180)
	expect("... an Agbero who is also an Activist earns nothing", IncomeScript.gross(s, 3), 0)
	expect("... an Activist who is also a Doctor earns only the Doctor's 70", IncomeScript.gross(s, 4), 70)


func tax_and_the_treasury() -> void:
	var s := new_term()
	s.roles = {1: ["Doctor", "Lawyer"]}
	var treasury_before: int = s.treasury
	var cash_before: int = s.psd[1]
	var ev := IncomeScript.pay(s, 1)
	expect("120 gross at 20% tax: 24 tax, 96 net", [ev[0]["gross"], ev[0]["paid"], ev[0]["tax"], ev[0]["net"]], [120, 120, 24, 96])
	expect("... the player gets the net and the treasury loses it", [s.psd[1] - cash_before, treasury_before - s.treasury], [96, 96])
	expect("... the event is public and logged once", [ev[0]["audience"], s.event_log.back() == ev[0]], [[], true])
	expect("a player who earns nothing gets no event", IncomeScript.pay(s, 3), [])

	# Tax follows the Constitution, and is rounded down in the player's favour.
	s = new_term()
	set_word(s, 2, 0, "33%")
	s.roles = {1: ["Doctor"]}
	ev = IncomeScript.pay(s, 1)
	expect("at an amended 33% a Doctor's 70 is taxed 23 (23.1 rounded down), net 47", [ev[0]["tax"], ev[0]["net"]], [23, 47])
	set_word(s, 2, 0, "0%")
	expect("at 0% there is no tax", IncomeScript.pay(s, 2)[0]["net"], 100)

	# A short treasury pays what it has.
	s = new_term()
	s.roles = {}
	var total: int = total_money(s)
	s.psd[2] += s.treasury - 50
	s.treasury = 50
	ev = IncomeScript.pay(s, 2)
	expect("a treasury with 50 left can't pay the Leader's 100: it pays 50, tax 10, net 40", [ev[0]["gross"], ev[0]["paid"], ev[0]["tax"], ev[0]["net"]], [100, 50, 10, 40])
	expect("... leaving 10 in the treasury", s.treasury, 10)
	expect("... and money is conserved", total_money(s), total)
	s.psd[2] += s.treasury
	s.treasury = 0
	ev = IncomeScript.pay(s, 2)
	expect("an empty treasury pays nothing", [ev[0]["paid"], ev[0]["net"], s.treasury], [0, 0, 0])


func debts_are_paid_first() -> void:
	var s := new_term()
	s.roles = {1: ["Doctor"]}
	s.treasury += s.psd[1]
	s.psd[1] = 0
	DebtScript.charge(s, 1, TREASURY, 30)
	DebtScript.charge(s, 1, 3, 40)
	var total: int = total_money(s)
	IncomeScript.pay(s, 1)   # 70 gross, 14 tax, 56 net
	expect("income pays the oldest debt first, then the next", [DebtScript.total_debt(s, 1), s.psd[1]], [14, 0])
	expect("... 56 net: 30 to the treasury, 26 of the 40 owed to player 3, who is repaid", [s.psd[3], s.debts.get(1, []).size()], [975 + 26, 1])
	expect("... and money is conserved", total_money(s), total)


func income_arrives_on_your_own_turn() -> void:
	var s := new_term()   # player 2 is the Leader and goes first
	s.roles = {3: ["Doctor"], 4: ["Activist"]}
	GameScript.tick(s)
	var cash3: int = s.psd[3]
	expect("a Doctor's income does not arrive at the start of the term", cash3, 975)
	expect("... the Leader's does arrive at the Leader's own turn", s.psd[2], 975 + 80)
	var ev := PlayScript.take_turn(s, 2)
	expect("when the Doctor's turn comes the income is paid first, then the performance starts", types(ev), ["turn_ended", "turn_started", "income_paid", "performance_started"])
	expect("... 70 less 14 tax is 56", [ev[2]["player"], ev[2]["net"], s.psd[3]], [3, 56, cash3 + 56])
	GameScript.tick(s)
	GameScript.tick(s)
	expect("... and only once, however often the loop runs", s.psd[3], cash3 + 56)
	ev = PlayScript.take_turn(s, 3)
	ev = PlayScript.take_turn(s, 4)
	expect("an Activist's turn pays nothing", types(ev), ["turn_ended", "turn_started", "performance_started"])
	expect("... the money is all still there", total_money(s), 12550)


func roles_stay_secret() -> void:
	var s := new_term()
	s.roles = {3: ["Doctor"]}
	var view: Dictionary = ViewsScript.state_view(s, 3)
	expect("nobody's view has role cards, not even their own (peeking comes later)", [view.has("roles"), ViewsScript.state_view_json(s, 4).contains("[\"Doctor\"]")], [false, false])


# --- helpers -----------------------------------------------------------------------------

func new_term() -> GameStateScript:
	for seed_value in range(1, 400):
		var s := GameScript.new_game([1, 2, 3, 4, 5], seed_value)
		for id in [1, 2, 3, 4, 5]:
			GameScript.handle(s, id, {"type": "cast_vote", "candidate": 2})
		if s.leader_type == PRESIDENT:
			GameScript.handle(s, 2, {"type": "pass_window"})
			return s
	assert(false, "no seed gave a President")
	return null


func set_word(s: GameStateScript, article_id: int, slot: int, text: String) -> void:
	var seen: int = 0
	for word in s.articles[article_id]:
		if word["amendable"]:
			if seen == slot:
				word["text"] = text
				return
			seen += 1


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
