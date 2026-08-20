---
name: setup
description: Initialize the current project for the team plugin — detect the stack, render and approve the per-project config, install the test wrapper, seed the knowledge base, arm the TDD gate, optionally install code-review-graph.
disable-model-invocation: true
---

# /team:setup — initialize a project

Everything mechanical lives in one idempotent script; your job is the human
parts: showing, asking, explaining.

1. **Dry run**:
   `bash "$CLAUDE_PLUGIN_ROOT/scripts/setup/init-project.sh"` — show the user
   the detected stack and the full proposed `.claude/team.json`. If detection
   looks wrong, re-run with `--stack <id>` (templates: laravel, symfony, php,
   node, nextjs, python, go, rust, generic). For a generic/unknown stack, ask
   the user for the test commands and edit the rendered config accordingly
   BEFORE applying.
2. **Ask for approval** of the config (AskUserQuestion). Only then:
   `... init-project.sh --apply` (add `--stack` if overridden).
   If `$ARGUMENTS` contains `--upgrade`, run `--upgrade` instead — it
   refreshes the shim and gitignore block without touching team.json.
3. **Arm the gate — baseline run** (ask first; it runs the full suite once):
   `bash .claude/tdd/run-tests --baseline`.
   - Green → gate armed clean. Red → brownfield mode: explain that the gate
     now measures *no new failures beyond <N>*, and that the first full green
     retires the mode. Error → the test command is wrong; fix team.json with
     the user before continuing.
   - No test command (generic) → say plainly: **the TDD gate is UNARMED for
     this project** and will stay so until test.command is configured.
4. **Optional code intelligence** (ask; skip cleanly on any failure):
   `pip install 'code-review-graph==2.3.7'` (pipx if available), then
   `code-review-graph build --repo "$(pwd)"`. CLI-only — **never run its
   `install --platform` command**; it mutates user-global MCP config the
   plugin cannot undo. Verify `.code-review-graph/` is gitignored
   (`git check-ignore .code-review-graph` must succeed).
5. **Commit** `.claude/team.json`, `.claude/knowledge/`,
   `.claude/tdd/run-tests`, and `.gitignore` with a message explaining what
   the team plugin adds. Then a one-paragraph runbook to the user: what's
   committed vs ignored, how the gate behaves ambient vs pipeline, and that
   /team:build, /team:fix, /team:quick are ready.
