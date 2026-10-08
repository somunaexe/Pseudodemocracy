extends SceneTree

# Whole games, played by scripted players through Game.handle, the same door a real server uses.
# After EVERY move the rules of the whole system are checked, not just what that move was meant
# to do. A bug anywhere (money, debt, turn order, elections, saves) shows up here as a broken rule.

const GameScript = preload("res://scripts/game.gd")
const SerializerScript = preload("res://scripts/serializer.gd")
const PopularityScript = preload("res://scripts/popularity.gd")
const GameStateScript = preload("res://scripts/game_state.gd")
const RolesScript = preload("res://scripts/roles.gd")
const ScoringScript = preload("res://scripts/scoring.gd")

const EXAM_WRITING = GameStateScript.ElectionPhase.EXAM_WRITING
const EXAM_ANSWERING = GameStateScript.ElectionPhase.EXAM_ANSWERING
const VOTING = GameStateScript.ElectionPhase.VOTING
const NONE = GameStateScript.TermPhase.NONE
const INAUGURATION = GameStateScript.TermPhase.INAUGURATION
const TURNS = GameStateScript.TermPhase.TURNS
const FAREWELL = GameStateScript.TermPhase.FAREWELL
const SERVER := 0
const BOX := 12550   # every PSD note in the game

var failures: int = 0
var problems: Array = []


func _init() -> void:
	# Ordinary games of different sizes and seeds.
	var all_types: Array = []
	for seed_value in range(1, 13):
		var run := play(5, seed_value, 6)
		all_types.append_array(run["types"])
		expect("seed %d: 6 terms of a 5-player game ran to the end (%d moves)" % [seed_value, run["steps"]], run["finished"], true)
		expect("seed %d: no rule was ever broken" % seed_value, run["problems"], [])
	for count in [3, 4, 7, 10]:
		var run := play(count, 100 + count, 5)
		expect("%d players: 5 terms ran to the end (%d moves)" % [count, run["steps"]], run["finished"], true)
		expect("%d players: no rule was ever broken" % count, run["problems"], [])

	# A poor player drifts into debt, is eliminated, and their heir becomes a Nepo Baby. The one thing
	# that can save them is leading (a Leader earns 100 PSD a turn) or a Settlement card that pays them.
	var poor_runs: int = 0
	var eliminations: int = 0
	var nepo_babies: int = 0
	var leaders_lost: int = 0
	var rescued: int = 0
	for seed_value in range(1, 25):
		var run := play(5, 200 + seed_value, 8, 3)
		expect("poor game %d: ran to the end" % seed_value, run["finished"], true)
		expect("poor game %d: no rule was ever broken" % seed_value, run["problems"], [])
		if run["leaders"].has(3) or run["windfalls"] > 0:
			rescued += 1
			continue
		poor_runs += 1
		eliminations += 1 if run["eliminated"].has(3) else 0
		nepo_babies += 1 if run["types"].has("nepo_baby") else 0
		leaders_lost += 1 if run["types"].has("leader_vacant") else 0
	expect("some poor players never led (%d of 24), so the test means something" % poor_runs, poor_runs >= 4, true)
	expect("a poor player who never led or got a windfall was eliminated, every time (%d of %d)" % [eliminations, poor_runs], eliminations, poor_runs)
	expect("... and their heir became a Nepo Baby each time", nepo_babies, poor_runs)

	# Everything that can happen did happen somewhere.
	var seen := play(5, 7, 6)
	for kind in ["election_started", "exam_written", "exam_revealed", "vote_started", "leader_elected", "leader_installed",
			"term_started", "levy_collected", "turn_started", "turn_ended", "farewell_opened", "term_ended", "window_passed",
			"amendment_proposed", "amendment_resolved", "article_changed", "ballot_cast", "exam_answered",
			"performance_started", "performance_voting_opened", "performance_vote_cast", "performance_resolved", "income_paid", "card_applied"]:
		expect("a played game produced a '%s' event" % kind, seen["types"].has(kind), true)

	# Choices come up too (only some cards ask for one, so across all the ordinary games).
	for kind in ["choice_needed", "choice_made", "role_gained"]:
		expect("the twelve ordinary games produced a '%s' event" % kind, all_types.has(kind), true)

	# The same seed always plays out the same way, to the last byte.
	var a := play(5, 42, 5)
	var b := play(5, 42, 5)
	expect("the same seed gives the same game, byte for byte", a["final"] == b["final"], true)
	expect("... and a different seed gives a different one", a["final"] != play(5, 43, 5)["final"], true)

	# A server that restarts from its save, again and again, plays exactly the same game.
	for seed_value in [3, 17, 29]:
		var straight := play(5, seed_value, 6)
		var restarted := play(5, seed_value, 6, 0, 7)
		expect("seed %d: restarting from a save every 7 moves changes nothing" % seed_value, [restarted["problems"], restarted["final"] == straight["final"]], [[], true])
	var poor_straight := play(5, 205, 8, 3)
	var poor_restarted := play(5, 205, 8, 3, 11)
	expect("... even through debt and an elimination", [poor_restarted["problems"], poor_restarted["final"] == poor_straight["final"]], [[], true])

	# Stopping the game ends it with a winner who is still in it.
	var game := GameScript.new_game([1, 2, 3, 4, 5], 11)
	vote_everyone(game)
	var over := GameScript.handle(game, SERVER, {"type": "finish_game"})
	expect("a game stopped after one election has a winner", over[0]["winners"], [game.leader_id])

	print("%d failure(s)" % failures)
	quit(1 if failures > 0 else 0)


