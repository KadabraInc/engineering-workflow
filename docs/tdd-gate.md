# The TDD gate — normative specification

This document is NORMATIVE: when scripts and this file disagree, one of them
has a bug — fix whichever is wrong, in the same change.

## Threat model — what the gate proves, honestly

The gate deterministically proves **ordering and freshness**:

- a verified failing test run preceded source edits (pre-edit gate), and
- a verified full-suite pass (or, brownfield, a full run with no new failures
  beyond the recorded baseline) preceded delivery (Stop gate), and
- every override or bypass left an audit line, and the PR step copies the
  audit tail into committed artifacts — overrides are PR-visible.

It **cannot prove the red was meaningful**. A junk test, a weakened
assertion, or an edit-then-revert dance can satisfy ordering. Those are
caught by the layers above: role separation (the implementer cannot edit
tests during implement), QA's run-log cross-check (`verify-evidence.sh`),
the diff-must-touch-tests delivery rule, two-axis review, and finally the
human PR gate — the only genuinely hard gate in the system.

Enforcement against a filesystem-sharing agent is **cost + visibility, not
prevention**: every protected file is one bash call away for a determined
evader. The design makes compliance cheaper than evasion (a targeted red
costs seconds) and makes evasion leave committed evidence.

## State — `.claude/tdd/state.json`

Written only by scripts (the wrapper `run-tests` and the PostToolUse
observer). Schema version 1:

| field | meaning |
|---|---|
| `status` | `red` \| `green` \| `error` \| `unknown` |
| `verified` | a machine exit code produced this status |
| `scope` | `full` \| `targeted` \| `observed` \| `none` |
| `failing_count` | parsed failure count, `-1` unknown |
| `baseline.failing_count` | brownfield baseline (set by `--baseline`), `-1` = none |
| `ever_green` | sticky: the project has had a full green at least once |
| `tests_fingerprint` | `stat:<sha256>` over sorted `path:size:mtime` of test-glob files |
| `bootstrap` | seeded by setup; first wrapper run clears it |

Unrecognized `schema_version` reads fail-closed: `status=unknown`,
`bootstrap=false`.

**Status semantics** (observer and wrapper agree): `green` = exit 0 (wrapper
full runs only — observed successes NEVER write green). `red` = nonzero exit
AND an anchored fail-pattern/count match. `error` = exit 126/127,
command-not-found, or nonzero exit with no recognizable test failure — a
broken runner is never red and never green. The asymmetry is deliberate: a
false red slightly weakens the gate; a false green would break it.

## Pre-edit gate (PreToolUse on Write/Edit/MultiEdit/NotebookEdit)

Classification, first match wins: always-protected → team.json `protected`
globs → `test` → `exempt` → `source` → `tdd.default_class` (preset default:
`source`, fail-closed).

| class | decision |
|---|---|
| protected | denied by config-protection (fix code, not configs) |
| test | allowed — writing tests IS the red step. Exception: denied during the `implement` phase (test files are frozen; revisions route through the test-engineer via cto adjudication) |
| exempt | allowed |
| source | gated by state, below |

| state | decision on source |
|---|---|
| bootstrap | warn + allow (arms on first wrapper run) |
| unknown / fingerprint mismatch / unrecognized schema | deny — run a targeted failing test or the wrapper |
| error | deny — fix the test command first |
| red (targeted/observed, fresh) | **allow** |
| red (full) at brownfield baseline | deny — ambient failures don't arm the gate; write a failing test for THIS change |
| red beyond baseline | allow |
| red older than `staleness_minutes` (default 240) | deny — re-run to re-arm |
| green within `green_edit_budget` (default 5; `refactor_budget` 25 with a declaration) | allow — refactoring under green is legitimate |
| green, budget exhausted | deny — re-verify or declare a refactor |

Escape hatches, all audited: `TEAM_TDD_GATE=off` (env), `.claude/tdd/allow`
(HUMAN-created one-shot override file: `{"paths":[...],"expires_at":...,
"reason":...}` — the bash-write-guard denies the model creating it),
`hooks.ambient_profile`/`pipeline_profile` in team.json, `tdd.enabled:false`
(team.json is protected, so human-only).

## Profiles and scoping

`minimal` (gate off, observers on) / `standard` (gate warns + audits) /
`strict` (gate denies). Pipeline sessions — `/team:build|fix|quick` write
`.claude/tdd/pipeline` — run `hooks.pipeline_profile` (default **strict**);
ambient sessions run `hooks.ambient_profile` (default **standard**), so the
gate never harasses ordinary work in a team-enabled repo. Hard TDD is hard
where it was promised: inside the pipeline. `TEAM_HOOK_PROFILE` env overrides
for one session.

## Delivery gate (Stop)

Stop fires at **every turn end**, so the gate blocks only in terminal
pipeline phases (`.claude/tdd/phase` ∈ qa/review/pr); elsewhere it warns at
most. Accounting is **git truth**: changed files = `git diff --name-only
<session-start SHA>` + untracked − files dirty at session start — shell
writes count the same as tool edits. Below `delivery.min_source_files`
(default 3) changed source files, nothing fires.

Blocking facts (each names its fix): no verified full pass (or brownfield
no-new-failures) · source newer than the verified run · zero test changes
without a `.claude/tdd/refactor` declaration · source importing test paths ·
spec/plan frozen-region hash mismatch after approval · missing retro decision
at PR phase. `stop_hook_active` short-circuits (anti-loop). Heuristics
(TODO/FIXME in diff) warn and never block.

## Fingerprint

`stat:` + sha256 over `LC_ALL=C`-sorted `path:size:mtime` lines of test-glob
files. Implemented identically in `scripts/tdd/state.sh` (gate side) and the
shim (wrapper side); byte-identical output is a tested invariant. Stat-based
is a deliberate trade — cheap everywhere and implementable in the
dependency-free shim. Residual: a same-size, restored-mtime test edit
(`touch -r`) preserves a red fingerprint; the run-log cross-check and PR
review cover that corner.

## Failure modes, by design

- **No JSON runtime** (jq/node/python3 all absent): everything fails OPEN
  with a loud session-start banner. A bricked editor is worse than a soft
  gate.
- **Hook crash / timeout**: that check is skipped (audited `check-error`),
  the rest run.
- **Version skew** (shim vs plugin): session banner + `/team:setup --upgrade`;
  unknown state schema reads as `unknown` (fail-closed), never green.
- **Slow suites**: `run-tests --background` (PID file, state written at
  completion). Flakes: opt-in `delivery.retry_failed: 1`, retries recorded.

## Known residual gaps (accepted, documented)

Interpreter one-liners and heredocs evade the bash-write-guard (git-truth
delivery accounting still counts them) · edit-test-then-revert evades the
test-diff rule (run-log cross-check + review) · Rust inline `#[cfg(test)]`
tests classify as source (template notes the workaround) · monorepos get one
team.json at the nearest ancestor of each edited file · Windows is
unsupported (bash hooks).
