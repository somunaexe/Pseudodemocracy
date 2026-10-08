extends SceneTree

const GameScript = preload("res://scripts/game.gd")
const UnionsScript = preload("res://scripts/unions.gd")
const RolesScript = preload("res://scripts/roles.gd")
const ElimScript = preload("res://scripts/elimination.gd")
const LawScript = preload("res://scripts/law.gd")
const ViewsScript = preload("res://scripts/views.gd")
const SerializerScript = preload("res://scripts/serializer.gd")
const GameStateScript = preload("res://scripts/game_state.gd")
const PlayScript = preload("res://tests/play.gd")

const PRESIDENT = GameStateScript.LeaderType.PRESIDENT
const ACTIVIST = GameStateScript.UnionType.ACTIVIST
const AGBERO = GameStateScript.UnionType.AGBERO

var failures: int = 0


func _init() -> void:
	recruiting()
	answering_an_invitation()
	leaving()
	kicking()
	dispersing()
	re_forming()
	a_mob_disperses_when_it_acts()
	people_leaving_the_game()
	views_and_saves()
	the_right_words()
	print("%d failure(s)" % failures)
	quit(1 if failures > 0 else 0)


func recruiting() -> void:
	# Player 3 is the Unionizer. The turn order is 2, 3, 4, 5, 1, so it is not their turn yet.
	var s := with_union(3, ACTIVIST)
	expect("not on the Unionizer's turn, a union can't recruit", recruit(s, 3, 4)[0]["reason"], "A union can only act on the Unionizer's turn, or the Leader's if the Leader is a member.")
	PlayScript.take_turn(s, 2)
	expect("on their own turn the Unionizer can ask a player", types(recruit(s, 3, 4)), ["union_invited"])
	var ev: Dictionary = last_of(s, "union_invited")
	expect("... in the open, with 30 seconds to answer", [ev["union_id"], ev["unionizer"], ev["target"], ev["seconds"], ev["audience"]], [1, 3, 4, 30, []])
	expect("... and the invitation is recorded", s.union_invites[4]["union_id"], 1)
	expect("a player can only be asked once at a time", recruit(s, 3, 4)[0]["reason"], "That player has already been asked to join a union or mob.")

	s = with_union(3, ACTIVIST)
	PlayScript.take_turn(s, 2)
	expect("only the Unionizer recruits", send(s, 4, recruit_command(1, 5))[0]["reason"], "Only the Unionizer decides for a union.")
	for bad in [null, "1", true, 1.0, 99]:
		expect("union %s is refused" % str(bad), send(s, 3, {"type": "union_recruit", "union_id": bad, "target": 4})[0]["reason"], "There is no such union or mob.")
	for bad in [null, "4", true, 4.0, 0, 9]:
		expect("target %s is refused" % str(bad), recruit(s, 3, bad)[0]["reason"], "Choose a player who is in the game.")
	expect("you can't recruit yourself", recruit(s, 3, 3)[0]["reason"], "You are already in the union.")
	expect("a union can't recruit the Leader (Article 8)", recruit(s, 3, 2)[0]["reason"], "A union can't recruit the Leader.")
	s.unions[2] = {"type": AGBERO, "owner": 5, "members": [5, 4], "confront_used": false}
	expect("... nor a member of another union", recruit(s, 3, 4)[0]["reason"], "A union can't recruit a member of another union or mob.")
	s.eliminated[1] = true
	expect("... nor an eliminated player", recruit(s, 3, 1)[0]["reason"], "Choose a player who is in the game.")
	s.sick[3] = true
	expect("a sick Unionizer can't act", recruit(s, 3, 5)[0]["reason"], "Sick players can't use pledges.")

	# On the Leader's turn if the Leader is a member.
	s = with_union(3, ACTIVIST)
	s.unions[1]["members"].append(2)   # the Leader is a member
	expect("on the Leader's turn, if the Leader is a member, the union may act", types(recruit(s, 3, 4)), ["union_invited"])
	s = with_union(3, ACTIVIST)
	expect("... but not if the Leader isn't", recruit(s, 3, 4)[0]["type"], "rejected")


