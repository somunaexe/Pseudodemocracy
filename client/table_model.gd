# What to draw for each seat and for the middle of the table, worked out from the view the server sent. Pure: no nodes.
# Everything shown here is public except what the server only tells this player; the server decides that, not the phone.

const GameStateScript = preload("res://scripts/game_state.gd")
const ConstitutionScript = preload("res://scripts/constitution.gd")

const ElectionPhase = GameStateScript.ElectionPhase
const TermPhase = GameStateScript.TermPhase


# One entry per seat in `order`, in that order.
static func seats(view: Dictionary, members: Array, me: int, order: Array) -> Array:
	var result: Array = []
	var performer: int = performing(view)
	for seat in order:
		var debts: Array = view.get("debts", {}).get(seat, [])
		var owed: int = 0
		for debt in debts:
			owed += int(debt["amount"])
		result.append({
			"seat": seat,
			"name": name_of(members, seat),
			"you": seat == me,
			"popularity": int(view.get("popularity", {}).get(seat, 0)),
			"psd": int(view.get("psd", {}).get(seat, 0)),
			"owed": owed,
			"leader": view.get("leader_id", -1) == seat,
			"vice": view.get("vice_id", -1) == seat,
			"sick": bool(view.get("sick", {}).get(seat, false)),
			"eliminated": bool(view.get("eliminated", {}).get(seat, false)),
			"frozen": view.get("frozen", {}).has(seat),
			"markers": int(view.get("markers", {}).get(seat, 0)),
			"roles": view.get("roles", {}).get(seat, []),
			"union": union_of(view, seat),
			"away": away(members, seat),
			"turn": seat == performer,
			"has_voted": voted(view, seat),
			"missed": int(view.get("missed_turns", {}).get(seat, 0)),
		})
	return result


static func name_of(members: Array, seat: int) -> String:
	for member in members:
		if int(member["seat"]) == seat:
			return str(member["name"])
	return "Player %d" % seat


static func away(members: Array, seat: int) -> bool:
	for member in members:
		if int(member["seat"]) == seat:
			return not bool(member["connected"])
	return false


# "activist" / "agbero" / "" and whether they run it.
static func union_of(view: Dictionary, seat: int) -> Dictionary:
	for id in view.get("unions", {}):
		var union: Dictionary = view["unions"][id]
		if seat in union["members"]:
			return {"type": "activist" if int(union["type"]) == GameStateScript.UnionType.ACTIVIST else "agbero", "owner": union["owner"] == seat}
	return {}


# The player whose turn it is, or -1.
static func performing(view: Dictionary) -> int:
	var term: Dictionary = view.get("term", {})
	if int(term.get("phase", TermPhase.NONE)) == TermPhase.TURNS and not term.get("waiting", []).is_empty():
		return int(term["waiting"][0])
	return -1


# Has this seat already voted in whatever vote is open (election, performance)? Their choice is never in the view.
static func voted(view: Dictionary, seat: int) -> bool:
	var election: Dictionary = view.get("election", {})
	if not election.is_empty() and seat in election.get("voted", []):
		return true
	var act: Dictionary = view.get("term", {}).get("act", {})
	return not act.is_empty() and seat in act.get("voted", [])


# The middle of the table.
static func centre(view: Dictionary, members: Array) -> Dictionary:
	var headline: String = "Waiting…"
	var election: Dictionary = view.get("election", {})
	var term: Dictionary = view.get("term", {})
	if view.get("game_over", false):
		headline = "Game over"
	elif not election.is_empty():
		match int(election.get("phase", ElectionPhase.NONE)):
			ElectionPhase.EXAM_WRITING: headline = "Election: %s is writing the exam" % name_of(members, int(view.get("leader_id", -1)))
			ElectionPhase.EXAM_ANSWERING: headline = "Election: the exam"
			ElectionPhase.VOTING: headline = "Election: vote for a Leader"
			_: headline = "Election"
	else:
		match int(term.get("phase", TermPhase.NONE)):
			TermPhase.INAUGURATION: headline = "Inauguration"
			TermPhase.TURNS:
				var who: int = performing(view)
				headline = "%s's turn" % name_of(members, who) if who != -1 else "Turns"
			TermPhase.FAREWELL: headline = "Farewell"
	return {
		"headline": headline,
		"round": int(view.get("current_round", 1)),
		"treasury": int(view.get("treasury", 0)),
		"leader_name": name_of(members, int(view.get("leader_id", -1))) if int(view.get("leader_id", -1)) != -1 else "",
	}


# The Constitution as lines: each article's number, title and current wording.
static func articles(view: Dictionary) -> Array:
	var lines: Array = []
	var ids: Array = view.get("articles", {}).keys()
	ids.sort()
	for id in ids:
		lines.append({"id": id, "title": ConstitutionScript.title(int(id)), "text": ConstitutionScript.to_text(view["articles"][id])})
	return lines
