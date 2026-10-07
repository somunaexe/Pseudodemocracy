extends SceneTree

const AmendmentScript = preload("res://scripts/amendment.gd")

var words: Array = [
	{"text": "Tax:", "amendable": false, "glue": false},
	{"text": "20%", "amendable": true, "glue": false},
]

func _init() -> void:
	check("valid change", ["Tax:", "30%"], true)
	check("fixed word changed", ["Duty:", "30%"], false)
	check("wrong length", ["Tax:"], false)
	check("blank word", ["Tax:", "  "], false)
	check("space inside", ["Tax:", "30 %"], false)
	check("underscores", ["Tax:", "3__0"], false)
	check("tab inside", ["Tax:", "30\t%"], false)
	check("apostrophe ok", ["Tax:", "can’t"], true)
	quit()

func check(label: String, proposal: Array, should_pass: bool) -> void:
	var result: String = AmendmentScript.validate_words(words, proposal)
	var ok: bool = result.is_empty() == should_pass
	print(("PASS " if ok else "FAIL ") + label + " -> '" + result + "'")