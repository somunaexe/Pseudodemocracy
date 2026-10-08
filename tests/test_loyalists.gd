extends SceneTree

const GameScript = preload("res://scripts/game.gd")
const GameStateScript = preload("res://scripts/game_state.gd")
const FlowScript = preload("res://scripts/amendment_flow.gd")
const ConstitutionScript = preload("res://scripts/constitution.gd")
const CardsScript = preload("res://scripts/cards.gd")
const CardEffectsScript = preload("res://scripts/card_effects.gd")
const LoyalistsScript = preload("res://scripts/loyalists.gd")
const RoundEndScript = preload("res://scripts/round_end.gd")
const RolesScript = preload("res://scripts/roles.gd")
const PopularityScript = preload("res://scripts/popularity.gd")
const EliminationScript = preload("res://scripts/elimination.gd")
const SerializerScript = preload("res://scripts/serializer.gd")
const ViewsScript = preload("res://scripts/views.gd")
const PlayScript = preload("res://tests/play.gd")

const PRESIDENT = GameStateScript.LeaderType.PRESIDENT
const ACTIVIST = GameStateScript.UnionType.ACTIVIST
const TAX := 2

var failures: int = 0


func _init() -> void:
	appointing()
	the_appointee_card()
	performance_votes()
	election_votes()
	amendment_votes()
	command_votes()
	time_and_defection()
	gender_penalty()
	leaving_the_game()
	views_and_saves()
	print("%d failure(s)" % failures)
	quit(1 if failures > 0 else 0)


func appointing() -> void:
	var s := new_turn()
	expect("nobody is loyal to start with", [LoyalistsScript.owner_of(s, 4), LoyalistsScript.followers_of(s, 3)], [0, []])
	var ev := LoyalistsScript.appoint(s, 3, 4, 3)
	expect("3 appoints 4 for 3 rounds", [ev[0]["type"], LoyalistsScript.owner_of(s, 4), s.loyalists[4]], ["loyalist_appointed", 3, {"owner": 3, "left": 3}])
	LoyalistsScript.appoint(s, 3, 5, 3)
	expect("an owner can have many Loyalists, in order", LoyalistsScript.followers_of(s, 3), [4, 5])
	LoyalistsScript.appoint(s, 1, 4, 2)
	expect("a new owner replaces the old", [LoyalistsScript.owner_of(s, 4), LoyalistsScript.followers_of(s, 3)], [1, [5]])
	expect("you can't be your own Loyalist", LoyalistsScript.problem_appointing(s, 3, 3), "You can't be your own Loyalist.")
	expect("... nor an eliminated player's", LoyalistsScript.problem_appointing(s, 3, 9), "That player is not in the game.")
	expect("a circle is refused: 3's own owner can't be 3's Loyalist", LoyalistsScript.problem_appointing(s, 4, 1), "They are already above you in a chain of loyalty.")
	LoyalistsScript.appoint(s, 4, 2, 3)   # 1 > 4 > 2
	expect("... also further up the chain", [LoyalistsScript.problem_appointing(s, 2, 1), LoyalistsScript.problem_appointing(s, 2, 4)], ["They are already above you in a chain of loyalty.", "They are already above you in a chain of loyalty."])
	expect("... but a stranger is fine", LoyalistsScript.problem_appointing(s, 2, 3), "")


