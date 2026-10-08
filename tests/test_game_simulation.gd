extends SceneTree

# Whole games, played by scripted players through Game.handle, the same door a real server uses.
# After EVERY move the rules of the whole system are checked, not just what that move was meant
# to do. A bug anywhere (money, debt, turn order, elections, saves) shows up here as a broken rule.

const GameScript = preload("res://scripts/game.gd")
const SerializerScript = preload("res://scripts/serializer.gd")
const PopularityScript = preload("res://scripts/popularity.gd")
const GameStateScript = preload("res://scripts/game_state.gd")
const DoctorScript = preload("res://scripts/doctor.gd")
const UnionsScript = preload("res://scripts/unions.gd")
const SicknessScript = preload("res://scripts/sickness.gd")
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

	# A Doctor at the table: doses, guesses, sabotage and cures, with every rule checked after every move.
	var dose_types: Array = []
	for seed_value in range(1, 9):
		var run := play(5, 300 + seed_value, 6, 0, 0, 3, 0, 4)
		dose_types.append_array(run["types"])
		expect("Doctor game %d: ran to the end (%d moves)" % [seed_value, run["steps"]], run["finished"], true)
		expect("Doctor game %d: no rule was ever broken" % seed_value, run["problems"], [])
	expect("the Secret Agent checked in the Doctor games (%d reports)" % dose_types.count("agent_report"), dose_types.has("agent_report"), true)
	for kind in ["dose_offered", "dose_accepted", "dose_rejected", "dose_expired", "sabotage_guessed", "dose_given", "sickened", "sickness_lengthened", "sickness_shortened", "recovered", "licence_lost", "dose_void"]:
		expect("the Doctor games produced a '%s' event (%d times)" % [kind, dose_types.count(kind)], dose_types.has(kind) or kind in ["dose_void"], true)
	var doc_straight := play(5, 303, 6, 0, 0, 3, 0, 4)
	var doc_restarted := play(5, 303, 6, 0, 5, 3, 0, 4)
	expect("a server restarting from its save every 5 moves, mid-dose or not, gives the same Doctor game", [doc_restarted["problems"], doc_restarted["final"] == doc_straight["final"]], [[], true])

	# A Lawyer at the table: wills proposed, signed, charged upkeep, put on hold and reactivated.
	var will_types: Array = []
	for seed_value in range(1, 9):
		var run := play(5, 400 + seed_value, 7, 3, 0, 0, 2, 4)
		will_types.append_array(run["types"])
		expect("Lawyer game %d: ran to the end (%d moves)" % [seed_value, run["steps"]], run["finished"], true)
		expect("Lawyer game %d: no rule was ever broken" % seed_value, run["problems"], [])
	for kind in ["will_proposed", "will_signed", "will_terms", "will_refused", "will_expired", "will_upkeep_paid", "will_on_hold"]:
		expect("the Lawyer games produced a '%s' event (%d times)" % [kind, will_types.count(kind)], will_types.has(kind), true)
	expect("... and wills reached their end: read out or void (%d read, %d void)" % [will_types.count("will_read"), will_types.count("will_void")], will_types.has("will_read") or will_types.has("will_void"), true)
	var will_straight := play(5, 403, 7, 3, 0, 0, 2, 4)
	var will_restarted := play(5, 403, 7, 3, 6, 0, 2, 4)
	expect("a server restarting from its save every 6 moves, with wills waiting or not, gives the same game", [will_restarted["problems"], will_restarted["final"] == will_straight["final"]], [[], true])

	# Unions at the table: founded, recruiting, refused, shrinking, kicking, dispersing and re-forming.
	var union_types: Array = []
	for seed_value in range(1, 9):
		var run := play(5, 500 + seed_value, 7, 0, 0, 0, 0, 0, true)
		union_types.append_array(run["types"])
		expect("union game %d: ran to the end (%d moves)" % [seed_value, run["steps"]], run["finished"], true)
		expect("union game %d: no rule was ever broken" % seed_value, run["problems"], [])
	for kind in ["union_founded", "union_invited", "union_joined", "union_invitation_refused", "union_invitation_expired", "union_left", "union_dispersed",
			"command_started", "command_performance_started", "command_voting_opened", "command_vote_cast", "command_performance_resolved"]:
		expect("the union games produced a '%s' event (%d times)" % [kind, union_types.count(kind)], union_types.has(kind), true)
	var union_straight := play(5, 503, 7, 0, 0, 0, 0, 0, true)
	var union_restarted := play(5, 503, 7, 0, 5, 0, 0, 0, true)
	expect("a server restarting from its save every 5 moves, with invitations waiting or not, gives the same union game", [union_restarted["problems"], union_restarted["final"] == union_straight["final"]], [[], true])

	# Everything that can happen did happen somewhere.
	var seen := play(5, 7, 6)
	for kind in ["election_started", "exam_written", "exam_revealed", "vote_started", "leader_elected", "leader_installed",
			"term_started", "levy_collected", "turn_started", "turn_ended", "farewell_opened", "term_ended", "window_passed",
			"amendment_proposed", "amendment_resolved", "article_changed", "ballot_cast", "exam_answered",
			"performance_started", "performance_voting_opened", "performance_vote_cast", "performance_resolved", "income_paid", "card_applied"]:
		expect("a played game produced a '%s' event" % kind, seen["types"].has(kind), true)

	# Choices come up too (only some cards ask for one, so across all the ordinary games).
	for kind in ["choice_needed", "choice_made", "role_gained", "card_played", "union_founded"]:
		expect("the twelve ordinary games produced a '%s' event (%d times)" % [kind, all_types.count(kind)], all_types.has(kind), true)

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
func play(player_count: int, seed_value: int, terms: int, poor: int = 0, restart_every: int = 0, doctor: int = 0, lawyer: int = 0, agent: int = 0, unions: bool = false) -> Dictionary:
	var ids: Array = range(1, player_count + 1)
	var s := GameScript.new_game(ids, seed_value)
	if poor != 0:
		s.treasury += s.psd[poor] - 30
		s.psd[poor] = 30
		s.wills[poor] = {"psd_heir": 4, "on_hold": false}
	if doctor != 0:
		RolesScript.grant(s, doctor, "Doctor")   # a Doctor from the start, so doses are given all game
	if unions:
		# Union cards in hand (played as soon as possible) and two Agberos, so mobs form, recruit, shrink,
		# disperse and re-form inside whole games.
		s.hands[3] = [{"deck": "settlement", "card": 8}]
		s.hands[1] = [{"deck": "settlement", "card": 7}]
		s.hands[5] = [{"deck": "settlement", "card": 9}]
		RolesScript.grant(s, 3, "Agbero")
		RolesScript.grant(s, 4, "Agbero")
	if agent != 0:
		RolesScript.grant(s, agent, "Secret Agent")   # a Secret Agent, who checks cards, wills and beads
	if lawyer != 0:
		RolesScript.grant(s, lawyer, "Lawyer")   # and a Lawyer, so wills are written all game
		if seed_value % 2 == 0:
			s.wills.erase(poor)                  # the poor player writes theirs through the Lawyer, and misses the upkeep
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
			if event["type"] == "income_paid" and event["player"] == poor and event["net"] > 0:
				windfalls += 1   # or a role (a Lawyer's 50, say) did
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
	var choosing := choice_move(s)
	if not choosing.is_empty():
		return choosing
	var played := hand_move(s)
	if not played.is_empty():
		return played
	var commanding := command_move(s)
	if not commanding.is_empty():
		return commanding
	var union := union_move(s)
	if not union.is_empty():
		return union
	var dose := doctor_move(s)
	if not dose.is_empty():
		return dose
	var will := lawyer_move(s)
	if not will.is_empty():
		return will
	var check := agent_move(s)
	if not check.is_empty():
		return check
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


