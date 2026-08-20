# Troubleshooting

**First move, always**: `/team:status` — it prints the gate state, the active
task, recent audit decisions, and runs a hook self-test that says whether the
gate is actually armed.

## "The gate keeps denying my edit"

Read the denial — every reason maps to one action (the tdd skill's
`gate-errors.md` is the full table). The two cheap moves solve most of it:
`bash .claude/tdd/run-tests --targeted <pattern>` (seconds, arms red) and
`bash .claude/tdd/run-tests` (full suite, earns green).

## "The gate denies everything after a pull/rebase"

Test-file mtimes changed → fingerprint mismatch → state reads unknown. One
targeted run re-arms. This is by design (tests changed underneath the
recorded state).

## "The suite was already failing before the plugin arrived"

Run `bash .claude/tdd/run-tests --baseline` once: brownfield mode. Delivery
then requires *no new failures beyond the baseline*, and ambient red stops
counting as an armed gate. The first real full green retires the mode
permanently.

## "Stop keeps getting blocked"

Only terminal pipeline phases block. The message names the missing fact:
usually a wrapper run (slow suite? `--background`), a missing test change
(declare the refactor if genuinely behavior-free), or the retro decision.

## "The gate is silently doing nothing"

`/team:status` self-test. Causes in order of likelihood: no
`.claude/team.json` (run /team:setup) · `test.command` empty (UNARMED — the
banner says so) · no JSON runtime on the machine (banner at session start;
install jq) · `TEAM_HOOKS=off` / `TEAM_TDD_GATE=off` left exported ·
`hooks.enabled: false` in team.json.

## "run-tests says error, not red"

The RUNNER is broken (exit 126/127, command not found, or unrecognizable
output) — read `.claude/tdd/last-run.log`. Fix `test.command` (human edit —
the file is protected) or re-run `/team:setup --upgrade`. A broken command
never counts as red or green on purpose.

## "Wrapper version warning at session start"

The committed shim lags the plugin: `/team:setup --upgrade` refreshes it
(and the gitignore block) without touching team.json.

## "Graph calls stopped happening"

Circuit breaker: `wc -l .claude/team/graph-failures` ≥3 opens it. Fix the
underlying failure (version? venv?), then `rm .claude/team/graph-failures`.

## "A teammate without the plugin broke the flow"

They can't, much: the shim (`bash .claude/tdd/run-tests`) is self-contained
and committed, so tests-with-state work for them; hooks simply don't run for
them. Their sessions won't write evidence or respect phases — pipeline tasks
should be driven from a plugin-equipped session.

## Escape hatches (audited, PR-visible)

One-shot per-path: create `.claude/tdd/allow` (human-only) —
`{"paths":["src/hotfix.ts"],"expires_at":"<iso>","reason":"<why>"}`.
Session-wide: `TEAM_TDD_GATE=off claude`. Project-wide: `tdd.enabled: false`
in team.json. Every use lands in the audit log, and the PR step surfaces the
audit tail — turning them off quietly isn't a thing.
