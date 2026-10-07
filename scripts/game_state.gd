class_name GameState

enum LeaderType { DICTATOR, PRESIDENT, COMMANDER }
enum AmendWindow { INAUGURATION, MID_TERM, FAREWELL }

var player_count: int = 0
var turns_played: int = 0
var leader_id: int = -1
var leader_type: LeaderType = LeaderType.PRESIDENT
var popularity: Dictionary = {}     # player id -> int
var sick: Dictionary = {}           # player id -> bool
var windows_used: Dictionary = {    # AmendWindow -> bool
	AmendWindow.INAUGURATION: false,
	AmendWindow.MID_TERM: false,
	AmendWindow.FAREWELL: false,
}

# Money and debt. Player ids start at 1 (0 means the treasury, see Debt.TREASURY_ID).
var treasury: int = 0
var psd: Dictionary = {}            # player id -> cash (never negative)
var debts: Dictionary = {}          # player id -> Array of { "creditor": int, "amount": int }
var debt_terms: Dictionary = {}     # player id -> own turns ended while owing anything
var eliminated: Dictionary = {}     # player id -> bool