# The Doctor (if there is one) gives doses during a term: heals a sick player, or sickens a willing one.
# Patients accept or let the offer lapse, players guess Sabotage or let the guessing run out, and the
# bead is poison in about half the doses, so every outcome gets played.
func doctor_move(s: GameStateScript) -> Dictionary:
	if s.term.is_empty() or not s.amend.is_empty():
		return {}
	if not s.dose.is_empty():
		var dose: Dictionary = s.dose
		if dose["phase"] == GameStateScript.DosePhase.OFFERED:
			var offer_number: int = count_events(s, "dose_offered")
			if offer_number % 7 == 3:
				return {"tick": int(dose["deadline"])}   # the patient never answers
			return {"player": dose["patient"], "command": {"type": "dose_respond", "accept": offer_number % 4 != 0}}
		if dose["guesser"] == 0 and (s.turns_played + dose["patient"]) % 2 == 0:
			for id in s.player_ids:
				if id != dose["doctor"] and not s.eliminated.get(id, false):
					return {"player": id, "command": {"type": "dose_guess"}}
		return {"tick": int(dose["deadline"])}
	if offers_this_term(s) >= 3:
		return {}   # a rejected or lapsed offer costs no charge, so the script itself must stop asking
	for doctor_id in RolesScript.holders(s, "Doctor"):
		if RolesScript.can_use_pledge(s, doctor_id, "Doctor") != "" or DoctorScript.charges_left(s, doctor_id) <= 0:
			continue
		for id in s.player_ids:
			if id == doctor_id or s.eliminated.get(id, false):
				continue
			var poison: bool = (s.current_round + id + s.turns_played) % 3 != 0
			var dose_name: String = ["Agbo", "Concoction", "Surgery"][(s.turns_played + id) % 3]
			if SicknessScript.is_sick(s, id):
				return {"player": doctor_id, "command": {"type": "dose_offer", "patient": id, "kind": "heal", "dose": dose_name, "price": 20, "poison": poison}}
			if SicknessScript.problem_sickening(s, id) == "":
				return {"player": doctor_id, "command": {"type": "dose_offer", "patient": id, "kind": "sicken", "dose": "Concoction", "price": 10}}   # 2 rounds, so a later Agbo only shortens it
	return {}


