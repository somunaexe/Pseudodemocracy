class_name Seats

# Who sits where. The players sit round the table in id order (the order of state.player_ids); eliminated players are skipped. "Left" is
# the next seat in that order, "right" the one before. Used by cards about neighbours ("the player 2 seats to your left", "the player
# sitting opposite you").

const GameStateScript = preload("res://scripts/game_state.gd")


static func active(state: GameStateScript) -> Array:
	return state.player_ids.filter(func(id): return not state.eliminated.get(id, false))


# The player `offset` seats to the left (negative: to the right). 0 if the player isn't seated or there is nobody else.
static func neighbour(state: GameStateScript, player_id: int, offset: int) -> int:
	var seats: Array = active(state)
	var at: int = seats.find(player_id)
	if at == -1 or seats.size() < 2:
		return 0
	var found: int = seats[posmod(at + offset, seats.size())]
	return 0 if found == player_id else found


# The player opposite: half the table away (rounded down).
static func opposite(state: GameStateScript, player_id: int) -> int:
	var seats: Array = active(state)
	return neighbour(state, player_id, seats.size() / 2)
