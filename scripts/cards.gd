class_name Cards

# The three decks, as data (data/cards.json, generated from data/source/cards.js):
#   performance  what a player has to perform on their turn
#   settlement   the card for winning the performance vote (the "good" card)
#   scandal      the card for losing it (the "bad" card)
# A card is its position in its list. The draw piles are SECRET server state (GameState.decks):
# each is a shuffled list of card numbers, drawn from the end. When a pile runs out it is
# shuffled afresh from the whole deck.

const GameStateScript = preload("res://scripts/game_state.gd")
const RngScript = preload("res://scripts/rng.gd")

const PATH := "res://data/cards.json"
const DECKS := ["performance", "settlement", "scandal"]

static var _data: Dictionary = {}


static func _load() -> Dictionary:
	if _data.is_empty():
		var file := FileAccess.open(PATH, FileAccess.READ)
		assert(file != null, "Can't open %s. Run: node tools/export_cards.js" % PATH)
		var parsed = JSON.parse_string(file.get_as_text())
		assert(parsed is Dictionary, "%s is not valid JSON" % PATH)
		_data = parsed
	return _data


static func count(deck: String) -> int:
	assert(deck in DECKS, "There is no deck called '%s'" % deck)
	return _load()[deck].size()


static func text(deck: String, card: int) -> String:
	assert(card >= 0 and card < count(deck), "There is no card %d in the %s deck" % [card, deck])
	return _load()[deck][card]


# What the game itself does when this card is drawn: {} (the table carries it out), or a dictionary
# (see CardEffects): "psd" and "popularity" for the drawer, and for cards that ask for a choice
# "choose", "gain_role", "swap_with" and "target". Performance cards have none.
static func effects(deck: String, card: int) -> Dictionary:
	assert(card >= 0 and card < count(deck), "There is no card %d in the %s deck" % [card, deck])
	return _whole(_load()["effects"].get(deck, {}).get(str(card), {}))


# JSON numbers load as floats; the effects hold only whole numbers, so turn them back, however deep.
static func _whole(value: Variant) -> Variant:
	match typeof(value):
		TYPE_FLOAT:
			return int(value)
		TYPE_ARRAY:
			var list: Array = []
			for item in value:
				list.append(_whole(item))
			return list
		TYPE_DICTIONARY:
			var map: Dictionary = {}
			for key in value:
				map[key] = _whole(value[key])
			return map
	return value


# Draw the top card of a deck, reshuffling the whole deck first if the pile is empty.
static func draw(state: GameStateScript, deck: String) -> int:
	assert(deck in DECKS, "There is no deck called '%s'" % deck)
	var pile: Array = state.decks.get(deck, [])
	if pile.is_empty():
		pile = _shuffled(state, count(deck))
	var card: int = pile.pop_back()
	state.decks[deck] = pile
	return card


# Fisher-Yates, with the game's own generator so a saved game shuffles the same way.
static func _shuffled(state: GameStateScript, size: int) -> Array:
	var cards: Array = range(size)
	for i in range(size - 1, 0, -1):
		var j: int = RngScript.below(state, i + 1)
		var held: int = cards[i]
		cards[i] = cards[j]
		cards[j] = held
	return cards
