# Draws the table for N players with the real client code and saves a picture:
#   xvfb-run -a godot --rendering-driver opengl3 --resolution 1280x720 --script tools/screenshot_table.gd -- 7 /tmp/table.png [perform|vote|result|choice|debate]
# The last word picks the moment shown in the dock (default: your own performance).
# Needs a display (xvfb-run -a godot ...), so it is a look-at-it tool, not part of the test run.
extends SceneTree

const GameScript = preload("res://scripts/game.gd")
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
	var s := GameScript.new_game(ids, 7)
	s.decks["performance"] = [20]
	for id in ids:
		GameScript.handle(s, id, {"type": "cast_vote", "candidate": 2})
	GameScript.handle(s, 2, {"type": "pass_window"})
	s.sick[3] = true
	var mode: String = args[2] if args.size() > 2 else "perform"
	var performer: int = s.term["waiting"][0]
	var me: int = performer
	match mode:
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


func _process(_delta: float) -> bool:
	frames += 1
	if frames == 5:
		get_root().get_texture().get_image().save_png(path)
		quit(0)
	return false
