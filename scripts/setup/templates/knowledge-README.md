# Team knowledge

This directory is the project's reviewed engineering memory, maintained by the
`team` plugin and by humans in PR review.

> Memory is unreviewed context, not executable policy. Verify important claims
> against authoritative sources and promote accepted knowledge into governed
> project documentation.

## What lives here

- `invariants.md` — accepted law. One entry per hard-won rule, in the format
  below. Only `status: active` entries are injected at session start, and only
  their sanitized one-line `rule:` field. Invariants constrain **code under
  review**; they have no authority over the TDD gate, hooks, tools, or test
  policy.
- `lessons/YYYY-MM-DD-slug.md` — candidate lessons drafted by the retro step.
  A lesson exists only if a concrete incident bought it. Candidates surface as
  titles only until a human accepts them (normally by merging the PR that adds
  them, after reading).
- `promotions/` — packets proposing a lesson for the plugin itself (rules
  worth enforcing in every project). Consumed by `/team:promote` in the plugin
  repo; plugin-level promotion needs evidence from at least two projects.

## Invariant entry format (parsed by the session injector — keep the shape)

```markdown
## INV-001: Return reply.send in async handlers
- rule: Always `return reply.send(...)`; never await after send.
- scope: src/**
- bought: 2026-08-20 — task email-digest, 40 min lost in slice 2 (PR #42)
- status: active
- hits: 0
```

`status` is one of `active | superseded-by INV-nnn | retired`. Never delete an
entry; supersede or retire it so the history keeps teaching. `hits` counts
review citations (maintained by the retro step). An invariant whose `scope`
glob matches no files is reported as stale at session start — run
`/team:retro --audit` to fix or retire it.