# --- a whole game --------------------------------------------------------------------------

# Plays until `terms` terms have been completed. If `poor` is a player id, that player starts
# with only 30 PSD (and names player 4 as their heir) and so drifts into debt.
func play(player_count: int, seed_value: int, terms: int, poor: int = 0, restart_every: int = 0) -> Dictionary:
	var ids: Array = range(1, player_count + 1)
	var s := GameScript.new_game(ids, seed_value)
	if poor != 0:
		s.treasury += s.psd[poor] - 30
		s.psd[poor] = 30
		s.wills[poor] = {"psd_heir": 4, "on_hold": false}
	problems = []
	var steps: int = 0
	var types_seen: Array = []
	var leaders: Array = []
	var windfalls: int = 0
	var log_size: int = 0
	while s.current_round <= terms and not s.game_over and steps < 4000:
		var move := next_move(s)
		if move.is_empty():
			problems.append("stuck at step %d: %s" % [steps, describe(s)])
			break
		var events: Array = []
		if move.has("tick"):
			events = GameScript.tick(s, move["tick"])
		else:
			events = GameScript.handle(s, move["player"], move["command"])
		steps += 1
		if events.size() > 0 and events[0]["type"] == "rejected":
			problems.append("step %d: a scripted move was refused (%s): %s" % [steps, str(move), events[0]["reason"]])
			break
		for event in events:
			types_seen.append(event["type"])
			if event["type"] == "leader_installed":
				leaders.append(event["leader"])
			if event["type"] in ["card_applied", "choice_made"] and event["player"] == poor and event.get("psd", 0) > 0:
				windfalls += 1   # a Settlement card paid the poor player
		check_rules(s, steps)
		if s.event_log.size() < log_size:
			problems.append("step %d: the event log shrank" % steps)
		log_size = s.event_log.size()
		if steps % 30 == 0 or (restart_every > 0 and steps % restart_every == 0):
			var errors: Array = []
			var restored: GameStateScript = SerializerScript.state_from_json(SerializerScript.state_to_json(s), errors)
			var difference: String = "" if errors.is_empty() else str(errors)
			if errors.is_empty():
				# Compared field by field against GameState itself, not against the serializer.
				for prop in GameStateScript.new().get_property_list():
					if prop["usage"] & PROPERTY_USAGE_SCRIPT_VARIABLE and difference == "":
						difference = diff(s.get(prop["name"]), restored.get(prop["name"]), prop["name"])
			if difference != "":
				problems.append("step %d: a saved game did not restore identically: %s" % [steps, difference])
			if restart_every > 0 and steps % restart_every == 0 and errors.is_empty():
				s = restored   # the server restarts: the game carries on from its save
	var eliminated: Array = []
	for id in s.eliminated:
		if s.eliminated[id]:
			eliminated.append(id)
	return {"steps": steps, "finished": s.current_round > terms, "problems": problems.duplicate(), "types": types_seen,
		"eliminated": eliminated, "leaders": leaders, "windfalls": windfalls, "final": SerializerScript.state_to_json(s)}


# What a sensible player does next, in the order the game needs it: an election first, then an
# amendment being decided, then the term.
func next_move(s: GameStateScript) -> Dictionary:
	if not s.election.is_empty():
		return election_move(s)
	if not s.amend.is_empty():
		return amendment_move(s)
	match s.term.get("phase", NONE):
		INAUGURATION, FAREWELL:
			# Every other term the Leader tries to amend the tax rate; otherwise they pass.
			if s.current_round % 2 == 0 and s.leader_type != GameStateScript.LeaderType.COMMANDER and not window_used(s):
				return {"player": s.leader_id, "command": tax_amendment(s)}
			return {"player": s.leader_id, "command": {"type": "pass_window"}}
		TURNS:
			return performance_move(s)
	return {}


