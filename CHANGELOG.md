# Changelog

## 0.1.0 — 2026-08-20

Initial release.

- Nine role agents (2 opus / 5 sonnet / 2 haiku) with typed artifact handoffs
  (spec → design → plan → evidence → qa → review), signature-strict test
  seams, and cto adjudication of test disputes.
- Pipeline skills: `/team:build` (with build-lite lane), `/team:fix`
  (repro-as-red), `/team:quick` (guarded escape hatch), `/team:setup`,
  `/team:status`, `/team:retro` (lessons, `--audit`, `--prune`),
  `/team:promote`; discipline skills `grilling`, `tdd`, `graph`.
- Hard TDD gate: red-is-cheap/green-is-expensive state machine, brownfield
  baseline mode, targeted verified green, refactor budgets and declarations,
  implement-phase test freeze, error-vs-red runner semantics — strict in
  pipeline sessions, warn+audit ambient.
- Delivery gate on git truth (session-start SHA accounting), evidence
  cross-checking (`verify-evidence.sh`), approval-hash freezing with an
  Amendments region, retro-decision requirement.
- Knowledge system: invariants-with-incidents ledger, sanitizing session
  injector as the trust boundary, staleness reporting, hits accounting,
  two-project promotion bar.
- Nine stack presets (laravel, symfony, php, node, nextjs, python, go, rust,
  generic) with per-stack exempt/protected judgment calls; idempotent setup
  with a committed self-contained test wrapper.
- Optional code-review-graph integration: pinned, CLI-only, circuit-broken,
  Grep/Glob fallbacks everywhere.
- 100+ bats tests over the enforcement machinery; CI: JSON cross-checks,
  shellcheck, bats, version sync, manifest promotion invariant.
