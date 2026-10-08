class_name Rivals

# Rivals (handbook glossary): "A label placed on a player by a specific card. It carries no rules or restrictions of
# its own; it only matters when another card says 'choose a rival' or similar, in which case it must target someone
# already carrying the label (if you have one)."
#
# A rival is one player's label on another (state.rivals: owner -> list of players), public, and it does not have to be
# mutual. It lasts until the rival leaves the game. A card that says "choose a rival" offers your rivals if you have
# any, otherwise any other player, and the one you choose becomes (or stays) your rival.
#
# Four small mechanics hang off it, all started by cards:
#   - a TRUCE (Settlement "You survived a vote of no confidence"): neither of the two can coup the other until the round
#     ends (truces are cleared by RoundEnd). Only a coup on the Leader is possible at all, so in practice the truce stops
#     the one of them who is not Leader from couping the other when they lead.
#   - an ACCORD (Peace Accord): for accordRounds rounds, if either is successfully couped, the other loses 10 popularity.
#   - SKIP DRAW ("Choose a Rival - they lose their next Result card draw"): their next Settlement or Scandal card is not
#     drawn; the performance and its popularity still count. Used up by the next draw that would have happened.
#   - a mob that is caught on camera disperses and its other members become the drawer's rivals (Scandal).
#
# Like Roles and Sickness, nothing here logs: every function returns its events and the caller logs them.

const GameStateScript = preload("res://scripts/game_state.gd")
const PopularityScript = preload("res://scripts/popularity.gd")
const EventsScript = preload("res://scripts/events.gd")


static func of(state: GameStateScript, owner: int) -> Array:
	return state.rivals.get(owner, []).duplicate()


static func is_rival(state: GameStateScript, owner: int, other: int) -> bool:
	return other in state.rivals.get(owner, [])


# Who a "choose a rival" card offers: the owner's rivals, or any other player if they have none.
static func candidates(state: GameStateScript, owner: int) -> Array:
	var result: Array = of(state, owner)
	if not result.is_empty():
		return result
	for id in state.player_ids:
		if id != owner and not state.eliminated.get(id, false):
			result.append(id)
	return result


# The other player becomes the owner's rival. Nothing happens if they already are.
static func name_rival(state: GameStateScript, owner: int, other: int) -> Array:
	if owner == other or is_rival(state, owner, other):
		return []
	if not state.rivals.has(owner):
		state.rivals[owner] = []
	state.rivals[owner].append(other)
	return [EventsScript.make("rival_named", {"owner": owner, "rival": other})]


# --- truce, accord, skipped draw -----------------------------------------------------------

static func truce(state: GameStateScript, a: int, b: int) -> Array:
	if not in_truce(state, a, b):
		state.truces.append([a, b])
	return [EventsScript.make("truce_made", {"a": a, "b": b})]


static func in_truce(state: GameStateScript, a: int, b: int) -> bool:
	for pair in state.truces:
		if (pair[0] == a and pair[1] == b) or (pair[0] == b and pair[1] == a):
			return true
	return false


static func accord(state: GameStateScript, a: int, b: int, rounds: int, loss: int) -> Array:
	state.accords.append({"a": a, "b": b, "left": rounds, "loss": loss})
	return [EventsScript.make("accord_made", {"a": a, "b": b, "rounds": rounds, "loss": loss})]


# The Leader has been couped: whoever has an accord with them loses its popularity cost.
static func accord_penalties(state: GameStateScript, couped: int) -> Array:
	var events: Array = []
	for entry in state.accords:
		var partner: int = -1
		if entry["a"] == couped:
			partner = entry["b"]
		elif entry["b"] == couped:
			partner = entry["a"]
		if partner == -1 or state.eliminated.get(partner, false):
			continue
		var before: int = PopularityScript.effective(state, partner)
		PopularityScript.change_base(state, partner, -int(entry["loss"]))
		events.append(EventsScript.make("accord_penalty", {"couped": couped, "player": partner, "popularity": PopularityScript.effective(state, partner) - before}))
	return events


static func skip_next_draw(state: GameStateScript, player_id: int) -> Array:
	state.skip_draw[player_id] = true
	return [EventsScript.make("draw_skipped_next", {"player": player_id})]


# --- time and leaving ----------------------------------------------------------------------

# A round ends: truces end, accords have one round fewer.
static func end_of_round(state: GameStateScript) -> Array:
	var events: Array = []
	state.truces = []
	var kept: Array = []
	for entry in state.accords:
		entry["left"] = int(entry["left"]) - 1
		if entry["left"] > 0:
			kept.append(entry)
		else:
			events.append(EventsScript.make("accord_ended", {"a": entry["a"], "b": entry["b"]}))
	state.accords = kept
	return events


# A player leaves the game: nobody is their rival or has them as one, and their pacts end.
static func remove_player(state: GameStateScript, player_id: int) -> void:
	state.rivals.erase(player_id)
	for owner in state.rivals.keys():
		state.rivals[owner].erase(player_id)
		if state.rivals[owner].is_empty():
			state.rivals.erase(owner)
	state.truces = state.truces.filter(func(pair): return pair[0] != player_id and pair[1] != player_id)
	state.accords = state.accords.filter(func(entry): return entry["a"] != player_id and entry["b"] != player_id)
	state.skip_draw.erase(player_id)
