# Architecture

## One paragraph

The plugin is a virtual engineering team: nine role agents (typed by what
they consume and produce), five user-invoked entry skills that sequence them
from the main conversation (the orchestrator — agents cannot call agents),
four shared discipline skills they all reference, and a deterministic
enforcement layer of six hook events funneled through one dispatcher —
because on this team, hard rules are pure functions and the LLM is for
judgment and prose only.

## Data flow (a feature request)

```
request ──/team:build──▶ intake: artifacts dir, branch, pipeline marker (strict profile)
   │
   ▼ interview        product-manager ⇄ user (grilling rounds), facts via codebase-scout
 spec.md
   ▼ design (cond.)   design-lead — human-facing surfaces only
 design.md
   ▼ plan             cto — signature-strict seams, slices, impact radius (graph|fallback)
 plan.md
   ▼ APPROVAL ⏸       user approves; spec+plan hashes frozen in state.json
   ▼ implement        per slice: test-engineer (RED, evidence) ⇄ implementer (GREEN, evidence)
   │                  gate: red-before-source enforced by PreToolUse hook; test files frozen
   ▼ qa               qa-verifier: wrapper run, verify-evidence.sh, orphan diff, hotspots
 qa.md
   ▼ review           standards-reviewer ∥ spec-reviewer (parallel, isolated, ≤400w each)
 review/summary.md    verbatim aggregation, tensions named, never merged
   ▼ retro            lesson decision (incident-backed or no-lesson: reason)
   ▼ pr               push, PR with evidence + reviews + audit tail. Never auto-merge.
```

Every arrow is a file (`.claude/team/artifacts/<slug>/…`, committed on the
branch): each role's completion criterion is "the next role's input artifact
exists and validates". The main loop passes paths and ≤150-word summaries,
never pastes artifacts.

## Enforcement layer

```
hooks/hooks.json (6 registrations)
   └─▶ scripts/hooks/dispatch.sh  — inert without .claude/team.json;
        │                           profile: pipeline marker → strict, else ambient
        ├─ pre-edit:  config-protection, tdd-gate
        ├─ pre-bash:  bash-write-guard
        ├─ post-edit: edit-counter, graph-update (async, circuit-broken)
        ├─ post-bash: test-run-observer (red is cheap)
        ├─ session-start: session-context (git baseline; sanitized knowledge
        │                 injection — THE trust boundary; status banners)
        └─ stop:      delivery-gate (git-truth accounting; blocks only in
                      terminal pipeline phases)
```

`scripts/tdd/run-tests.sh` is the only writer of green; setup installs it
into each project as a self-contained shim so teammates and CI need no
plugin. `docs/tdd-gate.md` is the normative spec.

## Knowledge loop

observations (hooks, audit log) → per-task retro drafts incident-backed
lessons (candidates) → PR review is the human gate → accepted invariants get
structured entries in `.claude/knowledge/invariants.md` → session-context
injects sanitized rule lines only, under a preamble denying them authority
over gates/tools → cto and standards-reviewer must cite applicable INV-ids →
`/team:retro --audit` retires stale/contradicting entries → promotion packets
(+ cross-repo issue) → `/team:promote` in this repo, two-project evidence bar.

## Repo layout

See the README's annotated tree. Contracts live in
`skills/build/references/` (artifact-schemas.md, pipeline-states.md) — they
are the single source of truth the agents, skills, and hooks all cite.
