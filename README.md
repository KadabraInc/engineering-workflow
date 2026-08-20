# team — a virtual engineering team for Claude Code

A Claude Code plugin that staffs your repo with a product manager, CTO,
design lead, test engineer, implementer, QA, and two reviewers — planning
with you at approval gates, then executing autonomously under a **hard,
hook-enforced TDD gate**, in **any stack** (Laravel, Symfony, Node,
TypeScript, Next.js, Python, Go, Rust, …), while committing what it learns
back into your project as *invariants with the incidents that bought them*.

```
request → interview → spec → design → plan → ⏸ YOUR APPROVAL
        → per-slice: failing test (RED) → implement (GREEN) → refactor
        → QA (evidence machine-checked) → two-axis review (parallel, isolated)
        → retro (lesson or no-lesson, explicitly) → PR (never auto-merged)
```

Hard rules are pure functions: the TDD gate, the delivery gate, evidence
verification, and the knowledge injector are deterministic bash — the LLM is
for judgment and prose only.

## Install

```
/plugin marketplace add KadabraInc/engineering-workflow
/plugin install team@engineering-workflow
```

Private repo? Read [docs/distribution.md](docs/distribution.md) first — two
env vars save you real pain. Then, per project:

```
/team:setup     # detect stack → you approve the config → gate armed
```

## Quickstart runbook

1. `/team:setup` — detects your stack (nine presets), renders
   `.claude/team.json`, asks your approval, installs the committed test
   wrapper (`.claude/tdd/run-tests` — works for teammates and CI without the
   plugin), seeds `.claude/knowledge/`, and offers a baseline suite run.
   Failing legacy suite? That's **brownfield mode**: the gate measures *no
   new failures*, and retires itself at your first full green.
2. `/team:build add a weekly email digest of new signups` — the
   product-manager interviews you (numbered questions, each with a
   recommended answer; facts it looks up itself), the design-lead covers
   human-facing surfaces, the cto writes a sliced plan with
   signature-strict test seams, and everything **pauses for your approval**.
   After that it runs alone: red → green per slice with machine-checked
   evidence, QA, parallel standards+spec reviews, a retro, and a PR whose
   body carries the acceptance criteria, the evidence trail, both reviews
   verbatim, and any gate overrides. Small-but-real changes take the
   build-lite lane automatically.
3. `/team:fix the digest double-sends on retry` — reproduction-as-failing-test
   replaces the spec; one lightweight approval; single-axis review; a lesson
   decision is mandatory (bugs are where invariants get bought).
4. `/team:quick fix the typo in the settings page` — no ceremony, but the
   TDD gate still applies to behavior changes, and the moment the change
   outgrows its eligibility it upgrades to build-lite. `/team:status` any
   time to see where things stand.

## The TDD gate in 60 seconds

**Red is cheap, green is expensive.** Any observed failing test run arms the
gate in seconds (`bash .claude/tdd/run-tests --targeted <pattern>`); only the
wrapper running your full suite writes green. Writing tests is always
allowed; source edits need red (or budgeted refactoring under green); a
broken test command is `error`, never red or green. Enforcement is scoped:
**strict inside `/team:*` pipelines, warn-and-audit in ordinary sessions** —
the gate never harasses a Tuesday-afternoon tweak. Every escape hatch exists
and every use is audited and surfaced in the PR. What the gate can and cannot
prove is stated honestly in [docs/tdd-gate.md](docs/tdd-gate.md) (normative).

## Components

