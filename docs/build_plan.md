# Build plan, in order

The rules engine (pure GDScript, tested headless) is nearly complete. What is left is, in order:

## Phase 1: finish and harden the rules engine (days, not weeks)
1. **Timeouts everywhere.** Exams, elections, amendment windows and the Leader's pass have no clock yet, so one absent player can stall a table. Add per-step deadlines and a sensible default (skip, abstain, pass) for each.
2. **The grammar referee.** Amendments need a ruling on whether the new wording is correct English (`rule_grammar` is server-only today). Decide how: a referee player, word lists, or a language model call. This is the biggest open design question.
3. **Remaining cards the table still plays by hand.** Exam effect cards (skip an exam, rig the marking), "can't run for 2 terms" (Scandal 20), COVID (spreads sickness to neighbours), Loyalist "choose up to 2", the other kept cards, and any card still read out and carried out by the table.
4. **(done)** **Article 17** (a union or mob that includes the Leader acts on a rival of the Leader's choice) and the Command Performance rules when the Leader is a member.
5. **Handbook sync.** Apply the pending edits to the handbook (heirs can't refuse, pledges, Vice earns 90, Command Performance, coup failure, two genders, the further-rounds rule, Vice, card changes) so the printed rules and the code agree.
6. **(first pass done; real tuning needs playtests)** **Balance pass.** Run many simulated games with varied player counts and read the numbers: how often players are eliminated, how long a game lasts, whether coups, markers or the Vice dominate. Tune `game_data.js`.

## Phase 2: the server (the game is online-only)
7. **(done)** **Network layer.** One authoritative server process (Godot headless) that owns every `GameState`, receives commands from clients, runs `Game.handle`, and sends each player only `Views.deliver` events and `state_view`. Reject malformed or oversized input with the existing `parse_command`.
8. **(done)** **Lobby and rooms.** Create/join a room by code, set name and gender, pick player count (3 to 10), start the game. Reconnect after a dropped connection by player token.
9. **(done)** **Clock and persistence.** A real server clock feeding `Game.tick`, plus saving the state to disk on every move so a server restart carries on (the serializer already round-trips).
10. **(done, hosting files untested)** **Accounts and hosting.** Minimal identity (name plus a secret token), then deploy to a small VPS or a Godot-compatible host with TLS (WebSocket).

## Phase 3: the client (Godot UI), in the order a game needs it
11. **(done)** **Lobby screen and connection.** Name, room code, ready, player list.
12. **(done, first version)** **Table view.** Players around the table with popularity, cash, role badges, Leader/Vice, unions and mobs, markers, rivals and loyalists; the treasury; the current Article texts.
13. **(first part done)** **The turn.** Performance card display, timers, Good/Bad voting, debates (sides, topic, vote), Settlement and Scandal reveals, choices (option, role, player pickers).
14. **(done, first version)** **Elections and amendments.** Exam writing and answering, ballot, amendment proposal editor (highlighted words only), co-sign prompt, voting, results.
15. **Private panels.** Your will, hand of kept cards, Secret Agent and peek reports, Doctor doses and bead guessing, hiring an Agent, free checks.
16. **Actions menu.** Coups, deals, unions (recruit, respond, command performance, confront), pay fine, wills.
17. **Event log and notifications.** A readable feed built from the events, with toasts for things aimed at you (offers, invitations, timeouts).
18. **End of game.** Final ranking screen and rematch.

## Phase 4: polish and release
19. **Art, sound and Nigerian-political flavour.** Card art, role portraits, table, music and effects.
20. **Accessibility and phones.** Layouts for phone and tablet, larger text, colour-blind-safe markers.
21. **Playtests.** Real tables of 3, 5 and 8 players; record where they stall or argue about a rule; fix the handbook and the engine together.
22. **Release.** Export builds (Android, iOS, web, desktop), store pages, privacy policy, moderation of free-text (topics, names), basic anti-cheat review (the server is already authoritative).

## Order of work, short version
Phase 1 items 1 and 2 first (they block everything else). Then the server (7 to 9) with a bare-bones client (11 to 13) so a real table can play end to end. Then the rest of the client in the order above, then polish.
