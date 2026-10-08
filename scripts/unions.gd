class_name Unions

# Activists (peaceful) form UNIONS, led by a Unionizer. Agberos (violent) form MOBS, led by a Capon (handbook
# Part 6, Activists & Agberos, Articles 7 to 17). One module and one table (state.unions) serve both, so the
# code says "union" for either; the words players read use the right name (word() and head() below), and
# events carry the group's type so the screen can do the same.
#
# A group is formed by playing a union or mob card (a Settlement card kept in the hand). The player who plays
# it is its leader and first member: it starts at 1, "recruiting".
#
# state.unions: union id -> { "type": UnionType, "owner": the Unionizer, "members": [ids, owner first],
#                              "confront_used": bool }
#
# A player is in at most one union ("can't recruit ... a member of another union", Article 8).
#
# What the leader (Unionizer or Capon) can do, only on a UNION TURN (their own turn, or the Leader's turn if the Leader is a
# member) and only if not sick (Article 9):
#   { "type": "union_recruit", "union_id": id, "target": id }   ask a player to join. "A free social ask": the
#        target must agree (union_respond), within unionInviteSeconds. The Leader and members of other unions
#        can't be recruited (Article 8).
#   { "type": "union_kick", "union_id": id, "target": id }      "just by saying so" (Article 10)
# Anyone asked answers:
#   { "type": "union_respond", "accept": bool }
# A member (not the Unionizer) may leave on their own turn (Article 10):
#   { "type": "union_leave" }
# The Unionizer may disperse the union whenever they like (the members "choose to disperse"):
#   { "type": "union_disperse", "union_id": id }
#
# A union that drops to unionDissolveAt (1) members dissolves and its card is lost (Article 11). An AGBERO MOB
# DISPERSES THE INSTANT IT ACTS (Article 13); an Activist union lingers (Article 12). After a mob disperses, the
# Agberos in it who still hold an Agbero role card may form a new mob straight away (union_reform).
#   { "type": "union_reform" }
# Not built: Command Performance (Articles 16 and 17), and how gains and losses are shared (Articles 12 and 13).
#
# Like Roles, the low-level functions (found, remove_member, disperse) log nothing and return their events; the
# commands log their own.

const GameStateScript = preload("res://scripts/game_state.gd")
const GameDataScript = preload("res://scripts/game_data.gd")
const LawScript = preload("res://scripts/law.gd")
const RolesScript = preload("res://scripts/roles.gd")
const RivalsScript = preload("res://scripts/rivals.gd")
const RngScript = preload("res://scripts/rng.gd")
const EventsScript = preload("res://scripts/events.gd")

const TYPES := {"activist": GameStateScript.UnionType.ACTIVIST, "agbero": GameStateScript.UnionType.AGBERO}


# The word for this group: Activists form a union, Agberos a mob.
static func word(union: Dictionary) -> String:
	return "mob" if union["type"] == GameStateScript.UnionType.AGBERO else "union"


# What its leader is called: a Unionizer leads a union, a Capon a mob.
static func head(union: Dictionary) -> String:
	return "Capon" if union["type"] == GameStateScript.UnionType.AGBERO else "Unionizer"


# --- who is in what ----------------------------------------------------------------------

# The union this player belongs to (as Unionizer or member), or -1.
static func union_of(state: GameStateScript, player_id: int) -> int:
	for id in state.unions:
		if player_id in state.unions[id]["members"]:
			return id
	return -1


# Is it a union turn for this union: the Unionizer's own turn, or the Leader's if the Leader is a member?
static func on_union_turn(state: GameStateScript, union: Dictionary) -> bool:
	var waiting: Array = state.term.get("waiting", [])
	if state.term.get("phase", GameStateScript.TermPhase.NONE) != GameStateScript.TermPhase.TURNS or waiting.is_empty():
		return false
	var now: int = waiting[0]
	return now == union["owner"] or (now == state.leader_id and state.leader_id in union["members"])


# --- founding ----------------------------------------------------------------------------

