#!/usr/bin/env bash
# graph-update.sh — PostToolUse check on Write|Edit|MultiEdit|NotebookEdit.
# Fire-and-forget incremental code-review-graph refresh so the graph stays
# usable across a session. Never blocks, never prints, costs ~0 when the tool
# is absent, and stops spawning entirely once the circuit breaker opens.
set -u
. "$PLUGIN_ROOT/scripts/lib/json.sh"
. "$PLUGIN_ROOT/scripts/lib/common.sh"
. "$PLUGIN_ROOT/scripts/lib/graph.sh"

[ -n "${TARGET_FILE:-}" ] || exit 0
graph_available || exit 0
REL=$(rel_path "$TEAM_ROOT" "$TARGET_FILE")
[ -n "$REL" ] || exit 0
case "$REL" in .claude/*|.git/*) exit 0 ;; esac

(
  cd "$TEAM_ROOT" &&
  timeout "$GRAPH_TIMEOUT_S" code-review-graph update --repo "$TEAM_ROOT" >/dev/null 2>&1 ||
  printf '%s update-failed\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)" >>"$(graph_failures_file)"
) &
exit 0
