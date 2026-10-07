# Architecture

The game is **server-authoritative**. A phone never changes the game; it asks, and the
server decides using the rules in `scripts/`. Everything below runs headless, so every rule
has a test (`tools/run_tests.sh`).

```
 phone (UI)                       server
 ----------                       ------
  command  ----------------->  handle(state, player_id, command)
 {"type": "vote", ...}             |  1. is this command allowed in the current phase?
                                   |  2. is this player allowed to do it? (Permissions)
                                   |  3. is the content valid? (Amendment.validate_words)
                                   |  4. change GameState (Debt, Scoring, ...)
  event    <-----------------   [events]  plain data, each with an audience
 {"type": "vote_cast", ...}
```

## The four patterns

1. **Commands.** Players only send requests. A refused command changes nothing and is not logged.
2. **Events.** `handle` returns plain-data events (`scripts/events.gd`). Each has an `audience`
   (empty = everyone). Secrets stay in server state; events carry only what the audience may see.
   Example: `vote_cast` says who voted, never how. `amendment_resolved` reveals it.
3. **State machine.** `AmendmentFlow.ALLOWED_COMMANDS` lists what each phase accepts:

   ```
   NONE --propose--> PROPOSED --rule_grammar(ok)--> VOTING --last vote--> NONE
   PROPOSED / VOTING --confront(Agbero)--> NONE (blocked)
   PROPOSED / VOTING --confront(Activist)--> same phase, votes weighted
   bad wording or bad grammar --> NONE (fine + popularity loss)
   ```
4. **Data-driven.** Numbers come from `data/game_data.json`, the Constitution from
   `data/articles.json`, both generated from `data/source/*.js` by `tools/`. No game number
   is typed into GDScript.

## Rules of the codebase

- Money only moves through `Debt.charge` and `Debt.receive`.
- Anything a player sends is untrusted: check its type before using it.
- Validate and store the same normalised string.
- Don't name your own types after Godot classes (`Window` broke us once).

## Not built yet

Serialization (state and commands to and from JSON), per-player event filtering, the other
phases (exam, vote for Leader, role draw, turns), cards, wills, elimination effects, the UI.
