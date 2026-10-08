class_name AmendmentFlow

# The whole life of one amendment. Four patterns meet here:
#  1. Commands: players only ever ask (handle). The server decides, using the rules.
#  2. Events: handle returns plain-data events saying what happened; the UI never
#     reads rules, it just reacts to events.
#  3. State machine: ALLOWED_COMMANDS says which commands each phase accepts.
#  4. Data-driven: penalties, steal amounts, the swing table and the Constitution
#     itself all come from the game data, not from numbers typed here.
#
# NONE --propose--> PROPOSED --rule_grammar(ok)--> VOTING --last vote--> NONE
#   PROPOSED/VOTING --confront(Agbero)--> NONE (blocked)
#   PROPOSED/VOTING --confront(Activist)--> same phase, votes now weighted
#   propose with bad wording, or rule_grammar(not ok) --> NONE (penalty)
#
# A rejected command changes nothing and is not logged.

const GameStateScript = preload("res://scripts/game_state.gd")
const GameDataScript = preload("res://scripts/game_data.gd")
const LawScript = preload("res://scripts/law.gd")
const PopularityScript = preload("res://scripts/popularity.gd")
const PermissionsScript = preload("res://scripts/permissions.gd")
const AmendmentScript = preload("res://scripts/amendment.gd")
const ConstitutionScript = preload("res://scripts/constitution.gd")
const DebtScript = preload("res://scripts/debt.gd")
const UnionsScript = preload("res://scripts/unions.gd")
const ViceScript = preload("res://scripts/vice.gd")
const LoyalistsScript = preload("res://scripts/loyalists.gd")
const EventsScript = preload("res://scripts/events.gd")

# Only the server may rule on grammar. How it decides (a referee, a tool, word lists)
# is still an open design question; see docs/design_decisions.md.
const SERVER_ID := 0

const ALLOWED_COMMANDS = {
	GameStateScript.AmendPhase.NONE: ["propose", "amend_agree"],
	GameStateScript.AmendPhase.PROPOSED: ["rule_grammar", "confront"],
	GameStateScript.AmendPhase.VOTING: ["vote", "confront"],
}


# Commands (all Dictionaries with a "type"):
#   { "type": "propose", "window": AmendWindow, "article_id": int, "new_texts": Array of String }
#   { "type": "amend_agree", "accept": bool }       the Leader or the Vice, to a proposal the other made (see below)
#   { "type": "rule_grammar", "ok": bool }          (server only)
#   { "type": "confront", "union_id": int }
#   { "type": "vote", "keep": bool }
# THE LEADER AND THE VICE AMEND TOGETHER: when there is a Vice who can take part, a proposal by either of them is not put
# out until the other agrees (amend_agree, amendCosignSeconds to answer; silence is a refusal). Until then nothing is
# used up. Once agreed it is the Leader's amendment: both sit out the vote and its result moves both their popularity.
# Returns the events it produced; a single "rejected" event if the command was refused.
static func handle(state: GameStateScript, player_id: int, command: Dictionary) -> Array:
	var type: String = str(command.get("type", ""))
	var phase: int = state.amend.get("phase", GameStateScript.AmendPhase.NONE)
	if not ALLOWED_COMMANDS[phase].has(type):
		return [_reject(player_id, "'%s' isn't possible at this stage." % type)]
	var events: Array = []
	match type:
		"propose":
			events = _propose(state, player_id, command)
		"amend_agree":
			events = _agree(state, player_id, command)
		"rule_grammar":
			events = _rule_grammar(state, player_id, command)
		"confront":
			events = _confront(state, player_id, command)
		"vote":
			events = _vote(state, player_id, command)
	if events.is_empty() or events[0]["type"] != "rejected":
		state.event_log.append_array(events)
	return events


# --- propose ---------------------------------------------------------------------------

static func _propose(state: GameStateScript, player_id: int, command: Dictionary) -> Array:
	var window = command.get("window", -1)
	if typeof(window) != TYPE_INT or not window in GameStateScript.AmendWindow.values():
		return [_reject(player_id, "Unknown amendment window.")]
	# Who is asking comes first, so a stranger learns nothing else.
	var problem: String = PermissionsScript.can_amend(state, player_id, window)
	if not problem.is_empty():
		return [_reject(player_id, problem)]
	var article_id = command.get("article_id", -1)
	if typeof(article_id) != TYPE_INT or not state.articles.has(article_id):
		return [_reject(player_id, "There is no such article.")]
	var texts = command.get("new_texts", null)
	if typeof(texts) != TYPE_ARRAY:
		return [_reject(player_id, "The new wording must be a list of words.")]
	for text in texts:
		if typeof(text) != TYPE_STRING:
			return [_reject(player_id, "Every new word must be text.")]
	var other: int = PermissionsScript.cosigner(state, player_id)
	if other != 0:
		return _offer(state, player_id, other, window, article_id, texts)
	return _put_out(state, state.leader_id, window, article_id, texts)


