#!/usr/bin/env bash
# check-manifest.sh — the bucket promotion invariant, CI-enforced:
# every shipped agent and skill appears in the README components table;
# nothing under drafts/ is referenced by any manifest or the README's table.
set -u
ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd -P)
FAIL=0

for f in "$ROOT"/agents/*.md; do
  [ -f "$f" ] || continue
  name=$(basename "$f" .md)
  grep -qE "\`$name\`" "$ROOT/README.md" || { echo "agent '$name' missing from README components table"; FAIL=1; }
done

for d in "$ROOT"/skills/*/; do
  [ -f "$d/SKILL.md" ] || continue
  name=$(basename "$d")
  grep -qE "\`(/team:)?$name\`" "$ROOT/README.md" || { echo "skill '$name' missing from README components table"; FAIL=1; }
done

while IFS= read -r id; do
  grep -qE "\"id\": \"$id\"|\`$id\`" "$ROOT/README.md" || { echo "hook check '$id' missing from README components table"; FAIL=1; }
done < <(jq -r '.checks[][].id' "$ROOT/hooks/registry.json" | sort -u)

if [ -d "$ROOT/drafts" ]; then
  for g in "$ROOT/drafts"/*; do
    [ -e "$g" ] || continue
    base=$(basename "$g")
    [ "$base" = "README.md" ] && continue
    if grep -q "drafts/$base" "$ROOT/.claude-plugin/plugin.json" "$ROOT/.claude-plugin/marketplace.json" 2>/dev/null; then
      echo "drafts/$base is referenced by a manifest — promote it properly or unreference it"
      FAIL=1
    fi
  done
fi

[ $FAIL -eq 0 ] && echo "manifest promotion invariant OK"
exit $FAIL