func the_appointee_card() -> void:
	var card: int = card_number("settlement", "You appointed an unqualified friend")
	var s := new_turn()
	LoyalistsScript.appoint(s, 4, 3, 3)   # 4 is 3's owner: 4 can't be appointed by 3
	var total: int = total_money(s)
	CardEffectsScript.apply(s, 3, "settlement", card)
	expect("the offer leaves out whoever is above the drawer in the chain of loyalty", s.choice["candidates"], [1, 2, 5])
	var cash: int = s.psd[5]
	var roles: Array = RolesScript.held(s, 5)
	var ev := send(s, 3, {"type": "choose", "choice": 5})
	expect("they get 100 PSD, one role card and become a Loyalist for 3 rounds", [s.psd[5] - cash, RolesScript.held(s, 5).size() - roles.size(), LoyalistsScript.owner_of(s, 5), s.loyalists[5]["left"]], [100, 1, 3, 3])
	expect("... the events, in order", types(ev), ["choice_made", "role_gained", "loyalist_appointed"])
	expect("... the money came from the treasury", total_money(s), total)

	s = new_turn()
	for role in RolesScript.names():
		RolesScript.grant(s, 5, role)
	CardEffectsScript.apply(s, 3, "settlement", card)
	ev = send(s, 3, {"type": "choose", "choice": 5})
	expect("a player who can hold no more roles still becomes the Loyalist, and the event says why no role", [LoyalistsScript.owner_of(s, 5), ev[0]["skipped"].size()], [3, 1])

	# Only the last one is a candidate, once everyone else is above the drawer or can't be.
	s = new_turn()
	CardEffectsScript.apply(s, 3, "settlement", card)
	expect("the drawer is not offered themselves", s.choice["candidates"], [1, 2, 4, 5])
	var picks := {}
	for seed_value in 12:
		var g := new_turn()
		g.rng_state = seed_value + 1
		CardEffectsScript.apply(g, 3, "settlement", card)
		send(g, 3, {"type": "choose", "choice": 5})
		picks[RolesScript.held(g, 5)[0]] = true
	expect("the role is random: different games give different roles", picks.keys().size() > 1, true)


func performance_votes() -> void:
	var s := voting_s()
	LoyalistsScript.appoint(s, 3, 4, 3)
	expect("a Loyalist can't vote before their owner has", send(s, 4, vote(true))[0]["reason"], "You vote with the player you are loyal to, once they have voted.")
	var ev := send(s, 3, vote(false))
	expect("the owner votes and the Loyalist votes with them", [types(ev), ev[1]["voter"], ev[1]["with"], s.term["act"]["votes"]], [["performance_vote_cast", "performance_vote_cast"], 4, 3, {3: false, 4: false}])
	expect("... a Loyalist who has voted can't vote again", send(s, 4, vote(true))[0]["reason"], "You have already voted.")

	# Chains: 3 > 4 > 5.
	s = voting_s()
	LoyalistsScript.appoint(s, 3, 4, 3)
	LoyalistsScript.appoint(s, 4, 5, 3)
	expect("5 follows 4, who follows 3", send(s, 5, vote(true))[0]["type"], "rejected")
	ev = send(s, 3, vote(true))
	expect("the whole chain votes with the head", [types(ev).size(), s.term["act"]["votes"]], [3, {3: true, 4: true, 5: true}])

	# A Loyalist whose owner is the performer votes freely.
	s = voting_s()
	LoyalistsScript.appoint(s, 2, 4, 3)   # 2 is performing
	expect("a Loyalist of the performer votes as they like", types(send(s, 4, vote(false))), ["performance_vote_cast"])
	expect("... and nobody follows", s.term["act"]["votes"], {4: false})

	# A sick or eliminated owner leaves the Loyalist free.
	s = voting_s()
	LoyalistsScript.appoint(s, 3, 4, 3)
	s.eliminated[3] = true
	expect("an eliminated owner can't be followed", types(send(s, 4, vote(true))), ["performance_vote_cast"])

	# The loyalty began after the owner voted: the Loyalist's vote becomes the owner's.
	s = voting_s()
	send(s, 3, vote(true))
	LoyalistsScript.appoint(s, 3, 4, 3)
	ev = send(s, 4, vote(false))
	expect("a late Loyalist who tries the other way votes as their owner did", s.term["act"]["votes"][4], true)

	# The result counts them all.
	s = voting_s()
	LoyalistsScript.appoint(s, 3, 4, 3)
	LoyalistsScript.appoint(s, 3, 5, 3)
	send(s, 1, vote(true))
	send(s, 3, vote(false))
	expect("2 Loyalists plus the owner make 3 bad votes against 1 good one", [last_of(s, "performance_resolved")["good"], last_of(s, "performance_resolved")["bad"]], [1, 3])


