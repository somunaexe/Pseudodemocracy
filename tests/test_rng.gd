extends SceneTree

const RngScript = preload("res://scripts/rng.gd")
const SerializerScript = preload("res://scripts/serializer.gd")
const GameStateScript = preload("res://scripts/game_state.gd")

var failures: int = 0


func _init() -> void:
	var s: GameStateScript = GameStateScript.new()

	# xorshift32 starting from 1 gives a known sequence (worked out independently).
	RngScript.seed_with(s, 1)
	var seen: Array = []
	for i in 5:
		seen.append(RngScript.next_raw(s))
	expect("the sequence from seed 1", seen, [270369, 67634689, 2647435461, 307599695, 2398689233])

	RngScript.seed_with(s, 0)
	expect("seed 0 would stick, so it becomes 1", s.rng_state, 1)
	RngScript.seed_with(s, 4294967296 + 7)
	expect("a seed is cut to 32 bits", s.rng_state, 7)

	# The same seed gives the same draws.
	var a: GameStateScript = GameStateScript.new()
	var b: GameStateScript = GameStateScript.new()
	RngScript.seed_with(a, 99)
	RngScript.seed_with(b, 99)
	var same: bool = true
	for i in 50:
		same = same and RngScript.below(a, 1000) == RngScript.below(b, 1000)
	expect("two games with one seed draw the same numbers", same, true)

	# The state survives a save: the game carries on with the very same numbers.
	RngScript.seed_with(a, 5)
	for i in 10:
		RngScript.below(a, 7)
	var errors: Array = []
	var restored: GameStateScript = SerializerScript.state_from_json(SerializerScript.state_to_json(a), errors)
	expect("the generator state saves and loads", errors, [])
	var continues: bool = true
	for i in 50:
		continues = continues and RngScript.below(a, 1000) == RngScript.below(restored, 1000)
	expect("a restored game keeps drawing the same numbers", continues, true)
	expect("the state always fits in a JSON number exactly", a.rng_state < 9007199254740992, true)

	# Fair: a draw of 1 in 5 should come out near 20% each.
	RngScript.seed_with(s, 12345)
	var counts: Array = [0, 0, 0, 0, 0]
	for i in 10000:
		counts[RngScript.below(s, 5)] += 1
	var fair: bool = true
	for count in counts:
		fair = fair and count > 1800 and count < 2200
	expect("10000 draws of 5 are all within 10%% of even: %s" % str(counts), fair, true)

	var in_range: bool = true
	for i in 1000:
		var x: int = RngScript.below(s, 3)
		in_range = in_range and x >= 0 and x < 3
	expect("draws stay in range", in_range, true)
	expect("n = 1 always gives 0", RngScript.below(s, 1), 0)
	expect("pick takes an item", RngScript.pick(s, ["a"]), "a")

	RngScript.seed_from_clock(s)
	expect("a clock seed is never 0", s.rng_state != 0, true)

	print("%d failure(s)" % failures)
	quit(1 if failures > 0 else 0)


func expect(label: String, actual: Variant, wanted: Variant) -> void:
	var ok: bool = typeof(actual) == typeof(wanted) and actual == wanted
	if not ok:
		failures += 1
	print(("PASS " if ok else "FAIL ") + label + " -> " + str(actual).left(80))
