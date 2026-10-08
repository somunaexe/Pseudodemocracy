extends SceneTree

const LawScript = preload("res://scripts/law.gd")
const ConstitutionScript = preload("res://scripts/constitution.gd")
const GameDataScript = preload("res://scripts/game_data.gd")
const GameStateScript = preload("res://scripts/game_state.gd")

var failures: int = 0


func _init() -> void:
	starting_law_matches_the_data()
	words_are_read_strictly()
	the_live_constitution_is_what_counts()
	print("%d failure(s)" % failures)
	quit(1 if failures > 0 else 0)


func starting_law_matches_the_data() -> void:
	var s := fresh()
	var bindings: Dictionary = ConstitutionScript.bindings()
	expect("13 rules are enforced", bindings.size(), 13)
	for rule in bindings:
		var binding: Dictionary = bindings[rule]
		var value: int = LawScript.get_int(s, rule)
		if binding["type"] == "enum":
			expect("%s starts as its word '%s'" % [rule, binding["expect"]], value, int(binding["values"][str(binding["expect"]).to_lower()]))
		else:
			expect("%s starts as the number in the text" % rule, value, int(binding["expect"]))
		if binding["source"] != null and binding["type"] != "enum":
			expect("%s agrees with game_data (%s)" % [rule, binding["source"]], value, source_value(binding["source"]))


func words_are_read_strictly() -> void:
	var percent := {"type": "percent", "label": "the tax rate"}
	var whole := {"type": "int", "label": "the levy", "min": 0, "max": 99999}
	var union_size := {"type": "int", "label": "the size", "min": 1, "max": 99999}
	var choice := {"type": "enum", "label": "the multiplier", "values": {"single": 1, "double": 2, "triple": 3}}

	for pair in [["30%", 30], ["0%", 0], ["100%", 100], ["007%", 7]]:
		expect("percent reads '%s'" % pair[0], LawScript.parse(percent, pair[0]), {"ok": true, "value": pair[1]})
	for bad in ["banana", "30", "%", "101%", "-5%", "30 %", "3.5%", "30%%", "", "thirty%", "٣٠%", "３０%", "1000%"]:
		expect("percent refuses '%s'" % bad, LawScript.parse(percent, bad)["ok"], false)

	for pair in [["25", 25], ["0", 0], ["99999", 99999]]:
		expect("number reads '%s'" % pair[0], LawScript.parse(whole, pair[0]), {"ok": true, "value": pair[1]})
	for bad in ["-1", "+5", "1e3", "2.5", "100000", "", " ", "twenty", "٢٥", "25%"]:
		expect("number refuses '%s'" % bad, LawScript.parse(whole, bad)["ok"], false)
	expect("a minimum is respected", LawScript.parse(union_size, "0")["ok"], false)
	expect("... and 1 is fine", LawScript.parse(union_size, "1")["ok"], true)

	expect("choice reads 'triple'", LawScript.parse(choice, "triple")["value"], 3)
	expect("choice ignores capitals", LawScript.parse(choice, "Double")["value"], 2)
	expect("choice refuses other words", LawScript.parse(choice, "quintuple")["ok"], false)
	var problem: String = LawScript.parse(percent, "banana")["problem"]
	expect("the message names the word and the rule", problem.contains("'banana'") and problem.contains("the tax rate"), true)
	expect("... and says what is allowed", problem.contains("0% to 100%"), true)
	expect("the choices are listed", LawScript.parse(choice, "x")["problem"].contains("single, double, triple"), true)


func the_live_constitution_is_what_counts() -> void:
	var s := fresh()
	expect("tax starts at 20", LawScript.get_int(s, "taxRate"), 20)
	set_rule_word(s, 2, 0, "35%")
	expect("amend the text and the rule follows", LawScript.get_int(s, "taxRate"), 35)
	var other := fresh()
	expect("another game is unaffected", LawScript.get_int(other, "taxRate"), 20)

	set_rule_word(s, 14, 0, "triple")
	expect("a word rule follows too", LawScript.get_int(s, "activistVote"), 3)
	set_rule_word(s, 31, 1, "+")
	expect("a sign can be flipped", LawScript.get_int(s, "nepoSign2"), 1)
	expect("... the others stay", [LawScript.get_int(s, "nepoSign1"), LawScript.get_int(s, "nepoSign3")], [-1, -1])
	set_rule_word(s, 31, 0, "-")
	expect("a plain hyphen also means minus", LawScript.get_int(s, "nepoSign1"), -1)

	# A rewrite is checked word by word, and only the bound words.
	var old: Array = other.articles[2]
	var ok_words: Array = texts_of(old)
	ok_words[6] = "banana"   # "the" (word 6): highlighted, but the game does not enforce it
	expect("an unenforced word can be anything", LawScript.check_new_wording(2, old, ok_words), "")
	var bad_words: Array = texts_of(old)
	bad_words[1] = "30"   # the tax rate (word 1) must be a percentage
	expect("a bound word must be readable", LawScript.check_new_wording(2, old, bad_words).begins_with("The game can't apply '30'"), true)
	expect("an article with no rules accepts anything", LawScript.check_new_wording(4, other.articles[4], texts_of(other.articles[4])), "")


# --- helpers ---------------------------------------------------------------------------

func fresh() -> GameStateScript:
	var s: GameStateScript = GameStateScript.new()
	s.articles = ConstitutionScript.initial_articles()
	return s


func set_rule_word(s: GameStateScript, article_id: int, slot: int, text: String) -> void:
	var seen: int = 0
	for word in s.articles[article_id]:
		if word["amendable"]:
			if seen == slot:
				word["text"] = text
				return
			seen += 1


func texts_of(words: Array) -> Array:
	var result: Array = []
	for word in words:
		result.append(word["text"])
	return result


func source_value(source: String) -> int:
	if "." in source:
		var parts: PackedStringArray = source.split(".")
		return GameDataScript.get_nested_int(parts[0], parts[1])
	return GameDataScript.get_int(source)


func expect(label: String, actual: Variant, wanted: Variant) -> void:
	var ok: bool = typeof(actual) == typeof(wanted) and actual == wanted
	if not ok:
		failures += 1
	print(("PASS " if ok else "FAIL ") + label + " -> " + str(actual).left(80))
