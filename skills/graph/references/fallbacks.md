# Graph fallbacks — the Grep/Glob equivalents

Skip `search_exclude` paths from team.json in every fallback search (stale
task artifacts pollute results).

## Architecture overview (plan phase)

1. `Glob */` and one level down — the directory map IS the module map in most
   projects.
2. Read the entrypoints (main/index/app/kernel per stack) and follow the
   first layer of imports.
3. For each module the spec touches: Grep its name across source to find its
   consumers. Present as "modules touched → their importers".

## Impact radius (before changing shared code)

For each symbol/file you'll change:
- importers: Grep for the module path or symbol name across source globs
  (`import .*X|require.*X|use .*X|from .*X` per stack idiom);
- callers: Grep the function/method name (word-bounded);
- tests: Grep the same names across test globs.
List files; read any consumer whose usage isn't obvious. "No importers found"
is a result worth stating — with the pattern you searched.

## Risk ranking (review)

`git diff --stat` → rank by lines changed, weighted up for source-glob paths
and paths many other files import (from the impact search above), down for
docs/config/exempt.

## Untested hotspots (QA)

Changed source files (git diff) minus files referenced by any test: for each
changed file, Grep test globs for its basename and its exported names. The
remainder is the hotspot list — tag `source: fallback`.
