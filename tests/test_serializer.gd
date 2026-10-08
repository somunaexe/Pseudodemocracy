extends SceneTree

const SerializerScript = preload("res://scripts/serializer.gd")
const FlowScript = preload("res://scripts/amendment_flow.gd")
const GameStateScript = preload("res://scripts/game_state.gd")
const ConstitutionScript = preload("res://scripts/constitution.gd")
const DebtScript = preload("res://scripts/debt.gd")

const INAUG = GameStateScript.AmendWindow.INAUGURATION
const MID = GameStateScript.AmendWindow.MID_TERM
const FAREWELL = GameStateScript.AmendWindow.FAREWELL
const TAX := 2
const SERVER := 0

var failures: int = 0


func _init() -> void:
	values_round_trip()
	state_round_trip()
	restored_game_carries_on()
	saved_games_are_checked()
	commands_from_clients()
	events_round_trip()
	print("%d failure(s)" % failures)
	quit(1 if failures > 0 else 0)


func values_round_trip() -> void:
	var errors: Array = []
	var original: Dictionary = {1: "one", 2: [3, {4: true}], "name": 7, 0: -5}
	var back = SerializerScript.from_json(SerializerScript.to_json(original), errors)
	expect("no errors", errors, [])
	expect("integer keys keep their type", diff(original, back, "v"), "")
	expect("key 1 is an int, not the text '1'", back.has(1) and not back.has("1"), true)
	expect("a key called '$pairs' is not mistaken for the marker",
		diff({"$pairs": 5}, SerializerScript.from_json(SerializerScript.to_json({"$pairs": 5}), errors), "v"), "")
	expect("the empty dictionary", diff({}, SerializerScript.from_json("{}", errors), "v"), "")
	expect("the same data always gives the same text",
		SerializerScript.to_json({"b": 1, "a": 2}), SerializerScript.to_json({"a": 2, "b": 1}))
	expect("plain JSON numbers come back as ints", typeof(SerializerScript.from_json("[3]", errors)[0]), TYPE_INT)
	expect("a real fraction is left alone", SerializerScript.from_json("[2.5]", errors)[0], 2.5)


func state_round_trip() -> void:
	var s := rich_state()
	var fresh := GameStateScript.new()
	for name in SerializerScript.state_fields(s):
		expect("test populates '%s' (so the round trip covers it)" % name, diff(s.get(name), fresh.get(name), name) != "", true)

	var before: String = SerializerScript.state_to_json(s)
	var errors: Array = []
	var restored: GameStateScript = SerializerScript.state_from_json(before, errors)
	expect("restores without errors", errors, [])
	for name in SerializerScript.state_fields(s):
		expect("field '%s' is identical, types included" % name, diff(s.get(name), restored.get(name), name), "")
	expect("saving does not change the state", SerializerScript.state_to_json(s), before)
	expect("saving the restored state gives the same text", SerializerScript.state_to_json(restored), before)
	expect("integer keys survived: psd[1]", restored.psd[1], s.psd[1])
	expect("the enum survived", restored.leader_type, GameStateScript.LeaderType.DICTATOR)
	expect("the in-progress votes are in the server's own save", before.contains("\"votes\""), true)


func restored_game_carries_on() -> void:
	var a := rich_state()
	var errors: Array = []
	var b: GameStateScript = SerializerScript.state_from_json(SerializerScript.state_to_json(a), errors)
	# Same remaining commands on the original and on the restored copy.
	var ev_a := FlowScript.handle(a, 5, {"type": "vote", "keep": false})
	var ev_b := FlowScript.handle(b, 5, {"type": "vote", "keep": false})
	expect("the vote finishes in the restored game", types(ev_b), ["vote_cast", "amendment_resolved", "article_changed"])
	expect("same events", diff(ev_a, ev_b, "events"), "")
	for name in SerializerScript.state_fields(a):
		expect("after playing on, '%s' still matches" % name, diff(a.get(name), b.get(name), name), "")


