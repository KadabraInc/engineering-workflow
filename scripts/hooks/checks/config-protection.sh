#!/usr/bin/env bash
# config-protection.sh — PreToolUse check on Write|Edit|MultiEdit|NotebookEdit.
#
# Denies edits to files that define or enforce the quality bar, so the path
# of least resistance is fixing code, never weakening the gate:
#   - the protected class from team.json globs (test/lint/tsconfig configs)
#   - the always-protected set (team.json itself, TDD state, audit log,
#     .claude/settings*.json)
#   - the plugin's own installed files (editing dispatch.sh disarms every
#     project on the machine — adversarial-review F3)
# Humans are not bound: these bind the model's Edit tool only, by design.
set -u
. "$PLUGIN_ROOT/scripts/lib/json.sh"
. "$PLUGIN_ROOT/scripts/lib/common.sh"

CHECK="config-protection"
[ -n "${TARGET_FILE:-}" ] || exit 0

# The plugin's own files are off-limits wherever they live.
ABS="$TARGET_FILE"
case "$ABS" in
  /*) : ;;
  *) ABS="${CWD:-$PWD}/$ABS" ;;
esac
case "$ABS" in
  "$PLUGIN_ROOT"/*)
    decide "$CHECK" "$ABS" "This is the team plugin's own code — changing it would alter enforcement for every project. Propose the change to the human instead (plugin repo: KadabraInc/engineering-workflow)"
    exit 0
    ;;
esac

REL=$(rel_path "$TEAM_ROOT" "$TARGET_FILE")
[ -n "$REL" ] || exit 0

if [ "$(classify_path "$REL")" = "protected" ]; then
  # One carve-out: the human-editable knowledge README is never protected;
  # everything else in the class is gate-defining.
  decide "$CHECK" "$REL" "Protected file (gate/config surface). Fix the code instead of the config; if the config is genuinely wrong, ask the human to change it or to grant a one-shot override (.claude/tdd/allow)"
fi
exit 0
