#!/usr/bin/env bash
# tdd-gate.sh — PreToolUse check on Write|Edit|MultiEdit|NotebookEdit.
#
# Deterministically enforces red-green-refactor ORDERING: a verified failing
# test run must precede source edits. It never runs tests itself (per-edit
# cost is a JSON read + one stat sweep) — "red" is earned by real runs via
# the observer or the wrapper, "green" only by the wrapper.
#
# What this gate proves and doesn't prove is documented in docs/tdd-gate.md;
# every deny reason emitted here has a "correct next action" entry in
# skills/tdd/references/gate-errors.md. Keep the two in sync.
set -u
. "$PLUGIN_ROOT/scripts/lib/json.sh"
. "$PLUGIN_ROOT/scripts/lib/common.sh"
. "$PLUGIN_ROOT/scripts/tdd/state.sh"

CHECK="tdd-gate"

# --- explicit bypasses (always audited, never silent) --------------------------
if [ "${TEAM_TDD_GATE:-on}" = "off" ]; then
  audit_log "$EVENT" "$CHECK" "bypass-env" "${TARGET_FILE:-}" "TEAM_TDD_GATE=off"
  exit 0
fi
if [ "$(json_get "$TEAM_CONFIG" .tdd.enabled true)" = "false" ]; then
  exit 0   # team.json is protected: only a human can have set this
fi

[ -n "${TARGET_FILE:-}" ] || exit 0
REL=$(rel_path "$TEAM_ROOT" "$TARGET_FILE")
[ -n "$REL" ] || exit 0   # outside the project

CLASS=$(classify_path "$REL")
case "$CLASS" in
  protected) exit 0 ;;   # config-protection owns this class
  exempt)    exit 0 ;;
  test)
    # Writing tests is the red step and always allowed — except during the
    # pipeline's implement phase, where test changes must route through the
    # test-engineer (deterministic phase fact, not agent identity, since
    # hooks cannot see which subagent is calling).
    if [ "$(cat "$TEAM_ROOT/.claude/tdd/phase" 2>/dev/null)" = "implement" ]; then
      decide "$CHECK" "$REL" "Implement phase: test files are frozen. If the test is wrong, return STATUS: BLOCKED so the cto adjudicates and the test-engineer revises it (logged as RED-REVISED in evidence.md)"
    fi
    exit 0
    ;;
esac
# CLASS is source (or default_class resolved to source) from here on.

# --- one-shot human override file ----------------------------------------------
ALLOW="$TEAM_ROOT/.claude/tdd/allow"
if [ -f "$ALLOW" ]; then
  EXPIRES=$(json_get "$ALLOW" .expires_at "")
  REASON=$(json_get "$ALLOW" .reason "unspecified")
  if [ -n "$EXPIRES" ] && [ "$(now_iso)" \< "$EXPIRES" ]; then
    if json_get_list "$ALLOW" .paths | glob_match_any_stdin "$REL"; then
      audit_log "$EVENT" "$CHECK" "override" "$REL" "allow file: $REASON"
      exit 0
    fi
  else
    rm -f "$ALLOW" 2>/dev/null || true   # expired: consume it
  fi
fi

# --- state ------------------------------------------------------------------------
STATUS=$(state_get status unknown)
BOOTSTRAP=$(state_get bootstrap true)
SCOPE=$(state_get scope none)
FINISHED=$(state_get finished_at "")
FAILING=$(state_get failing_count -1)
BASELINE=$(state_get baseline.failing_count -1)
STORED_FP=$(state_get tests_fingerprint "")

if [ ! -f "$(tdd_state_file)" ]; then
  decide "$CHECK" "$REL" "No TDD state found — run /team:setup (or bash .claude/tdd/run-tests) to initialize the gate"
  exit 0
fi

if [ "$BOOTSTRAP" = "true" ]; then
  emit_warn "[$CHECK] bootstrap mode: gate arms after the first 'bash .claude/tdd/run-tests' run"
  audit_log "$EVENT" "$CHECK" "bootstrap-allow" "$REL" "bootstrap mode"
  exit 0
fi

# Fingerprint freshness: tests changed since the recorded run -> state unusable.
if [ -n "$STORED_FP" ]; then
  CURRENT_FP=$(fingerprint_tests)
  if [ "$CURRENT_FP" != "$STORED_FP" ]; then
    decide "$CHECK" "$REL" "Test files changed since the last verified run — re-arm: bash .claude/tdd/run-tests --targeted <pattern> (seconds), or the full wrapper"
    exit 0
  fi
fi

age_minutes() {
  local then_s now_s
  then_s=$(date -u -d "$FINISHED" +%s 2>/dev/null || date -u -j -f %Y-%m-%dT%H:%M:%SZ "$FINISHED" +%s 2>/dev/null || echo 0)
  now_s=$(now_epoch)
  [ "$then_s" -gt 0 ] && echo $(( (now_s - then_s) / 60 )) || echo 99999
}

case "$STATUS" in
  error)
    decide "$CHECK" "$REL" "Test command is broken (last run errored, see .claude/tdd/last-run.log) — fix test.command in .claude/team.json or re-run /team:setup before editing source"
    ;;
  unknown)
    decide "$CHECK" "$REL" "No verified test state. Write or pick a failing test and run it: bash .claude/tdd/run-tests --targeted <pattern> (or the full wrapper). Red opens this gate"
    ;;
  red)
    # Brownfield: ambient pre-existing failures do NOT arm the gate — only a
    # failure beyond the baseline (or a targeted/observed red) proves there is
    # a failing test for the work at hand.
    if [ "$SCOPE" = "full" ] && [ "${BASELINE:--1}" -ge 0 ] && [ "${FAILING:--1}" -ge 0 ] && [ "$FAILING" -le "$BASELINE" ]; then
      decide "$CHECK" "$REL" "Suite is red at its pre-existing baseline ($BASELINE known failures) — that does not arm the gate. Write a failing test for THIS change and run: bash .claude/tdd/run-tests --targeted <pattern>"
      exit 0
    fi
    STALE_MIN=$(json_get "$TEAM_CONFIG" .tdd.staleness_minutes 240)
    if [ "$(age_minutes)" -gt "$STALE_MIN" ]; then
      decide "$CHECK" "$REL" "Red state is older than ${STALE_MIN}m — re-run the failing test to re-arm: bash .claude/tdd/run-tests --targeted <pattern>"
      exit 0
    fi
    audit_log "$EVENT" "$CHECK" "allow" "$REL" "red"
    ;;
  green)
    BUDGET=$(json_get "$TEAM_CONFIG" .tdd.green_edit_budget 5)
    if [ -f "$TEAM_ROOT/.claude/tdd/refactor" ]; then
      BUDGET=$(json_get "$TEAM_CONFIG" .tdd.refactor_budget 25)
    fi
    EDITS=$(source_edits_since_run)
    if [ "$EDITS" -ge "$BUDGET" ]; then
      decide "$CHECK" "$REL" "Green refactor budget exhausted ($EDITS source edits since the verified run) — re-verify: bash .claude/tdd/run-tests, or for a deliberate behavior-free refactor declare it (audited, PR-visible): echo '<why>' > .claude/tdd/refactor"
      exit 0
    fi
    audit_log "$EVENT" "$CHECK" "allow" "$REL" "green (edits $EDITS/$BUDGET)"
    ;;
  *)
    decide "$CHECK" "$REL" "Unrecognized TDD state '$STATUS' — treating as unknown; run bash .claude/tdd/run-tests"
    ;;
esac
exit 0
