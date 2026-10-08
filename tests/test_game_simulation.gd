extends SceneTree

# Whole games, played by scripted players through Game.handle, the same door a real server uses.
# After EVERY move the rules of the whole system are checked, not just what that move was meant
# to do. A bug anywhere (money, debt, turn order, elections, saves) shows up here as a broken rule.

const GameScript = preload("res://scripts/game.gd")
const SerializerScript = preload("res://scripts/serializer.gd")
const PopularityScript = preload("res://scripts/popularity.gd")
const GameStateScript = preload("res://scripts/game_state.gd")
const DoctorScript = preload("res://scripts/doctor.gd")
const CoupScript = preload("res://scripts/coup.gd")
const UnionsScript = preload("res://scripts/unions.gd")
const SicknessScript = preload("res://scripts/sickness.gd")
const RolesScript = preload("res://scripts/roles.gd")
const CardsScript = preload("res://scripts/cards.gd")
const CorruptionScript = preload("res://scripts/corruption.gd")
const RivalsScript = preload("res://scripts/rivals.gd")
const LoyalistsScript = preload("res://scripts/loyalists.gd")
const PermissionsScript = preload("res://scripts/permissions.gd")
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
var pay_fines: bool = false   # a frozen player in the simulation pays the fine as soon as they can


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
	for kind in ["agent_requested", "agent_refused", "agent_request_expired"]:
		expect("... and was hired: a '%s' event (%d times)" % [kind, dose_types.count(kind)], dose_types.has(kind), true)
	for kind in ["dose_offered", "dose_accepted", "dose_rejected", "dose_expired", "sabotage_guessed", "dose_given", "sickened", "sickness_lengthened", "sickness_shortened", "recovered", "licence_lost", "dose_void"]:
		expect("the Doctor games produced a '%s' event (%d times)" % [kind, dose_types.count(kind)], dose_types.has(kind) or kind in ["dose_void"], true)
	var doc_straight := play(5, 303, 6, 0, 0, 3, 0, 4)
	var doc_restarted := play(5, 303, 6, 0, 5, 3, 0, 4)
	expect("a server restarting from its save every 5 moves, mid-dose or not, gives the same Doctor game", [doc_restarted["problems"], doc_restarted["final"] == doc_straight["final"]], [[], true])

	# A Lawyer at the table: wills proposed, signed, charged upkeep, put on hold and reactivated.
	var will_types: Array = []
	var mirrored_votes: int = 0
	for seed_value in range(1, 9):
		var run := play(5, 400 + seed_value, 7, 3, 0, 0, 2, 4)
		will_types.append_array(run["types"])
		mirrored_votes += run["mirrored"]
		expect("Lawyer game %d: ran to the end (%d moves)" % [seed_value, run["steps"]], run["finished"], true)
		expect("Lawyer game %d: no rule was ever broken" % seed_value, run["problems"], [])
	expect("Loyalists voted with their owners in these games (%d votes)" % mirrored_votes, mirrored_votes > 0, true)
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
			"command_started", "command_performance_started", "command_voting_opened", "command_vote_cast", "command_performance_resolved", "union_pitched"]:
		expect("the union games produced a '%s' event (%d times)" % [kind, union_types.count(kind)], union_types.has(kind), true)
	var union_straight := play(5, 503, 7, 0, 0, 0, 0, 0, true)
	var union_restarted := play(5, 503, 7, 0, 5, 0, 0, 0, true)
	expect("a server restarting from its save every 5 moves, with invitations waiting or not, gives the same union game", [union_restarted["problems"], union_restarted["final"] == union_straight["final"]], [[], true])

	# Coups at the table: real coups and deals, with the round stopping and the new Leader going first.
	var coup_types: Array = []
	for seed_value in range(1, 9):
		var run := play(5, 600 + seed_value, 7, 0, 0, 0, 0, 0, false, true)
		coup_types.append_array(run["types"])
		expect("coup game %d: ran to the end (%d moves)" % [seed_value, run["steps"]], run["finished"], true)
		expect("coup game %d: no rule was ever broken" % seed_value, run["problems"], [])
	for kind in ["coup_succeeded", "coup_failed", "coup_deal", "leader_installed"]:
		expect("the coup games produced a '%s' event (%d times)" % [kind, coup_types.count(kind)], coup_types.has(kind), true)
	var coup_straight := play(5, 603, 7, 0, 0, 0, 0, 0, false, true)
	var coup_restarted := play(5, 603, 7, 0, 5, 0, 0, 0, false, true)
	expect("a server restarting from its save every 5 moves gives the same coup game", [coup_restarted["problems"], coup_restarted["final"] == coup_straight["final"]], [[], true])

	# Corruption at the table: a frozen player who pays the fine, and one who waits it out.
	var corruption_types: Array = []
	for seed_value in range(1, 9):
		pay_fines = seed_value % 2 == 0
		var run := play(5, 700 + seed_value, 7, 0, 0, 0, 0, 0, false, false, 5)
		corruption_types.append_array(run["types"])
		expect("corruption game %d: ran to the end (%d moves)" % [seed_value, run["steps"]], run["finished"], true)
		expect("corruption game %d: no rule was ever broken" % seed_value, run["problems"], [])
	pay_fines = false
	for kind in ["marker_gained", "fine_paid", "freeze_expired"]:   # the freeze itself happens at set-up
		expect("the corruption games produced a '%s' event (%d times)" % [kind, corruption_types.count(kind)], corruption_types.has(kind), true)
	pay_fines = true
	var corrupt_straight := play(5, 702, 7, 0, 0, 0, 0, 0, false, false, 5)
	var corrupt_restarted := play(5, 702, 7, 0, 5, 0, 0, 0, false, false, 5)
	pay_fines = false
	expect("a server restarting from its save every 5 moves gives the same corruption game", [corrupt_restarted["problems"], corrupt_restarted["final"] == corrupt_straight["final"]], [[], true])

	# Everything that can happen did happen somewhere.
	var seen := play(5, 7, 6)
	for kind in ["election_started", "exam_written", "exam_revealed", "vote_started", "leader_elected", "leader_installed",
			"term_started", "levy_collected", "turn_started", "turn_ended", "farewell_opened", "term_ended", "window_passed",
			"amendment_proposed", "amendment_resolved", "article_changed", "ballot_cast", "exam_answered",
			"performance_started", "performance_voting_opened", "performance_vote_cast", "performance_resolved", "income_paid", "card_applied"]:
		expect("a played game produced a '%s' event" % kind, seen["types"].has(kind), true)

	# Choices come up too (only some cards ask for one, so across all the ordinary games).
	for kind in ["choice_needed", "choice_made", "role_gained", "card_played", "union_founded", "vice_appointed", "amendment_offered", "debate_started", "debate_turn", "debate_vote_cast", "union_pitch_unavailable", "exam_skipped", "exam_timeout", "vote_timeout", "window_passed", "poll_opened", "poll_closed", "hospital_opened", "diaspora_set", "flyover_gave", "modifier_given", "stipend_set", "card_buried"]:
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
func play(player_count: int, seed_value: int, terms: int, poor: int = 0, restart_every: int = 0, doctor: int = 0, lawyer: int = 0, agent: int = 0, unions: bool = false, coups: bool = false, corrupt: int = 0) -> Dictionary:
	var ids: Array = range(1, player_count + 1)
	var genders: Dictionary = {}
	if seed_value <= 12 and seed_value % 2 == 0:
		for id in ids:
			genders[id] = "male" if id % 2 == 0 else "female"   # so the cards that ask for men or women have someone to ask
	var s := GameScript.new_game(ids, seed_value, genders)
	if seed_value <= 12 and seed_value % 2 == 0:
		# Every Settlement card with a rule of its own comes up early (drawn from the end of the list).
		s.decks["settlement"] = [1, 3, 4, 6, 10, 12, 13, 14, 16, 17, 24, 27, 28, 29, 34, 38, 39, 41, 44, 45, 46, 47, 48, 49]
	if poor != 0:
		s.treasury += s.psd[poor] - 30
		s.psd[poor] = 30
		s.wills[poor] = {"psd_heir": 4, "on_hold": false}
	if doctor != 0:
		RolesScript.grant(s, doctor, "Doctor")   # a Doctor from the start, so doses are given all game
	if coups:
		# Two popular challengers, each holding a coup card (a role card with a sticker), so coups and deals happen.
		for challenger in [4, 5]:
			for role in RolesScript.names():
				if RolesScript.has(s, challenger, role):
					continue
				RolesScript.grant(s, challenger, role)
				if RolesScript.has_sticker(s, challenger, role):
					break
				RolesScript.remove(s, challenger, role)
			PopularityScript.change_base(s, challenger, 35 if challenger == 4 else 28)
	if unions:
		s.decks["performance"] = [10, 10, 10, 10, 10, 10]   # "A rival union wants your backing" comes up often, with unions about
		# Union cards in hand (played as soon as possible) and two Agberos, so mobs form, recruit, shrink,
		# disperse and re-form inside whole games.
		s.hands[3] = [{"deck": "settlement", "card": 8}]
		s.hands[1] = [{"deck": "settlement", "card": 7}]
		s.hands[5] = [{"deck": "settlement", "card": 9}]
		RolesScript.grant(s, 3, "Agbero")
		RolesScript.grant(s, 4, "Agbero")
	if seed_value <= 12 and seed_value % 4 == 1:
		s.decks["performance"] = [15, 15, 10]   # two debates, then a rival union's pitch: they are the first cards drawn
	if seed_value <= 12 and seed_value % 3 == 0:
		s.decks["settlement"] = [11]   # the keys to the city are the first Settlement card drawn, so the Vice appears
	if seed_value >= 300 and seed_value < 500 and seed_value % 2 == 1:
		# Loyalty chains from the start (3 > 4 > 5, for the length of the game), so ballots of every kind are mirrored.
		LoyalistsScript.appoint(s, 3, 4, 100)
		LoyalistsScript.appoint(s, 4, 5, 100)
	if corrupt != 0:
		# Frozen by corruption from the start, with two roles to lose. pay_fines says whether they pay the fine as soon
		# as they can or wait the freeze out. A second player holds one marker, which stays unfrozen.
		RolesScript.grant(s, corrupt, "Doctor")
		RolesScript.grant(s, corrupt, "Activist")
		for i in 3:
			CorruptionScript.give(s, corrupt)
		CorruptionScript.give(s, 2)
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
	var mirrored: int = 0   # votes a Loyalist cast with their owner
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
			if event.has("with"):
				mirrored += 1
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
		"eliminated": eliminated, "leaders": leaders, "windfalls": windfalls, "mirrored": mirrored, "final": SerializerScript.state_to_json(s)}


