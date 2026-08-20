---
name: tdd
description: The team's red-green-refactor contract under the hard gate — what a good test is, where tests attach (pre-agreed seams), the slice loop, evidence rules, and what every gate denial means. Consult when writing or judging tests, when the TDD gate denies an edit, or when running the implement phase.
---

# TDD under the gate

The gate (hooks) enforces *ordering* mechanically: verified red before source
edits, verified green before delivery. This skill is the reference that makes
the loop produce tests worth keeping. Consult its sections during the loop,
not after.

## What a good test is

Behavior through a public interface, reading like a specification. Expected
values come from an **independent source of truth** — a fixture, the spec's
acceptance numbers, a hand-computed value — never recomputed the way the
implementation computes them.

## Seams — where tests attach

A seam is a stable interface agreed in plan.md (file + exact exported
signature). **No test is written at an unconfirmed seam** — you can't test
everything, so effort lands where the plan agreed it matters. Seam missing or
prose-only → back to the cto, not improvised.

## The loop (per slice)

red (targeted run proves the failure is assertion-level) → green (smallest
diff) → bounded tidy under green. **Substantive refactoring is not part of
the loop; it belongs to review.** Evidence rows are appended for every RED
and GREEN with timestamps copied from real runs — QA machine-checks them
against the run log.

## Anti-patterns

Three, with tells — details in `references/anti-patterns.md`:
**tautological** (assertion recomputes expected), **implementation-coupled**
(breaks on refactor without behavior change), **horizontal bulk** (all tests
up front verify imagined behavior — work in vertical slices, tracer bullets).

## When the gate denies you

Every denial message maps to one correct next action —
`references/gate-errors.md`. The cheap moves: a targeted red costs seconds
(`bash .claude/tdd/run-tests --targeted <pattern>`); the full wrapper earns
green. Never work around a denial (shell tricks are audited and surface in
the PR); never weaken a test or config to get green.
