class_name GameState

enum LeaderType { DICTATOR, PRESIDENT, COMMANDER }
enum Window { INAUGURATION, MID_TERM, FAREWELL }

var player_count: int = 0
var turns_played: int = 0
var leader_id: int = -1
var leader_type: LeaderType = LeaderType.PRESIDENT
var popularity: Dictionary = {}     # player id -> int
var sick: Dictionary = {}           # player id -> bool
var windows_used: Dictionary = {    # Window -> bool
	Window.INAUGURATION: false,
	Window.MID_TERM: false,
	Window.FAREWELL: false,
}
