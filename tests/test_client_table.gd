extends SceneTree

const GameScript = preload("res://scripts/game.gd")
const ViewsScript = preload("res://scripts/views.gd")
const LayoutScript = preload("res://client/table_layout.gd")
const TableModelScript = preload("res://client/table_model.gd")
const TableScreenScript = preload("res://client/table_screen.gd")
const SessionModelScript = preload("res://client/session_model.gd")
const GameStateScript = preload("res://scripts/game_state.gd")

var failures: int = 0


func _init() -> void:
	layout()
	model()
	screen()
	print("%d failure(s)" % failures)
	quit(1 if failures > 0 else 0)


func layout() -> void:
	var area: Rect2 = LayoutScript.table_area()
	expect("the table is on a sideways phone screen", [LayoutScript.SCREEN, area.position.y], [Vector2(1280, 720), 64.0])
	for count in range(3, 11):
		var spots: Array = LayoutScript.positions(count)
		var size: Vector2 = LayoutScript.badge_size(count)
		var inside: bool = true
		var apart: bool = true
		for i in count:
			var box := Rect2(spots[i] - size / 2.0, size)
			inside = inside and area.encloses(box) and Rect2(Vector2.ZERO, LayoutScript.SCREEN).encloses(box)
			for j in range(i + 1, count):
				apart = apart and not box.intersects(Rect2(spots[j] - size / 2.0, size))
		expect("%d players: every badge is on the screen" % count, inside, true)
		expect("%d players: no two badges overlap" % count, apart, true)
		var clear: bool = true
		for i in count:
			var box := Rect2(spots[i] - size / 2.0, size)
			clear = clear and not box.intersects(LayoutScript.right_dock()) and not box.intersects(LayoutScript.left_dock())
		expect("%d players: nobody sits in the docks beside your badge" % count, clear, true)
		expect("%d players: you sit at the bottom middle" % count, [absf(spots[0].x - 640.0) < 0.01, spots[0].y > area.get_center().y], [true, true])
	var one: Array = LayoutScript.positions(4)
	expect("the next seat clockwise is on your left, and the one opposite is at the top", [one[1].x < 640.0, one[2].y < one[0].y, absf(one[2].x - 640.0) < 0.01, one[3].x > 640.0], [true, true, true, true])
	expect("the docks are the bottom corners, either side of you", [LayoutScript.right_dock().position.x > 640.0, LayoutScript.left_dock().end.x < 640.0, LayoutScript.right_dock().end.y <= 720.0], [true, true, true])
	expect("everyone sees the same order from their own place", [LayoutScript.order_from([1, 2, 3, 4, 5], 3), LayoutScript.order_from([1, 2, 3, 4, 5], 1), LayoutScript.order_from([1, 2, 3], 99)], [[3, 4, 5, 1, 2], [1, 2, 3, 4, 5], [1, 2, 3]])


func started_view(me: int) -> Dictionary:
	var s := GameScript.new_game([1, 2, 3, 4, 5], 7)
	for id in [1, 2, 3, 4, 5]:
		GameScript.handle(s, id, {"type": "cast_vote", "candidate": 2})
	s.sick[3] = true
	s.markers[4] = 2
	s.psd[5] = 640
	s.roles[1] = ["Doctor"]
	s.unions[1] = {"type": GameStateScript.UnionType.AGBERO, "owner": 4, "members": [4, 5], "confront_used": false}
	GameScript.handle(s, 2, {"type": "pass_window"})
	return ViewsScript.state_view(s, me)


func members() -> Array:
	return [{"seat": 1, "name": "Ada", "connected": true}, {"seat": 2, "name": "Bola", "connected": true}, {"seat": 3, "name": "Chi", "connected": false}, {"seat": 4, "name": "Dayo", "connected": true}, {"seat": 5, "name": "Efe", "connected": true}]


func model() -> void:
	var view := started_view(1)
	var seats: Array = TableModelScript.seats(view, members(), 1, [1, 2, 3, 4, 5])
	expect("the first badge is you", [seats[0]["you"], seats[0]["name"], seats[1]["you"]], [true, "Ada", false])
	expect("the Leader is marked", [seats[1]["leader"], seats[0]["leader"]], [true, false])
	expect("sickness, markers, money, roles show", [seats[2]["sick"], seats[3]["markers"], seats[4]["psd"], seats[0]["roles"]], [true, 2, int(view["psd"][5]), ["Doctor"]])
	expect("an absent player is marked away", [seats[2]["away"], seats[1]["away"]], [true, false])
	expect("a mob is shown, with its Capon", [seats[3]["union"], seats[4]["union"]], [{"type": "agbero", "owner": true}, {"type": "agbero", "owner": false}])
	expect("a name for a seat nobody described", TableModelScript.name_of([], 4), "Player 4")
	var centre: Dictionary = TableModelScript.centre(view, members())
	expect("the middle says the round, the treasury and the Leader", [centre["round"], centre["treasury"] > 0, centre["leader_name"]], [1, true, "Bola"])
	expect("... and whose turn it is once the turns begin", centre["headline"], "Bola's turn")
	var election_view := ViewsScript.state_view(GameScript.new_game([1, 2, 3], 3), 1)
	expect("the first election is announced", TableModelScript.centre(election_view, members().slice(0, 3))["headline"], "Election: vote for a Leader")
	expect("the Constitution is listed article by article with its wording", [TableModelScript.articles(view).size() > 20, TableModelScript.articles(view)[0]["text"].length() > 0], [true, true])
	var s := GameScript.new_game([1, 2, 3, 4, 5], 7)
	GameScript.handle(s, 1, {"type": "cast_vote", "candidate": 2})
	expect("who has voted shows, never for whom", [TableModelScript.voted(ViewsScript.state_view(s, 3), 1), TableModelScript.voted(ViewsScript.state_view(s, 3), 2)], [true, false])


func screen() -> void:
	var table = TableScreenScript.new()
	table.model = SessionModelScript.new()
	get_root().add_child(table)
	table.refresh()
	expect("with no view yet it says it is waiting", table.top_label.text, "Waiting for the table…")
	table.model.seat = 3
	table.model.members = members()
	table.model.view = started_view(3)
	table.refresh()
	expect("one badge per player", table.badges.size(), 5)
	expect("your badge is at the bottom middle", [absf(table.badges[3].position.x + table.badges[3].size.x / 2.0 - 640.0) < 0.5, table.badges[3].position.y > 360.0], [true, true])
	expect("the badge text carries name, popularity, money and tags", table.badges[4].get_node("Text").text.contains("Dayo") and table.badges[4].get_node("Text").text.contains("2 markers"), true)
	expect("the top bar shows the round, treasury and Leader", table.top_label.text.contains("Round 1") and table.top_label.text.contains("Leader: Bola"), true)
	table.constitution_button.pressed.emit()
	expect("the Constitution opens as a panel, and closes again", [table.overlay.visible, table.overlay_text.text.begins_with("Article 1")], [true, true])
	table.constitution_button.pressed.emit()
	expect("... closed", table.overlay.visible, false)
	table.model.view["eliminated"] = {2: true}
	table.refresh()
	expect("an eliminated player's badge says so", table.badges[2].get_node("Text").text.contains("out"), true)
	table.queue_free()


func expect(label: String, actual: Variant, wanted: Variant) -> void:
	var ok: bool = typeof(actual) == typeof(wanted) and actual == wanted
	if not ok:
		failures += 1
	print(("PASS " if ok else "FAIL ") + label + " -> " + str(actual).left(90))
