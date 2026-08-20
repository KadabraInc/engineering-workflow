#!/usr/bin/env bash
# verify-evidence.sh <task-artifacts-dir>
#
# Machine cross-check that evidence.md's RED/GREEN claims correspond to runs
# that actually happened (adversarial-review F6c: rows can be typed without
# any run ever executing). Every ISO timestamp in a RED cell must match a
# red run in .claude/tdd/runs.log within TOLERANCE seconds; every GREEN cell
# a wrapper green/red-at-baseline run. Exit 0 PASS / 1 FAIL with gaps listed.
# Run by the qa-verifier agent — a script verdict, not an LLM judgment.
set -u
TOLERANCE=300

TASK_DIR="${1:?usage: verify-evidence.sh <task-artifacts-dir>}"
EVIDENCE="$TASK_DIR/evidence.md"
[ -f "$EVIDENCE" ] || { echo "FAIL: no evidence.md in $TASK_DIR"; exit 1; }

ROOT="$TASK_DIR"
while [ "$ROOT" != "/" ] && [ ! -f "$ROOT/.claude/team.json" ]; do ROOT=$(dirname "$ROOT"); done
RUNS="$ROOT/.claude/tdd/runs.log"
[ -f "$RUNS" ] || { echo "FAIL: no runs.log at $RUNS — no test run was ever recorded"; exit 1; }

to_epoch() { date -u -d "$1" +%s 2>/dev/null || date -u -j -f %Y-%m-%dT%H:%M:%SZ "$1" +%s 2>/dev/null || echo 0; }

# runs.log lines: {"ts":"...","kind":"wrapper|observed",...,"status":"red|green|error",...}
match_run() { # match_run <iso-ts> <wanted-status> [wanted-kind]
  local want_ts want_status="$2" want_kind="${3:-}" line ts st kind e1 e2
  want_ts=$(to_epoch "$1")
  [ "$want_ts" -gt 0 ] || return 1
  while IFS= read -r line; do
    ts=$(printf '%s' "$line" | grep -oE '"ts":"[^"]*"' | cut -d'"' -f4)
    st=$(printf '%s' "$line" | grep -oE '"status":"[^"]*"' | cut -d'"' -f4)
    kind=$(printf '%s' "$line" | grep -oE '"kind":"[^"]*"' | cut -d'"' -f4)
    [ "$st" = "$want_status" ] || continue
    [ -z "$want_kind" ] || [ "$kind" = "$want_kind" ] || continue
    e1=$(to_epoch "$ts")
    e2=$((want_ts - e1)); [ $e2 -lt 0 ] && e2=$((-e2))
    [ $e2 -le $TOLERANCE ] && return 0
  done <"$RUNS"
  return 1
}

FAILS=0
CHECKED=0
# Evidence rows carry cells like "RED exit=1 2026-08-20T10:12:00Z" and
# "GREEN 2026-08-20T10:31:00Z" (schema: skills/build/references/artifact-schemas.md).
while IFS= read -r line; do
  case "$line" in \|*\|*\|*) : ;; *) continue ;; esac
  red_ts=$(printf '%s' "$line" | grep -oE 'RED[^|]*[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9:]{8}Z' | grep -oE '[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9:]{8}Z' | head -1)
  green_ts=$(printf '%s' "$line" | grep -oE 'GREEN[^|]*[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9:]{8}Z' | grep -oE '[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9:]{8}Z' | head -1)
  if [ -n "$red_ts" ]; then
    CHECKED=$((CHECKED + 1))
    if ! match_run "$red_ts" red; then
      echo "GAP: evidence claims RED at $red_ts but runs.log has no red run within ${TOLERANCE}s: $line"
      FAILS=$((FAILS + 1))
    fi
  fi
  if [ -n "$green_ts" ]; then
    CHECKED=$((CHECKED + 1))
    if ! match_run "$green_ts" green wrapper; then
      echo "GAP: evidence claims GREEN at $green_ts but runs.log has no wrapper green within ${TOLERANCE}s: $line"
      FAILS=$((FAILS + 1))
    fi
  fi
done <"$EVIDENCE"

if [ $CHECKED -eq 0 ]; then
  echo "FAIL: evidence.md contains no timestamped RED/GREEN cells to verify"
  exit 1
fi
if [ $FAILS -gt 0 ]; then
  echo "FAIL: $FAILS of $CHECKED evidence claims have no matching recorded run"
  exit 1
fi
echo "PASS: all $CHECKED evidence claims match recorded runs"
exit 0
