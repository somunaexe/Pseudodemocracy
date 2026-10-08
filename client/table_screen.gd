# The table: everyone round an oval, the middle of the table, the menu bar and the Constitution. Landscape, for a phone held
# sideways. It only DRAWS the session model (what the server told this player) and emits what the player pressed.
extends Control

const SessionModelScript = preload("res://client/session_model.gd")
const TableLayoutScript = preload("res://client/table_layout.gd")
const TableModelScript = preload("res://client/table_model.gd")

signal constitution_requested

const FONT := 22
const SMALL := 17
const TABLE_COLOUR := Color(0.10, 0.34, 0.24)
const RIM_COLOUR := Color(0.36, 0.22, 0.10)
const BADGE_COLOUR := Color(0.13, 0.14, 0.17)
const TURN_COLOUR := Color(0.95, 0.75, 0.15)
const YOU_COLOUR := Color(0.35, 0.65, 0.95)
const GONE_COLOUR := Color(0.35, 0.35, 0.35)

var model = SessionModelScript.new()
var badges: Dictionary = {}      # seat -> Panel
var top_label: Label
var centre_label: Label
var constitution_button: Button
var overlay: Panel
var overlay_text: RichTextLabel
var seat_order: Array = []


func _ready() -> void:
	refresh()


func _build() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	var theme := Theme.new()
	theme.default_font_size = FONT
	self.theme = theme
	top_label = Label.new()
	top_label.position = Vector2(16, 14)
	top_label.size = Vector2(900, 40)
	add_child(top_label)
	constitution_button = Button.new()
	constitution_button.text = "Constitution"
	constitution_button.position = Vector2(1280 - 216, 8)
	constitution_button.size = Vector2(200, 48)
	constitution_button.pressed.connect(_toggle_constitution)
	add_child(constitution_button)
	centre_label = Label.new()
	centre_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	centre_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	centre_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	add_child(centre_label)
	overlay = Panel.new()
	overlay.position = Vector2(120, 70)
	overlay.size = Vector2(1040, 600)
	overlay.visible = false
	add_child(overlay)
	overlay_text = RichTextLabel.new()
	overlay_text.position = Vector2(20, 16)
	overlay_text.size = Vector2(1000, 568)
	overlay_text.bbcode_enabled = false
	overlay.add_child(overlay_text)


func _toggle_constitution() -> void:
	overlay.visible = not overlay.visible
	if overlay.visible:
		var text: String = ""
		for line in TableModelScript.articles(model.view):
			text += "Article %d%s\n%s\n\n" % [line["id"], (" – " + line["title"]) if line["title"] != "" else "", line["text"]]
		overlay_text.text = text
	constitution_requested.emit()


func _draw() -> void:
	var area: Rect2 = TableLayoutScript.table_area()
	var centre: Vector2 = area.get_center()
	var rx: float = area.size.x / 2.0 - 8.0
	var ry: float = area.size.y / 2.0 - 8.0
	draw_colored_polygon(_ellipse(centre, rx, ry), RIM_COLOUR)
	draw_colored_polygon(_ellipse(centre, rx - 14.0, ry - 14.0), TABLE_COLOUR)


func _ellipse(centre: Vector2, rx: float, ry: float) -> PackedVector2Array:
	var points := PackedVector2Array()
	for i in 72:
		var angle: float = TAU * float(i) / 72.0
		points.append(centre + Vector2(cos(angle) * rx, sin(angle) * ry))
	return points


# Draws whatever the model says right now.
func refresh() -> void:
	if top_label == null:
		_build()
	var view: Dictionary = model.view
	if view.is_empty():
		top_label.text = "Waiting for the table…"
		return
	var order: Array = TableLayoutScript.order_from(view["player_ids"], model.seat)
	var count: int = order.size()
	var size: Vector2 = TableLayoutScript.badge_size(count)
	var spots: Array = TableLayoutScript.positions(count)
	var seats: Array = TableModelScript.seats(view, model.members, model.seat, order)
	var centre: Dictionary = TableModelScript.centre(view, model.members)
	top_label.text = "Round %d     Treasury %s PSD%s" % [centre["round"], _money(centre["treasury"]), ("     Leader: " + centre["leader_name"]) if centre["leader_name"] != "" else ""]
	centre_label.text = centre["headline"]
	centre_label.size = Vector2(420, 120)
	centre_label.position = TableLayoutScript.table_area().get_center() - centre_label.size / 2.0
	for seat in badges.keys():
		if not seat in order:
			badges[seat].queue_free()
			badges.erase(seat)
	for i in count:
		var info: Dictionary = seats[i]
		if not badges.has(info["seat"]):
			badges[info["seat"]] = _make_badge()
		var badge: Panel = badges[info["seat"]]
		badge.size = size
		badge.position = spots[i] - size / 2.0
		_fill_badge(badge, info)
	queue_redraw()


func _make_badge() -> Panel:
	var badge := Panel.new()
	add_child(badge)
	var label := Label.new()
	label.name = "Text"
	label.position = Vector2(8, 4)
	label.autowrap_mode = TextServer.AUTOWRAP_OFF
	label.add_theme_font_size_override("font_size", SMALL)
	badge.add_child(label)
	return badge


# Name on top, then popularity and money, then tags (crown, sick, roles ...).
func _fill_badge(badge: Panel, info: Dictionary) -> void:
	var style := StyleBoxFlat.new()
	style.bg_color = BADGE_COLOUR if not info["eliminated"] else GONE_COLOUR
	style.set_corner_radius_all(14)
	style.set_border_width_all(4 if (info["turn"] or info["you"]) else 1)
	style.border_color = TURN_COLOUR if info["turn"] else (YOU_COLOUR if info["you"] else Color(0.5, 0.5, 0.5))
	badge.add_theme_stylebox_override("panel", style)
	var label: Label = badge.get_node("Text")
	label.size = badge.size - Vector2(16, 8)
	var tags: Array = []
	if info["leader"]: tags.append("Leader")
	if info["vice"]: tags.append("Vice")
	if info["sick"]: tags.append("sick")
	if info["frozen"]: tags.append("frozen")
	if info["markers"] > 0: tags.append("%d marker%s" % [info["markers"], "" if info["markers"] == 1 else "s"])
	if not info["union"].is_empty(): tags.append(("Unionizer" if info["union"]["owner"] else "") if info["union"]["type"] == "activist" else ("Capon" if info["union"]["owner"] else "mob"))
	if info["eliminated"]: tags = ["out"]
	if info["away"]: tags.append("away")
	if info["has_voted"]: tags.append("voted")
	tags = tags.filter(func(tag): return tag != "")
	for role in info["roles"]:
		tags.append(str(role))
	label.text = "%s%s\nPop %d   %s PSD%s\n%s" % [info["name"], "  (you)" if info["you"] else "", info["popularity"], _money(info["psd"]), ("  owes " + _money(info["owed"])) if info["owed"] > 0 else "", ", ".join(tags)]


static func _money(amount: int) -> String:
	return str(amount)
