class_name Corruption

# Corruption markers (handbook glossary). A card can put a marker on a player. There are corruptionTokens (15)
# in the box, and a marker is only given if one is left. On the player's corruption.limit-th marker (the third):
#   - their roles are FROZEN: they keep the cards but have no powers, no role income and no coup (like CANCELLED),
#   - they can't draw a Settlement card (a good vote moves their popularity but gives no card),
#   - they lose corruption.pop popularity (30), a drop of the base that is remembered.
# It lifts one of two ways:
#   - they pay corruption.fine (200) to the treasury, from cash, with { "type": "pay_fine" }: the roles come back
#     and the popularity drop is reversed (as far as the track allows), the markers go back in the box,
#   - or corruption.wait (3) rounds pass: the freeze lifts, the roles are gone for good (the cards go back in the box),
#     the popularity drop stays and the markers go back in the box.
# A frozen player takes no more markers. (Assumed: the round the freeze happens in counts as the first of the
# waiting rounds, as sickness does.)
#
# Like Roles and Sickness, the helpers (give, end_of_round, release) log nothing: the caller logs the events they
# return. The one command, pay_fine, logs its own.

const GameStateScript = preload("res://scripts/game_state.gd")
const GameDataScript = preload("res://scripts/game_data.gd")
const DebtScript = preload("res://scripts/debt.gd")
const PopularityScript = preload("res://scripts/popularity.gd")
const RolesScript = preload("res://scripts/roles.gd")
const EventsScript = preload("res://scripts/events.gd")


static func limit() -> int:
	return GameDataScript.get_nested_int("corruption", "limit")


static func held(state: GameStateScript, player_id: int) -> int:
	return int(state.markers.get(player_id, 0))


static func is_frozen(state: GameStateScript, player_id: int) -> bool:
	return state.frozen.has(player_id)


# Markers still in the box.
static func supply(state: GameStateScript) -> int:
	var out: int = 0
	for id in state.markers:
		out += int(state.markers[id])
	return int(GameDataScript.values()["components"]["corruptionTokens"]) - out


# Put a marker on the player. Returns the events (not yet logged); a marker that can't be given is said so.
static func give(state: GameStateScript, player_id: int) -> Array:
	if not player_id in state.player_ids or state.eliminated.get(player_id, false):
		return []
	if is_frozen(state, player_id):
		return [EventsScript.make("marker_refused", {"player": player_id, "reason": "already frozen"})]
	if supply(state) <= 0:
		return [EventsScript.make("marker_refused", {"player": player_id, "reason": "no markers left in the box"})]
	state.markers[player_id] = held(state, player_id) + 1
	var events: Array = [EventsScript.make("marker_gained", {"player": player_id, "markers": held(state, player_id)})]
	if held(state, player_id) >= limit():
		var before: int = PopularityScript.base(state, player_id)
		PopularityScript.change_base(state, player_id, -GameDataScript.get_nested_int("corruption", "pop"))
		var drop: int = before - PopularityScript.base(state, player_id)
		var wait: int = GameDataScript.get_nested_int("corruption", "wait")
		state.frozen[player_id] = {"left": wait, "drop": drop}
		events.append(EventsScript.make("player_frozen", {"player": player_id, "popularity_lost": drop, "rounds": wait, "roles": RolesScript.held(state, player_id)}))
	return events


# A round ends: the freezes count down. One that runs out takes the roles for good.
static func end_of_round(state: GameStateScript) -> Array:
	var events: Array = []
	var ids: Array = state.frozen.keys()
	ids.sort()
	for id in ids:
		state.frozen[id]["left"] = int(state.frozen[id]["left"]) - 1
		if state.frozen[id]["left"] > 0:
			continue
		state.frozen.erase(id)
		state.markers.erase(id)
		var lost: Array = RolesScript.held(state, id)
		events.append_array(RolesScript.clear(state, id))
		events.append(EventsScript.make("freeze_expired", {"player": id, "roles_lost": lost}))
	return events


# An eliminated player's markers go back in the box.
static func release(state: GameStateScript, player_id: int) -> void:
	state.markers.erase(player_id)
	state.frozen.erase(player_id)


# --- the fine ------------------------------------------------------------------------------

static func handle(state: GameStateScript, player_id: int, command: Dictionary) -> Array:
	if str(command.get("type", "")) != "pay_fine":
		return [_reject(player_id, "Unknown command.")]
	if not player_id in state.player_ids or state.eliminated.get(player_id, false):
		return [_reject(player_id, "You are not in the game.")]
	if not is_frozen(state, player_id):
		return [_reject(player_id, "You are not frozen.")]
	var fine: int = GameDataScript.get_nested_int("corruption", "fine")
	if int(state.psd.get(player_id, 0)) < fine:
		return [_reject(player_id, "The fine is %d PSD, from cash." % fine)]
	DebtScript.charge(state, player_id, DebtScript.TREASURY_ID, fine)
	var drop: int = int(state.frozen[player_id]["drop"])
	PopularityScript.change_base(state, player_id, drop)
	state.frozen.erase(player_id)
	state.markers.erase(player_id)
	var event: Dictionary = EventsScript.make("fine_paid", {"player": player_id, "fine": fine, "popularity_restored": drop})
	state.event_log.append(event)
	return [event]


static func _reject(player_id: int, reason: String) -> Dictionary:
	return EventsScript.make("rejected", {"reason": reason}, [player_id])
