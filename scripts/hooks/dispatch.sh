#!/usr/bin/env bash
# dispatch.sh <event-key> — the single hook entry point.
#
# Reads the hook payload from stdin exactly once, resolves the consuming
# project's root FROM THE OPERATION TARGET, and runs the checks registered
# for the event in hooks/registry.json. Inert (exit 0, no output) unless the
# project has opted in via .claude/team.json.
#
# Check protocol (each check gets the payload on stdin and these env vars:
# EVENT, MODE, TEAM_ROOT, TEAM_CONFIG, PLUGIN_ROOT, PAYLOAD_FILE, TOOL_NAME,
# TARGET_FILE, SESSION_ID, CWD, PROFILE):
#   - nothing on stdout, exit 0            -> allow
#   - "WARN:<reason>" lines                -> aggregated into one systemMessage
#   - PreToolUse deny JSON (emit_deny)     -> forwarded verbatim, first wins
#   - "BLOCK:<reason>" (stop event only)   -> dispatcher exits 2, reason on stderr
#   - "CTX:" prefix lines (session-start)  -> stripped and printed as context
# A check that crashes is treated as allow (fail-open) but audited.
set -u

EVENT="${1:-}"
[ -n "$EVENT" ] || exit 0

SELF_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)
PLUGIN_ROOT="${CLAUDE_PLUGIN_ROOT:-$(cd "$SELF_DIR/../.." && pwd -P)}"
export PLUGIN_ROOT

# shellcheck source=../lib/json.sh
. "$PLUGIN_ROOT/scripts/lib/json.sh"
# shellcheck source=../lib/common.sh
. "$PLUGIN_ROOT/scripts/lib/common.sh"

# --- read payload once ------------------------------------------------------
PAYLOAD_FILE=$(mktemp "${TMPDIR:-/tmp}/team-hook.XXXXXX") || exit 0
trap 'rm -f "$PAYLOAD_FILE"' EXIT
cat >"$PAYLOAD_FILE" 2>/dev/null || true

# With no JSON runtime we cannot parse the payload; fail open, but loudly on
# session-start so the condition is visible.
if [ -z "$JSON_RUNTIME" ]; then
  if [ "$EVENT" = "session-start" ]; then
    printf 'team plugin: no JSON runtime found (need jq, node, or python3). All team gates are DISARMED (fail-open).\n'
  fi
  exit 0
fi

TOOL_NAME=$(json_get "$PAYLOAD_FILE" .tool_name "")
CWD=$(json_get "$PAYLOAD_FILE" .cwd "")
SESSION_ID=$(json_get "$PAYLOAD_FILE" .session_id "")
TARGET_FILE=$(json_get "$PAYLOAD_FILE" .tool_input.file_path "")
[ -n "$TARGET_FILE" ] || TARGET_FILE=$(json_get "$PAYLOAD_FILE" .tool_input.notebook_path "")
export TOOL_NAME CWD SESSION_ID TARGET_FILE PAYLOAD_FILE EVENT

# --- resolve project root ---------------------------------------------------
# Edit-family events resolve from the target file; everything else from cwd.
case "$EVENT" in
  pre-edit|post-edit) ROOT_HINT="${TARGET_FILE:-$CWD}" ;;
  *)                  ROOT_HINT="${CWD:-$PWD}" ;;
esac
TEAM_ROOT=$(find_team_root "$ROOT_HINT")
[ -n "$TEAM_ROOT" ] || exit 0                       # inert outside team projects
TEAM_CONFIG="$TEAM_ROOT/.claude/team.json"
export TEAM_ROOT TEAM_CONFIG

# --- master switches ---------------------------------------------------------
[ "${TEAM_HOOKS:-on}" = "off" ] && exit 0
[ "$(json_get "$TEAM_CONFIG" .hooks.enabled true)" = "false" ] && exit 0

# --- profile ------------------------------------------------------------------
# Pipeline sessions (marker written by /team:build|fix|quick) run the pipeline
# profile (default strict: hard gate). Ambient sessions run the ambient
# profile (default standard: warn + audit). Env var overrides everything.
if [ -n "${TEAM_HOOK_PROFILE:-}" ]; then
  PROFILE="$TEAM_HOOK_PROFILE"
elif [ -f "$TEAM_ROOT/.claude/tdd/pipeline" ]; then
  PROFILE=$(json_get "$TEAM_CONFIG" .hooks.pipeline_profile "strict")
else
  PROFILE=$(json_get "$TEAM_CONFIG" .hooks.ambient_profile "standard")
fi
export PROFILE

# --- run registered checks ---------------------------------------------------
REGISTRY="$PLUGIN_ROOT/hooks/registry.json"
WARNINGS=""
CONTEXT=""

# json.sh only walks object keys, so enumerate check entries with the runtime.
list_checks() {
  case "$JSON_RUNTIME" in
    jq) jq -r --arg ev "$EVENT" '.checks[$ev] // [] | .[] | [.id, .script, (.mode[$ENV.PROFILE] // "off")] | @tsv' "$REGISTRY" 2>/dev/null ;;
    node) node -e '
      const r = JSON.parse(require("fs").readFileSync(process.argv[1], "utf8"));
      for (const c of (r.checks[process.argv[2]] || [])) {
        console.log([c.id, c.script, (c.mode || {})[process.env.PROFILE] || "off"].join("\t"));
      }' "$REGISTRY" "$EVENT" 2>/dev/null ;;
    python3) python3 -c '
import json, os, sys
r = json.load(open(sys.argv[1]))
for c in r.get("checks", {}).get(sys.argv[2], []):
    print("\t".join([c["id"], c["script"], c.get("mode", {}).get(os.environ.get("PROFILE", ""), "off")]))
' "$REGISTRY" "$EVENT" 2>/dev/null ;;
  esac
}

while IFS=$'\t' read -r check_id check_script check_mode; do
  [ -n "${check_id:-}" ] || continue
  [ "$check_mode" = "off" ] && continue
  MODE="$check_mode"
  export MODE
  out=$(bash "$PLUGIN_ROOT/scripts/hooks/$check_script" <"$PAYLOAD_FILE" 2>/dev/null)
  rc=$?
  if [ $rc -ne 0 ]; then
    audit_log "$EVENT" "$check_id" "check-error" "${TARGET_FILE:-}" "check exited $rc; failing open"
    continue
  fi
  [ -n "$out" ] || continue
  while IFS= read -r line; do
    case "$line" in
      WARN:*)  WARNINGS="${WARNINGS:+$WARNINGS | }${line#WARN:}" ;;
      CTX:*)   CONTEXT="${CONTEXT}${line#CTX:}"$'\n' ;;
      BLOCK:*)
        # Stop-event block: exit 2 puts the reason in front of the model.
        printf '%s\n' "${line#BLOCK:}" >&2
        exit 2
        ;;
      '{'*'permissionDecision'*)
        printf '%s\n' "$line"          # first deny wins
        exit 0
        ;;
    esac
  done <<<"$out"
done < <(list_checks)

# --- non-blocking output ------------------------------------------------------
if [ "$EVENT" = "session-start" ]; then
  [ -n "$CONTEXT" ] && printf '%s' "$CONTEXT"
  [ -n "$WARNINGS" ] && printf '\n[team] %s\n' "$WARNINGS"
  exit 0
fi
if [ -n "$WARNINGS" ]; then
  printf '{"systemMessage":"[team] %s"}\n' "$(json_escape "$WARNINGS")"
fi
exit 0