# Why this player can't found a union now, or "".
static func problem_founding(state: GameStateScript, player_id: int) -> String:
	if not player_id in state.player_ids or state.eliminated.get(player_id, false):
		return "You are not in the game."
	if union_of(state, player_id) != -1:
		return "You are already in a union or mob."
	return ""


# Found a union of this type ("activist" or "agbero"). The caller checks problem_founding first.
static func found(state: GameStateScript, player_id: int, type_name: String) -> Array:
	assert(type_name in TYPES, "no such union type '%s'" % type_name)
	assert(problem_founding(state, player_id) == "", "found() needs a player who can found a union")
	var id: int = 1
	for existing in state.unions:
		id = maxi(id, int(existing) + 1)
	state.unions[id] = {"type": TYPES[type_name], "owner": player_id, "members": [player_id], "confront_used": false}
	state.reform.erase(player_id)   # a new mob uses up the right to re-form
	return [EventsScript.make("union_founded", {"union_id": id, "type": state.unions[id]["type"], "unionizer": player_id})]


# --- leaving, dissolving, dispersing -----------------------------------------------------

# Take the player out of the union. The union dissolves if it is left with too few members (Article 11), or
# if it was the Unionizer who left the game (assumed). Returns the events.
static func remove_member(state: GameStateScript, union_id: int, player_id: int, why: String) -> Array:
	var union: Dictionary = state.unions[union_id]
	union["members"].erase(player_id)
	var events: Array = [EventsScript.make("union_left", {"union_id": union_id, "player": player_id, "why": why})]
	if union["members"].size() <= LawScript.get_int(state, "unionDissolveAt") or union["owner"] == player_id:
		state.unions.erase(union_id)
		_drop_invites(state, union_id)
		events.append(EventsScript.make("union_dissolved", {"union_id": union_id}))
	return events


# The union disperses (the Unionizer chose to, or a mob has acted). Agberos in a dispersed mob who still hold an
# Agbero role card may form a new one at once.
static func disperse(state: GameStateScript, union_id: int, why: String) -> Array:
	var union: Dictionary = state.unions[union_id]
	state.unions.erase(union_id)
	_drop_invites(state, union_id)
	var may_reform: Array = []
	if union["type"] == GameStateScript.UnionType.AGBERO:
		for member in union["members"]:
			if RolesScript.has(state, member, "Agbero") and not state.eliminated.get(member, false):
				state.reform[member] = true
				may_reform.append(member)
	return [EventsScript.make("union_dispersed", {"union_id": union_id, "why": why, "members": union["members"].duplicate(), "may_reform": may_reform})]


static func _drop_invites(state: GameStateScript, union_id: int) -> void:
	for target in state.union_invites.keys():
		if state.union_invites[target]["union_id"] == union_id:
			state.union_invites.erase(target)


# --- commands ----------------------------------------------------------------------------

static func handle(state: GameStateScript, player_id: int, command: Dictionary) -> Array:
	match str(command.get("type", "")):
		"union_recruit":
			return _recruit(state, player_id, command)
		"union_respond":
			return _respond(state, player_id, command)
		"union_leave":
			return _leave(state, player_id)
		"union_kick":
			return _kick(state, player_id, command)
		"union_disperse":
			return _disperse(state, player_id, command)
		"union_reform":
			return _reform(state, player_id)
	return [_reject(player_id, "Unknown command.")]


# The union this Unionizer commands, or a reason they can't (as a rejection reason).
static func _own_union(state: GameStateScript, player_id: int, command: Dictionary) -> Array:
	var union_id = command.get("union_id", null)
	if typeof(union_id) != TYPE_INT or not state.unions.has(union_id):
		return [-1, "There is no such union or mob."]
	if state.unions[union_id]["owner"] != player_id:
		return [-1, "Only the %s decides for a %s." % [head(state.unions[union_id]), word(state.unions[union_id])]]
	if state.sick.get(player_id, false):
		return [-1, "Sick players can't use pledges."]
	return [union_id, ""]