# The proposal is checked and goes out as the Leader's (once the Vice, if there is one, has agreed).
static func _put_out(state: GameStateScript, player_id: int, window: int, article_id: int, texts: Array) -> Array:
	var old_words: Array = state.articles[article_id]
	var cleaned: Array = _normalise(old_words, texts)   # validate and store the same strings
	var structural: String = AmendmentScript.validate_words(old_words, cleaned)
	if structural.is_empty():
		# A word the game can't apply as a rule is a failed check like any other: the Leader
		# chose to write it, so the fine, the popularity loss and the used window all apply.
		structural = LawScript.check_new_wording(article_id, old_words, cleaned)
	if structural.is_empty():
		structural = LawScript.check_levy_band(state, article_id, old_words, cleaned)

	# Accepted. From here the attempt uses up the window whatever happens next.
	state.windows_used[window] = true
	var events: Array = [EventsScript.make("amendment_proposed", {
		"leader": player_id,
		"window": window,
		"article_id": article_id,
		"title": ConstitutionScript.title(article_id),
		"old_text": ConstitutionScript.to_text(old_words),
		"proposed": cleaned,
	})]
	if not structural.is_empty():
		events.append_array(_fail(state, article_id, structural))
		return events
	state.amend = {
		"phase": GameStateScript.AmendPhase.PROPOSED,
		"window": window,
		"article_id": article_id,
		"new_words": _apply_texts(old_words, cleaned),
		"votes": {},           # voter id -> bool. Secret until the vote is resolved.
		"activists": [],       # ids of Activist unions that have confronted
	}
	if not state.grammar_referee:
		# No referee yet (a design question left open): every wording is accepted and the vote opens at once.
		var ruled: Dictionary = {"ok": true, "referee": false}
		_start_vote_clock(state, ruled)
		events.append(EventsScript.make("grammar_ruled", ruled))
		events.append_array(_maybe_resolve(state))
	return events


# --- agreeing ----------------------------------------------------------------------------

static func _offer(state: GameStateScript, proposer: int, other: int, window: int, article_id: int, texts: Array) -> Array:
	if not state.amend_offer.is_empty():
		return [_reject(proposer, "A proposal is already waiting for agreement.")]
	var seconds: int = GameDataScript.get_int("amendCosignSeconds")
	var ends_at: int = state.clock_ms + seconds * 1000
	state.amend_offer = {"by": proposer, "other": other, "window": window, "article_id": article_id, "texts": texts.duplicate(), "deadline": ends_at}
	return [EventsScript.make("amendment_offered", {
		"by": proposer, "other": other, "window": window, "article_id": article_id,
		"title": ConstitutionScript.title(article_id), "proposed": texts.duplicate(), "seconds": seconds, "ends_at_ms": ends_at,
	})]


static func _agree(state: GameStateScript, player_id: int, command: Dictionary) -> Array:
	var offer: Dictionary = state.amend_offer
	if offer.is_empty() or player_id != offer["other"]:
		return [_reject(player_id, "There is no proposal waiting for your agreement.")]
	var accept = command.get("accept", null)
	if typeof(accept) != TYPE_BOOL:
		return [_reject(player_id, "Accept or refuse.")]
	state.amend_offer = {}
	if not accept:
		return [EventsScript.make("amendment_offer_refused", {"by": offer["by"], "other": offer["other"]})]
	# Everything is checked again: the Leader may have changed, the window may be gone.
	var why: String = PermissionsScript.can_amend(state, state.leader_id, offer["window"])
	if why == "":
		why = PermissionsScript.timing_problem(state, offer["window"])
	if why != "":
		return [EventsScript.make("amendment_offer_void", {"by": offer["by"], "other": offer["other"], "reason": why})]
	return _put_out(state, state.leader_id, offer["window"], offer["article_id"], offer["texts"])


