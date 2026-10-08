extends SceneTree

const GameScript = preload("res://scripts/game.gd")
const RolesScript = preload("res://scripts/roles.gd")
const SicknessScript = preload("res://scripts/sickness.gd")
const RoundEndScript = preload("res://scripts/round_end.gd")
const ViewsScript = preload("res://scripts/views.gd")
const SerializerScript = preload("res://scripts/serializer.gd")
const GameStateScript = preload("res://scripts/game_state.gd")
const PlayScript = preload("res://tests/play.gd")

const PRESIDENT = GameStateScript.LeaderType.PRESIDENT
const AGENT := 2   # the Leader, so it is their turn first
const OTHER := 3   # an Agent whose turn it is not

var failures: int = 0


func _init() -> void:
	who_may_check()
	checking_a_card()
	checking_a_will()
	checking_the_bead()
	once_a_round()
	secrecy()
	print("%d failure(s)" % failures)
	quit(1 if failures > 0 else 0)


func who_may_check() -> void:
	var s := game()
	expect("a player who isn't a Secret Agent can't check", send(s, 4, check("coup", {"target": 5, "role": "Doctor"}))[0]["reason"], "You don't hold the Secret Agent role.")
	s.sick[AGENT] = true
	expect("a sick Agent can't", send(s, AGENT, check("will", {"target": 5}))[0]["reason"], "Sick players can't use role powers.")
	s.sick[AGENT] = false
	s.popularity[AGENT] = -50
	expect("a CANCELLED Agent can't", send(s, AGENT, check("will", {"target": 5}))[0]["reason"], "CANCELLED players have no roles until they climb back.")
	s.popularity[AGENT] = 0
	for bad in [null, "Coup", 1, "agent", true]:
		expect("kind %s is refused" % str(bad), send(s, AGENT, {"type": "agent_check", "kind": bad})[0]["reason"], "Choose coup, will or bead.")
	expect("a refused check doesn't use up the power", s.agent_used.has(AGENT), false)


func checking_a_card() -> void:
	# Find one card with a sticker and one without, so both answers are tested.
	var with_sticker := ""
	var without := ""
	for role in ["Doctor", "Lawyer", "Agbero", "Activist"]:
		var s := game()
		RolesScript.grant(s, 5, role)
		if RolesScript.has_sticker(s, 5, role) and with_sticker == "":
			with_sticker = role
		if not RolesScript.has_sticker(s, 5, role) and without == "":
			without = role
	var s := game()
	expect("both a stickered and an unstickered card were found to test", [with_sticker != "", without != ""], [true, true])
	RolesScript.grant(s, 5, with_sticker)
	var ev := send(s, AGENT, check("coup", {"target": 5, "role": with_sticker}))
	expect("on their own turn the Agent learns a card has a sticker", [types(ev), ev[0]["sticker"], ev[0]["target"], ev[0]["role"]], [["agent_report"], true, 5, with_sticker])
	expect("... and the report is for the Agent alone", ev[0]["audience"], [AGENT])
	expect("... and sits in the log once", count(s.event_log, "agent_report"), 1)

	s = game()
	RolesScript.grant(s, 5, without)
	ev = send(s, AGENT, check("coup", {"target": 5, "role": without}))
	expect("... or that it doesn't", ev[0]["sticker"], false)

	s = game()
	RolesScript.grant(s, 5, "Doctor")
	expect("not on someone else's turn", send(s, OTHER, check("coup", {"target": 5, "role": "Doctor"}))[0]["reason"], "You can only check cards and wills on your own turn.")
	expect("a target must be a player in the game", send(s, AGENT, check("coup", {"target": 9, "role": "Doctor"}))[0]["reason"], "Choose a player who is in the game.")
	for bad in [null, "5", true, 5.0]:
		expect("target %s is refused" % str(bad), send(s, AGENT, check("coup", {"target": bad, "role": "Doctor"}))[0]["reason"], "Choose a player who is in the game.")
	expect("the target must hold the role", send(s, AGENT, check("coup", {"target": 5, "role": "Lawyer"}))[0]["reason"], "That player doesn't hold that role.")
	for bad in [null, 5, "doctor"]:
		expect("role %s is refused" % str(bad), send(s, AGENT, check("coup", {"target": 5, "role": bad}))[0]["reason"], "That player doesn't hold that role.")
	s.eliminated[5] = true
	expect("an eliminated player can't be checked", send(s, AGENT, check("coup", {"target": 5, "role": "Doctor"}))[0]["reason"], "Choose a player who is in the game.")
	expect("... and none of those refusals used the power", s.agent_used.has(AGENT), false)

	s = game()
	RolesScript.grant(s, AGENT, "Lawyer")
	expect("an Agent may check their own card", types(send(s, AGENT, check("coup", {"target": AGENT, "role": "Lawyer"}))), ["agent_report"])