static func _recruit(state: GameStateScript, owner: int, command: Dictionary) -> Array:
	var own: Array = _own_union(state, owner, command)
	if own[1] != "":
		return [_reject(owner, own[1])]
	var union_id: int = own[0]
	if not on_union_turn(state, state.unions[union_id]):
		return [_reject(owner, "A %s can only act on the %s's turn, or the Leader's if the Leader is a member." % [word(state.unions[union_id]), head(state.unions[union_id])])]
	var target = command.get("target", null)
	if typeof(target) != TYPE_INT or not target in state.player_ids or state.eliminated.get(target, false):
		return [_reject(owner, "Choose a player who is in the game.")]
	if target == owner:
		return [_reject(owner, "You are already in the %s." % word(state.unions[union_id]))]
	var problem: String = _problem_recruiting(state, target, state.unions[union_id])
	if problem != "":
		return [_reject(owner, problem)]
	return [_log(state, "union_invited", _send_invite(state, union_id, owner, target))]


# The invitation itself: the player has unionInviteSeconds to answer. Returns the data of the event.
static func _send_invite(state: GameStateScript, union_id: int, owner: int, target: int) -> Dictionary:
	var seconds: int = GameDataScript.get_int("unionInviteSeconds")
	var ends_at: int = state.clock_ms + seconds * 1000
	state.union_invites[target] = {"union_id": union_id, "deadline": ends_at}
	return {"union_id": union_id, "unionizer": owner, "target": target, "seconds": seconds, "ends_at_ms": ends_at}


# "A rival union wants your backing" (a Performance card): the Unionizer or Capon of a union that is not the player's pitches
# them for unionInviteSeconds (30) and they decide, by answering the invitation (union_respond). The union is one led by one
# of the player's rivals if there is one, otherwise any other union (chosen at random). Nothing happens, and it is said, if
# there is no such union or the player can't join one (the Leader and the Vice can't, nor can a member of a union).
# Returns the events (not yet logged).
static func pitch(state: GameStateScript, target: int) -> Array:
	var mine: int = union_of(state, target)
	var rival_unions: Array = []
	var other_unions: Array = []
	var ids: Array = state.unions.keys()
	ids.sort()
	for union_id in ids:
		var union: Dictionary = state.unions[union_id]
		if union_id == mine or state.eliminated.get(union["owner"], false):
			continue
		other_unions.append(union_id)
		if RivalsScript.is_rival(state, target, union["owner"]):
			rival_unions.append(union_id)
	var pool: Array = rival_unions if not rival_unions.is_empty() else other_unions
	if pool.is_empty():
		return [EventsScript.make("union_pitch_unavailable", {"player": target, "reason": "there is no other union or mob"})]
	var picked: int = RngScript.pick(state, pool)
	var problem: String = _problem_recruiting(state, target, state.unions[picked])
	if mine != -1:
		problem = "they are already in a union or mob"
	if problem != "":
		return [EventsScript.make("union_pitch_unavailable", {"player": target, "reason": problem})]
	return [EventsScript.make("union_pitched", _send_invite(state, picked, state.unions[picked]["owner"], target))]


# Why this player can't be recruited, or "" (Article 8).
static func _problem_recruiting(state: GameStateScript, target: int, union: Dictionary) -> String:
	if target == state.leader_id:
		return "A %s can't recruit the Leader." % word(union)
	if target == state.vice_id:
		return "A %s can't recruit the Vice." % word(union)
	if union_of(state, target) != -1:
		return "A %s can't recruit a member of another union or mob." % word(union)
	if state.union_invites.has(target):
		return "That player has already been asked to join a union or mob."
	return ""


static func _respond(state: GameStateScript, player_id: int, command: Dictionary) -> Array:
	if not state.union_invites.has(player_id):
		return [_reject(player_id, "Nobody has asked you to join a union or mob.")]
	var accept = command.get("accept", null)
	if typeof(accept) != TYPE_BOOL:
		return [_reject(player_id, "Accept or refuse.")]
	var invite: Dictionary = state.union_invites[player_id]
	state.union_invites.erase(player_id)
	var union_id: int = invite["union_id"]
	if not accept:
		return [_log(state, "union_invitation_refused", {"union_id": union_id, "player": player_id})]
	if not state.unions.has(union_id):
		return [_log(state, "union_invitation_void", {"union_id": union_id, "player": player_id, "reason": "the union or mob no longer exists"})]
	if player_id == state.leader_id or player_id == state.vice_id or union_of(state, player_id) != -1:
		return [_log(state, "union_invitation_void", {"union_id": union_id, "player": player_id, "reason": "they can no longer join"})]
	state.unions[union_id]["members"].append(player_id)
	return [_log(state, "union_joined", {"union_id": union_id, "player": player_id})]


