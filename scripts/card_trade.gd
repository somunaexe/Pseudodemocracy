class_name CardTrade

# Selling a kept card to another player ("keep this card till you become Leader or sell it"). Any kept card can be sold.
#   { "type": "sell_card", "index": place in the hand, "buyer": id, "price": whole number }   the seller
#   { "type": "buy_card", "seller": id, "accept": bool }                                      the buyer
# The buyer has cardOfferSeconds to answer (silence is a refusal) and must have the price in cash. If they accept they pay the seller
# and the card moves to their hand. A card for a seat (the levy cut) starts working at once if its new holder is the Leader.
# One offer per seller at a time (state.card_offers, public). Every event is logged here, once.

const GameStateScript = preload("res://scripts/game_state.gd")
const GameDataScript = preload("res://scripts/game_data.gd")
const DebtScript = preload("res://scripts/debt.gd")
const SpecialCardsScript = preload("res://scripts/special_cards.gd")
const EventsScript = preload("res://scripts/events.gd")

const PRICE_MAX := 5000


static func handle(state: GameStateScript, player_id: int, command: Dictionary) -> Array:
	match str(command.get("type", "")):
		"sell_card":
			return _sell(state, player_id, command)
		"buy_card":
			return _buy(state, player_id, command)
	return [_reject(player_id, "Unknown command.")]


static func _sell(state: GameStateScript, seller: int, command: Dictionary) -> Array:
	if not seller in state.player_ids or state.eliminated.get(seller, false):
		return [_reject(seller, "You are not in the game.")]
	var hand: Array = state.hands.get(seller, [])
	var index = command.get("index", null)
	var buyer = command.get("buyer", null)
	var price = command.get("price", null)
	if typeof(index) != TYPE_INT or index < 0 or index >= hand.size():
		return [_reject(seller, "Choose a card in your hand by its number.")]
	if typeof(buyer) != TYPE_INT or buyer == seller or not buyer in state.player_ids or state.eliminated.get(buyer, false):
		return [_reject(seller, "Choose another player who is in the game.")]
	if typeof(price) != TYPE_INT or price < 0 or price > PRICE_MAX:
		return [_reject(seller, "The price must be a whole number from 0 to %d." % PRICE_MAX)]
	if state.card_offers.has(seller):
		return [_reject(seller, "You already have a card for sale.")]
	var seconds: int = GameDataScript.get_int("cardOfferSeconds")
	var ends_at: int = state.clock_ms + seconds * 1000
	state.card_offers[seller] = {"buyer": buyer, "deck": hand[index]["deck"], "card": hand[index]["card"], "price": price, "deadline": ends_at}
	return [_log(state, "card_offered", {"seller": seller, "buyer": buyer, "deck": hand[index]["deck"], "card": hand[index]["card"], "price": price, "seconds": seconds, "ends_at_ms": ends_at})]


static func _buy(state: GameStateScript, buyer: int, command: Dictionary) -> Array:
	var seller = command.get("seller", null)
	var accept = command.get("accept", null)
	if typeof(seller) != TYPE_INT or not state.card_offers.has(seller) or state.card_offers[seller]["buyer"] != buyer:
		return [_reject(buyer, "Nobody is selling you a card.")]
	if typeof(accept) != TYPE_BOOL:
		return [_reject(buyer, "Accept or refuse.")]
	var offer: Dictionary = state.card_offers[seller]
	state.card_offers.erase(seller)
	if not accept:
		return [_log(state, "card_sale_refused", {"seller": seller, "buyer": buyer})]
	var index: int = _find(state, seller, offer)
	if index == -1:
		return [_log(state, "card_sale_void", {"seller": seller, "buyer": buyer, "reason": "the seller no longer has the card"})]
	if int(state.psd.get(buyer, 0)) < int(offer["price"]):
		return [_log(state, "card_sale_void", {"seller": seller, "buyer": buyer, "reason": "the buyer can't pay"})]
	DebtScript.charge(state, buyer, seller, int(offer["price"]))
	state.hands[seller].remove_at(index)
	if state.hands[seller].is_empty():
		state.hands.erase(seller)
	if not state.hands.has(buyer):
		state.hands[buyer] = []
	state.hands[buyer].append({"deck": offer["deck"], "card": offer["card"]})
	var events: Array = [_log(state, "card_sold", {"seller": seller, "buyer": buyer, "deck": offer["deck"], "card": offer["card"], "price": offer["price"]})]
	events.append_array(SpecialCardsScript.refresh(state, buyer))
	return events


static func _find(state: GameStateScript, seller: int, offer: Dictionary) -> int:
	var hand: Array = state.hands.get(seller, [])
	for i in hand.size():
		if hand[i]["deck"] == offer["deck"] and hand[i]["card"] == offer["card"]:
			return i
	return -1


# Offers nobody answered in time are refused.
static func step(state: GameStateScript) -> Array:
	var sellers: Array = state.card_offers.keys()
	sellers.sort()
	for seller in sellers:
		var offer: Dictionary = state.card_offers[seller]
		if state.clock_ms >= int(offer["deadline"]) or state.eliminated.get(seller, false) or state.eliminated.get(offer["buyer"], false):
			state.card_offers.erase(seller)
			return [_log(state, "card_offer_expired", {"seller": seller, "buyer": offer["buyer"]})]
	return []


static func remove_player(state: GameStateScript, player_id: int) -> void:
	state.card_offers.erase(player_id)
	for seller in state.card_offers.keys():
		if state.card_offers[seller]["buyer"] == player_id:
			state.card_offers.erase(seller)


static func _log(state: GameStateScript, type: String, data: Dictionary) -> Dictionary:
	var event: Dictionary = EventsScript.make(type, data)
	state.event_log.append(event)
	return event


static func _reject(player_id: int, reason: String) -> Dictionary:
	return EventsScript.make("rejected", {"reason": reason}, [player_id])
