#!/usr/bin/env bash
# team-shim v0.1.0
#
# The verified test wrapper — the ONLY writer of "green". Self-contained on
# purpose: /team:setup copies this file to <project>/.claude/tdd/run-tests so
# teammates and CI can run it without the plugin installed. Keep it minimal;
# every line here is drift surface (the session banner warns when this copy's
# version lags the plugin).
#
# Usage:
#   run-tests                     full configured suite -> may write green
#   run-tests --targeted <pat>    targeted run -> may write scoped green/red
#   run-tests --baseline          full run; record result as the brownfield baseline
#   run-tests --background        full run detached (PID file; state written at completion)
#
# Status semantics (adversarial-review F9): red requires BOTH a nonzero exit
# AND a fail-pattern match; exit 126/127 or command-not-found is "error", its
# own state — a broken test command must never read as either red or green.
set -u

SHIM_VERSION="0.1.0"
SCHEMA_VERSION=1

# --- locate project ----------------------------------------------------------
ROOT="$PWD"
while [ "$ROOT" != "/" ] && [ ! -f "$ROOT/.claude/team.json" ]; do ROOT=$(dirname "$ROOT"); done
[ -f "$ROOT/.claude/team.json" ] || { echo "run-tests: no .claude/team.json found from $PWD" >&2; exit 1; }
CFG="$ROOT/.claude/team.json"
TDD="$ROOT/.claude/tdd"
mkdir -p "$TDD/counters"

# --- minimal JSON access (jq -> node -> python3) ------------------------------
jget() { # jget <dotted.path> <default>
  local path="$1" default="${2-}" out=""
  if command -v jq >/dev/null 2>&1; then
    # never '// empty': jq treats boolean false as missing under '//'
    out=$(jq -r "${path} | if . == null then empty else tostring end" "$CFG" 2>/dev/null)
  elif command -v node >/dev/null 2>&1; then
    out=$(node -e 'const f=require("fs");try{let v=JSON.parse(f.readFileSync(process.argv[1],"utf8"));for(const k of process.argv[2].split(".").filter(Boolean)){v=(v??{})[k];}if(v!=null)process.stdout.write(String(v));}catch(e){}' "$CFG" "$path" 2>/dev/null)
  elif command -v python3 >/dev/null 2>&1; then
    out=$(python3 -c 'import json,sys
try:
    v=json.load(open(sys.argv[1]))
    for k in [p for p in sys.argv[2].split(".") if p]: v=v.get(k) if isinstance(v,dict) else None
    if v is not None: sys.stdout.write(str(v).lower() if isinstance(v,bool) else str(v))
except Exception: pass' "$CFG" "$path" 2>/dev/null)
  fi
  [ -n "$out" ] && printf '%s' "$out" || printf '%s' "$default"
}

sget() { # sget <dotted.path> <default> — same but against state.json
  local saved="$CFG"; CFG="$TDD/state.json"
  [ -f "$CFG" ] || { CFG="$saved"; printf '%s' "$2"; return 0; }
  jget "$1" "$2"; CFG="$saved"
}

jesc() { local s="$1"; s=${s//\\/\\\\}; s=${s//\"/\\\"}; s=${s//$'\n'/\\n}; s=${s//$'\t'/\\t}; printf '%s' "$s"; }

# --- stat-based fingerprint (shared contract with the plugin's state.sh) ------
fingerprint_stat() {
  local files f lines=""
  if git -C "$ROOT" rev-parse --git-dir >/dev/null 2>&1; then
    files=$(git -C "$ROOT" ls-files --cached --others --exclude-standard 2>/dev/null)
  else
    files=$(cd "$ROOT" && find . -type f -not -path './.git/*' 2>/dev/null | sed 's|^\./||')
  fi
  local pats; pats=$(if command -v jq >/dev/null 2>&1; then jq -r '(.globs.test // [])[]' "$CFG" 2>/dev/null; else jget .globs.test ""; fi)
  while IFS= read -r f; do
    [ -n "$f" ] || continue
    local p matched=""
    while IFS= read -r p; do
      [ -n "$p" ] || continue
      local q=${p//\*\*/\*}
      # shellcheck disable=SC2254
      case "$f" in $q) matched=1 ;; esac
      case "$p" in \*\*/*) local t=${p#\*\*/}; t=${t//\*\*/\*}
        # shellcheck disable=SC2254
        case "$f" in $t) matched=1 ;; esac ;;
      esac
    done <<<"$pats"
    if [ -n "$matched" ] && [ -f "$ROOT/$f" ]; then
      lines="${lines}${f}:$(wc -c <"$ROOT/$f" 2>/dev/null || echo 0):$(stat -c %Y "$ROOT/$f" 2>/dev/null || stat -f %m "$ROOT/$f" 2>/dev/null || echo 0)"$'\n'
    fi
  done <<<"$files"
  local sorted; sorted=$(printf '%s' "$lines" | LC_ALL=C sort)
  if command -v sha256sum >/dev/null 2>&1; then printf 'stat:%s' "$(printf '%s' "$sorted" | sha256sum | cut -d' ' -f1)"
  elif command -v shasum >/dev/null 2>&1; then printf 'stat:%s' "$(printf '%s' "$sorted" | shasum -a 256 | cut -d' ' -f1)"
  else printf 'stat:%s' "$(printf '%s' "$sorted" | cksum | tr ' ' '-')"
  fi
}

# --- args ---------------------------------------------------------------------
SCOPE="full"; PATTERN=""; BASELINE=0; BACKGROUND=0
while [ $# -gt 0 ]; do
  case "$1" in
    --targeted) SCOPE="targeted"; PATTERN="${2:-}"; shift 2 ;;
    --baseline) BASELINE=1; shift ;;
    --background) BACKGROUND=1; shift ;;
    --child) BACKGROUND=2; shift ;;   # internal: we ARE the detached child
    *) echo "run-tests: unknown arg $1" >&2; exit 1 ;;
  esac