# What a sensible player does next, in the order the game needs it: an election first, then an
# amendment being decided, then the term.
func next_move(s: GameStateScript) -> Dictionary:
	if not s.election.is_empty():
		return election_move(s)
	if not s.amend_offer.is_empty():
		# The other of the Leader and the Vice agrees to the proposal, except now and then, when they let the time run out.
		if (s.current_round + s.amend_offer["by"]) % 4 == 3:
			return {"tick": int(s.amend_offer["deadline"])}
		return {"player": s.amend_offer["other"], "command": {"type": "amend_agree", "accept": (s.current_round + s.amend_offer["other"]) % 5 != 0}}
	var polling := poll_move(s)
	if not polling.is_empty():
		return polling
	var choosing := choice_move(s)
	if not choosing.is_empty():
		return choosing
	for permit in s.peeks:
		if permit["kinds"].has("coup") and (s.peeks.size() > 1 or s.current_round % 2 == 0):   # free checks are used now and then
			return {"player": permit["holder"], "command": {"type": "peek", "target": permit["target"], "kind": "coup"}}
	var played := hand_move(s)
	if not played.is_empty():
		return played
	var coup := coup_move(s)
	if not coup.is_empty():
		return coup
	if pay_fines:
		for id in s.frozen:
			if s.psd.get(id, 0) >= 200:
				return {"player": id, "command": {"type": "pay_fine"}}
	var hiring := hire_move(s)
	if not hiring.is_empty():
		return hiring
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
			# With a Vice in the term, every third round it is the Vice who proposes the tax amendment (the Leader agrees).
			if s.vice_id != -1 and s.current_round % 3 == 0 and not window_used(s) and amend_offers_this_term(s) == 0 and PermissionsScript.leader_powers_problem(s, s.vice_id) == "":
				return {"player": s.vice_id, "command": tax_amendment(s)}
			# Every other term the Leader tries to amend the tax rate; otherwise they pass.
			if s.current_round % 2 == 0 and s.leader_type != GameStateScript.LeaderType.COMMANDER and not window_used(s) and amend_offers_this_term(s) == 0:
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
		"players":
			answer = s.choice["candidates"].slice(0, (s.current_round + chooser) % (s.choice["max"] + 1))
		"number":
			answer = s.choice["min"] + (s.current_round + chooser) % (s.choice["max"] - s.choice["min"] + 1)
	return {"player": chooser, "command": {"type": "choose", "choice": answer}}


