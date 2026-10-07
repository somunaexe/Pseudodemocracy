# Pseudodemocracy: rule changes to catch up on

These are the decisions made since the older rulebook, which still had a 500 PSD coup, Herbs/Medicine and a "Coup Window" step. **Where this file or the data files disagree with what you already have, these win.**

## New: data files (single source of truth)
- `data/game_data.js`: every number in the game, plus fail-fast checks.
- `data/articles.js`: the 31 Constitution articles. `__word__` marks an amendable word.
- `data/cards.js`: all 150 cards and the card glossary.

Import these files and never retype their values. The printed rulebook is generated from the same three files.

## Setup & money
- Every player starts with **1,000 PSD**. The highest note is 100.
- All money not dealt to players goes to the **treasury**: 12,550 − 1,000 × players. The treasury gives change.

## Rounds
- **A term is one round**: every player takes one turn.
- **Mid-term** comes once at least half the players have played (round up).
- **Exam:** the Leader writes a **sealed answer key** before the exam. The pass mark is more than 50% (an article).
- **Win:** most rounds as Leader. A term cut short by a coup scores **½**. A term still running when the game stops counts as a full round. **Tie-break:** (popularity + 50) × PSD.
- **A sick or CANCELLED Leader** keeps the seat and still collects income, but can't use powers or amend.

## Coups
- They cost **300 PSD** + 1 coup card, and the challenger needs **20+** more popularity than the Leader. There's no "coup zone" requirement.
- A coup can happen **at any time in any term**. A successful coup stops the round, and the new Leader starts a fresh term (no exam or vote) and takes the first turn.
- A Leader above +30 popularity can't be couped. This is intended.

## The Constitution (new system)
- The rulebook holds **rules**, which are locked. The Constitution holds **articles**, which are amendable.
- Leaders can **rewrite** articles but can't add or remove them. Only **highlighted** words can change, one word for one word. A/an/the go with the word they belong to, and symbols count as words.
- There are **3 amendment windows** per term: Inauguration, Mid-term and Farewell.
- **The Leader writes the amendment privately, then announces it.** It's checked for correct English and for changing only highlighted words, with no vote on this. If it fails, the article reverts, the window is used up, the Leader pays **100 PSD** to the treasury, **and** loses **base swing × number of other players** in popularity (5 players: 6 × 4 = −24).
- **Amendment vote:** everyone except the Leader votes at once, with no discussion. **Keeping or rejecting** the amendment is a flat count (one vote each): a **Dictator's** amendment always stands, a **President's** needs a majority, and a **Commander** can't amend. **Popularity is scaled by player count:** each vote for raises the Leader's popularity by the base swing, and each vote against lowers it by the base swing.
- The **levy, levy band and band shift are now articles.** If the band shifts, the levy moves to the closest value inside it. There's no separate Leader-type levy rule.
- **Coup principle:** anything that decides whether, how or by whom a coup can happen stays a locked rule.

## Votes & cards
- **Performance votes:** everyone except the performer votes.
- **Result cards are now called Settlement (good vote) and Scandal (bad vote).**
- **Cards beat rules:** if a card contradicts the rules or the Constitution, follow the card.
- Card terms: Rival, Loyalist, Corruption marker (3 markers → frozen, −30 popularity; pay 200 PSD or wait 3 terms), and **Vice** (a second Leader, scoring ½ round per term).

## Unions
- Unions recruit, kick or act only on the **unionizer's** turn, and on the **Leader's** turn if the Leader is a member.
- The unionizer owns the union and kicks members just by saying so. A union lasts until its members disperse or it drops to 1 member.
- An Agbero mob's leader is called the **Capon**. Agberos can re-form straight away if they hold an Agbero card.
- **Confront the Leader** triggers when the Leader is **amending an article**, on any turn. An amendment blocked by Agberos uses up that window.

## Doctor & health
- Anything a Doctor gives is a **dose**: **Agbo** (±1 round), **Concoction** (±2), or **Surgery** (instant recovery, or elimination through sabotage only). **Doses have no fixed prices.**
- Doctors can offer cures, and patients can reject them.
- **No stacking:** a sick player can't be sickened again. After recovering, they're **immune** for as long as their original sickness lasted. This applies to sickness from any source. The table tracks it from memory.
- Eliminated players' roles are **rescinded** unless willed.

## Components
- **Doctor's beads replace prescription cards:** the Doctor announces the dose and hides a bead in their hand — blue = Cure, red = Poison (`game_data.js` → `beads`). Sabotage is guessed before the patient takes the bead.
- **Coup stickers:** a coup card is any role card with a coup sticker attached. Stickers are attached before the game without looking at the cards' faces; after one is used, anyone may reattach it to another role card, again without looking.
- **No Civilian card:** a player with no role is a Civilian. **No Rival tokens:** Rival is just a card keyword.

## Roles
- **Removed:** Legislative, Banker, Teacher and PM. The Secret Agent stays.