func answering_an_invitation() -> void:
	var s := invited(3, 4)
	expect("nobody else answers it", send(s, 5, {"type": "union_respond", "accept": true})[0]["reason"], "Nobody has asked you to join a union or mob.")
	for bad in [null, "yes", 1]:
		expect("answer %s is refused" % str(bad), send(s, 4, {"type": "union_respond", "accept": bad})[0]["reason"], "Accept or refuse.")
	var ev := send(s, 4, {"type": "union_respond", "accept": true})
	expect("accepting joins the union", [types(ev), s.unions[1]["members"], s.union_invites.has(4)], [["union_joined"], [3, 4], false])
	expect("... and a member is in it", UnionsScript.union_of(s, 4), 1)

	s = invited(3, 4)
	var refused := send(s, 4, {"type": "union_respond", "accept": false})
	expect("refusing leaves things as they were", [types(refused), s.unions[1]["members"], s.union_invites.has(4)], [["union_invitation_refused"], [3], false])

	s = invited(3, 4)
	expect("before the time is up the invitation stands", types(GameScript.tick(s, int(s.union_invites[4]["deadline"]) - 1)), [])
	var late := GameScript.tick(s, int(s.union_invites[4]["deadline"]))
	expect("silence for 30 seconds is a refusal", [types(late), s.union_invites.has(4), s.unions[1]["members"]], [["union_invitation_expired"], false, [3]])

	s = invited(3, 4)
	s.unions.erase(1)
	expect("if the union has gone by then, the invitation is void", types(send(s, 4, {"type": "union_respond", "accept": true})), ["union_invitation_void"])
	s = invited(3, 4)
	s.leader_id = 4
	expect("if they have become the Leader, they can't join", send(s, 4, {"type": "union_respond", "accept": true})[0]["reason"], "they can no longer join")
	s = invited(3, 4)
	s.unions[2] = {"type": AGBERO, "owner": 5, "members": [5, 4], "confront_used": false}
	expect("... nor if they joined another union meanwhile", send(s, 4, {"type": "union_respond", "accept": true})[0]["type"], "union_invitation_void")


func leaving() -> void:
	var s := with_members(3, ACTIVIST, [3, 4, 5])
	expect("a player outside a union can't leave", send(s, 1, {"type": "union_leave"})[0]["reason"], "You are not in a union or mob.")
	expect("the Unionizer disperses rather than leaving", send(s, 3, {"type": "union_leave"})[0]["reason"], "The Unionizer disperses the union instead of leaving it.")
	expect("a member leaves only on their own turn", send(s, 4, {"type": "union_leave"})[0]["reason"], "A member may leave on their own turn.")
	PlayScript.take_turn(s, 2)
	PlayScript.take_turn(s, 3)
	var ev := send(s, 4, {"type": "union_leave"})
	expect("on their own turn a member leaves", [types(ev), s.unions[1]["members"], ev[0]["why"]], [["union_left"], [3, 5], "left"])
	PlayScript.take_turn(s, 4)
	var ev2 := send(s, 5, {"type": "union_leave"})
	expect("a union left with 1 member dissolves (Article 11)", [types(ev2), s.unions.has(1)], [["union_left", "union_dissolved"], false])
	expect("... both events logged once", [count(s.event_log, "union_left"), count(s.event_log, "union_dissolved")], [2, 1])

	# The size at which a union dissolves is a rule the Constitution can change.
	s = with_members(3, ACTIVIST, [3, 4, 5])
	set_word(s, 11, 0, "2")   # Article 11: dissolves at 2
	PlayScript.take_turn(s, 2)
	PlayScript.take_turn(s, 3)
	expect("an amended threshold is obeyed: a union at 2 members is gone", [LawScript.get_int(s, "unionDissolveAt"), types(send(s, 4, {"type": "union_leave"}))], [2, ["union_left", "union_dissolved"]])