func saved_games_are_checked() -> void:
	var s := rich_state()
	var text: String = SerializerScript.state_to_json(s)
	var errors: Array = []

	expect("nonsense is refused", SerializerScript.state_from_json("not json", errors), null)
	expect("... with a message", errors.is_empty(), false)

	errors = []
	SerializerScript.state_from_json(text.replace("\"version\":%d" % SerializerScript.SCHEMA_VERSION, "\"version\":99"), errors)
	expect("a different schema version is refused", errors.size(), 1)
	expect("... and says why", errors[0].contains("version"), true)

	errors = []
	SerializerScript.state_from_json("[1, 2, 3]", errors)
	expect("a list is not a saved game", errors, ["this is not a saved game"])

	errors = []
	SerializerScript.state_from_json(text.replace("\"treasury\":", "\"gold\":"), errors)
	expect("a renamed field is reported twice (missing and unknown)", errors.size(), 2)

	errors = []
	SerializerScript.state_from_json(text.replace("\"treasury\":100", "\"treasury\":\"lots\""), errors)
	expect("a field of the wrong type is refused", errors.size(), 1)
	expect("... naming the field", errors[0].contains("treasury"), true)


func commands_from_clients() -> void:
	# What a phone sends: JSON text. Its numbers arrive as floats.
	var s := make_state()
	var words: Array = s.articles[TAX]
	var texts: Array = []
	for i in words.size():
		texts.append("30%" if i == 1 else words[i]["text"])
	var text: String = JSON.stringify({"type": "propose", "window": 0.0, "article_id": 2.0, "new_texts": texts})
	var errors: Array = []
	var command: Dictionary = SerializerScript.parse_command(text, errors)
	expect("a command parses", errors, [])
	expect("whole numbers become ints", typeof(command["window"]), TYPE_INT)
	expect("the flow accepts it", FlowScript.handle(s, 1, command)[0]["type"], "amendment_proposed")

	errors = []
	expect("not JSON", SerializerScript.parse_command("hello", errors), {})
	expect("... reports it", errors.is_empty(), false)
	errors = []
	expect("a list is not a command", SerializerScript.parse_command("[1]", errors), {})
	errors = []
	expect("no type", SerializerScript.parse_command("{\"window\": 1}", errors), {})
	errors = []
	expect("type must be text", SerializerScript.parse_command("{\"type\": 5}", errors), {})
	errors = []
	expect("too large", SerializerScript.parse_command("{\"type\": \"" + "x".repeat(70000) + "\"}", errors), {})
	expect("... says so", errors, ["command is too large"])
	errors = []
	expect("deep nesting is refused", SerializerScript.parse_command("{\"type\": \"vote\", \"x\": " + "[".repeat(40) + "]".repeat(40) + "}", errors), {})
	expect("... says so", errors.has("data is nested too deeply"), true)
	errors = []
	SerializerScript.parse_command("{\"type\": \"vote\", \"x\": {\"$pairs\": \"nope\"}}", errors)
	expect("a malformed pair list is refused", errors.is_empty(), false)
	errors = []
	SerializerScript.parse_command("{\"type\": \"vote\", \"x\": {\"$pairs\": [[1]]}}", errors)
	expect("a pair with one item is refused", errors.is_empty(), false)
	errors = []
	SerializerScript.parse_command("{\"type\": \"vote\", \"x\": {\"$pairs\": [[[1], 2]]}}", errors)
	expect("a list can't be a key", errors.is_empty(), false)


func events_round_trip() -> void:
	var s := make_state()
	var words: Array = s.articles[TAX]
	var texts: Array = []
	for i in words.size():
		texts.append("30%" if i == 1 else words[i]["text"])
	FlowScript.handle(s, 1, {"type": "propose", "window": INAUG, "article_id": TAX, "new_texts": texts})
	FlowScript.handle(s, SERVER, {"type": "rule_grammar", "ok": true})
	var events: Array = []
	for id in [2, 3, 4, 5]:
		events.append_array(FlowScript.handle(s, id, {"type": "vote", "keep": id != 5}))
	var errors: Array = []
	var back = SerializerScript.from_json(SerializerScript.to_json(events), errors)
	expect("events round trip, including the votes with player ids as keys", diff(events, back, "events"), "")
	var cast: String = SerializerScript.to_json(events[0])
	expect("a vote_cast event on the wire does not contain the choice", cast.contains("keep"), false)
	expect("... it says only who voted", cast.contains("\"voter\":2"), true)