# A proposal nobody agreed to in time is dropped, and so is one whose pair has broken up.
static func step(state: GameStateScript) -> Array:
	if state.amend.get("phase", GameStateScript.AmendPhase.NONE) == GameStateScript.AmendPhase.VOTING and state.clock_ms >= int(state.amend.get("deadline", 1 << 60)):
		var late: Array = [EventsScript.make("amendment_vote_timeout", {"article_id": state.amend["article_id"]})]   # the rest abstain
		late.append_array(_resolve(state))
		state.event_log.append_array(late)
		return late
	var offer: Dictionary = state.amend_offer
	if offer.is_empty():
		return []
	var who_left: bool = not ViceScript.is_leader_or_vice(state, int(offer["by"])) or not ViceScript.is_leader_or_vice(state, int(offer["other"])) \
		or state.eliminated.get(offer["by"], false) or state.eliminated.get(offer["other"], false)
	if who_left:
		state.amend_offer = {}
		var gone: Dictionary = EventsScript.make("amendment_offer_void", {"by": offer["by"], "other": offer["other"], "reason": "the Leader and the Vice are no longer the same pair"})
		state.event_log.append(gone)
		return [gone]
	if state.clock_ms >= int(offer["deadline"]):
		state.amend_offer = {}
		var expired: Dictionary = EventsScript.make("amendment_offer_expired", {"by": offer["by"], "other": offer["other"]})
		state.event_log.append(expired)
		return [expired]
	return []


# Highlighted words are trimmed; fixed words are left exactly as sent so the check sees any change.
static func _normalise(old_words: Array, texts: Array) -> Array:
	var cleaned: Array = []
	for i in texts.size():
		var text: String = texts[i]
		if i < old_words.size() and old_words[i]["amendable"]:
			text = text.strip_edges()
		cleaned.append(text)
	return cleaned


static func _apply_texts(old_words: Array, cleaned: Array) -> Array:
	var result: Array = []
	for i in old_words.size():
		var word: Dictionary = old_words[i].duplicate()
		if word["amendable"]:
			word["text"] = cleaned[i]
		result.append(word)
	return result


# --- grammar ---------------------------------------------------------------------------

static func _rule_grammar(state: GameStateScript, player_id: int, command: Dictionary) -> Array:
	if player_id != SERVER_ID:
		return [_reject(player_id, "Only the server can rule on grammar.")]
	var ok = command.get("ok", null)
	if typeof(ok) != TYPE_BOOL:
		return [_reject(player_id, "A grammar ruling must be true or false.")]
	var ruled: Dictionary = {"ok": ok}
	if ok:
		_start_vote_clock(state, ruled)
	var events: Array = [EventsScript.make("grammar_ruled", ruled)]
	if not ok:
		events.append_array(_fail(state, state.amend["article_id"], "The new wording isn't correct English."))
		return events
	events.append_array(_maybe_resolve(state))   # in case nobody is left who can vote
	return events


# The vote opens: the voters have amendVoteSeconds, and those who don't vote abstain. The ruling event says how long.
static func _start_vote_clock(state: GameStateScript, ruled: Dictionary) -> void:
	var seconds: int = GameDataScript.get_int("amendVoteSeconds")
	state.amend["phase"] = GameStateScript.AmendPhase.VOTING
	state.amend["deadline"] = state.clock_ms + seconds * 1000
	ruled["seconds"] = seconds
	ruled["ends_at_ms"] = int(state.amend["deadline"])


# A failed check: the article keeps its old wording, the window stays used, the Leader
# pays the fine and loses (base swing x the other players) popularity.
static func _fail(state: GameStateScript, article_id: int, reason: String) -> Array:
	var leader: int = state.leader_id
	var fine: int = GameDataScript.get_int("amendPenalty")
	var active: int = _active_players(state).size()
	var lost: int = GameDataScript.base_swing(active) * (active - 1)
	var became_debt: int = 0
	for amender in _amenders(state):   # the Leader and the Vice amend together, so they pay together
		became_debt += DebtScript.charge(state, amender, DebtScript.TREASURY_ID, fine)
		PopularityScript.change_base(state, amender, -lost)
	state.amend = {}
	_record(state, article_id, "failed_check", 0, 0, "")
	return [EventsScript.make("amendment_failed", {
		"reason": reason,
		"fine": fine,
		"fine_became_debt": became_debt,
		"popularity_lost": lost,
	})]


# --- confront --------------------------------------------------------------------------

