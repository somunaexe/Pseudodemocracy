class_name RoundEnd

# Everything that happens when a round (a term) ends: wills are charged their upkeep, sickness and immunity
# count down, the Doctor's charges and the Secret Agents' one check come back. One place, called when an election begins after a term (see Election.begin). Like
# Sickness and Roles, nothing here logs: the caller logs the events it returns.

const GameStateScript = preload("res://scripts/game_state.gd")
const SicknessScript = preload("res://scripts/sickness.gd")
const EffectClockScript = preload("res://scripts/effect_clock.gd")
const WillsScript = preload("res://scripts/wills.gd")
const CorruptionScript = preload("res://scripts/corruption.gd")
const RivalsScript = preload("res://scripts/rivals.gd")
const LoyalistsScript = preload("res://scripts/loyalists.gd")


static func run(state: GameStateScript) -> Array:
	for id in state.coup_ban.keys():   # a coup ban counts down with each round, not the one it began in
		if EffectClockScript.skips(state, "coup_ban", id):
			continue
		state.coup_ban[id] -= 1
		if state.coup_ban[id] <= 0:
			state.coup_ban.erase(id)
	state.doctor_used = {}
	state.agent_used = {}
	var events: Array = WillsScript.end_of_round(state)   # upkeep first: a will on hold when the round ends
	events.append_array(SicknessScript.end_of_round(state))
	events.append_array(CorruptionScript.end_of_round(state))
	events.append_array(RivalsScript.end_of_round(state))
	events.append_array(LoyalistsScript.end_of_round(state))
	return events
