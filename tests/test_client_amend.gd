extends SceneTree

const CoreScript = preload("res://server/server_core.gd")
const ModelScript = preload("res://client/session_model.gd")
const AmendModelScript = preload("res://client/amend_model.gd")
const AmendScreenScript = preload("res://client/amend_screen.gd")
const TurnScript = preload("res://client/turn_model.gd")
const GameStateScript = preload("res://scripts/game_state.gd")
const SerializerScript = preload("res://scripts/serializer.gd")

var failures: int = 0
var core
var phones: Dictionary = {}
var code: String = ""


func _init() -> void:
	the_window()
	the_lists()
	proposing_and_voting()
	the_vice()
	confronting()
	the_sheet()
	print("%d failure(s)" % failures)
	quit(1 if failures > 0 else 0)


# Five phones at a started game; player 2 is Leader and the Inauguration window is open. (A Commander can't amend, so seeds are
# tried until the Leader is a President.)
func table() -> void:
	for seed_value in range(51, 400):
		core = CoreScript.new(seed_value)
		phones = {}
		for conn in [1, 2, 3, 4, 5]:
			var model = ModelScript.new()
			model.connected = true
			phones[conn] = model
			core.connect_peer(conn, 0)
		send(1, ModelScript.make_create_room("Ada", ""))
		code = phones[1].code
		for conn in [2, 3, 4, 5]:
			send(conn, ModelScript.make_join_room(code, ["", "Bola", "Chi", "Dayo", "Efe"][conn - 1], ""))
		send(1, ModelScript.make_start_game())
		for conn in [1, 2, 3, 4, 5]:
			send(conn, ModelScript.make_command({"type": "cast_vote", "candidate": 2}))
		if phones[1].view["leader_type"] == GameStateScript.LeaderType.PRESIDENT:
			assert(phones[1].view["term"]["phase"] == GameStateScript.TermPhase.INAUGURATION)
			return
	assert(false, "no seed gave a President")


func state():
	return core.rooms[code]["state"]


func sync_all() -> void:
	for conn in phones:
		send(conn, ModelScript.make_sync())


func send(conn: int, text: String) -> void:
	for item in core.receive(conn, text, 0):
		var errors: Array = []
		if phones.has(item["to"]):
			phones[item["to"]].apply(SerializerScript.from_json(item["text"], errors))


func dock(conn: int) -> Dictionary:
	return TurnScript.describe(phones[conn].view, phones[conn].seat, phones[conn].members)


func the_window() -> void:
	table()
	var leader: Dictionary = dock(2)
	expect("at the Inauguration the Leader is offered to propose or pass", [leader["mode"], leader["buttons"].map(func(b): return b["label"]), leader["seconds"]], ["window", ["Propose an amendment", "Pass"], 60])
	expect("the others wait for the Leader", [dock(3)["mode"], dock(3)["title"]], ["watch", "Bola may amend"])
	expect("only the Leader (or the Vice) can use the window", [AmendModelScript.my_window(phones[2].view, 2), AmendModelScript.my_window(phones[3].view, 3)], [GameStateScript.AmendWindow.INAUGURATION, -1])
	expect("the Pass button is the real command", leader["buttons"][1]["command"], {"type": "pass_window"})
	send(2, ModelScript.make_command(leader["buttons"][1]["command"]))
	expect("passing closes the window: the performance begins", [AmendModelScript.open_window(phones[2].view), dock(2)["mode"]], [-1, "perform"])
	table()
	state().sick[2] = true
	sync_all()
	expect("a sick Leader may not amend, and is told so", [AmendModelScript.can_use_powers(phones[2].view, 2), dock(2)["buttons"].map(func(b): return b["label"]), dock(2)["title"].contains("can't amend")], [false, ["Pass"], true])
	table()
	state().turns_played = 2
	state().term["phase"] = GameStateScript.TermPhase.TURNS
	state().term["waiting"] = [3, 4, 5]
	state().term["played"] = [1, 2]
	state().player_count = 5
	sync_all()
	expect("the mid-term window opens once half have played (3 of 5), not at 2", AmendModelScript.open_window(phones[2].view), -1)
	state().turns_played = 3
	sync_all()
	expect("... and then the Leader gets the Amend button's window", AmendModelScript.my_window(phones[2].view, 2), GameStateScript.AmendWindow.MID_TERM)


