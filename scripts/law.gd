class_name Law

# The law as it stands NOW. Leaders can rewrite highlighted words in the Constitution, so a
# number such as the Agbero steal can't be fixed in the game's data: it is whatever the
# current wording says. Every rule the Constitution governs is read through here, from the
# live articles in GameState.articles.
#
# A rule is a "binding" (data/source/articles.js): one highlighted word of one article and how
# to read it. Highlighted words with no binding are not enforced by the game; the table
# enforces them, as in the physical game.
#
# A Leader may only write a bound word the game can read (check_new_wording), so the law can
# always be applied. Reading a word that can't be read means the state was corrupted by hand.

const GameStateScript = preload("res://scripts/game_state.gd")
const ConstitutionScript = preload("res://scripts/constitution.gd")

const DEFAULT_INT_MAX := 99999


# The current value of a rule. Whole numbers, percentages and fixed words (such as "double")
# all come back as ints.
static func get_int(state: GameStateScript, rule: String) -> int:
	var all: Dictionary = ConstitutionScript.bindings()
	assert(all.has(rule), "There is no rule called '%s'" % rule)
	var binding: Dictionary = all[rule]
	var words: Array = state.articles[binding["article_id"]]
	var parsed: Dictionary = parse(binding, word_in_slot(words, int(binding["slot"])))
	assert(parsed["ok"], "The Constitution holds a word for %s that the game can't read" % rule)
	return int(parsed.get("value", 0))


# The text of the n-th highlighted word (0 = the first) of an article's words.
static func word_in_slot(words: Array, slot: int) -> String:
	var seen: int = 0
	for word in words:
		if word["amendable"]:
			if seen == slot:
				return word["text"]
			seen += 1
	return ""


# Can the game read this word as this rule? Returns { "ok": true, "value": int } or
# { "ok": false, "problem": String }.
static func parse(binding: Dictionary, text: String) -> Dictionary:
	match binding["type"]:
		"int":
			var low: int = int(binding.get("min", 0))
			var high: int = int(binding.get("max", DEFAULT_INT_MAX))
			if _is_number(text, 5) and int(text) >= low and int(text) <= high:
				return {"ok": true, "value": int(text)}
			return _unreadable(binding, text, "a whole number from %d to %d" % [low, high])
		"percent":
			if text.ends_with("%") and _is_number(text.trim_suffix("%"), 3) and int(text.trim_suffix("%")) <= 100:
				return {"ok": true, "value": int(text.trim_suffix("%"))}
			return _unreadable(binding, text, "a whole percentage from 0% to 100%, like 30%")
		"enum":
			var values: Dictionary = binding["values"]
			if values.has(text.to_lower()):
				return {"ok": true, "value": int(values[text.to_lower()])}
			return _unreadable(binding, text, "one of: " + ", ".join(values.keys()))
	assert(false, "Unknown binding type '%s'" % str(binding["type"]))
	return {"ok": false, "problem": "unknown rule type"}


# Check the bound words of a proposed rewrite (same length and fixed words already checked).
# Returns "" if the game can read them all, otherwise a message for the Leader.
static func check_new_wording(article_id: int, old_words: Array, new_texts: Array) -> String:
	var index_of_slot: Array = []
	for i in old_words.size():
		if old_words[i]["amendable"]:
			index_of_slot.append(i)
	for binding in ConstitutionScript.bindings_for(article_id):
		var parsed: Dictionary = parse(binding, new_texts[index_of_slot[int(binding["slot"])]])
		if not parsed["ok"]:
			return parsed["problem"]
	return ""


static func _is_number(text: String, max_digits: int) -> bool:
	if text.is_empty() or text.length() > max_digits:
		return false
	for character in text:
		if character < "0" or character > "9":
			return false
	return true


static func _unreadable(binding: Dictionary, text: String, wanted: String) -> Dictionary:
	return {"ok": false, "problem": "The game can't apply '%s' as %s. Use %s." % [text, binding["label"], wanted]}
