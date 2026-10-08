class_name Peeks

# Free peeks, started by cards (handbook: "they may check your Doctor bead, role draw, or coup-card status once, free,
# without warning"; "a rival gets to check your coup-card status for free, once"; "a Secret Agent owes you a favor").
#
# A PERMIT lets its holder check one thing about one player, once, for nothing (state.peeks, SERVER-ONLY: if the list
# were public, a permit that disappears would be a warning that it was used).
#   { "holder": id, "target": id, "kinds": ["coup", "bead"], "round_only": bool }
#   coup   the target's coup-card status: for each role card they hold, whether it carries a coup sticker
#   bead   the bead in the Doctor's hand while the target (as the Doctor) is handing over a cure
# ("Role draw" in the card text is read as the same as coup-card status: roles are public, so the one secret about a role
# card is its sticker. To confirm with the designer.)
# round_only permits end with the round ("for the rest of your term"); the others last until used or until a player in
# them leaves the game. One check uses the permit up, and only a check that gives an answer does (no cure under way = no
# bead, and the permit stays).
#
#   { "type": "peek", "target": id, "kind": "coup" | "bead" }
# The answer goes to the holder alone (the target is not told). The permit itself is announced when it is granted: the
# card is read out to the table anyway.
#
# The Secret Agent's FAVOR (a Settlement card) is the same report made at once, without a permit.
#
# Like Roles and Sickness the helpers log nothing; the command logs its own event.

const GameStateScript = preload("res://scripts/game_state.gd")
const RolesScript = preload("res://scripts/roles.gd")
const RivalsScript = preload("res://scripts/rivals.gd")
const RngScript = preload("res://scripts/rng.gd")
const EventsScript = preload("res://scripts/events.gd")

const KINDS := ["coup", "bead"]


static func grant(state: GameStateScript, holder: int, target: int, kinds: Array, round_only: bool) -> Array:
	if holder == target or holder == 0:
		return []
	state.peeks.append({"holder": holder, "target": target, "kinds": kinds.duplicate(), "round_only": round_only})
	return [EventsScript.make("peek_granted", {"holder": holder, "target": target, "kinds": kinds.duplicate(), "round_only": round_only})]


# "A rival gets to check your coup-card status": one of the players linked to the drawer by a rivalry, either way, chosen
# at random. Nobody if there is no such player.
static func grant_to_a_rival(state: GameStateScript, target: int, kinds: Array) -> Array:
	var linked: Array = []
	for id in state.player_ids:
		if id == target or state.eliminated.get(id, false):
			continue
		if RivalsScript.is_rival(state, target, id) or RivalsScript.is_rival(state, id, target):
			linked.append(id)
	if linked.is_empty():
		return [EventsScript.make("peek_unavailable", {"target": target, "reason": "the drawer has no rival"})]
	return grant(state, RngScript.pick(state, linked), target, kinds, false)


# The cards of the player and whether each has a coup sticker.
static func cards_of(state: GameStateScript, target: int) -> Array:
	var result: Array = []
	for role in RolesScript.held(state, target):
		result.append({"role": role, "sticker": RolesScript.has_sticker(state, target, role)})
	return result


# The permits of one holder, for their own view.
static func permits_of(state: GameStateScript, holder: int) -> Array:
	var result: Array = []
	for permit in state.peeks:
		if permit["holder"] == holder:
			result.append({"target": permit["target"], "kinds": permit["kinds"].duplicate(), "round_only": permit["round_only"]})
	return result


static func end_of_round(state: GameStateScript) -> void:
	state.peeks = state.peeks.filter(func(permit): return not permit["round_only"])


static func remove_player(state: GameStateScript, player_id: int) -> void:
	state.peeks = state.peeks.filter(func(permit): return permit["holder"] != player_id and permit["target"] != player_id)


# --- the command -----------------------------------------------------------------------------

static func handle(state: GameStateScript, player_id: int, command: Dictionary) -> Array:
	if not player_id in state.player_ids or state.eliminated.get(player_id, false):
		return [_reject(player_id, "You are not in the game.")]
	var target = command.get("target", null)
	var kind = command.get("kind", null)
	if typeof(target) != TYPE_INT or typeof(kind) != TYPE_STRING or not kind in KINDS:
		return [_reject(player_id, "Say whose coup cards or bead to check.")]
	var index: int = -1
	for i in state.peeks.size():
		var permit: Dictionary = state.peeks[i]
		if permit["holder"] == player_id and permit["target"] == target and kind in permit["kinds"]:
			index = i
			break
	if index == -1:
		return [_reject(player_id, "You have no free check of that.")]
	var report: Dictionary = {"target": target, "kind": kind}
	if kind == "coup":
		report["cards"] = cards_of(state, target)
	else:
		var dose: Dictionary = state.dose
		if dose.is_empty() or dose["kind"] != "heal" or dose["doctor"] != target:
			return [_reject(player_id, "That player is not handing over a bead right now.")]
		report["patient"] = dose["patient"]
		report["bead"] = "red" if state.dose_secret.get("poison", false) else "blue"
	state.peeks.remove_at(index)
	var event: Dictionary = EventsScript.make("peek_report", report, [player_id])
	state.event_log.append(event)
	return [event]


static func _reject(player_id: int, reason: String) -> Dictionary:
	return EventsScript.make("rejected", {"reason": reason}, [player_id])
