# The exam, from the phone's side. Pure (no nodes), so it is tested against the real server.
#
# The LEADER picks 5 to 10 prepared questions from the bank and marks their own true answer to each; pressing "Lock in" sends
# the picks and the server seals the answers away for good: nobody, the Leader included, can change them or see them before the
# marking. The TAKERS see only the questions and tick one option for each. Nothing here knows the answer key: it never reaches
# the phone.

const GameStateScript = preload("res://scripts/game_state.gd")
const ExamBankScript = preload("res://scripts/exam_bank.gd")
const GameDataScript = preload("res://scripts/game_data.gd")

const ElectionPhase = GameStateScript.ElectionPhase


# Which exam screen this player needs right now: "write" (the Leader picking), "answer" (a taker answering) or "".
static func mode(view: Dictionary, me: int) -> String:
	var election: Dictionary = view.get("election", {})
	if election.is_empty():
		return ""
	match int(election.get("phase", ElectionPhase.NONE)):
		ElectionPhase.EXAM_WRITING:
			return "write" if int(view.get("leader_id", -1)) == me else ""
		ElectionPhase.EXAM_ANSWERING:
			if me in election.get("takers", []) and not me in election.get("answered", []):
				return "answer"
	return ""


static func seconds_left(view: Dictionary, elapsed_ms: int) -> int:
	var election: Dictionary = view.get("election", {})
	if not election.has("deadline"):
		return -1
	return maxi(0, int(ceil(float(int(election["deadline"]) - int(view.get("clock_ms", 0)) - elapsed_ms) / 1000.0)))


static func min_questions() -> int:
	return GameDataScript.get_int("examQuestions")


static func max_questions() -> int:
	return GameDataScript.get_int("examMaxQuestions")


# --- the Leader's side -------------------------------------------------------------------------

# picks: the exam so far, in the order the questions were added. Each is either a bank question { "id", "answer" } or one the
# Leader typed { "text", "options", "answer" }; answer is -1 until the Leader marks their true option.
static func is_typed(pick: Dictionary) -> bool:
	return pick.has("text")


# Why a typed question can't be added yet ("" = fine): the same limits the server enforces.
static func typed_problem(text: String, options: Array) -> String:
	var max_text: int = GameDataScript.get_int("examTextMax")
	if text.strip_edges().is_empty():
		return "Type the question."
	if text.strip_edges().length() > max_text:
		return "A question can be at most %d characters." % max_text
	var seen: Array = []
	for option in options:
		var clean: String = str(option).strip_edges()
		if clean.is_empty():
			continue
		if clean in seen:
			return "Two options are the same."
		seen.append(clean)
	if seen.size() < GameDataScript.get_int("examOptions"):
		return "Give at least %d options." % GameDataScript.get_int("examOptions")
	return ""


# Adds a question the Leader typed (blank options dropped). Returns the new picks, or the old ones if it can't be added.
static func add_typed(picks: Array, text: String, options: Array) -> Array:
	if typed_problem(text, options) != "" or picks.size() >= max_questions():
		return picks.duplicate(true)
	var clean: Array = []
	for option in options:
		if str(option).strip_edges() != "":
			clean.append(str(option).strip_edges())
	var result: Array = picks.duplicate(true)
	result.append({"text": text.strip_edges(), "options": clean.slice(0, GameDataScript.get_int("examMaxOptions")), "answer": -1})
	return result


static func remove_at(picks: Array, index: int) -> Array:
	var result: Array = picks.duplicate(true)
	if index >= 0 and index < result.size():
		result.remove_at(index)
	return result


# Mark which option is TRUE for you on the question at this position in the exam.
static func mark_at(picks: Array, index: int, answer: int) -> Array:
	var result: Array = picks.duplicate(true)
	if index >= 0 and index < result.size():
		result[index]["answer"] = answer
	return result


static func writer_state(picks: Array) -> Dictionary:
	var answered: int = 0
	for pick in picks:
		if int(pick["answer"]) >= 0:
			answered += 1
	var enough: bool = picks.size() >= min_questions() and picks.size() <= max_questions()
	var ready: bool = enough and answered == picks.size()
	var note: String = "%d questions (%d to %d), %d answered" % [picks.size(), min_questions(), max_questions(), answered]
	return {"picked": picks.size(), "answered": answered, "ready": ready, "note": note, "command": lock_command(picks) if ready else {}}


static func lock_command(picks: Array) -> Dictionary:
	return {"type": "write_exam", "picks": picks.map(func(pick): return {"text": pick["text"], "options": pick["options"], "answer": int(pick["answer"])} if is_typed(pick) else {"id": int(pick["id"]), "answer": int(pick["answer"])})}


# Tap a bank question: it joins the exam (unmarked), or leaves it. Returns the new picks.
static func toggle(picks: Array, id: int) -> Array:
	var result: Array = []
	var found: bool = false
	for pick in picks:
		if not is_typed(pick) and int(pick["id"]) == id:
			found = true
		else:
			result.append(pick)
	if not found:
		if picks.size() >= max_questions():
			return picks.duplicate(true)   # the exam is full: take one out first
		result = picks.duplicate(true)
		result.append({"id": id, "answer": -1})
	return result


# The question as shown: the bank's wording or the typed one.
static func shown(pick: Dictionary) -> Dictionary:
	if is_typed(pick):
		return {"text": pick["text"], "options": pick["options"]}
	return ExamBankScript.question(int(pick["id"]))


static func bank() -> Array:
	return ExamBankScript.all()


# --- a taker's side ----------------------------------------------------------------------------

static func questions(view: Dictionary) -> Array:
	return view.get("election", {}).get("exam", {}).get("questions", [])


static func taker_state(view: Dictionary, answers: Array) -> Dictionary:
	var total: int = questions(view).size()
	var given: int = 0
	for answer in answers:
		if int(answer) >= 0:
			given += 1
	var ready: bool = total > 0 and answers.size() == total and given == total
	return {"total": total, "given": given, "ready": ready, "note": "%d of %d answered" % [given, total], "command": {"type": "answer_exam", "answers": answers.map(func(a): return int(a))} if ready else {}}


# A fresh, empty set of answers for the exam in this view.
static func blank_answers(view: Dictionary) -> Array:
	var result: Array = []
	for i in questions(view).size():
		result.append(-1)
	return result
