# The exam sheet: a full-screen page over the table. The Leader builds their exam (prepared questions to tick, or their own typed
# ones) and LOCKS it; a taker answers it. All the rules are in ExamModel and on the server; this only draws and sends.
extends Control

const SessionModelScript = preload("res://client/session_model.gd")
const ExamModelScript = preload("res://client/exam_model.gd")

signal command_requested(command: Dictionary)

const PICKED := Color(0.20, 0.45, 0.85)
const TRUE_ANSWER := Color(0.15, 0.62, 0.30)
const PLAIN := Color(0.22, 0.24, 0.30)

var model = SessionModelScript.new()
var picks: Array = []             # the Leader's exam so far
var answers: Array = []           # a taker's answers so far
var confirming: bool = false      # the Leader pressed "Lock in" and is being asked to be sure
var drawn_for: String = ""        # which page is on screen, so a refresh does not rebuild it (and eat a press)
var title_label: Label
var clock_label: Label
var note_label: Label
var body: VBoxContainer
var footer: HBoxContainer
var typed_text: LineEdit
var typed_options: Array = []
var typed_message: Label
var typed_draft: Dictionary = {"text": "", "options": ["", "", ""]}   # what is typed so far survives a redraw


func _ready() -> void:
	refresh()


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
	var head := HBoxContainer.new()
	column.add_child(head)
	title_label = Label.new()
	title_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title_label.add_theme_font_size_override("font_size", 30)
	head.add_child(title_label)
	note_label = Label.new()
	note_label.add_theme_font_size_override("font_size", 20)
	head.add_child(note_label)
	clock_label = Label.new()
	clock_label.custom_minimum_size.x = 110
	clock_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	clock_label.add_theme_font_size_override("font_size", 30)
	head.add_child(clock_label)
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	column.add_child(scroll)
	body = VBoxContainer.new()
	body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	body.add_theme_constant_override("separation", 10)
	scroll.add_child(body)
	footer = HBoxContainer.new()
	footer.alignment = BoxContainer.ALIGNMENT_CENTER
	footer.add_theme_constant_override("separation", 30)
	column.add_child(footer)


# Shows or hides the sheet and keeps it current.
func refresh() -> void:
	if body == null:
		_build()
	var view: Dictionary = model.view
	var mode: String = ExamModelScript.mode(view, model.seat) if not view.is_empty() else ""
	visible = mode != ""
	if mode == "":
		picks = []
		answers = []
		confirming = false
		drawn_for = ""
		return
	clock_label.text = "%d s" % ExamModelScript.seconds_left(view, model.elapsed_ms())
	if mode == "write":
		_draw_writer()
	else:
		_draw_taker(view)


# --- the Leader ------------------------------------------------------------------------------

func _draw_writer() -> void:
	var state: Dictionary = ExamModelScript.writer_state(picks)
	title_label.text = "Set your exam"
	note_label.text = state["note"]
	var signature: String = "write|" + JSON.stringify(picks) + "|" + str(confirming)
	if signature == drawn_for:
		return
	drawn_for = signature
	_clear()
	if confirming:
		_draw_confirmation()
		return
	var hint := _label("Pick prepared questions, or type your own for a laugh. For each, mark YOUR true answer: the others will try to guess it.", 18)
	body.add_child(hint)
	# Your exam so far, with the answer buttons.
	for i in picks.size():
		body.add_child(_exam_row(i, picks[i]))
	body.add_child(_typed_form())
	body.add_child(_label("Prepared questions (tap to add or remove):", 18))
	var bank: Array = ExamModelScript.bank()
	for id in bank.size():
		var in_exam: bool = false
		for pick in picks:
			if not ExamModelScript.is_typed(pick) and int(pick["id"]) == id:
				in_exam = true
		var row := Button.new()
		row.text = ("✓ " if in_exam else "") + bank[id]["text"]
		row.alignment = HORIZONTAL_ALIGNMENT_LEFT
		row.custom_minimum_size.y = 52
		_style(row, PICKED if in_exam else PLAIN, 18)
		row.pressed.connect(func(): picks = ExamModelScript.toggle(picks, id); refresh())
		body.add_child(row)
	for child in footer.get_children():
		footer.remove_child(child)
		child.queue_free()
	var lock := Button.new()
	lock.text = "Lock in my exam"
	lock.custom_minimum_size = Vector2(320, 64)
	lock.disabled = not state["ready"]
	_style(lock, TRUE_ANSWER, 24)
	lock.pressed.connect(func(): confirming = true; refresh())
	footer.add_child(lock)


# One question in your exam: its text, the option buttons (green = your true answer) and a remove button.
func _exam_row(index: int, pick: Dictionary) -> Control:
	var shown: Dictionary = ExamModelScript.shown(pick)
	var box := VBoxContainer.new()
	box.add_child(_label("%d. %s%s" % [index + 1, shown["text"], "   (your own)" if ExamModelScript.is_typed(pick) else ""], 20))
	var line := HFlowContainer.new()
	line.add_theme_constant_override("h_separation", 14)
	for option_index in shown["options"].size():
		var option := Button.new()
		option.text = shown["options"][option_index]
		option.custom_minimum_size = Vector2(150, 48)
		_style(option, TRUE_ANSWER if int(pick["answer"]) == option_index else PLAIN, 18)
		option.pressed.connect(func(): picks = ExamModelScript.mark_at(picks, index, option_index); refresh())
		line.add_child(option)
	var remove := Button.new()
	remove.text = "Remove"
	remove.custom_minimum_size = Vector2(110, 48)
	_style(remove, Color(0.7, 0.25, 0.25), 18)
	remove.pressed.connect(func(): picks = ExamModelScript.remove_at(picks, index); refresh())
	line.add_child(remove)
	box.add_child(line)
	return box