done

if [ "$BACKGROUND" = "1" ]; then
  CHILD_ARGS="--child"
  [ "$BASELINE" = 1 ] && CHILD_ARGS="$CHILD_ARGS --baseline"
  # shellcheck disable=SC2086
  nohup bash "$0" $CHILD_ARGS >"$TDD/background.out" 2>&1 &
  echo $! >"$TDD/run.pid"
  echo "run-tests: full suite started in background (pid $(cat "$TDD/run.pid")). State is written at completion; check .claude/tdd/state.json (finished_at changes) or .claude/tdd/background.out"
  exit 0
fi

# --- pick command ---------------------------------------------------------------
CMD=$(jget .test.command "")
[ -n "$CMD" ] || { echo "run-tests: test.command not configured in .claude/team.json (gate is UNARMED). Run /team:setup." >&2; exit 1; }
if [ "$SCOPE" = "targeted" ]; then
  TCMD=$(jget .test.targeted_command "")
  [ -n "$TCMD" ] || { echo "run-tests: test.targeted_command not configured; run the full suite or add it to team.json" >&2; exit 1; }
  [ -n "$PATTERN" ] || { echo "run-tests: --targeted requires a pattern" >&2; exit 1; }
  CMD=${TCMD//\{pattern\}/$PATTERN}
fi

# --- run ------------------------------------------------------------------------
STARTED=$(date -u +%Y-%m-%dT%H:%M:%SZ)
LOG="$TDD/last-run.log"
( cd "$ROOT" && bash -c "$CMD" ) >"$LOG" 2>&1
EXIT=$?

RETRIES=$(jget .delivery.retry_failed 0)
RETRIED=false
if [ "$EXIT" -ne 0 ] && [ "$SCOPE" = "full" ] && [ "${RETRIES:-0}" -ge 1 ]; then
  ( cd "$ROOT" && bash -c "$CMD" ) >"$LOG" 2>&1
  EXIT=$?
  RETRIED=true
fi
FINISHED=$(date -u +%Y-%m-%dT%H:%M:%SZ)

# --- classify --------------------------------------------------------------------
FAIL_COUNT=-1
FCP=$(jget .test.fail_count_pattern "")
if [ -n "$FCP" ]; then
  FAIL_COUNT=$(grep -oE "$FCP" "$LOG" 2>/dev/null | head -1 | grep -oE '[0-9]+' | head -1)
  [ -n "$FAIL_COUNT" ] || FAIL_COUNT=-1
fi
PATTERN_HIT=0
while IFS= read -r pat; do
  [ -n "$pat" ] || continue
  grep -qE "$pat" "$LOG" 2>/dev/null && PATTERN_HIT=1
done <<<"$(if command -v jq >/dev/null 2>&1; then jq -r '(.test.fail_patterns // [])[]' "$CFG" 2>/dev/null; fi)"

STATUS="error"
if [ "$EXIT" -eq 0 ]; then
  STATUS="green"
elif [ "$EXIT" -eq 126 ] || [ "$EXIT" -eq 127 ] || head -10 "$LOG" | grep -qiE 'command not found|no such file or directory'; then
  STATUS="error"
elif [ "$PATTERN_HIT" -eq 1 ] || [ "${FAIL_COUNT:-0}" -gt 0 ]; then
  STATUS="red"
else
  STATUS="error"   # nonzero exit with no recognizable test failure = broken command, not red
fi

# --- preserve sticky fields -------------------------------------------------------
BASE_COUNT=$(sget .baseline.failing_count -1)
BASE_AT=$(sget .baseline.captured_at "")
EVER_GREEN=$(sget .ever_green false)
if [ "$STATUS" = "green" ] && [ "$SCOPE" = "full" ]; then EVER_GREEN=true; fi
if [ "$BASELINE" = 1 ] && [ "$SCOPE" = "full" ]; then
  BASE_COUNT=$([ "$STATUS" = "green" ] && echo 0 || echo "$FAIL_COUNT")
  BASE_AT="$FINISHED"
fi

FP=$(fingerprint_stat)

# --- write state atomically --------------------------------------------------------
TMP="$TDD/.state.json.tmp.$$"
cat >"$TMP" <<EOF
{
  "schema_version": $SCHEMA_VERSION,
  "shim_version": "$SHIM_VERSION",
  "status": "$STATUS",
  "verified": true,
  "scope": "$SCOPE",
  "command": "$(jesc "$CMD")",
  "exit_code": $EXIT,
  "retried": $RETRIED,
  "started_at": "$STARTED",
  "finished_at": "$FINISHED",
  "failing_count": ${FAIL_COUNT:--1},
  "tests_fingerprint": "$FP",
  "baseline": { "failing_count": ${BASE_COUNT:--1}, "captured_at": "$BASE_AT" },
  "ever_green": $EVER_GREEN,
  "bootstrap": false
}
EOF
mv -f "$TMP" "$TDD/state.json"

# Verified run: budgets reset.
: >"$TDD/counters/source_edits.log" 2>/dev/null || true
: >"$TDD/counters/test_edits.log" 2>/dev/null || true
rm -f "$TDD/refactor" 2>/dev/null || true

printf '{"ts":"%s","kind":"wrapper","scope":"%s","exit":%s,"failing":%s,"status":"%s","command":"%s"}\n' \
  "$FINISHED" "$SCOPE" "$EXIT" "${FAIL_COUNT:--1}" "$STATUS" "$(jesc "$CMD")" >>"$TDD/runs.log"

# --- report ---------------------------------------------------------------------------
tail -20 "$LOG"
echo "---"
echo "run-tests: status=$STATUS scope=$SCOPE exit=$EXIT failing=${FAIL_COUNT} (full output: .claude/tdd/last-run.log)"
if [ "$STATUS" = "error" ]; then
  echo "run-tests: the test command itself failed to run — fix .claude/team.json test.command or re-run /team:setup" >&2
fi
[ "$STATUS" = "green" ] || exit 1
exit 0
