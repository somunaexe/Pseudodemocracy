extends SceneTree

const GameScript = preload("res://scripts/game.gd")
const CommandPerformanceScript = preload("res://scripts/command_performance.gd")
const PopularityScript = preload("res://scripts/popularity.gd")
const RolesScript = preload("res://scripts/roles.gd")
const ElimScript = preload("res://scripts/elimination.gd")
const ViewsScript = preload("res://scripts/views.gd")
const SerializerScript = preload("res://scripts/serializer.gd")
const GameStateScript = preload("res://scripts/game_state.gd")
const PlayScript = preload("res://tests/play.gd")

const PRESIDENT = GameStateScript.LeaderType.PRESIDENT
const ACTIVIST = GameStateScript.UnionType.ACTIVIST
const AGBERO = GameStateScript.UnionType.AGBERO
const SWING := 6

var failures: int = 0


func _init() -> void:
	starting_one()
	the_scenario()
	choosing_the_target()
	performing_and_voting()
	the_union_vote_is_doubled()
	the_result()
	acting_changes_the_group()
	the_leader_in_the_group()
	when_it_cannot_go_on()
	views_and_saves()
	print("%d failure(s)" % failures)
	quit(1 if failures > 0 else 0)


func starting_one() -> void:
	# Player 3 is the Unionizer with player 4. It is player 2's turn first (the order is 2, 3, 4, 5, 1).
	var s := with_union(ACTIVIST, [3, 4])
	expect("not on a union turn: refused", send(s, 3, command(5, "sell a fridge"))[0]["reason"], "A union can only command a performance on the Unionizer's own turn.")
	next_turn(s)   # player 3's turn; their own performance is running
	expect("not while the Unionizer's own performance is still going", send(s, 3, command(5, "sell a fridge"))[0]["reason"], "Wait until the performance of the player whose turn it is has finished.")
	performance_done(s)
	expect("only the Unionizer commands", send(s, 4, {"type": "union_command", "union_id": 1, "scenario": "x", "target": 5})[0]["reason"], "Only the Unionizer decides for a union.")
	for bad in [null, "1", true, 99]:
		expect("union %s is refused" % str(bad), send(s, 3, {"type": "union_command", "union_id": bad, "scenario": "x", "target": 5})[0]["reason"], "There is no such union or mob.")
	s.sick[3] = true
	expect("a sick Unionizer can't", send(s, 3, command(5, "sell a fridge"))[0]["reason"], "Sick players can't use pledges.")
	s.sick[3] = false

	var small := with_union(ACTIVIST, [3])
	next_turn(small)
	performance_done(small)
	expect("a union needs 2 members to act (Article 7)", send(small, 3, command(5, "sell a fridge"))[0]["reason"], "The union is too small to act.")

	var ev := send(s, 3, command(5, "sell a fridge to a penguin"))
	expect("a command starts: announced to everyone, then the performance", [types(ev), ev[0]["audience"]], [["command_started", "command_performance_started"], []])
	expect("... who, what and for how long", [ev[0]["leader"], ev[0]["target"], ev[0]["scenario"], ev[1]["seconds"]], [3, 5, "sell a fridge to a penguin", 60])
	expect("... and it is on the clock", [s.command["phase"], s.command["deadline"]], [GameStateScript.CommandPhase.PERFORMING, s.clock_ms + 60000])
	expect("the turn can't end while it is under way", send(s, 3, {"type": "end_turn"})[0]["reason"], "A Command Performance is under way.")
	expect("only one at a time", send(s, 3, command(1, "another"))[0]["reason"], "A Command Performance is already under way.")


func the_scenario() -> void:
	var s := ready_union(ACTIVIST, [3, 4])
	for bad in [null, 5, true, ["x"]]:
		expect("scenario %s is refused" % str(bad), send(s, 3, command(5, bad))[0]["reason"], "Write the scenario as text.")
	for bad in ["", "   ", "\n\t "]:
		expect("a blank scenario is refused", send(s, 3, command(5, bad))[0]["reason"], "The scenario must be from 1 to 280 characters.")
	expect("... and one that is too long", send(s, 3, command(5, "x".repeat(281)))[0]["reason"], "The scenario must be from 1 to 280 characters.")
	expect("280 characters are allowed, and the text is trimmed", [types(send(s, 3, command(5, "  " + "y".repeat(280) + "  "))), s.command["scenario"].length()], [["command_started", "command_performance_started"], 280])


