# What the right-hand dock shows, worked out from the view the server sent: a title, the card, a countdown, and BUTTONS, each
# carrying the exact command it sends. The screen only draws this and sends the command of whichever button is pressed; every
# rule (who may vote, who may end the turn) is still the server's. Pure: no nodes, so it is tested against the real server.
#
# describe(view, me, members, elapsed_ms, input) returns
#   { "mode": String, "title": String, "card": String, "lines": [String], "seconds": int (-1 = no clock), "buttons": [ {label, command, disabled?, toggle?} ] }
# modes: "none", "choice", "watch_choice", "perform", "watch", "challenge", "debate_speak", "debate_vote", "vote", "voted", "result", "end_turn"
# input: { "topic": String, "selection": Array } what the player has typed or ticked so far (for a debate topic, a "pick several" question)

const GameStateScript = preload("res://scripts/game_state.gd")
const CardsScript = preload("res://scripts/cards.gd")
const TableModelScript = preload("res://client/table_model.gd")

const ActPhase = GameStateScript.ActPhase
const DEFAULT_TOPIC := "Anything you like"


static func describe(view: Dictionary, me: int, members: Array, elapsed_ms: int = 0, input: Dictionary = {}) -> Dictionary:
	var out: Dictionary = {"mode": "none", "title": "", "card": "", "lines": [], "seconds": -1, "buttons": []}
	var clock: int = int(view.get("clock_ms", 0)) + elapsed_ms
	if view.get("game_over", false):
		out["title"] = "The game is over"
		return out
	var choice: Dictionary = view.get("choice", {})
	if not choice.is_empty():
		return _choice(out, choice, me, members, clock, input)
	var act: Dictionary = view.get("term", {}).get("act", {})
	if act.is_empty():
		return out
	var performer: int = int(act["player"])
	var who: String = TableModelScript.name_of(members, performer)
	out["card"] = CardsScript.text("performance", int(act["card"]))
	var debate: Dictionary = act.get("debate", {})
	match int(act["phase"]):
		ActPhase.PERFORMING:
			out["seconds"] = _seconds(int(act["deadline"]), clock)
			if not debate.is_empty():
				return _debate(out, view, act, debate, me, members, who, input)
			if me == performer:
				out["mode"] = "perform"
				out["title"] = "Your performance"
				out["buttons"] = [{"label": "I'm done", "command": {"type": "finish_performance"}}]
			else:
				out["mode"] = "watch"
				out["title"] = "%s is performing" % who
		ActPhase.VOTING:
			out["seconds"] = _seconds(int(act["deadline"]), clock)
			var voted: Array = act.get("voted", [])
			out["lines"] = ["%d have voted" % voted.size()]
			if not debate.is_empty():
				return _debate_vote(out, act, debate, me, members, who)
			if me == performer:
				out["mode"] = "watch"
				out["title"] = "The table is voting on you"
			elif act.has("my_vote") or me in voted:
				out["mode"] = "voted"
				out["title"] = "You voted. Waiting for the others"
			else:
				out["mode"] = "vote"
				out["title"] = "Was %s any good?" % who
				out["buttons"] = [{"label": "Good", "tone": "good", "command": {"type": "performance_vote", "good": true}}, {"label": "Bad", "tone": "bad", "command": {"type": "performance_vote", "good": false}}]
		ActPhase.DONE:
			out["mode"] = "result"
			out["title"] = _result_line(view, who)
			if me == performer:
				out["mode"] = "end_turn"
				if act.has("end_by"):
					out["seconds"] = _seconds(int(act["end_by"]), clock)
				out["buttons"] = [{"label": "End my turn", "command": {"type": "end_turn"}}]
	return out


