# Pipeline states and routing

The build flow is a state machine over `state.json.phase`. The main loop (you)
is the orchestrator: route on the DISK state, never on remembered context —
after any compaction or resume, re-read `state.json` and the current-phase
artifact before acting. Update `phase` when a phase completes, and mirror the
phases the hooks care about into `.claude/tdd/phase` via
`bash "$CLAUDE_PLUGIN_ROOT/scripts/tdd/state.sh" phase <name>`.

## Phases

| phase | who works | consumes → produces | done when |
|---|---|---|---|
| intake | main loop | request → request.md, state.json, branch | branch exists, triage decided |
| interview | product-manager (+codebase-scout) | request.md, answers → questions-r*.md, spec.md | frontier empty (≤3 rounds; 0 is valid) and spec.md validates against its schema |
| design | design-lead (conditional) | spec.md → design.md | every human-facing surface in the spec has a design section, or phase skipped with reason in state.json |
| plan | cto | spec.md, design.md, invariants.md, graph → plan.md | every slice has signature-strict seams; every A-n mapped to a slice |
| approval | main loop + user | spec.md, plan.md → approvals hashes in state.json | user picked Approve; hashes recorded |
| implement | test-engineer ⇄ implementer, per slice | plan.md slice → tests, src, evidence.md rows | every task in every slice has RED and GREEN evidence rows |
| qa | qa-verifier | everything → qa.md | qa.md verdict PASS |
| review | standards-reviewer ∥ spec-reviewer | diff, spec, design → review/*.md, summary.md | no blocking findings open |
| retro | main loop (retro skill) | observations, evidence events, reviews → lesson decision in state.json, optional lesson file | state.json.lesson.decision set |
| pr | main loop | everything → pushed branch + PR | PR exists; pipeline marker cleared |

## Phase hygiene (hooks depend on these)

- On entering **implement**: `state.sh phase implement` (freezes test files
  against the implementer), and `state.sh pipeline-on` was already set at
  intake (strict profile).
- On entering **qa** / **review** / **pr**: `state.sh phase qa|review|pr`
  (arms the delivery gate's block mode).
- On PR created or task aborted: `state.sh phase clear && state.sh
  pipeline-off`, and remove `.claude/team/active-task`.
- At intake: write the slug to `.claude/team/active-task`, `state.sh
  pipeline-on`, push the branch after the first commit.
- **Push after approval and after every slice commit** — remote sessions are
  ephemeral; unpushed slices die with the container.

## Slice loop (inside implement, per slice, in plan order)

1. test-engineer: failing test(s) at the slice's seams only → runs them
   (targeted) → RED rows in evidence.md. Meaningful RED = assertion-level; an
   import/resolution failure is transitional — implementer scaffolds the seam
   stubs, then test-engineer re-verifies assertion-red before handoff.
2. Main loop verifies `.claude/tdd/state.json` shows red (targeted/observed)
   before delegating implementation. Not red → back to test-engineer, not forward.
3. implementer: impact check (graph skill or grep callers) → minimal diff to
   green → runs targeted then full wrapper as appropriate → GREEN rows.
4. Bounded refactor under green (budget-enforced by the gate). Substantive
   refactors wait for review.
5. Narrative commit: `Slice N/M: <tracer goal> — evidence in evidence.md`. Push.

## Retry routing

| situation | route |
|---|---|
| implementer can't reach green after 2 attempts, claims test wrong | **cto adjudicates** (gets the run log path `.claude/tdd/last-run.log`, the test, the seam). Test wrong → test-engineer revises (RED-REVISED event, never silent). Plan wrong → cto amends plan.md `## Amendments` |
| amendment changes spec meaning or crosses slices | PAUSE — present to user, re-approve (updates hashes) |
| qa FAIL | missing tests → test-engineer (mini red/green); behavior gaps → implementer. Max 2 QA iterations, then pause to user with the gap list |
| review blocking finding | behavioral → red/green micro-cycle (test-engineer then implementer); non-behavioral → implementer under green. Re-run only the axis that raised it. Max 2 iterations, then pause with the named tension |
| any agent returns STATUS: BLOCKED | read its reason; route by this table, or pause to user if no row fits |
| any agent returns STATUS: NEEDS-DECISION | present the decision to the user with the agent's recommendation |

## Delegation contract (every Agent call)

Pass: artifact PATHS (absolute), the task slug, the slice/phase, and a
≤150-word state summary. Never paste whole artifacts into prompts — agents
read their own inputs. Require the trailer: `STATUS: DONE | BLOCKED |
NEEDS-DECISION` + ≤150-word summary. Parallel calls (the two reviewers) go in
ONE message with two Agent invocations; they must not see each other's output.

## Scaling down

- **build-lite** (small-but-real change): skip interview (or 1 batched
  round), spec written inline from the request by the main loop using the
  spec schema, single combined approval message, cto plans 1–2 slices,
  single-axis review (standards only). Same phases, same hooks, same evidence.
- A pure question is never a pipeline: answer it (codebase-scout for lookups),
  offer /team:build if the answer reveals work.