func choosing_the_target() -> void:
	var s := ready_union(ACTIVIST, [3, 4])
	for bad in [null, "5", true, 5.0, 0, 9]:
		expect("target %s is refused" % str(bad), send(s, 3, command(bad, "x"))[0]["reason"], "Choose a player outside your union.")
	expect("a member of the union can't be the target", send(s, 3, command(4, "x"))[0]["reason"], "Choose a player outside your union.")
	expect("nor the Unionizer", send(s, 3, command(3, "x"))[0]["reason"], "Choose a player outside your union.")
	s.eliminated[5] = true
	expect("nor an eliminated player", send(s, 3, command(5, "x"))[0]["reason"], "Choose a player outside your union.")
	expect("a regular player can be commanded", types(send(s, 3, command(1, "x"))).has("command_performance_started"), true)
	s = ready_union(ACTIVIST, [3, 4])
	expect("so can the Leader, when they are not in the union", [types(send(s, 3, command(2, "x"))).has("command_performance_started"), s.command["target"]], [true, 2])
	s = ready_union(ACTIVIST, [3, 4, 5, 1, 2])
	expect("a union of everyone has no one to command", send(s, 3, command(5, "x"))[0]["reason"], "There is no one to command.")


func performing_and_voting() -> void:
	var s := commanded(5)
	expect("before the minute is up nothing happens", types(GameScript.tick(s, int(s.command["deadline"]) - 1)), [])
	expect("only the performer finishes early", send(s, 3, {"type": "command_finish"})[0]["reason"], "Only the performer can finish the performance.")
	expect("no voting while they perform", send(s, 1, vote(true))[0]["reason"], "It isn't time to vote.")
	var ev := send(s, 5, {"type": "command_finish"})
	expect("finishing early opens the voting", [types(ev), ev[0]["voters"], ev[0]["seconds"], s.command["phase"]], [["command_voting_opened"], [1, 2, 3, 4], 15, GameStateScript.CommandPhase.VOTING])
	expect("... everyone but the performer votes, the Unionizer and members included", send(s, 3, vote(true))[0]["type"], "command_vote_cast")
	expect("the performer can't vote on themselves", send(s, 5, vote(true))[0]["reason"], "You can't vote on this performance.")
	expect("... nor a stranger, nor the server", [send(s, 9, vote(true))[0]["reason"], send(s, 0, vote(true))[0]["reason"]], ["You can't vote on this performance.", "You can't vote on this performance."])
	expect("one vote each", send(s, 3, vote(false))[0]["reason"], "You have already voted.")
	for bad in [null, "yes", 1, 0]:
		expect("vote %s is refused" % str(bad), send(s, 1, {"type": "command_vote", "good": bad})[0]["reason"], "Vote Good or Bad.")
	var cast := last_of(s, "command_vote_cast")
	expect("a vote event says that they voted, never how", [cast["voter"], cast.has("good")], [3, false])

	s = commanded(5)
	GameScript.tick(s, int(s.command["deadline"]))
	expect("the minute running out opens the voting by itself", s.command["phase"], GameStateScript.CommandPhase.VOTING)
	var done := GameScript.tick(s, int(s.command["deadline"]))
	expect("with nobody voting, the 15 seconds end in a tie", [types(done), done[0]["outcome"], done[0]["popularity_delta"]], [["command_performance_resolved"], "tie", 0])

	s = commanded(5)
	send(s, 5, {"type": "command_finish"})
	for id in [1, 2, 3]:
		send(s, id, vote(true))
	expect("the last vote ends it at once", types(send(s, 4, vote(true))), ["command_vote_cast", "command_performance_resolved"])


func the_union_vote_is_doubled() -> void:
	# Raw votes 2 to 2, but the union's members (3 and 4) both said Good and count double: 4 to 2.
	var s := commanded(5)
	send(s, 5, {"type": "command_finish"})
	send(s, 1, vote(false))
	send(s, 2, vote(false))
	send(s, 3, vote(true))
	var ev := send(s, 4, vote(true))
	var done: Dictionary = ev[1]
	expect("a union's votes count double: 2 members for, 2 others against, is 4 to 2", [done["good"], done["bad"], done["multiplier"], done["outcome"]], [4, 2, 2, "good"])
	expect("... so the performer gains a swing", [done["popularity_delta"], PopularityScript.effective(s, 5)], [SWING, SWING])

	# The same votes without the union's weight would have been a tie.
	s = commanded(5)
	s.command["members"] = []
	send(s, 5, {"type": "command_finish"})
	send(s, 1, vote(false))
	send(s, 2, vote(false))
	send(s, 3, vote(true))
	expect("(without the doubling it is a tie)", send(s, 4, vote(true))[1]["outcome"], "tie")

	# Against the union: members voting Bad.
	s = commanded(5)
	send(s, 5, {"type": "command_finish"})
	send(s, 1, vote(true))
	send(s, 2, vote(true))
	send(s, 3, vote(false))
	var against: Dictionary = send(s, 4, vote(false))[1]
	expect("two members against beat two others for", [against["good"], against["bad"], against["popularity_delta"]], [2, 4, -SWING])

	# A mob's members count double too, even after the mob has dispersed.
	s = with_union(AGBERO, [3, 4])
	next_turn(s)
	performance_done(s)
	send(s, 3, command(5, "stir up trouble"))
	expect("the mob has already dispersed", s.unions.has(1), false)
	send(s, 5, {"type": "command_finish"})
	send(s, 1, vote(false))
	send(s, 2, vote(false))
	send(s, 3, vote(true))
	expect("... but its members' votes still count double", send(s, 4, vote(true))[1]["outcome"], "good")


