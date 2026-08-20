---
name: status
description: Show the team pipeline's current state — active task and phase, TDD gate state and profile, recent gate denials and overrides, graph availability — plus a hook self-test.
disable-model-invocation: true
---

# /team:status — where things stand

Report, don't fix. Gather and present:

1. **TDD state**: `bash "$CLAUDE_PLUGIN_ROOT/scripts/tdd/state.sh" status`
   verbatim, then translate: what the gate will do to the next source edit
   and the cheapest way to change that (targeted red / wrapper run). If
   team.json has no test.command, lead with **"TDD gate: UNARMED"**.
2. **Active task**: `.claude/team/active-task` + its state.json — slug,
   phase, current slice, retries, approvals recorded. No active task → say so.
3. **Recent gate activity**: last ~15 lines of `.claude/team/audit.log` —
   summarize denials, warns, and especially overrides/bypasses (these will
   surface in the PR).
4. **Graph**: available (version) or fallback mode, and whether the failure
   circuit breaker is open (`.claude/team/graph-failures`).
5. **Hook self-test** (is the gate actually on?): craft a minimal PreToolUse
   payload for a source file and pipe it through
   `bash "$CLAUDE_PLUGIN_ROOT/scripts/hooks/dispatch.sh" pre-edit` — report
   whether it denied/warned/allowed and that this matches the expected
   profile (pipeline marker → strict, else ambient). A silent allow in a
   state that should deny means the gate is disarmed — say so loudly and name
   the likely cause (no JSON runtime, hooks disabled, TEAM_TDD_GATE=off).