# A card choice that is waiting, whoever it belongs to. Every kind is made, taking different answers in turn so
# none is always the first, and some are never answered so the server chooses.
func choice_move(s: GameStateScript) -> Dictionary:
	if s.choice.is_empty():
		return {}
	var chooser: int = s.choice["player"]
	if (s.current_round + chooser + s.turns_played) % 3 == 0:
		return {"tick": int(s.choice["deadline"])}   # they never answered: the server chooses
	var answer: Variant = 0
	match s.choice["kind"]:
		"option":
			answer = (s.current_round + chooser) % s.choice["labels"].size()
		"role", "player":
			answer = s.choice["candidates"][(s.current_round + chooser) % s.choice["candidates"].size()]
	return {"player": chooser, "command": {"type": "choose", "choice": answer}}


# Players play the union cards they are keeping as soon as they can.
func hand_move(s: GameStateScript) -> Dictionary:
	var owners: Array = s.hands.keys()
	owners.sort()
	for owner in owners:
		if not s.eliminated.get(owner, false) and UnionsScript.problem_founding(s, owner) == "":
			return {"player": owner, "command": {"type": "play_card", "index": 0}}
	return {}


# A Command Performance under way: the performer finishes early (or doesn't), voters vote (or don't), so every way it
# can end gets played.
func command_move(s: GameStateScript) -> Dictionary:
	if s.command.is_empty():
		return {}
	var cmd: Dictionary = s.command
	match cmd["phase"]:
		GameStateScript.CommandPhase.PERFORMING:
			if (cmd["target"] + s.turns_played) % 2 == 0:
				return {"player": cmd["target"], "command": {"type": "command_finish"}}
			return {"tick": int(cmd["deadline"])}
		GameStateScript.CommandPhase.VOTING:
			var waiting: Array = []
			for id in s.player_ids:
				if id != cmd["target"] and not s.eliminated.get(id, false) and not cmd["votes"].has(id):
					waiting.append(id)
			if cmd["votes"].size() >= 2 and (cmd["target"] + s.turns_played) % 3 == 0:
				return {"tick": int(cmd["deadline"])}   # the rest never voted
			return {"player": waiting[0], "command": {"type": "command_vote", "good": (waiting[0] + count_events(s, "command_started")) % 3 != 0}}
	return {}


