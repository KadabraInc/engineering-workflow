---
name: grilling
description: The team's interview primitive — align with the user before work by asking question frontiers in rounds, each question numbered with a recommended answer. Use whenever requirements, scope, or a design choice need human decisions: the interview phase of a feature, an ambiguous bug report, a setup with unknown commands.
---

# Grilling — the interview primitive

Model the open decisions as a **design tree**: each decision unlocks others.
Work in **rounds**. The **frontier** is every decision whose prerequisites
are settled. Each round, ask the WHOLE frontier at once — numbered, each with
your recommended answer:

```
Q1 — <short title>: <the question; concrete options where they exist>
➡ recommended: <your answer, one-line why>
```

The split that makes this work: **facts are your job, decisions are the
user's.** Anything a lookup can answer — how the code works today, what a
library supports, what the data looks like — you find (codebase-scout for
repo facts) and never ask. What remains are genuine judgment calls: scope,
tradeoffs, priorities, taste.

Mechanics:

- Deliver via AskUserQuestion where the frontier fits its limits (a
  recommended answer is listed first); a frontier too large or too
  free-form goes as the numbered text block above, answered in prose.
- Answers can invalidate branches — prune pruned subtrees silently; don't
  re-ask settled decisions.
- **The session is done when the frontier is empty.** An empty first frontier
  is a valid outcome: say so and proceed.
- Respect the caller's round cap (the pipeline uses 3). Leftover decisions
  become recorded open questions (OQ-n), never assumptions.
- Record each round's questions and answers where the caller specifies
  (pipeline: `interview/questions-rN.md` / `answers-rN.md`).
