class_name Serializer

# Turns game data into JSON text and back, exactly. Three things JSON gets wrong by default:
#  1. Dictionary keys become text, so {1: "x"} comes back as {"1": "x"}. Dictionaries with
#     any non-text key are written as {"$pairs": [[key, value], ...]} so keys keep their type.
#  2. Every number comes back as a float. Whole numbers are turned back into ints on loading
#     (the game state holds no real fractions).
#  3. Anything from a client is untrusted: size, depth and shape are checked.
#
# Errors never stop the program: functions that can fail take an `errors` Array and add
# messages to it. If it is still empty afterwards, the result is good.
#
# state_to_json writes the WHOLE state, including secrets (sealed votes). It is for the
# server's own saves only. Never send it to a client.

const GameStateScript = preload("res://scripts/game_state.gd")

# Bump this whenever GameState fields or enum values change meaning, so an old save is
# refused instead of being silently misread.
const SCHEMA_VERSION := 25   # 2: added wills; 3: added nepo; 4: added election and rng_state; 5: added term and game_over; 6: added last_turn_player and leader_goes_first; 7: added levy_band; 8: added clock_ms and decks; 9: added roles; 10: added sick_left, sick_original and immune_left; 11: added dose, dose_secret and doctor_used; 12: added will_offers; 13: added role_cards and agent_used; 14: added choice and hands; 15: added union_invites and reform; 16: added genders; 17: added command; 18: added agent_offers; 19: added coup_ban; 20: added markers and frozen; 21: added rivals, truces, accords and skip_draw; 22: added loyalists; 23: added vice_id, vice_type and vice_windows_used; 24: added effect_round; 25: the Vice has no card or windows of their own (removed vice_type and vice_windows_used), added amend_offer
const PAIRS_KEY := "$pairs"
const MAX_DEPTH := 32
const MAX_COMMAND_BYTES := 65536


# --- values -------------------------------------------------------------------------------

static func encode(value: Variant) -> Variant:
	match typeof(value):
		TYPE_BOOL, TYPE_INT, TYPE_STRING:
			return value
		TYPE_ARRAY:
			var items: Array = []
			for item in value:
				items.append(encode(item))
			return items
		TYPE_DICTIONARY:
			return _encode_dictionary(value)
	assert(false, "Serializer can't encode type %d (state holds only bool, int, String, Array, Dictionary)" % typeof(value))
	return null


static func _encode_dictionary(value: Dictionary) -> Dictionary:
	var plain: bool = true
	for key in value:
		if typeof(key) != TYPE_STRING or key == PAIRS_KEY:
			plain = false
			break
	if plain:
		var out: Dictionary = {}
		for key in value:
			out[key] = encode(value[key])
		return out
	var pairs: Array = []
	for key in value:
		pairs.append([encode(key), encode(value[key])])
	return {PAIRS_KEY: pairs}


static func decode(value: Variant, errors: Array, depth: int = 0) -> Variant:
	if depth > MAX_DEPTH:
		errors.append("data is nested too deeply")
		return null
	match typeof(value):
		TYPE_FLOAT:
			if value == floorf(value) and absf(value) < 9.0e15:
				return int(value)
			return value
		TYPE_ARRAY:
			var items: Array = []
			for item in value:
				items.append(decode(item, errors, depth + 1))
			return items
		TYPE_DICTIONARY:
			if value.size() == 1 and value.has(PAIRS_KEY):
				return _decode_pairs(value[PAIRS_KEY], errors, depth)
			var out: Dictionary = {}
			for key in value:
				out[key] = decode(value[key], errors, depth + 1)
			return out
	return value


static func _decode_pairs(pairs: Variant, errors: Array, depth: int) -> Dictionary:
	var out: Dictionary = {}
	if typeof(pairs) != TYPE_ARRAY:
		errors.append("'%s' must hold a list of [key, value] pairs" % PAIRS_KEY)
		return out
	for pair in pairs:
		if typeof(pair) != TYPE_ARRAY or pair.size() != 2:
			errors.append("every entry in '%s' must be a [key, value] pair" % PAIRS_KEY)
			return {}
		var key = decode(pair[0], errors, depth + 1)
		if typeof(key) == TYPE_ARRAY or typeof(key) == TYPE_DICTIONARY or key == null:
			errors.append("a dictionary key must be a number, text or bool")
			return {}
		out[key] = decode(pair[1], errors, depth + 1)
	return out


static func to_json(value: Variant) -> String:
	return JSON.stringify(encode(value))   # keys are sorted, so the text is stable


static func from_json(text: String, errors: Array) -> Variant:
	var json: JSON = JSON.new()
	if json.parse(text) != OK:
		errors.append("not valid JSON: " + json.get_error_message())
		return null
	return decode(json.data, errors)


# --- the game state (server-side saves) -------------------------------------------------

# Every variable declared in GameState, found by asking Godot, so a field added later
# is saved automatically and cannot be forgotten.
static func state_fields(state: GameStateScript) -> Array:
	var names: Array = []
	for prop in state.get_property_list():
		if prop["usage"] & PROPERTY_USAGE_SCRIPT_VARIABLE:
			names.append(prop["name"])
	names.sort()
	return names


static func state_to_json(state: GameStateScript) -> String:
	var fields: Dictionary = {}
	for name in state_fields(state):
		fields[name] = state.get(name)
	return to_json({"version": SCHEMA_VERSION, "state": fields})


# Returns the restored state, or null (with errors filled in) if the text is unusable.
static func state_from_json(text: String, errors: Array) -> GameStateScript:
	var data = from_json(text, errors)
	if not errors.is_empty():
		return null
	if typeof(data) != TYPE_DICTIONARY or not data.has("version") or typeof(data.get("state")) != TYPE_DICTIONARY:
		errors.append("this is not a saved game")
		return null
	if data["version"] != SCHEMA_VERSION:
		errors.append("saved with schema version %s, this build reads version %d" % [str(data["version"]), SCHEMA_VERSION])
		return null
	var state: GameStateScript = GameStateScript.new()
	var saved: Dictionary = data["state"]
	var fields: Array = state_fields(state)
	for name in saved:
		if not name in fields:
			errors.append("unknown field '%s'" % name)
	for name in fields:
		if not saved.has(name):
			errors.append("missing field '%s'" % name)
		elif typeof(saved[name]) != typeof(state.get(name)):
			errors.append("field '%s' has the wrong type" % name)
		else:
			state.set(name, saved[name])
	if not errors.is_empty():
		return null
	return state


# --- commands from clients (untrusted) -------------------------------------------------

# Turns the text a client sent into a command Dictionary, with whole numbers as ints.
# Returns {} (with errors filled in) if it isn't a well-formed command. Whether the command
# is allowed is the job of AmendmentFlow.handle, not of this function.
static func parse_command(text: String, errors: Array) -> Dictionary:
	if text.to_utf8_buffer().size() > MAX_COMMAND_BYTES:
		errors.append("command is too large")
		return {}
	var value = from_json(text, errors)
	if not errors.is_empty():
		return {}
	if typeof(value) != TYPE_DICTIONARY or typeof(value.get("type")) != TYPE_STRING:
		errors.append("a command must be an object with a text 'type'")
		return {}
	return value
