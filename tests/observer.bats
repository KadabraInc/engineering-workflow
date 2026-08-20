#!/usr/bin/env bats
# Observer semantics: red from confident failure only; success never sets
# green; broken commands become "error"; non-test commands are ignored.

load helpers

setup() { make_project; }

observer() { # observer <command> <output> <exit>
  local pf="$BATS_TEST_TMPDIR/payload.json"
  payload_bash "$1" "$2" "$3" >"$pf"
  EVENT="post-bash" MODE="on" PROFILE="strict" SESSION_ID="bats" \
    TEAM_ROOT="$PROJ" TEAM_CONFIG="$TEAM_CONFIG" PLUGIN_ROOT="$PLUGIN_ROOT" \
    PAYLOAD_FILE="$pf" TOOL_NAME="Bash" TARGET_FILE="" CWD="$PROJ" \
    run bash "$PLUGIN_ROOT/scripts/hooks/checks/test-run-observer.sh" <"$pf"
}

state_status() {
  TEAM_ROOT="$PROJ" bash -c '. "'"$PLUGIN_ROOT"'/scripts/lib/json.sh"; json_get "'"$PROJ"'/.claude/tdd/state.json" .status missing'
}

@test "failing test run sets red" {
  observer "npm test" "Tests: 3 failed, 1 passed" 1
  [ "$status" -eq 0 ]
  [ "$(state_status)" = "red" ]
}

@test "passing test run never sets green (wrapper-only)" {
  write_state red observed 1
  observer "npm test" "all passed, 0 failed" 0
  [ "$(state_status)" = "red" ]
}

@test "command-not-found becomes error, not red" {
  observer "npm test" "sh: vitest: command not found" 127
  [ "$(state_status)" = "error" ]
}

@test "nonzero exit WITHOUT failure pattern does not set red" {
  observer "npm test" "some unrelated crash output" 2
  [ ! -f "$PROJ/.claude/tdd/state.json" ] || [ "$(state_status)" != "red" ]
}

@test "non-test command is ignored entirely" {
  observer "ls -la" "Tests: 3 failed" 1
  [ ! -f "$PROJ/.claude/tdd/state.json" ]
}

@test "wrapper invocations are skipped (wrapper writes its own state)" {
  observer "bash .claude/tdd/run-tests" "Tests: 3 failed" 1
  [ ! -f "$PROJ/.claude/tdd/state.json" ]
}

@test "observed red resets the edit-budget counters" {
  echo "t old src/index.js" >>"$PROJ/.claude/tdd/counters/source_edits.log"
  observer "npm test" "Tests: 1 failed" 1
  [ "$(wc -l <"$PROJ/.claude/tdd/counters/source_edits.log" 2>/dev/null | tr -d '[:space:]')" -eq 0 ]
}

@test "webpack-style FAIL noise without exit code does not set red" {
  # pattern-only mode requires an explicit failure COUNT; bare 'FAIL' noise is
  # not confident. Build payload without exit_code field.
  local pf="$BATS_TEST_TMPDIR/payload.json"
  printf '{"session_id":"bats","cwd":"%s","tool_name":"Bash","tool_input":{"command":"npm test"},"tool_response":{"text":"FAIL in module x (webpack)"}}' "$PROJ" >"$pf"
  EVENT="post-bash" MODE="on" TEAM_ROOT="$PROJ" TEAM_CONFIG="$TEAM_CONFIG" \
    PLUGIN_ROOT="$PLUGIN_ROOT" PAYLOAD_FILE="$pf" TOOL_NAME="Bash" TARGET_FILE="" CWD="$PROJ" \
    run bash "$PLUGIN_ROOT/scripts/hooks/checks/test-run-observer.sh" <"$pf"
  [ ! -f "$PROJ/.claude/tdd/state.json" ]
}
