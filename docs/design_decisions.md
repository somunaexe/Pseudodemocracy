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
3. **A union that contains the Leader (or Vice)** acts on a rival of the Leader's choice instead (Article 17, built): the Unionizer names the rival (one of the Leader's rivals, or anyone outside the group if none). A mob makes the rival pay each member 50; Activists cost the rival one swing of popularity. The amendment carries on untouched. Assumption: the Unionizer names the rival on the Leader's behalf.
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

Not built yet: the exam's effect cards (skip an exam, rig the marking), "can't run for 2 terms" (Scandal 20), and the trigger that starts `Election.begin("term_ended")` when the Farewell window closes.

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

### Kept cards and the hand (built: card_effects.gd, unions.gd)

Some Settlement cards say "keep this card" or "play anytime". They go into the player's hand and are played later with `play_card`.

| Question | Decision | Status |
|---|---|---|
| Which kept cards are built? | The three union cards: found an Activist union, found an Agbero mob, found either (the player then chooses which). The other kept cards (vote of no confidence, 25% levy reduction, the youth wing) need mechanics that don't exist yet and stay with the table. | **Built** (3 cards) |
| Who sees a hand? | The owner sees their cards. Everyone sees how many cards each player holds. The server keeps the hands. | Assumed, please confirm |
| When can a card be played? | At any time, even between terms or during an election ("play anytime"). A card can't be played while a choice is waiting. | Confirmed (card text) |
| Who can found a union? | Anyone in the game who is not already in a union (Article 8: a member of another union can't be recruited). A card that can't be played stays in the hand. | Assumed |
| The "either" card. | Playing it asks which kind (an option choice with the usual 10 seconds, then the server picks at random). If they have joined a union by then, nothing is founded and the event says why. | **Built** |
| What happens to a hand at elimination? | The cards are lost. | Assumed |
| Is a pending choice still tied to a turn? | No: it is one global choice (`state.choice`) that is public. A player can't end their own turn while their own choice waits; other people's turns are unaffected. | **Built** |

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

## Coups (built: scripts/coup.gd)

From the handbook (Part 3, Coups, and the setup and strategy notes). "A coup can happen at any point during any term."

| Question | Decision | Status |
|---|---|---|
| What does a coup cost? | 300 PSD in hand, paid to the treasury, and a coup card. Cash only: a player in debt has no cash, so can't coup (your earlier ruling). | Confirmed; "to the treasury" is assumed |
| What is a coup card? | A role card with a coup sticker. Only the holder can see which of their cards have one (their view lists them); a Secret Agent can check others. A Civilian has none. | Confirmed |
| When does it succeed? | When the challenger's effective popularity (Nepo debuff included) is at least 20 points above the Leader's. So a Leader above +30 can't be couped at all. | Confirmed |
| If they are not 20 ahead? | The coup fails: they lose the coup card (the sticker moves) and the 300 PSD (to the treasury). Nothing else happens. | Confirmed (your answer) |
| When can it happen? | During a term (the Inauguration, a turn, the Farewell), by anyone but the Leader. Not during an election. CANCELLED players have no roles, so no card. | Confirmed; the Leader and CANCELLED rules are assumed |
| What happens on success? | The round stops at once. The couped Leader scores half a round (1 half-round, not 2). The levy band shifts on their popularity at that moment. Sickness and charges move on a round. An amendment under way is abandoned, and a performance or Command Performance ends with the term. | Confirmed |
| Who is Leader next? | The challenger: no exam, no vote, straight to the Leader role card draw and the Inauguration. They take the first turn of the new term. | Confirmed |
| The sticker. | After a coup (or a deal) it comes off the card that was used and goes onto another role card at random, so there are always exactly 10. | Confirmed |
| A deal. | "The challenger may negotiate a deal instead and lose only the coup card": they keep their 300 PSD, the sticker moves, and there is no coup. It needs the same 300 PSD and a coup card, but not the popularity gap. The deal itself is the table's. | Confirmed; the requirements are assumed |
| "You can't attempt a coup for 1 term" (Scandal) | A ban counted in rounds, ended by the round end. It applies to deals too. | **Built** (1 card) |
| Not built | The cards that mention rivals ("neither of you can coup the other for the current term", the Peace Accord, a rival checking your coup status for free) need the Rival label. Vice is not built either (the "keys to the city" card). | Next step |

## Gender (built: scripts/genders.gd)

The handbook's online-version note: "players enter their gender so gendered cards work."

| Question | Decision | Status |
|---|---|---|
| What can a player enter? | Female or male: there are only two options. A player who hasn't said is in neither group the cards name. | Confirmed (your answer) |
| When? | In the lobby: pass it to `new_game`, or each player sends `set_gender`, and may change it until the first Leader is installed. After that it is fixed, so nobody can change it to dodge a card. | Assumed |
| Who can see it? | Everyone: the cards name groups at the table ("every woman"). | Assumed |
| Which cards use it? | One so far: "Collect 5 PSD from every woman at the table" (each other woman pays the drawer; what she can't pay becomes debt). The others need things that aren't built (choosing up to 3 men, Loyalists, a recurring apology). | **Built** (1 card) |

## Sickness (built: scripts/sickness.gd)

From the handbook (Doctor & Health, Articles 21 to 24). A round is a term.

| Question | Decision | Status |
|---|---|---|
| What can a sick player not do? | Use pledges, write exams, vote or be voted for (Article 21). Already enforced everywhere via `state.sick`. | **Built** |
| How long is sickness? | A number of rounds, counted down at the end of each round: when the term ends, or when a mid-term vacancy ends it early. The very first election ends no round. A sickness of 1 round started mid-term therefore ends at the end of that same term, before the exam. | Assumed, please confirm |
| Can you be sickened twice? | No stacking: a sick player can't be sickened again, however they became sick (a dose or a card). | Confirmed (handbook) |
| What happens on recovery? | The player is immune for as many rounds as their ORIGINAL sickness lasted. Sabotage lengthens the sickness but not the immunity (handbook example: Concoction 2 rounds, sabotage +2, sick for 4, immune for 2). | Confirmed (handbook) |
| Immunity from a card. | The card gives that many rounds, counted the same way, and never shortens an immunity the player already has. | Assumed |
| Is it public? | Yes: who is sick, for how long, and who is immune. ("Keep track of who is sick and who is immune yourselves.") | Confirmed |
| CANCELLED players. | At -50 or lower a player has no roles until they climb back: no pledges and no role income. They keep the cards. A CANCELLED Leader still collects the Leader's 100 (handbook). | Confirmed (handbook) |
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

## The Lawyer and wills (built: scripts/wills.gd)

From the handbook (Part 6, Wills & Inheritance, Articles 26 to 31).

| Question | Decision | Status |
|---|---|---|
| How is a will made? | The player proposes it to a Lawyer: an heir for the PSD, optionally a separate heir for the roles (0 means nobody, so the roles are rescinded), a fee and an upkeep. The Lawyer accepts or refuses. No answer in 30 seconds is a refusal. | Confirmed (handbook); the 30 seconds is mine |
| What are the fee and the upkeep? | "An agreed fee" and upkeep each round, so both are numbers the two of them agree, 0 to 5,000. The fee is paid once when the Lawyer signs; the upkeep is charged at the end of every round. | Confirmed (handbook); the limit is mine |
| What if the fee can't be paid? | It becomes debt to the Lawyer, like any agreed payment (your earlier ruling). | Confirmed |
| What is a missed payment? | At the end of a round, having less cash than the upkeep (so also being in debt). The payment is then not made: the will goes on hold and the unpaid upkeep builds up as arrears. | Assumed, please confirm |
| How is a will reactivated? | `will_catch_up` pays all the arrears at once, which needs the whole sum in hand. Upkeep is paid again from the next round (Article 27: "reactivate it anytime by catching up"). | Confirmed; "all at once" is assumed |
| A will on hold at death. | It doesn't count (Article 27): the PSD goes to the treasury and the roles are rescinded. | Confirmed |
| Who knows what is in a will? | Only the testator and the Lawyer. That a will exists is public; its terms (heirs, fee, upkeep) go in events only they receive. The server keeps the wills (and any waiting for a signature) and never puts them in a general view. Each player's view includes their own will, and a Lawyer's the wills they keep. The Secret Agent will be able to check one. | **Built** |
| Can heirs refuse? | No (your ruling). The handbook file still says "each heir accepts or rejects", so it is out of date there. Every heir is a Nepo Baby. | Confirmed (your ruling) |
| What if the Lawyer is gone? | The Lawyer reads the will out, so a will whose Lawyer has been eliminated or has lost the Lawyer role at its owner's death can't be carried out and does not count. Its upkeep stops. | Assumed, please confirm |
| Can a will be changed or torn up? | A new proposal replaces the old will once the Lawyer signs it (and the fee is paid again). `will_revoke` tears it up with no refund. | Assumed |
| Can the Lawyer write their own will? | Through another Lawyer, yes. Not through themselves. | Assumed |
| Do other cards matter? | "Raise your Doctor/Lawyer fee by 20 for the next term" and "convince the Lawyer to draft your will for free" are left to the table. | Next step |

## The Secret Agent and the role cards (built: scripts/secret_agent.gd, roles.gd)

From the handbook (Part 6): "Can check one role card for coup-sticker status and will contents on their turn. Can check the Doctor's bead before it is handed over. Can not be caught sharing what they've discovered, or they lose the role. Can only use this power once per round."

| Question | Decision | Status |
|---|---|---|
| Are the 25 role cards real cards? | Yes. Each of the five roles has five numbered cards. A role is held as a particular card, which moves with the role (granted from the box, taken back, swapped, inherited). | **Built** |
| Where are the coup stickers? | 10 of the 25 cards, chosen at random at the start with the game's own generator, as "attached without looking at the cards' faces". The sticker stays on the card wherever it goes, including back in the box. Reattaching stickers after a coup comes with coups. | **Built** (placing); coups later |
| Who can see a sticker? | Nobody, except a Secret Agent who checks. The cards are server-only; no view or event shows them. Everyone does see who holds which role. | **Built** |
| What can an Agent check? | A card someone holds (is there a sticker?), a player's will (the heirs, the Lawyer, the upkeep and whether it is on hold), or the bead in the Doctor's hand while a heal is being offered or the guessing is open. | **Built** |
| When? | Cards and wills on the Agent's own turn; the bead whenever a heal is under way (the Doctor can't look at their own bead). | Confirmed (handbook says "on their turn" for cards and wills); the bead timing is assumed |
| How often? | Once per round in total, of any kind. A refused check does not use it up. | Confirmed (handbook) |
| Who learns the result? | Only the Agent, in an event sent to nobody else. | **Built** |
| Can a player hire an Agent? | Yes (your rule): on the Agent's own turn, another player asks them to check a card or a will of the asker's choosing for an agreed price (0 to 5,000). The Agent accepts or refuses; 30 seconds of silence is a refusal. If they accept, the asker pays at once (debt if they can't) and both learn the result. | Confirmed (the rule); the limits and the timer are mine |
| What can be hired? | Cards (sticker or not) and wills. The bead is not for hire. | Assumed |
| Does a hire use the Agent's power? | Yes: it is their one check for the round, whoever it is for. A request that can't be fulfilled when the Agent answers (the target changed, the turn moved on, the Agent fell sick) is void and costs nothing. | Assumed |
| Who knows about a hire? | Only the asker and the Agent: the request, the refusal and the report go to them alone. The requests themselves are server-only. | **Built** |
| "Not being caught sharing". | For the table: the game can't hear what players say. There is no command to accuse an Agent yet. | Left to the table |
| Own cards and own will. | An Agent may check their own. | Assumed |
| Can sick, CANCELLED or eliminated Agents check? | No (the shared role rule). | Confirmed |
| The cards "a rival may check your coup-card status for free, once" and "peek at your role card once". | Left to the table until coups exist. | Next step |

## Activist unions and Agbero mobs (built: scripts/unions.gd)

**Words:** Activists form a *union*, led by a *Unionizer*. Agberos form a *mob*, led by a *Capon*. The code has one `Unions` module and one `state.unions` table for both, and every message the server sends uses the right word for the group involved (events carry the group's type so the screen can too). A role's powers are called *pledges*.

From the handbook (Part 6, Activists & Agberos, Articles 7 to 17). Founding a group by playing a card is described under Kept cards and the hand.

| Question | Decision | Status |
|---|---|---|
| Who owns one? | The Unionizer of a union, the Capon of a mob: whoever founded it. Their decisions are the group's. | Confirmed (handbook) |
| How does a union grow? | The Unionizer asks a player to join ("a free social ask"). The player agrees, or refuses, or lets the 30 seconds run out (a refusal). | Confirmed; the consent and the 30 seconds are mine |
| Who can't be recruited? | The Leader, and members of another union (Article 8). A player can only have one invitation at a time. | Confirmed |
| When can a union act? | Recruiting and kicking only on the Unionizer's own turn, or on the Leader's turn if the Leader is a member (Article 9). Sick Unionizers can't. | Confirmed |
| Leaving. | A member (not the Unionizer) may leave on their own turn (Article 10). The Unionizer disperses the union instead. | Confirmed |
| Kicking. | The Unionizer kicks a member just by saying so, on a union turn (Article 10). | Confirmed |
| Dispersing. | The Unionizer may disperse the union at any time ("until its members choose to disperse"). | Assumed (any time, not only on a union turn) |
| Dissolving. | A union that drops to the size in Article 11 (1, an amendable number) dissolves and the card is lost. An eliminated Unionizer dissolves it too. | Confirmed; the Unionizer rule is assumed |
| Does an Activist union linger after acting? | Yes (Article 12): after confronting the Leader it stays, having used its one confront. | Confirmed |
| Does an Agbero mob disperse when it acts? | Yes, at once (Article 13). It used not to; the confront now ends with `union_dispersed`. | **Built** (new) |
| Can Agberos re-form? | After a mob disperses, any of its members who still hold an Agbero role card may form a new one straight away (`union_reform`), once. A union that merely dissolves gives no such right. | Confirmed (handbook); "once" is assumed |
| Does the Activist or Agbero role card matter otherwise? | Not for anything but re-forming. Holding the role earns nothing (they earn no income) and is not needed to be in a union. | Assumed, please confirm |
| Command Performance (Articles 16 and 17) | **Built**, see below. | **Built** |
| "Shared" and "personal" gains (Articles 12 and 13) | Only a description of how the two groups mirror each other ("both sides of the same coin"). It adds no rule. | Confirmed (your answer) |

### Command Performance (built: scripts/command_performance.gd)

| Question | Decision | Status |
|---|---|---|
| Who writes the scenario? | The group's leader (Unionizer or Capon), in free text, 1 to 280 characters. | Confirmed (free text); the limit is mine |
| Who performs it? | A player the Unionizer (or Capon) names, with the final say, for 60 seconds. It can be a regular player or the Leader, as long as they are not in the group. They may finish early. | Confirmed (you said it now reaches regular players) |
| Who votes? | Everyone except the performer, Good or Bad, for 15 seconds, or until all have voted. | Confirmed |
| What moves? | The performer's popularity, by exactly +swing (more Good) or -swing (more Bad). A tie changes nothing. No Settlement or Scandal card. | Confirmed |
| The "union's total popularity vote is doubled". | Each member of the commanding union or mob counts twice, whether it is Activists or Agberos, and even after a mob has dispersed. | Confirmed (the handbook text you gave); applied to the vote on the performance, as a fixed 2 |
| When? | Only on the Unionizer's (or Capon's) OWN turn, once their own performance has finished. Not on the Leader's turn, even if the Leader is a member. The turn can't end until it is over. Once per group per turn, one at a time. Needs 2 members. | Confirmed (your answer); the rest is assumed |
| Article 17: the Leader is in the group. | The Unionizer (or Capon) has the final say on the target, not the Leader. Even if the Leader is a member, the Unionizer names a player outside the group. | Confirmed (your answer) |
| Does a mob disperse? | Yes, the instant it acts (Article 13); its Agbero-card holders may re-form. An Activist union lingers. | Confirmed |
| When is it void? | If the term ends (a coup, the Leader eliminated) or the performer leaves the game. | Assumed |

## Corruption markers (built: scripts/corruption.gd)

Fifteen markers in the box. Cards give them out: eight cards give one to the drawer, one gives one to the drawer and one to a player they choose, one gives one to the chosen player only, and one lets the Leader expose the drawer. A player on their third marker is **frozen**.

| Question | Decision | Status |
|---|---|---|
| What does the third marker do? | Roles frozen, no Settlement cards, -30 popularity (a drop of the base, remembered). | Confirmed (glossary) |
| What does "roles frozen" mean in play? | The player keeps the cards but has no powers, no role income and no coup, as with CANCELLED. The Leader's own pay stays. | Assumed |
| What does "can't pick Settlement cards" mean? | A good vote still moves popularity, but they draw no Settlement card. A bad vote still draws a Scandal. | Assumed |
| How is it lifted? | `pay_fine`: 200 PSD from cash to the treasury, any time; roles back, the popularity drop reversed (only what really came off, if the track stopped it), markers back in the box. Or wait 3 rounds: the freeze lifts, the roles go back in the box for good, the drop stays, the markers go back. | Confirmed (glossary) |
| Can the fine be paid on credit? | No: it must come from cash. | Assumed |
| Does the round of the freeze count as one of the three? | No: 3 rounds means 3 further rounds (`EffectClock`; the same for sickness, immunity from a card, coup bans, Loyalists and Accords). | Confirmed |
| Can a frozen player take more markers? | No; a card that would give one says it was refused. A marker also isn't given when the box is empty. | Assumed |
| Does an eliminated player's marker go back? | Yes. | Assumed |
| The embezzlement card: who decides? | The Leader chooses (stay quiet, split, expose), with `choiceSeconds` to answer, else the server picks at random. The embezzler's turn can't end until it is done. Splitting: the Leader takes half of the 200 from the embezzler (debt if short). Exposing: the embezzler keeps the money and gets a marker. If the embezzler is the Leader, or the seat is empty, nobody chooses. | Assumed |
| "Collect 70 PSD from you as compensation". | The drawer pays the chosen player 70 (debt if short), the chosen player gets a marker, the drawer none. | Assumed |
| "Snitch and split the punishment" (the embezzlement traced card). | See Card families below. | **Built** |

## Rivals (built: scripts/rivals.gd)

| Question | Decision | Status |
|---|---|---|
| What is a rival? | A one-way public label: your list of rivals. It has no rules of its own. It lasts until the rival leaves the game. | Confirmed (glossary), one-way assumed |
| "Choose a rival" when you have none. | Any other player is offered, and the one you choose becomes your rival. With rivals, only they are offered. | Confirmed (glossary), labelling the chosen assumed |
| A rival's scandal (+5 / -15). | You gain 5 at once; the chosen rival loses 15. | **Built** |
| The vote of no confidence card (kept). | Playable any time, without a union. The two of you can't coup each other until the round ends. It also makes the chosen player your rival. | **Built**, rival label assumed |
| Peace Accord. | For 3 rounds, if either of you is successfully couped (overthrown as Leader), the other loses 10 popularity. A failed coup costs nothing. The round the Accord was made in does not count. | **Built** |
| Lose the next Result card draw. | The chosen player's next Settlement or Scandal card is not drawn (they still perform and the popularity still moves). A tie draws no card, so the penalty waits. | **Built** |
| Mob caught on camera. | The drawer's union or mob disperses (whoever is in it, not just the leader) and the other members become the drawer's rivals. | **Built** |
| A rival may check your coup card, Doctor bead or role draw for free; debate a rival; a rival union's pitch. | See Card families below. | **Built** |

## Loyalists (built: scripts/loyalists.gd)

| Question | Decision | Status |
|---|---|---|
| What is a Loyalist? | A player who "votes with you on anything at all" for the number of rounds a card says. You can have many. | Confirmed (glossary) |
| Which votes? | All of them: amendments, elections, performances and Command Performances. | Confirmed ("anything at all") |
| How is "votes with you" played? | The owner votes first. The moment they do, each Loyalist who may vote in that ballot casts the same vote (and their own Loyalists after them). A Loyalist can't vote for themselves while their owner can still vote. The ballot event for them says `with` the owner and never how they voted. | Assumed |
| What if the owner can't vote in that ballot (the performer, the Leader in an amendment, sick, eliminated)? | The Loyalist votes freely. | Assumed |
| What if the loyalty began after the owner voted? | The Loyalist's vote becomes the owner's. | Assumed |
| Can someone follow two owners? | No: a new appointment replaces the old. | Assumed |
| Can there be circles (A follows B who follows A)? | No: an appointment that would make one is refused (the card doesn't offer that player). A chain (A > B > C) is fine. | Assumed |
| What about a Loyalist of an Activist union's member when the union confronts? | The member's vote is automatic (and doubled). Their Loyalists, and theirs, vote against the Leader too, once each, without the doubling. | Assumed |
| How long is "3 terms"? | The round of the appointment is not one of them (EffectClock): 3 rounds is 3 further rounds. | Assumed |
| The appointment card. | The chosen player gets 100 PSD from the treasury and a random role card they can hold (none if they can't hold any: it says so), and becomes the Loyalist. | **Built** |
| "Your current Loyalist (if any) defects" | One Loyalist, chosen at random, leaves. | Assumed |
| "An extra 5 for each male Loyalist you have". | Counts the drawer's own Loyalists (direct) who are male. | **Built** |
| Elimination. | A player who leaves follows nobody and nobody follows them. | **Built** |

## The Vice (built: scripts/vice.gd)

"A second Leader created by a card. A Vice is a Leader in every way, but each term served as Vice scores 1/2 round." The card is the keys to the city.

| Question | Decision | Status |
|---|---|---|
| The keys to the city. | The drawer takes the Leader's role outright if their popularity is higher (the Leader is demoted to Vice and the new Leader keeps the Leader card of the role they took). Otherwise, equal popularity included, the drawer becomes Vice. The Leader drawing it, or a Vice who isn't more popular, gets nothing. | Confirmed |
| How many Vices? | One. A new Vice replaces the old (a displaced Vice is just a player again). | Assumed |
| Does the Vice have a Leader card? | No. The Leader's card decides everything. | Confirmed (amend together) |
| What does the Vice earn? | 90 PSD at the start of their own turn (the Leader 100), plus role income, taxed as usual. | Confirmed |
| Amendments. | The Vice shares the Leader's windows. They amend together: a proposal by either is not put out until the other agrees (`amend_agree`, `amendCosignSeconds` = 30 to answer; silence is a refusal). Nothing is used up until it is agreed, then it goes out as the Leader's amendment. The Leader passing a window ends it for both. | Confirmed |
| Who votes on it, and who gets the result? | Neither the Leader nor the Vice votes. A vote result, or a failed check (fine and popularity loss), applies to both of them. An Agbero mob's steal is paid by the Leader. | Confirmed (both sit out), consequences confirmed (both pay and lose) |
| A sick, CANCELLED or eliminated Vice. | Not needed to agree: the Leader proposes alone. A Commander Leader still can't amend, Vice or no Vice. | Assumed |
| Unions. | A union or mob can't recruit the Vice, as with the Leader; a union with the Vice in it can't confront. | Assumed |
| Scoring. | The Vice scores 1 half-round for a term served (the Leader 2); also if the game is stopped mid-term. The ousted Leader of a swap serves the rest as Vice, so scores 1; the new Leader gets the full 2 at the end. | Confirmed (1/2) |
| When does the Vice end? | With the Leader's term. | Confirmed |
| The Leader is eliminated. | The Vice takes over as Leader and the term goes on, with no election. An amendment under way is abandoned. | Confirmed |
| The Leader is couped. | The Vice stays Vice in the new term, unless the new Leader draws a Dictator card (then there is no Vice), or the Vice is the one who couped (then they are Leader). | Confirmed |
| The Vice is eliminated. | There is no Vice; a proposal waiting for them is dropped. | Assumed |
| Can a Vice coup? | Yes, as any player who isn't the Leader. | Assumed |

## Card families (built: card_effects.gd, peeks.gd, performance.gd, unions.gd)

| Card | How it plays | Status |
|---|---|---|
| Embezzlement traced (Scandal) | The drawer chooses: take it alone (return 200, -20 popularity, one marker) or snitch and split, which asks a second question, whom (any other player). Then both return 100, lose 10 popularity and get a marker. The partner has no say. Slow answers are made at random by the server, both questions. | Confirmed: the partner has no say |
| A rival now has your number (Scandal) | The drawer chooses a player, who gets one free check of the drawer until the round ends: the coup-card status or, while the drawer is handing over a cure, the bead. Using it is private; the drawer is not told. | **Built** |
| "Role draw" in that card | Read as the same thing as coup-card status: roles are public, so the only secret about a role card is its sticker. | Confirmed |
| A rival gets to check your coup-card status (Scandal) | One player linked to the drawer by a rivalry (either has named the other), chosen at random, gets one free check of the drawer, with no time limit but use. Nothing happens, and it is said, if the drawer has no rival. | Assumed |
| A Secret Agent owes you a favor (Settlement) | If another player holds the Secret Agent role, the drawer chooses a player with a role and is shown whether each of their role cards has a coup sticker (private). It uses nobody's once-a-round check. No Agent, no favor. | Assumed |
| Debate a rival (Performance) | The performance becomes a debate. The performer challenges one of their rivals (anyone if they have none) with a topic. They speak 30 seconds each (either can end early), then everyone else votes for the winner (Loyalists vote with their owner). The winner moves +swing and the loser -swing, both. The performer draws a Settlement card if they win and a Scandal if they lose; a tie draws nothing; the rival draws nothing. A performer who doesn't challenge in time is given a rival at random. The rival can't refuse. | Confirmed |
| A rival union wants your backing (Performance) | A union or mob led by one of the performer's rivals (otherwise another union) pitches the performer through a 30-second invitation they answer with `union_respond`; silence is a refusal. The performance goes on as usual. Nothing happens, and it is said, if there is no such union or the performer can't join (the Leader, the Vice, a union member). | Assumed |

## Clocks and the grammar referee (built)

The digital game needs a clock on every step, or one absent player stalls a table. `Game.tick` moves the clock; all deadlines are checked in the game loop.

| Step | Clock | When it runs out |
|---|---|---|
| The Leader writes the exam | `examWriteSeconds` 120 | The exam is skipped and everyone votes. |
| The takers answer | `examAnswerSeconds` 90 | Those who didn't answer have failed. If nobody answered the exam is skipped and everyone votes. |
| A ballot (and each runoff) | `electionVoteSeconds` 60 | Those who didn't vote abstain. A tie runs again, then is decided by lot, so an election always ends. |
| The Inauguration and the Farewell window | `windowSeconds` 60 | A window nobody used is passed for the Leader. A proposal or a vote under way has its own clock. |
| A proposal waiting for the Vice | `amendCosignSeconds` 30 | Refused. |
| The vote on an amendment | `amendVoteSeconds` 45 | Those who didn't vote abstain; the votes cast decide. |

Every start-of-step event carries `ends_at_ms` for the clients' timers. All values are assumed and are in `game_data.js`.

**The grammar referee is switched off** (`grammarReferee: 0`, `GameState.grammar_referee`): every wording is accepted and the vote opens at once. The ruling command still exists for when a referee is decided.

## The remaining cards (built: special_cards.gd, modifiers.gd, schedule.gd, polls.gd, choices.gd, card_trade.gd)

Plumbing: a card with a rule of its own says `special` in its data. **Modifiers** (`state.mods`) are temporary rules on a player, with a first and a last round ("next term" = the next round; "for 2 terms" = the 2 further rounds) and a number of uses. The **schedule** holds payments and penalties for later rounds. A **poll** is a question to several players at once: each answers once (`poll_answer`), silence is the card's default option after `pollSeconds` (30), answers are secret until it closes, and the drawer's turn waits. Questions about cards queue if one is already open. Rounding for money is always in the player's favour.

### Settlement cards

| Card | Rule | Status |
|---|---|---|
| The Old Boys | The drawer picks up to 3 men (the genders at the table). Each man answers in a poll: give 50 PSD, show a role card (the drawer alone sees whether each of his role cards has a coup sticker), or refuse and lose 10 popularity. Silence gives the 50. | Assumed (default) |
| A diaspora relative | 150 now, then 50 at the end of each later round, stopping for good the first time the player's popularity is 0 or below. | Confirmed (card text) |
| You are now a doctor (hospital) | The drawer becomes a Doctor if a card is left, collects 150. Three Doctors share it (the drawer counts as one if they are one): each other Doctor in that share takes 50 of it; each further Doctor, lowest id first after the share, is paid 50 from the drawer's own pocket (debt if short). | Assumed |
| You crowdfunded a flyover | The other players split 200 (rounded up); each chooses in a poll: give their share to the drawer, pay it to the treasury, or lose 10 popularity instead. Silence gives it to the drawer. | Assumed |
| A statue of yourself | The drawer chooses: the Leader pays them 100 at the end of each of the next 2 rounds, or the treasury does and the Leader loses 15 popularity (outed). If the drawer is the Leader the treasury pays and nobody is outed. | Assumed |
| 25% levy reduction | A kept card. It does nothing until its holder is Leader; then it leaves the hand and cuts their own levy by 25% (rounded down in their favour) until they lose the seat. Drawn or bought by the sitting Leader it works at once. It can be sold (`sell_card`, `buy_card`, buyer must have the cash, 30 seconds to answer). | Assumed |
| 20-v-1, designated heckler | The chosen player draws a random Scandal card and it applies to them. | Assumed ("pick" read as draw) |
| The youth wing backs you | A kept card. At the end of the next election everyone who has never been Leader and was seen voting for the holder gets +5 popularity. Then the card is gone, even if they lost. | Assumed |
| Free Settlement card | At their next performance's result the player also draws a Settlement card, whatever the vote said. | Assumed |
| A bloc fundraiser | 20 PSD from the treasury for each other member of the union or mob the drawer is in. | Assumed |
| Skip your next exam | They needn't answer and count as having passed; once. | Confirmed |
| You cut your own salary | +20 popularity. A Civilian loses 50 PSD; someone with a role chooses: lose 50, or skip their next income. | Assumed |
| Look at the top cards | The drawer privately sees the top Settlement and top Scandal cards and may bury each at the bottom (silence leaves them). | Confirmed |
| Lend you 15 PSD | The chosen player hands over 15 PSD now; the drawer repays at the end of the 3rd further round (debt if short). | Assumed |
| Survive a scandal unscathed | Next round only, popularity losses are halved (rounded down). | Confirmed |
| Raise your Doctor/Lawyer fee | Next round the player's dose price or will fee is quietly 20 more (the patient or client pays it). Without either role they choose one to become. | Assumed |
| Up to 2 players must vote with you | Each chosen player answers in a poll: be the drawer's Loyalist for the rest of the term, or lose 5 popularity. Silence agrees. | Assumed |
| Reroll one Result card draw | Next round, the first Result card they draw: they may keep it, or reroll: the first card goes to a player they name (and applies to them) and they draw again. Silence keeps it. | Assumed |
| Popularity floor | Next round, the player's popularity can't be pushed below what it was when the card was drawn. A player already below it gets no protection. | Confirmed |
| Petrol subsidy | 60 PSD at the end of each of the next 2 rounds. | Confirmed |
| National hero | +20 popularity and no CANCELLED status this round. | Confirmed |
| Qualified for benefits | Their next income is not taxed. ("Tax collection" read as the income tax, not the levy.) | Assumed |
| Public holiday | Every other player's next income is skipped. | Assumed |
| Appointee under investigation (Settlement) | The drawer picks a player; both get +20 popularity and 100 PSD from the treasury. | Confirmed |

### Scandal cards

| Card | Rule | Status |
|---|---|---|
| The women playing the game | -5 popularity at the end of each of the next 4 rounds, until the player apologises (`apologize`): the others judge in a poll, and it counts if MORE than half say so (silence says no). They may try again, one at a time. | Confirmed (table decides); majority rule assumed |
| You owe the player 2 seats to your left 150 | The player 2 seats to the left (next seat in id order, skipping the eliminated) holds an IOU for 150, payable on demand. It is an IOU, not a debt in the money system (a player in debt holds no cash). Until it is paid the creditor may block any of the drawer's Result cards: they are asked in a poll when one is drawn (silence lets it through). The owner may pay it (`pay_iou`, needs 150 in hand) or the creditor may demand it (`demand_iou`: the owner pays what they have and the rest becomes debt). Either ends the right. | Assumed |
| Spoke horribly at a debate | The drawer is a Civilian (roles back in the box). If already a Civilian they name a player with a role who becomes one instead (the game can't hear who "speaks to" them). | Assumed |
| Nobody shows up to your rally | -10 popularity; if in a union or mob the drawer chooses another member to leave it. | Confirmed |
| Tax returns leaked | The player seated next on the left sets a "transparency fee" from 10 to 50 (0 to 50 if the drawer is a Civilian), paid to the treasury. Silence sets the smallest. | Assumed ("closest" = next seat) |
| Flyover collapsed | The drawer pays 200 split among the others (rounded up). Each chooses: accept the share (the drawer pays them), redirect it to the treasury (the drawer pays it there), or reject it (the drawer keeps it). Silence accepts. | Assumed |
| Tax break ruled illegal | The next levy is doubled, once. A Leader's levy-setting power (amending the Levy article) is suspended this round. | Confirmed |
| Lost the 20-v-1 | The drawer becomes a Civilian and the player opposite (half the table away) takes the roles; a role they already hold goes back in the box. | Confirmed |
| Delayed Reckoning | Face-down (everyone knows it exists). The next time the levy goes UP, by an amendment or by the levy band moving it, it flips: -5 popularity and the difference in levy is repaid to the treasury. | Assumed (difference paid once) |
| Pothole | Pay 50, or ask a player to "read it aloud" and each pays 25 (the helper has no say). | Assumed |
| A satirist | -15 popularity. In the next 2 rounds anyone may cite it once against one of the drawer's Settlement cards before it resolves: a poll to the others, the first to cancel wins. | Confirmed |
| Term limits | -25 popularity; can't be a candidate in the next 2 elections (can still vote). | Confirmed |
| Role card frozen | Next round the drawer can't use any role's power. | Assumed |
| Choose a player: repay 50 / criticize / may peek / peace offering | The chosen player is paid 50; or -5 for the drawer and +5 for them; or gets a once-only free look at the drawer's coup cards; or is paid 30 while the drawer loses 7 popularity. | Confirmed |
| Lose your next Settlement draw | The next Settlement card the drawer would draw is lost; a Scandal draw doesn't use it up. | Confirmed |
| Marking your exam | The next exam the drawer sits: the Leader, who marks, may decide whether they pass (`rig_exam`, secret until the marks are read). The marking waits for the decision or the exam clock; the card is used either way. | Assumed |
| COVID | The drawer and the players seated on either side are sick for 3 rounds (the immune and the already sick are skipped, and it is said), and so is the last player they spoke to, whom they name. The sentence about eye contact is something the game can't see: the table plays it. | Assumed |
| Missed your policy announcement | Their next income is skipped. | Confirmed |
| Extra Performance card | On their next turn, when the first performance is over a second begins. | Confirmed |

## Roles (skeleton built: scripts/roles.gd)

The five role cards are held, given, taken, swapped, inherited and rescinded. What each role can DO is not built; this table says what the handbook gives me and what I still need.

| Role | Income | In the handbook files | Built | Still needed from you |
|---|---|---|---|---|
| Doctor | 70 | Doses (Agbo, Concoction, Surgery), no fixed prices. Hidden bead: blue Cure, red Poison. A patient can reject a cure. Sabotage is guessed before the bead is taken. A right guess means the Doctor pays the guesser, gives a real Cure and loses their licence; a wrong guess means the guesser pays the Doctor what the patient paid. | Everything above (see The Doctor and Sickness) | Confirm my assumptions in The Doctor |
| Lawyer | 50 | Signs wills for an agreed fee and collects upkeep every round (Article 26). | Everything in The Lawyer and wills | Confirm my assumptions |
| Secret Agent | 80 | Checks a card's coup sticker or a will on their turn, or the Doctor's bead; once per round. | Everything in The Secret Agent | Confirm my assumptions |
| Activist | none | Peaceful union member. Founds a union with a Settlement card, recruits, kicks, confronts the Leader. | Everything in Unions except Command Performance | Command Performance and shared gains |
| Agbero | none | Violent mob member; the Capon leads. The mob disperses when it acts, and can re-form straight away for those who hold an Agbero card. | Everything in Unions except Command Performance | Command Performance and personal gains |

| Question | Decision | Status |
|---|---|---|
| How many of each role? | Five cards of each (`roleCopies`), so at most five holders. A player never holds two of the same role, but can hold several different ones. | Assumed (never two of the same) |
| What is a player with no role? | A Civilian. There is no Civilian card. | Confirmed (CHANGES.md) |
| Are roles visible? | Yes, to everyone. A coup sticker on a role card is the hidden part. | Confirmed |
| Who may use a role's power? | Someone who holds it, is in the game, and isn't sick (Article 17). A player frozen by corruption can't either (see Corruption). | **Built** (the shared rule) |
| What happens to roles on elimination? | Rescinded (the cards go back in the box), unless willed. | Confirmed (Article 53 and CHANGES.md) |
| Can a will name a different heir for roles? | Yes (Article 56): an optional `role_heir` in the will, by default the heir of the money. A will on hold, or a role heir who is the testator, a stranger or eliminated, means the roles are rescinded. | **Built** |
| Does a role heir become a Nepo Baby? | Yes: anyone who inherits something from a will does, if they actually received a role card. One heir for everything is a Nepo Baby once. | Confirmed |
| The heir already holds that role. | They can't hold it twice, so that card goes back in the box. | Assumed |
| How are roles gained? | From Settlement cards: choose any role, swap roles, gain the Lawyer role (all built, see Choices). Others (found a union, become a Doctor/Lawyer if you hold neither) wait for their mechanics. | **Built** (3 cards) |

Not built yet, and the next steps: choices of several players, the other kept cards, and a first Godot screen. A role card can carry a hidden coup status: everyone sees a player is a Doctor, but no one knows whether that card has a coup sticker on it (10 stickers). That record now exists, server-only; coups will use it.

Known gaps: if nobody can stand in an election (everyone CANCELLED), the election fails and the game stalls. If only one or two players remain, nothing ends the game; the server must send `finish_game`.

The simulation (`tests/test_game_simulation.gd`) plays whole games with scripted players, including a poor player who falls into debt and is eliminated, and checks after every move: money is neither made nor lost, a player in debt holds no cash, popularity stays on the track, the turn order matches the counts, no dead player is still in play, and a game restored from its save carries on exactly as the original would.

## Performance cards with mechanics

Built in `scripts/performance_cards.gd`; state lives in `state.term["act"]["special"]` and `["card_data"]`.

| Card | What happens |
|---|---|
| Useless product | The table may buy it; Good vote pays the performer, a Bad vote costs them popularity. |
| Neighbour dispute | The player on the performer's right is the rival; the table's vote decides who wins 100 PSD (the Leader is asked to judge if neither is the Leader). |
| Custody (the 4th player) | Same shape as the dispute; the winner takes 150 PSD from the treasury and the loser pays 50 costs. |
| Loan pitch | The performer picks a lender, who sets the interest (0, 10, 25 or 50%, or refuses) and lends 200 PSD, repaid in 3 rounds. |
| Convenient excuse | The sold excuse skips the buyer's next exam. |
| Election fraud | Believed: +10 popularity; not believed: -15. |
| Mediation | Two players are mediated live; a Good vote pays both. |
| Pitch your union/mob | The performer's union invites a player in no union; with no union nothing happens. |
| Word wrestle | A named opponent; whoever sends `concede` first loses 20 PSD to the treasury. |

Tests: `tests/test_performance_cards.gd`.

## Balance pass (first reading)

Run with `godot --headless --script tests/test_game_simulation.gd -- balance` (about 5 minutes; 20 games per size, 10 terms, scripted players; `-- one PLAYERS SEED TERMS` replays one game).

| Players | Eliminated / game | Moves / game | Richest ÷ poorest at the end | Coups / game | Markers / game | Sick / game |
|---|---|---|---|---|---|---|
| 3 | 0.0 | 237 | 2.0 | 0.1 | 0.4 | 0.8 |
| 4 | 0.2 | 462 | 2.2 | 0.3 | 1.6 | 1.5 |
| 5 | 0.2 | 464 | 2.7 | 0.2 | 0.9 | 2.5 |
| 7 | 0.0 | 727 | 3.8 | 0.3 | 1.1 | 2.5 |
| 10 | 0.0 | 1155 | 4.4 | 0.8 | 1.9 | 3.0 |

What it says, and what it cannot say:
- Nothing runs away: nobody sits in debt at the end, wealth stays within 2 to 4.5 times between richest and poorest, and the game's money is conserved.
- The simulated players are scripted, not strategic (they follow fixed rules, never scheme), so these numbers show that the rules are stable, not that they are fun. Real tuning needs real tables: leave `game_data.js` as it is until a playtest.
- Found by the run: with everyone else eliminated, the last player sat in a game nobody could play. The game now ends when fewer than two players are standing (the survivor wins).

## The server (phase 2, built: server/)

| Question | Decision | Status |
|---|---|---|
| Structure | `server/server_core.gd` holds everything (rooms, seats, tokens, who is told what) and knows nothing of sockets; `server/ws_server.gd` only moves bytes (WebSocket, ws://, put a TLS proxy in front for wss://). | **Built** |
| Who is a player? | The connection's seat, never a field in the message. A command naming another player is ignored. | **Built** |
| What a client receives | Only events it may see (`Views.deliver`) and its own `state_view`; the long event log only on join, resume and `sync`. A refusal goes only to whoever asked. | **Built** |
| Rooms | 4-letter code (no I or O), 3 to 10 players, host starts, seats are fixed in join order when it starts, names 1 to 24 characters and unique in the room, at most 200 rooms. | Assumed |
| Reconnecting | A 128-bit random token from the operating system is the key to a seat; `resume` returns the seat and the full picture; the newest connection wins. A dropped player stays seated and the game's clocks carry on without them. | **Built** |
| Abuse | Messages over 64 KB, bad JSON, unknown types and floods (20 at once, 8 more per second) get an error and change nothing. Clients can't end the game or rule on grammar (server only). | **Built** |
| Saving | Every accepted move is saved to its own file (`<CODE>.json`, written then renamed so a crash never leaves half a file) BEFORE players are told. A refused move or a look at the table is not saved. | **Built** |
| Restart | `load_saved` brings rooms back; players resume with their token. The game clock continues from where it was (downtime costs no deadlines) and downtime is not idle time. Bad or other-version saves are skipped. | **Built** |
| Clean-up | Unstarted empty room: 1 hour; finished game: 1 day; running game nobody touched: 1 week. The clock moving a game does not count as touching it. | Assumed |
| Accounts | None: a name and a secret token per room is the identity (see docs/deploying.md). | Assumed |
| Hosting | Dockerfile, compose with Caddy for TLS, systemd unit: written, **untested**. | Written |

Checks: `tests/test_server_core.gd` (pretend connections) and `tools/smoke_server.sh` (the real WebSocket server, one client).

## A player who walks away mid-turn

| Moment | What happens | Status |
|---|---|---|
| Performing, and the table's vote | The clocks already close them (60 s, then 15 s of voting). Nobody's input is needed. | Built earlier |
| A question to them (card choice, poll, offer, invitation, exam) | Each has its own clock and a default answer. | Built earlier |
| After the performance, before "end turn" | **New:** after `turnEndSeconds` (15) the server ends the turn for them (`turn_ended` with `auto: true`), through the normal end-of-turn steps (debt term, Nepo). The count only runs while nothing else holds the turn up and restarts afterwards. Before this, the table would wait for ever. | **Built** |
| Absent for several turns | **New (your call):** a turn the server had to end where the player did nothing at all is a *missed turn*; `missedTurnLimit` (2) missed turns IN A ROW eliminate them (reason `absent`; will, cash and roles go as for any elimination). Any turn they act in or end themselves restarts the count. Others acting on their turn (voting) does not count for them. Shown to everyone as `missed_turns`, with a `turn_missed` event as a warning. In a row, not in total, is my reading. | **Built** |
