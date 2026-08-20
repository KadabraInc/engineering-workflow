#!/usr/bin/env bats
# The verified wrapper: the only writer of green; error semantics; baseline
# capture; counter/refactor resets; run log.

load helpers

setup() { make_project; }

wrap() { ( cd "$PROJ" && run bash "$PLUGIN_ROOT/scripts/tdd/run-tests.sh" "$@" ); }

get() { bash -c '. "'"$PLUGIN_ROOT"'/scripts/lib/json.sh"; json_get "'"$PROJ"'/.claude/tdd/state.json" '"$1"' missing'; }

@test "full green run writes verified green and sets ever_green" {
  echo green >"$PROJ/runner-mode"
  ( cd "$PROJ" && bash "$PLUGIN_ROOT/scripts/tdd/run-tests.sh" )
  [ "$(get .status)" = "green" ]
  [ "$(get .verified)" = "true" ]
  [ "$(get .ever_green)" = "true" ]
  [ "$(get .scope)" = "full" ]
}

@test "failing run with pattern writes red with failing_count" {
  echo "red:4" >"$PROJ/runner-mode"
  ( cd "$PROJ" && bash "$PLUGIN_ROOT/scripts/tdd/run-tests.sh" ) || true
  [ "$(get .status)" = "red" ]
  [ "$(get .failing_count)" = "4" ]
}

@test "exit 127 writes error, not red" {
  echo error >"$PROJ/runner-mode"
  ( cd "$PROJ" && bash "$PLUGIN_ROOT/scripts/tdd/run-tests.sh" ) || true
  [ "$(get .status)" = "error" ]
}

@test "verified run truncates counters and clears refactor declaration" {
  echo "t x src/index.js" >>"$PROJ/.claude/tdd/counters/source_edits.log"
  echo "why" >"$PROJ/.claude/tdd/refactor"
  echo green >"$PROJ/runner-mode"
  ( cd "$PROJ" && bash "$PLUGIN_ROOT/scripts/tdd/run-tests.sh" )
  [ "$(wc -l <"$PROJ/.claude/tdd/counters/source_edits.log" 2>/dev/null | tr -d '[:space:]')" -eq 0 ]
  [ ! -f "$PROJ/.claude/tdd/refactor" ]
}

@test "--baseline records the failure count as brownfield baseline" {
  echo "red:7" >"$PROJ/runner-mode"
  ( cd "$PROJ" && bash "$PLUGIN_ROOT/scripts/tdd/run-tests.sh" --baseline ) || true
  [ "$(get .baseline.failing_count)" = "7" ]
}

@test "baseline survives later runs; green baseline is 0" {
  echo "red:7" >"$PROJ/runner-mode"
  ( cd "$PROJ" && bash "$PLUGIN_ROOT/scripts/tdd/run-tests.sh" --baseline ) || true
  echo "red:9" >"$PROJ/runner-mode"
  ( cd "$PROJ" && bash "$PLUGIN_ROOT/scripts/tdd/run-tests.sh" ) || true
  [ "$(get .baseline.failing_count)" = "7" ]
  [ "$(get .failing_count)" = "9" ]
}

@test "targeted run records scope targeted" {
  echo "red:1" >"$PROJ/runner-mode"
  ( cd "$PROJ" && bash "$PLUGIN_ROOT/scripts/tdd/run-tests.sh" --targeted example ) || true
  [ "$(get .scope)" = "targeted" ]
}

@test "runs are appended to runs.log" {
  echo green >"$PROJ/runner-mode"
  ( cd "$PROJ" && bash "$PLUGIN_ROOT/scripts/tdd/run-tests.sh" )
  grep -q '"kind":"wrapper"' "$PROJ/.claude/tdd/runs.log"
}

@test "wrapper and state.sh produce identical fingerprints" {
  echo green >"$PROJ/runner-mode"
  ( cd "$PROJ" && bash "$PLUGIN_ROOT/scripts/tdd/run-tests.sh" )
  [ "$(get .tests_fingerprint)" = "$(current_fingerprint)" ]
}

@test "missing test command exits with guidance" {
  bash -c '. "'"$PLUGIN_ROOT"'/scripts/lib/json.sh"; :'
  sed -i 's/"command": "bash fake-runner.sh"/"command": ""/' "$PROJ/.claude/team.json"
  ( cd "$PROJ" && run bash "$PLUGIN_ROOT/scripts/tdd/run-tests.sh" )
  ( cd "$PROJ" && ! bash "$PLUGIN_ROOT/scripts/tdd/run-tests.sh" 2>/dev/null )
}
