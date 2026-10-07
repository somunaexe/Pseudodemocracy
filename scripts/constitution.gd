class_name Constitution

# The Constitution as data: data/articles.json, generated from the JS source by
# tools/export_articles.js. The live, amendable copy is GameState.articles.

const PATH := "res://data/articles.json"

static var _data: Dictionary = {}


static func _load() -> Dictionary:
	if _data.is_empty():
		var file := FileAccess.open(PATH, FileAccess.READ)
		assert(file != null, "Can't open %s. Run: node tools/export_articles.js" % PATH)
		var parsed = JSON.parse_string(file.get_as_text())
		assert(parsed is Dictionary, "%s is not valid JSON" % PATH)
		_data = parsed
	return _data


# A fresh copy of every article's starting wording: article id -> Array of words.
static func initial_articles() -> Dictionary:
	var result: Dictionary = {}
	for chapter in _load()["chapters"]:
		for article in chapter["articles"]:
			result[int(article["id"])] = article["words"].duplicate(true)
	return result


static func title(article_id: int) -> String:
	for chapter in _load()["chapters"]:
		for article in chapter["articles"]:
			if int(article["id"]) == article_id:
				return article["title"]
	return ""


# Words back into a sentence. A word marked "glue" has no space before it.
static func to_text(words: Array) -> String:
	var text: String = ""
	for word in words:
		if not word["glue"] and not text.is_empty():
			text += " "
		text += word["text"]
	return text
