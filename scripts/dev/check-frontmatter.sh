#!/usr/bin/env bash
# check-frontmatter.sh — every SKILL.md and agent .md opens with frontmatter
# that a STRICT YAML parser accepts.
#
# This exists because `claude plugin validate` runs continue-on-error in CI
# (command availability is version-dependent), so nothing hard-failed on a
# malformed header: skills/grilling shipped with an unquoted colon in its
# description ("...need human decisions: the interview phase..."), which YAML
# reads as a nested mapping. Claude Code's own loader is lenient enough to
# have taken it anyway, which is exactly what made it invisible — the file was
# broken for every strict consumer while looking fine in use.
#
# Checked per file: the fenced header exists, name and description are both
# present, and any value containing ": " or opening with a YAML indicator is
# quoted. No YAML library needed, so it runs anywhere bash does.
set -u
ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd -P)
FAIL=0

check_value() {
  local file=$1 key=$2 value=$3
  if [ -z "$value" ]; then
    echo "$file: '$key' is empty"
    FAIL=1
    return
  fi
  # Already quoted end to end? Nothing inside can confuse the parser.
  case "$value" in
    '"'*'"' | "'"*"'") return ;;
  esac
  case "$value" in
    *": "*)
      echo "$file: '$key' contains \": \" unquoted — YAML reads it as a nested key; wrap the value in double quotes"
      FAIL=1
      ;;
  esac
  case "$value" in
    [\[\{\&\*\!\|\>\%\@\`]*)
      echo "$file: '$key' opens with a YAML indicator character — wrap the value in double quotes"
      FAIL=1
      ;;
  esac
}

check_file() {
  local f=$1
  if [ "$(head -n 1 "$f")" != "---" ]; then
    echo "$f: does not open with a '---' frontmatter fence"
    FAIL=1
    return
  fi
  # The header is everything up to the second fence.
  local header
  header=$(awk 'NR==1 && $0=="---" {next} $0=="---" {exit} {print}' "$f")
  local key
  for key in name description; do
    if ! printf '%s\n' "$header" | grep -qE "^$key:[[:space:]]"; then
      echo "$f: frontmatter has no '$key'"
      FAIL=1
      continue
    fi
    local value
    value=$(printf '%s\n' "$header" | sed -n "s/^$key:[[:space:]]*//p" | head -n 1)
    check_value "$f" "$key" "$value"
  done
}

for f in "$ROOT"/skills/*/SKILL.md "$ROOT"/agents/*.md; do
  [ -f "$f" ] || continue
  check_file "$f"
done

if [ "$FAIL" -eq 0 ]; then
  echo "frontmatter ok: $(ls -d "$ROOT"/skills/*/ 2>/dev/null | wc -l | tr -d ' ') skills, $(ls "$ROOT"/agents/*.md 2>/dev/null | wc -l | tr -d ' ') agents"
fi
exit "$FAIL"