func election_votes() -> void:
	var s := GameScript.new_game([1, 2, 3, 4, 5], 5)
	expect("the first election is voting at once", s.election["phase"], GameStateScript.ElectionPhase.VOTING)
	LoyalistsScript.appoint(s, 3, 4, 3)
	expect("a Loyalist can't vote first in an election either", send(s, 4, {"type": "cast_vote", "candidate": 1})[0]["reason"], "You vote with the player you are loyal to, once they have voted.")
	expect("... and a bad candidate is still refused for the owner", send(s, 3, {"type": "cast_vote", "candidate": 99})[0]["reason"], "That isn't one of the candidates.")
	var ev := send(s, 3, {"type": "cast_vote", "candidate": 2})
	expect("the Loyalist's ballot goes the owner's way and is said once", [types(ev), ev[1]["voter"], ev[1]["with"], s.election["votes"]], [["ballot_cast", "ballot_cast"], 4, 3, {3: 2, 4: 2}])
	expect("... the ballot event never says for whom", ev[1].has("candidate"), false)

	# A Loyalist who can't vote (sick) is not given a ballot.
	s = GameScript.new_game([1, 2, 3, 4, 5], 5)
	LoyalistsScript.appoint(s, 3, 4, 3)
	s.sick[4] = true
	ev = send(s, 3, {"type": "cast_vote", "candidate": 2})
	expect("a sick Loyalist's vote is not cast for them", [types(ev), s.election["votes"]], [["ballot_cast"], {3: 2}])


func amendment_votes() -> void:
	var s := amendment_s()
	LoyalistsScript.appoint(s, 3, 4, 3)
	expect("a Loyalist waits for their owner in an amendment too", send_flow(s, 4, {"type": "vote", "keep": true})[0]["reason"], "You vote with the player you are loyal to, once they have voted.")
	var ev := send_flow(s, 3, {"type": "vote", "keep": false})
	expect("... then votes with them", [types(ev), s.amend["votes"]], [["vote_cast", "vote_cast"], {3: false, 4: false}])

	# The Leader can't vote, so their Loyalist votes freely.
	s = amendment_s()
	LoyalistsScript.appoint(s, 1, 4, 3)   # 1 is the Leader
	expect("a Loyalist of the Leader votes as they like", types(send_flow(s, 4, {"type": "vote", "keep": true})), ["vote_cast"])

	# Loyalists of a confronting union's members vote against the Leader, one vote each and without the union's doubling.
	s = amendment_s()
	s.unions[11] = {"type": ACTIVIST, "owner": 2, "members": [2, 5], "confront_used": false}
	LoyalistsScript.appoint(s, 2, 3, 3)
	LoyalistsScript.appoint(s, 3, 4, 3)
	var confronted := send_flow(s, 2, {"type": "confront", "union_id": 11})
	expect("the union confronts and, with its members and their Loyalists decided, the amendment resolves at once", types(confronted), ["union_confronted", "amendment_resolved"])
	expect("2 members count double (4), their 2 Loyalists once each (2): 6 against, none for", [confronted[1]["for"], confronted[1]["against"], confronted[1]["auto_against"]], [0, 6, 4])

	s = amendment_s()
	s.unions[11] = {"type": ACTIVIST, "owner": 2, "members": [2, 5], "confront_used": false}
	LoyalistsScript.appoint(s, 2, 3, 3)
	s.amend["activists"] = [11]
	expect("a Loyalist of a union member can't vote by hand", send_flow(s, 3, {"type": "vote", "keep": true})[0]["reason"], "You vote with the player you are loyal to, and their union's vote is cast automatically.")
	LoyalistsScript.appoint(s, 5, 4, 3)
	expect("... nor can a Loyalist of another member of the union", send_flow(s, 4, {"type": "vote", "keep": true})[0]["type"], "rejected")