static func _confront(state: GameStateScript, player_id: int, command: Dictionary) -> Array:
	var union_id = command.get("union_id", -1)
	if typeof(union_id) != TYPE_INT or not state.unions.has(union_id):
		return [_reject(player_id, "There is no such union or mob.")]
	var union: Dictionary = state.unions[union_id]
	if union["owner"] != player_id:
		return [_reject(player_id, "Only the %s decides for a %s." % [UnionsScript.head(union), UnionsScript.word(union)])]
	if state.eliminated.get(player_id, false) or state.sick.get(player_id, false):
		return [_reject(player_id, "A sick or eliminated %s can't use pledges." % UnionsScript.head(union))]
	if union["members"].size() < LawScript.get_int(state, "unionMin"):
		return [_reject(player_id, "The %s is too small to act." % UnionsScript.word(union))]
	if union["confront_used"]:
		return [_reject(player_id, "This %s has already confronted the Leader." % UnionsScript.word(union))]
	if state.leader_id in union["members"] or state.vice_id in union["members"]:
		return [_reject(player_id, "A %s that includes the Leader can't confront (Article 17 is not built yet)." % UnionsScript.word(union))]

	union["confront_used"] = true
	var events: Array = [EventsScript.make("union_confronted", {
		"union_id": union_id,
		"union_type": union["type"],
		"unionizer": player_id,
	})]
	if union["type"] == GameStateScript.UnionType.AGBERO:
		events.append_array(_block(state, union_id, union))
	else:
		state.amend["activists"].append(union_id)
		events.append_array(_maybe_resolve(state))
	return events


# Agbero confront: the amendment is blocked (its window stays used) and the Leader pays
# each member the steal amount. Assumption: that is "50 x union size" in total, 50 each.
static func _block(state: GameStateScript, union_id: int, union: Dictionary) -> Array:
	var steal: int = LawScript.get_int(state, "agberoSteal")
	var became_debt: int = 0
	for member in union["members"]:
		became_debt += DebtScript.charge(state, state.leader_id, member, steal)
	var article_id: int = state.amend["article_id"]
	state.amend = {}
	_record(state, article_id, "blocked", 0, 0, "")
	var events: Array = [EventsScript.make("amendment_blocked", {
		"union_id": union_id,
		"stolen_each": steal,
		"members": union["members"].duplicate(),
		"became_debt": became_debt,
	})]
	events.append_array(UnionsScript.disperse(state, union_id, "the mob acted"))   # an Agbero mob disperses the instant it acts (Article 13)
	return events


# --- voting ----------------------------------------------------------------------------

static func _vote(state: GameStateScript, player_id: int, command: Dictionary) -> Array:
	var keep = command.get("keep", null)
	if typeof(keep) != TYPE_BOOL:
		return [_reject(player_id, "A vote must be keep or reject.")]
	if not player_id in _eligible_voters(state):
		return [_reject(player_id, "You can't vote on this amendment.")]
	if player_id in _auto_voters(state):
		return [_reject(player_id, "Your union's vote is cast automatically.")]
	if player_id in _auto_followers(state):
		return [_reject(player_id, "You vote with the player you are loyal to, and their union's vote is cast automatically.")]
	if state.amend["votes"].has(player_id):
		return [_reject(player_id, "You have already voted.")]
	var may: Callable = func(id): return id in _eligible_voters(state) and not id in _auto_voters(state)
	var blocked: String = LoyalistsScript.problem_voting(state, player_id, state.amend["votes"], may)
	if blocked != "":
		return [_reject(player_id, blocked)]
	keep = LoyalistsScript.vote_for(state, player_id, keep, state.amend["votes"], may)   # a Loyalist votes as their owner did
	state.amend["votes"][player_id] = keep
	# Everyone learns THAT you voted, never HOW. The votes stay in server state until the result.
	var events: Array = [EventsScript.make("vote_cast", {"voter": player_id})]
	for pair in LoyalistsScript.mirror(state, player_id, keep, state.amend["votes"], may):
		events.append(EventsScript.make("vote_cast", {"voter": pair[0], "with": pair[1]}))
	events.append_array(_maybe_resolve(state))
	return events


# Everyone except the Leader, the sick and the eliminated.
static func _eligible_voters(state: GameStateScript) -> Array:
	var result: Array = []
	for id in state.player_ids:
		if id == state.leader_id or id == state.vice_id or state.eliminated.get(id, false) or state.sick.get(id, false):
			continue   # the Leader and the Vice amend together and sit out the vote
		result.append(id)
	return result


