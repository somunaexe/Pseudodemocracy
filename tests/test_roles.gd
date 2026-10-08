extends SceneTree

const GameScript = preload("res://scripts/game.gd")
const RolesScript = preload("res://scripts/roles.gd")
const IncomeScript = preload("res://scripts/income.gd")
const ElimScript = preload("res://scripts/elimination.gd")
const GameStateScript = preload("res://scripts/game_state.gd")
const ViewsScript = preload("res://scripts/views.gd")

var failures: int = 0


func _init() -> void:
	the_roles()
	holding_roles()
	the_copy_limit()
	swapping_and_clearing()
	using_a_power()
	income_follows_roles()
	elimination_without_a_will()
	elimination_with_a_will()
	print("%d failure(s)" % failures)
	quit(1 if failures > 0 else 0)


func the_roles() -> void:
	expect("there are five roles", RolesScript.names(), ["Doctor", "Lawyer", "Secret Agent", "Activist", "Agbero"])
	expect("... five copies of each", RolesScript.copies(), 5)
	var s := table(10)
	expect("a new game has only Civilians", [RolesScript.is_civilian(s, 1), RolesScript.holders(s, "Doctor")], [true, []])


func holding_roles() -> void:
	var s := table(5)
	var ev := RolesScript.grant(s, 2, "Doctor")
	expect("a role is granted with one public event", [ev[0]["type"], ev[0]["player"], ev[0]["role"], ev[0]["audience"]], ["role_gained", 2, "Doctor", []])
	expect("... and held", [RolesScript.has(s, 2, "Doctor"), RolesScript.is_civilian(s, 2), RolesScript.held(s, 2)], [true, false, ["Doctor"]])
	RolesScript.grant(s, 2, "Lawyer")
	expect("roles stack: different roles can be held together", RolesScript.held(s, 2), ["Doctor", "Lawyer"])
	expect("but never two of the same", RolesScript.problem_granting(s, 2, "Doctor"), "They already hold that role.")
	expect("an unknown role can't be granted", RolesScript.problem_granting(s, 2, "Banker"), "There is no role called 'Banker'.")
	expect("... nor to a stranger", RolesScript.problem_granting(s, 9, "Agbero"), "That player is not in the game.")
	s.eliminated[4] = true
	expect("... nor to an eliminated player", RolesScript.problem_granting(s, 4, "Agbero"), "That player is not in the game.")

	var held := RolesScript.held(s, 2)
	held.append("Agbero")
	expect("what held() returns is a copy", RolesScript.held(s, 2), ["Doctor", "Lawyer"])

	ev = RolesScript.remove(s, 2, "Doctor")
	expect("a role can be taken away", [ev[0]["type"], RolesScript.held(s, 2)], ["role_lost", ["Lawyer"]])
	expect("taking one they don't hold does nothing", RolesScript.remove(s, 2, "Doctor"), [])
	RolesScript.remove(s, 2, "Lawyer")
	expect("with none left they are a Civilian again, and the entry is gone", [RolesScript.is_civilian(s, 2), s.roles.has(2)], [true, false])


func the_copy_limit() -> void:
	var s := table(10)
	for id in [1, 2, 3, 4, 5]:
		RolesScript.grant(s, id, "Doctor")
	expect("five Doctors use up the five cards", [RolesScript.copies_left(s, "Doctor"), RolesScript.holders(s, "Doctor")], [0, [1, 2, 3, 4, 5]])
	expect("a sixth can't be a Doctor", RolesScript.problem_granting(s, 6, "Doctor"), "All 5 Doctor cards are taken.")
	expect("... but other roles are unaffected", RolesScript.problem_granting(s, 6, "Lawyer"), "")
	RolesScript.remove(s, 3, "Doctor")
	expect("a card handed back can be given again", [RolesScript.copies_left(s, "Doctor"), RolesScript.problem_granting(s, 6, "Doctor")], [1, ""])


func swapping_and_clearing() -> void:
	var s := table(5)
	RolesScript.grant(s, 1, "Doctor")
	RolesScript.grant(s, 1, "Agbero")
	RolesScript.grant(s, 2, "Lawyer")
	var ev := RolesScript.swap(s, 1, 2)
	expect("a swap exchanges everything held", [RolesScript.held(s, 1), RolesScript.held(s, 2)], [["Lawyer"], ["Doctor", "Agbero"]])
	expect("... with one event naming both", [ev[0]["type"], ev[0]["a_now"], ev[0]["b_now"]], ["roles_swapped", ["Lawyer"], ["Doctor", "Agbero"]])
	RolesScript.swap(s, 3, 1)
	expect("swapping with a Civilian hands everything over", [RolesScript.held(s, 3), RolesScript.is_civilian(s, 1)], [["Lawyer"], true])
	var cleared := RolesScript.clear(s, 2)
	expect("clear makes a Civilian and says what was lost", [types(cleared), RolesScript.is_civilian(s, 2)], [["role_lost", "role_lost"], true])
	expect("... clearing a Civilian does nothing", RolesScript.clear(s, 1), [])


func using_a_power() -> void:
	var s := table(5)
	RolesScript.grant(s, 2, "Doctor")
	expect("a holder in good health can use the power", RolesScript.can_use_power(s, 2, "Doctor"), "")
	expect("a player who doesn't hold the role can't", RolesScript.can_use_power(s, 2, "Lawyer"), "You don't hold the Lawyer role.")
	expect("... and a Civilian can't use any", RolesScript.can_use_power(s, 1, "Doctor"), "You don't hold the Doctor role.")
	s.sick[2] = true
	expect("sick players can't use role powers", RolesScript.can_use_power(s, 2, "Doctor"), "Sick players can't use role powers.")
	s.sick[2] = false
	s.eliminated[2] = true
	expect("eliminated players can't", RolesScript.can_use_power(s, 2, "Doctor"), "You are out of the game.")


