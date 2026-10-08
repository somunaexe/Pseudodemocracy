class_name Loyalists

# Loyalists (handbook glossary): "A player made your Loyalist by a card votes with you on anything at all, for however
# long that card states. The status simply expires when that duration ends, or earlier if a card says they defect. You
# can have more than one at a time."
#
# state.loyalists maps a FOLLOWER to { "owner", "left" }: a player follows at most one owner (a new appointment
# replaces the old), an owner can have many, and a follower can have followers of their own (the chain is followed).
# Nobody can be made the Loyalist of their own follower, direct or indirect: that would be a circle, with nobody to
# follow. It is public. "left" counts rounds down at the end of each round, the round of the appointment included
# (as for sickness); at 0 the loyalty expires.
#
# "Votes with you on anything at all" is applied to every ballot: an amendment, an election, a performance (also a
# Command Performance). When the owner casts a vote, each follower who may vote in that ballot is given the same one at
# once (and so on down the chain). A follower may not vote for themselves while their owner can still vote in the
# ballot; if the owner has already voted by the time the follower does (the loyalty began mid-ballot), the follower's
# vote is changed to the owner's. If the owner cannot vote in a ballot (the performer, the Leader in an amendment, a
# sick or eliminated player) the follower votes freely. Gender never matters except to one Scandal card.
#
# Like Roles and Sickness, nothing here logs: every function returns its events and the caller logs them.

const GameStateScript = preload("res://scripts/game_state.gd")
const GendersScript = preload("res://scripts/genders.gd")
const EventsScript = preload("res://scripts/events.gd")
const RngScript = preload("res://scripts/rng.gd")


# Who this player follows, or 0.
static func owner_of(state: GameStateScript, follower: int) -> int:
	return int(state.loyalists.get(follower, {}).get("owner", 0))


# The players who follow this owner directly, lowest id first.
static func followers_of(state: GameStateScript, owner: int) -> Array:
	var result: Array = []
	for id in state.loyalists:
		if state.loyalists[id]["owner"] == owner:
			result.append(id)
	result.sort()
	return result


# Why this player can't be made the owner's Loyalist, or "".
static func problem_appointing(state: GameStateScript, owner: int, follower: int) -> String:
	if follower == owner:
		return "You can't be your own Loyalist."
	if not follower in state.player_ids or state.eliminated.get(follower, false):
		return "That player is not in the game."
	var up: int = owner   # walk up from the owner: meeting the follower would make a circle
	var steps: int = 0
	while up != 0 and steps <= state.player_ids.size():
		if up == follower:
			return "They are already above you in a chain of loyalty."
		up = owner_of(state, up)
		steps += 1
	return ""


static func appoint(state: GameStateScript, owner: int, follower: int, rounds: int) -> Array:
	assert(problem_appointing(state, owner, follower) == "", "appoint() needs a follower who can be appointed")
	state.loyalists[follower] = {"owner": owner, "left": rounds, "since": state.current_round}
	return [EventsScript.make("loyalist_appointed", {"owner": owner, "loyalist": follower, "rounds": rounds})]


# One of the owner's Loyalists, chosen at random, defects ("your current Loyalist (if any) defects"). Nothing happens
# if they have none.
static func defect_one(state: GameStateScript, owner: int) -> Array:
	var all: Array = followers_of(state, owner)
	if all.is_empty():
		return []
	var gone: int = RngScript.pick(state, all)
	state.loyalists.erase(gone)
	return [EventsScript.make("loyalist_defected", {"owner": owner, "loyalist": gone})]


# How many of the owner's direct Loyalists are of the gender.
static func count_of_gender(state: GameStateScript, owner: int, gender: String) -> int:
	var n: int = 0
	for id in followers_of(state, owner):
		if GendersScript.of(state, id) == gender:
			n += 1
	return n


static func end_of_round(state: GameStateScript) -> Array:
	var events: Array = []
	var ids: Array = state.loyalists.keys()
	ids.sort()
	for id in ids:
		if int(state.loyalists[id].get("since", -1)) == state.current_round:
			continue   # n rounds means n further rounds: not the one it began in
		state.loyalists[id]["left"] = int(state.loyalists[id]["left"]) - 1
		if state.loyalists[id]["left"] <= 0:
			events.append(EventsScript.make("loyalty_ended", {"owner": state.loyalists[id]["owner"], "loyalist": id}))
			state.loyalists.erase(id)
	return events


# A player leaves the game: they follow nobody, and nobody follows them.
static func remove_player(state: GameStateScript, player_id: int) -> void:
	state.loyalists.erase(player_id)
	for id in state.loyalists.keys():
		if state.loyalists[id]["owner"] == player_id:
			state.loyalists.erase(id)


# --- voting ---------------------------------------------------------------------------------
# `votes` is the ballot's own dictionary (voter -> what they voted), `may_vote` a Callable(id) -> bool for that ballot.

# Why this player can't vote for themselves, or "": their owner can still vote in this ballot.
static func problem_voting(state: GameStateScript, voter: int, votes: Dictionary, may_vote: Callable) -> String:
	var owner: int = owner_of(state, voter)
	if owner != 0 and may_vote.call(owner) and not votes.has(owner):
		return "You vote with the player you are loyal to, once they have voted."
	return ""


# What a follower's vote is if their owner has already voted: the owner's. Otherwise the value they gave.
static func vote_for(state: GameStateScript, voter: int, value: Variant, votes: Dictionary, may_vote: Callable) -> Variant:
	var owner: int = owner_of(state, voter)
	if owner != 0 and may_vote.call(owner) and votes.has(owner):
		return votes[owner]
	return value


# The owner has voted `value`: every follower who may vote and has not yet does the same, down the chain.
# Returns [follower, owner] pairs, in order, so the caller can say who followed whom.
static func mirror(state: GameStateScript, owner: int, value: Variant, votes: Dictionary, may_vote: Callable) -> Array:
	var followed: Array = []
	for follower in followers_of(state, owner):
		if may_vote.call(follower) and not votes.has(follower):
			votes[follower] = value
			followed.append([follower, owner])
			followed.append_array(mirror(state, follower, value, votes, may_vote))
	return followed