# A question a card put to several players: each answers (option by who they are and the round), or lets the time run out.
func poll_move(s: GameStateScript) -> Dictionary:
	for poll in s.polls:
		if (poll["id"] + s.current_round) % 4 == 0:
			return {"tick": int(poll["deadline"])}
		for id in poll["targets"]:
			if not poll["answers"].has(id):
				return {"player": id, "command": {"type": "poll_answer", "poll": poll["id"], "option": (id + poll["id"]) % poll["labels"].size()}}
	return {}


# Players play the union cards they are keeping as soon as they can.
func hand_move(s: GameStateScript) -> Dictionary:
	var owners: Array = s.hands.keys()
	owners.sort()
	for owner in owners:
		if s.eliminated.get(owner, false) or UnionsScript.problem_founding(s, owner) != "":
			continue
		for i in s.hands[owner].size():
			if not CardsScript.effects(s.hands[owner][i]["deck"], s.hands[owner][i]["card"]).has("special"):
				return {"player": owner, "command": {"type": "play_card", "index": i}}
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
			var voter: int = first_free(s, waiting)
			return {"player": voter, "command": {"type": "command_vote", "good": (voter + count_events(s, "command_started")) % 3 != 0}}
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
					if candidate != union["owner"] and not s.eliminated.get(candidate, false) and candidate != s.leader_id and candidate != s.vice_id \
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