func command_votes() -> void:
	var s := new_turn()
	PlayScript.take_turn(s, 2)
	s.unions[1] = {"type": ACTIVIST, "owner": 3, "members": [3, 4], "confront_used": false}
	for i in 2:
		var act: Dictionary = s.term["act"]
		if act["phase"] == GameStateScript.ActPhase.DONE:
			break
		GameScript.tick(s, int(act["deadline"]))
	send(s, 3, {"type": "union_command", "union_id": 1, "scenario": "sell a fridge", "target": 5})
	send(s, 5, {"type": "command_finish"})
	LoyalistsScript.appoint(s, 1, 2, 3)
	expect("it is voting time", s.command["phase"], GameStateScript.CommandPhase.VOTING)
	expect("a Loyalist waits for their owner here too", send(s, 2, {"type": "command_vote", "good": true})[0]["reason"], "You vote with the player you are loyal to, once they have voted.")
	var ev := send(s, 1, {"type": "command_vote", "good": false})
	expect("... and votes with them", [types(ev), s.command["votes"]], [["command_vote_cast", "command_vote_cast"], {1: false, 2: false}])


func time_and_defection() -> void:
	var s := new_turn()
	LoyalistsScript.appoint(s, 3, 4, 2)
	LoyalistsScript.appoint(s, 3, 5, 3)
	var ev := RoundEndScript.run(s)
	expect("a round passes: both have one fewer", [s.loyalists[4]["left"], s.loyalists[5]["left"], ev.size()], [1, 2, 0])
	ev = RoundEndScript.run(s)
	expect("the shorter loyalty ends", [s.loyalists.has(4), s.loyalists.has(5), types(ev)], [false, true, ["loyalty_ended"]])
	expect("... and the event says whose", [ev[0]["owner"], ev[0]["loyalist"]], [3, 4])
	RoundEndScript.run(s)
	expect("the last one ends after 3 rounds", s.loyalists, {})

	# "Caught fraternizing": -20 and a Loyalist defects.
	var card: int = card_number("scandal", "You were caught fraternizing")
	s = new_turn()
	var pop: int = PopularityScript.effective(s, 3)
	ev = CardEffectsScript.apply(s, 3, "scandal", card)
	expect("with no Loyalist the drawer just loses 20", [PopularityScript.effective(s, 3) - pop, types(ev)], [-20, ["card_applied"]])
	LoyalistsScript.appoint(s, 3, 4, 3)
	ev = CardEffectsScript.apply(s, 3, "scandal", card)
	expect("with one, they defect", [types(ev), s.loyalists, ev[1]["loyalist"]], [["card_applied", "loyalist_defected"], {}, 4])
	LoyalistsScript.appoint(s, 3, 4, 3)
	LoyalistsScript.appoint(s, 3, 5, 3)
	CardEffectsScript.apply(s, 3, "scandal", card)
	expect("with two, exactly one defects", s.loyalists.size(), 1)
	var gone := {}
	for seed_value in 12:
		var g := new_turn()
		g.rng_state = seed_value + 1
		LoyalistsScript.appoint(g, 3, 4, 3)
		LoyalistsScript.appoint(g, 3, 5, 3)
		CardEffectsScript.apply(g, 3, "scandal", card)
		gone[g.loyalists.keys()[0]] = true
	expect("... which one is random", gone.keys().size(), 2)


func gender_penalty() -> void:
	var card: int = card_number("scandal", "The men playing the game")
	var s := new_turn()
	s.genders = {3: "female", 4: "male", 5: "male", 1: "female", 2: "male"}
	var pop: int = PopularityScript.effective(s, 3)
	CardEffectsScript.apply(s, 3, "scandal", card)
	expect("no Loyalists: just 15", PopularityScript.effective(s, 3) - pop, -15)
	LoyalistsScript.appoint(s, 3, 4, 3)
	LoyalistsScript.appoint(s, 3, 5, 3)
	LoyalistsScript.appoint(s, 3, 1, 3)
	pop = PopularityScript.effective(s, 3)
	var ev := CardEffectsScript.apply(s, 3, "scandal", card)
	expect("two male Loyalists (and a female one) cost 15 + 5 + 5", [PopularityScript.effective(s, 3) - pop, ev[0]["popularity"], ev[0]["loyalists_counted"]], [-25, -25, 2])
	# Other people's Loyalists don't count.
	LoyalistsScript.appoint(s, 2, 4, 3)
	s.popularity[3] = 0
	pop = PopularityScript.effective(s, 3)
	CardEffectsScript.apply(s, 3, "scandal", card)
	expect("a Loyalist who now follows someone else doesn't count", PopularityScript.effective(s, 3) - pop, -20)


