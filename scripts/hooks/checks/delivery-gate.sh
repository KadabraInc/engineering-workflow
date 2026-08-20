#!/usr/bin/env bash
# delivery-gate.sh — Stop check. The deterministic backstop.
#
# Counts what actually changed via git (diff vs the session-start SHA plus
# untracked files, minus files already dirty at session start) — so writes
# that dodged the per-tool guards (python -c, heredocs, mv) still count
# (adversarial-review F4). Blocks ONLY in terminal pipeline phases (qa,
# review, pr); everywhere else — including every mid-conversation Stop, which
# fires at each turn end, not at task end (F1) — it warns at most. Machine
# facts block; regex heuristics only ever warn.
set -u
. "$PLUGIN_ROOT/scripts/lib/json.sh"
. "$PLUGIN_ROOT/scripts/lib/common.sh"
. "$PLUGIN_ROOT/scripts/tdd/state.sh"

CHECK="delivery-gate"

# Mandatory anti-loop guard.
[ "$(json_get "$PAYLOAD_FILE" .stop_hook_active "false")" = "true" ] && exit 0

PHASE=$(cat "$TEAM_ROOT/.claude/tdd/phase" 2>/dev/null || echo "")
case "$PHASE" in
  qa|review|pr) : ;;                # terminal-eligible: MODE stands
  *) MODE="warn" ;;                 # everything else: never block a turn end
esac

verdict() { # verdict <reason>
  audit_log "stop" "$CHECK" "$([ "$MODE" = block ] && echo block || echo warn)" "" "$1"
  if [ "$MODE" = "block" ]; then emit_block "[delivery-gate] $1"; else emit_warn "[delivery-gate] $1"; fi
}

# --- git-truth accounting -------------------------------------------------------
SESSION_FILE="$TEAM_ROOT/.claude/team/session-${SESSION_ID:-unknown}.json"
START_SHA=$(json_get "$SESSION_FILE" .start_sha "")
PRE_DIRTY=$(json_get_list "$SESSION_FILE" .dirty)

changed=""
if [ -n "$START_SHA" ] && git -C "$TEAM_ROOT" rev-parse "$START_SHA" >/dev/null 2>&1; then
  changed=$(git -C "$TEAM_ROOT" diff --name-only "$START_SHA" 2>/dev/null)
fi
untracked=$(git -C "$TEAM_ROOT" status --porcelain 2>/dev/null | awk '$1 == "??" {print $2}')
all_changed=$(printf '%s\n%s\n' "$changed" "$untracked" | sort -u | grep -v '^$' || true)

SRC_CHANGED=""; TEST_CHANGED=0
while IFS= read -r f; do
  [ -n "$f" ] || continue
  printf '%s\n' "$PRE_DIRTY" | grep -qxF "$f" && continue    # predates this session
  case "$(classify_path "$f")" in
    source) SRC_CHANGED="$SRC_CHANGED$f"$'\n' ;;
    test)   TEST_CHANGED=$((TEST_CHANGED + 1)) ;;
  esac
done <<<"$all_changed"
SRC_COUNT=$(printf '%s' "$SRC_CHANGED" | grep -c . || true)

THRESHOLD=$(json_get "$TEAM_CONFIG" .delivery.min_source_files 3)
[ "$SRC_COUNT" -lt "$THRESHOLD" ] && exit 0    # trivial sessions pass untouched

# --- machine facts ----------------------------------------------------------------
STATUS=$(state_get status unknown); VERIFIED=$(state_get verified false)
SCOPE=$(state_get scope none); FINISHED=$(state_get finished_at "")
FAILING=$(state_get failing_count -1); BASELINE=$(state_get baseline.failing_count -1)
EVER_GREEN=$(state_get ever_green false)

suite_ok=0
if [ "$STATUS" = "green" ] && [ "$VERIFIED" = "true" ] && [ "$SCOPE" = "full" ]; then
  suite_ok=1
elif [ "$EVER_GREEN" != "true" ] && [ "${BASELINE:--1}" -ge 0 ] && [ "$STATUS" = "red" ] &&
     [ "$SCOPE" = "full" ] && [ "${FAILING:--1}" -ge 0 ] && [ "$FAILING" -le "$BASELINE" ]; then
  suite_ok=1   # brownfield: full run shows no NEW failures beyond baseline
