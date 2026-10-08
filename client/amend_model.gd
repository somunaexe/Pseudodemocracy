# Amending the Constitution, from the phone's side. Pure (no nodes), tested against the real server.
#
# THE LEADER TAPS, NOT TYPES. Only the highlighted words a rule is attached to ("bound" words: the tax rate, the levy, the pass mark,
# how many members make a union...) can be changed, and each is changed by tapping one of a short list of values the game
# understands, so every change has a known action. A highlighted word with no rule attached yet is shown but can't be changed here:
# there is no action to attach to it. (The server still checks everything, and a word it can't read costs the Leader a fine.)
#
# describe-style functions return plain Dictionaries: { "mode", "title", "lines", "seconds", "buttons": [ {label, command | action} ] }.

const GameStateScript = preload("res://scripts/game_state.gd")
const ConstitutionScript = preload("res://scripts/constitution.gd")
const GameDataScript = preload("res://scripts/game_data.gd")
const TableModelScript = preload("res://client/table_model.gd")

const AmendWindow = GameStateScript.AmendWindow
const AmendPhase = GameStateScript.AmendPhase
const TermPhase = GameStateScript.TermPhase

const MAX_OPTIONS := 11


# --- who may amend, and when ---------------------------------------------------------------------

# Is this player the Leader, or the Vice who amends with them, and able to use that power now (not a Commander, not sick, not
# CANCELLED)? The same test as the server's, on what the phone can see.
static func can_use_powers(view: Dictionary, me: int) -> bool:
	var leader: int = int(view.get("leader_id", -1))
	var vice: int = int(view.get("vice_id", -1))
	if me != leader and not (me == vice and vice != -1):
		return false
	if int(view.get("leader_type", 0)) == GameStateScript.LeaderType.COMMANDER:
		return false
	for id in [leader, me]:
		if view.get("sick", {}).get(id, false) or int(view.get("popularity", {}).get(id, 0)) <= GameDataScript.get_int("cancelledAt"):
			return false
	return true


# The window that is open right now for amending (0, 1 or 2), or -1 (none, or already used, or something is already going on).
static func open_window(view: Dictionary) -> int:
	if not view.get("amend", {}).is_empty() or not view.get("amend_offer", {}).is_empty() or not view.get("election", {}).is_empty():
		return -1
	var phase: int = int(view.get("term", {}).get("phase", TermPhase.NONE))
	var window: int = -1
	match phase:
		TermPhase.INAUGURATION:
			window = AmendWindow.INAUGURATION
		TermPhase.TURNS:
			if int(view.get("turns_played", 0)) >= ceili(int(view.get("player_count", 0)) / 2.0):
				window = AmendWindow.MID_TERM
		TermPhase.FAREWELL:
			window = AmendWindow.FAREWELL
	if window == -1 or view.get("windows_used", {}).get(window, true):
		return -1
	return window


static func window_name(window: int) -> String:
	return ["Inauguration", "Mid-term", "Farewell"][window]


# Can this player propose an amendment now? Returns the window or -1.
static func my_window(view: Dictionary, me: int) -> int:
	return open_window(view) if can_use_powers(view, me) else -1


# --- the articles and their tappable words ---------------------------------------------------------

# Every article with at least one rule attached to a highlighted word: [ {id, title, text} ].
static func amendable_articles(view: Dictionary) -> Array:
	var ids: Array = []
	for binding in ConstitutionScript.bindings().values():
		if not int(binding["article_id"]) in ids:
			ids.append(int(binding["article_id"]))
	ids.sort()
	var result: Array = []
	for id in ids:
		if view.get("articles", {}).has(id):
			result.append({"id": id, "title": ConstitutionScript.title(id), "text": ConstitutionScript.to_text(view["articles"][id])})
	return result


# Each word of the article as the phone draws it: { index, text, kind: "fixed" | "unbound" | "bound", binding? }.
# "bound" words can be tapped; "unbound" ones are highlighted in the Constitution but have no rule attached yet.
static func words(view: Dictionary, article_id: int) -> Array:
	var bindings: Array = ConstitutionScript.bindings_for(article_id)
	var result: Array = []
	var slot: int = 0
	for index in view["articles"][article_id].size():
		var word: Dictionary = view["articles"][article_id][index]
		var entry: Dictionary = {"index": index, "text": str(word["text"]), "glue": bool(word.get("glue", false)), "kind": "fixed"}
		if word["amendable"]:
			entry["kind"] = "unbound"
			for binding in bindings:
				if int(binding["slot"]) == slot:
					entry["kind"] = "bound"
					entry["binding"] = binding
			slot += 1
		result.append(entry)
	return result