# A turn is a performance. Some run out of time instead of being finished, some votes are
# Good and some Bad, and some votes never come, so every way the clock and the ballots
# can end a performance gets played.
func performance_move(s: GameStateScript) -> Dictionary:
	var act: Dictionary = s.term["act"]
	var performer: int = act["player"]
	match act["phase"]:
		GameStateScript.ActPhase.PERFORMING:
			if act["card"] % 3 == 0:
				return {"tick": int(act["deadline"])}
			return {"player": performer, "command": {"type": "finish_performance"}}
		GameStateScript.ActPhase.VOTING:
			var waiting: Array = []
			for id in s.player_ids:
				if id != performer and not s.eliminated.get(id, false) and not act["votes"].has(id):
					waiting.append(id)
			if act["votes"].size() >= 2 and act["card"] % 2 == 0:
				return {"tick": int(act["deadline"])}   # the rest never voted
			return {"player": waiting[0], "command": {"type": "performance_vote", "good": (waiting[0] * 7 + act["card"]) % 3 != 0}}
	if act.has("choice") and (s.current_round + performer) % 3 == 0:
		return {"tick": int(act["choice"]["deadline"])}   # they never answered: the server chooses
	if act.has("choice"):
		# Every kind of choice is made, taking different answers in turn so none is always the first.
		var choice: Dictionary = act["choice"]
		var answer: Variant = 0
		match choice["kind"]:
			"option":
				answer = (s.current_round + performer) % choice["labels"].size()
			"role", "player":
				answer = choice["candidates"][(s.current_round + performer) % choice["candidates"].size()]
		return {"player": performer, "command": {"type": "choose", "choice": answer}}
	return {"player": performer, "command": {"type": "end_turn"}}


func window_used(s: GameStateScript) -> bool:
	var window: int = GameStateScript.AmendWindow.INAUGURATION if s.term["phase"] == INAUGURATION else GameStateScript.AmendWindow.FAREWELL
	return s.windows_used[window]


func election_move(s: GameStateScript) -> Dictionary:
	match s.election["phase"]:
		EXAM_WRITING:
			var questions: Array = []
			for i in 5:
				questions.append({"text": "Question %d?" % (i + 1), "options": ["A", "B", "C"], "answer": (i + s.current_round) % 3})
			return {"player": s.leader_id, "command": {"type": "write_exam", "questions": questions}}
		EXAM_ANSWERING:
			for id in s.election["takers"]:
				if id in s.election["answers"] or s.eliminated.get(id, false) or s.sick.get(id, false):
					continue
				# Some players get everything right, some everything wrong.
				var answers: Array = []
				for key in s.election["key"]:
					answers.append(key if (id + s.current_round) % 3 != 0 else (key + 1) % 3)
				return {"player": id, "command": {"type": "answer_exam", "answers": answers}}
		VOTING:
			for id in s.election["voters"]:
				if id in s.election["votes"] or s.eliminated.get(id, false) or s.sick.get(id, false):
					continue
				var candidates: Array = s.election["candidates"]
				return {"player": id, "command": {"type": "cast_vote", "candidate": candidates[(id + s.current_round) % candidates.size()]}}
	return {}


func amendment_move(s: GameStateScript) -> Dictionary:
	if s.amend["phase"] == GameStateScript.AmendPhase.PROPOSED:
		return {"player": SERVER, "command": {"type": "rule_grammar", "ok": true}}
	for id in s.player_ids:
		if id == s.leader_id or s.eliminated.get(id, false) or s.sick.get(id, false) or s.amend["votes"].has(id):
			continue
		return {"player": id, "command": {"type": "vote", "keep": true}}
	return {}


func tax_amendment(s: GameStateScript) -> Dictionary:
	var window: int = GameStateScript.AmendWindow.INAUGURATION if s.term["phase"] == INAUGURATION else GameStateScript.AmendWindow.FAREWELL
	var texts: Array = []
	var rate: String = "%d%%" % (10 + (s.current_round * 7) % 40)
	var slot: int = 0
	for word in s.articles[2]:
		if word["amendable"]:
			texts.append(rate if slot == 0 else word["text"])
			slot += 1
		else:
			texts.append(word["text"])
	return {"type": "propose", "window": window, "article_id": 2, "new_texts": texts}


func vote_everyone(s: GameStateScript) -> void:
	for id in s.player_ids:
		GameScript.handle(s, id, {"type": "cast_vote", "candidate": 2})


# --- the rules that must hold after every move ----------------------------------------------

