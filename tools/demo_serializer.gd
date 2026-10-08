extends SceneTree

# Run:  godot --headless --script tools/demo_serializer.gd
# Shows why the game needs a Serializer, using a tiny piece of game state.

const SerializerScript = preload("res://scripts/serializer.gd")


func _init() -> void:
	# Player 1 has 900 PSD, player 2 has 1050. This is how the game holds it in memory.
	var psd := {1: 900, 2: 1050}
	print("1) In memory:      ", psd)
	print("   The key is a:   ", type_string(typeof(psd.keys()[0])), "    psd[1] = ", psd[1])
	print()

	# The obvious way to turn it into text and back:
	var naive_text := JSON.stringify(psd)
	var naive_back = JSON.parse_string(naive_text)
	var naive_key = naive_back.keys()[0]
	print("2) Plain JSON text:  ", naive_text)
	print("   Loaded back:      ", naive_back)
	print("   The key is now a: ", type_string(typeof(naive_key)), ", the value is a ", type_string(typeof(naive_back[naive_key])))
	print("   Does psd[1] still work?  ", naive_back.has(1), "   (the game would crash or give 0)")
	print()

	# With the Serializer:
	var errors: Array = []
	var text := SerializerScript.to_json(psd)
	var back = SerializerScript.from_json(text, errors)
	var key = back.keys()[0]
	print("3) Serializer text:  ", text)
	print("   Loaded back:      ", back)
	print("   The key is a:     ", type_string(typeof(key)), ", the value is a ", type_string(typeof(back[key])))
	print("   Does psd[1] work? ", back.has(1), "  ->  ", back.get(1))
	print()

	# A command arriving from a phone. Phones send text, and numbers arrive as decimals.
	var from_phone := "{\"type\": \"propose\", \"window\": 0, \"article_id\": 2}"
	var plain = JSON.parse_string(from_phone)
	var command := SerializerScript.parse_command(from_phone, errors)
	print("4) A phone sends:    ", from_phone)
	print("   Plain JSON gives: window is a ", type_string(typeof(plain["window"])), " (", plain["window"], ")")
	print("   parse_command:    window is a ", type_string(typeof(command["window"])), " (", command["window"], ")")
	print()

	# Rubbish from a phone must not crash the server.
	var bad_errors: Array = []
	var nothing := SerializerScript.parse_command("hello there", bad_errors)
	print("5) A phone sends:    hello there")
	print("   parse_command:    ", nothing, "   errors: ", bad_errors)
	quit()
