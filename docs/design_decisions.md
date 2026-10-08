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
- Elimination is built for cash, debt, wills and unions. Roles and the Nepo Baby debuff are not (see Elimination below).
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
- **Nepo Baby debuff.** A temporary reduction that is lifted afterwards (not three permanent hits). It needs a base popularity plus modifiers; see the answer in the chat history, and `docs/architecture.md` once built.
- **The Leader is eliminated.** The seat is vacant and a new Leader is voted for. Built: the seat is vacated and an amendment in progress is abandoned (its window stays used). Not built: the election itself.

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
| Which words does the game enforce? | A "binding" ties one highlighted word to one rule (data/source/articles.js). 12 of the 116 highlighted words are bound today. | **Built** |
| What about the other 104 highlighted words? | Free text, enforced by the table as in the physical game. The Constitution shows them but the game does not apply them. | **Built** |
| What may a Leader write in a bound word? | Only a word the game can read: a whole percentage (30%), a whole number in a range, or one of a fixed list of words (single, double, triple, quadruple; plus or minus). | **Built**, please confirm |
| What happens if they write something else (e.g. "banana" as a tax rate)? | The proposal is refused. No fine, no popularity loss, the window is not used, and they can try again. | **Built**, please confirm |
| What still costs the fine? | Breaking "one word for one word": changing a fixed word, writing two words, or leaving a word blank; or a bad grammar ruling. | Unchanged |
| When does an amended rule apply? | From the moment the amendment stands. While it is being voted on, the old law applies. | **Built** |
| What stops the data and the text disagreeing? | The export fails if a bound word's starting text differs from game_data. | **Built** |

Rules enforced today:

| Rule | Article | Reads as |
|---|---|---|
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
