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

# Wills are SECRET until their owner is eliminated, then carried out. Server only (see Views).
var wills: Dictionary = {}          # player id -> { "psd_heir": int, "on_hold": bool }

# Nepo Babies: the heirs whose popularity is temporarily reduced (Articles 30 and 31).
var nepo: Dictionary = {}           # player id -> step 1, 2 or 3 of the debuff; absent = not a Nepo Baby

# The election of the next Leader (see Election). Part of it is secret: Views removes it.
enum ElectionPhase { NONE, EXAM_WRITING, EXAM_ANSWERING, VOTING }
var election: Dictionary = {}       # {} when there is no election under way

# The server's random number generator (see Rng). SECRET: whoever knew it could predict every draw.
var rng_state: int = 2463534242

# The term in progress: Inauguration, the levy, every player's turn, then the Farewell (see TermLoop).
enum TermPhase { NONE, INAUGURATION, TURNS, FAREWELL }
var term: Dictionary = {}           # {} between terms; in TURNS and FAREWELL it lists the players who have "played" and who are "waiting", in turn order
var game_over: bool = false

# Whose turn starts the next term. Play carries on round the table from where the last term stopped,
# except after a coup, when the new Leader goes first (see TermLoop).
var last_turn_player: int = 0       # the player who took the most recent turn; 0 before any turn
var leader_goes_first: bool = false # set by a coup, used up by the next term's turn order

# The levy band (Articles 4 and 5): the lowest and highest levy the Constitution allows. It moves
# at the end of a term (see LevyBand). The levy itself is a word of Article 3.
var levy_band: Dictionary = {"low": 0, "high": 0}
