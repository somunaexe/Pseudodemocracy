# Design decisions

Decisions made while building the digital version, so they aren't lost.
Add a line whenever the handbook is silent and the table has to decide.

## Final ranking (who wins)

Compared in this order. Built in `scripts/scoring.gd` and covered by 22 tests.

1. **Half-rounds as Leader** (full term = 2, couped term = 1).
2. **Tie-break score** `(popularity + 51) x PSD`. Anyone in debt scores their negative PSD, so they rank below everyone at 0 PSD or above, and a smaller debt wins.
3. **Popularity.** This settles: everyone at exactly 0 PSD, equal debts, and different players whose products happen to be equal.
4. **Still equal:** a shared win.

**Eliminated players can never win**, even with the most rounds (decided). `Scoring.final_winners(state)` filters them out first; if everyone is eliminated there is no winner.

Open:
- The handbook must be reworded: "popularity + 51", a 1-101 score, popularity as the second key, and a shared win on a full tie.

## Debt

| Question | Decision | Status |
|---|---|---|
| A player can't afford a payment (levy, tax, Agbero steal, a Doctor's fee, ...). | They go into debt. | Decided, not built yet. |
| Who is owed? | It depends on the cause: the treasury (levy, tax), another player (e.g. 50 PSD to a Doctor for a treatment). Each debt records its creditor. | Decided |
| What happens to a player in debt each round? | The levy and tax are added to their debt. | Decided |
| How long can debt last? | 3 terms, then the player is eliminated. A "term" here is one of that player's own turns coming round again. | Decided. Open: see below. |
| Forced vs agreed payments (levy vs a Doctor's fee). | No split. Any payment a player can't cover becomes debt, as in real life, including payments they agree to (e.g. a Doctor's fee). There is no "loan" concept and no "can they afford it?" guard on agreed payments. Confirmed twice. | **Built** (`Debt.charge`; `test_debt.gd` covers an agreed payment to a player) |
| When is debt collected, and in what order? | Immediately, the moment money reaches the player, oldest debt first (FIFO). Each debt is its own entry; same-creditor debts are not merged. | **Built** (`Debt.receive`) |
| A debt is owed to a player who is then eliminated. | The debt is cleared, unless they have an heir: then the heir is owed instead. | **Built** (`Elimination`, `GameState.heirs`) |
| Paying it off and falling back in. | Paying off all debt resets the count to zero. | Decided |
| Can a player in debt launch a coup? | No. A coup costs 300 PSD and they don't have it. No special rule needed. | Decided |
| Do heirs inherit debt? | Yes, automatically. **An heir can't accept or refuse any inheritance** (rule changed). They get the whole estate: cash and debt. | **Built** (`Elimination.eliminate`) |
| Tie-break `(popularity + 50) x PSD` with negative PSD. | Anyone below 0 PSD ranks under everyone at 0 or above; among debtors the smaller debt wins. | **Built** (scripts/scoring.gd, tested) |
| Tie-break shift: 50 or 51? | 51. A CANCELLED player (-50) scored 0 whatever their PSD; now they score 1 x PSD. Handbook wording must change to `popularity + 51`. | **Built** (`tieBreakShift` in game data) |
| Can a player pay part of what they owe? | Yes. They pay what they have; the rest becomes a debt to the same creditor. | **Built** (scripts/debt.gd, tested) |
| When is a debt term counted? | At the END of the debtor's own turn, if they still owe anything. The 3rd such turn eliminates them. | **Built** |

Open debt questions:
- All income must go through `Debt.receive()` (roles, cards, treasury payouts), or it will skip collection.
- Elimination is built for cash, debt, wills, unions, roles and the Nepo Baby debuff.
- A round cut short by a coup gives some players no turn that round. By the "own turn" definition, no debt term is counted for them.

## Other

| Question | Decision | Status |
|---|---|---|
| Where does grammar checking for amendments happen? | Server decides. Method still open (referee, tool, or word lists). | Open |
| Amendment words are validated on the server, never trusted from the client. | Server-authoritative. | Decided |

## Amendment flow (built: scripts/amendment_flow.gd, 113 tests)

Commands in, events out, a state machine in between (NONE, PROPOSED, VOTING). See docs/architecture.md.

| Question | Decision | Status |
|---|---|---|
| Does a failed check use up the window? | Yes. So does a blocked, rejected or successful amendment: the window is used the moment a proposal is accepted. | **Built** |
| What counts as a "failed check"? | Changing a fixed word, a wrong word count, a replacement that isn't one word, or a bad grammar ruling. All cost 100 PSD and (base swing x other players) popularity. | **Built** |
| Active players for the swing / penalty. | Players who are not eliminated, the Leader included. | **Built** |
| Who rules on grammar? | Only the server (player 0). *How* it decides is still open. | Open |
| Who can vote? | Everyone except the Leader, the sick and the eliminated. | **Built** |
| How do you vote? | By hand, in secret: the server holds the votes, everyone is told THAT you voted, and the result reveals HOW. | **Built** |
| President / Dictator | President needs more for than against (a tie fails). A Dictator's amendment always stands. Both still move popularity. | **Built** |
| Agbero confront | Blocks the amendment (window stays used). The Leader pays the steal amount to each member. | **Built**, see assumption 1 |
| Activist confront | Each member's vote counts double, against the Leader, cast automatically. A vote they cast earlier is ignored. | **Built**, see assumption 2 |
| Who can confront? | Only the unionizer, not sick or eliminated, union of at least 2, once only, while the amendment is PROPOSED or VOTING. | **Built** |

Assumptions to confirm:
1. **Agbero steal.** The handbook says "steal 50 x union size". I read it as 50 to *each* member (so 50 x size in total). If the Leader can't pay everyone, members are paid in the order they joined and the rest becomes debt (FIFO). Is "who gets paid first" meant to matter?
2. **Activist doubling.** I doubled the weight for both the keep/reject count and the popularity swing. The handbook says "the union's total vote is doubled".
3. **A union that contains the Leader** can't confront at all (Article 17 says its actions target a rival; not built yet).
4. ~~Commands from the network carry floats.~~ Solved: `Serializer.parse_command` converts them to ints before `handle` sees them.

## Serialization (built: scripts/serializer.gd, 105 checks)

| Question | Decision | Status |
|---|---|---|
| How are saves and messages written? | JSON text, with non-text dictionary keys as `$pairs` so they keep their type. | **Built** |
| What stops an old save being misread? | `SCHEMA_VERSION`; a save with another version is refused. Bump it when a field or enum changes meaning. | **Built** |
| What can a client send? | Only a command object, max 64 KB, nested at most 32 deep. Whether it is allowed is decided by the rules, not the parser. | **Built** |
| What does a reconnecting player see? | `Views.state_view`: an allow-list of public fields, with others' votes removed. | **Built** (scripts/views.gd, 50 checks) |

## What is public (Views)

| Question | Decision | Status |
|---|---|---|
| Is a player's PSD, debt and popularity public? | Yes. | Confirmed |
| Is union membership public? | Yes (the rules say you can't recruit a member of another union, so players must be able to tell). | Confirmed |
| Are heirs public? | Yes, once the player is eliminated (the Lawyer reads the will out). | Confirmed |
| When is a will carried out? | When its owner is eliminated. The Lawyer reads it out, so it becomes public then. Before that, a will is secret (server only). | Decided, not built |
| Votes during an amendment | Hidden until the result; everyone sees who has voted, and you see your own. | **Built** |
| Wills, role cards, coup stickers, Doctor's beads, exam keys | Server only, when they are built. | Not built |

## Elimination (built: scripts/elimination.gd, 67 checks)

| Question | Decision | Status |
|---|---|---|
| Who gets the estate? | The heir named in the will, whole, automatically. An heir can't refuse anything. | **Built** (rule changed) |
| What counts as a usable will? | It exists, is not on hold (Article 27), and names a living player other than the owner. Otherwise it is void and the event says why. | **Built** |
| No usable will: where does the cash go? | The treasury (Article 29). | **Built** |
| No usable will: what happens to their debts? | They disappear with them; the creditors lose the money. | Confirmed |
| An heir inherits debt and has cash. | Collection is immediate: the cash pays the oldest debt first (the heir's own debts, then the inherited ones). Inherited debt goes to the back of the queue. | **Built** |
| The dead player owed the heir. | That debt is cancelled; nobody owes themselves. | **Built** |
| Money owed TO the dead player. | Goes to the heir, or is cleared if there is none. No money is ever paid to a dead player. | **Built** |
| Union memberships. | Ended (Article 25). A union left with one member dissolves (Article 11). | **Built** |
| A union whose unionizer is eliminated. | Dissolves. | Confirmed |
| A vote that was waiting for the eliminated player. | Finishes if they were the last one awaited. | **Built** |
| When is a will carried out? | At elimination, and it is then public. Until then it is server-only (`wills`). | **Built** |

A fact worth knowing: debt is collected the moment money arrives, so a player who owes anything holds 0 cash. An estate is therefore always cash *or* debt, never both. The code handles both anyway.

Handbook sentences that now contradict "an heir cannot refuse":
- Part 6: "Each heir accepts or rejects independently."
- Article 29: "Unwilled or **rejected** PSD goes to the treasury."
- Article 30: "An heir who **accepts** an inheritance becomes a Nepo Baby." (`accepts` is a highlighted, amendable word.)

Decided, not built yet:
- **Nepo Baby debuff.** Built; see the Nepo Baby section below.
- **The Leader is eliminated.** Built: the seat is vacated, an amendment in progress is abandoned (its window stays used), and an election with no exam starts (see Election).

Not built yet, and why:
- **Roles** are rescinded unless willed; a will may name a different role heir (see Roles).
- **Wills.** Nothing creates one yet (the Lawyer, the fee, "on hold" upkeep). Tests set them directly.
- **Scoring** a term cut short because the Leader was eliminated: ½, like a coup, or something else?
- **A dissolved union's earlier confront.** If an Activist union confronts and then dissolves before the vote ends, its automatic votes disappear and its members vote by hand. Is that intended?

## Amended articles drive the game (built: scripts/law.gd, 158 checks)

**The problem:** a Leader could rewrite "Tax: 20%" to "Tax: 30%" and nothing changed, because the game read its numbers from `game_data.json`, not from the Constitution.

**The fix:** the live Constitution (`GameState.articles`) is the source of truth for every number it governs. `Law.get_int(state, "agberoSteal")` reads the current wording. A test (`test_law_guard.gd`) fails if any script reads one of those numbers straight from the data again.

| Question | Decision | Status |
|---|---|---|
| Which words does the game enforce? | A "binding" ties one highlighted word to one rule (data/source/articles.js). 13 of the 116 highlighted words are bound today. | **Built** |
| What about the other 104 highlighted words? | Free text, enforced by the table as in the physical game. The Constitution shows them but the game does not apply them. | **Built** |
| What may a Leader write in a bound word? | A word the game can read: a whole percentage (30%), a whole number in a range, or one of a fixed list of words (single, double, triple, quadruple; plus or minus). Anything else fails the check. | **Built**, please confirm |
| What happens if they write something else (e.g. "banana" as a tax rate)? | It is a failed check, because they chose to write it: 100 PSD, popularity loss, window used. No free retry. | **Built** (rule changed by the designer) |
| What else costs the fine? | Breaking "one word for one word": changing a fixed word, writing two words, or leaving a word blank; or a bad grammar ruling. | Unchanged |
| When does an amended rule apply? | From the moment the amendment stands. While it is being voted on, the old law applies. | **Built** |
| What stops the data and the text disagreeing? | The export fails if a bound word's starting text differs from game_data. | **Built** |

Rules enforced today:

| Rule | Article | Reads as |
|---|---|---|
| passCompare | 1 Exam Pass Mark | more / less / fewer ("more than 50%") |
| passMark | 1 Exam Pass Mark | percentage |
| taxRate | 2 Tax | percentage |
| levy | 3 Levy | whole number |
| malpracticeFine | 6 Malpractice | whole number |
| unionStart, unionMin | 7 Union Size | whole numbers (at least 1) |
| unionDissolveAt | 11 Dissolving | whole number |
| activistVote | 14 Activist Confront | single / double / triple / quadruple |
| agberoSteal | 15 Agbero Confront | whole number |
| nepoSign1, 2, 3 | 31 Nepo Baby Debuff | minus or plus |

Only taxRate-style rules that game code actually uses (unionMin, unionDissolveAt, activistVote, agberoSteal) change behavior today. The rest are ready for when the levy, tax, exam and Nepo Baby code is built: that code must call `Law.get_int`.

To enforce another highlighted word: add a binding to its article in `data/source/articles.js` (percent / whole / choice), run `node tools/export_articles.js`, then read it with `Law.get_int`. The guard test then protects it.

Open:
- **Is narrowing amendments acceptable?** In the physical game a Leader can write any grammatical word. In the digital game a bound word must be one the game understands. Which of the 104 unenforced words matter for gameplay (for example "the treasury" in Tax, or "can't" in Sickness) and need a vocabulary next?
- The vocabulary limits (for example a whole number up to 99,999, a union must keep at least 1 member) are my choices.
- **Handbook:** Part 4 should say that in the digital version a highlighted word that controls a rule must be a word the game understands.

## Nepo Babies (built: scripts/nepo.gd and popularity.gd, 42 + 46 checks)

An heir becomes a Nepo Baby (Article 30). Their popularity is reduced by 30, then 20, then 10, and then the reduction is lifted (Article 31).

| Question | Decision | Status |
|---|---|---|
| Permanent hits or a temporary reduction? | A temporary reduction that is lifted afterwards. | Decided, **built** |
| How is popularity stored now? | `popularity` is the BASE (what votes and cards do). The Nepo Baby change is a modifier on top. **Effective popularity** = base + modifier, kept on the -50..+50 track. | **Built** (`Popularity`) |
| What counts as effective popularity? | Being CANCELLED, the final ranking and what players see. Votes and fines change the base only. | **Built** |
| How is the debuff stored? | Only the step (1, 2 or 3) per Nepo Baby. The size is worked out when needed: the magnitudes (30, 20, 10) come from the game data (they are fixed text in the article), the signs from the law as it stands. | **Built** |
| Can a Leader change it? | Yes: the three "-" words of Article 31 are bound. Writing "+" turns that step into a bonus, at once. | **Built** |
| When does it move to the next step? | At the end of the Nepo Baby's own turn (the same "term" as debt). Step 1 starts the moment they inherit. | Assumed, please confirm |
| Who becomes one? | Every heir, because an heir cannot refuse. A debt-only estate counts. | **Built** |
| Inheriting again while already a Nepo Baby. | Restarts at step 1 (no stacking). | Assumed, please confirm |
| Eliminated while a Nepo Baby. | The debuff ends with them. | **Built** |

Why a modifier instead of subtracting from popularity: a subtraction can't be undone, because votes in the meantime changed the number, so "lifted afterwards" would be impossible to compute.

Rule for the code: nothing outside `Popularity` reads `state.popularity` (a test enforces it). Use `Popularity.effective` for what counts and `Popularity.base` only when the base is meant.

The end of a player's turn is now `TurnEnd.end_turn` (debt term, possible elimination, then the Nepo step).

Handbook wording to check: Article 31 says "over the next 3 rounds" and the handbook says "removed in the 4th round"; the digital version counts the Nepo Baby's own turns, not table rounds.

## The Leader election (built: scripts/election.gd, rng.gd; 170 + 12 checks)

Round order from the handbook: Exam, Vote, Role card draw, then the Inauguration amendment window. Same pattern as the amendment flow: commands in (`write_exam`, `skip_exam`, `answer_exam`, `cast_vote`), events out, a state machine in between.

| Question | Decision | Status |
|---|---|---|
| When is there an exam? | Only when a term has ended normally and the Leader can write one. Not in the first election, not after a vacancy (nobody to write it), not if the Leader is sick or CANCELLED ("no exam ready: everyone votes and runs"). | **Built** |
| What does the Leader write? | 5 to 10 multiple-choice questions, each with 2 to 3 options and one right answer (the limits are in game_data). The answer key is sealed in server state. | **Built** |
| Who sits it? | Everyone alive and not sick, except the Leader. | **Built** |
| When is it marked? | When everyone who can sit it has handed in answers. The key is then revealed. | **Built** |
| How is it marked? | "More than" the pass mark, with no fractions (3 of 6 is exactly 50% and does not pass). The pass mark AND the word "more" are in Article 1 and can be amended (to "less" or "fewer", the Exam rule flips). | **Built** |
| The Leader's own exam. | The Leader is counted as having passed it. | Confirmed |
| Who can vote and stand? | Only players who passed. Sick and eliminated players can't take part (Article 21). A CANCELLED player can vote but not stand. | **Built** (CANCELLED: confirmed) |
| Is there a "running" step? | No. Any eligible player can be voted for. | Confirmed |
| Can you vote for yourself? | Yes. | Confirmed |
| Is the vote secret? | Yes, until all ballots are in: everyone sees THAT you voted, never for whom. Then the result reveals every ballot. | **Built** |
| Who wins? | The most votes. | Confirmed |
| A tie. | The tied candidates are voted on again, once. A second tie is decided by lot. | Confirmed |
| Only one candidate can stand. | They win unopposed, with no ballots. | **Built** |
| Nobody who passed can stand. | The exam is void and everyone eligible may vote and stand. | Confirmed |
| Nobody can stand at all. | The election fails and is cleared. | Confirmed |
| The Leader role cards. | Three cards, one for each role (Dictator, President, Commander). The Leader KEEPS their card for their whole term: it is their role. It goes back into the pile and is shuffled only when it is time to draw, so all three cards are in every draw and each is equally likely (a re-elected Leader can draw the same card again). | **Built**, corrected by the designer |
| The outgoing Leader's score. | A term that ends normally is credited 2 half-rounds when the election begins. A Leader eliminated mid-term is credited 1 half-round for the cut-short term, like a coup. It is kept for the record only: an eliminated player can never win, so it never ranks. (If the term had already ended and an election was under way, nothing more is added.) | Confirmed |
| A CANCELLED (or sick) Leader. | Keeps the seat; becoming CANCELLED starts no election. At the end of the term the election runs as normal with no exam: they can vote but cannot stand. | **Built** (tested end to end: a failed amendment drives the Leader to -50) |
| Can a Leader tamper with the exam? | No. The answer key is sealed when the exam is written and nothing can change it afterwards, so answers can't be altered after seeing responses. Questions are free text, so a Leader writes whatever they like. Nothing special is built for the handbook's "insider question" sample, which is only an example, not a rule. | Confirmed |
| What starts a new term? | `install_leader`: the draw, 0 turns played, all three amendment windows open again, and the round counter goes up by one (except the first election). A coup will use the same function. | **Built** |
| What if the exam never arrives? | The server can skip it (`skip_exam`, server only). It also skips itself if the Leader is eliminated while writing. | **Built** |
| What if someone leaves mid-election? | An elimination re-checks the exam and the vote, so it finishes if they were the last one awaited. Ballots for a dead candidate are discarded. | **Built** |

Random numbers: `Rng` is a small seedable generator whose whole state is one whole number (`rng_state`), so a save restores it exactly and tests are repeatable. `rng_state` is server-only: whoever knew it could predict every draw. `Rng.seed_from_clock` must be called when a real game is created.

Not built yet: the exam's effect cards (skip an exam, rig the marking), Loyalists voting with you, "can't run for 2 terms" (Scandal 20), and the trigger that starts `Election.begin("term_ended")` when the Farewell window closes.

Handbook to update: how ties, self-votes and the "running" step work, and that the Leader keeps their role card until the next draw.

## The turn and round loop (built: scripts/term_loop.gd and game.gd; 94 + 75 checks)

`Game.new_game(player_ids, seed)` creates a game (3 to 10 players, 1,000 PSD each, the rest of the box in the treasury, the first election begun). After that everything goes through `Game.handle(state, player, command)`, which routes the command and then lets `TermLoop.settle` move the game on by itself as far as it can. Nothing runs on a timer.

A term: **Inauguration** (the Leader may amend, or `pass_window`) then the **levy**, then every player's **turn** (`end_turn`), then the **Farewell** (amend or `pass_window`), then the term ends and the election begins.

| Question | Decision | Status |
|---|---|---|
| Who takes the first turn? | The player after the last one to take a turn, then round the table in seat order, skipping the eliminated. Only after a coup does the new Leader go first, for that one term. An interrupted term resumes from the last completed turn. In the very first term the first Leader goes first, as after a coup. | Confirmed |
| What is the order within the term? | Inauguration amendment, then the levy, then the turns. So a Leader who amends the levy at the Inauguration changes what is collected that round. | **Built** (tested) |
| Who pays the levy? | Every player who is not eliminated, the Leader included, at the rate in the Constitution (Article 3). What a player can't cover becomes debt. | **Built** |
| Does passing a window use it up? | Yes. A passed window is gone, so the Inauguration amendment can't be made later in the term. | **Built** |
| When can each amendment be made? | Inauguration window: only at the Inauguration. Mid-term: once half the players (rounded up) have played, until the term ends. Farewell: only at the Farewell. None between terms or during an election. | **Built** |
| Does the term wait for an amendment? | At the Inauguration and the Farewell, yes: the term moves on only when the amendment has been decided. The Mid-term amendment doesn't pause the turns. | **Built** |
| A Leader who can't amend (Commander, sick, CANCELLED). | Both windows are skipped automatically. | **Built** |
| Do sick players take their turn? | Yes, and they perform and vote like anyone else. | Assumed |
| A player eliminated mid-term. | Leaves the turn order, and the counts that open the Mid-term and Farewell windows follow. | **Built** |
| The Leader eliminated mid-term. | The term ends, a vacancy election starts, and a new term begins by itself when a Leader is installed. | **Built** |
| How does a term end? | The Leader is credited 2 half-rounds and the election begins (with an exam if the Leader can write one). | **Built** |
| How does the game end? | The server sends `finish_game`. A running term counts as a full round, and the winners are worked out. The game is then closed. | **Built** |
| Is every event in the log exactly once? | Yes: an event is logged by the module that creates it, and a test compares what the commands returned with the log. | **Built** |

### The levy band (built: scripts/levy_band.gd, law.gd; 43 checks)

| Question | Decision | Status |
|---|---|---|
| How does the Leader set the levy (Article 4)? | By amending Article 3, like any other rule. There is no separate command. | Confirmed |
| What if the new levy is outside the band? | A failed check (Article 3: "the levy must stay within the levy band"): the fine, the popularity loss and the used window all apply. | Confirmed |
| Where is the band kept? | In `state.levy_band` (low, high), starting at 25 to 50 and public. The numbers printed in Article 4 are the starting band and are never rewritten (only a Leader's amendment changes the Constitution's words, and only highlighted ones); the UI shows the live band. | Confirmed |
| When does the band shift (Article 5)? | When a term ends, after the Farewell. A term cut short by the Leader's elimination has no shift. | Confirmed |
| Whose popularity? | The sitting Leader's effective popularity (Nepo debuff included). Below minus X raises the band by 10; above plus X lowers it by 10. Exactly X does nothing. | Confirmed |
| What moves? | Both ends together. The low end never drops below 25; if the floor stops it, the high end moves by the same smaller amount, so the band keeps its width. At the floor with nothing to move, there is no event. | Confirmed |
| What happens to the levy? | If it is outside the new band, the game rewrites Article 3's word to the closest value inside it. | **Built** |
| What can Leaders amend in Article 5? | The two X numbers (`levyRaiseBelow`, `levyLowerAbove`, both 20) are bound rules, so an amended number is obeyed. The shift (10), the floor (25), the minus and plus signs and the verbs are not bound; the table enforces them. | Assumed |

## The performance, a player's turn (built: scripts/performance.gd, cards.gd, income.gd)

A turn: the levy has already been paid (at the start of the term). The player draws a **Performance card** at random, everyone is told what it says, and the player has **60 seconds** to perform it. Then everyone else votes **Good or Bad** for **15 seconds**. Popularity moves, a result card may be drawn, and the player ends their turn.

| Question | Decision | Status |
|---|---|---|
| When are the levy and income paid? | The levy at the start of the term, from everyone, as before. Income, and the tax on it, on the player's own turn, before their performance. It feels more personal that way: a Doctor's turn is when they get their 70. | Confirmed |
| Who votes? | Everyone still in the game except the performer. Sick players vote. | Confirmed |
| How does the vote end? | When the 15 seconds are up, or earlier when every voter has voted. A vote that never comes doesn't count. | Confirmed (ending early is assumed) |
| What does the vote do to popularity? | A win is exactly +swing and a loss exactly -swing, however many voted each way (the swing for the table: 6 for five players). A tie changes nothing. This is NOT the amendment rule, which counts every vote. | Confirmed |
| What does the vote do to cards? | More Good: the player draws a Settlement card. More Bad: a Scandal card. A tie, or nobody voting: no change and no card. | Confirmed |
| What starts the voting? | The 60 seconds running out, or the performer finishing early. | Confirmed (finishing early is assumed) |
| Who keeps the time? | The server. `Game.tick(state, now_ms)` moves the game's clock forward and never back. Every deadline is an absolute time on that clock, so a saved game carries on correctly. Time is whole milliseconds because saves hold only whole numbers. | **Built** |
| Are the votes secret? | Yes until the result. Everyone sees WHO has voted, you see your own vote, and the result reveals all of them. | **Built** |
| Are the decks secret? | Yes. The draw piles are server-only, shuffled with the game's own random generator, and reshuffled when empty. | **Built** |
| Does the Activist doubling apply to a performance vote? | No. It applies only when a confrontation is triggered. | Confirmed |
| What do Settlement and Scandal cards DO? | The drawn card is read out to everyone. If it only concerns the player's own PSD and popularity (22 cards), or is one of the 4 that ask for a choice (see Choices), the game applies it: money to or from the treasury (a short treasury pays what it has; what a player can't pay becomes debt) and popularity on the track. Every other card is carried out by the table, and the event says so. Performance cards are just things to perform. | Confirmed (self-only cards first) |
| Where do a card's effects live? | In an `effects` table in `cards.js`, keyed by the start of the card's text. The export fails if a key matches no card or two, or if an amount isn't a number in the card's own text. | **Built** |
| What is still left to the table? | Cards with choices, other players, timing ("keep this", "next term"), corruption markers, the sick duration, Loyalists and Vices. Each needs its own mechanic first. | Next steps |
| Can a turn end before the result? | No. `end_turn` is refused until the performance is done. | **Built** |

### Choices (built: card_effects.gd)

Some cards need the player to decide. The card is drawn and applied as far as it can be, then the turn waits for one `choose` command, and `end_turn` is refused ("Make your choice first") until it comes.

| Question | Decision | Status |
|---|---|---|
| What kinds of choice are there? | An **option** (one of the card's own options, by number), a **role** (any role the player can be given), a **player** (any other player in the game, or only those who hold a role). | **Built** |
| Which cards use them? | Four so far, one of each: "gain 15 popularity or 70 PSD", "choose any role", "a player praises you and you gain the Lawyer role", "swap roles with a player who has a role (they lose 5 popularity)". | **Built** |
| What does the server check? | That a choice is pending, that it is the drawer answering, that the answer has the right type (a whole number, or text; not a bool, a float, a list or nothing), and that it is one of the offered choices. The offer is built when the card is drawn from the live state: eliminated players, yourself, Civilians (for a swap) and roles you already hold are never offered. | **Built** |
| Everyone sees the choice? | Yes, and who it is waiting on. | **Built** |
| What if there is nothing to choose from? | The card says so ("choice_unavailable") and the turn carries on. Example: you already hold every role. | **Built** |
| What if the effect can't be done after the choice? | That part is skipped and the event says why. Example: "you gain the Lawyer role" when you are already a Lawyer; the chosen player still gains their popularity. | Assumed |
| What if the player never chooses? | They have 10 seconds on the server clock (`choiceSeconds`). Then the server chooses at random among the valid answers, using the game's own random generator, so a saved game stays reproducible. The event says it was automatic. | Confirmed |
| Do exams and other votes time out too? | Not yet. Only the performance, its vote and the choice have timers. A real server will need a rule for absent players everywhere. | **Known gap** |
| Can a card choose several players ("choose up to 3")? | Not yet. One choice of one thing. | Next step |

### Income (built: scripts/income.gd)

| Question | Decision | Status |
|---|---|---|
| Who pays income? | The treasury. If it can't cover it, it pays what it has. Total money never changes. | Confirmed |
| Who earns what? | The Leader 100. Secret Agent 80, Doctor 70, Lawyer 50. Activists and Agberos earn nothing. | Confirmed |
| Can roles stack? | Yes, and each role earns its own income, on top of the Leader's 100 if they lead. | Confirmed |
| What is the tax? | The tax rate in Article 2 (so it follows amendments) of what was paid, rounded down, in the player's favour. The tax goes back to the treasury; the player gets the rest. | Confirmed |
| Is income collected against debts? | Yes. It goes through `Debt.receive`, so the oldest debts are paid first. A Leader's income can therefore pull them out of debt. | **Built** |
| Does the event show where the income came from? | It shows the amounts only (gross, tax, net). Roles are public, so nothing is hidden by this. | **Built** |
| Are role cards secret? | No. Everyone can see who holds which roles. (I wrongly assumed they were secret from the card text; you corrected this.) | Confirmed |
| How are roles gained? | From Settlement cards. So dealing roles comes with the card effects. | Confirmed |

## Sickness (built: scripts/sickness.gd)

From the handbook (Doctor & Health, Articles 21 to 24). A round is a term.

| Question | Decision | Status |
|---|---|---|
| What can a sick player not do? | Use role powers, write exams, vote or be voted for (Article 21). Already enforced everywhere via `state.sick`. | **Built** |
| How long is sickness? | A number of rounds, counted down at the end of each round: when the term ends, or when a mid-term vacancy ends it early. The very first election ends no round. A sickness of 1 round started mid-term therefore ends at the end of that same term, before the exam. | Assumed, please confirm |
| Can you be sickened twice? | No stacking: a sick player can't be sickened again, however they became sick (a dose or a card). | Confirmed (handbook) |
| What happens on recovery? | The player is immune for as many rounds as their ORIGINAL sickness lasted. Sabotage lengthens the sickness but not the immunity (handbook example: Concoction 2 rounds, sabotage +2, sick for 4, immune for 2). | Confirmed (handbook) |
| Immunity from a card. | The card gives that many rounds, counted the same way, and never shortens an immunity the player already has. | Assumed |
| Is it public? | Yes: who is sick, for how long, and who is immune. ("Keep track of who is sick and who is immune yourselves.") | Confirmed |
| CANCELLED players. | At -50 or lower a player has no roles until they climb back: no role powers and no role income. They keep the cards. A CANCELLED Leader still collects the Leader's 100 (handbook). | Confirmed (handbook) |
| Cards. | "Sick for 1 round" (Scandal) and "immune for the next 2 terms" (Settlement) are applied by the game. The COVID card (it spreads to nearby players and to whoever makes eye contact) stays with the table. | **Built** (2 cards) |

## The Doctor (built: scripts/doctor.gd)

From the handbook (Doctor & Health, Articles 18 to 24). A Doctor gets 2 charges a round, spent openly on doses.

| Question | Decision | Status |
|---|---|---|
| What is a dose? | Agbo (1 round), Concoction (2 rounds) or Surgery (instant). The Doctor names the price: doses have no fixed prices. Limit 0 to 5,000 PSD. | Confirmed (handbook, CHANGES.md); the limit is mine |
| How does healing go? | The Doctor offers a dose and a price to a sick patient, and secretly chooses the bead in their hand (blue Cure, red Poison). The patient accepts or rejects. If they accept they pay the Doctor at once and a charge is spent. Anyone but the Doctor may guess Sabotage for 10 seconds. Then the bead is revealed and the dose is given. | **Built** |
| Who sees the bead? | Nobody until the dose is given. It lives in server-only state and never appears in an event or a view. | **Built** |
| Bead blue, no guess. | The dose cures: Agbo -1 round, Concoction -2, Surgery recovers at once. | Confirmed |
| Bead red, no guess (Sabotage works). | Agbo +1 round, Concoction +2, Surgery eliminates the patient (their will is carried out). | Confirmed |
| Bead red, right guess. | The Doctor pays the guesser, the patient gets a genuine Cure, and the Doctor loses their licence (the Doctor role card) (Article 19). | Confirmed; the amount is assumed to be the price |
| Bead blue, wrong guess. | The guesser pays the Doctor the price, and the patient is cured (Article 20). | Confirmed |
| "Payment lost". | The patient's payment is never refunded, whatever the bead was. A patient who cannot afford it goes into debt to the Doctor, as agreed payments always do. | Confirmed (your earlier ruling) |
| How many guesses? | One guess per dose: the first to guess is "the guesser". The patient may guess too. | Assumed, please confirm |
| How long to answer, and to guess? | 30 seconds for the patient to answer (silence is a rejection and costs no charge), then 10 seconds to guess. | Assumed, please confirm |
| Does a rejected offer use a charge? | No. A charge is spent when the patient accepts. | Assumed |
| What is "Sicken"? | The handbook doesn't say who may be sickened. I made it a service: the Doctor offers Agbo or Concoction at a price, and a patient who accepts and pays is sick for that many rounds. There is no bead and no guessing. Surgery can't be used to sicken. | Assumed, please confirm |
| Who can be a patient? | Anyone in the game except the Doctor. Healing needs a sick patient. Sickening needs someone who can be sickened (not sick, not immune). | Assumed (the Doctor can't treat themselves) |
| When can doses be given? | During a term, not during an election. Only one dose at a time. | Assumed |
| When is a dose void? | If the Doctor or the patient leaves the game, or the Doctor stops being a Doctor, before it is given. The payment is not refunded. A guesser who has left the game made no guess. | Assumed |
| Do the Doctor's charges come back? | Yes, at the end of every round. | Confirmed |
| Sick or CANCELLED Doctors. | Can't use the power (Article 21 and the CANCELLED rule). | Confirmed |

## Roles (skeleton built: scripts/roles.gd)

The five role cards are held, given, taken, swapped, inherited and rescinded. What each role can DO is not built; this table says what the handbook gives me and what I still need.

| Role | Income | In the handbook files | Built | Still needed from you |
|---|---|---|---|---|
| Doctor | 70 | Doses (Agbo, Concoction, Surgery), no fixed prices. Hidden bead: blue Cure, red Poison. A patient can reject a cure. Sabotage is guessed before the bead is taken. A right guess means the Doctor pays the guesser, gives a real Cure and loses their licence; a wrong guess means the guesser pays the Doctor what the patient paid. | Everything above (see The Doctor and Sickness) | Confirm my assumptions in The Doctor |
| Lawyer | 50 | Signs wills for an agreed fee and collects upkeep every round (Article 54). | Holding and income only | Who must have their will signed, the fee, the upkeep amount, and a command to write a will (there isn't one yet) |
| Secret Agent | 80 | Stays (CHANGES.md); no power described. Cards mention checking coup status and role draws. | Holding and income only | What the Secret Agent does |
| Activist | none | Founds an Activist union (a Settlement card, played any time). Unions exist: recruit, kick, confront the Leader. | The union rules built earlier | How a player becomes an Activist, and how a Settlement card founds a union |
| Agbero | none | Founds an Agbero mob; its leader is the Capon. Can re-form straight away if they hold an Agbero card. | The union rules built earlier | The same |

| Question | Decision | Status |
|---|---|---|
| How many of each role? | Five cards of each (`roleCopies`), so at most five holders. A player never holds two of the same role, but can hold several different ones. | Assumed (never two of the same) |
| What is a player with no role? | A Civilian. There is no Civilian card. | Confirmed (CHANGES.md) |
| Are roles visible? | Yes, to everyone. A coup sticker on a role card is the hidden part. | Confirmed |
| Who may use a role's power? | Someone who holds it, is in the game, and isn't sick (Article 17). Frozen role cards come with corruption markers and a Scandal card. | **Built** (the shared rule) |
| What happens to roles on elimination? | Rescinded (the cards go back in the box), unless willed. | Confirmed (Article 53 and CHANGES.md) |
| Can a will name a different heir for roles? | Yes (Article 56): an optional `role_heir` in the will, by default the heir of the money. A will on hold, or a role heir who is the testator, a stranger or eliminated, means the roles are rescinded. | **Built** |
| Does a role heir become a Nepo Baby? | Yes: anyone who inherits something from a will does, if they actually received a role card. One heir for everything is a Nepo Baby once. | Confirmed |
| The heir already holds that role. | They can't hold it twice, so that card goes back in the box. | Assumed |
| How are roles gained? | From Settlement cards: choose any role, swap roles, gain the Lawyer role (all built, see Choices). Others (found a union, become a Doctor/Lawyer if you hold neither) wait for their mechanics. | **Built** (3 cards) |

Not built yet, and the next steps: each role's power (committed separately), sickness, the union-founding cards, choices of several players, then coups. A role card can carry a hidden coup status: everyone sees a player is a Doctor, but no one knows whether that card has a coup sticker on it (10 stickers). That will be a server-only record when coups are built; one Scandal card lets a rival check it.

Known gaps: if nobody can stand in an election (everyone CANCELLED), the election fails and the game stalls. If only one or two players remain, nothing ends the game; the server must send `finish_game`.

The simulation (`tests/test_game_simulation.gd`) plays whole games with scripted players, including a poor player who falls into debt and is eliminated, and checks after every move: money is neither made nor lost, a player in debt holds no cash, popularity stays on the track, the turn order matches the counts, no dead player is still in play, and a game restored from its save carries on exactly as the original would.
