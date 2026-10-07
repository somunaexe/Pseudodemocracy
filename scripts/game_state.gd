class_name GameState

enum LeaderType { DICTATOR, PRESIDENT, COMMANDER }
enum AmendWindow { INAUGURATION, MID_TERM, FAREWELL }
enum AmendPhase { NONE, PROPOSED, VOTING }
enum UnionType { ACTIVIST, AGBERO }

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

# Who is playing and how they are doing, for the end-of-game ranking.
var player_ids: Array = []          # every player id at the table
var half_rounds: Dictionary = {}    # player id -> half-rounds as Leader (full term = 2, couped = 1)

# The live Constitution and the amendment in progress.
var current_round: int = 1
var articles: Dictionary = {}       # article id -> Array of words { text, amendable, glue }
var amend: Dictionary = {}          # the amendment in progress, {} when there is none (see AmendmentFlow)
var amendment_record: Array = []    # finished attempts, for the table's Amendment Record
var event_log: Array = []           # every event the server has emitted, in order

# Unions and inheritance.
var unions: Dictionary = {}         # union id -> { "type": UnionType, "owner": int, "members": Array, "confront_used": bool }
var heirs: Dictionary = {}          # eliminated player id -> the heir who is owed money they were owed
