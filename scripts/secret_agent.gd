class_name SecretAgent

# The Secret Agent (handbook Part 6): "Can check one role card for coup-sticker status and will contents on
# their turn. Can check the Doctor's bead before it is handed over. Can not be caught sharing what they've
# discovered, or they lose the role. Can only use this power once per round."
#
#   { "type": "agent_check", "kind": "coup", "target": id, "role": "Doctor" }   a role card someone holds:
#                                                                                does it carry a coup sticker?
#   { "type": "agent_check", "kind": "will", "target": id }                      what is in that player's will
#   { "type": "agent_check", "kind": "bead" }                                    the bead in the Doctor's hand
#
# What the Agent finds out goes to the Agent alone, in an event nobody else is sent. One check a round, of
# any kind (the power is used once per round). A coup or will check is made on the Agent's own turn; the bead
# can be checked while a heal is being offered or while the guessing is open, by anyone but the Doctor.
# Sick, CANCELLED or eliminated Agents can't use the power (Roles.can_use_pledge).
#
# HIRING (agreed with the designer): on the Agent's own turn another player may ask them to check a card or a will of
# the asker's choosing for an agreed price. The Agent accepts or refuses (silence for agentOfferSeconds is a
# refusal). If they accept the asker pays the price at once (debt if they can't), the check is made, and both of
# them learn the result. It is the Agent's one check for the round. Only cards and wills can be hired: the bead is
# the Agent's own business.
#   { "type": "agent_hire", "agent": id, "kind": "coup" | "will", "target": id, "role": "Doctor" (for coup),
#     "price": whole number }                                                    the asker
#   { "type": "agent_respond", "client": id, "accept": bool }                    the Agent
# What is asked for stays between the two of them: the request, the refusal and the report go to them alone.
#
# "Not being caught sharing" is for the table to judge: the game cannot hear what players say.
# (Assumed: an Agent may check their own cards and their own will.)
#
# Every event this file creates is logged here, once.

const GameStateScript = preload("res://scripts/game_state.gd")
const RolesScript = preload("res://scripts/roles.gd")
const GameDataScript = preload("res://scripts/game_data.gd")
const DebtScript = preload("res://scripts/debt.gd")
const EventsScript = preload("res://scripts/events.gd")

const KINDS := ["coup", "will", "bead"]


static func handle(state: GameStateScript, player_id: int, command: Dictionary) -> Array:
	match str(command.get("type", "")):
		"agent_check":
			return _check(state, player_id, command)
		"agent_hire":
			return _hire(state, player_id, command)
		"agent_respond":
			return _respond(state, player_id, command)
	return [_reject(player_id, "Unknown command.")]


static func _check(state: GameStateScript, agent: int, command: Dictionary) -> Array:
	var power: String = RolesScript.can_use_pledge(state, agent, "Secret Agent")
	if power != "":
		return [_reject(agent, power)]
	if state.agent_used.get(agent, false):
		return [_reject(agent, "You have already used your power this round.")]
	var kind = command.get("kind", null)
	if typeof(kind) != TYPE_STRING or not kind in KINDS:
		return [_reject(agent, "Choose coup, will or bead.")]
	var report: Dictionary = {"kind": kind}
	match kind:
		"coup":
			var problem: String = _on_their_turn(state, agent)
			if problem != "":
				return [_reject(agent, problem)]
			var target = command.get("target", null)
			var role = command.get("role", null)
			if typeof(target) != TYPE_INT or not target in state.player_ids or state.eliminated.get(target, false):
				return [_reject(agent, "Choose a player who is in the game.")]
			if typeof(role) != TYPE_STRING or not RolesScript.has(state, target, role):
				return [_reject(agent, "That player doesn't hold that role.")]
			report["target"] = target
			report["role"] = role
			report["sticker"] = RolesScript.has_sticker(state, target, role)
		"will":
			var problem2: String = _on_their_turn(state, agent)
			if problem2 != "":
				return [_reject(agent, problem2)]
			var target2 = command.get("target", null)
			if typeof(target2) != TYPE_INT or not target2 in state.player_ids or state.eliminated.get(target2, false):
				return [_reject(agent, "Choose a player who is in the game.")]
			if not state.wills.has(target2):
				return [_reject(agent, "That player has no will.")]   # that a will exists is public anyway
			report["target"] = target2
			report["will"] = state.wills[target2].duplicate(true)
		"bead":
			var dose: Dictionary = state.dose
			if dose.is_empty() or dose["kind"] != "heal":
				return [_reject(agent, "No Doctor is handing over a bead.")]
			if agent == dose["doctor"]:
				return [_reject(agent, "It is your own bead.")]
			report["doctor"] = dose["doctor"]
			report["patient"] = dose["patient"]
			report["bead"] = "red" if state.dose_secret.get("poison", false) else "blue"
	state.agent_used[agent] = true
	var event: Dictionary = EventsScript.make("agent_report", report, [agent])
	state.event_log.append(event)
	return [event]


