class_name GameData

# Reads data/game_data.json, which is generated from data/source/game_data.js
# by tools/export_game_data.js. Never type these numbers into GDScript.

const PATH := "res://data/game_data.json"

static var _cache: Dictionary = {}


static func values() -> Dictionary:
	if _cache.is_empty():
		var file := FileAccess.open(PATH, FileAccess.READ)
		assert(file != null, "Can't open %s. Run: node tools/export_game_data.js" % PATH)
		var parsed = JSON.parse_string(file.get_as_text())
		assert(parsed is Dictionary, "%s is not valid JSON" % PATH)
		_cache = parsed
	return _cache


# JSON numbers always load as floats in Godot, so whole numbers are converted here.
static func get_int(key: String) -> int:
	var data := values()
	assert(data.has(key), "game_data.json has no key '%s'" % key)
	return int(data[key])


# Nested values, e.g. get_nested_int("levy", "bandLow").
static func get_nested_int(key: String, sub_key: String) -> int:
	var data := values()
	assert(data.has(key) and data[key] is Dictionary and data[key].has(sub_key),
		"game_data.json has no '%s.%s'" % [key, sub_key])
	return int(data[key][sub_key])