# "Write your own": a question and 2 or 3 options.
func _typed_form() -> Control:
	var box := VBoxContainer.new()
	box.add_child(_label("Write your own question:", 18))
	typed_text = LineEdit.new()
	typed_text.placeholder_text = "Your question"
	typed_text.max_length = 200
	typed_text.custom_minimum_size.y = 48
	typed_text.text = typed_draft["text"]
	typed_text.text_changed.connect(func(text): typed_draft["text"] = text)
	box.add_child(typed_text)
	var options_row := HBoxContainer.new()
	options_row.add_theme_constant_override("separation", 10)
	typed_options = []
	for i in 3:
		var field := LineEdit.new()
		field.placeholder_text = "Option %d%s" % [i + 1, "" if i < 2 else " (optional)"]
		field.max_length = 200
		field.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		field.custom_minimum_size.y = 48
		field.text = typed_draft["options"][i]
		field.text_changed.connect(func(text): typed_draft["options"][i] = text)
		typed_options.append(field)
		options_row.add_child(field)
	box.add_child(options_row)
	var add := Button.new()
	add.text = "Add my question"
	add.custom_minimum_size = Vector2(240, 52)
	_style(add, PICKED, 20)
	add.pressed.connect(_on_add_typed)
	box.add_child(add)
	typed_message = _label("", 16)
	box.add_child(typed_message)
	return box


func _on_add_typed() -> void:
	var options: Array = typed_options.map(func(field): return field.text)
	var problem: String = ExamModelScript.typed_problem(typed_text.text, options)
	if problem != "":
		typed_message.text = problem
		return
	picks = ExamModelScript.add_typed(picks, typed_text.text, options)
	typed_draft = {"text": "", "options": ["", "", ""]}
	drawn_for = ""
	refresh()


func _draw_confirmation() -> void:
	body.add_child(_label("Lock in your exam?", 34))
	body.add_child(_label("Once locked, your answers are sealed. Nobody can change them or see them, you included, until the marking. The questions are shown to the others straight away.", 22))
	for child in footer.get_children():
		footer.remove_child(child)
		child.queue_free()
	var back := Button.new()
	back.text = "Back"
	back.custom_minimum_size = Vector2(240, 64)
	_style(back, PLAIN, 24)
	back.pressed.connect(func(): confirming = false; refresh())
	footer.add_child(back)
	var lock := Button.new()
	lock.text = "Lock it"
	lock.custom_minimum_size = Vector2(320, 64)
	_style(lock, TRUE_ANSWER, 24)
	lock.pressed.connect(func(): command_requested.emit(ExamModelScript.writer_state(picks)["command"]))
	footer.add_child(lock)


# --- a taker ---------------------------------------------------------------------------------

func _draw_taker(view: Dictionary) -> void:
	if answers.size() != ExamModelScript.questions(view).size():
		answers = ExamModelScript.blank_answers(view)
	var state: Dictionary = ExamModelScript.taker_state(view, answers)
	title_label.text = "The exam"
	note_label.text = state["note"]
	var signature: String = "take|" + JSON.stringify(answers) + "|" + str(ExamModelScript.questions(view).size())
	if signature == drawn_for:
		return
	drawn_for = signature
	_clear()
	body.add_child(_label("How well do you know the Leader? Tick one answer for each question.", 18))
	var questions: Array = ExamModelScript.questions(view)
	for i in questions.size():
		var box := VBoxContainer.new()
		box.add_child(_label("%d. %s" % [i + 1, questions[i]["text"]], 20))
		var line := HFlowContainer.new()
		line.add_theme_constant_override("h_separation", 14)
		for option_index in questions[i]["options"].size():
			var option := Button.new()
			option.text = questions[i]["options"][option_index]
			option.custom_minimum_size = Vector2(150, 52)
			_style(option, PICKED if answers[i] == option_index else PLAIN, 18)
			option.pressed.connect(func(): answers[i] = option_index; refresh())
			line.add_child(option)
		box.add_child(line)
		body.add_child(box)
	for child in footer.get_children():
		footer.remove_child(child)
		child.queue_free()
	var hand_in := Button.new()
	hand_in.text = "Hand in my answers"
	hand_in.custom_minimum_size = Vector2(360, 64)
	hand_in.disabled = not state["ready"]
	_style(hand_in, TRUE_ANSWER, 24)
	hand_in.pressed.connect(func(): command_requested.emit(ExamModelScript.taker_state(model.view, answers)["command"]))
	footer.add_child(hand_in)


# --- small helpers ---------------------------------------------------------------------------

func _clear() -> void:
	for child in body.get_children():
		body.remove_child(child)
		child.queue_free()


func _label(text: String, size: int) -> Label:
	var label := Label.new()
	label.text = text
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.add_theme_font_size_override("font_size", size)
	return label


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
