#!/usr/bin/env bash
# test-run-observer.sh — PostToolUse check on Bash.
#
# Red is cheap: ANY observed test run that confidently failed arms the gate,
# so the write-test -> run-it -> edit-source inner loop costs seconds.
# Green is expensive: observed successes NEVER write green — only the
# verified wrapper does. The asymmetry is safety: a false red slightly
# weakens the gate; a false green would break it.
#
# "Confident failure" (adversarial-review F9): a machine exit code that is
# nonzero AND a fail-pattern/count match. Exit 126/127 or command-not-found
# is "error" (broken command), never red. With no exit code available we
# require a fail_count_pattern match with count > 0.
set -u
. "$PLUGIN_ROOT/scripts/lib/json.sh"
. "$PLUGIN_ROOT/scripts/lib/common.sh"
. "$PLUGIN_ROOT/scripts/tdd/state.sh"

CHECK="test-run-observer"

CMD=$(json_get "$PAYLOAD_FILE" .tool_input.command "")
[ -n "$CMD" ] || exit 0

# The wrapper writes state itself.
case "$CMD" in *".claude/tdd/run-tests"*) exit 0 ;; esac

MATCH=$(json_get "$TEAM_CONFIG" .test.match "")
[ -n "$MATCH" ] || exit 0
printf '%s' "$CMD" | grep -qE "$MATCH" || exit 0

# Output text and exit code: field names vary across Claude Code versions, so
# probe several and fall back to pattern-only mode (documented limitation).
OUTPUT=$(json_get "$PAYLOAD_FILE" .tool_response.text "")
[ -n "$OUTPUT" ] || OUTPUT=$(json_get "$PAYLOAD_FILE" .tool_response.output "")
[ -n "$OUTPUT" ] || OUTPUT=$(json_get "$PAYLOAD_FILE" .tool_response.stdout "")
EXIT_CODE=$(json_get "$PAYLOAD_FILE" .tool_response.exit_code "")
[ -n "$EXIT_CODE" ] || EXIT_CODE=$(json_get "$PAYLOAD_FILE" .tool_response.exitCode "")
IS_ERROR=$(json_get "$PAYLOAD_FILE" .tool_response.is_error "")

FAIL_COUNT=-1
FCP=$(json_get "$TEAM_CONFIG" .test.fail_count_pattern "")
if [ -n "$FCP" ] && [ -n "$OUTPUT" ]; then
  FAIL_COUNT=$(printf '%s' "$OUTPUT" | grep -oE "$FCP" | head -1 | grep -oE '[0-9]+' | head -1)
  [ -n "$FAIL_COUNT" ] || FAIL_COUNT=-1
fi
PATTERN_HIT=0
while IFS= read -r pat; do
  [ -n "$pat" ] || continue
  printf '%s' "$OUTPUT" | grep -qE "$pat" && PATTERN_HIT=1
done < <(json_get_list "$TEAM_CONFIG" .test.fail_patterns)

STATUS=""
if printf '%s' "$OUTPUT" | head -10 | grep -qiE 'command not found|no such file or directory' ||
   [ "$EXIT_CODE" = "126" ] || [ "$EXIT_CODE" = "127" ]; then
  STATUS="error"
elif [ -n "$EXIT_CODE" ] && [ "$EXIT_CODE" != "0" ] && { [ "$PATTERN_HIT" -eq 1 ] || [ "${FAIL_COUNT:-0}" -gt 0 ]; }; then
  STATUS="red"
elif [ -z "$EXIT_CODE" ] && [ "$IS_ERROR" != "false" ] && [ "${FAIL_COUNT:-0}" -gt 0 ]; then
  STATUS="red"   # pattern-only mode: an explicit nonzero failure count is confident enough
fi
[ -n "$STATUS" ] || exit 0   # pass or ambiguous: leave state alone

# Preserve sticky fields, refresh fingerprint, write state atomically.
BASE_COUNT=$(state_get baseline.failing_count -1)
BASE_AT=$(state_get baseline.captured_at "")
EVER_GREEN=$(state_get ever_green false)
FP=$(fingerprint_tests)
NOW=$(now_iso)
mkdir -p "$(tdd_dir)/counters"

atomic_write "$(tdd_state_file)" <<EOF
{
  "schema_version": 1,
  "status": "$STATUS",
  "verified": $( [ -n "$EXIT_CODE" ] && echo true || echo false ),
  "scope": "observed",
  "command": "$(json_escape "$CMD")",
  "exit_code": ${EXIT_CODE:--1},
  "started_at": "$NOW",
  "finished_at": "$NOW",
  "failing_count": ${FAIL_COUNT:--1},
  "tests_fingerprint": "$FP",
  "baseline": { "failing_count": ${BASE_COUNT:--1}, "captured_at": "$BASE_AT" },
  "ever_green": $EVER_GREEN,
  "bootstrap": false
}
EOF

append_line "$(tdd_dir)/runs.log" \
  "{\"ts\":\"$NOW\",\"kind\":\"observed\",\"scope\":\"observed\",\"exit\":${EXIT_CODE:--1},\"failing\":${FAIL_COUNT:--1},\"status\":\"$STATUS\",\"command\":\"$(json_escape "$CMD")\"}"

# Observed red is a verified-enough arming event: reset budgets like the wrapper.
if [ "$STATUS" = "red" ]; then
  : >"$(tdd_dir)/counters/source_edits.log" 2>/dev/null || true
  : >"$(tdd_dir)/counters/test_edits.log" 2>/dev/null || true
fi

audit_log "$EVENT" "$CHECK" "state-$STATUS" "" "observed test run: exit=${EXIT_CODE:-?} failing=${FAIL_COUNT}"
exit 0