# --- helpers ---------------------------------------------------------------------------

func make_state() -> GameStateScript:
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
	return s


# A game with every field of GameState filled in and an amendment half way through its vote.
func rich_state() -> GameStateScript:
	var s := make_state()
	s.leader_type = GameStateScript.LeaderType.DICTATOR
	s.current_round = 3
	s.player_ids.append(6)
	s.player_count = 6
	s.psd[6] = 0
	s.popularity[6] = -20
	s.sick[6] = false
	s.eliminated[6] = true
	s.half_rounds = {1: 4, 2: 2, 3: 1}
	s.unions[10] = {"type": GameStateScript.UnionType.ACTIVIST, "owner": 2, "members": [2, 3], "confront_used": false}
	s.unions[11] = {"type": GameStateScript.UnionType.AGBERO, "owner": 4, "members": [4, 5], "confront_used": true}
	s.heirs[6] = 4
	s.wills[2] = {"psd_heir": 4, "on_hold": false}
	s.nepo[4] = 2
	s.rng_state = 3735928559
	s.term = {"phase": GameStateScript.TermPhase.TURNS, "played": [2], "waiting": [3, 4], "announced": 3}
	s.game_over = true
	s.last_turn_player = 4
	s.levy_band = {"low": 35, "high": 60}
	s.clock_ms = 123456
	s.dose = {"phase": GameStateScript.DosePhase.GUESSING, "doctor": 2, "patient": 3, "kind": "heal", "dose": "Agbo", "price": 40, "deadline": 99000, "guesser": 4}
	s.role_cards = {0: {"role": "Doctor", "sticker": true, "holder": 2}, 1: {"role": "Doctor", "sticker": false, "holder": 0}}
	s.agent_used = {4: true}
	s.coup_ban = {3: 2}
	s.effect_round = {"sick:3": 2}
	s.markers = {2: 3, 4: 1}
	s.rivals = {2: [3, 4]}
	s.truces = [[2, 3]]
	s.accords = [{"a": 2, "b": 4, "left": 2, "loss": 10}]
	s.skip_draw = {5: true}
	s.grammar_referee = false
	s.choice_queue = [{"pending": {"player": 2, "deck": "settlement", "card": 22, "kind": "option", "deadline": 5000, "labels": ["a", "b"]}, "shown": {"player": 2}}]
	s.card_offers = {3: {"buyer": 4, "deck": "settlement", "card": 12, "price": 100, "deadline": 777}}
	s.poll_counter = 4
	s.polls = [{"id": 4, "special": "flyover", "drawer": 2, "targets": [3, 4], "labels": ["a", "b", "c"], "default": 0, "answers": {3: 1}, "deadline": 9999, "mode": "each", "data": {"share": 50}, "deck": "settlement", "card": 6}]
	s.schedule = [{"kind": "stipend", "player": 3, "source": "treasury", "amount": 50, "from": 2, "until": 3, "while_popular": false}]
	s.mods = {3: {"halve_loss": {"from": 2, "until": 2, "uses": -1}}}
	s.peeks = [{"holder": 4, "target": 2, "kinds": ["coup", "bead"], "round_only": true}]
	s.loyalists = {4: {"owner": 2, "left": 2}}
	s.frozen = {2: {"left": 2, "drop": 30}}
	s.agent_offers = {2: {"client": 5, "kind": "will", "target": 3, "role": "", "price": 40, "deadline": 8000}}
	s.command = {"phase": GameStateScript.CommandPhase.VOTING, "union_id": 1, "union_type": 0, "leader": 3, "target": 4, "scenario": "sell a fridge to a penguin", "deadline": 9000, "votes": {2: true, 5: false}}
	s.genders = {2: "female", 3: "male"}
	s.union_invites = {5: {"union_id": 10, "deadline": 7777}}
	s.reform = {4: true}
	s.choice = {"player": 2, "deck": "settlement", "card": 22, "kind": "option", "deadline": 5000, "labels": ["a", "b"]}
	s.hands = {3: [{"deck": "settlement", "card": 7}]}
	s.dose_secret = {"poison": true}
	s.will_offers = {3: {"lawyer": 2, "psd_heir": 4, "role_heir": 0, "fee": 50, "upkeep": 10, "deadline": 12345}}
	s.doctor_used = {2: 1}
	s.sick_left = {3: 2}
	s.sick_original = {3: 1}
	s.immune_left = {4: 3}
	s.roles = {2: ["Doctor", "Lawyer"], 4: ["Activist"]}
	s.decks = {"performance": [4, 0, 2], "settlement": [1], "scandal": []}
	s.leader_goes_first = true
	s.election = {
		"phase": GameStateScript.ElectionPhase.VOTING, "reason": "term_ended", "runoff": 1,
		"exam": {"questions": [{"text": "Who rules?", "options": ["Me", "You"]}]}, "key": [0],
		"takers": [2, 3, 4], "answers": {2: [0], 3: [1], 4: [0]},
		"voters": [2, 3, 4], "candidates": [2, 3], "votes": {2: 3, 4: 2},
	}

	# 1) an amendment that is voted on (so the log holds a result with player ids as keys)
	send(s, 1, propose(s, INAUG, {1: "30%"}))
	send(s, SERVER, {"type": "rule_grammar", "ok": true})
	for id in [2, 3, 4, 5]:
		send(s, id, {"type": "vote", "keep": true})
	# 2) one that fails its check
	s.turns_played = 3
	send(s, 1, propose(s, MID, {0: "Duty:"}))
	# 3) one left half way through its vote (Farewell opens once all 6 players have played)
	s.turns_played = 6
	send(s, 1, propose(s, FAREWELL, {1: "35%"}))
	send(s, SERVER, {"type": "rule_grammar", "ok": true})
	send(s, 2, {"type": "vote", "keep": true})
	send(s, 3, {"type": "vote", "keep": false})

	s.sick[4] = true
	DebtScript.charge(s, 3, 2, 3000)   # more than they have: part becomes debt
	s.debt_terms[3] = 1
	s.vice_id = 6   # not one of the voters: the Vice does not vote on amendments
	s.amend_offer = {"by": 6, "other": 1, "window": 1, "article_id": 2, "texts": ["a", "b"], "deadline": 5555}
	return s


