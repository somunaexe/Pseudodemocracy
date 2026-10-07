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
| A debt is owed to a player who is then eliminated. | The debt is cleared, unless they have an heir: then the heir is owed instead. | **Built** (`Debt.eliminate`, `GameState.heirs`) |
| Paying it off and falling back in. | Paying off all debt resets the count to zero. | Decided |
| Can a player in debt launch a coup? | No. A coup costs 300 PSD and they don't have it. No special rule needed. | Decided |
| Do heirs inherit debt? | Yes. A Nepo Baby inherits debt along with the estate. | Decided. Open: can they reject a debt-only estate? |
| Tie-break `(popularity + 50) x PSD` with negative PSD. | Anyone below 0 PSD ranks under everyone at 0 or above; among debtors the smaller debt wins. | **Built** (scripts/scoring.gd, tested) |
| Tie-break shift: 50 or 51? | 51. A CANCELLED player (-50) scored 0 whatever their PSD; now they score 1 x PSD. Handbook wording must change to `popularity + 51`. | **Built** (`tieBreakShift` in game data) |
| Can a player pay part of what they owe? | Yes. They pay what they have; the rest becomes a debt to the same creditor. | **Built** (scripts/debt.gd, tested) |
| When is a debt term counted? | At the END of the debtor's own turn, if they still owe anything. The 3rd such turn eliminates them. | **Built** |

Open debt questions:
- All income must go through `Debt.receive()` (roles, cards, treasury payouts), or it will skip collection.
- Elimination by debt is only *marked* so far. PSD to the treasury, roles rescinded, wills and heirs are not wired up.
- Can an heir reject a debt-only estate?
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
| Is a player's PSD, debt and popularity public? | Yes. | Assumed, please confirm |
| Is union membership public? | Yes (the rules say you can't recruit a member of another union, so players must be able to tell). | Assumed, please confirm |
| Are heirs public? | Yes, once the player is eliminated (the Lawyer reads the will out). | Assumed, please confirm |
| Votes during an amendment | Hidden until the result; everyone sees who has voted, and you see your own. | **Built** |
| Wills, role cards, coup stickers, Doctor's beads, exam keys | Server only, when they are built. | Not built |