func kicking() -> void:
	var s := with_members(3, ACTIVIST, [3, 4, 5, 1])
	PlayScript.take_turn(s, 2)
	expect("only the Unionizer kicks", send(s, 4, {"type": "union_kick", "union_id": 1, "target": 5})[0]["reason"], "Only the Unionizer decides for a union.")
	for bad in [null, "4", true, 9, 2]:
		expect("kick target %s is refused" % str(bad), send(s, 3, {"type": "union_kick", "union_id": 1, "target": bad})[0]["reason"], "That player is not in your union.")
	expect("the Unionizer can't kick themselves", send(s, 3, {"type": "union_kick", "union_id": 1, "target": 3})[0]["reason"], "The Unionizer can't be kicked out of their own union.")
	var ev := send(s, 3, {"type": "union_kick", "union_id": 1, "target": 4})
	expect("the Unionizer kicks a member just by saying so", [types(ev), ev[0]["why"], s.unions[1]["members"]], [["union_left"], "kicked", [3, 5, 1]])
	var s2 := with_members(3, ACTIVIST, [3, 4])
	expect("not outside a union turn", send(s2, 3, {"type": "union_kick", "union_id": 1, "target": 4})[0]["reason"], "A union can only act on the Unionizer's turn, or the Leader's if the Leader is a member.")
	PlayScript.take_turn(s2, 2)
	expect("kicking the last member dissolves the union", types(send(s2, 3, {"type": "union_kick", "union_id": 1, "target": 4})), ["union_left", "union_dissolved"])


func dispersing() -> void:
	var s := with_members(3, ACTIVIST, [3, 4, 5])
	expect("only the Unionizer disperses", send(s, 4, {"type": "union_disperse", "union_id": 1})[0]["reason"], "Only the Unionizer decides for a union.")
	var ev := send(s, 3, {"type": "union_disperse", "union_id": 1})
	expect("the Unionizer can disperse the union at any time", [types(ev), s.unions.has(1), ev[0]["why"]], [["union_dispersed"], false, "the Unionizer dispersed it"])
	expect("... an Activist union leaves no right to re-form", s.reform, {})

	s = with_members(3, AGBERO, [3, 4, 5])
	RolesScript.grant(s, 3, "Agbero")
	RolesScript.grant(s, 4, "Agbero")
	ev = send(s, 3, {"type": "union_disperse", "union_id": 1})
	expect("a dispersed mob lets its members who still hold an Agbero card form a new one", [ev[0]["may_reform"], s.reform], [[3, 4], {3: true, 4: true}])


func re_forming() -> void:
	var s := with_members(3, AGBERO, [3, 4])
	RolesScript.grant(s, 3, "Agbero")
	send(s, 3, {"type": "union_disperse", "union_id": 1})
	expect("someone with no right to re-form can't", send(s, 5, {"type": "union_reform"})[0]["reason"], "You have no mob to re-form.")
	var ev := send(s, 3, {"type": "union_reform"})
	expect("a Capon who still holds an Agbero card re-forms a mob at once", [types(ev), s.unions[1]["owner"], s.unions[1]["type"], s.reform.has(3)], [["union_founded"], 3, AGBERO, false])
	expect("... and the right is used up", send(s, 3, {"type": "union_reform"})[0]["reason"], "You have no mob to re-form.")

	s = with_members(3, AGBERO, [3, 4])
	RolesScript.grant(s, 3, "Agbero")
	send(s, 3, {"type": "union_disperse", "union_id": 1})
	RolesScript.remove(s, 3, "Agbero")
	expect("without the Agbero card they can't", send(s, 3, {"type": "union_reform"})[0]["reason"], "You no longer hold an Agbero role card.")
	expect("... and the right is gone", s.reform.has(3), false)

	s = with_members(3, AGBERO, [3, 4])
	RolesScript.grant(s, 4, "Agbero")
	send(s, 3, {"type": "union_disperse", "union_id": 1})
	s.unions[7] = {"type": ACTIVIST, "owner": 1, "members": [1, 4], "confront_used": false}
	expect("a player already in a union can't re-form", send(s, 4, {"type": "union_reform"})[0]["reason"], "You are already in a union or mob.")

	s = with_members(3, AGBERO, [3, 4])
	RolesScript.grant(s, 3, "Agbero")
	UnionsScript.remove_member(s, 1, 4, "left")   # drops to 1 member: dissolved, not dispersed
	expect("a union that dissolves (1 member left) gives no right to re-form", s.reform, {})