func propose(s: GameStateScript, window: int, changes: Dictionary) -> Dictionary:
	var words: Array = s.articles[TAX]
	var texts: Array = []
	for i in words.size():
		texts.append(changes.get(i, words[i]["text"]))
	return {"type": "propose", "window": window, "article_id": TAX, "new_texts": texts}


func send(s: GameStateScript, player_id: int, command: Dictionary) -> Array:
	return FlowScript.handle(s, player_id, command)


func types(events: Array) -> Array:
	var result: Array = []
	for event in events:
		result.append(event["type"])
	return result


# Compares two values including their types and the types of dictionary keys.
# Returns "" when identical, otherwise where they first differ.
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
				return "%s: key %s (type %d) missing" % [path, str(key), typeof(key)]
			var d: String = diff(a[key], b[key], "%s[%s]" % [path, str(key)])
			if d != "":
				return d
	elif a != b:
		return "%s: %s vs %s" % [path, str(a), str(b)]
	return ""


func expect(label: String, actual: Variant, wanted: Variant) -> void:
	var ok: bool = typeof(actual) == typeof(wanted) and actual == wanted
	if actual == null and wanted == null:
		ok = true
	if not ok:
		failures += 1
	print(("PASS " if ok else "FAIL ") + label + " -> " + (str(actual).left(80)))
