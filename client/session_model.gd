# What the phone knows about its connection to the server, and nothing about the screen.
#
# apply() takes every message the server sends and updates this; the screens only READ it. The make_* functions build the
# text to send. Because it has no nodes and no socket, it is tested headless against the real ServerCore.
#
# Stages: ENTRY (not in a room), LOBBY (in a room that has not started), PLAYING (the game is running or over).

const SerializerScript = preload("res://scripts/serializer.gd")
const GendersScript = preload("res://scripts/genders.gd")

enum Stage { ENTRY, LOBBY, PLAYING }

const NAME_MAX := 24
const CODE_LENGTH := 4

var token: String = ""
var code: String = ""
var seat: int = 0                  # 0 until we have one
var host_seat: int = 0
var members: Array = []            # [{seat, name, connected}]
var started: bool = false
var view: Dictionary = {}          # our latest view of the game (state_view)
var recent_events: Array = []      # events since the last time the screen looked, oldest first
var error: String = ""             # the last thing the server refused, until the screen has shown it
var connected: bool = false        # is the socket open (set by the connection)
var view_received_ms: int = 0      # local clock (Time.get_ticks_msec) when the view arrived: countdowns run on from there


# Milliseconds since the view arrived: the game's clock, as the phone last heard it, has moved on by this much.
func elapsed_ms(now_ms: int = -1) -> int:
	if now_ms < 0:
		now_ms = Time.get_ticks_msec()
	return maxi(0, now_ms - view_received_ms)


func stage() -> int:
	if code == "":
		return Stage.ENTRY
	return Stage.PLAYING if started else Stage.LOBBY


# We hold a saved seat and the server has not yet said we still have it.
func resuming() -> bool:
	return token != "" and seat == 0


func is_host() -> bool:
	return seat != 0 and seat == host_seat


func can_start() -> bool:
	return stage() == Stage.LOBBY and is_host() and members.size() >= 3


# What to remember on the phone so a dropped connection, or closing the app, can pick the seat up again.
func to_save() -> Dictionary:
	return {"token": token, "code": code}


func from_save(data: Dictionary) -> void:
	token = str(data.get("token", ""))
	code = str(data.get("code", ""))   # shown as "reconnecting" until the server confirms with a welcome


func has_saved_seat() -> bool:
	return token != ""


# Takes the events the screen has not seen yet.
func take_events() -> Array:
	var events: Array = recent_events
	recent_events = []
	return events


func take_error() -> String:
	var text: String = error
	error = ""
	return text


func apply(message: Dictionary) -> void:
	match str(message.get("type", "")):
		"welcome":
			token = str(message["token"])
			code = str(message["code"])
			seat = int(message["you"])
		"room":
			code = str(message["code"])
			host_seat = int(message["host"])
			started = bool(message["started"])
			members = message["members"]
		"state":
			view_received_ms = Time.get_ticks_msec()
			if message.get("full", false):
				view = message["view"]
			else:
				var log: Array = view.get("event_log", [])   # the long log only comes with a full picture: keep ours
				view = message["view"]
				view["event_log"] = log
		"events":
			recent_events.append_array(message["events"])
			if recent_events.size() > 500:
				recent_events = recent_events.slice(recent_events.size() - 500)
			var log: Array = view.get("event_log", [])
			for event in message["events"]:
				if event["type"] != "rejected":
					log.append(event)
				else:
					error = str(event.get("reason", ""))
			view["event_log"] = log
		"error":
			error = str(message["reason"])
			if error.begins_with("That token is not known"):
				forget()   # the server lost our seat (or the room is gone): back to the start, not a loop of retries
		"left":
			forget()


# Leave the room on this phone (after leaving it, or when the server no longer knows us).
func forget() -> void:
	token = ""
	code = ""
	seat = 0
	host_seat = 0
	members = []
	started = false
	view = {}
	recent_events = []


# --- what to send ----------------------------------------------------------------------------

# Why a name or code can't be sent, for the screen to show before bothering the server. "" means fine.
static func name_problem(name: String) -> String:
	var trimmed: String = name.strip_edges()
	if trimmed.is_empty():
		return "Type your name."
	if trimmed.length() > NAME_MAX:
		return "Your name can be at most %d characters." % NAME_MAX
	return ""


static func code_problem(room_code: String) -> String:
	var trimmed: String = room_code.strip_edges()
	if trimmed.length() != CODE_LENGTH:
		return "A room code has %d letters." % CODE_LENGTH
	return ""


static func gender_choices() -> Array:
	return [""] + GendersScript.names()


static func make_create_room(name: String, gender: String) -> String:
	return SerializerScript.to_json({"type": "create_room", "name": name.strip_edges(), "gender": gender})


static func make_join_room(room_code: String, name: String, gender: String) -> String:
	return SerializerScript.to_json({"type": "join_room", "code": room_code.strip_edges().to_upper(), "name": name.strip_edges(), "gender": gender})


func make_resume() -> String:
	return SerializerScript.to_json({"type": "resume", "token": token})


static func make_start_game() -> String:
	return SerializerScript.to_json({"type": "start_game"})


static func make_leave() -> String:
	return SerializerScript.to_json({"type": "leave"})


static func make_sync() -> String:
	return SerializerScript.to_json({"type": "sync"})


static func make_command(command: Dictionary) -> String:
	return SerializerScript.to_json({"type": "command", "command": command})
