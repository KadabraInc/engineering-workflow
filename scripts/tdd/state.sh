#!/usr/bin/env bash
# state.sh — TDD state helpers, sourceable and CLI-able.
#
#   state.sh fingerprint            print current test-file fingerprint
#   state.sh status                 print one-line human status
#   state.sh pipeline-on|off        mark/unmark this repo as running a /team:* flow
#   state.sh phase <name>|clear     record the active pipeline phase (implement, qa, ...)
#
# State lives in .claude/tdd/state.json — written ONLY by scripts (the
# wrapper and the observer), never by the model directly; the file is in the
# always-protected set. Unrecognized schema versions read as status=unknown
# (fail-closed), never as green.
set -u

STATE_SELF_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)
if ! command -v json_get >/dev/null 2>&1; then
  . "$STATE_SELF_DIR/../lib/json.sh"
  . "$STATE_SELF_DIR/../lib/common.sh"
fi

TDD_SCHEMA_VERSION=1

tdd_dir()        { printf '%s/.claude/tdd' "$TEAM_ROOT"; }
tdd_state_file() { printf '%s/state.json' "$(tdd_dir)"; }

# state_get <key> <default> — reads a top-level state key; any state file with
# a schema_version we don't know yields the default (fail-closed).
state_get() {
  local f; f=$(tdd_state_file)
  [ -f "$f" ] || { printf '%s' "$2"; return 0; }
  local sv; sv=$(json_get "$f" .schema_version "0")
  if [ "$sv" != "$TDD_SCHEMA_VERSION" ]; then
    # Unknown schema is fail-closed: status reads unknown, bootstrap reads
    # false (a default of true here would fail OPEN via the bootstrap allow).
    case "$1" in
      status)    printf 'unknown' ;;
      bootstrap) printf 'false' ;;
      *)         printf '%s' "$2" ;;
    esac
    return 0
  fi
  json_get "$f" ".$1" "$2"
}

# ---------------------------------------------------------------------------
# Fingerprint: sorted "path:size:mtime" lines over files matching globs.test,
# sha256'd, prefixed "stat:". This MUST stay byte-identical to
# fingerprint_stat() in run-tests.sh — the shim writes it, the gate compares
# it; algorithm drift reads as permanent "unknown" and bricks the gate.
# Stat-based (not content-based) is a deliberate trade: cheap on any repo and
# implementable in the dependency-free shim; the touch-spoof residual is
# documented in docs/tdd-gate.md and covered by the run-log cross-check.
# ---------------------------------------------------------------------------
list_test_files() {
  local files
  if git -C "$TEAM_ROOT" rev-parse --git-dir >/dev/null 2>&1; then
    files=$(git -C "$TEAM_ROOT" ls-files --cached --others --exclude-standard 2>/dev/null)
  else
    files=$(cd "$TEAM_ROOT" && find . -type f -not -path './.git/*' 2>/dev/null | sed 's|^\./||')
  fi
  local f
  while IFS= read -r f; do
    [ -n "$f" ] || continue
    if json_get_list "$TEAM_CONFIG" .globs.test | glob_match_any_stdin "$f"; then
      printf '%s\n' "$f"
    fi
  done <<<"$files"
}

fingerprint_tests() {
  local f lines=""
  while IFS= read -r f; do
    [ -n "$f" ] || continue
    if [ -f "$TEAM_ROOT/$f" ]; then
      lines="${lines}${f}:$(wc -c <"$TEAM_ROOT/$f" 2>/dev/null || echo 0):$(stat -c %Y "$TEAM_ROOT/$f" 2>/dev/null || stat -f %m "$TEAM_ROOT/$f" 2>/dev/null || echo 0)"$'\n'
    fi
  done < <(list_test_files)
  printf 'stat:%s' "$(sha256_of_string "$(printf '%s' "$lines" | LC_ALL=C sort)")"
}

# ---------------------------------------------------------------------------
# Counters: append-only line logs (race-safe without locking). The wrapper
# truncates them on every verified run; budgets count lines.
# ---------------------------------------------------------------------------
count_lines() { [ -f "$1" ] || { echo 0; return; }; wc -l <"$1" 2>/dev/null | tr -d '[:space:]'; }
source_edits_since_run() { count_lines "$(tdd_dir)/counters/source_edits.log"; }
test_edits_since_run()   { count_lines "$(tdd_dir)/counters/test_edits.log"; }

# ---------------------------------------------------------------------------
# CLI
# ---------------------------------------------------------------------------
if [ "${BASH_SOURCE[0]}" = "${0}" ]; then
  TEAM_ROOT=${TEAM_ROOT:-$(find_team_root "$PWD")}
  [ -n "$TEAM_ROOT" ] || { echo "state.sh: no .claude/team.json found from $PWD" >&2; exit 1; }
  TEAM_CONFIG="$TEAM_ROOT/.claude/team.json"
  case "${1:-status}" in
    fingerprint) fingerprint_tests; echo ;;
    pipeline-on)  mkdir -p "$(tdd_dir)"; printf '{"since":"%s"}\n' "$(now_iso)" >"$(tdd_dir)/pipeline" ;;
    pipeline-off) rm -f "$(tdd_dir)/pipeline" ;;
    phase)
      case "${2:-}" in
        clear|'') rm -f "$(tdd_dir)/phase" ;;
        *) mkdir -p "$(tdd_dir)"; printf '%s\n' "$2" >"$(tdd_dir)/phase" ;;
      esac
      ;;
    status)
      s=$(state_get status unknown); v=$(state_get verified false); sc=$(state_get scope none)
      fc=$(state_get failing_count -1); bl=$(state_get baseline.failing_count -1)
      eg=$(state_get ever_green false); ft=$(state_get finished_at never)
      echo "tdd: status=$s verified=$v scope=$sc failing=$fc baseline=$bl ever_green=$eg last_run=$ft"
      echo "edits since run: source=$(source_edits_since_run) test=$(test_edits_since_run)"
      [ -f "$(tdd_dir)/pipeline" ] && echo "pipeline session: ACTIVE (strict profile)" || echo "pipeline session: no (ambient profile)"
      ;;
    *) echo "usage: state.sh [fingerprint|status|pipeline-on|pipeline-off|phase <name>|clear]" >&2; exit 1 ;;
  esac
fi