func checking_a_will() -> void:
	var s := game()
	s.wills[5] = {"psd_heir": 4, "role_heir": 1, "on_hold": true, "lawyer": 3, "upkeep": 20, "arrears": 20}
	var ev := send(s, AGENT, check("will", {"target": 5}))
	expect("the Agent learns what is in a will", [types(ev), ev[0]["will"]["psd_heir"], ev[0]["will"]["role_heir"], ev[0]["will"]["on_hold"]], [["agent_report"], 4, 1, true])
	expect("... for the Agent's eyes only", ev[0]["audience"], [AGENT])
	ev[0]["will"]["psd_heir"] = 99
	expect("the report is a copy of the will", s.wills[5]["psd_heir"], 4)

	s = game()
	expect("a player with no will has nothing to read", send(s, AGENT, check("will", {"target": 5}))[0]["reason"], "That player has no will.")
	expect("... and that didn't use the power", s.agent_used.has(AGENT), false)
	s.wills[5] = {"psd_heir": 4, "on_hold": false}
	expect("not on someone else's turn", send(s, OTHER, check("will", {"target": 5}))[0]["reason"], "You can only check cards and wills on your own turn.")
	for bad in [null, "5", 99]:
		expect("will target %s is refused" % str(bad), send(s, AGENT, check("will", {"target": bad}))[0]["reason"], "Choose a player who is in the game.")


func checking_the_bead() -> void:
	var s := game()
	expect("with no dose in progress there is no bead", send(s, OTHER, check("bead", {}))[0]["reason"], "No Doctor is handing over a bead.")
	RolesScript.grant(s, 5, "Doctor")
	SicknessScript.sicken(s, 4, 2)
	send(s, 5, {"type": "dose_offer", "patient": 4, "kind": "heal", "dose": "Agbo", "price": 10, "poison": true})
	var ev := send(s, OTHER, check("bead", {}))
	expect("while a dose is offered the Agent can see the bead, even off their own turn", [types(ev), ev[0]["bead"], ev[0]["doctor"], ev[0]["patient"], ev[0]["audience"]], [["agent_report"], "red", 5, 4, [OTHER]])

	s = game()
	RolesScript.grant(s, 5, "Doctor")
	SicknessScript.sicken(s, 4, 2)
	send(s, 5, {"type": "dose_offer", "patient": 4, "kind": "heal", "dose": "Agbo", "price": 10, "poison": false})
	send(s, 4, {"type": "dose_respond", "accept": true})
	expect("... and while the guessing is open: a blue bead", send(s, OTHER, check("bead", {}))[0]["bead"], "blue")
	GameScript.tick(s, int(s.dose["deadline"]))
	s.agent_used.erase(OTHER)
	expect("... but not after the dose is given", send(s, OTHER, check("bead", {}))[0]["reason"], "No Doctor is handing over a bead.")

	s = game()
	RolesScript.grant(s, 5, "Doctor")
	RolesScript.grant(s, 4, "Secret Agent")
	SicknessScript.sicken(s, 3, 2)
	send(s, 5, {"type": "dose_offer", "patient": 3, "kind": "heal", "dose": "Agbo", "price": 10, "poison": true})
	expect("the patient, if an Agent, may look too", types(send(s, 4, check("bead", {}))), ["agent_report"])
	RolesScript.grant(s, 5, "Secret Agent")
	expect("the Doctor can't check their own bead", send(s, 5, check("bead", {}))[0]["reason"], "It is your own bead.")

	s = game()
	RolesScript.grant(s, 5, "Doctor")
	send(s, 5, {"type": "dose_offer", "patient": 4, "kind": "sicken", "dose": "Agbo", "price": 10})
	expect("a sickening dose has no bead", send(s, OTHER, check("bead", {}))[0]["reason"], "No Doctor is handing over a bead.")