# A question for someone: you answer, or you watch them answer.
static func _choice(out: Dictionary, choice: Dictionary, me: int, members: Array, clock: int, input: Dictionary) -> Dictionary:
	out["seconds"] = _seconds(int(choice["deadline"]), clock)
	out["card"] = str(choice.get("prompt", ""))
	if int(choice["player"]) != me:
		out["mode"] = "watch_choice"
		out["title"] = "%s is choosing…" % TableModelScript.name_of(members, int(choice["player"]))
		return out
	out["mode"] = "choice"
	out["title"] = "Your choice"
	var buttons: Array = []
	match str(choice["kind"]):
		"option":
			for i in choice["labels"].size():
				buttons.append({"label": str(choice["labels"][i]), "command": {"type": "choose", "choice": i}})
		"role":
			for role in choice["candidates"]:
				buttons.append({"label": str(role), "command": {"type": "choose", "choice": str(role)}})
		"player":
			for id in choice["candidates"]:
				buttons.append({"label": TableModelScript.name_of(members, int(id)), "command": {"type": "choose", "choice": int(id)}})
		"players":
			var picked: Array = input.get("selection", [])
			out["lines"] = ["Pick up to %d" % int(choice["max"])]
			for id in choice["candidates"]:
				buttons.append({"label": ("✓ " if id in picked else "") + TableModelScript.name_of(members, int(id)), "toggle": int(id)})
			buttons.append({"label": "Confirm", "command": {"type": "choose", "choice": picked.duplicate()}})
		"number":
			var low: int = int(choice["min"])
			var high: int = int(choice["max"])
			var step: int = maxi(1, int(ceil(float(high - low + 1) / 8.0)))   # at most 8 buttons
			var value: int = low
			while value <= high:
				buttons.append({"label": str(value), "command": {"type": "choose", "choice": value}})
				value += step
	out["buttons"] = buttons
	return out


static func _debate(out: Dictionary, view: Dictionary, act: Dictionary, debate: Dictionary, me: int, members: Array, who: String, input: Dictionary) -> Dictionary:
	var performer: int = int(act["player"])
	if int(debate["rival"]) == 0:
		if me == performer:
			out["mode"] = "challenge"
			out["title"] = "Challenge a rival to a debate"
			var topic: String = str(input.get("topic", "")).strip_edges()
			if topic == "":
				topic = DEFAULT_TOPIC
			out["lines"] = ["Topic: " + topic]
			var rivals: Array = view.get("rivals", {}).get(performer, [])
			for id in view["player_ids"]:
				if id == performer or view.get("eliminated", {}).get(id, false):
					continue
				if not rivals.is_empty() and not id in rivals:
					continue   # with rivals you must choose one of them
				out["buttons"].append({"label": TableModelScript.name_of(members, int(id)), "command": {"type": "debate_challenge", "rival": int(id), "topic": topic}})
		else:
			out["mode"] = "watch"
			out["title"] = "%s is choosing a rival to debate" % who
		return out
	var speaker: int = performer if int(debate["side"]) == 0 else int(debate["rival"])
	var rival_name: String = TableModelScript.name_of(members, int(debate["rival"]))
	out["lines"] = ["Topic: %s" % str(debate.get("topic", "")), "%s against %s" % [who, rival_name]]
	if me == speaker:
		out["mode"] = "debate_speak"
		out["title"] = "Your turn to speak"
		out["buttons"] = [{"label": "I've said enough", "command": {"type": "debate_finish"}}]
	else:
		out["mode"] = "watch"
		out["title"] = "%s is speaking" % TableModelScript.name_of(members, speaker)
	return out


static func _debate_vote(out: Dictionary, act: Dictionary, debate: Dictionary, me: int, members: Array, who: String) -> Dictionary:
	var performer: int = int(act["player"])
	var rival: int = int(debate["rival"])
	var voted: Array = act.get("voted", [])
	out["lines"].append("Topic: %s" % str(debate.get("topic", "")))
	if me == performer or me == rival:
		out["mode"] = "watch"
		out["title"] = "The table is voting on your debate"
	elif act.has("my_vote") or me in voted:
		out["mode"] = "voted"
		out["title"] = "You voted. Waiting for the others"
	else:
		out["mode"] = "debate_vote"
		out["title"] = "Who won the debate?"
		for id in [performer, rival]:
			out["buttons"].append({"label": TableModelScript.name_of(members, id), "command": {"type": "debate_vote", "winner": id}})
	return out


# The line under a finished performance: how the vote went and what card was drawn.
static func _result_line(view: Dictionary, who: String) -> String:
	var log: Array = view.get("event_log", [])
	for i in range(log.size() - 1, -1, -1):
		var event: Dictionary = log[i]
		if event["type"] == "performance_resolved":
			var line: String = "%s: %d Good, %d Bad" % [who, int(event["good"]), int(event["bad"])]
			if int(event["popularity_delta"]) != 0:
				line += " (%+d popularity)" % int(event["popularity_delta"])
			if event.has("text"):
				line += ". %s card: %s" % [str(event["deck"]).capitalize(), str(event["text"])]
			return line
	return "%s has finished" % who


static func _seconds(deadline_ms: int, clock_ms: int) -> int:
	return maxi(0, int(ceil(float(deadline_ms - clock_ms) / 1000.0)))
