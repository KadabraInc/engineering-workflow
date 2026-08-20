# shellcheck shell=bash
# common.sh — shared helpers for all team-plugin hook checks and scripts.
# Bash + coreutils only; JSON access via json.sh's runtime shim.
#
# Contract for consumers: source json.sh first, then this file.

# ---------------------------------------------------------------------------
# Project root resolution
# ---------------------------------------------------------------------------
# The root is the nearest ancestor directory containing .claude/team.json,
# resolved FROM THE TARGET of the operation (the file being edited), not from
# cwd — a session cd'd elsewhere editing /repo/src/x.py by absolute path must
# still be gated (and a scratchpad file must not be). Falls back to the
# nearest .git ancestor only to answer "is there even a repo here".
#
# find_team_root <start-path>  -> prints root dir, or nothing if none found.
find_team_root() {
  local p="$1"
  [ -n "$p" ] || return 0
  [ -d "$p" ] || p=$(dirname -- "$p")
  # Normalize to an absolute physical path; a nonexistent dir (new file in a
  # new subdir) walks up to its first existing ancestor.
  while [ -n "$p" ] && [ ! -d "$p" ]; do p=$(dirname -- "$p"); done
  p=$(cd "$p" 2>/dev/null && pwd -P) || return 0
  while [ -n "$p" ] && [ "$p" != "/" ]; do
    if [ -f "$p/.claude/team.json" ]; then printf '%s' "$p"; return 0; fi
    p=$(dirname -- "$p")
  done
  return 0
}

# rel_path <root> <path> -> path relative to root ("" if outside root)
rel_path() {
  local root="$1" path="$2" dir base
  case "$path" in
    /*) : ;;
    *) path="$PWD/$path" ;;
  esac
  # Physical-resolve the parent dir (file itself may not exist yet).
  dir=$(dirname -- "$path"); base=$(basename -- "$path")
  while [ -n "$dir" ] && [ ! -d "$dir" ]; do base=$(basename -- "$dir")/"$base"; dir=$(dirname -- "$dir"); done
  dir=$(cd "$dir" 2>/dev/null && pwd -P) || { printf ''; return 0; }
  path="$dir/$base"
  case "$path" in
    "$root"/*) printf '%s' "${path#"$root"/}" ;;
    "$root")   printf '.' ;;
    *)         printf '' ;;
  esac
}

# ---------------------------------------------------------------------------
# Glob matching
# ---------------------------------------------------------------------------
# Bash [[ == ]] pattern matching against a STRING treats '*' as matching any
# characters INCLUDING '/', which is exactly the ** semantics we want. Two
# translations make team.json globs behave as documented:
#   - "**/X" also matches "X" at the root (zero directories)
#   - remaining "**" collapses to "*"
# glob_match <path> <pattern> -> exit 0 on match
glob_match() {
  local path="$1" pat="$2"
  pat=${pat//\*\*/\*}
  # shellcheck disable=SC2254
  case "$path" in
    $pat) return 0 ;;
  esac
  case "$2" in
    \*\*/*)
      local tail="${2#\*\*/}"
      tail=${tail//\*\*/\*}
      # shellcheck disable=SC2254
      case "$path" in
        $tail) return 0 ;;
      esac
      ;;
  esac
  return 1
}

# glob_match_any <path> <<< "one pattern per line"
glob_match_any() {
  local path="$1" pat
  while IFS= read -r pat; do
    [ -n "$pat" ] || continue
    glob_match "$path" "$pat" && return 0
  done
  return 1
}

