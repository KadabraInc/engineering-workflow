#!/usr/bin/env bash
# init-project.sh — everything /team:setup executes. Idempotent.
#
#   init-project.sh                       dry run: print detection + proposed config
#   init-project.sh --apply               write everything (after the user approved)
#   init-project.sh --apply --stack node  override detection
#   init-project.sh --upgrade             refresh shim + gitignore block only
#
# The setup SKILL drives the human parts around this script: showing the
# proposed team.json for approval BEFORE --apply, offering the baseline run,
# and the optional code-review-graph install (pinned, CLI-only).
set -u

SELF_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)
PLUGIN_ROOT="${CLAUDE_PLUGIN_ROOT:-$(cd "$SELF_DIR/../.." && pwd -P)}"
TEMPLATES="$SELF_DIR/templates"

APPLY=0; UPGRADE=0; STACK=""; PROJECT="$PWD"
while [ $# -gt 0 ]; do
  case "$1" in
    --apply) APPLY=1; shift ;;
    --upgrade) UPGRADE=1; APPLY=1; shift ;;
    --stack) STACK="${2:-}"; shift 2 ;;
    --project) PROJECT="${2:-}"; shift 2 ;;
    *) echo "init-project: unknown arg $1" >&2; exit 1 ;;
  esac
done
cd "$PROJECT" || exit 1

# Refuse to run outside a git repo — branches and delivery accounting need one.
git rev-parse --git-dir >/dev/null 2>&1 || { echo "init-project: $PROJECT is not a git repository"; exit 1; }

[ -n "$STACK" ] || STACK=$(bash "$SELF_DIR/detect-stack.sh" "$PROJECT")
TEMPLATE="$TEMPLATES/team.$STACK.json"
[ -f "$TEMPLATE" ] || { echo "init-project: no template for stack '$STACK'"; exit 1; }

# --- resolve template placeholders (runner refinement) --------------------------
TEST_CMD=""; TARGETED_CMD=""
case "$STACK" in
  node|nextjs)
    if grep -qE '"vitest"' package.json 2>/dev/null; then
      TEST_CMD="npx vitest run"; TARGETED_CMD="npx vitest run {pattern}"
    elif grep -qE '"jest"' package.json 2>/dev/null; then
      TEST_CMD="npx jest"; TARGETED_CMD="npx jest {pattern}"
    else
      TEST_CMD="npm test --silent"; TARGETED_CMD=""
    fi
    ;;
  laravel)
    if [ -f vendor/bin/pest ] || grep -q '"pestphp/pest"' composer.json 2>/dev/null; then
      TEST_CMD="./vendor/bin/pest"; TARGETED_CMD="./vendor/bin/pest --filter {pattern}"
    else
      TEST_CMD="php artisan test"; TARGETED_CMD="php artisan test --filter {pattern}"
    fi
    ;;
esac

render_config() {
  sed -e "s|__TEST_CMD__|$TEST_CMD|" -e "s|__TARGETED_CMD__|$TARGETED_CMD|" "$TEMPLATE"
}

# Branch prefix: follow the repo's observed convention when one exists.
BRANCH_PREFIX="team/"
if git branch -a --format='%(refname:short)' 2>/dev/null | grep -qE '^(remotes/)?([^/]+/)?claude/'; then
  BRANCH_PREFIX="claude/team-"
fi

if [ "$APPLY" -eq 0 ]; then
  echo "detected stack: $STACK"
  [ -n "$TEST_CMD" ] && echo "test command:   $TEST_CMD"
  echo "branch prefix:  $BRANCH_PREFIX"
  echo "--- proposed .claude/team.json ---"
  render_config | sed "s|\"branch_prefix\": \"team/\"|\"branch_prefix\": \"$BRANCH_PREFIX\"|"
  echo "--- nothing written (dry run). Re-run with --apply after user approval ---"
  exit 0
fi

mkdir -p .claude/tdd/counters .claude/team/artifacts .claude/knowledge/lessons .claude/knowledge/promotions

# --- team.json (never overwrite an existing one except in a fresh apply) ---------
if [ -f .claude/team.json ] && [ "$UPGRADE" -eq 1 ]; then
  echo "keeping existing .claude/team.json (upgrade mode)"
elif [ -f .claude/team.json ]; then
  echo "init-project: .claude/team.json exists — use --upgrade to refresh shim/gitignore without touching it" >&2
  exit 1
else
  render_config | sed "s|\"branch_prefix\": \"team/\"|\"branch_prefix\": \"$BRANCH_PREFIX\"|" >.claude/team.json
  echo "wrote .claude/team.json (stack: $STACK)"
fi

# --- knowledge seeds (only if missing) ---------------------------------------------
[ -f .claude/knowledge/README.md ]     || cp "$TEMPLATES/knowledge-README.md" .claude/knowledge/README.md
[ -f .claude/knowledge/invariants.md ] || cp "$TEMPLATES/invariants-seed.md" .claude/knowledge/invariants.md

# --- test wrapper shim ------------------------------------------------------------------
cp "$PLUGIN_ROOT/scripts/tdd/run-tests.sh" .claude/tdd/run-tests
chmod +x .claude/tdd/run-tests
echo "installed .claude/tdd/run-tests (shim $(grep -m1 '^# team-shim v' .claude/tdd/run-tests | grep -oE '[0-9.]+'))"

# --- seed TDD state (bootstrap: warn-only until the first wrapper run) --------------------
if [ ! -f .claude/tdd/state.json ] || [ "$UPGRADE" -eq 0 ]; then
  if [ ! -f .claude/tdd/state.json ]; then
    cat >.claude/tdd/state.json <<EOF
{
  "schema_version": 1,
  "status": "unknown",
  "verified": false,
  "scope": "none",
  "command": "",
  "exit_code": -1,
  "started_at": "",
  "finished_at": "",
  "failing_count": -1,
  "tests_fingerprint": "",
  "baseline": { "failing_count": -1, "captured_at": "" },
  "ever_green": false,
  "bootstrap": true
}
EOF
    echo "seeded TDD state (bootstrap mode)"
  fi
fi

# --- managed .gitignore block ----------------------------------------------------------------
touch .gitignore
if grep -q '^# team:begin' .gitignore; then
  awk '/^# team:begin/{skip=1} !skip{print} /^# team:end/{skip=0}' .gitignore >.gitignore.tmp.$$ &&
    mv .gitignore.tmp.$$ .gitignore
fi
cat "$TEMPLATES/gitignore-snippet" >>.gitignore
echo "managed .gitignore block refreshed"

echo ""
echo "Setup complete. Next steps:"
echo "  1. Review and commit .claude/team.json + .claude/knowledge/ + .claude/tdd/run-tests"
if [ -z "$TEST_CMD" ] && [ "$STACK" = "generic" ]; then
  echo "  2. Fill test.command in .claude/team.json — until then the TDD gate is UNARMED"
else
  echo "  2. Arm the gate with a baseline run: bash .claude/tdd/run-tests --baseline"
fi
echo "  3. Optional code intelligence: pip install 'code-review-graph==2.3.7' && code-review-graph build"
echo "     (CLI-only; do NOT run its 'install --platform' — it mutates global MCP config)"
exit 0