# The short list of values a bound word can be changed to, as the words that would be written. The current value is first.
static func options(binding: Dictionary, current: String, view: Dictionary) -> Array:
	var result: Array = [current]
	match str(binding["type"]):
		"enum":
			var seen_values: Array = []
			var current_value = binding["values"].get(current.to_lower(), null)
			if current_value != null:
				seen_values.append(current_value)
			for text in binding["values"]:
				var value = binding["values"][text]
				if value in seen_values:
					continue   # "-" and "−" mean the same: offer one
				seen_values.append(value)
				result.append(str(text))
		"int", "percent":
			var percent: bool = str(binding["type"]) == "percent"
			var now: int = int(current.trim_suffix("%")) if current.trim_suffix("%").is_valid_int() else 0
			var low: int = int(binding.get("min", 0))
			var high: int = int(binding.get("max", 99999)) if not percent else 100
			if binding["name"] == "levy":
				low = maxi(low, int(view.get("levy_band", {}).get("low", low)))   # the levy must stay in the band: don't offer what would be fined
				high = mini(high, int(view.get("levy_band", {}).get("high", high)))
			var candidates: Array = [now - 10, now - 5, now - 1, now + 1, now + 5, now + 10, now * 2, now / 2, low, high]
			if now >= 100:
				candidates = [now - 100, now - 50, now - 10, now + 10, now + 50, now + 100, now * 2, now / 2, low, high]
			var seen: Array = [now]
			var wanted: Array = []
			for value in candidates:
				if value >= low and value <= high and not value in seen:
					seen.append(value)
					wanted.append(value)
			wanted.sort()
			for value in wanted:
				result.append("%d%s" % [value, "%" if percent else ""])
	return result.slice(0, MAX_OPTIONS)


# The command that proposes this rewrite: edits maps word index -> new text. Unedited words are sent as they are.
static func propose_command(view: Dictionary, article_id: int, edits: Dictionary) -> Dictionary:
	var window: int = open_window(view)
	var texts: Array = []
	for word in view["articles"][article_id]:
		texts.append(str(word["text"]))
	for index in edits:
		texts[int(index)] = str(edits[index])
	return {"type": "propose", "window": window, "article_id": article_id, "new_texts": texts}


static func text_with(view: Dictionary, article_id: int, edits: Dictionary) -> String:
	var copy: Array = view["articles"][article_id].duplicate(true)
	for index in edits:
		copy[int(index)]["text"] = str(edits[index])
	return ConstitutionScript.to_text(copy)


# --- what the dock shows during an amendment ----------------------------------------------------

# The dock's content for the amendment moments: the window being open, a proposal waiting for the other of Leader and Vice, and the
# vote. Returns {} when none of these applies (so the dock shows something else).
static func dock(view: Dictionary, me: int, members: Array, elapsed_ms: int = 0) -> Dictionary:
	var clock: int = int(view.get("clock_ms", 0)) + elapsed_ms
	var offer: Dictionary = view.get("amend_offer", {})
	var amend: Dictionary = view.get("amend", {})
	var out: Dictionary = {"mode": "none", "title": "", "card": "", "lines": [], "seconds": -1, "buttons": []}
	if not offer.is_empty():
		out["seconds"] = _seconds(int(offer["deadline"]), clock)
		var wording: String = _wording_of(view, int(offer["article_id"]), offer["texts"])
		out["card"] = wording
		if me == int(offer["other"]):
			out["mode"] = "cosign"
			out["title"] = "%s wants to amend. Agree?" % TableModelScript.name_of(members, int(offer["by"]))
			out["buttons"] = [{"label": "Agree", "tone": "good", "command": {"type": "amend_agree", "accept": true}}, {"label": "Refuse", "tone": "bad", "command": {"type": "amend_agree", "accept": false}}]
		else:
			out["mode"] = "watch"
			out["title"] = "Waiting for %s to agree" % TableModelScript.name_of(members, int(offer["other"]))
		return out
	if not amend.is_empty():
		return _vote_dock(out, view, amend, me, members, clock)
	var phase: int = int(view.get("term", {}).get("phase", TermPhase.NONE))
	if phase in [TermPhase.INAUGURATION, TermPhase.FAREWELL] and view.get("election", {}).is_empty():
		var window: int = AmendWindow.INAUGURATION if phase == TermPhase.INAUGURATION else AmendWindow.FAREWELL
		if view.get("windows_used", {}).get(window, true):
			return out   # the window is used or passed: the term moves on by itself
		out["seconds"] = _seconds(int(view["term"].get("window_deadline", 0)), clock)
		var leader: int = int(view.get("leader_id", -1))
		out["mode"] = "window"
		if me == leader or (me == int(view.get("vice_id", -1)) and me != -1):
			var may: bool = can_use_powers(view, me)
			out["title"] = "Amend the Constitution?"
			if may:
				out["buttons"].append({"label": "Propose an amendment", "action": "open_amend"})
			if me == leader:
				out["buttons"].append({"label": "Pass", "command": {"type": "pass_window"}})
			elif may:
				out["lines"] = ["The Leader may pass"]
			if not may and me == leader:
				out["title"] = "You can't amend (sick or cancelled)"
		else:
			out["title"] = "%s may amend" % TableModelScript.name_of(members, leader)
			out["mode"] = "watch"
	return out