# ---------------------------------------------------------------------------
# Path classification (first match wins): protected > test > exempt > source
# > default_class. Requires TEAM_CONFIG to be set (path to team.json).
# Always-protected paths are hardcoded so a weakened team.json cannot unlist
# them (config-protection's own backstop).
# ---------------------------------------------------------------------------
ALWAYS_PROTECTED='.claude/team.json
.claude/tdd/*
.claude/team/audit.log
.claude/settings.json
.claude/settings.local.json'

classify_path() {
  local rel="$1"
  if glob_match_any "$rel" <<<"$ALWAYS_PROTECTED"; then printf 'protected'; return 0; fi
  if json_get_list "$TEAM_CONFIG" .globs.protected | glob_match_any_stdin "$rel"; then printf 'protected'; return 0; fi
  if json_get_list "$TEAM_CONFIG" .globs.test      | glob_match_any_stdin "$rel"; then printf 'test'; return 0; fi
  if json_get_list "$TEAM_CONFIG" .globs.exempt    | glob_match_any_stdin "$rel"; then printf 'exempt'; return 0; fi
  if json_get_list "$TEAM_CONFIG" .globs.source    | glob_match_any_stdin "$rel"; then printf 'source'; return 0; fi
  json_get "$TEAM_CONFIG" .tdd.default_class "source"
}

# helper so classify_path can pipe lists in
glob_match_any_stdin() {
  local path="$1" pat matched=1
  while IFS= read -r pat; do
    [ -n "$pat" ] || continue
    if glob_match "$path" "$pat"; then matched=0; fi
  done
  return $matched
}

# ---------------------------------------------------------------------------
# Audit log — JSONL, gitignored, rotated at ~1MB. Every gate decision,
# bypass, and override lands here; the PR phase copies the session tail into
# committed artifacts so overrides are PR-visible.
# audit_log <event> <check_id> <decision> <path> <reason>
# ---------------------------------------------------------------------------
audit_log() {
  local event="$1" check="$2" decision="$3" path="$4" reason="$5"
  local log="$TEAM_ROOT/.claude/team/audit.log"
  mkdir -p "$(dirname "$log")" 2>/dev/null || return 0
  if [ -f "$log" ] && [ "$(wc -c <"$log" 2>/dev/null || echo 0)" -gt 1048576 ]; then
    mv -f "$log" "$log.1" 2>/dev/null || true
  fi
  printf '{"ts":"%s","session":"%s","event":"%s","check":"%s","decision":"%s","path":"%s","reason":"%s"}\n' \
    "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$(json_escape "${SESSION_ID:-}")" "$event" "$check" "$decision" \
    "$(json_escape "$path")" "$(json_escape "$reason")" >>"$log" 2>/dev/null || true
}

# ---------------------------------------------------------------------------
# Hook output emitters. Checks print via these; dispatch.sh routes them.
#   deny  -> full PreToolUse deny JSON on stdout (dispatcher forwards, exit 0)
#   warn  -> "WARN:<reason>" line (dispatcher aggregates into a systemMessage)
#   block -> "BLOCK:<reason>" line (Stop event; dispatcher exits 2 with reason)
# ---------------------------------------------------------------------------
emit_deny() {
  local check="$1" reason="$2"
  printf '{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"deny","permissionDecisionReason":"[%s] %s"}}\n' \
    "$check" "$(json_escape "$reason")"
}

emit_warn()  { printf 'WARN:%s\n' "$1"; }
emit_block() { printf 'BLOCK:%s\n' "$1"; }

# decide <check_id> <path> <reason>
# Honors MODE (block|warn) set by the dispatcher, audits either way.
decide() {
  local check="$1" path="$2" reason="$3"
  if [ "${MODE:-warn}" = "block" ]; then
    audit_log "${EVENT:-pre-edit}" "$check" "deny" "$path" "$reason"
    emit_deny "$check" "$reason — see /team:status and docs/tdd-gate.md"
  else
    audit_log "${EVENT:-pre-edit}" "$check" "warn" "$path" "$reason"
    emit_warn "[$check] $reason"
  fi
}

# ---------------------------------------------------------------------------
# Misc
# ---------------------------------------------------------------------------
now_iso()   { date -u +%Y-%m-%dT%H:%M:%SZ; }
now_epoch() { date -u +%s; }

# atomic_write <dest> — writes stdin to dest via tmp+mv (same filesystem).
atomic_write() {
  local dest="$1" tmp
  tmp="$(dirname "$dest")/.$(basename "$dest").tmp.$$"
  cat >"$tmp" && mv -f "$tmp" "$dest"
}

# append_line <file> <line> — O_APPEND single-write append (race-safe enough
# for counter logs: concurrent appends interleave whole lines on local FS).
append_line() {
  mkdir -p "$(dirname "$1")" 2>/dev/null || true
  printf '%s\n' "$2" >>"$1"
}

# sha256_of_file <file> — best-available content hash.
sha256_of_file() {
  if command -v sha256sum >/dev/null 2>&1; then sha256sum "$1" | cut -d' ' -f1
  elif command -v shasum >/dev/null 2>&1; then shasum -a 256 "$1" | cut -d' ' -f1
  else cksum "$1" | cut -d' ' -f1-2 | tr ' ' '-'
  fi
}

sha256_of_string() {
  if command -v sha256sum >/dev/null 2>&1; then printf '%s' "$1" | sha256sum | cut -d' ' -f1
  elif command -v shasum >/dev/null 2>&1; then printf '%s' "$1" | shasum -a 256 | cut -d' ' -f1
  else printf '%s' "$1" | cksum | cut -d' ' -f1-2 | tr ' ' '-'
  fi
}
