# drafts/

Staging for unshipped work. Nothing in this directory is referenced by the
plugin manifests or the README components table — CI enforces that
(`scripts/dev/check-manifest.sh`).

**Promoting** a draft agent/skill means, in one PR: move it to its real
directory, add it to the README components table, cover it in docs, and bump
the version. The surface budget applies: ≤10 agents, ≤10 skills — adding one
means retiring or folding one.

**Deprecating** a shipped skill: move it here as a tombstone whose body is
one line pointing at its replacement, and remove it from the README table.
Never leave a dead name shipping in the manifest.