# Coups: a player who can attempt one does, now and then, and now and then makes a deal instead. Limited by counts so the
# game goes on. Only moves the game would accept are made.
func coup_move(s: GameStateScript) -> Dictionary:
	if s.game_over or s.term.is_empty() or not s.election.is_empty():
		return {}
	var done: int = count_events(s, "coup_succeeded") + count_events(s, "coup_deal")
	if done >= 6 or count_events(s, "turn_ended") % 5 != 3 or recently(s, ["coup_succeeded", "coup_deal"]):
		return {}
	for id in s.player_ids:
		if CoupScript._problem_with(s, id) != "" or RolesScript.coup_cards(s, id).is_empty():
			continue
		var gap: int = PopularityScript.effective(s, id) - PopularityScript.effective(s, s.leader_id)
		if done % 2 == 0 and (gap >= 20 or done % 4 == 2):
			return {"player": id, "command": {"type": "coup"}}   # (every so often a coup that is bound to fail)
		if done % 2 == 1:
			return {"player": id, "command": {"type": "coup", "deal": true}}
	return {}


# Did one of these events happen since the last turn ended?
func recently(s: GameStateScript, kinds: Array) -> bool:
	for i in range(s.event_log.size() - 1, -1, -1):
		var kind: String = s.event_log[i]["type"]
		if kind == "turn_ended":
			return false
		if kind in kinds:
			return true
	return false


