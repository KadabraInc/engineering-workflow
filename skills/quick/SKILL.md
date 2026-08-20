---
name: quick
description: Guarded escape hatch for genuinely small changes — no agents, no spec, no review ceremony; the TDD gate still applies. Hard upgrade rule when the change outgrows eligibility.
disable-model-invocation: true
---

# /team:quick — small changes without ceremony

You do the work yourself — no subagents, no spec, no review phase. The hooks
don't care which flow is running: the TDD gate still gates source edits, and
behavior changes still need a red first (targeted runs make that cost
seconds: `bash .claude/tdd/run-tests --targeted <pattern>`).

**Eligibility — by risk, not file count.** All must hold:
- no schema/migration change, no new public surface (route, command, exported
  API), no protected paths;
- expected diff ≤ ~150 lines;
- you can name the existing tests that cover the behavior you're touching, or
  the change is behavior-free (docs, copy, config values in exempt paths).

**The upgrade rule is hard.** The moment eligibility breaks mid-work — a
surprise coupling, a needed schema tweak, an unrelated failing test — STOP.
Say what broke, then restart as the **build-lite lane** of /team:build
(see its pipeline-states.md), carrying over anything already done. Do not
push through "just one more file".

Do the work: branch (`<branch_prefix>quick-<slug>`), red if behavior changes
(targeted), edit, green (targeted, then full wrapper if >1 source file),
narrative commit explaining what and why, push. Offer a PR; for one-line
changes the user may prefer to fold it into other work — ask.

No lesson required — but if the quick task surprised you, say so and offer
/team:retro.
