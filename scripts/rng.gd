class_name Rng

# A small random number generator for the server (xorshift32). Its whole state is ONE whole
# number, GameState.rng_state, so it is saved and restored exactly (JSON would round a bigger
# number), and a game replays the same way from the same seed, which is what tests need.
#
# rng_state must never reach a client: anyone who knew it could predict every draw.

const GameStateScript = preload("res://scripts/game_state.gd")

const MASK := 0xFFFFFFFF
const RANGE := 4294967296   # 2^32


static func seed_with(state: GameStateScript, value: int) -> void:
	var seed_value: int = value & MASK
	state.rng_state = seed_value if seed_value != 0 else 1   # the generator can't start from 0


# For a real game: start from the clock.
static func seed_from_clock(state: GameStateScript) -> void:
	seed_with(state, int(Time.get_unix_time_from_system() * 1000.0) ^ Time.get_ticks_usec())


static func next_raw(state: GameStateScript) -> int:
	var x: int = state.rng_state
	x ^= (x << 13) & MASK
	x ^= x >> 17
	x ^= (x << 5) & MASK
	state.rng_state = x
	return x


# A whole number from 0 to n - 1, every value equally likely (no modulo bias).
static func below(state: GameStateScript, n: int) -> int:
	assert(n > 0, "Rng.below needs a positive n")
	var limit: int = RANGE - (RANGE % n)
	var x: int = next_raw(state)
	while x >= limit:
		x = next_raw(state)
	return x % n


static func pick(state: GameStateScript, items: Array) -> Variant:
	return items[below(state, items.size())]
