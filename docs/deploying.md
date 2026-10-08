# Running the server

## What it needs
One Godot 4.7 binary, this project folder, a place to keep saves, and a TLS proxy so players connect over `wss://`.
A small VPS (1 vCPU, 512 MB) is plenty: a game is a few hundred kilobytes and a table moves a few messages a second.

## Run it by hand
    godot --headless --script server/ws_server.gd -- --port 9080 --data /var/lib/pseudodemocracy

`PORT`, `DATA_DIR` and `--max` (most connections, default 500) are the only settings. On start it says how many saved rooms it restored.

## On a server
- **Docker:** `docker compose -f deploy/docker-compose.yml up -d` runs the game and Caddy (automatic HTTPS). Edit the domain in `deploy/Caddyfile` first. The `Dockerfile` has not been built yet; check the Godot download name when you first do.
- **No Docker:** `deploy/pseudodemocracy.service` is a systemd unit (restarts on a crash, saves in `/var/lib/pseudodemocracy`). Put Caddy or nginx in front.

## What survives what
- **A crash or restart:** every accepted move is written to disk before anyone is told, so at most the move in progress is lost. Players reconnect with the token the game stored (`resume`) and find their seat. The game's clock carries on from where it was, so a night of downtime does not skip everyone's turn.
- **Cleanup:** an unstarted room nobody is in goes after 30 minutes, a finished game after an hour, a running game with nobody connected after 3 hours (it normally ends sooner: absent players are eliminated after two missed turns).
- **Updating the game:** a save from an older engine version (`SCHEMA_VERSION` in `scripts/serializer.gd`) is skipped with a message, not guessed at. Finish or abandon running games before a release that changes the state.

## Identity (there are no accounts, on purpose)
A player is a name plus a secret token, issued when they join a room and stored on their device. That is all the game needs: no passwords or emails to leak, and no way to impersonate another seat without their token. Lose the token (clear the app's storage) and the seat is lost with it. If you later want profiles that persist across games (stats, friends), add them as a separate service; the game server only needs the token.

## Not done yet
- The Docker build and the compose stack are untested. The first real deployment is the test.
- No rate limit per IP (the proxy sees the address, the game server does not). Add one in Caddy or nginx if the server is public.
- Backups: copy the data directory.
