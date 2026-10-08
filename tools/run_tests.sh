#!/usr/bin/env bash
# Runs every tests/test_*.gd headless. Fails if any test prints FAIL or a script error.
# Usage: tools/run_tests.sh          (uses "godot" on PATH)
# A test file that runs longer than 60 seconds is killed and counts as a failure.
#        GODOT=/path/to/godot tools/run_tests.sh
cd "$(dirname "$0")/.." || exit 1
GODOT="${GODOT:-godot}"
bad=0
for t in tests/test_*.gd; do
  echo "=== $t"
  out=$(timeout 60 "$GODOT" --headless --script "$t" 2>&1)
  code=$?
  echo "$out" | grep -v '^Godot Engine'
  if [ $code -ne 0 ] || echo "$out" | grep -qE '^FAIL|SCRIPT ERROR|Parse Error'; then
    echo ">>> FAILED: $t"
    bad=1
  fi
done
[ $bad -eq 0 ] && echo "ALL TESTS PASSED" || echo "SOME TESTS FAILED"
exit $bad