| type | name | one line |
|---|---|---|
| agent | `cto` | opus. Technical plans, signature-strict seams, slices, contracts, dispute adjudication |
| agent | `product-manager` | sonnet. Grilling interviews; spec with testable R-n, acceptance A-n, open questions OQ-n |
| agent | `design-lead` | sonnet. Human-facing surfaces only: states, layout, exact copy (Blade/JSX/HTML/email/CLI) |
| agent | `test-engineer` | sonnet. Failing tests at pre-agreed seams; assertion-level RED; never touches src |
| agent | `implementer` | sonnet. Minimal diff to green; scaffolds seam stubs; never edits tests |
| agent | `qa-verifier` | haiku. Mechanical: wrapper run, evidence cross-check, orphan diff, hotspots, acceptance map |
| agent | `standards-reviewer` | opus. Correctness/security axis with anti-noise gates; zero findings is a valid review |
| agent | `spec-reviewer` | sonnet. Spec-fidelity axis; parallel and isolated from standards |
| agent | `codebase-scout` | haiku. One factual lookup, ≤150 words, file:line cited |
| skill | `/team:setup` | initialize a project (config approval, wrapper, knowledge seeds, baseline) |
| skill | `/team:build` | the full pipeline (and its build-lite lane) |
| skill | `/team:fix` | bug flow — repro-as-red |
| skill | `/team:quick` | guarded escape hatch; gate still applies |
| skill | `/team:status` | state, audit tail, hook self-test |
| skill | `/team:retro` | lessons, ledger hygiene (`--audit`), artifact pruning (`--prune`), promotions |
| skill | `/team:promote` | (run in this repo) fold ≥2-project lessons into the plugin |
| skill | `grilling` | interview primitive: question frontiers with recommended answers |
| skill | `tdd` | the red-green contract, anti-patterns, gate-error playbook |
| skill | `graph` | code-review-graph wrapper with mandatory Grep/Glob fallbacks |
| hook check | `tdd-gate` | red-before-source, budgeted green, brownfield-aware (pre-edit) |
| hook check | `config-protection` | gate-defining files are not model-editable (pre-edit) |
| hook check | `bash-write-guard` | shell writes into gated paths get flagged (pre-bash) |
| hook check | `test-run-observer` | derives red from real runs; never green (post-bash) |
| hook check | `edit-counter` | feeds the green refactor budget (post-edit) |
| hook check | `graph-update` | async graph refresh, circuit-broken (post-edit) |
| hook check | `session-context` | git baseline + sanitized knowledge injection + status banner (session-start) |
| hook check | `delivery-gate` | git-truth completion facts; blocks only in terminal phases (stop) |

**Surface budget** (enforced by review, checked by CI): ≤10 agents, ≤10
skills. Adding one means retiring or folding one — a 68-agent plugin is
sediment, not capability.

## Repo tree

```
.claude-plugin/          plugin.json + marketplace.json (this repo is both)
agents/                  the nine roles
skills/                  entry skills + discipline skills (+ references/ contracts)
hooks/                   hooks.json (6 registrations) + registry.json (checks × profiles)
scripts/hooks/           dispatch.sh + checks/ (all deterministic bash)
scripts/tdd/             run-tests.sh (the wrapper/shim) + state.sh
scripts/setup/           detect-stack.sh + init-project.sh + templates/ (9 stack presets)
scripts/dev/             sync-version, check-manifest, simulate-hook, verify-evidence
tests/                   bats suite (the machinery is itself built test-first)
docs/                    architecture, tdd-gate (NORMATIVE), knowledge, configuration,
                         distribution, troubleshooting
drafts/                  unshipped staging — never referenced by manifests
```

## What lands in YOUR project

Committed: `.claude/team.json` (config, protected), `.claude/tdd/run-tests`
(self-contained wrapper), `.claude/knowledge/` (invariants + lessons),
`.claude/team/artifacts/<task>/` (specs, plans, evidence — the audit trail;
prune merged ones with `/team:retro --prune`). Gitignored: TDD state,
counters, audit log, session markers, `.code-review-graph/`.

## Development (this repo)

`npm i -g bats && bats tests/` (100+ tests) · `shellcheck scripts/**/*.sh` ·
`bash scripts/dev/simulate-hook.sh pre-edit --file src/x.ts --project <dir>`
to poke the dispatcher · versioning via `scripts/dev/sync-version.sh` (CI
enforces sync + the manifest promotion invariant).

## Known limitations

- **Enforcement is cost + visibility, not prevention** — a filesystem-sharing
  agent can defeat any local gate; this one makes compliance cheaper than
  evasion and makes evasion land in the PR ([docs/tdd-gate.md](docs/tdd-gate.md)).
- No tests / no test command → the gate is **UNARMED** and says so at every
  session start (WordPress-style projects: this is you until you configure a
  runner).
- Rust inline `#[cfg(test)]` tests classify as source (workaround in the
  preset); Windows unsupported (bash hooks); one team.json per (nested)
  project root in monorepos.
- Plugin updates don't propagate on their own — see
  [docs/distribution.md](docs/distribution.md).
- `code-review-graph` is optional, pinned, CLI-only, and circuit-broken;
  everything works without it.

MIT · [CHANGELOG](CHANGELOG.md)
