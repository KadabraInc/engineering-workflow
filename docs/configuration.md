# Configuration — `.claude/team.json` reference

Created by `/team:setup` from a stack preset, approved by you before writing,
committed to the project. The file is **protected**: the model's Edit tool
cannot change it — that's the point (nobody passes tests by weakening the
config). Humans edit it freely.

```jsonc
{
  "schema_version": 1,          // config schema; setup --upgrade migrates
  "stack": "node",              // informational

  "test": {
    "command": "npx vitest run",             // FULL suite — the only path to green
    "targeted_command": "npx vitest run {pattern}",  // single test; {pattern} substituted
    "match": "vitest|npm (run )?test",       // ERE: which Bash commands the observer watches
    "fail_patterns": ["[1-9][0-9]* failed"], // ERE list: confident-failure markers
    "fail_count_pattern": "[0-9]+ failed"    // ERE whose first number is the failure count
  },

  "globs": {                    // classification, first match wins:
    "source": ["src/**"],       //   protected > test > exempt > source > default_class
    "test": ["tests/**", "**/*.test.*"],
    "exempt": ["**/*.md", "docs/**"],        // never gated (docs, config, generated)
    "protected": ["vitest.config.*"]         // never model-editable (plus the always-
                                             // protected set: team.json, .claude/tdd/**,
                                             // audit log, .claude/settings*.json)
  },

  "tdd": {
    "enabled": true,            // false = gate off (human-only change; audited context)
    "default_class": "source",  // unmatched paths fail CLOSED as source
    "staleness_minutes": 240,   // red older than this must re-run
    "green_edit_budget": 5,     // source edits allowed under green before re-verify
    "refactor_budget": 25       // budget with a declared .claude/tdd/refactor
  },

  "hooks": {
    "enabled": true,            // master switch for all team hooks in this project
    "ambient_profile": "standard",   // ordinary sessions: warn + audit
    "pipeline_profile": "strict"     // /team:* sessions: hard deny
  },

  "delivery": {
    "min_source_files": 3,      // sessions changing fewer source files skip the Stop gate
    "retry_failed": 0           // wrapper retries on full-suite failure (flaky suites; audited)
  },

  "knowledge": { "dir": ".claude/knowledge" },

  "search_exclude": [".claude/team/artifacts/**", ".claude/knowledge/lessons/**"],
                                // paths the scout/graph/fallback searches skip
  "branch_prefix": "team/",     // task branches; setup adopts an existing claude/ convention
  "graph": { "enabled": true }  // false = never call code-review-graph
}
```

## Env overrides (per session, all audited where they bypass)

| var | effect |
|---|---|
| `TEAM_HOOKS=off` | dispatcher inert this session |
| `TEAM_HOOK_PROFILE=minimal\|standard\|strict` | force a profile |
| `TEAM_TDD_GATE=off` | bypass the pre-edit gate (audit line per edit) |

## Glob semantics

`*` and `**` both cross `/` in these patterns (bash string matching);
`**/X` additionally matches `X` at the repo root. Patterns are matched
against paths relative to the project root (the nearest ancestor of the
edited file containing `.claude/team.json` — that rule is also the monorepo
story: nested team.json wins for files under it).
