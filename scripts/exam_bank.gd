class_name ExamBank

# The prepared exam questions (data/exam_questions.json, from data/source/exam_questions.js). A Leader does not type their exam:
# they pick questions from this bank and say what their true answer to each is. A question is its position in the list.

const PATH := "res://data/exam_questions.json"

static var _data: Dictionary = {}


static func _load() -> Dictionary:
	if _data.is_empty():
		var file := FileAccess.open(PATH, FileAccess.READ)
		assert(file != null, "Can't open %s. Run: node tools/export_exam_questions.js" % PATH)
		var parsed = JSON.parse_string(file.get_as_text())
		assert(parsed is Dictionary, "%s is not valid JSON" % PATH)
		_data = parsed
	return _data


static func count() -> int:
	return _load()["questions"].size()


# { "text": String, "options": Array of String }
static func question(id: int) -> Dictionary:
	return _load()["questions"][id].duplicate(true)


static func all() -> Array:
	return _load()["questions"].duplicate(true)