# Unions: invitations are answered (some ignored), Unionizers recruit on their turns, members leave on theirs, big
# unions kick, some disperse, and Agberos re-form. All limited by counts so the script cannot ask forever.
func union_move(s: GameStateScript) -> Dictionary:
	if s.game_over:
		return {}
	var asked: Array = s.union_invites.keys()
	asked.sort()
	for target in asked:
		var number: int = count_events(s, "union_invited")
		if number % 4 == 1:
			return {"tick": int(s.union_invites[target]["deadline"])}   # nobody answers
		return {"player": target, "command": {"type": "union_respond", "accept": number % 3 != 0}}
	for player in s.reform:
		if s.reform[player]:
			return {"player": player, "command": {"type": "union_reform"}}
	var waiting: Array = s.term.get("waiting", [])
	if s.term.get("phase", 0) != GameStateScript.TermPhase.TURNS or waiting.is_empty():
		return {}
	var now: int = waiting[0]
	var ids: Array = s.unions.keys()
	ids.sort()
	for union_id in ids:
		var union: Dictionary = s.unions[union_id]
		var members: Array = union["members"]
		if now in members and now != union["owner"] and (s.turns_played + now) % 3 == 0:
			return {"player": now, "command": {"type": "union_leave"}}
		if (union["owner"] == now or (now == s.leader_id and s.leader_id in members)) and not s.sick.get(union["owner"], false):
			var turn_number: int = count_events(s, "turn_started")
			var act: Dictionary = s.term.get("act", {})
			if s.command.is_empty() and now == union["owner"] and not act.is_empty() and act["phase"] == GameStateScript.ActPhase.DONE \
					and members.size() >= 2 and turn_number % 3 != 0 and commands_this_term(s) < 2 \
					and union.get("commanded", -1) != s.current_round * 1000 + s.turns_played:
				var outside: Array = []
				for candidate in s.player_ids:
					if not candidate in members and not s.eliminated.get(candidate, false):
						outside.append(candidate)
				if not outside.is_empty():
					var order := {"type": "union_command", "union_id": union_id, "scenario": "scenario %d" % turn_number, "target": outside[turn_number % outside.size()]}
					return {"player": union["owner"], "command": order}
			if members.size() >= 3 and turn_number % 4 == 0:
				return {"player": union["owner"], "command": {"type": "union_kick", "union_id": union_id, "target": members[members.size() - 1]}}
			if members.size() >= 2 and turn_number % 9 == 0:
				return {"player": union["owner"], "command": {"type": "union_disperse", "union_id": union_id}}
			if recruits_this_term(s) < 3:
				for candidate in s.player_ids:
					if candidate != union["owner"] and not s.eliminated.get(candidate, false) and candidate != s.leader_id \
							and UnionsScript.union_of(s, candidate) == -1 and not s.union_invites.has(candidate):
						return {"player": union["owner"], "command": {"type": "union_recruit", "union_id": union_id, "target": candidate}}
	return {}


func commands_this_term(s: GameStateScript) -> int:
	var n: int = 0
	for i in range(s.event_log.size() - 1, -1, -1):
		var kind: String = s.event_log[i]["type"]
		if kind == "term_started":
			break
		if kind == "command_started":
			n += 1
	return n


func recruits_this_term(s: GameStateScript) -> int:
	var n: int = 0
	for i in range(s.event_log.size() - 1, -1, -1):
		var kind: String = s.event_log[i]["type"]
		if kind == "term_started":
			break
		if kind == "union_invited":
			n += 1
	return n


# The Secret Agent (if there is one) uses their one check a round: the bead if a heal is under way, else on their
# own turn a will if there is one to read, else a role card somebody holds.
func agent_move(s: GameStateScript) -> Dictionary:
	if s.term.is_empty() or s.game_over:
		return {}
	for agent in RolesScript.holders(s, "Secret Agent"):
		if s.agent_used.get(agent, false) or RolesScript.can_use_pledge(s, agent, "Secret Agent") != "":
			continue
		if not s.dose.is_empty() and s.dose["kind"] == "heal" and agent != s.dose["doctor"]:
			return {"player": agent, "command": {"type": "agent_check", "kind": "bead"}}
		var waiting: Array = s.term.get("waiting", [])
		if s.term.get("phase", 0) != GameStateScript.TermPhase.TURNS or waiting.is_empty() or waiting[0] != agent:
			continue
		for testator in s.wills:
			if not s.eliminated.get(testator, false):
				return {"player": agent, "command": {"type": "agent_check", "kind": "will", "target": testator}}
		for holder in s.roles:
			if not s.eliminated.get(holder, false) and not s.roles[holder].is_empty():
				return {"player": agent, "command": {"type": "agent_check", "kind": "coup", "target": holder, "role": s.roles[holder][0]}}
	return {}