# --- hiring ------------------------------------------------------------------------------

# What a card or will check would say, or a reason it can't be made: [report, problem].
static func _report_for(state: GameStateScript, kind: String, target: Variant, role: Variant) -> Array:
	if typeof(target) != TYPE_INT or not target in state.player_ids or state.eliminated.get(target, false):
		return [{}, "Choose a player who is in the game."]
	if kind == "coup":
		if typeof(role) != TYPE_STRING or not RolesScript.has(state, target, role):
			return [{}, "That player doesn't hold that role."]
		return [{"kind": "coup", "target": target, "role": role, "sticker": RolesScript.has_sticker(state, target, role)}, ""]
	if not state.wills.has(target):
		return [{}, "That player has no will."]
	return [{"kind": "will", "target": target, "will": state.wills[target].duplicate(true)}, ""]


static func _hire(state: GameStateScript, client: int, command: Dictionary) -> Array:
	if not client in state.player_ids or state.eliminated.get(client, false):
		return [_reject(client, "You are not in the game.")]
	var agent = command.get("agent", null)
	if typeof(agent) != TYPE_INT or not agent in state.player_ids or state.eliminated.get(agent, false):
		return [_reject(client, "Choose an Agent who is in the game.")]
	if agent == client:
		return [_reject(client, "You can't hire yourself.")]
	if not RolesScript.has(state, agent, "Secret Agent"):
		return [_reject(client, "That player is not a Secret Agent.")]
	var problem: String = _on_their_turn(state, agent)
	if problem != "":
		return [_reject(client, "You can only hire an Agent on their own turn.")]
	var power: String = RolesScript.can_use_pledge(state, agent, "Secret Agent")
	if power != "":
		return [_reject(client, power)]
	if state.agent_used.get(agent, false):
		return [_reject(client, "That Agent has already used their power this round.")]
	if state.agent_offers.has(agent):
		return [_reject(client, "That Agent already has a request waiting.")]
	var kind = command.get("kind", null)
	if typeof(kind) != TYPE_STRING or not kind in ["coup", "will"]:
		return [_reject(client, "Choose coup or will.")]
	var checked: Array = _report_for(state, kind, command.get("target", null), command.get("role", null))
	if checked[1] != "":
		return [_reject(client, checked[1])]
	var maximum: int = GameDataScript.get_int("agentPriceMax")
	var price = command.get("price", null)
	if typeof(price) != TYPE_INT or price < 0 or price > maximum:
		return [_reject(client, "The price must be a whole number from 0 to %d." % maximum)]
	var seconds: int = GameDataScript.get_int("agentOfferSeconds")
	var ends_at: int = state.clock_ms + seconds * 1000
	state.agent_offers[agent] = {"client": client, "kind": kind, "target": command["target"], "role": command.get("role", ""), "price": price, "deadline": ends_at}
	return [_log(state, "agent_requested", {"client": client, "agent": agent, "kind": kind, "target": command["target"], "role": command.get("role", ""), "price": price, "seconds": seconds, "ends_at_ms": ends_at}, [client, agent])]


