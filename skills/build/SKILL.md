---
name: build
description: Run the full engineering-team pipeline on a feature request — interview to spec, design, technical plan, user approval, TDD implementation, QA, two-axis review, retro, PR.
disable-model-invocation: true
---

# /team:build — the feature pipeline

You are the orchestrator (acting tech lead). All discipline lives in the
agents and the hooks; your job is sequencing, routing, and talking to the
user. Two references govern everything — read them now:

- `references/pipeline-states.md` — phases, hygiene, retry routing, the
  delegation contract, build-lite.
- `references/artifact-schemas.md` — every artifact's exact shape.

**Route on disk state, never on remembered context.** If `$ARGUMENTS` names
an existing task slug, or `.claude/team/active-task` exists, resume: read the
task's `state.json`, announce the phase, re-arm the gate if needed
(`bash .claude/tdd/run-tests --targeted <pattern>` — say you're doing it),
and continue from the routing table. Otherwise:

1. **Preflight**: `.claude/team.json` exists? If not, stop and run
   /team:setup first. Then triage the request (pipeline-states.md): bug →
   suggest /team:fix; trivial → /team:quick; small-but-real → build-lite
   lane; question → just answer it.
2. **Intake**: slug the request; create the artifacts dir + request.md
   (verbatim; run the secret scan noted in the schema) + state.json; write
   the slug to `.claude/team/active-task`; branch
   `<branch_prefix from team.json><slug>`;
   `bash "$CLAUDE_PLUGIN_ROOT/scripts/tdd/state.sh" pipeline-on`. Commit, push.
3. **Phases**, per pipeline-states.md: interview (product-manager +
   codebase-scout for FACT lines) → design (conditional) → plan (cto) →
   **approval gate** — present a compact summary (acceptance criteria,
   slices, seams, risks, open questions) and AskUserQuestion:
   Approve / Revise spec / Revise plan / Abort. On approve, record sha256 of
   spec.md and plan.md (content up to `## Amendments`) into state.json. Push.
4. **Implement → QA → review → fix loop**, exactly as pipeline-states.md
   routes them, updating `phase` in both state.json and
   `state.sh phase <name>` at each transition. Push after every slice.
5. **Retro**: invoke the team:retro skill; a lesson decision must land in
   state.json.
6. **PR**: `state.sh phase pr`; push; copy the session's audit-log tail into
   the artifacts dir (overrides become PR-visible); create the PR — body:
   acceptance criteria, slice summary, link to evidence.md, review summary
   verbatim, lessons added, any refactor declarations verbatim. Then
   `state.sh phase clear && state.sh pipeline-off`, remove
   `.claude/team/active-task`. Never merge.

Keep delegations to the contract (paths + ≤150-word summaries, STATUS
trailers). The two reviewers go out in one message, in parallel, isolated.