func check_rules(s: GameStateScript, step: int) -> void:
	var where: String = "step %d: " % step
	for role in RolesScript.names():
		if RolesScript.holders(s, role).size() > RolesScript.copies():
			problems.append(where + "more than %d %s cards are held" % [RolesScript.copies(), role])
	for id in s.roles:
		var seen_roles: Array = []
		for role in s.roles[id]:
			if not role in RolesScript.names() or role in seen_roles:
				problems.append(where + "player %d holds a bad or doubled role (%s)" % [id, role])
			seen_roles.append(role)
		if s.eliminated.get(id, false) and not s.roles[id].is_empty():
			problems.append(where + "eliminated player %d still holds roles" % id)
		if s.roles[id].is_empty():
			problems.append(where + "player %d has an empty role list instead of none" % id)
	var total: int = s.treasury
	for id in s.player_ids:
		var cash: int = int(s.psd.get(id, 0))
		var debt: int = 0
		for entry in s.debts.get(id, []):
			debt += entry["amount"]
		total += cash
		if cash < 0:
			problems.append(where + "player %d has negative cash" % id)
		if debt > 0 and cash > 0:
			problems.append(where + "player %d holds %d PSD while owing %d" % [id, cash, debt])
		var base: int = PopularityScript.base(s, id)
		if base < -50 or base > 50:
			problems.append(where + "player %d's popularity %d is off the track" % [id, base])
		if s.eliminated.get(id, false):
			if cash != 0 or debt != 0:
				problems.append(where + "eliminated player %d still has money or debt" % id)
			if id == s.leader_id:
				problems.append(where + "an eliminated player is the Leader")
			if s.nepo.has(id):
				problems.append(where + "an eliminated player is a Nepo Baby")
	if total != BOX:
		problems.append(where + "money was created or lost: %d instead of %d" % [total, BOX])
	if s.leader_id != -1 and s.eliminated.get(s.leader_id, false):
		problems.append(where + "the Leader is eliminated")
	if not s.term.is_empty() and not s.election.is_empty():
		problems.append(where + "a term and an election are both running")
	if not s.amend.is_empty() and s.term.is_empty():
		problems.append(where + "an amendment is under way outside a term")
	for id in s.nepo:
		if not s.nepo[id] in [1, 2, 3]:
			problems.append(where + "player %d has Nepo step %s" % [id, str(s.nepo[id])])
	if s.rng_state <= 0 or s.rng_state >= 4294967296:
		problems.append(where + "the random generator state left its range")
	if s.term.get("phase", NONE) in [TURNS, FAREWELL]:
		var seen: Array = []
		for id in s.term["played"] + s.term["waiting"]:
			if s.eliminated.get(id, false):
				problems.append(where + "an eliminated player is in the turn order")
			if id in seen:
				problems.append(where + "player %d is in the turn order twice" % id)
			seen.append(id)
		if s.turns_played != s.term["played"].size() or s.player_count != seen.size():
			problems.append(where + "turns_played and player_count disagree with the turn order")
		if s.term["phase"] == FAREWELL and not s.term["waiting"].is_empty():
			problems.append(where + "the Farewell began before everyone had played")
	if s.leader_id == -1 and s.term.get("phase", NONE) != NONE:
		problems.append(where + "a term is running with no Leader")


# "" when two values are identical, types included; otherwise where they first differ.
func diff(a: Variant, b: Variant, path: String) -> String:
	if typeof(a) != typeof(b):
		return "%s: type %d vs %d" % [path, typeof(a), typeof(b)]
	if typeof(a) == TYPE_ARRAY:
		if a.size() != b.size():
			return "%s: %d items vs %d" % [path, a.size(), b.size()]
		for i in a.size():
			var d: String = diff(a[i], b[i], "%s[%d]" % [path, i])
			if d != "":
				return d
	elif typeof(a) == TYPE_DICTIONARY:
		if a.size() != b.size():
			return "%s: %d keys vs %d" % [path, a.size(), b.size()]
		for key in a:
			if not b.has(key):
				return "%s: key %s missing" % [path, str(key)]
			var d: String = diff(a[key], b[key], "%s[%s]" % [path, str(key)])
			if d != "":
				return d
	elif a != b:
		return "%s: %s vs %s" % [path, str(a), str(b)]
	return ""


func describe(s: GameStateScript) -> String:
	return "round %d, leader %d, term %s, election %s, amend %s" % [s.current_round, s.leader_id, str(s.term.get("phase", NONE)), str(s.election.get("phase", "-")), str(s.amend.get("phase", "-"))]


func expect(label: String, actual: Variant, wanted: Variant) -> void:
	var ok: bool = typeof(actual) == typeof(wanted) and actual == wanted
	if not ok:
		failures += 1
	print(("PASS " if ok else "FAIL ") + label + " -> " + str(actual).left(300))
