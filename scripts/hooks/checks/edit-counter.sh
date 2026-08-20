#!/usr/bin/env bash
# edit-counter.sh — PostToolUse check on Write|Edit|MultiEdit|NotebookEdit.
# Appends one line per source/test edit to append-only counter logs (line
# appends interleave whole lines; no locking needed). The wrapper truncates
# them on every verified run; the gate's green budget counts source lines.
# Delivery accounting does NOT rely on these (it uses git diff truth) — the
# counters only feed the in-session refactor budget.
set -u
. "$PLUGIN_ROOT/scripts/lib/json.sh"
. "$PLUGIN_ROOT/scripts/lib/common.sh"

[ -n "${TARGET_FILE:-}" ] || exit 0
REL=$(rel_path "$TEAM_ROOT" "$TARGET_FILE")
[ -n "$REL" ] || exit 0

case "$(classify_path "$REL")" in
  source) append_line "$TEAM_ROOT/.claude/tdd/counters/source_edits.log" "$(now_iso) $REL" ;;
  test)   append_line "$TEAM_ROOT/.claude/tdd/counters/test_edits.log"   "$(now_iso) $REL" ;;
esac
exit 0