# Hiring a Secret Agent: on the Agent's own turn another player asks for a card or a will to be checked; the Agent
# accepts, refuses or says nothing. Limited per term, since a refused request costs nothing.
func hire_move(s: GameStateScript) -> Dictionary:
	if s.game_over or s.term.is_empty():
		return {}
	var agents: Array = s.agent_offers.keys()
	agents.sort()
	for agent in agents:
		var number: int = count_events(s, "agent_requested")
		if number % 5 == 2:
			return {"tick": int(s.agent_offers[agent]["deadline"])}   # the Agent never answers
		return {"player": agent, "command": {"type": "agent_respond", "client": s.agent_offers[agent]["client"], "accept": number % 3 != 0}}
	var waiting: Array = s.term.get("waiting", [])
	if s.term.get("phase", 0) != GameStateScript.TermPhase.TURNS or waiting.is_empty():
		return {}
	var now: int = waiting[0]
	if not RolesScript.has(s, now, "Secret Agent") or s.agent_used.get(now, false) or RolesScript.can_use_pledge(s, now, "Secret Agent") != "":
		return {}
	if hires_this_term(s) >= 2:
		return {}
	var client: int = 0
	for id in s.player_ids:
		if id != now and not s.eliminated.get(id, false):
			client = id
			break
	if client == 0:
		return {}
	for testator in s.wills:
		if not s.eliminated.get(testator, false):
			return {"player": client, "command": {"type": "agent_hire", "agent": now, "kind": "will", "target": testator, "price": 15}}
	for holder in s.roles:
		if not s.eliminated.get(holder, false) and not s.roles[holder].is_empty():
			return {"player": client, "command": {"type": "agent_hire", "agent": now, "kind": "coup", "target": holder, "role": s.roles[holder][0], "price": 15}}
	return {}


# Proposals to amend that waited for agreement since the term began: a refused or lapsed one uses nothing up, so the
# script must not propose forever.
func amend_offers_this_term(s: GameStateScript) -> int:
	var n: int = 0
	for i in range(s.event_log.size() - 1, -1, -1):
		var kind: String = s.event_log[i]["type"]
		if kind == "term_started":
			break
		if kind == "amendment_offered":
			n += 1
	return n


func hires_this_term(s: GameStateScript) -> int:
	var n: int = 0
	for i in range(s.event_log.size() - 1, -1, -1):
		var kind: String = s.event_log[i]["type"]
		if kind == "term_started":
			break
		if kind == "agent_requested":
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
	if RolesScript.can_use_pledge(s, keeper, "Lawyer") != "":
		return {}   # a sick (or frozen) Lawyer keeps no wills for now
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
	if act.has("debate"):
		return debate_move(s, act)
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
			var voter: int = first_free(s, waiting)
			return {"player": voter, "command": {"type": "performance_vote", "good": (voter * 7 + act["card"]) % 3 != 0}}
	return {"player": performer, "command": {"type": "end_turn"}}


# A debate card: the performer challenges (or lets the time run out), each side speaks or runs out the clock, the table
# votes for the winner (some never vote).
func debate_move(s: GameStateScript, act: Dictionary) -> Dictionary:
	var performer: int = act["player"]
	var debate: Dictionary = act["debate"]
	if act["phase"] == GameStateScript.ActPhase.PERFORMING:
		if debate["rival"] == 0:
			if (performer + s.current_round) % 3 == 0:
				return {"tick": int(act["deadline"])}
			var candidates: Array = RivalsScript.candidates(s, performer)
			return {"player": performer, "command": {"type": "debate_challenge", "rival": candidates[0], "topic": "the price of garri"}}
		var speaker: int = performer if debate["side"] == 0 else debate["rival"]
		if (speaker + s.turns_played) % 2 == 0:
			return {"player": speaker, "command": {"type": "debate_finish"}}
		return {"tick": int(act["deadline"])}
	if act["phase"] == GameStateScript.ActPhase.VOTING:
		var waiting: Array = []
		for id in s.player_ids:
			if id != performer and id != debate["rival"] and not s.eliminated.get(id, false) and not act["votes"].has(id):
				waiting.append(id)
		if waiting.is_empty() or (act["votes"].size() >= 1 and act["card"] % 2 == 0):
			return {"tick": int(act["deadline"])}   # the rest never voted
		var voter: int = first_free(s, waiting)
		return {"player": voter, "command": {"type": "debate_vote", "winner": performer if (voter + act["card"]) % 3 != 0 else debate["rival"]}}
	return {"player": performer, "command": {"type": "end_turn"}}


