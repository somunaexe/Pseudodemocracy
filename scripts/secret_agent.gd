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
# "Not being caught sharing" is for the table to judge: the game cannot hear what players say.
# (Assumed: an Agent may check their own cards and their own will.)
#
# Every event this file creates is logged here, once.

const GameStateScript = preload("res://scripts/game_state.gd")
const RolesScript = preload("res://scripts/roles.gd")
const EventsScript = preload("res://scripts/events.gd")

const KINDS := ["coup", "will", "bead"]


static func handle(state: GameStateScript, agent: int, command: Dictionary) -> Array:
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


# A coup or will check is made on the Agent's own turn.
static func _on_their_turn(state: GameStateScript, agent: int) -> String:
	var waiting: Array = state.term.get("waiting", [])
	if state.term.get("phase", GameStateScript.TermPhase.NONE) != GameStateScript.TermPhase.TURNS or waiting.is_empty() or waiting[0] != agent:
		return "You can only check cards and wills on your own turn."
	return ""


static func _reject(player_id: int, reason: String) -> Dictionary:
	return EventsScript.make("rejected", {"reason": reason}, [player_id])