# The Lawyer (if there is one) keeps wills: players propose, the Lawyer signs or lets the offer lapse, players
# who missed their upkeep catch up when they can. Proposals are limited per term because a refused or lapsed
# one costs nothing, and the script must not ask forever.
func lawyer_move(s: GameStateScript) -> Dictionary:
	if s.game_over:
		return {}
	var lawyers: Array = RolesScript.holders(s, "Lawyer")
	if lawyers.is_empty():
		return {}
	var keeper: int = lawyers[0]
	var testators: Array = s.will_offers.keys()
	testators.sort()
	for testator in testators:
		if s.will_offers[testator]["lawyer"] == keeper:
			var proposal_number: int = count_events(s, "will_proposed")
			if proposal_number % 5 == 2:
				return {"tick": int(s.will_offers[testator]["deadline"])}   # the Lawyer never answers
			return {"player": keeper, "command": {"type": "will_respond", "testator": testator, "accept": proposal_number % 3 != 0}}
	for id in s.player_ids:
		if id == keeper or s.eliminated.get(id, false):
			continue
		var will: Dictionary = s.wills.get(id, {})
		if not will.is_empty() and will["on_hold"] and int(s.psd.get(id, 0)) >= int(will["arrears"]):
			return {"player": id, "command": {"type": "will_catch_up"}}
	if proposals_this_term(s) >= 3 or s.term.is_empty():
		return {}
	var by_cash: Array = s.player_ids.duplicate()
	by_cash.sort_custom(func(a, b): return int(s.psd.get(a, 0)) < int(s.psd.get(b, 0)))   # the poorest ask first
	for id in by_cash:
		if id == keeper or s.eliminated.get(id, false) or s.wills.has(id) or s.will_offers.has(id):
			continue
		var heir: int = 0
		for step_on in range(1, s.player_ids.size()):
			var candidate: int = s.player_ids[(s.player_ids.find(id) + step_on) % s.player_ids.size()]
			if not s.eliminated.get(candidate, false):
				heir = candidate
				break
		if heir == 0:
			continue
		var command := {"type": "will_propose", "lawyer": keeper, "psd_heir": heir, "fee": 10, "upkeep": 15 + 10 * (id % 3)}
		if (id + s.current_round) % 3 == 0:
			command["role_heir"] = 0
		return {"player": id, "command": command}
	return {}


func proposals_this_term(s: GameStateScript) -> int:
	var n: int = 0
	for i in range(s.event_log.size() - 1, -1, -1):
		var kind: String = s.event_log[i]["type"]
		if kind == "term_started":
			break
		if kind == "will_proposed":
			n += 1
	return n


func count_events(s: GameStateScript, type: String) -> int:
	var n: int = 0
	for event in s.event_log:
		if event["type"] == type:
			n += 1
	return n


# How many doses have been offered since the current term began.
func offers_this_term(s: GameStateScript) -> int:
	var n: int = 0
	for i in range(s.event_log.size() - 1, -1, -1):
		var kind: String = s.event_log[i]["type"]
		if kind == "term_started":
			break
		if kind == "dose_offered":
			n += 1
	return n


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
	for id in s.wills:
		var will: Dictionary = s.wills[id]
		if s.eliminated.get(id, false):
			problems.append(where + "eliminated player %d still has a will" % id)
		if typeof(will["on_hold"]) != TYPE_BOOL or int(will.get("arrears", 0)) < 0 or int(will.get("upkeep", 0)) < 0:
			problems.append(where + "player %d has a malformed will" % id)
		if will.get("on_hold", false) != (int(will.get("arrears", 0)) > 0) and will.has("lawyer"):
			problems.append(where + "player %d's will: on hold and arrears disagree" % id)
	var in_union: Dictionary = {}
	for union_id in s.unions:
		var union: Dictionary = s.unions[union_id]
		if union["members"].is_empty() or union["members"][0] != union["owner"]:
			problems.append(where + "union %d: the Unionizer isn't its first member" % union_id)
		for member in union["members"]:
			if in_union.has(member):
				problems.append(where + "player %d is in two unions" % member)
			in_union[member] = union_id
			if s.eliminated.get(member, false):
				problems.append(where + "an eliminated player %d is in union %d" % [member, union_id])
	for owner in s.hands:
		if s.eliminated.get(owner, false) or s.hands[owner].is_empty():
			problems.append(where + "player %d has a hand that should not exist" % owner)
	if not s.role_cards.is_empty():
		var stickers: int = 0
		for card in s.role_cards:
			stickers += 1 if s.role_cards[card]["sticker"] else 0
			var holder: int = s.role_cards[card]["holder"]
			if holder != 0 and not RolesScript.has(s, holder, s.role_cards[card]["role"]):
				problems.append(where + "card %d (%s) is held by %d, who doesn't hold that role" % [card, s.role_cards[card]["role"], holder])
			if holder != 0 and s.eliminated.get(holder, false):
				problems.append(where + "an eliminated player %d holds card %d" % [holder, card])
		if stickers != 10:
			problems.append(where + "there are %d coup stickers, not 10" % stickers)
		for id in s.roles:
			for role in s.roles[id]:
				if RolesScript.card_of(s, id, role) == -1:
					problems.append(where + "player %d holds %s but no card says so" % [id, role])
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
