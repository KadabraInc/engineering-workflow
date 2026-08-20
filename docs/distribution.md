# Distribution — installing, updating, private-repo reality

## Names you will see

| thing | name |
|---|---|
| GitHub repo & marketplace | `engineering-workflow` |
| plugin | `team` |
| skills | `/team:setup`, `/team:build`, `/team:fix`, `/team:quick`, `/team:status`, `/team:retro`, `/team:promote` |

## Install

```
/plugin marketplace add KadabraInc/engineering-workflow
/plugin install team@engineering-workflow
```
then in each project: `/team:setup`.

## Private-repo bootstrap (do this once per machine, or installs WILL fail)

- `gh auth setup-git` (or working SSH keys — the `owner/repo` shorthand
  clones over SSH by default; set `CLAUDE_CODE_PLUGIN_PREFER_HTTPS=1` to use
  HTTPS credentials instead).
- Set `CLAUDE_CODE_PLUGIN_KEEP_MARKETPLACE_ON_FAILURE=1` in your environment:
  background marketplace refreshes run without credential helpers, and a
  failed refresh can otherwise drop the marketplace — **removing a
  marketplace uninstalls its plugins**.
- Team/Enterprise orgs: prefer distributing via Organization settings →
  Plugins — org sync reads through the GitHub App and bypasses per-user git
  auth entirely. This repo's layout (plugin at the marketplace root,
  `source: "./"`) is exactly the supported shape.
- Optionally add the marketplace to each consuming project's
  `.claude/settings.json` `extraKnownMarketplaces` so folder trust offers it
  automatically.

## Updates do NOT flow by themselves

Third-party marketplaces have auto-update **off** by default. To ship a
change: bump the version (`scripts/dev/sync-version.sh --write X.Y.Z` + a
CHANGELOG entry — CI enforces sync), then users run
`/plugin marketplace update engineering-workflow`. The session banner warns
when the installed shim version lags the plugin; `/team:setup --upgrade`
refreshes per-project files. Expect version skew across projects — the
runtime handles it (unknown state schemas read fail-closed; config reads have
defaults; the banner names the fix) but don't let it accumulate.

## code-review-graph (optional dependency policy)

Install **pinned** (`pip install 'code-review-graph==2.3.7'`, pipx preferred)
— it is a young, solo-maintained tool; the pin is the abandonment insurance
(the plugin keeps working on the tested version, or degrades to fallbacks on
purpose). **CLI-only**: never run its `install --platform` (it mutates
user-global `~/.claude.json` and loads 30 MCP tools into every project;
the plugin cannot undo that). Beware the similarly-named
`code-review-graph-codeblackwell` fork shipping the same executable name —
install only `code-review-graph` from PyPI. `.code-review-graph/` (a full
structural map of your codebase) must stay gitignored; setup verifies with
`git check-ignore`.
