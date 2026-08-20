# helpers.bash — shared fixtures for the bats suite.
# Each test gets a throwaway project under $BATS_TEST_TMPDIR with a real git
# repo, a team.json, and a fake test runner whose behavior the test controls.

PLUGIN_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd -P)"
export PLUGIN_ROOT CLAUDE_PLUGIN_ROOT="$PLUGIN_ROOT"

make_project() {
  PROJ="$BATS_TEST_TMPDIR/proj"
  mkdir -p "$PROJ/src" "$PROJ/tests" "$PROJ/docs" "$PROJ/.claude/tdd/counters" "$PROJ/.claude/team"
  git -C "$PROJ" init -q 2>/dev/null || true
  cat >"$PROJ/.claude/team.json" <<'EOF'
{
  "schema_version": 1,
  "stack": "generic",
  "test": {
    "command": "bash fake-runner.sh",
    "targeted_command": "bash fake-runner.sh {pattern}",
    "match": "fake-runner|npm test|vitest|jest|pytest|phpunit|artisan test",
    "fail_patterns": ["[1-9][0-9]* (failed|failures)", "FAILURES!"],
    "fail_count_pattern": "[0-9]+ failed"
  },
  "globs": {
    "source": ["src/**", "lib/**"],
    "test": ["tests/**", "**/*.test.*", "**/*.spec.*"],
    "exempt": ["docs/**", "**/*.md", ".claude/**", ".github/**", "**/*.yml"],
    "protected": ["vitest.config.*", "tsconfig.json"]
  },
  "tdd": {
    "enabled": true,
    "default_class": "source",
    "staleness_minutes": 240,
    "green_edit_budget": 3,
    "refactor_budget": 10
  },
  "hooks": { "enabled": true, "ambient_profile": "standard", "pipeline_profile": "strict" },
  "delivery": { "min_source_files": 3, "retry_failed": 0 },
  "knowledge": { "dir": ".claude/knowledge" },
  "search_exclude": [".claude/team/artifacts/**"],
  "branch_prefix": "team/"
}
EOF
  # fake-runner.sh: behavior driven by $PROJ/runner-mode (green|red:N|error)
  cat >"$PROJ/fake-runner.sh" <<'EOF'
#!/usr/bin/env bash
mode=$(cat runner-mode 2>/dev/null || echo green)
case "$mode" in
  green) echo "all tests passed, 0 failed"; exit 0 ;;
  red:*) n=${mode#red:}; echo "Tests: $n failed, 2 passed"; exit 1 ;;
  error) echo "sh: some-runner: command not found"; exit 127 ;;
esac
EOF
  echo "test('x', () => {})" >"$PROJ/tests/example.test.js"
  echo "module.exports = 1" >"$PROJ/src/index.js"
  export TEAM_ROOT="$PROJ" TEAM_CONFIG="$PROJ/.claude/team.json"
}

# write_state <status> [scope] [failing] [baseline] [extra-kv...]
# Writes a syntactically valid state.json with the CURRENT fingerprint so the
# gate's freshness check passes unless a test perturbs the test files after.
write_state() {
  local status="$1" scope="${2:-full}" failing="${3:--1}" baseline="${4:--1}"
  local fp
  fp=$(current_fingerprint)
  cat >"$PROJ/.claude/tdd/state.json" <<EOF
{
  "schema_version": 1,
  "status": "$status",
  "verified": true,
  "scope": "$scope",
  "command": "bash fake-runner.sh",
  "exit_code": 1,
  "started_at": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
  "finished_at": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
  "failing_count": $failing,
  "tests_fingerprint": "$fp",
  "baseline": { "failing_count": $baseline, "captured_at": "" },
  "ever_green": false,
  "bootstrap": false
}
EOF
}

current_fingerprint() {
  ( cd "$PROJ" && TEAM_ROOT="$PROJ" TEAM_CONFIG="$PROJ/.claude/team.json" \
      bash "$PLUGIN_ROOT/scripts/tdd/state.sh" fingerprint )
}

# payload_edit <abs-file-path>  — PreToolUse Write payload JSON on stdout
payload_edit() {
  printf '{"session_id":"bats","cwd":"%s","tool_name":"Write","tool_input":{"file_path":"%s","content":"x"}}' "$PROJ" "$1"
}

# payload_bash <command> <output> <exit_code>
payload_bash() {
  local cmd out code
  cmd=$(printf '%s' "$1" | sed 's/\\/\\\\/g; s/"/\\"/g')
  out=$(printf '%s' "$2" | sed 's/\\/\\\\/g; s/"/\\"/g')
  code="$3"
  printf '{"session_id":"bats","cwd":"%s","tool_name":"Bash","tool_input":{"command":"%s"},"tool_response":{"text":"%s","exit_code":%s}}' "$PROJ" "$cmd" "$out" "$code"
}

# run_check <check-script> <payload> [MODE]
# Invokes one check the way dispatch.sh would (env contract + stdin payload).
run_check() {
  local script="$1" payload="$2" mode="${3:-block}"
  local pf="$BATS_TEST_TMPDIR/payload.json"
  printf '%s' "$payload" >"$pf"
  local target
  target=$(TEAM_CONFIG="$TEAM_CONFIG" bash -c '
    . "'"$PLUGIN_ROOT"'/scripts/lib/json.sh"
    json_get "'"$pf"'" .tool_input.file_path ""')
  EVENT="pre-edit" MODE="$mode" PROFILE="strict" SESSION_ID="bats" \
    TEAM_ROOT="$TEAM_ROOT" TEAM_CONFIG="$TEAM_CONFIG" PLUGIN_ROOT="$PLUGIN_ROOT" \
    PAYLOAD_FILE="$pf" TOOL_NAME="Write" TARGET_FILE="$target" CWD="$PROJ" \
    run bash "$PLUGIN_ROOT/scripts/hooks/$script" <"$pf"
}

# run_dispatch <event> <payload> [profile-env]
run_dispatch() {
  local event="$1" payload="$2"
  run bash -c "printf '%s' '$payload' | bash '$PLUGIN_ROOT/scripts/hooks/dispatch.sh' '$event'"
}

assert_deny()  { [ "$status" -eq 0 ] && [[ "$output" == *'"permissionDecision":"deny"'* ]]; }
assert_allow() { [ "$status" -eq 0 ] && [[ "$output" != *'"permissionDecision":"deny"'* ]]; }
assert_warn()  { [[ "$output" == *'WARN:'* ]]; }