func once_a_round() -> void:
	var s := game()
	RolesScript.grant(s, 5, "Doctor")
	RolesScript.grant(s, 5, "Lawyer")
	expect("the first check works", types(send(s, AGENT, check("coup", {"target": 5, "role": "Doctor"}))), ["agent_report"])
	expect("a second check in the same round does not", send(s, AGENT, check("coup", {"target": 5, "role": "Lawyer"}))[0]["reason"], "You have already used your power this round.")
	expect("... of any kind", send(s, AGENT, check("will", {"target": 5}))[0]["reason"], "You have already used your power this round.")
	RoundEndScript.run(s)
	expect("the power comes back when the round ends", [s.agent_used, types(send(s, AGENT, check("coup", {"target": 5, "role": "Lawyer"})))], [{AGENT: true}, ["agent_report"]])
	# The bead check counts too.
	s = game()
	RolesScript.grant(s, 5, "Doctor")
	SicknessScript.sicken(s, 4, 2)
	send(s, 5, {"type": "dose_offer", "patient": 4, "kind": "heal", "dose": "Agbo", "price": 10, "poison": false})
	send(s, OTHER, check("bead", {}))
	expect("looking at the bead uses the round's one check", send(s, OTHER, check("bead", {}))[0]["reason"], "You have already used your power this round.")


func secrecy() -> void:
	var s := game()
	RolesScript.grant(s, 5, "Doctor")
	send(s, AGENT, check("coup", {"target": 5, "role": "Doctor"}))
	for viewer in [1, 3, 4, 5]:
		var seen: Array = ViewsScript.visible_events(s.event_log, viewer).filter(func(e): return e["type"] == "agent_report")
		expect("player %d is never shown the report" % viewer, seen, [])
	expect("the Agent is", ViewsScript.visible_events(s.event_log, AGENT).filter(func(e): return e["type"] == "agent_report").size(), 1)
	expect("who has used their power is not in anyone's view", [ViewsScript.state_view(s, 1).has("agent_used"), ViewsScript.state_view(s, AGENT).has("agent_used")], [false, false])
	var errors: Array = []
	var restored: GameStateScript = SerializerScript.state_from_json(SerializerScript.state_to_json(s), errors)
	expect("a saved game remembers who has checked", [errors, restored.agent_used], [[], {AGENT: true}])


# --- helpers -----------------------------------------------------------------------------

# Player 2 leads and has the first turn; players 2 and 3 are Secret Agents.
func game() -> GameStateScript:
	for seed_value in range(1, 400):
		var s := GameScript.new_game([1, 2, 3, 4, 5], seed_value)
		for id in [1, 2, 3, 4, 5]:
			GameScript.handle(s, id, {"type": "cast_vote", "candidate": 2})
		if s.leader_type == PRESIDENT:
			GameScript.handle(s, 2, {"type": "pass_window"})
			RolesScript.grant(s, AGENT, "Secret Agent")
			RolesScript.grant(s, OTHER, "Secret Agent")
			return s
	assert(false, "no seed gave a President")
	return null


func check(kind: String, extra: Dictionary) -> Dictionary:
	var command := {"type": "agent_check", "kind": kind}
	for key in extra:
		command[key] = extra[key]
	return command


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
