extends SceneTree

const GameDataScript = preload("res://scripts/game_data.gd")

var failures: int = 0


func _init() -> void:
	# Values the handbook states in prose, so a bad export is caught.
	expect("cancelledAt is -50", GameDataScript.get_int("cancelledAt"), -50)
	expect("start money is 1000", GameDataScript.get_int("startMoney"), 1000)
	expect("box total is 12550", GameDataScript.get_int("boxTotal"), 12550)
	expect("coup costs 300", GameDataScript.get_int("coupCost"), 300)
	expect("coup gap is 20", GameDataScript.get_int("coupGap"), 20)
	expect("levy starts at 25", GameDataScript.get_nested_int("levy", "start"), 25)
	expect("levy band high is 50", GameDataScript.get_nested_int("levy", "bandHigh"), 50)
	expect("swing table has 7 rows", GameDataScript.values()["swing"].size(), 7)

	# The exam: 5 to 10 questions with 2 to 3 options each; one Leader card for each role.
	expect("an exam has at least 5 questions", GameDataScript.get_int("examQuestions"), 5)
	expect("... and at most 10", GameDataScript.get_int("examMaxQuestions"), 10)
	expect("each question has at least 2 options", GameDataScript.get_int("examOptions"), 2)
	expect("... and at most 3", GameDataScript.get_int("examMaxOptions"), 3)
	var cards: Dictionary = GameDataScript.values()["components"]["leaderCards"]
	expect("one Leader card for each of the three roles", [int(cards["Dictator"]), int(cards["President"]), int(cards["Commander"]), cards.size()], [1, 1, 1, 3])

	# The swing table, including its ranges ("8–10") and open end ("11+").
	for pair in [[3, 10], [4, 7], [5, 6], [6, 5], [7, 4], [8, 3], [9, 3], [10, 3], [11, 1], [15, 1], [2, 10]]:
		expect("base swing for %d players" % pair[0], GameDataScript.base_swing(pair[0]), pair[1])

	# Gotcha made visible: JSON numbers arrive as floats, get_int converts them.
	expect("raw JSON number is a float", typeof(GameDataScript.values()["cancelledAt"]), TYPE_FLOAT)
	expect("get_int returns an int", typeof(GameDataScript.get_int("cancelledAt")), TYPE_INT)

	print("%d failure(s)" % failures)
	quit(1 if failures > 0 else 0)


func expect(label: String, actual: Variant, wanted: Variant) -> void:
	var ok: bool = actual == wanted
	if not ok:
		failures += 1
	print(("PASS " if ok else "FAIL ") + label + " -> " + str(actual))
