extends SceneTree

const ViewsScript = preload("res://scripts/views.gd")
const SerializerScript = preload("res://scripts/serializer.gd")
const FlowScript = preload("res://scripts/amendment_flow.gd")
const GameStateScript = preload("res://scripts/game_state.gd")
const ConstitutionScript = preload("res://scripts/constitution.gd")

const INAUG = GameStateScript.AmendWindow.INAUGURATION
const TAX := 2
const SERVER := 0

var failures: int = 0


func _init() -> void:
	events_are_filtered()
	votes_stay_secret()
	every_field_is_classified()
	views_are_safe_copies()
	print("%d failure(s)" % failures)
	quit(1 if failures > 0 else 0)


func events_are_filtered() -> void:
	var events: Array = [
		{"type": "announcement", "audience": []},
		{"type": "private_note", "audience": [2]},
		{"type": "for_two_and_three", "audience": [2, 3]},
		{"type": "no_audience_field"},
	]
	expect("everyone sees public events", types(ViewsScript.visible_events(events, 4)), ["announcement", "no_audience_field"])
	expect("player 2 sees theirs too", types(ViewsScript.visible_events(events, 2)), ["announcement", "private_note", "for_two_and_three", "no_audience_field"])
	expect("player 3 sees only the shared one", types(ViewsScript.visible_events(events, 3)), ["announcement", "for_two_and_three", "no_audience_field"])
	expect("a spectator sees only public events", types(ViewsScript.visible_events(events, 99)), ["announcement", "no_audience_field"])
	expect("no events, no problem", ViewsScript.visible_events([], 1), [])

	var sorted: Dictionary = ViewsScript.deliver(events, [2, 3, 4])
	expect("deliver gives one list per player", sorted.keys(), [2, 3, 4])
	expect("... each filtered", [sorted[2].size(), sorted[3].size(), sorted[4].size()], [4, 3, 2])


func votes_stay_secret() -> void:
	var s := mid_vote_state()
	# Player 2 voted keep (true), player 3 voted reject (false). Players 4 and 5 have not voted.
	for viewer in [1, 2, 3, 4, 5, 99]:
		var view: Dictionary = ViewsScript.state_view(s, viewer)
		expect("player %d: no vote table in the view" % viewer, view["amend"].has("votes"), false)
		expect("player %d: sees WHO has voted" % viewer, view["amend"]["voted"], [2, 3])
		var text: String = ViewsScript.state_view_json(s, viewer)
		# The Constitution has the word "votes" in it, so look for the vote table's key
		# (a name followed by a colon) and for the actual choices, not for the word.
		expect("player %d: the text sent has no vote table" % viewer, text.contains("\"votes\":"), false)
		expect("player %d: the text sent has nobody's choices" % viewer, text.contains("[[2,true],[3,false]]"), false)
	expect("player 2 sees their own vote", ViewsScript.state_view(s, 2)["amend"]["my_vote"], true)
	expect("player 3 sees their own vote", ViewsScript.state_view(s, 3)["amend"]["my_vote"], false)
	expect("player 4 has no vote to show", ViewsScript.state_view(s, 4)["amend"].has("my_vote"), false)
	expect("a spectator has no vote to show", ViewsScript.state_view(s, 99)["amend"].has("my_vote"), false)
	expect("the amendment's wording is public", ViewsScript.state_view(s, 4)["amend"].has("new_words"), true)

	# The server still holds the real votes.
	expect("the server keeps the votes", s.amend["votes"], {2: true, 3: false})

	# After the result everyone may learn how everyone voted.
	FlowScript.handle(s, 4, {"type": "vote", "keep": true})
	var ev := FlowScript.handle(s, 5, {"type": "vote", "keep": true})
	expect("the result reveals the votes to everyone", ViewsScript.visible_events(ev, 4)[1]["votes"], {2: true, 3: false, 4: true, 5: true})
	expect("... and the amendment is no longer in progress", ViewsScript.state_view(s, 4)["amend"], {})

	# Events addressed to one player stay out of the others' history.
	s.event_log.append({"type": "private_note", "audience": [2]})
	expect("the addressee has it in their history", types(ViewsScript.state_view(s, 2)["event_log"]).has("private_note"), true)
	expect("others do not", types(ViewsScript.state_view(s, 3)["event_log"]).has("private_note"), false)


func every_field_is_classified() -> void:
	var fields: Array = SerializerScript.state_fields(GameStateScript.new())
	expect("every GameState field is classified", ViewsScript.unclassified_fields(fields), [])
	expect("a new, unclassified field is caught", ViewsScript.unclassified_fields(fields + ["doctor_beads"]), ["doctor_beads"])
	var total: int = ViewsScript.PUBLIC_FIELDS.size() + ViewsScript.REDACTED_FIELDS.size() + ViewsScript.SERVER_ONLY_FIELDS.size()
	expect("no field is listed twice, none is stale", total, fields.size())
	var view: Dictionary = ViewsScript.state_view(GameStateScript.new(), 1)
	expect("the view has every field except the server-only ones, plus the derived keys", view.keys().size(), fields.size() - ViewsScript.SERVER_ONLY_FIELDS.size() + ViewsScript.DERIVED_KEYS.size())
	expect("the view has no wills", view.has("wills"), false)


func views_are_safe_copies() -> void:
	var s := mid_vote_state()
	var view: Dictionary = ViewsScript.state_view(s, 4)
	view["psd"][1] = 999999
	view["articles"][TAX][1]["text"] = "99%"
	view["amend"]["voted"].append(42)
	expect("changing a view does not change the money", s.psd[1], 1000)
	expect("... or the Constitution", s.articles[TAX][1]["text"], "20%")
	expect("... or the votes", s.amend["votes"].size(), 2)

	# A view can be sent: it survives the serializer unchanged.
	var errors: Array = []
	var fresh: Dictionary = ViewsScript.state_view(s, 4)
	var back = SerializerScript.from_json(SerializerScript.to_json(fresh), errors)
	expect("a view survives being sent", errors, [])
	expect("... unchanged", SerializerScript.to_json(back), SerializerScript.to_json(fresh))


# --- helpers ---------------------------------------------------------------------------

func mid_vote_state() -> GameStateScript:
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
	FlowScript.handle(s, 1, {"type": "propose", "window": INAUG, "article_id": TAX, "new_texts": texts})
	FlowScript.handle(s, SERVER, {"type": "rule_grammar", "ok": true})
	FlowScript.handle(s, 2, {"type": "vote", "keep": true})
	FlowScript.handle(s, 3, {"type": "vote", "keep": false})
	return s


func types(events: Array) -> Array:
	var result: Array = []
	for event in events:
		result.append(event["type"])
	return result


func expect(label: String, actual: Variant, wanted: Variant) -> void:
	var ok: bool = typeof(actual) == typeof(wanted) and actual == wanted
	if not ok:
		failures += 1
	print(("PASS " if ok else "FAIL ") + label + " -> " + str(actual).left(80))
