#!/usr/bin/env bash
# bash-write-guard.sh — PreToolUse check on Bash.
#
# Early friction, not enforcement: flags shell commands whose literal path
# tokens write into protected or gated source paths (redirects, tee, sed -i,
# mv/cp/touch/dd targets). A determined evader has endless routes around a
# tokenizer (python -c, heredocs, cd && relative writes) — which is why
# delivery accounting uses git-diff truth and every override lands in the
# audit trail. Protected targets deny in standard+strict; source targets
# follow the TDD gate's current answer for that path.
set -u
. "$PLUGIN_ROOT/scripts/lib/json.sh"
. "$PLUGIN_ROOT/scripts/lib/common.sh"

CHECK="bash-write-guard"
CMD=$(json_get "$PAYLOAD_FILE" .tool_input.command "")
[ -n "$CMD" ] || exit 0

# Allowlisted prefixes: the wrapper, git plumbing, and the graph CLI.
case "$CMD" in
  "bash .claude/tdd/run-tests"*|"bash \"$TEAM_ROOT/.claude/tdd/run-tests\""*|git\ *|code-review-graph\ *) exit 0 ;;
esac

# Collect candidate write-target tokens: words after redirects and after the
# classic in-place/copy writers. Conservative on purpose — only literal paths.
targets=""
# redirects: > >> >| (word after the operator)
while IFS= read -r t; do targets="$targets $t"; done < <(
  printf '%s' "$CMD" | grep -oE '[>]{1,2}[|]?[[:space:]]*[^[:space:];|&<>]+' | sed -E 's/^[>|]+[[:space:]]*//'
)
# tee [-a] TARGET
while IFS= read -r t; do targets="$targets $t"; done < <(
  printf '%s' "$CMD" | grep -oE 'tee[[:space:]]+(-a[[:space:]]+)?[^[:space:];|&<>]+' | awk '{print $NF}'
)
# sed -i FILE (last arg heuristic), perl -i, and explicit writers
while IFS= read -r t; do targets="$targets $t"; done < <(
  printf '%s' "$CMD" | grep -oE '(sed|perl)[[:space:]]+-[a-zA-Z]*i[a-zA-Z]*[[:space:]]+[^;|&]*' | awk '{print $NF}'
)
# mv/cp/touch/truncate/dd of= — take trailing path args
while IFS= read -r t; do targets="$targets $t"; done < <(
  printf '%s' "$CMD" | grep -oE '(mv|cp|touch|truncate)[[:space:]]+[^;|&]*' | tr ' ' '\n' | tail -n +2
)
while IFS= read -r t; do targets="$targets $t"; done < <(
  printf '%s' "$CMD" | grep -oE 'of=[^[:space:];|&]+' | sed 's/^of=//'
)

for t in $targets; do
  # strip quotes
  t=${t%\"}; t=${t#\"}; t=${t%\'}; t=${t#\'}
  [ -n "$t" ] || continue
  case "$t" in -*) continue ;; esac
  REL=$(rel_path "$TEAM_ROOT" "$t")
  [ -n "$REL" ] || continue

  # The refactor declaration is deliberately model-writable (audited, and the
  # PR step surfaces it verbatim); the allow file is human-only.
  [ "$REL" = ".claude/tdd/refactor" ] && continue
  if [ "$REL" = ".claude/tdd/allow" ]; then
    decide "$CHECK" "$REL" "The override file .claude/tdd/allow is a HUMAN escape hatch — creating it yourself defeats the gate. Ask the user to create it, or satisfy the gate (targeted failing test, seconds)"
    exit 0
  fi

  CLASS=$(classify_path "$REL")
  case "$CLASS" in
    protected)
      decide "$CHECK" "$REL" "Shell write into a protected file. Fix the code instead of the config; humans can change protected files directly"
      exit 0
      ;;
    source)
      decide "$CHECK" "$REL" "Shell write into gated source ($REL) — use the Edit/Write tools so the TDD gate can evaluate it (shell writes still count at delivery via git diff)"
      exit 0
      ;;
  esac
done
exit 0
