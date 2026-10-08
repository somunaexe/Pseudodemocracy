# The amendment sheet: a full-screen page for the Leader (or the Vice): pick an article, TAP a highlighted word, TAP one of the
# values it may take, then propose. Everything it offers comes from AmendModel; nothing is typed.
extends Control

const SessionModelScript = preload("res://client/session_model.gd")
const AmendModelScript = preload("res://client/amend_model.gd")
const ConstitutionScript = preload("res://scripts/constitution.gd")

signal command_requested(command: Dictionary)

const BOUND := Color(0.20, 0.45, 0.85)
const CHANGED := Color(0.15, 0.62, 0.30)
const PLAIN := Color(0.22, 0.24, 0.30)

var model = SessionModelScript.new()
var is_open: bool = false
var article_id: int = -1          # -1: choosing an article
var edits: Dictionary = {}        # word index -> new text
var tapped: int = -1              # the word whose values are showing
var drawn_for: String = ""
var title_label: Label
var body: VBoxContainer
var footer: HBoxContainer


func _build() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	var back := ColorRect.new()
	back.color = Color(0.06, 0.07, 0.10, 1.0)
	back.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(back)
	var column := VBoxContainer.new()
	column.position = Vector2(24, 12)
	column.size = Vector2(1232, 696)
	column.add_theme_constant_override("separation", 8)
	add_child(column)
	title_label = Label.new()
	title_label.add_theme_font_size_override("font_size", 30)
	column.add_child(title_label)
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	column.add_child(scroll)
	body = VBoxContainer.new()
	body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	body.add_theme_constant_override("separation", 12)
	scroll.add_child(body)
	footer = HBoxContainer.new()
	footer.alignment = BoxContainer.ALIGNMENT_CENTER
	footer.add_theme_constant_override("separation", 30)
	column.add_child(footer)


func open() -> void:
	is_open = true
	article_id = -1
	edits = {}
	tapped = -1
	drawn_for = ""
	refresh()


func close() -> void:
	is_open = false
	refresh()


# Keeps the sheet current. It closes by itself once the window is gone (the proposal went out, or time ran out).
func refresh() -> void:
	if body == null:
		_build()
	var view: Dictionary = model.view
	if is_open and (view.is_empty() or AmendModelScript.my_window(view, model.seat) == -1):
		is_open = false
	visible = is_open
	if not is_open:
		drawn_for = ""
		return
	var signature: String = "%d|%s|%d" % [article_id, JSON.stringify(edits), tapped]
	if signature == drawn_for:
		return
	drawn_for = signature
	for child in body.get_children():
		body.remove_child(child)
		child.queue_free()
	for child in footer.get_children():
		footer.remove_child(child)
		child.queue_free()
	title_label.text = "Amend the Constitution (%s window)" % AmendModelScript.window_name(AmendModelScript.my_window(view, model.seat))
	if article_id == -1:
		_draw_articles(view)
	else:
		_draw_article(view)


func _draw_articles(view: Dictionary) -> void:
	body.add_child(_label("Choose an article. You change it by tapping the highlighted words that have a rule attached. This uses up the window whether or not the amendment passes, and a failed one costs you a fine and popularity.", 18))
	for article in AmendModelScript.amendable_articles(view):
		var button := Button.new()
		button.text = "Article %d, %s: %s" % [article["id"], article["title"], article["text"]]
		button.alignment = HORIZONTAL_ALIGNMENT_LEFT
		button.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		button.custom_minimum_size.y = 64
		_style(button, PLAIN, 18)
		button.pressed.connect(func(): article_id = article["id"]; edits = {}; tapped = -1; refresh())
		body.add_child(button)
	footer.add_child(_button("Close", PLAIN, func(): close()))


func _draw_article(view: Dictionary) -> void:
	body.add_child(_label("Article %d, %s" % [article_id, ConstitutionScript.title(article_id)], 24))
	body.add_child(_label("Tap a blue word to change it. Grey highlighted words have no rule attached yet, so they can't be changed from here.", 16))
	var flow := HFlowContainer.new()
	flow.add_theme_constant_override("h_separation", 8)
	flow.add_theme_constant_override("v_separation", 8)
	body.add_child(flow)
	var words: Array = AmendModelScript.words(view, article_id)
	for word in words:
		var shown: String = str(edits.get(word["index"], word["text"]))
		if word["kind"] == "bound":
			var chip := Button.new()
			chip.text = shown
			chip.custom_minimum_size = Vector2(60, 56)
			_style(chip, CHANGED if edits.has(word["index"]) else BOUND, 24)
			var index: int = word["index"]
			chip.pressed.connect(func(): tapped = index if tapped != index else -1; refresh())
			flow.add_child(chip)
		else:
			var plain := _label(shown, 24)
			plain.autowrap_mode = TextServer.AUTOWRAP_OFF   # a word must never wrap letter by letter inside the flow
			plain.custom_minimum_size.y = 56
			plain.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
			if word["kind"] == "unbound":
				plain.add_theme_color_override("font_color", Color(0.65, 0.65, 0.35))
			flow.add_child(plain)
	if tapped != -1:
		var picked: Dictionary = words[tapped]
		var current: String = str(picked["text"])
		body.add_child(_label("%s: choose a value" % picked["binding"]["label"], 20))
		var row := HFlowContainer.new()
		row.add_theme_constant_override("h_separation", 14)
		row.add_theme_constant_override("v_separation", 10)
		body.add_child(row)
		for option in AmendModelScript.options(picked["binding"], current, view):
			var button := Button.new()
			button.text = ("now: " if option == current else "") + option
			button.custom_minimum_size = Vector2(130, 56)
			_style(button, CHANGED if str(edits.get(tapped, current)) == option else PLAIN, 22)
			var value: String = option
			button.pressed.connect(func(): _choose(tapped, value, current))
			row.add_child(button)
	body.add_child(_label("New wording: " + AmendModelScript.text_with(view, article_id, edits), 22))
	footer.add_child(_button("Back", PLAIN, func(): article_id = -1; edits = {}; tapped = -1; refresh()))
	var propose := _button("Propose this change", CHANGED, func(): command_requested.emit(AmendModelScript.propose_command(model.view, article_id, edits)))
	propose.disabled = edits.is_empty()
	footer.add_child(propose)


func _choose(index: int, value: String, current: String) -> void:
	if value == current:
		edits.erase(index)
	else:
		edits[index] = value
	tapped = -1
	refresh()


func _label(text: String, size: int) -> Label:
	var label := Label.new()
	label.text = text
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.add_theme_font_size_override("font_size", size)
	return label


func _button(text: String, colour: Color, action: Callable) -> Button:
	var button := Button.new()
	button.text = text
	button.custom_minimum_size = Vector2(300, 64)
	_style(button, colour, 24)
	button.pressed.connect(action)
	return button


func _style(button: Button, colour: Color, size: int) -> void:
	for state_name in ["normal", "hover", "pressed", "disabled", "focus"]:
		var box := StyleBoxFlat.new()
		box.bg_color = colour.lightened(0.18) if state_name == "pressed" else (colour.darkened(0.5) if state_name == "disabled" else colour)
		box.set_corner_radius_all(10)
		box.content_margin_left = 14
		box.content_margin_right = 14
		button.add_theme_stylebox_override(state_name, box)
	button.add_theme_color_override("font_color", Color.WHITE)
	button.add_theme_color_override("font_disabled_color", Color(0.8, 0.8, 0.8))
	button.add_theme_font_size_override("font_size", size)