static func _respond(state: GameStateScript, agent: int, command: Dictionary) -> Array:
	var client = command.get("client", null)
	if typeof(client) != TYPE_INT or not state.agent_offers.has(agent) or state.agent_offers[agent]["client"] != client:
		return [_reject(agent, "There is no request waiting for you from that player.")]
	var accept = command.get("accept", null)
	if typeof(accept) != TYPE_BOOL:
		return [_reject(agent, "Accept or refuse.")]
	var offer: Dictionary = state.agent_offers[agent]
	if not accept:
		state.agent_offers.erase(agent)
		return [_log(state, "agent_refused", {"client": client, "agent": agent}, [client, agent])]
	# Everything is checked again: the turn, the Agent, and what was asked for may all have changed.
	var gone: String = _problem_hiring(state, agent, offer)
	if gone != "":
		state.agent_offers.erase(agent)
		return [_log(state, "agent_request_void", {"client": client, "agent": agent, "reason": gone}, [client, agent])]
	var checked: Array = _report_for(state, offer["kind"], offer["target"], offer["role"])
	state.agent_offers.erase(agent)
	if checked[1] != "":
		return [_log(state, "agent_request_void", {"client": client, "agent": agent, "reason": checked[1]}, [client, agent])]
	var owed: int = DebtScript.charge(state, client, agent, offer["price"])
	state.agent_used[agent] = true
	var report: Dictionary = checked[0]
	report["client"] = client
	report["agent"] = agent
	report["paid"] = offer["price"]
	if owed > 0:
		report["new_debt"] = owed
	return [_log(state, "agent_report", report, [agent, client])]


# Why a hire can't go ahead, or "".
static func _problem_hiring(state: GameStateScript, agent: int, offer: Dictionary) -> String:
	if not offer["client"] in state.player_ids or state.eliminated.get(offer["client"], false):
		return "the asker left the game"
	if _on_their_turn(state, agent) != "":
		return "it is no longer the Agent's turn"
	var power: String = RolesScript.can_use_pledge(state, agent, "Secret Agent")
	if power != "":
		return power
	if state.agent_used.get(agent, false):
		return "the Agent has already used their power this round"
	return ""


# --- the automatic steps -----------------------------------------------------------------

# A request nobody answered in time is refused; one whose Agent's turn has ended is void.
static func step(state: GameStateScript) -> Array:
	var events: Array = []
	var agents: Array = state.agent_offers.keys()
	agents.sort()
	for agent in agents:
		var offer: Dictionary = state.agent_offers[agent]
		if _on_their_turn(state, agent) != "":
			state.agent_offers.erase(agent)
			events.append(_log(state, "agent_request_void", {"client": offer["client"], "agent": agent, "reason": "it is no longer the Agent's turn"}, [offer["client"], agent]))
		elif state.clock_ms >= int(offer["deadline"]):
			state.agent_offers.erase(agent)
			events.append(_log(state, "agent_request_expired", {"client": offer["client"], "agent": agent}, [offer["client"], agent]))
	return events


static func _log(state: GameStateScript, type: String, data: Dictionary, audience: Array) -> Dictionary:
	var event: Dictionary = EventsScript.make(type, data, audience)
	state.event_log.append(event)
	return event


# A coup or will check is made on the Agent's own turn.
static func _on_their_turn(state: GameStateScript, agent: int) -> String:
	var waiting: Array = state.term.get("waiting", [])
	if state.term.get("phase", GameStateScript.TermPhase.NONE) != GameStateScript.TermPhase.TURNS or waiting.is_empty() or waiting[0] != agent:
		return "You can only check cards and wills on your own turn."
	return ""


static func _reject(player_id: int, reason: String) -> Dictionary:
	return EventsScript.make("rejected", {"reason": reason}, [player_id])