fi

if [ "$suite_ok" -eq 0 ]; then
  verdict "$SRC_COUNT source files changed this session but no verified full-suite pass (state=$STATUS scope=$SCOPE). Run: bash .claude/tdd/run-tests"
  exit 0
fi

# Freshness: the verified run must postdate the newest changed source file.
if [ -n "$FINISHED" ]; then
  RUN_EPOCH=$(date -u -d "$FINISHED" +%s 2>/dev/null || date -u -j -f %Y-%m-%dT%H:%M:%SZ "$FINISHED" +%s 2>/dev/null || echo 0)
  while IFS= read -r f; do
    [ -n "$f" ] && [ -f "$TEAM_ROOT/$f" ] || continue
    M=$(stat -c %Y "$TEAM_ROOT/$f" 2>/dev/null || stat -f %m "$TEAM_ROOT/$f" 2>/dev/null || echo 0)
    if [ "$M" -gt "$RUN_EPOCH" ]; then
      verdict "Source changed after the last verified run ($f) — re-run: bash .claude/tdd/run-tests"
      exit 0
    fi
  done <<<"$SRC_CHANGED"
fi

# Diff must touch tests (or carry a declared refactor — audited & PR-visible).
if [ "$TEST_CHANGED" -eq 0 ] && [ ! -f "$TEAM_ROOT/.claude/tdd/refactor" ]; then
  verdict "$SRC_COUNT source files changed with zero test changes. Add/extend a test, or declare a behavior-free refactor: echo '<why>' > .claude/tdd/refactor (surfaced verbatim in the PR)"
  exit 0
fi

# Source must not import test paths (deterministic F17 check).
while IFS= read -r f; do
  [ -n "$f" ] && [ -f "$TEAM_ROOT/$f" ] || continue
  if grep -nE '(require|import|from|include|use)[^;]*["'"'"'(/ ]tests?/' "$TEAM_ROOT/$f" >/dev/null 2>&1; then
    verdict "Source file $f imports from a test path — production code must not depend on test files"
    exit 0
  fi
done <<<"$SRC_CHANGED"

# Pipeline integrity: approval hashes and the retro decision.
ACTIVE="$TEAM_ROOT/.claude/team/active-task"
if [ -f "$ACTIVE" ]; then
  SLUG=$(head -1 "$ACTIVE" | tr -cd 'a-z0-9-')
  TDIR="$TEAM_ROOT/.claude/team/artifacts/$SLUG"
  TSTATE="$TDIR/state.json"
  hash_approved() { awk 'BEGIN{p=1} /^## Amendments/{p=0} p' "$1" 2>/dev/null | { if command -v sha256sum >/dev/null 2>&1; then sha256sum; else shasum -a 256; fi; } | cut -d' ' -f1; }
  for doc in spec plan; do
    STORED=$(json_get "$TSTATE" ".approvals.${doc}_sha256" "")
    if [ -n "$STORED" ] && [ -f "$TDIR/$doc.md" ]; then
      NOW_HASH=$(hash_approved "$TDIR/$doc.md")
      if [ "$NOW_HASH" != "$STORED" ]; then
        verdict "$doc.md changed after user approval (outside ## Amendments) — restore it or re-run the approval gate; silent post-approval edits are not allowed"
        exit 0
      fi
    fi
  done
  if [ "$PHASE" = "pr" ]; then
    LESSON=$(json_get "$TSTATE" .lesson.decision "")
    if [ -z "$LESSON" ]; then
      verdict "PR phase requires a retro decision — record lesson or no-lesson in $TDIR/state.json (retro skill step)"
      exit 0
    fi
  fi
fi

# --- warn-only heuristics ------------------------------------------------------------
if [ -n "$START_SHA" ]; then
  TODOS=$(git -C "$TEAM_ROOT" diff "$START_SHA" 2>/dev/null | grep -cE '^\+.*(TODO|FIXME)' || true)
  [ "${TODOS:-0}" -gt 0 ] && emit_warn "[delivery-gate] $TODOS added TODO/FIXME lines in this session's diff"
fi
exit 0
