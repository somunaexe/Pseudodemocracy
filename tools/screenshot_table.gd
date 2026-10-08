# Draws the table for N players with the real client code and saves a picture:
#   xvfb-run -a godot --rendering-driver opengl3 --resolution 1280x720 --script tools/screenshot_table.gd -- 7 /tmp/table.png [perform|vote|result|choice|debate|exam_write|exam_take|ballot]
# The last word picks the moment shown in the dock (default: your own performance).
# Needs a display (xvfb-run -a godot ...), so it is a look-at-it tool, not part of the test run.
extends SceneTree

const GameScript = preload("res://scripts/game.gd")
const GameStateScript = preload("res://scripts/game_state.gd")
const AmendModelScript = preload("res://client/amend_model.gd")
const ElectionScript = preload("res://scripts/election.gd")
const ViewsScript = preload("res://scripts/views.gd")
const TableScreenScript = preload("res://client/table_screen.gd")
const SessionModelScript = preload("res://client/session_model.gd")

var frames := 0
var path := "/tmp/table.png"


func _init() -> void:
	var args: PackedStringArray = OS.get_cmdline_user_args()
	var count: int = int(args[0]) if args.size() > 0 else 5
	if args.size() > 1:
		path = args[1]
	var ids: Array = range(1, count + 1)
	var mode: String = args[2] if args.size() > 2 else "perform"
	var amending: bool = mode in ["window", "amend_sheet", "amend_vote", "cosign"]
	var s: GameStateScript = null
	for seed_value in range(7, 400):
		s = GameScript.new_game(ids, seed_value)
		for id in ids:
			GameScript.handle(s, id, {"type": "cast_vote", "candidate": 2})
		if not amending or s.leader_type == GameStateScript.LeaderType.PRESIDENT:   # a Commander can't amend
			break
	s.decks["performance"] = [20]
	var me: int = 1
	var performer: int = 2
	if not amending:
		GameScript.handle(s, 2, {"type": "pass_window"})
		performer = s.term["waiting"][0]
		me = performer
	s.sick[3] = true
	match mode:
		"window":
			me = 2
		"amend_sheet":
			me = 2
		"cosign":
			s.vice_id = 3
			s.sick[3] = false
			GameScript.handle(s, 2, {"type": "propose", "window": 0, "article_id": 2, "new_texts": AmendModelScript.propose_command(ViewsScript.state_view(s, 2), 2, {tax_rate_index(s): "25%"})["new_texts"]})
			me = 3
		"amend_vote":
			GameScript.handle(s, 2, {"type": "propose", "window": 0, "article_id": 2, "new_texts": AmendModelScript.propose_command(ViewsScript.state_view(s, 2), 2, {tax_rate_index(s): "25%"})["new_texts"]})
			me = 1
		"vote":
			GameScript.handle(s, performer, {"type": "finish_performance"})
			me = 1 if performer != 1 else 3
		"result":
			GameScript.handle(s, performer, {"type": "finish_performance"})
			for id in ids:
				if id != performer:
					GameScript.handle(s, id, {"type": "performance_vote", "good": id % 2 == 0})
		"choice":
			s.choice = {"player": performer, "subject": performer, "deck": "settlement", "card": 22, "kind": "option", "labels": ["Gain 15 popularity", "Take 150 PSD"], "deadline": s.clock_ms + 10000, "prompt": "Pick your reward."}
		"debate":
			s.term["act"]["debate"] = {"rival": 0, "topic": "", "side": -1}
		"exam_write", "exam_take", "ballot":
			s.term = {}
			ElectionScript.begin(s, "term_ended")
			me = s.leader_id if mode == "exam_write" else 1
			if mode != "exam_write":
				var picks: Array = []
				for i in 5:
					picks.append({"id": i * 3, "answer": i % 3})
				GameScript.handle(s, s.leader_id, {"type": "write_exam", "picks": picks})
			if mode == "ballot":
				for id in ids:
					if id != s.leader_id:
						GameScript.handle(s, id, {"type": "answer_exam", "answers": [0, 1, 2, 0, 1]})
	var model = SessionModelScript.new()
	model.seat = me
	model.view = ViewsScript.state_view(s, me)
	var names := ["Ada", "Bolanle", "Chidi", "Dayo", "Efe", "Funmi", "Gbenga", "Hauwa", "Ikenna", "Jumoke"]
	for id in ids:
		model.members.append({"seat": id, "name": names[id - 1], "connected": id != 4})
	var table = TableScreenScript.new()
	table.model = model
	get_root().add_child(table)
	table.refresh()
	if mode == "amend_sheet":
		table.amend_sheet.open()
		table.amend_sheet.article_id = 2
		table.amend_sheet.edits = {tax_rate_index(s): "25%"}
		table.amend_sheet.tapped = tax_rate_index(s)
		table.amend_sheet.drawn_for = ""
		table.amend_sheet.refresh()


func _process(_delta: float) -> bool:
	frames += 1
	if frames == 5:
		get_root().get_texture().get_image().save_png(path)
		quit(0)
	return false


# The position of the tax rate ("20%") among the words of Article 2.
func tax_rate_index(s: GameStateScript) -> int:
	return AmendModelScript.words(ViewsScript.state_view(s, 2), 2).filter(func(w): return w["kind"] == "bound")[0]["index"]
