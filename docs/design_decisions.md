# Design decisions

Decisions made while building the digital version, so they aren't lost.
Add a line whenever the handbook is silent and the table has to decide.

| Question | Decision | Status |
|---|---|---|
| A player can't afford a payment (e.g. the Agbero Confront steal, 50 × union size). | They go into debt: PSD may go negative. | Decided, not built yet. |
| What happens to a player in debt each round? | The levy and tax are added to their debt. | Decided |
| How long can debt last? | At most 3 rounds, then the player is eliminated. | Decided. Open: does leaving debt reset the count? Which moment counts a round? |
| Can a player in debt launch a coup? | No. A coup costs 300 PSD, and they don't have it. No special rule needed. | Decided |
| Does the tie-break `(popularity + 50) x PSD` work with negative PSD? | Unclear: it can rank a more popular debtor below a less popular one. See notes below. | **Open** |
| Where does grammar checking for amendments happen? | Server decides. Method still open (referee, tool, or word lists). | Open |
| Amendment words are validated on the server, never trusted from the client. | Server-authoritative. | Decided |

## Notes

**Tie-break with debt.** `(popularity + 50) x PSD` with negative PSD flips the meaning of popularity:
two players with -100 PSD, one at +40 popularity (score 90 x -100 = -9000) and one at -40 popularity
(10 x -100 = -1000). The less popular debtor ranks higher. Also, a CANCELLED player (-50 popularity)
scores 0 whatever their PSD, which beats any debtor. Needs a rule, e.g. "debtors rank below everyone
with PSD >= 0, then by PSD".

**Open questions about debt:** who is owed (treasury, or the Agbero union)? Does debt pass to heirs
(Nepo Baby)? What does a player owing money do in the Doctor / Lawyer fee flows?
