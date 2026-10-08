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
- Elimination is built for cash, debt, wills, unions and the Nepo Baby debuff. Roles are not (see Elimination below).
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
- **Roles** don't exist in the game state yet, so they can't be inherited or rescinded.
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
| Who takes the first turn? | The player after the last one to take a turn, then round the table in seat order, skipping the eliminated. Only after a coup does the new Leader go first, for that one term. An interrupted term resumes from the last completed turn. The very first term starts at the first seat (no previous player, no coup). | Confirmed (first-term rule assumed) |
| What is the order within the term? | Inauguration amendment, then the levy, then the turns. So a Leader who amends the levy at the Inauguration changes what is collected that round. | **Built** (tested) |
| Who pays the levy? | Every player who is not eliminated, the Leader included, at the rate in the Constitution (Article 3). What a player can't cover becomes debt. | **Built** |
| Does passing a window use it up? | Yes. A passed window is gone, so the Inauguration amendment can't be made later in the term. | **Built** |
| When can each amendment be made? | Inauguration window: only at the Inauguration. Mid-term: once half the players (rounded up) have played, until the term ends. Farewell: only at the Farewell. None between terms or during an election. | **Built** |
| Does the term wait for an amendment? | At the Inauguration and the Farewell, yes: the term moves on only when the amendment has been decided. The Mid-term amendment doesn't pause the turns. | **Built** |
| A Leader who can't amend (Commander, sick, CANCELLED). | Both windows are skipped automatically. | **Built** |
| Do sick players take their turn? | Yes. (A turn has no content yet.) | Assumed |
| A player eliminated mid-term. | Leaves the turn order, and the counts that open the Mid-term and Farewell windows follow. | **Built** |
| The Leader eliminated mid-term. | The term ends, a vacancy election starts, and a new term begins by itself when a Leader is installed. | **Built** |
| How does a term end? | The Leader is credited 2 half-rounds and the election begins (with an exam if the Leader can write one). | **Built** |
| How does the game end? | The server sends `finish_game`. A running term counts as a full round, and the winners are worked out. The game is then closed. | **Built** |
| Is every event in the log exactly once? | Yes: an event is logged by the module that creates it, and a test compares what the commands returned with the log. | **Built** |

Not built yet, and the next steps: what a turn contains (Performance cards), income and tax, the Leader setting the levy within its band (Article 4) and the Levy Band Shift at the end of a term (Article 5, which also needs its numbers bound as rules), coups.

Known gaps: if nobody can stand in an election (everyone CANCELLED), the election fails and the game stalls. If only one or two players remain, nothing ends the game; the server must send `finish_game`.

The simulation (`tests/test_game_simulation.gd`) plays whole games with scripted players, including a poor player who falls into debt and is eliminated, and checks after every move: money is neither made nor lost, a player in debt holds no cash, popularity stays on the track, the turn order matches the counts, no dead player is still in play, and a game restored from its save carries on exactly as the original would.