# Members of a confronting Activist union vote automatically, against the Leader.
static func _auto_voters(state: GameStateScript) -> Array:
	var eligible: Array = _eligible_voters(state)
	var result: Array = []
	for union_id in state.amend.get("activists", []):
		if not state.unions.has(union_id):
			continue   # the union was dissolved since it confronted
		for member in state.unions[union_id]["members"]:
			if member in eligible and not member in result:
				result.append(member)
	return result


# The Loyalists of a confronting union's members (and theirs, down the chain) vote against the Leader too, one vote each,
# without the union's multiplier. A member of the union is an automatic voter and not counted here.
static func _auto_followers(state: GameStateScript) -> Array:
	var eligible: Array = _eligible_voters(state)
	var auto: Array = _auto_voters(state)
	var result: Array = []
	var queue: Array = auto.duplicate()
	while not queue.is_empty():
		var owner: int = queue.pop_front()
		for follower in LoyalistsScript.followers_of(state, owner):
			if follower in eligible and not follower in auto and not follower in result:
				result.append(follower)
				queue.append(follower)
	return result


# Call after anything that changes who can vote (an elimination): the vote may now be complete.
static func recheck(state: GameStateScript) -> Array:
	var events: Array = _maybe_resolve(state)
	state.event_log.append_array(events)
	return events


static func _maybe_resolve(state: GameStateScript) -> Array:
	if state.amend.get("phase", GameStateScript.AmendPhase.NONE) != GameStateScript.AmendPhase.VOTING:
		return []
	var auto: Array = _auto_voters(state)
	var following: Array = _auto_followers(state)
	for id in _eligible_voters(state):
		if not id in auto and not id in following and not state.amend["votes"].has(id):
			return []   # still waiting for someone
	return _resolve(state)


static func _resolve(state: GameStateScript) -> Array:
	var auto: Array = _auto_voters(state)
	var following: Array = _auto_followers(state)
	var keep: int = 0
	var against: int = following.size()   # the Loyalists of the union's members vote against, one each
	var revealed: Dictionary = {}
	for id in state.amend["votes"]:
		if id in auto or id in following:
			continue   # a vote cast before the union confronted no longer counts
		revealed[id] = state.amend["votes"][id]
		if state.amend["votes"][id]:
			keep += 1
		else:
			against += 1
	var multiplier: int = LawScript.get_int(state, "activistVote")
	against += auto.size() * multiplier

	var swing: int = GameDataScript.base_swing(_active_players(state).size())
	var delta: int = (keep - against) * swing
	for amender in _amenders(state):
		PopularityScript.change_base(state, amender, delta)

	var stands: bool = false
	match state.leader_type:
		GameStateScript.LeaderType.DICTATOR:
			stands = true          # a Dictator's amendment always stands
		GameStateScript.LeaderType.PRESIDENT:
			stands = keep > against   # needs more for than against
	var article_id: int = state.amend["article_id"]
	var new_words: Array = state.amend["new_words"]
	var events: Array = [EventsScript.make("amendment_resolved", {
		"article_id": article_id,
		"for": keep,
		"against": against,
		"auto_against": auto.size() * multiplier,
		"popularity_delta": delta,
		"stands": stands,
		"votes": revealed,
	})]
	if stands:
		state.articles[article_id] = new_words
		events.append(EventsScript.make("article_changed", {
			"article_id": article_id,
			"title": ConstitutionScript.title(article_id),
			"text": ConstitutionScript.to_text(new_words),
		}))
	_record(state, article_id, "stood" if stands else "rejected", keep, against, ConstitutionScript.to_text(new_words))
	state.amend = {}
	return events


# --- helpers ---------------------------------------------------------------------------

# Who amends: the Leader and, if there is one in the game, the Vice.
static func _amenders(state: GameStateScript) -> Array:
	var result: Array = [state.leader_id]
	if state.vice_id != -1 and not state.eliminated.get(state.vice_id, false):
		result.append(state.vice_id)
	return result


static func _active_players(state: GameStateScript) -> Array:
	var result: Array = []
	for id in state.player_ids:
		if not state.eliminated.get(id, false):
			result.append(id)
	return result


static func _record(state: GameStateScript, article_id: int, outcome: String, keep: int, against: int, text: String) -> void:
	state.amendment_record.append({
		"round": state.current_round,
		"leader": state.leader_id,
		"article_id": article_id,
		"outcome": outcome,
		"for": keep,
		"against": against,
		"text": text,
	})


static func _reject(player_id: int, reason: String) -> Dictionary:
	return EventsScript.make("rejected", {"reason": reason}, [player_id])
