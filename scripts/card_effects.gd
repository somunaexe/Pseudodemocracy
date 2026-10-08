class_name CardEffects

# What a Settlement or Scandal card does to the player who drew it, for the cards whose effect is
# only about that player's own money and popularity (listed in data/source/cards.js):
#   psd > 0   the treasury pays the player (what it has, if it is short); debts are paid first
#   psd < 0   the player pays the treasury; whatever they can't cover becomes debt
#   popularity   moves the base popularity (it stays on the track)
# Every other card is read out to the table, which carries it out: the event says by_table.
# Total money never changes.
#
# Every event this file creates is logged here, once.

const GameStateScript = preload("res://scripts/game_state.gd")
const CardsScript = preload("res://scripts/cards.gd")
const DebtScript = preload("res://scripts/debt.gd")
const PopularityScript = preload("res://scripts/popularity.gd")
const EventsScript = preload("res://scripts/events.gd")


# Apply a drawn card to the player. Returns one event.
static func apply(state: GameStateScript, player_id: int, deck: String, card: int) -> Array:
	var effect: Dictionary = CardsScript.effects(deck, card)
	var data: Dictionary = {"player": player_id, "deck": deck, "card": card, "by_table": effect.is_empty()}
	if effect.has("psd"):
		var amount: int = int(effect["psd"])
		if amount > 0:
			var paid: int = mini(amount, state.treasury)
			state.treasury -= paid
			DebtScript.receive(state, player_id, paid)
			data["psd"] = paid
			if paid < amount:
				data["short"] = amount - paid
		else:
			data["psd"] = amount
			var owed: int = DebtScript.charge(state, player_id, DebtScript.TREASURY_ID, -amount)
			if owed > 0:
				data["new_debt"] = owed
	if effect.has("popularity"):
		var before: int = PopularityScript.effective(state, player_id)
		PopularityScript.change_base(state, player_id, int(effect["popularity"]))
		data["popularity"] = PopularityScript.effective(state, player_id) - before   # what actually changed
	var event: Dictionary = EventsScript.make("card_applied", data)
	state.event_log.append(event)
	return [event]
