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

# The server's clock, in whole milliseconds. Only Game.tick moves it, so every deadline is an
# absolute time on this clock and a saved game picks up where it stopped (see PerformanceTurn).
var clock_ms: int = 0

# The draw piles of the Performance, Settlement and Scandal decks (see Cards). SECRET: whoever
# knew the order would know the next cards.
var decks: Dictionary = {}          # deck name -> shuffled list of card numbers, drawn from the end

# Where a player is in their performance: PERFORMING (acting out the card), VOTING (the others vote
# Good or Bad), DONE (resolved; the player may now end their turn).
enum ActPhase { PERFORMING, VOTING, DONE }

# The role cards each player holds (Doctor, Lawyer, Secret Agent, Activist, Agbero). A player can hold
# several, and each earns its own income. Public: everyone can see who holds which role. Roles are
# gained from Settlement cards; nothing deals them yet.
var roles: Dictionary = {}          # player id -> list of role names; absent = no roles

# How long each sick player stays sick, and for how long they cannot be sickened again. A round is a term.
# state.sick (above) is the flag everything else checks; these say for how long.
var sick_left: Dictionary = {}      # player id -> rounds of sickness still to go
var sick_original: Dictionary = {}  # player id -> how long the sickness first was; sabotage doesn't change it
var immune_left: Dictionary = {}    # player id -> rounds during which they can't be sickened

# The Doctor's dose in progress (see Doctor): at most one at a time. {} when there is none.
# Public: everyone sees who, which dose and the price. What is in the Doctor's hand is not (dose_secret).
enum DosePhase { OFFERED, GUESSING }
var dose: Dictionary = {}           # { "phase", "doctor", "patient", "kind": "heal"|"sicken", "dose", "price", "deadline", "guesser" (0 = none) }
var dose_secret: Dictionary = {}    # { "poison": bool }: the bead hidden in the Doctor's hand. SECRET: server only
var doctor_used: Dictionary = {}    # Doctor's player id -> charges spent this round (they get doctorCharges a round)

# Wills waiting for their Lawyer to sign (see Wills), by testator. SECRET: they hold the heirs. Server only.
var will_offers: Dictionary = {}    # testator id -> { "lawyer", "psd_heir", "role_heir", "fee", "upkeep", "deadline" }

# The 25 physical role cards (5 copies of each of the 5 roles), by card number. SECRET: a card may carry a coup
# sticker, and nobody knows which do (see Roles and the Secret Agent). "holder" is a player id, or 0 when the card
# is in the box. state.roles (public) says who holds which role; this says which card, and its sticker.
var role_cards: Dictionary = {}     # card id -> { "role": String, "sticker": bool, "holder": int }

# Secret Agents who have used their power this round (they get one use a round). Server only.
var agent_used: Dictionary = {}     # player id -> true

# A card choice waiting for its player (see CardEffects). Only one at a time. {} when there is none. Public.
var choice: Dictionary = {}         # { "player", "deck", "card", "kind", "deadline", + "labels" or "candidates" }

# Cards kept to play later ("play anytime"), by player. SECRET to the owner: the server keeps them, a view shows
# each player their own hand and everyone the size of every hand.
var hands: Dictionary = {}          # player id -> list of { "deck": String, "card": int }

# Invitations to join a union, by the player asked (see Unions). Public: recruiting is a social ask in the open.
var union_invites: Dictionary = {}  # invited player id -> { "union_id": int, "deadline": clock ms }

# Agbero who may form a new mob straight away because their last one dispersed and they still hold an Agbero
# role card (see Unions). Public.
var reform: Dictionary = {}         # player id -> true

# Each player's gender, so gendered cards ("every woman at the table") can work. Public. Set in the lobby (before the
# first Leader) and then fixed. A player who has said nothing is in none of the groups.
var genders: Dictionary = {}        # player id -> "female" or "male"

# A Command Performance in progress (see CommandPerformance): a union or mob scripts a scenario and a player performs it.
# At most one at a time. {} when there is none. Public, except the votes, which are secret until the result.
enum CommandPhase { PERFORMING, VOTING }
var command: Dictionary = {}        # { "phase", "union_id", "union_type", "leader", "target", "members", "scenario", "deadline", "votes" }

# Requests to hire a Secret Agent, by the Agent asked (see SecretAgent). SECRET: they hold what is to be checked.
var agent_offers: Dictionary = {}   # agent id -> { "client", "kind", "target", "role", "price", "deadline" }

# Players barred from attempting a coup, and for how many more rounds (a Scandal card). Public.
var coup_ban: Dictionary = {}       # player id -> rounds left

# Corruption markers held (see Corruption), and the players frozen by their last one. Public.
var markers: Dictionary = {}        # player id -> markers held
var frozen: Dictionary = {}         # player id -> { "left": rounds until the freeze runs out, "drop": popularity lost }