func a_mob_disperses_when_it_acts() -> void:
	# The Agbero confront is in AmendmentFlow; here we check the Activist side lingers and the mob's members
	# who hold the Agbero card may re-form. The confront itself is tested in test_amendment_flow.
	var s := with_members(3, AGBERO, [3, 4])
	RolesScript.grant(s, 3, "Agbero")
	var ev := UnionsScript.disperse(s, 1, "the mob acted")
	expect("a mob that has acted disperses with that reason", [ev[0]["type"], ev[0]["why"], s.unions.has(1), s.reform], ["union_dispersed", "the mob acted", false, {3: true}])


func people_leaving_the_game() -> void:
	var s := with_members(3, ACTIVIST, [3, 4, 5])
	ElimScript.eliminate(s, 4, "debt")
	expect("an eliminated member leaves the union", [s.unions[1]["members"], UnionsScript.union_of(s, 4)], [[3, 5], -1])
	ElimScript.eliminate(s, 3, "debt")
	expect("an eliminated Unionizer dissolves it (assumed)", s.unions.has(1), false)

	s = invited(3, 4)
	ElimScript.eliminate(s, 4, "debt")
	expect("an eliminated player's invitation lapses", s.union_invites.has(4), false)
	s = invited(3, 4)
	ElimScript.eliminate(s, 3, "debt")
	expect("an invitation to a union that has dissolved is dropped", s.union_invites.has(4), false)

	s = with_members(3, AGBERO, [3, 4])
	RolesScript.grant(s, 3, "Agbero")
	send(s, 3, {"type": "union_disperse", "union_id": 1})
	ElimScript.eliminate(s, 3, "debt")
	expect("an eliminated player's right to re-form is gone", s.reform.has(3), false)


func views_and_saves() -> void:
	var s := invited(3, 4)
	s.reform[5] = true
	var view: Dictionary = ViewsScript.state_view(s, 1)
	expect("everyone sees who has been asked to join a union, and who may re-form", [view["union_invites"][4]["union_id"], view["reform"]], [1, {5: true}])
	var errors: Array = []
	var restored: GameStateScript = SerializerScript.state_from_json(SerializerScript.state_to_json(s), errors)
	for g in [s, restored]:
		send(g, 4, {"type": "union_respond", "accept": true})
	expect("a saved game with an invitation waiting carries on the same way", [errors, SerializerScript.state_to_json(s) == SerializerScript.state_to_json(restored)], [[], true])