func income_follows_roles() -> void:
	var s := table(5)
	RolesScript.grant(s, 1, "Doctor")
	RolesScript.grant(s, 1, "Secret Agent")
	RolesScript.grant(s, 3, "Agbero")
	expect("income is read from the roles held: Doctor 70 + Secret Agent 80", IncomeScript.gross(s, 1), 150)
	expect("... an Agbero earns nothing", IncomeScript.gross(s, 3), 0)
	RolesScript.remove(s, 1, "Doctor")
	expect("... and a role handed back stops paying", IncomeScript.gross(s, 1), 80)
	expect("everyone sees the roles", ViewsScript.state_view(s, 4)["roles"], {1: ["Secret Agent"], 3: ["Agbero"]})


func elimination_without_a_will() -> void:
	var s := table(5)
	RolesScript.grant(s, 3, "Doctor")
	RolesScript.grant(s, 3, "Lawyer")
	var ev := ElimScript.eliminate(s, 3, "debt")
	var rescinded := find(ev, "roles_rescinded")
	expect("without a will the roles are rescinded", [rescinded["player"], rescinded["roles"], RolesScript.is_civilian(s, 3)], [3, ["Doctor", "Lawyer"], true])
	expect("... and the cards are back in the box", [RolesScript.copies_left(s, "Doctor"), RolesScript.copies_left(s, "Lawyer")], [5, 5])
	expect("... the event is in the log exactly once", count(s.event_log, "roles_rescinded"), 1)

	s = table(5)
	RolesScript.grant(s, 3, "Doctor")
	s.wills[3] = {"psd_heir": 4, "on_hold": true}
	ev = ElimScript.eliminate(s, 3, "debt")
	expect("a will on hold gives nothing: the roles are rescinded", [types(ev).has("roles_rescinded"), RolesScript.holders(s, "Doctor")], [true, []])

	s = table(5)
	RolesScript.grant(s, 3, "Agbero")
	ev = ElimScript.eliminate(s, 2, "debt")
	expect("a Civilian's elimination has no role events", [types(ev).has("roles_rescinded"), types(ev).has("roles_inherited")], [false, false])


func elimination_with_a_will() -> void:
	var s := table(5)
	RolesScript.grant(s, 3, "Doctor")
	RolesScript.grant(s, 3, "Lawyer")
	s.wills[3] = {"psd_heir": 4, "on_hold": false}
	var ev := ElimScript.eliminate(s, 3, "debt")
	var inherited := find(ev, "roles_inherited")
	expect("by default the roles go to the heir of the money", [inherited["heir"], inherited["roles"], RolesScript.held(s, 4)], [4, ["Doctor", "Lawyer"], ["Doctor", "Lawyer"]])
	expect("... nothing is left with the dead player", [RolesScript.is_civilian(s, 3), s.roles.has(3)], [true, false])

	# A different role heir (Article 56).
	s = table(5)
	RolesScript.grant(s, 3, "Doctor")
	s.wills[3] = {"psd_heir": 4, "role_heir": 5, "on_hold": false}
	ev = ElimScript.eliminate(s, 3, "debt")
	expect("a will can name a different heir for the roles", [RolesScript.held(s, 5), RolesScript.held(s, 4), s.heirs[3]], [["Doctor"], [], 4])
	expect("... and only the heir of the money is a Nepo Baby", [s.nepo.has(4), s.nepo.has(5)], [true, false])

	# An unusable role heir.
	for bad in [3, 9]:
		s = table(5)
		RolesScript.grant(s, 3, "Doctor")
		s.wills[3] = {"psd_heir": 4, "role_heir": bad, "on_hold": false}
		ElimScript.eliminate(s, 3, "debt")
		expect("a role heir who is the testator or a stranger (%d): the roles are rescinded, the money still goes to 4" % bad, [RolesScript.holders(s, "Doctor"), s.heirs[3]], [[], 4])
	s = table(5)
	RolesScript.grant(s, 3, "Doctor")
	s.eliminated[5] = true
	s.wills[3] = {"psd_heir": 4, "role_heir": 5, "on_hold": false}
	ElimScript.eliminate(s, 3, "debt")
	expect("... and so is an eliminated role heir", RolesScript.holders(s, "Doctor"), [])

	# The heir already holds one: that card goes back in the box.
	s = table(5)
	RolesScript.grant(s, 3, "Doctor")
	RolesScript.grant(s, 3, "Lawyer")
	RolesScript.grant(s, 4, "Doctor")
	s.wills[3] = {"psd_heir": 4, "on_hold": false}
	ev = ElimScript.eliminate(s, 3, "debt")
	inherited = find(ev, "roles_inherited")
	expect("a role the heir already holds is not held twice", [inherited["roles"], inherited["returned_to_box"], RolesScript.held(s, 4)], [["Lawyer"], ["Doctor"], ["Doctor", "Lawyer"]])
	expect("... so the Doctor cards still add up", RolesScript.holders(s, "Doctor"), [4])


# --- helpers -----------------------------------------------------------------------------

func table(players: int) -> GameStateScript:
	var ids: Array = range(1, players + 1)
	return GameScript.new_game(ids, 3)


func find(events: Array, type: String) -> Dictionary:
	for event in events:
		if event["type"] == type:
			return event
	return {}


func count(events: Array, type: String) -> int:
	var n: int = 0
	for event in events:
		if event["type"] == type:
			n += 1
	return n


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