func the_result() -> void:
	var s := commanded(5)
	var cash: int = s.psd[5]
	var total: int = total_money(s)
	var decks: Dictionary = s.decks.duplicate(true)
	send(s, 5, {"type": "command_finish"})
	for id in [1, 2, 4]:
		send(s, id, vote(false))
	var ev := send(s, 3, vote(false))
	var done: Dictionary = ev[1]
	expect("more Bad: the performer loses exactly the swing", [done["outcome"], done["popularity_delta"], PopularityScript.effective(s, 5)], ["bad", -SWING, -SWING])
	expect("... the votes are shown at last, the scenario with them", [done["votes"], done["scenario"], done["target"], done["leader"]], [{1: false, 2: false, 4: false, 3: false}, "sell a fridge to a penguin", 5, 3])
	expect("... no card is drawn and no money moves", [s.decks == decks, s.psd[5] - cash, total_money(s)], [true, 0, total])
	expect("... the command is over and the turn can end", [s.command, types(PlayScript.take_turn(s, 3))[0]], [{}, "turn_ended"])
	expect("... and logged once", count(s.event_log, "command_performance_resolved"), 1)

	# Once per union turn; again on the next union turn.
	s = commanded(5)
	finish_command(s)
	expect("the same union can't command twice in one turn", send(s, 3, command(1, "again"))[0]["reason"], "This union has already commanded a performance this turn.")


func acting_changes_the_group() -> void:
	var s := with_union(ACTIVIST, [3, 4])
	next_turn(s)
	performance_done(s)
	send(s, 3, command(5, "x"))
	expect("an Activist union lingers after acting (Article 12)", s.unions.has(1), true)
	finish_command(s)
	next_turn(s)   # the turn passes to 4, then 5, then 1... the Unionizer's turn does not return this term, so skip
	s = with_union(AGBERO, [3, 4])
	RolesScript.grant(s, 3, "Agbero")
	next_turn(s)
	performance_done(s)
	var ev := send(s, 3, command(5, "x"))
	expect("an Agbero mob disperses the instant it acts (Article 13)", [types(ev), s.unions.has(1), ev[-1]["why"]], [["command_started", "command_performance_started", "union_dispersed"], false, "the mob acted"])
	expect("... and the Capon, who holds an Agbero card, may re-form it", s.reform, {3: true})
	expect("... the command carries on regardless", s.command["target"], 5)


func the_leader_in_the_group() -> void:
	# Article 17: the Leader (player 2) is a member, so the Leader picks the target. The Unionizer (player 3) still
	# commands on their own turn: never on the Leader's.
	var s := with_union(ACTIVIST, [3, 2])
	performance_done(s)   # it is the Leader's turn, and the Leader is a member
	expect("even with the Leader in the group, a command can't be made on the Leader's turn", send(s, 3, {"type": "union_command", "union_id": 1, "scenario": "do a dance"})[0]["reason"], "A union can only command a performance on the Unionizer's own turn.")
	next_turn(s)
	performance_done(s)   # now player 3's own turn
	var ev := send(s, 3, {"type": "union_command", "union_id": 1, "scenario": "do a dance"})
	expect("with the Leader in the group, the Leader chooses whom", [types(ev), s.command["phase"], s.command["chooser"], s.command["candidates"]], [["command_started"], GameStateScript.CommandPhase.TARGETING, 2, [1, 4, 5]])
	expect("... only the Leader chooses", send(s, 3, {"type": "command_target", "target": 4})[0]["reason"], "Only the Leader chooses the target.")
	for bad in [null, "4", true, 3, 2, 9]:
		expect("target %s is refused" % str(bad), send(s, 2, {"type": "command_target", "target": bad})[0]["reason"], "Choose one of the players offered.")
	var chosen := send(s, 2, {"type": "command_target", "target": 4})
	expect("the Leader's choice starts the performance", [types(chosen), s.command["target"], s.command["phase"], chosen[0]["auto"]], [["command_target_chosen", "command_performance_started"], 4, GameStateScript.CommandPhase.PERFORMING, false])
	expect("... and can't be changed", send(s, 2, {"type": "command_target", "target": 5})[0]["reason"], "There is no target to choose.")

	# They don't choose: the server does, from the same list.
	s = ready_union(ACTIVIST, [3, 2])
	send(s, 3, {"type": "union_command", "union_id": 1, "scenario": "do a dance"})
	expect("before the 10 seconds are up nothing happens", types(GameScript.tick(s, int(s.command["deadline"]) - 1)), [])
	var auto := GameScript.tick(s, int(s.command["deadline"]))
	expect("the server picks a valid target at random", [types(auto), auto[0]["auto"], s.command["target"] in [1, 4, 5]], [["command_target_chosen", "command_performance_started"], true, true])

	# The Leader in a group never targets their own side.
	s = ready_union(ACTIVIST, [3, 2, 4])
	send(s, 3, {"type": "union_command", "union_id": 1, "scenario": "x"})
	expect("the candidates are everyone outside the group", s.command["candidates"], [1, 5])