func the_right_words() -> void:
	# Activists form a union led by a Unionizer. Agberos form a mob led by a Capon. Messages must say so.
	var u := with_union(3, ACTIVIST)
	var m := with_union(3, AGBERO)
	expect("the word for each group", [UnionsScript.word(u.unions[1]), UnionsScript.word(m.unions[1])], ["union", "mob"])
	expect("... and for its leader", [UnionsScript.head(u.unions[1]), UnionsScript.head(m.unions[1])], ["Unionizer", "Capon"])
	expect("a stranger commanding a union is told about the Unionizer", send(u, 4, recruit_command(1, 5))[0]["reason"], "Only the Unionizer decides for a union.")
	expect("... and about the Capon for a mob", send(m, 4, recruit_command(1, 5))[0]["reason"], "Only the Capon decides for a mob.")
	expect("off their turn, a union is told it acts on the Unionizer's turn", recruit(u, 3, 4)[0]["reason"], "A union can only act on the Unionizer's turn, or the Leader's if the Leader is a member.")
	expect("... a mob on the Capon's", recruit(m, 3, 4)[0]["reason"], "A mob can only act on the Capon's turn, or the Leader's if the Leader is a member.")
	PlayScript.take_turn(m, 2)
	expect("a mob can't recruit the Leader", recruit(m, 3, 2)[0]["reason"], "A mob can't recruit the Leader.")
	expect("... nor itself again", recruit(m, 3, 3)[0]["reason"], "You are already in the mob.")
	m.unions[2] = {"type": ACTIVIST, "owner": 5, "members": [5, 4], "confront_used": false}
	expect("a member of any other group can't be recruited: union or mob", recruit(m, 3, 4)[0]["reason"], "A mob can't recruit a member of another union or mob.")
	var mob := with_members(3, AGBERO, [3, 4, 5])
	expect("the Capon disperses the mob rather than leaving it", send(mob, 3, {"type": "union_leave"})[0]["reason"], "The Capon disperses the mob instead of leaving it.")
	PlayScript.take_turn(mob, 2)
	expect("a Capon can't be kicked out of their own mob", send(mob, 3, {"type": "union_kick", "union_id": 1, "target": 3})[0]["reason"], "The Capon can't be kicked out of their own mob.")
	expect("... and a stranger isn't in the mob", send(mob, 3, {"type": "union_kick", "union_id": 1, "target": 2})[0]["reason"], "That player is not in your mob.")
	expect("the Capon dispersing says it was the Capon", send(mob, 3, {"type": "union_disperse", "union_id": 1})[0]["why"], "the Capon dispersed it")
	expect("a player with no group is told of both", send(mob, 1, {"type": "union_leave"})[0]["reason"], "You are not in a union or mob.")
	expect("a missing group is told of both", send(mob, 3, {"type": "union_disperse", "union_id": 9})[0]["reason"], "There is no such union or mob.")
	expect("a sick Capon can't use pledges", send(with_members_sick(), 3, recruit_command(1, 4))[0]["reason"], "Sick players can't use pledges.")


func with_members_sick() -> GameStateScript:
	var s := with_union(3, AGBERO)
	PlayScript.take_turn(s, 2)
	s.sick[3] = true
	return s


# --- helpers -----------------------------------------------------------------------------

# A running term (player 2 leads and has the first turn: the order is 2, 3, 4, 5, 1) and a union of this type
# owned by `owner`, with only its founder in it.
func with_union(owner: int, type: int) -> GameStateScript:
	var s := new_turn()
	s.unions[1] = {"type": type, "owner": owner, "members": [owner], "confront_used": false}
	return s


func with_members(owner: int, type: int, members: Array) -> GameStateScript:
	var s := with_union(owner, type)
	s.unions[1]["members"] = members
	return s


# A union owned by `owner` has asked `target`, on the Unionizer's turn.
func invited(owner: int, target: int) -> GameStateScript:
	var s := with_union(owner, ACTIVIST)
	PlayScript.take_turn(s, 2)
	send(s, owner, recruit_command(1, target))
	return s


func recruit_command(union_id: int, target: Variant) -> Dictionary:
	return {"type": "union_recruit", "union_id": union_id, "target": target}


func recruit(s: GameStateScript, owner: int, target: Variant) -> Array:
	return send(s, owner, recruit_command(1, target))


func set_word(s: GameStateScript, article_id: int, slot: int, text: String) -> void:
	var seen: int = 0
	for word in s.articles[article_id]:
		if word["amendable"]:
			if seen == slot:
				word["text"] = text
				return
			seen += 1


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