func the_lists() -> void:
	table()
	var view: Dictionary = phones[2].view
	var articles: Array = AmendModelScript.amendable_articles(view)
	expect("only articles with a rule attached to a word are offered", [articles.size(), articles.map(func(a): return a["id"]).has(2), articles.map(func(a): return a["id"]).has(4)], [10, true, false])
	var tax: Array = AmendModelScript.words(view, 2)
	var rate: Dictionary = tax.filter(func(w): return w["kind"] == "bound")[0]
	expect("in the Tax article the rate is tappable and the other highlighted words are shown but fixed", [rate["text"], tax.filter(func(w): return w["kind"] == "unbound").size(), tax.filter(func(w): return w["kind"] == "bound").size()], ["20%", 3, 1])
	var rates: Array = AmendModelScript.options(rate["binding"], "20%", view)
	expect("a percentage offers a short list round the current value, all valid", [rates[0], rates.size() <= 11, rates.has("25%"), rates.has("10%"), rates.has("0%"), rates.has("100%")], ["20%", true, true, true, true, true])
	var all_valid: bool = true
	for option in rates:
		all_valid = all_valid and int(option.trim_suffix("%")) >= 0 and int(option.trim_suffix("%")) <= 100
	expect("... and nothing outside 0 to 100", all_valid, true)
	var levy_words: Array = AmendModelScript.words(view, 3)
	var levy: Dictionary = levy_words.filter(func(w): return w["kind"] == "bound")[0]
	var levies: Array = AmendModelScript.options(levy["binding"], "25", view)
	var in_band: bool = true
	for option in levies:
		in_band = in_band and int(option) >= 25 and int(option) <= 50
	expect("the levy only offers values inside the levy band, so a fine can't happen by tapping", [in_band, levies.has("50"), levies.has("30")], [true, true, true])
	var compare: Dictionary = AmendModelScript.words(view, 1).filter(func(w): return w["kind"] == "bound")[0]
	expect("a word with a few meanings offers each meaning once", AmendModelScript.options(compare["binding"], "more", view), ["more", "less"])
	var signs: Dictionary = AmendModelScript.words(view, 31).filter(func(w): return w["kind"] == "bound")[0]
	expect("'+' and '-' are offered, without the duplicate minus", AmendModelScript.options(signs["binding"], "−", view).size(), 2)
	expect("the proposal command carries every word, with the edits in place", AmendModelScript.propose_command(view, 2, {rate["index"]: "25%"})["new_texts"][rate["index"]], "25%")
	expect("... and the window", AmendModelScript.propose_command(view, 2, {})["window"], GameStateScript.AmendWindow.INAUGURATION)
	expect("the preview shows the new wording", AmendModelScript.text_with(view, 2, {rate["index"]: "25%"}).contains("25% of income"), true)


func proposing_and_voting() -> void:
	table()
	var view: Dictionary = phones[2].view
	var rate: Dictionary = AmendModelScript.words(view, 2).filter(func(w): return w["kind"] == "bound")[0]
	send(2, ModelScript.make_command(AmendModelScript.propose_command(view, 2, {rate["index"]: "25%"})))
	expect("a tapped value is accepted by the server: no fine, and it goes to the vote", [state().amend.get("phase", 0), state().event_log.any(func(e): return e["type"] == "amendment_failed")], [GameStateScript.AmendPhase.VOTING, false])
	var vote: Dictionary = dock(3)
	expect("the others are asked to keep or reject, with old and new wording", [vote["mode"], vote["buttons"].map(func(b): return b["label"]), vote["card"].contains("20%"), vote["card"].contains("25%")], ["amend_vote", ["Keep it", "Reject it"], true, true])
	expect("the Leader just watches", [dock(2)["mode"], dock(2)["buttons"]], ["watch", []])
	for conn in [1, 3, 4]:
		send(conn, ModelScript.make_command(dock(conn)["buttons"][0]["command"]))
	expect("after voting, a player is told they voted", dock(1)["mode"], "voted")
	send(5, ModelScript.make_command(dock(5)["buttons"][0]["command"]))
	sync_all()
	expect("when all have voted to keep it, the Constitution changes everywhere", [phones[4].view["articles"][2][rate["index"]]["text"], dock(2)["mode"] != "amend_vote"], ["25%", true])


