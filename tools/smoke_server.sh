#!/usr/bin/env bash
# Starts the real WebSocket server on a spare port, connects one client and checks it gets a room back. Needs GODOT set.
cd "$(dirname "$0")/.." || exit 1
GODOT="${GODOT:-godot}"
port=$((20000 + RANDOM % 20000))
"$GODOT" --headless --script server/ws_server.gd -- --port "$port" >/dev/null 2>&1 &
server=$!
trap 'kill $server 2>/dev/null' EXIT
sleep 3
out=$(timeout 30 "$GODOT" --headless --script tools/smoke_client.gd -- "$port" 2>&1)
echo "$out" | grep -q '"type":"room"' && echo "SERVER SMOKE TEST PASSED" || { echo "$out"; echo "SERVER SMOKE TEST FAILED"; exit 1; }
out=$(timeout 60 "$GODOT" --headless --script tools/smoke_phone.gd -- "$port" 2>&1)
echo "$out" | grep -q "PHONE SMOKE OK" && echo "$out" | grep "PHONE SMOKE OK" || { echo "$out"; echo "PHONE SMOKE TEST FAILED"; exit 1; }