func when_it_cannot_go_on() -> void:
	var s := commanded(5)
	ElimScript.eliminate(s, 5, "debt")
	var ev := GameScript.tick(s)
	expect("if the performer leaves the game it is void", [types(ev), s.command], [["command_void"], {}])
	s = commanded(5)
	ElimScript.eliminate(s, 2, "debt")   # the Leader: the term ends
	expect("if the term ends (the Leader is eliminated) it is void too", [types(GameScript.tick(s)), s.command], [["command_void"], {}])
	s = commanded(5)
	s.leader_id = 2
	s.term = {}
	expect("... and so is a command left over when no term is running (a new term then begins)", types(GameScript.tick(s))[0], "command_void")


func views_and_saves() -> void:
	var s := commanded(5)
	send(s, 5, {"type": "command_finish"})
	send(s, 1, vote(true))
	send(s, 2, vote(false))
	var seen: Dictionary = ViewsScript.state_view(s, 1)
	expect("everyone sees the command and who has voted, but not how", [seen["command"]["scenario"], seen["command"]["voted"], seen["command"].has("votes"), seen["command"]["my_vote"]], ["sell a fridge to a penguin", [1, 2], false, true])
	expect("a player who hasn't voted sees no vote of their own", ViewsScript.state_view(s, 4)["command"].has("my_vote"), false)
	expect("the JSON of the term has no vote either", SerializerScript.to_json(ViewsScript.state_view(s, 4)["command"]).contains("votes"), false)
	var errors: Array = []
	var restored: GameStateScript = SerializerScript.state_from_json(SerializerScript.state_to_json(s), errors)
	for g in [s, restored]:
		send(g, 3, vote(true))
		GameScript.tick(g, int(g.command["deadline"]))
	expect("a saved game carries on to the same result", [errors, SerializerScript.state_to_json(s) == SerializerScript.state_to_json(restored)], [[], true])


# --- helpers -----------------------------------------------------------------------------

# A running term (player 2 leads and has the first turn; the order is 2, 3, 4, 5, 1) and a group of this type led
# by player 3 with these members.
func with_union(type: int, members: Array) -> GameStateScript:
	var s := new_turn()
	s.unions[1] = {"type": type, "owner": 3, "members": members, "confront_used": false}
	return s


# The group's leader (3) is on their own turn with their performance over: ready to command.
func ready_union(type: int, members: Array) -> GameStateScript:
	var s := with_union(type, members)
	next_turn(s)
	performance_done(s)
	return s


# Player 3 has commanded player 5 to "sell a fridge to a penguin", and the performance has begun.
func commanded(target: int) -> GameStateScript:
	var s := ready_union(ACTIVIST, [3, 4])
	send(s, 3, command(target, "sell a fridge to a penguin"))
	return s


func finish_command(s: GameStateScript) -> void:
	send(s, s.command["target"], {"type": "command_finish"})
	GameScript.tick(s, int(s.command["deadline"]))


# End the turn that is being played (its performance first) so the next player's turn begins.
func next_turn(s: GameStateScript) -> void:
	PlayScript.take_turn(s, s.term["waiting"][0])


# Let the turn-holder's own performance run its course with nobody voting (a tie).
func performance_done(s: GameStateScript) -> void:
	for i in 2:
		var act: Dictionary = s.term["act"]
		if act["phase"] == GameStateScript.ActPhase.DONE:
			break
		GameScript.tick(s, int(act["deadline"]))


func command(target: Variant, scenario: Variant) -> Dictionary:
	return {"type": "union_command", "union_id": 1, "scenario": scenario, "target": target}


func vote(good: Variant) -> Dictionary:
	return {"type": "command_vote", "good": good}


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


func count(events: Array, type: String) -> int:
	var n: int = 0
	for event in events:
		if event["type"] == type:
			n += 1
	return n


func total_money(s: GameStateScript) -> int:
	var total: int = s.treasury
	for id in s.psd:
		total += s.psd[id]
	return total


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