func window_used(s: GameStateScript) -> bool:
	var window: int = GameStateScript.AmendWindow.INAUGURATION if s.term["phase"] == INAUGURATION else GameStateScript.AmendWindow.FAREWELL
	return s.windows_used[window]


func election_move(s: GameStateScript) -> Dictionary:
	match s.election["phase"]:
		EXAM_WRITING:
			if s.current_round % 3 == 2:
				return {"tick": int(s.election["deadline"])}   # the Leader never writes it
			var questions: Array = []
			for i in 5:
				questions.append({"text": "Question %d?" % (i + 1), "options": ["A", "B", "C"], "answer": (i + s.current_round) % 3})
			return {"player": s.leader_id, "command": {"type": "write_exam", "questions": questions}}
		EXAM_ANSWERING:
			if s.current_round % 4 == 1 and not s.election["answers"].is_empty():
				return {"tick": int(s.election["deadline"])}   # the slow ones fail
			for id in s.election["takers"]:
				if id in s.election["answers"] or s.eliminated.get(id, false) or s.sick.get(id, false):
					continue
				# Some players get everything right, some everything wrong.
				var answers: Array = []
				for key in s.election["key"]:
					answers.append(key if (id + s.current_round) % 3 != 0 else (key + 1) % 3)
				return {"player": id, "command": {"type": "answer_exam", "answers": answers}}
		VOTING:
			if s.current_round % 5 == 0 and not s.election["votes"].is_empty():
				return {"tick": int(s.election["deadline"])}   # the rest abstain
			for id in s.election["voters"]:
				if id in s.election["votes"] or s.eliminated.get(id, false) or s.sick.get(id, false):
					continue
				var waiting: Array = s.election["voters"].filter(func(v): return not v in s.election["votes"] and not s.eliminated.get(v, false) and not s.sick.get(v, false))
				var voter: int = first_free(s, waiting)
				var candidates: Array = s.election["candidates"]
				return {"player": voter, "command": {"type": "cast_vote", "candidate": candidates[(voter + s.current_round) % candidates.size()]}}
	return {}


func amendment_move(s: GameStateScript) -> Dictionary:
	if s.amend["phase"] == GameStateScript.AmendPhase.PROPOSED:
		return {"player": SERVER, "command": {"type": "rule_grammar", "ok": true}}
	var waiting: Array = []
	for id in s.player_ids:
		if id == s.leader_id or id == s.vice_id or s.eliminated.get(id, false) or s.sick.get(id, false) or s.amend["votes"].has(id):
			continue
		waiting.append(id)
	if waiting.is_empty():
		return {}
	return {"player": first_free(s, waiting), "command": {"type": "vote", "keep": true}}


