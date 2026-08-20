#!/usr/bin/env bash
# simulate-hook.sh — craft a hook payload and pipe it through dispatch.sh,
# printing the decision. Local development + the /team:status self-test.
#
#   simulate-hook.sh pre-edit --file <path> [--project <dir>]
#   simulate-hook.sh pre-bash --command '<cmd>' [--project <dir>]
#   simulate-hook.sh post-bash --command '<cmd>' --output '<text>' --exit <n>
#   simulate-hook.sh stop [--project <dir>]
#   simulate-hook.sh session-start [--project <dir>]
set -u
ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd -P)

EVENT="${1:?usage: simulate-hook.sh <event> [--file|--command|--output|--exit|--project ...]}"
shift
FILE=""; COMMAND=""; OUTPUT=""; EXITC="0"; PROJECT="$PWD"
while [ $# -gt 0 ]; do
  case "$1" in
    --file) FILE="$2"; shift 2 ;;
    --command) COMMAND="$2"; shift 2 ;;
    --output) OUTPUT="$2"; shift 2 ;;
    --exit) EXITC="$2"; shift 2 ;;
    --project) PROJECT="$2"; shift 2 ;;
    *) echo "unknown arg $1" >&2; exit 1 ;;
  esac
done

esc() {
  local s="$1"
  s=${s//\\/\\\\}
  s=${s//\"/\\\"}
  s=${s//$'\n'/\\n}
  s=${s//$'\r'/\\r}
  s=${s//$'\t'/\\t}
  printf '%s' "$s"
}

case "$EVENT" in
  pre-edit|post-edit)
    PAYLOAD=$(printf '{"session_id":"simulate","cwd":"%s","tool_name":"Write","tool_input":{"file_path":"%s"}}' "$(esc "$PROJECT")" "$(esc "$FILE")")
    ;;
  pre-bash)
    PAYLOAD=$(printf '{"session_id":"simulate","cwd":"%s","tool_name":"Bash","tool_input":{"command":"%s"}}' "$(esc "$PROJECT")" "$(esc "$COMMAND")")
    ;;
  post-bash)
    PAYLOAD=$(printf '{"session_id":"simulate","cwd":"%s","tool_name":"Bash","tool_input":{"command":"%s"},"tool_response":{"text":"%s","exit_code":%s}}' "$(esc "$PROJECT")" "$(esc "$COMMAND")" "$(esc "$OUTPUT")" "$EXITC")
    ;;
  stop)
    PAYLOAD=$(printf '{"session_id":"simulate","cwd":"%s","stop_hook_active":false}' "$(esc "$PROJECT")")
    ;;
  session-start)
    PAYLOAD=$(printf '{"session_id":"simulate","cwd":"%s"}' "$(esc "$PROJECT")")
    ;;
  *) echo "unknown event $EVENT" >&2; exit 1 ;;
esac

printf '%s' "$PAYLOAD" | CLAUDE_PLUGIN_ROOT="$ROOT" bash "$ROOT/scripts/hooks/dispatch.sh" "$EVENT"
RC=$?
echo "--- dispatch exit: $RC $( [ $RC -eq 2 ] && echo '(BLOCKED)' )" >&2
exit $RC
