extends SceneTree

const ConstitutionScript = preload("res://scripts/constitution.gd")

var failures: int = 0


func _init() -> void:
	var articles: Dictionary = ConstitutionScript.initial_articles()
	expect("31 articles", articles.size(), 31)
	expect("Tax is article 2", ConstitutionScript.title(2), "Tax")
	expect("Tax text round-trips", ConstitutionScript.to_text(articles[2]), "Tax: 20% of income goes to the treasury every round.")
	expect("Levy Band Shift has a space in '− 20'", "below − 20 popularity" in ConstitutionScript.to_text(articles[5]), true)
	expect("unknown id has no title", ConstitutionScript.title(999), "")

	# Each call gives an independent copy, so amending one game can't change another.
	articles[2][1]["text"] = "99%"
	expect("copies are independent", ConstitutionScript.initial_articles()[2][1]["text"], "20%")

	print("%d failure(s)" % failures)
	quit(1 if failures > 0 else 0)


func expect(label: String, actual: Variant, wanted: Variant) -> void:
	var ok: bool = actual == wanted
	if not ok:
		failures += 1
	print(("PASS " if ok else "FAIL ") + label + " -> " + str(actual))