func leaving_the_game() -> void:
	var s := new_turn()
	LoyalistsScript.appoint(s, 3, 4, 3)
	LoyalistsScript.appoint(s, 4, 5, 3)
	LoyalistsScript.appoint(s, 1, 2, 3)
	EliminationScript.eliminate(s, 4, "debt")
	expect("when a Loyalist leaves they stop following, and their own Loyalists are free", s.loyalists.keys(), [2])
	EliminationScript.eliminate(s, 1, "debt")
	expect("when an owner leaves their Loyalists are free", s.loyalists, {})


func views_and_saves() -> void:
	var s := new_turn()
	LoyalistsScript.appoint(s, 3, 4, 2)
	var seen: Dictionary = ViewsScript.state_view(s, 1)
	expect("everyone sees who is loyal to whom", seen["loyalists"], {4: {"owner": 3, "left": 2}})
	var errors: Array = []
	var restored: GameStateScript = SerializerScript.state_from_json(SerializerScript.state_to_json(s), errors)
	expect("a saved game keeps it", [errors, restored.loyalists], [[], {4: {"owner": 3, "left": 2}}])


# --- helpers -----------------------------------------------------------------------------

func vote(good: bool) -> Dictionary:
	return {"type": "performance_vote", "good": good}


# Player 2 (the Leader) has finished performing and the others are voting.
func voting_s() -> GameStateScript:
	var s := new_turn()
	send(s, 2, {"type": "finish_performance"})
	return s


func amendment_s() -> GameStateScript:
	var s: GameStateScript = GameStateScript.new()
	s.player_ids = [1, 2, 3, 4, 5]
	s.player_count = 5
	s.leader_id = 1
	s.leader_type = GameStateScript.LeaderType.PRESIDENT
	for id in s.player_ids:
		s.psd[id] = 1000
		s.popularity[id] = 0
		s.sick[id] = false
	s.articles = ConstitutionScript.initial_articles()
	var words: Array = s.articles[TAX]
	var texts: Array = []
	for i in words.size():
		texts.append("30%" if i == 1 else words[i]["text"])
	FlowScript.handle(s, 1, {"type": "propose", "window": GameStateScript.AmendWindow.INAUGURATION, "article_id": TAX, "new_texts": texts})
	FlowScript.handle(s, 0, {"type": "rule_grammar", "ok": true})
	return s


func card_number(deck: String, prefix: String) -> int:
	for i in CardsScript.count(deck):
		if CardsScript.text(deck, i).begins_with(prefix):
			return i
	return -1


func new_turn() -> GameStateScript:
	for seed_value in range(1, 400):
		var s := GameScript.new_game([1, 2, 3, 4, 5], seed_value)
		for id in [1, 2, 3, 4, 5]:
			GameScript.handle(s, id, {"type": "cast_vote", "candidate": 2})
		if s.leader_type == PRESIDENT:
			GameScript.handle(s, 2, {"type": "pass_window"})
			return s
	assert(false, "no seed gave a President")
	return null


func last_of(s: GameStateScript, type: String) -> Dictionary:
	for i in range(s.event_log.size() - 1, -1, -1):
		if s.event_log[i]["type"] == type:
			return s.event_log[i]
	return {}


func total_money(s: GameStateScript) -> int:
	var total: int = s.treasury
	for id in s.psd:
		total += s.psd[id]
	return total


func send(s: GameStateScript, player_id: int, command: Dictionary) -> Array:
	return GameScript.handle(s, player_id, command)


func send_flow(s: GameStateScript, player_id: int, command: Dictionary) -> Array:
	return FlowScript.handle(s, player_id, command)


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
