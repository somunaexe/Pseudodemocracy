#!/usr/bin/env bash
# Runs the tests/test_*.gd files headless, in parallel, and prints only what went wrong plus one summary line.
# Usage: tools/run_tests.sh                 every test
#        tools/run_tests.sh scandal peeks   only the files whose names contain one of the words (during development)
#        tools/run_tests.sh -v scandal      also print every PASS line
#        GODOT=/path/to/godot tools/run_tests.sh      (otherwise "godot" on PATH)
# A file fails if it prints FAIL, a script error or a parse error, exits non-zero, or runs longer than 180 seconds.
# Exit code 0 when everything passed. The slow whole-game simulation is test_game_simulation.gd: leave it for the end of a change.
cd "$(dirname "$0")/.." || exit 1
GODOT="${GODOT:-godot}"
verbose=0
words=()
for arg in "$@"; do
  if [ "$arg" = "-v" ]; then verbose=1; else words+=("$arg"); fi
done
files=()
for t in tests/test_*.gd; do
  if [ ${#words[@]} -eq 0 ]; then files+=("$t"); continue; fi
  for w in "${words[@]}"; do
    case "$t" in *"$w"*) files+=("$t"); break ;; esac
  done
done
if [ ${#files[@]} -eq 0 ]; then echo "no test file matches: ${words[*]}"; exit 1; fi
# The whole-game simulation is split into groups of games, run side by side (see GROUPS in tests/test_game_simulation.gd).
sim_groups="ordinary poor doctor lawyer unions coups corruption scandals misc"
jobs_list=()
for t in "${files[@]}"; do
  if [ "$t" = "tests/test_game_simulation.gd" ]; then
    for g in $sim_groups; do jobs_list+=("$t|$g"); done
  else
    jobs_list+=("$t|")
  fi
done
out_dir=$(mktemp -d)
trap 'rm -rf "$out_dir"' EXIT
export GODOT out_dir
run_one() {
  t="${1%%|*}"
  group="${1##*|}"
  name=$(basename "$t" .gd)${group:+.$group}
  if [ -n "$group" ]; then
    timeout 180 "$GODOT" --headless --script "$t" -- "$group" >"$out_dir/$name.out" 2>&1
  else
    timeout 180 "$GODOT" --headless --script "$t" >"$out_dir/$name.out" 2>&1
  fi
  echo $? >"$out_dir/$name.code"
}
export -f run_one
jobs=$(nproc 2>/dev/null || echo 2)
printf '%s\n' "${jobs_list[@]}" | xargs -P "$jobs" -I{} bash -c 'run_one "{}"'
bad=0
passed=0
for job in "${jobs_list[@]}"; do
  t="${job%%|*}"
  group="${job##*|}"
  name=$(basename "$t" .gd)${group:+.$group}
  out="$out_dir/$name.out"
  code=$(cat "$out_dir/$name.code" 2>/dev/null || echo 1)
  if [ "$code" -ne 0 ] || grep -qE '^FAIL|SCRIPT ERROR|Parse Error' "$out"; then
    bad=$((bad + 1))
    echo "=== FAILED: $t ${group}"
    grep -E '^FAIL|SCRIPT ERROR|Parse Error|^ERROR' "$out" | head -20
  else
    passed=$((passed + 1))
    [ "$verbose" -eq 1 ] && grep -E '^PASS' "$out"
  fi
done
if [ "$bad" -eq 0 ]; then echo "ALL TESTS PASSED ($passed runs)"; exit 0; fi
echo "SOME TESTS FAILED ($bad of ${#jobs_list[@]} runs)"
exit 1
