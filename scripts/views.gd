class_name Views

# What each player is allowed to see. The server holds the whole truth (GameState);
# a phone only ever gets a view built here.
#
# The rule is an ALLOW-LIST: a field is shown only if it is listed as public. A field
# added to GameState later is hidden from everyone until someone classifies it, and the
# test fails until they do. Forgetting a secret can never leak it.

const GameStateScript = preload("res://scripts/game_state.gd")
const SerializerScript = preload("res://scripts/serializer.gd")
const PopularityScript = preload("res://scripts/popularity.gd")

# Everyone at the table may see these.
const PUBLIC_FIELDS = [
	"player_count", "turns_played", "leader_id", "leader_type", "sick",
	"windows_used", "treasury", "psd", "debts", "debt_terms", "eliminated", "player_ids",
	"half_rounds", "current_round", "articles", "amendment_record", "unions", "heirs", "nepo", "game_over", "clock_ms", "roles", "last_turn_player", "leader_goes_first", "levy_band",
]

# Shown only after being cleaned up for the one asking (see state_view).
const REDACTED_FIELDS = ["amend", "event_log", "popularity", "election", "term"]

# Extra keys a view carries that are not GameState fields.
const DERIVED_KEYS = ["popularity_base"]

# Never leave the server. A will is secret until its owner is eliminated; then it is read out
# in an event. rng_state is secret because whoever knew it could predict every random draw. (Exam keys and the Doctor's beads will go here when they exist.)
const SERVER_ONLY_FIELDS = ["wills", "rng_state", "decks"]


# Fields of GameState that are in none of the three lists.
static func unclassified_fields(fields: Array) -> Array:
	var result: Array = []
	for name in fields:
		if not name in PUBLIC_FIELDS and not name in REDACTED_FIELDS and not name in SERVER_ONLY_FIELDS:
			result.append(name)
	return result


# The events this player may see: those for everyone (empty audience) and those addressed to them.
static func visible_events(events: Array, player_id: int) -> Array:
	var result: Array = []
	for event in events:
		var audience: Array = event.get("audience", [])
		if audience.is_empty() or player_id in audience:
			result.append(event.duplicate(true))
	return result


# Sorts a batch of new events into one list per player, ready to send.
static func deliver(events: Array, player_ids: Array) -> Dictionary:
	var result: Dictionary = {}
	for id in player_ids:
		result[id] = visible_events(events, id)
	return result


# A copy of the game as this player may see it. A player id that isn't at the table
# (a spectator) gets the public parts only. Changing the copy never changes the game.
static func state_view(state: GameStateScript, player_id: int) -> Dictionary:
	var unclassified: Array = unclassified_fields(SerializerScript.state_fields(state))
	assert(unclassified.is_empty(), "GameState fields not classified in Views: %s" % str(unclassified))
	var view: Dictionary = {}
	for name in PUBLIC_FIELDS:
		view[name] = _copy(state.get(name))
	# "popularity" in a view is what counts (base plus the Nepo Baby change); the base is alongside.
	var effective: Dictionary = {}
	for id in state.player_ids:
		effective[id] = PopularityScript.effective(state, id)
	view["popularity"] = effective
	view["popularity_base"] = PopularityScript.bases(state)
	view["amend"] = _amend_view(state.amend, player_id)
	view["election"] = _election_view(state.election, player_id)
	view["term"] = _term_view(state.term, player_id)
	view["event_log"] = visible_events(state.event_log, player_id)
	return view


static func state_view_json(state: GameStateScript, player_id: int) -> String:
	return SerializerScript.to_json(state_view(state, player_id))


# The amendment in progress, without anyone's vote. Everyone sees WHO has voted;
# you also see how YOU voted.
static func _amend_view(amend: Dictionary, player_id: int) -> Dictionary:
	if amend.is_empty():
		return {}
	var view: Dictionary = amend.duplicate(true)
	var votes: Dictionary = view.get("votes", {})
	view.erase("votes")
	var voters: Array = votes.keys()
	voters.sort()
	view["voted"] = voters
	if votes.has(player_id):
		view["my_vote"] = votes[player_id]
	return view


# The election, without the answer key, anyone's exam answers or anyone's ballot. Everyone sees
# WHO has answered and WHO has voted; you also see your own answers and ballot.
static func _election_view(election: Dictionary, player_id: int) -> Dictionary:
	if election.is_empty():
		return {}
	var view: Dictionary = election.duplicate(true)
	view.erase("key")
	var answers: Dictionary = view.get("answers", {})
	var votes: Dictionary = view.get("votes", {})
	view.erase("answers")
	view.erase("votes")
	var answered: Array = answers.keys()
	answered.sort()
	var voted: Array = votes.keys()
	voted.sort()
	view["answered"] = answered
	view["voted"] = voted
	if answers.has(player_id):
		view["my_answers"] = answers[player_id]
	if votes.has(player_id):
		view["my_vote"] = votes[player_id]
	return view


# The term, without how anyone voted on the performance. Everyone sees WHO has voted; you also
# see your own vote.
static func _term_view(term: Dictionary, player_id: int) -> Dictionary:
	var view: Dictionary = term.duplicate(true)
	if view.has("act"):
		var votes: Dictionary = view["act"]["votes"]
		var voted: Array = votes.keys()
		voted.sort()
		view["act"].erase("votes")
		view["act"]["voted"] = voted
		if votes.has(player_id):
			view["act"]["my_vote"] = votes[player_id]
	return view


static func _copy(value: Variant) -> Variant:
	if typeof(value) == TYPE_ARRAY or typeof(value) == TYPE_DICTIONARY:
		return value.duplicate(true)
	return value