static func _leave(state: GameStateScript, player_id: int) -> Array:
	var union_id: int = union_of(state, player_id)
	if union_id == -1:
		return [_reject(player_id, "You are not in a union or mob.")]
	if state.unions[union_id]["owner"] == player_id:
		return [_reject(player_id, "The %s disperses the %s instead of leaving it." % [head(state.unions[union_id]), word(state.unions[union_id])])]
	var waiting: Array = state.term.get("waiting", [])
	if state.term.get("phase", GameStateScript.TermPhase.NONE) != GameStateScript.TermPhase.TURNS or waiting.is_empty() or waiting[0] != player_id:
		return [_reject(player_id, "A member may leave on their own turn.")]
	return _log_all(state, remove_member(state, union_id, player_id, "left"))


static func _kick(state: GameStateScript, owner: int, command: Dictionary) -> Array:
	var own: Array = _own_union(state, owner, command)
	if own[1] != "":
		return [_reject(owner, own[1])]
	var union_id: int = own[0]
	if not on_union_turn(state, state.unions[union_id]):
		return [_reject(owner, "A %s can only act on the %s's turn, or the Leader's if the Leader is a member." % [word(state.unions[union_id]), head(state.unions[union_id])])]
	var target = command.get("target", null)
	if typeof(target) != TYPE_INT or not target in state.unions[union_id]["members"]:
		return [_reject(owner, "That player is not in your %s." % word(state.unions[union_id]))]
	if target == owner:
		return [_reject(owner, "The %s can't be kicked out of their own %s." % [head(state.unions[union_id]), word(state.unions[union_id])])]
	return _log_all(state, remove_member(state, union_id, target, "kicked"))


static func _disperse(state: GameStateScript, owner: int, command: Dictionary) -> Array:
	var own: Array = _own_union(state, owner, command)
	if own[1] != "":
		return [_reject(owner, own[1])]
	return _log_all(state, disperse(state, own[0], "the %s dispersed it" % head(state.unions[own[0]])))


# An Agbero whose mob dispersed forms a new one straight away if they still hold an Agbero role card.
static func _reform(state: GameStateScript, player_id: int) -> Array:
	if not state.reform.get(player_id, false):
		return [_reject(player_id, "You have no mob to re-form.")]
	if not RolesScript.has(state, player_id, "Agbero"):
		state.reform.erase(player_id)
		return [_reject(player_id, "You no longer hold an Agbero role card.")]
	var problem: String = problem_founding(state, player_id)
	if problem != "":
		return [_reject(player_id, problem)]
	return _log_all(state, found(state, player_id, "agbero"))


# --- the automatic steps -----------------------------------------------------------------

# An invitation nobody answered in time is refused. (A mob that dispersed keeps its right to re-form until used.)
static func step(state: GameStateScript) -> Array:
	var events: Array = []
	var asked: Array = state.union_invites.keys()
	asked.sort()
	for target in asked:
		var invite: Dictionary = state.union_invites[target]
		if state.clock_ms >= int(invite["deadline"]):
			state.union_invites.erase(target)
			events.append(_log(state, "union_invitation_expired", {"union_id": invite["union_id"], "player": target}))
	return events


# --- helpers -----------------------------------------------------------------------------

static func _log_all(state: GameStateScript, events: Array) -> Array:
	for event in events:
		state.event_log.append(event)
	return events


static func _log(state: GameStateScript, type: String, data: Dictionary) -> Dictionary:
	var event: Dictionary = EventsScript.make(type, data)
	state.event_log.append(event)
	return event


static func _reject(player_id: int, reason: String) -> Dictionary:
	return EventsScript.make("rejected", {"reason": reason}, [player_id])