static func _vote_dock(out: Dictionary, view: Dictionary, amend: Dictionary, me: int, members: Array, clock: int) -> Dictionary:
	var article_id: int = int(amend["article_id"])
	if amend.has("deadline"):
		out["seconds"] = _seconds(int(amend["deadline"]), clock)
	out["card"] = "Now: %s\nProposed: %s" % [ConstitutionScript.to_text(view["articles"][article_id]), ConstitutionScript.to_text(amend["new_words"])]
	var voted: Array = amend.get("voted", [])
	out["lines"] = ["%d voted" % voted.size()]
	var leader: int = int(view.get("leader_id", -1))
	var vice: int = int(view.get("vice_id", -1))
	var eligible: bool = me != leader and me != vice and not view.get("eliminated", {}).get(me, false) and not view.get("sick", {}).get(me, false)
	if amend.has("my_vote") or me in voted:
		out["mode"] = "voted"
		out["title"] = "You voted. Waiting…"
	elif eligible and not _votes_automatically(view, amend, me):
		out["mode"] = "amend_vote"
		out["title"] = "Keep the new wording?"
		out["buttons"] = [{"label": "Keep it", "tone": "good", "command": {"type": "vote", "keep": true}}, {"label": "Reject it", "tone": "bad", "command": {"type": "vote", "keep": false}}]
	else:
		out["mode"] = "watch"
		out["title"] = "Vote on %s's amendment" % TableModelScript.name_of(members, leader)
		if eligible:
			out["title"] = "Your union votes for you"
	out["buttons"].append_array(confront_buttons(view, me, members))
	return out


# A member of a confronting Activist union has the union's vote cast for them.
static func _votes_automatically(view: Dictionary, amend: Dictionary, me: int) -> bool:
	for union_id in amend.get("activists", []):
		if view.get("unions", {}).has(union_id) and me in view["unions"][union_id]["members"]:
			return true
	return false


# The Unionizer's (or Capon's) confront buttons while an amendment is going on. A union that includes the Leader or the Vice
# cannot act against them (Article 17): it names a rival instead, so there is a button for each rival it may name.
static func confront_buttons(view: Dictionary, me: int, members: Array) -> Array:
	var buttons: Array = []
	var leader: int = int(view.get("leader_id", -1))
	var vice: int = int(view.get("vice_id", -1))
	for union_id in view.get("unions", {}):
		var union: Dictionary = view["unions"][union_id]
		if int(union["owner"]) != me or union["confront_used"] or union["members"].size() < GameDataScript.get_int("unionMin"):
			continue
		if view.get("sick", {}).get(me, false) or view.get("eliminated", {}).get(me, false):
			continue
		var word: String = "mob" if int(union["type"]) == GameStateScript.UnionType.AGBERO else "union"
		if leader in union["members"] or vice in union["members"]:
			var chooser: int = leader if leader in union["members"] else vice
			var rivals: Array = view.get("rivals", {}).get(chooser, [])
			for id in view["player_ids"]:
				if id in union["members"] or view.get("eliminated", {}).get(id, false):
					continue
				if not rivals.is_empty() and not id in rivals:
					continue
				buttons.append({"label": "Your %s acts on %s" % [word, TableModelScript.name_of(members, int(id))], "command": {"type": "confront", "union_id": int(union_id), "rival": int(id)}})
		else:
			var verb: String = "Block it" if int(union["type"]) == GameStateScript.UnionType.AGBERO else "Confront the Leader"
			buttons.append({"label": "%s (your %s)" % [verb, word], "command": {"type": "confront", "union_id": int(union_id)}})
	return buttons


static func _wording_of(view: Dictionary, article_id: int, texts: Array) -> String:
	var copy: Array = view["articles"][article_id].duplicate(true)
	for i in mini(copy.size(), texts.size()):
		copy[i]["text"] = str(texts[i])
	return ConstitutionScript.to_text(copy)


static func _seconds(deadline_ms: int, clock_ms: int) -> int:
	return maxi(0, int(ceil(float(deadline_ms - clock_ms) / 1000.0)))