# Of the players still to vote, the first who is not waiting on their owner's vote (a Loyalist votes with them).
func first_free(s: GameStateScript, waiting: Array) -> int:
	for id in waiting:
		if not LoyalistsScript.owner_of(s, id) in waiting:
			return id
	return waiting[0]


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
	var held_total: int = 0
	for id in s.markers:
		held_total += s.markers[id]
		if s.eliminated.get(id, false) or s.markers[id] <= 0 or s.markers[id] > CorruptionScript.limit():
			problems.append(where + "player %d holds %d markers" % [id, s.markers[id]])
		if (s.markers[id] == CorruptionScript.limit()) != s.frozen.has(id):
			problems.append(where + "player %d: markers and the freeze disagree" % id)
	if held_total > 15:
		problems.append(where + "%d markers are out, but the box holds 15" % held_total)
	for id in s.frozen:
		if not s.markers.has(id) or s.frozen[id]["left"] <= 0:
			problems.append(where + "player %d is frozen without markers or time" % id)
		if RolesScript.can_use_pledge(s, id, "Doctor") == "" and RolesScript.has(s, id, "Doctor"):
			problems.append(where + "frozen player %d can still use a pledge" % id)
	for owner in s.rivals:
		if s.eliminated.get(owner, false) or s.rivals[owner].is_empty() or owner in s.rivals[owner]:
			problems.append(where + "player %d has a malformed rival list" % owner)
		for rival in s.rivals[owner]:
			if s.eliminated.get(rival, false):
				problems.append(where + "player %d has an eliminated rival %d" % [owner, rival])
	for pair in s.truces:
		if s.eliminated.get(pair[0], false) or s.eliminated.get(pair[1], false) or pair[0] == pair[1]:
			problems.append(where + "a truce %s involves a player who left or is the same twice" % str(pair))
	for entry in s.accords:
		if s.eliminated.get(entry["a"], false) or s.eliminated.get(entry["b"], false) or entry["left"] <= 0:
			problems.append(where + "an accord %s should have ended" % str(entry))
	for id in s.skip_draw:
		if s.eliminated.get(id, false):
			problems.append(where + "an eliminated player %d still loses a draw" % id)
	if s.vice_id != -1:
		if s.eliminated.get(s.vice_id, false) or s.vice_id == s.leader_id or s.leader_id == -1:
			problems.append(where + "malformed Vice %d (Leader %d)" % [s.vice_id, s.leader_id])
	if not s.amend_offer.is_empty():
		var offer: Dictionary = s.amend_offer
		if not (offer["by"] == s.leader_id and offer["other"] == s.vice_id) and not (offer["by"] == s.vice_id and offer["other"] == s.leader_id):
			problems.append(where + "a proposal waits for agreement from someone who is not the other of the pair")
	for follower in s.loyalists:
		var owner: int = s.loyalists[follower]["owner"]
		if s.eliminated.get(follower, false) or s.eliminated.get(owner, false) or owner == follower or s.loyalists[follower]["left"] <= 0:
			problems.append(where + "malformed loyalty: %d follows %d" % [follower, owner])
		var up: int = owner
		var hops: int = 0
		while up != 0 and hops < 20:
			up = LoyalistsScript.owner_of(s, up)
			hops += 1
		if hops >= 20:
			problems.append(where + "a circle of loyalty through %d" % follower)
	for permit in s.peeks:
		if permit["holder"] == permit["target"] or s.eliminated.get(permit["holder"], false) or s.eliminated.get(permit["target"], false) or permit["kinds"].is_empty():
			problems.append(where + "malformed free check %s" % str(permit))
	for id in s.mods:
		if s.eliminated.get(id, false) or s.mods[id].is_empty():
			problems.append(where + "player %d has modifiers they shouldn't" % id)
		for name in s.mods[id]:
			var record: Dictionary = s.mods[id][name]
			if int(record["uses"]) == 0 or (int(record["until"]) != -1 and int(record["until"]) < int(record["from"])):
				problems.append(where + "player %d's modifier %s is malformed: %s" % [id, name, str(record)])
	for entry in s.schedule:
		for key in ["player", "borrower", "lender"]:
			if entry.has(key) and s.eliminated.get(entry[key], false):
				problems.append(where + "a scheduled entry %s involves an eliminated player" % str(entry))
	for poll in s.polls:
		if poll["targets"].is_empty() or s.eliminated.get(poll["drawer"], false):
			problems.append(where + "a poll with nobody to ask or no drawer: %s" % str(poll))
	if s.choice.is_empty() and not s.choice_queue.is_empty():
		problems.append(where + "questions are queued but none is open")
	for seller in s.card_offers:
		if s.eliminated.get(seller, false) or s.eliminated.get(s.card_offers[seller]["buyer"], false):
			problems.append(where + "a card offer involves an eliminated player")
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
