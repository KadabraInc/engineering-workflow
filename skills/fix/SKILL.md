---
name: fix
description: Run the engineering-team bug-fix flow — reproduce the bug as a failing test, get a lightweight approval, fix under the TDD gate, targeted QA, standards review, capture the lesson, PR.
disable-model-invocation: true
---

# /team:fix — the bug flow

Bugs skip the interview and the full plan: **the reproduction is the spec,
and the failing test is the plan.** Same hooks, same evidence, same schemas
(see the team:build skill's references — both apply here).

1. **Preflight + intake** as in build (slug, artifacts dir, request.md with
   secret scan, `active-task`, branch, `state.sh pipeline-on`, push). At most
   ONE clarifying round, and only if you cannot reproduce from the report.
2. **Repro as red** (test-engineer): a failing test that demonstrates the
   bug at the nearest stable seam — assertion-level red, evidence row
   appended. If the bug can't be captured in a test (rare: visual, timing),
   record why in state.json and treat this as build-lite instead.
3. **Lightweight approval**: show the user the repro (test + failure output)
   and a one-paragraph proposed fix. AskUserQuestion: Approve / Adjust / Abort.
4. **Scope check**: impact radius of the fix (graph skill or grep). Crosses a
   module boundary or touches >3 source files → cto writes a one-slice
   mini-plan first (seams table required); otherwise proceed.
5. **Fix** (implementer): minimal diff to green; full wrapper run;
   GREEN evidence row. `state.sh phase implement` during, `phase qa` after.
6. **Targeted QA** (qa-verifier): suite + evidence audit + orphan-diff on
   this diff only.
7. **Single-axis review**: standards-reviewer only (spec fidelity IS the
   repro test passing). Fix loop per pipeline-states.md routing.
8. **Lesson decision — bugs are where invariants get bought.** Invoke
   team:retro. Write a lesson when the bug taught a reusable rule; otherwise
   record `no-lesson: <reason>` in state.json. Either way the decision is
   explicit.
9. **PR** as in build (audit tail copied in, phases cleared, never merge).