func the_vice() -> void:
	table()
	state().vice_id = 3
	sync_all()
	expect("the Vice may also use the window", [AmendModelScript.my_window(phones[3].view, 3), dock(3)["buttons"].map(func(b): return b["label"])], [GameStateScript.AmendWindow.INAUGURATION, ["Propose an amendment"]])
	var view: Dictionary = phones[2].view
	var rate: Dictionary = AmendModelScript.words(view, 2).filter(func(w): return w["kind"] == "bound")[0]
	send(2, ModelScript.make_command(AmendModelScript.propose_command(view, 2, {rate["index"]: "10%"})))
	var ask: Dictionary = dock(3)
	expect("the Leader's proposal waits for the Vice: they are asked to agree, with the wording", [ask["mode"], ask["buttons"].map(func(b): return b["label"]), ask["card"].contains("10%"), ask["seconds"]], ["cosign", ["Agree", "Refuse"], true, 30])
	expect("the Leader is told they are waiting", [dock(2)["mode"], dock(2)["title"]], ["watch", "Waiting for Chi to agree"])
	send(3, ModelScript.make_command(ask["buttons"][0]["command"]))
	expect("when the Vice agrees it goes to the vote, and both sit it out", [state().amend.get("phase", 0), dock(3)["mode"], dock(2)["mode"]], [GameStateScript.AmendPhase.VOTING, "watch", "watch"])


func confronting() -> void:
	table()
	state().unions[1] = {"type": GameStateScript.UnionType.ACTIVIST, "owner": 4, "members": [4, 5], "confront_used": false}
	sync_all()
	var rate: Dictionary = AmendModelScript.words(phones[2].view, 2).filter(func(w): return w["kind"] == "bound")[0]
	send(2, ModelScript.make_command(AmendModelScript.propose_command(phones[2].view, 2, {rate["index"]: "30%"})))
	var union: Dictionary = dock(4)
	expect("the Unionizer sees a Confront button beside their vote", union["buttons"].map(func(b): return b["label"]), ["Keep it", "Reject it", "Confront the Leader (your union)"])
	expect("a member who isn't the Unionizer does not", dock(5)["buttons"].map(func(b): return b["label"]), ["Keep it", "Reject it"])
	send(4, ModelScript.make_command(union["buttons"][2]["command"]))
	expect("pressing it confronts: the union's votes are now automatic, against the Leader", [state().amend["activists"], dock(5)["title"]], [[1], "Your union votes for you"])
	table()
	state().unions[1] = {"type": GameStateScript.UnionType.AGBERO, "owner": 3, "members": [3, 2], "confront_used": false}   # the Leader is in this mob
	sync_all()
	send(2, ModelScript.make_command(AmendModelScript.propose_command(phones[2].view, 2, {rate["index"]: "30%"})))
	var capon: Array = dock(3)["buttons"].map(func(b): return b["label"])
	expect("a mob that includes the Leader can't act on them: it names a rival instead (Article 17)", [capon.size(), capon[2].begins_with("Your mob acts on ")], [5, true])
	send(3, ModelScript.make_command(dock(3)["buttons"][2]["command"]))
	expect("the server accepts the rival and the amendment carries on", [state().event_log.any(func(e): return e["type"] == "rival_robbed"), state().amend.get("phase", 0)], [true, GameStateScript.AmendPhase.VOTING])


func the_sheet() -> void:
	table()
	var sheet = AmendScreenScript.new()
	sheet.model = phones[2]
	get_root().add_child(sheet)
	sheet.refresh()
	expect("the sheet is closed until opened", sheet.visible, false)
	sheet.open()
	expect("it opens on the list of 10 amendable articles", [sheet.visible, sheet.body.get_child_count()], [true, 11])
	var sent: Array = []
	sheet.command_requested.connect(func(command): sent.append(command))
	sheet.article_id = 2
	sheet.drawn_for = ""
	sheet.refresh()
	expect("choosing an article shows it, with Back and a disabled Propose", [sheet.footer.get_child_count(), sheet.footer.get_child(1).disabled], [2, true])
	var rate: Dictionary = AmendModelScript.words(phones[2].view, 2).filter(func(w): return w["kind"] == "bound")[0]
	sheet.tapped = rate["index"]
	sheet.drawn_for = ""
	sheet.refresh()
	sheet._choose(rate["index"], "25%", "20%")
	expect("tapping a word then a value changes it, and Propose switches on", [sheet.edits, sheet.footer.get_child(1).disabled], [{rate["index"]: "25%"}, false])
	sheet.footer.get_child(1).pressed.emit()
	expect("Propose sends the exact command", [sent.size(), sent[0]["type"], sent[0]["new_texts"][rate["index"]]], [1, "propose", "25%"])
	sheet._choose(rate["index"], "20%", "20%")
	expect("choosing the current value again undoes the change", sheet.edits, {})
	phones[2].view["windows_used"][0] = true
	sheet.refresh()
	expect("the sheet closes by itself when the window is no longer open", sheet.visible, false)
	sheet.queue_free()


func expect(label: String, actual: Variant, wanted: Variant) -> void:
	var ok: bool = typeof(actual) == typeof(wanted) and actual == wanted
	if not ok:
		failures += 1
	print(("PASS " if ok else "FAIL ") + label + " -> " + str(actual).left(90))
