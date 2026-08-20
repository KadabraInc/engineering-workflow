# Gate denials → the correct next action

Every deny reason `tdd-gate` and friends emit, mapped to the move that
unblocks you honestly. (Kept in sync with scripts/hooks/checks/*.sh — CI has
no automated check for this file; update it when you change a reason string.)

| Denial says | It means | Do this |
|---|---|---|
| "No TDD state found — run /team:setup" | Project never initialized (or state deleted) | Run /team:setup, or `bash .claude/tdd/run-tests` if team.json exists |
| "No verified test state. Write or pick a failing test..." | State is `unknown` — no run recorded, or state invalidated | Write/pick the failing test for your change; `bash .claude/tdd/run-tests --targeted <pattern>` (seconds) |
| "Test files changed since the last verified run" | Fingerprint mismatch — tests edited after the recorded run | Re-run the targeted failing test to re-arm |
| "Red state is older than Nm" | Red went stale | Re-run the targeted failing test |
| "Suite is red at its pre-existing baseline (N known failures)" | Brownfield: ambient failures don't arm the gate | Write a failing test for THIS change; run it targeted |
| "Test command is broken (last run errored...)" | Exit 126/127 or unrecognizable failure — the RUNNER is broken, not the tests | Read `.claude/tdd/last-run.log`; fix test.command in team.json WITH THE USER (it's protected), or /team:setup --upgrade |
| "Green refactor budget exhausted (N source edits...)" | Too many edits under green without re-verification | `bash .claude/tdd/run-tests` to re-verify — or, for a true behavior-free refactor, `echo '<why>' > .claude/tdd/refactor` (lands verbatim in the PR) |
| "Implement phase: test files are frozen" | You're the implementer; tests route through the test-engineer | Two honest attempts at green, then `STATUS: BLOCKED` with the test path + `.claude/tdd/last-run.log` — the cto adjudicates |
| "Protected file (gate/config surface)" | Config-protection: the file defines the quality bar | Fix the code, not the config; genuinely wrong config → ask the human |
| "This is the team plugin's own code" | You tried to edit the installed plugin | Propose the change for the plugin repo instead |
| "The override file .claude/tdd/allow is a HUMAN escape hatch" | You tried to self-grant an override | Satisfy the gate (targeted red), or ask the user to create the file |
| "Shell write into gated source" | Redirect/sed/tee into source via bash | Use Edit/Write so the gate can evaluate; delivery counts shell writes anyway |
| Stop blocked: "no verified full-suite pass" | Delivery gate: source changed, no wrapper green (or brownfield delta) | `bash .claude/tdd/run-tests` (use `--background` for slow suites) |
| Stop blocked: "zero test changes" | Source changed, tests didn't, no refactor declared | Add/extend a test — or declare the refactor if genuinely behavior-free |
| Stop blocked: "imports from a test path" | Production code depends on test files | Move the shared code into source; tests import FROM source, never the reverse |
| Stop blocked: "changed after user approval" | spec/plan frozen region edited post-approval | Restore the frozen region; changes go in `## Amendments` + re-approval |
| Stop blocked: "requires a retro decision" | PR phase without lesson/no-lesson recorded | Run the team:retro step; record the decision in state.json |
