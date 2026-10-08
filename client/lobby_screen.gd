# The first screens: where to connect, your name, create or join a room, and the waiting room.
# Built in code (no scene file to keep in step) for a PHONE held SIDEWAYS (1280 x 720): the form in two columns so it fits without
# scrolling, big text, big buttons, nothing smaller than a thumb. It only DRAWS the session model and emits what the player asked for; main.gd turns those into messages.
extends Control

const SessionModelScript = preload("res://client/session_model.gd")

signal connect_requested(address: String)
signal create_requested(name: String, gender: String)
signal join_requested(room_code: String, name: String, gender: String)
signal start_requested
signal leave_requested

const FONT_SIZE := 26
const TITLE_SIZE := 44
const CODE_SIZE := 80
const TAP_HEIGHT := 72      # a finger needs about 9 mm: 72 px of a 720 px-high screen is about 10 mm on a 6-inch phone
const MARGIN := 28

var model = SessionModelScript.new()

var column: VBoxContainer
var status_label: Label
var message_label: Label
var server_field: LineEdit
var name_field: LineEdit
var gender_menu: OptionButton
var code_field: LineEdit
var create_button: Button
var join_button: Button
var entry_box: HBoxContainer
var lobby_box: VBoxContainer
var room_code_label: Label
var members_box: VBoxContainer
var start_button: Button
var leave_button: Button
var waiting_label: Label
var playing_label: Label


func _ready() -> void:
	refresh()


func _build() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	var theme := Theme.new()
	theme.default_font_size = FONT_SIZE
	self.theme = theme
	var margin := MarginContainer.new()
	margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, MARGIN)
	add_child(margin)
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	margin.add_child(scroll)
	column = VBoxContainer.new()
	column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	column.add_theme_constant_override("separation", 14)
	scroll.add_child(column)

	var title := Label.new()
	title.text = "Pseudodemocracy"
	title.add_theme_font_size_override("font_size", TITLE_SIZE)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	column.add_child(title)
	status_label = _label("")
	status_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	column.add_child(status_label)
	message_label = _label("")
	message_label.add_theme_color_override("font_color", Color(0.85, 0.2, 0.2))
	column.add_child(message_label)

	entry_box = HBoxContainer.new()
	entry_box.add_theme_constant_override("separation", 40)
	column.add_child(entry_box)
	var left := VBoxContainer.new()
	left.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	left.add_theme_constant_override("separation", 10)
	entry_box.add_child(left)
	var right := VBoxContainer.new()
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	right.add_theme_constant_override("separation", 10)
	entry_box.add_child(right)
	left.add_child(_label("Server"))
	server_field = _field("ws://host:9080")
	server_field.text_submitted.connect(func(text): connect_requested.emit(text))
	left.add_child(server_field)
	var connect_button := _button("Connect")
	connect_button.pressed.connect(func(): connect_requested.emit(server_field.text))
	left.add_child(connect_button)
	left.add_child(_label("Your name"))
	name_field = _field("Name")
	name_field.max_length = SessionModelScript.NAME_MAX
	left.add_child(name_field)
	left.add_child(_label("Gender (some cards ask)"))
	gender_menu = OptionButton.new()
	gender_menu.custom_minimum_size.y = TAP_HEIGHT
	for choice in SessionModelScript.gender_choices():
		gender_menu.add_item(choice if choice != "" else "Prefer not to say")
	left.add_child(gender_menu)
	create_button = _button("Create a room")
	create_button.pressed.connect(_on_create)
	right.add_child(create_button)
	right.add_child(_label("or join with a code"))
	code_field = _field("ABCD")
	code_field.max_length = SessionModelScript.CODE_LENGTH
	code_field.alignment = HORIZONTAL_ALIGNMENT_CENTER
	right.add_child(code_field)
	join_button = _button("Join the room")
	join_button.pressed.connect(_on_join)
	right.add_child(join_button)

	lobby_box = VBoxContainer.new()
	lobby_box.add_theme_constant_override("separation", 10)
	column.add_child(lobby_box)
	lobby_box.add_child(_label("Room code, tell your friends:"))
	room_code_label = Label.new()
	room_code_label.add_theme_font_size_override("font_size", CODE_SIZE)
	room_code_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lobby_box.add_child(room_code_label)
	members_box = VBoxContainer.new()
	members_box.add_theme_constant_override("separation", 10)
	lobby_box.add_child(members_box)
	waiting_label = _label("")
	lobby_box.add_child(waiting_label)
	start_button = _button("Start the game")
	start_button.pressed.connect(func(): start_requested.emit())
	lobby_box.add_child(start_button)
	leave_button = _button("Leave the room")
	leave_button.pressed.connect(func(): leave_requested.emit())
	lobby_box.add_child(leave_button)

	playing_label = _label("")
	column.add_child(playing_label)


func _on_create() -> void:
	var problem: String = SessionModelScript.name_problem(name_field.text)
	if problem != "":
		show_message(problem)
		return
	create_requested.emit(name_field.text, _gender())


func _on_join() -> void:
	var problem: String = SessionModelScript.name_problem(name_field.text)
	if problem == "":
		problem = SessionModelScript.code_problem(code_field.text)
	if problem != "":
		show_message(problem)
		return
	join_requested.emit(code_field.text, name_field.text, _gender())


func _gender() -> String:
	return SessionModelScript.gender_choices()[gender_menu.selected]


func show_message(text: String) -> void:
	message_label.text = text


# Draws whatever the model says right now.
func refresh() -> void:
	if column == null:
		_build()   # (drawn before it entered the tree, as a test may)
	var stage: int = model.stage()
	if not model.connected:
		status_label.text = "Connecting…" if model.resuming() else "Not connected"
	else:
		status_label.text = "Reconnecting to your seat…" if model.resuming() else "Connected"
	entry_box.visible = stage == SessionModelScript.Stage.ENTRY and not model.resuming()
	lobby_box.visible = stage == SessionModelScript.Stage.LOBBY and not model.resuming()
	playing_label.visible = stage == SessionModelScript.Stage.PLAYING and not model.resuming()
	var enabled: bool = model.connected
	create_button.disabled = not enabled
	join_button.disabled = not enabled
	if model.error != "":
		show_message(model.take_error())
	room_code_label.text = model.code
	for child in members_box.get_children():
		members_box.remove_child(child)
		child.queue_free()
	for member in model.members:
		var line := _label("%d. %s%s%s" % [member["seat"], member["name"], "  (host)" if member["seat"] == model.host_seat else "", "" if member["connected"] else "  (away)"])
		members_box.add_child(line)
	start_button.visible = model.is_host()
	start_button.disabled = not model.can_start()
	waiting_label.text = "Waiting for the host to start." if not model.is_host() else ("Waiting for players (3 to 10)." if model.members.size() < 3 else "Ready when you are.")
	playing_label.text = "The game has started. (The table screen comes next.)"


func _label(text: String) -> Label:
	var label := Label.new()
	label.text = text
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	return label


func _field(placeholder: String) -> LineEdit:
	var field := LineEdit.new()
	field.placeholder_text = placeholder
	field.custom_minimum_size.y = TAP_HEIGHT
	return field


func _button(text: String) -> Button:
	var button := Button.new()
	button.text = text
	button.custom_minimum_size.y = TAP_HEIGHT
	return button
