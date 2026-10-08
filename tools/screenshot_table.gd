# Draws the table for N players with the real client code and saves a picture: godot --script tools/screenshot_table.gd -- 7 /tmp/table.png
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
	for id in ids:
		GameScript.handle(s, id, {"type": "cast_vote", "candidate": 2})
	GameScript.handle(s, 2, {"type": "pass_window"})
	s.sick[3] = true
	var model = SessionModelScript.new()
	model.seat = 1
	model.view = ViewsScript.state_view(s, 1)
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
