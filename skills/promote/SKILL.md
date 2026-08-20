---
name: promote
description: Consume lesson promotion packets into the team plugin itself — run inside the engineering-workflow plugin repo to review cross-project promotion candidates and turn accepted ones into a plugin PR.
disable-model-invocation: true
---

# /team:promote — fold project lessons into the plugin

Run this INSIDE the plugin repo (`KadabraInc/engineering-workflow`), not in a
consuming project.

1. **Collect candidates**: open issues titled `promotion: *` on this repo,
   plus any packet files the user pastes/points to
   (`.claude/knowledge/promotions/*.md` from their projects).
2. **The bar**: evidence from **≥2 distinct projects** (the packet names
   them), and the rule must be project-agnostic — no stack assumptions a
   preset doesn't own, no Kadabra-specific paths. One project's quirk stays
   in that project's ledger.
3. **Decide the landing place** with the user, per candidate:
   - agent instruction (a discipline rule → the owning agent's .md),
   - skill reference (a technique → tdd/graph/grilling references),
   - preset default (a stack fact → the team.<stack>.json template),
   - hook check (a mechanically checkable rule → propose, but flag that hook
     changes need the full bats treatment).
4. **One branch, one PR** per promotion round: the change, a CHANGELOG entry,
   version bump per the repo's versioning rules, tests updated when behavior
   changed. Close the consumed issues with a link to the PR.
5. Anything rejected: comment why on its issue and close — the reason
   travels back to the proposing project's ledger.
