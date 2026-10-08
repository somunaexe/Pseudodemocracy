extends SceneTree

const ConstitutionScript = preload("res://scripts/constitution.gd")
const GameDataScript = preload("res://scripts/game_data.gd")

var failures: int = 0


# The Constitution is the source of truth for every number it governs. If game code read one
# of those numbers straight from game_data, an amendment would change the words and not the
# game. This test fails if any script under scripts/ does that.
func _init() -> void:
	var bindings: Dictionary = ConstitutionScript.bindings()

	# The scanner itself must be able to catch a violation.
	expect("catches get_int on a governed key", violations('var x = GameDataScript.get_int("agberoSteal")', bindings), ["agberoSteal"])
	expect("catches a nested key", violations('GameDataScript.get_nested_int("levy", "start")', bindings), ["levy"])
	expect("catches reading the raw table", violations('GameDataScript.values()["taxRate"]', bindings), ["taxRate"])
	expect("leaves a locked key alone", violations('GameDataScript.get_int("amendPenalty")', bindings), [])
	expect("leaves the law alone", violations('LawScript.get_int(state, "agberoSteal")', bindings), [])

	# Every governed key must really exist in the data (catches typos in articles.js).
	for rule in bindings:
		var source = bindings[rule]["source"]
		if source != null:
			var top: String = str(source).split(".")[0]
			expect("%s: source '%s' exists in game_data" % [rule, source], GameDataScript.values().has(top), true)

	# Popularity has a base and a modifier. Only popularity.gd may read the raw table.
	expect("catches a raw popularity read", reads_popularity_directly("if state.popularity.get(id, 0) < 0:"), true)
	expect("leaves Popularity calls alone", reads_popularity_directly("PopularityScript.effective(state, id)"), false)

	var dir := DirAccess.open("res://scripts")
	var scanned: int = 0
	for file in dir.get_files():
		if not file.ends_with(".gd") or file == "game_data.gd":
			continue
		var text: String = FileAccess.get_file_as_string("res://scripts/" + file)
		scanned += 1
		expect("%s reads no governed number from the data" % file, violations(text, bindings), [])
		if file != "popularity.gd":
			expect("%s doesn't read raw popularity (use Popularity)" % file, reads_popularity_directly(text), false)
	expect("scanned the scripts", scanned > 10, true)

	print("%d failure(s)" % failures)
	quit(1 if failures > 0 else 0)


# Raw popularity is only the BASE. What counts also includes temporary modifiers (the Nepo Baby
# debuff), so code must ask Popularity.effective, or Popularity.base when it means the base.
func reads_popularity_directly(text: String) -> bool:
	return text.contains("state.popularity")


# The names of governed rules whose starting number is read straight from game_data in this text.
func violations(text: String, bindings: Dictionary) -> Array:
	var found: Array = []
	for rule in bindings:
		var source = bindings[rule]["source"]
		if source == null:
			continue
		var parts: PackedStringArray = str(source).split(".")
		var patterns: Array = []
		if parts.size() == 1:
			patterns = ['get_int("%s")' % parts[0], 'values()["%s"]' % parts[0]]
		else:
			patterns = ['get_nested_int("%s", "%s")' % [parts[0], parts[1]], 'values()["%s"]["%s"]' % [parts[0], parts[1]]]
		for pattern in patterns:
			if text.contains(pattern) and not found.has(parts[0] if parts.size() > 1 else rule):
				found.append(parts[0] if parts.size() > 1 else rule)
	return found


func expect(label: String, actual: Variant, wanted: Variant) -> void:
	var ok: bool = typeof(actual) == typeof(wanted) and actual == wanted
	if not ok:
		failures += 1
	print(("PASS " if ok else "FAIL ") + label + " -> " + str(actual).left(80))
