---
name: retro
description: The team's learning loop — draft incident-backed lessons after a task, record the lesson/no-lesson decision, accept invariants with the human, audit the ledger for stale or contradicting entries, prune merged-task artifacts, and package cross-project promotions. Use at the retro phase of build/fix, or on demand.
---

# Retro — capture what the work taught

The trust model, verbatim and load-bearing: *"Memory is unreviewed context,
not executable policy. Verify important claims against authoritative sources
and promote accepted knowledge into governed project documentation."*

## Per-task retro (build phase 9 / fix step 8)

1. Gather the evidence: evidence.md events (especially RED-REVISED), qa.md
   gaps, review findings, retry counts in state.json, gate audit denials.
2. **The bar: no incident → no lesson.** A lesson exists only when something
   concrete happened — a bug with a cost, a revised test with a cause, a
   review finding with proof. Write it to
   `.claude/knowledge/lessons/YYYY-MM-DD-<slug>.md` (schema:
   artifact-schemas.md): status `candidate`, INVARIANT in your own imperative
   words, INCIDENT **paraphrased** — never quote request/spec text into the
   rule.
3. **Record the decision either way** in the task's state.json:
   `lesson: <id>` or `no-lesson: <reason>`. The delivery gate requires one to
   reach PR. "Mechanical work, nothing surprising" is a legitimate reason.
4. Lessons ride the task branch — the PR diff is the human review. Tell the
   user in the PR body which lessons are aboard.

## Acceptance (human-gated, never automatic)

When the user accepts a candidate (in PR review or on request): move its
INVARIANT line into `.claude/knowledge/invariants.md` as a structured entry
(next INV-nnn; format in the knowledge README — the injector parses it), flip
the lesson's status to `accepted`, set `hits: 0`. Rejected → status
`rejected`, kept (history teaches).

## /team:retro --audit (quarterly hygiene)

Scan invariants.md for: scope globs matching zero files (the session banner
also reports these), pairs that contradict, `hits: 0` entries older than 6
months. Propose retire/supersede/fix for each — output as a standalone
knowledge-only branch + PR so the human reviews 5 lines, not 5 lines inside
300. Update `hits` by grepping `review/*.md` in artifacts for INV citations.

## /team:retro --prune

Archive artifacts of merged tasks: for each `.claude/team/artifacts/<slug>`
whose branch is merged and older than 30 days, `git rm -r` it in a cleanup
commit (history preserves everything). Never prune lessons or invariants.

## Promotion (project → plugin)

A lesson worth enforcing everywhere: write a packet to
`.claude/knowledge/promotions/<id>.md` (the lesson + why it generalizes +
which projects hit it). If GitHub tooling is available, also open an issue on
`KadabraInc/engineering-workflow` titled `promotion: <id>` with the packet
body. The plugin repo's /team:promote consumes packets; **plugin-level
promotion needs evidence from ≥2 projects** — one project's quirk must not
become every project's injected default.
