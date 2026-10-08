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


# The popularity change per vote for a table of this many active players, read from the
# swing table (rows like ["3", 10], ["8–10", 3], ["11+", 1]). Below the table's first row
# it uses the first row.
static func base_swing(players: int) -> int:
	var rows: Array = values()["swing"]
	for row in rows:
		var label: String = row[0]
		var swing: int = int(row[1])
		if label.ends_with("+"):
			if players >= int(label.trim_suffix("+")):
				return swing
		elif "–" in label:
			var bounds: PackedStringArray = label.split("–")
			if players >= int(bounds[0]) and players <= int(bounds[1]):
				return swing
		elif players == int(label):
			return swing
	return int(rows[0][1])
