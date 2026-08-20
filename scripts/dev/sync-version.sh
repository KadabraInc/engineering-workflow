#!/usr/bin/env bash
# sync-version.sh --check | --write <version>
# One version, four places: plugin.json, marketplace.json metadata, the
# CHANGELOG's top entry, and the shim header in run-tests.sh (session-context
# compares shim vs plugin at runtime, so they must ship equal).
set -u
ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd -P)

pv() { jq -r .version "$ROOT/.claude-plugin/plugin.json"; }
mv_() { jq -r .metadata.version "$ROOT/.claude-plugin/marketplace.json"; }
cv() { grep -m1 -oE '^## \[?[0-9]+\.[0-9]+\.[0-9]+' "$ROOT/CHANGELOG.md" 2>/dev/null | grep -oE '[0-9]+\.[0-9]+\.[0-9]+'; }
sv() { grep -m1 '^# team-shim v' "$ROOT/scripts/tdd/run-tests.sh" | grep -oE '[0-9]+\.[0-9]+\.[0-9]+'; }

case "${1:---check}" in
  --check)
    P=$(pv); M=$(mv_); C=$(cv); S=$(sv)
    if [ "$P" = "$M" ] && [ "$P" = "$C" ] && [ "$P" = "$S" ]; then
      echo "version sync OK: $P"
      exit 0
    fi
    echo "version mismatch: plugin.json=$P marketplace.json=$M CHANGELOG=$C shim=$S" >&2
    exit 1
    ;;
  --write)
    V="${2:?usage: sync-version.sh --write <version>}"
    tmp=$(mktemp)
    jq --arg v "$V" '.version = $v' "$ROOT/.claude-plugin/plugin.json" >"$tmp" && mv "$tmp" "$ROOT/.claude-plugin/plugin.json"
    tmp=$(mktemp)
    jq --arg v "$V" '.metadata.version = $v' "$ROOT/.claude-plugin/marketplace.json" >"$tmp" && mv "$tmp" "$ROOT/.claude-plugin/marketplace.json"
    sed -i.bak -E "s/^# team-shim v[0-9.]+/# team-shim v$V/; s/^SHIM_VERSION=\"[0-9.]+\"/SHIM_VERSION=\"$V\"/" "$ROOT/scripts/tdd/run-tests.sh" && rm -f "$ROOT/scripts/tdd/run-tests.sh.bak"
    echo "wrote $V to plugin.json, marketplace.json, shim. Add the CHANGELOG entry yourself — it needs words, not just a number."
    ;;
  *) echo "usage: sync-version.sh --check | --write <version>" >&2; exit 1 ;;
esac
