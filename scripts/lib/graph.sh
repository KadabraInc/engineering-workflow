# graph.sh — hardened wrapper around the optional code-review-graph CLI.
#
# Findings that shaped this file (adversarial review F6): the tool is young
# and solo-maintained, so we pin a tested version range, call CLI-only (never
# its MCP install, which mutates user-global config), always pass an absolute
# --repo (relative paths have wiped graphs upstream), cap output, and stop
# calling it after repeated failures (circuit breaker). Nothing in the
# pipeline may REQUIRE graph output — every consumer has a Grep/Glob fallback.

GRAPH_MIN_VERSION="2.3"
GRAPH_MAX_FAILURES=3
GRAPH_TIMEOUT_S=20
GRAPH_OUTPUT_CAP=8000   # bytes forwarded to context, max

graph_failures_file() { printf '%s/.claude/team/graph-failures' "$TEAM_ROOT"; }

graph_available() {
  [ "$(json_get "$TEAM_CONFIG" .graph.enabled true)" = "false" ] && return 1
  command -v code-review-graph >/dev/null 2>&1 || return 1
  local f; f=$(graph_failures_file)
  if [ -f "$f" ] && [ "$(wc -l <"$f" 2>/dev/null | tr -d '[:space:]')" -ge "$GRAPH_MAX_FAILURES" ]; then
    return 1   # circuit open
  fi
  return 0
}

graph_version_ok() {
  local v
  v=$(code-review-graph --version 2>/dev/null | grep -oE '[0-9]+\.[0-9]+' | head -1)
  [ -n "$v" ] || return 1
  [ "$(printf '%s\n%s\n' "$GRAPH_MIN_VERSION" "$v" | sort -V | head -1)" = "$GRAPH_MIN_VERSION" ]
}

# graph_run <args...> — timeout-bounded, output-capped, failure-counted.
graph_run() {
  graph_available || { echo "(graph unavailable — using fallback)"; return 1; }
  local out rc
  out=$(cd "$TEAM_ROOT" && timeout "$GRAPH_TIMEOUT_S" code-review-graph "$@" --repo "$TEAM_ROOT" 2>&1)
  rc=$?
  if [ $rc -ne 0 ]; then
    printf '%s %s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "rc=$rc args=$*" >>"$(graph_failures_file)" 2>/dev/null || true
    echo "(graph call failed rc=$rc — using fallback)"
    return 1
  fi
  : >"$(graph_failures_file)" 2>/dev/null || true   # success closes the breaker
  printf '%s' "$out" | head -c "$GRAPH_OUTPUT_CAP"
}
