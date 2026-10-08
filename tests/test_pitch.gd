extends SceneTree

const GameScript = preload("res://scripts/game.gd")
const GameStateScript = preload("res://scripts/game_state.gd")
const CardsScript = preload("res://scripts/cards.gd")
const UnionsScript = preload("res://scripts/unions.gd")
const RivalsScript = preload("res://scripts/rivals.gd")
const ViceScript = preload("res://scripts/vice.gd")
const PlayScript = preload("res://tests/play.gd")

const PRESIDENT = GameStateScript.LeaderType.PRESIDENT
const ACTIVIST = GameStateScript.UnionType.ACTIVIST
const AGBERO = GameStateScript.UnionType.AGBERO

var failures: int = 0


func _init() -> void:
	the_card()
	which_union()
	nothing_to_join()
	deciding()
	print("%d failure(s)" % failures)
	quit(1 if failures > 0 else 0)


func the_card() -> void:
	var card: int = card_number("A rival union wants your backing")
	expect("the card is listed as a pitch", CardsScript.effects("performance", card), {"pitch": true})
	var s := new_turn()
	s.unions[1] = {"type": ACTIVIST, "owner": 5, "members": [5, 1], "confront_used": false}
	var ev := turn_with(s, card)
	expect("when the card starts player 3's performance a union that isn't theirs pitches them", [types(ev), ev[1]["unionizer"], ev[1]["target"], ev[1]["seconds"]], [["performance_started", "union_pitched"], 5, 3, 30])
	expect("... as an invitation they can answer", s.union_invites.get(3, {}).get("union_id", -1), 1)
	expect("... and the performance carries on", s.term["act"]["player"], 3)


func which_union() -> void:
	var s := new_turn()
	s.unions[1] = {"type": ACTIVIST, "owner": 5, "members": [5, 1], "confront_used": false}
	s.unions[2] = {"type": AGBERO, "owner": 4, "members": [4, 1], "confront_used": false}
	RivalsScript.name_rival(s, 3, 4)
	var ev := UnionsScript.pitch(s, 3)
	expect("a union led by one of the player's rivals is the one that pitches", [ev[0]["type"], ev[0]["union_id"]], ["union_pitched", 2])
	s = new_turn()
	s.unions[1] = {"type": ACTIVIST, "owner": 5, "members": [5, 1], "confront_used": false}
	s.unions[2] = {"type": AGBERO, "owner": 4, "members": [4, 1], "confront_used": false}
	var seen := {}
	for seed_value in 16:
		var g := new_turn()
		g.unions = s.unions.duplicate(true)
		g.rng_state = seed_value * 7919 + 5
		seen[UnionsScript.pitch(g, 3)[0]["union_id"]] = true
	expect("with no rival, any union but their own, at random", seen.keys().size(), 2)
	s.unions[3] = {"type": ACTIVIST, "owner": 3, "members": [3, 2], "confront_used": false}
	var picked := {}
	for seed_value in 16:
		var g := new_turn()
		g.unions = s.unions.duplicate(true)
		g.rng_state = seed_value * 7919 + 5
		var out := UnionsScript.pitch(g, 3)
		picked[out[0]["union_id"] if out[0]["type"] == "union_pitched" else -1] = true
	expect("a union the player already belongs to doesn't pitch them", picked.keys(), [-1])
	var left_out := new_turn()
	left_out.unions[1] = {"type": ACTIVIST, "owner": 5, "members": [5, 1], "confront_used": false}
	left_out.eliminated[5] = true
	expect("... nor does one whose Unionizer has gone", UnionsScript.pitch(left_out, 3)[0]["type"], "union_pitch_unavailable")


func nothing_to_join() -> void:
	var s := new_turn()
	var ev := UnionsScript.pitch(s, 3)
	expect("with no union at the table nothing happens, and it is said", [ev[0]["type"], ev[0]["reason"]], ["union_pitch_unavailable", "there is no other union or mob"])
	s.unions[1] = {"type": ACTIVIST, "owner": 5, "members": [5, 1], "confront_used": false}
	expect("the Leader can't be recruited", UnionsScript.pitch(s, 2)[0]["type"], "union_pitch_unavailable")
	ViceScript.appoint(s, 4)
	expect("nor the Vice", UnionsScript.pitch(s, 4)[0]["type"], "union_pitch_unavailable")
	s.union_invites[3] = {"union_id": 1, "deadline": 99999}
	expect("nor someone who has already been asked", UnionsScript.pitch(s, 3)[0]["type"], "union_pitch_unavailable")
	s = new_turn()
	s.unions[1] = {"type": ACTIVIST, "owner": 5, "members": [5, 3], "confront_used": false}
	s.unions[2] = {"type": AGBERO, "owner": 4, "members": [4, 1], "confront_used": false}
	expect("a member of one union isn't pitched by another", UnionsScript.pitch(s, 3)[0]["type"], "union_pitch_unavailable")


func deciding() -> void:
	var card: int = card_number("A rival union wants your backing")
	var s := new_turn()
	s.unions[1] = {"type": ACTIVIST, "owner": 5, "members": [5, 1], "confront_used": false}
	turn_with(s, card)
	var ev := send(s, 3, {"type": "union_respond", "accept": true})
	expect("the performer accepts and joins", [types(ev), s.unions[1]["members"]], [["union_joined"], [5, 1, 3]])
	s = new_turn()
	s.unions[1] = {"type": ACTIVIST, "owner": 5, "members": [5, 1], "confront_used": false}
	turn_with(s, card)
	ev = send(s, 3, {"type": "union_respond", "accept": false})
	expect("or refuses", [types(ev), s.unions[1]["members"]], [["union_invitation_refused"], [5, 1]])
	s = new_turn()
	s.unions[1] = {"type": ACTIVIST, "owner": 5, "members": [5, 1], "confront_used": false}
	turn_with(s, card)
	var ticked := GameScript.tick(s, int(s.union_invites[3]["deadline"]))
	expect("silence for 30 seconds is a refusal", [types(ticked).has("union_invitation_expired"), s.unions[1]["members"]], [true, [5, 1]])


# --- helpers -----------------------------------------------------------------------------

# Player 3's turn begins with this performance card. Returns the events of ending player 2's turn.
func turn_with(s: GameStateScript, card: int) -> Array:
	s.decks["performance"] = [card]
	return PlayScript.take_turn_all(s, 2).filter(func(e): return e["type"] in ["performance_started", "union_pitched", "union_pitch_unavailable"])


func card_number(prefix: String) -> int:
	for i in CardsScript.count("performance"):
		if CardsScript.text("performance", i).begins_with(prefix):
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
