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

## The law (scripts/law.gd)

Leaders can rewrite the Constitution, so a number it governs (tax, levy, the Agbero steal) is never
fixed in the data: it is whatever the current wording says. `Law.get_int(state, "rule")` reads it
from `state.articles`. A rule is a *binding*: one highlighted word of one article and how to read
it (data/source/articles.js). A Leader may only write a bound word the game can read; unreadable
words are refused for free. Unbound highlighted words stay free text for the table to enforce.
`test_law_guard.gd` fails if any script reads a governed number from game_data directly.

## Rules of the codebase

- **Never read a Constitution-governed number from game_data. Use `Law`.**

- Money only moves through `Debt.charge` and `Debt.receive`.
- Anything a player sends is untrusted: check its type before using it.
- Validate and store the same normalised string.
- Don't name your own types after Godot classes (`Window` broke us once).

## Serialization (scripts/serializer.gd)

JSON gets three things wrong, and the serializer fixes each:

| Problem | Fix |
|---|---|
| Dictionary keys turn into text (`{1: x}` comes back as `{"1": x}`) | A dictionary with any non-text key is written as `{"$pairs": [[key, value], ...]}`, so keys keep their type. |
| Every number comes back as a float | Whole numbers are turned back into ints on loading. (The state holds no real fractions.) |
| Clients can send anything | `parse_command` checks size (64 KB), depth (32), and shape, and returns the command with ints restored. |

- `state_to_json` / `state_from_json` save and load the **whole** state. It lists the fields by
  asking Godot, so a field added to `GameState` is saved automatically. **It includes secrets
  (sealed votes): server saves only, never send it to a client.**
- A save carries `SCHEMA_VERSION`. Bump it whenever a field or an enum value changes meaning;
  an old save is then refused instead of silently misread.
- Functions that can fail take an `errors` array and never crash on bad input.
- The test builds a state with every field filled in, round-trips it, and compares **types as
  well as values**; it also fails if a new field is not covered by that state.

## Views: what each player may see (scripts/views.gd)

The server holds the whole truth; a phone only gets a **view**.

- `Views.visible_events(events, player_id)` keeps events for everyone (empty `audience`) and
  those addressed to that player. `Views.deliver(events, player_ids)` does it for the whole table.
- `Views.state_view(state, player_id)` is the game as that player may see it. It is an
  **allow-list**: only fields listed in `PUBLIC_FIELDS` are copied. `amend` and `event_log` are
  cleaned up per player: others' votes are removed (you get `voted`, the list of who has voted,
  and `my_vote` for yourself), and the history is filtered by audience.
- A field in none of the three lists (`PUBLIC_FIELDS`, `REDACTED_FIELDS`, `SERVER_ONLY_FIELDS`)
  stops `state_view` and fails the test, so a new secret can never leak by being forgotten.
- A view is a deep copy and survives the serializer, so it can be sent as it is.

## Elimination (scripts/elimination.gd)

`Elimination.end_turn` counts a debt term and eliminates on the third; `Elimination.eliminate`
settles the estate (to the heir, or the treasury), reassigns debts owed to the dead player,
ends union memberships, and re-checks any vote waiting on them. It returns events like
everything else. `Debt.end_of_turn` only reports that the limit was reached.
Schema version 2 added `GameState.wills` (server-only; see Views).

## Not built yet

The other
phases (exam, vote for Leader, role draw, turns), cards, wills, elimination effects, the UI.
