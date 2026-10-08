class_name Income

# Income, paid from the treasury at the start of a player's own turn, with tax taken from it:
#   - the Leader earns leaderIncome (100), the Vice viceIncome (90)
#   - each role card earns its roleIncome (Doctor 70, Lawyer 50, Secret Agent 80; Activists and
#     Agberos earn nothing). Roles stack, so a Doctor who is also a Lawyer earns both.
#   - a card can skip one income altogether (skip_income) or its tax (skip_tax), see Modifiers
#   - tax is the tax rate (Article 2, so it follows amendments) of what was paid, rounded down,
#     which favours the player; the tax goes straight back to the treasury.
# If the treasury can't cover the income, it pays what it has.
# Money is conserved: the treasury loses exactly what the player gains. The player's gain goes
# through Debt.receive, so it pays their oldest debts first.
#
# Every event this file creates is logged here, once.

const GameStateScript = preload("res://scripts/game_state.gd")
const GameDataScript = preload("res://scripts/game_data.gd")
const LawScript = preload("res://scripts/law.gd")
const DebtScript = preload("res://scripts/debt.gd")
const RolesScript = preload("res://scripts/roles.gd")
const ModifiersScript = preload("res://scripts/modifiers.gd")
const EventsScript = preload("res://scripts/events.gd")


# What this player earns before tax and before the treasury runs short.
static func gross(state: GameStateScript, player_id: int) -> int:
	var total: int = 0
	if player_id == state.leader_id:
		total += GameDataScript.get_int("leaderIncome")
	elif player_id == state.vice_id:
		total += GameDataScript.get_int("viceIncome")
	if not RolesScript.is_cancelled(state, player_id) and not state.frozen.has(player_id):   # CANCELLED or frozen players have no roles; the Leader's pay stays
		for role in RolesScript.held(state, player_id):
			total += GameDataScript.get_nested_int("roleIncome", str(role))
	return total


# Pay the player. Returns [] if they earn nothing.
static func pay(state: GameStateScript, player_id: int) -> Array:
	var owed: int = gross(state, player_id)
	if owed == 0:
		return []
	if ModifiersScript.active(state, player_id, "skip_income"):
		ModifiersScript.use(state, player_id, "skip_income")   # a card says this income is not collected
		var skipped: Dictionary = EventsScript.make("income_skipped", {"player": player_id, "gross": owed})
		state.event_log.append(skipped)
		return [skipped]
	var paid: int = mini(owed, state.treasury)
	var tax: int = (paid * LawScript.get_int(state, "taxRate")) / 100   # whole PSD, rounded down
	if ModifiersScript.active(state, player_id, "skip_tax"):
		ModifiersScript.use(state, player_id, "skip_tax")   # "you qualified for benefits": no tax this time
		tax = 0
	var net: int = paid - tax
	state.treasury -= net
	DebtScript.receive(state, player_id, net)
	var event: Dictionary = EventsScript.make("income_paid", {"player": player_id, "gross": owed, "paid": paid, "tax": tax, "net": net})
	state.event_log.append(event)
	return [event]
