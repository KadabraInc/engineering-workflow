#!/usr/bin/env bats
# detect-stack per framework fixture; init-project apply/dry-run/upgrade
# idempotence; gitignore block management; placeholder rendering.

load helpers

mkrepo() {
  R="$BATS_TEST_TMPDIR/repo"
  mkdir -p "$R"
  git -C "$R" init -q
}

detect() { bash "$PLUGIN_ROOT/scripts/setup/detect-stack.sh" "$R"; }

@test "detect: laravel via composer.json marker" {
  mkrepo; echo '{"require":{"laravel/framework":"^11.0"}}' >"$R/composer.json"
  [ "$(detect)" = "laravel" ]
}

@test "detect: symfony via composer.json marker" {
  mkrepo; echo '{"require":{"symfony/framework-bundle":"^7.0"}}' >"$R/composer.json"
  [ "$(detect)" = "symfony" ]
}

@test "detect: plain php via composer.json" {
  mkrepo; echo '{"require":{"guzzlehttp/guzzle":"^7"}}' >"$R/composer.json"
  [ "$(detect)" = "php" ]
}

@test "detect: nextjs via package.json next dep" {
  mkrepo; echo '{"dependencies":{"next":"15.0.0"}}' >"$R/package.json"
  [ "$(detect)" = "nextjs" ]
}

@test "detect: node via package.json" {
  mkrepo; echo '{"devDependencies":{"vitest":"^3"}}' >"$R/package.json"
  [ "$(detect)" = "node" ]
}

@test "detect: python via pyproject" {
  mkrepo; touch "$R/pyproject.toml"
  [ "$(detect)" = "python" ]
}

@test "detect: go via go.mod" {
  mkrepo; touch "$R/go.mod"
  [ "$(detect)" = "go" ]
}

@test "detect: rust via Cargo.toml" {
  mkrepo; touch "$R/Cargo.toml"
  [ "$(detect)" = "rust" ]
}

@test "detect: generic fallback" {
  mkrepo
  [ "$(detect)" = "generic" ]
}

@test "init: dry run writes nothing" {
  mkrepo; echo '{"devDependencies":{"vitest":"^3"}}' >"$R/package.json"
  run bash "$PLUGIN_ROOT/scripts/setup/init-project.sh" --project "$R"
  [ "$status" -eq 0 ]
  [[ "$output" == *"npx vitest run"* ]]
  [ ! -f "$R/.claude/team.json" ]
}

@test "init: apply writes config, shim, seeds, state, gitignore block" {
  mkrepo; echo '{"devDependencies":{"vitest":"^3"}}' >"$R/package.json"
  run bash "$PLUGIN_ROOT/scripts/setup/init-project.sh" --project "$R" --apply
  [ "$status" -eq 0 ]
  [ -f "$R/.claude/team.json" ]
  grep -q '"command": "npx vitest run"' "$R/.claude/team.json"
  [ -x "$R/.claude/tdd/run-tests" ]
  grep -q team-shim "$R/.claude/tdd/run-tests"
  grep -q '"bootstrap": true' "$R/.claude/tdd/state.json"
  [ -f "$R/.claude/knowledge/invariants.md" ]
  grep -q '# team:begin' "$R/.gitignore"
  grep -q '!.claude/tdd/run-tests' "$R/.gitignore"
}

@test "init: second apply refuses without --upgrade; upgrade keeps config" {
  mkrepo; echo '{"devDependencies":{"jest":"^29"}}' >"$R/package.json"
  bash "$PLUGIN_ROOT/scripts/setup/init-project.sh" --project "$R" --apply >/dev/null
  run bash "$PLUGIN_ROOT/scripts/setup/init-project.sh" --project "$R" --apply
  [ "$status" -eq 1 ]
  echo '{"schema_version":1,"custom":"kept","test":{"command":"npx jest"},"globs":{"source":[],"test":[],"exempt":[],"protected":[]},"tdd":{},"hooks":{},"knowledge":{"dir":".claude/knowledge"}}' >"$R/.claude/team.json"
  run bash "$PLUGIN_ROOT/scripts/setup/init-project.sh" --project "$R" --upgrade
  [ "$status" -eq 0 ]
  grep -q '"custom": *"kept"\|"custom":"kept"' "$R/.claude/team.json"
}

@test "init: gitignore block is not duplicated on re-run" {
  mkrepo; touch "$R/go.mod"
  bash "$PLUGIN_ROOT/scripts/setup/init-project.sh" --project "$R" --apply >/dev/null
  bash "$PLUGIN_ROOT/scripts/setup/init-project.sh" --project "$R" --upgrade >/dev/null
  [ "$(grep -c '# team:begin' "$R/.gitignore")" -eq 1 ]
}

@test "init: laravel with pest picks pest commands" {
  mkrepo
  echo '{"require":{"laravel/framework":"^11"},"require-dev":{"pestphp/pest":"^3"}}' >"$R/composer.json"
  bash "$PLUGIN_ROOT/scripts/setup/init-project.sh" --project "$R" --apply >/dev/null
  grep -q '"command": "./vendor/bin/pest"' "$R/.claude/team.json"
}

@test "init: laravel without pest picks artisan test" {
  mkrepo
  echo '{"require":{"laravel/framework":"^11"}}' >"$R/composer.json"
  bash "$PLUGIN_ROOT/scripts/setup/init-project.sh" --project "$R" --apply >/dev/null
  grep -q '"command": "php artisan test"' "$R/.claude/team.json"
}

@test "init: claude/ branch convention is adopted as prefix" {
  mkrepo; touch "$R/go.mod"
  git -C "$R" -c user.email=t@t -c user.name=t commit --allow-empty -qm init
  git -C "$R" branch claude/some-old-work
  bash "$PLUGIN_ROOT/scripts/setup/init-project.sh" --project "$R" --apply >/dev/null
  grep -q '"branch_prefix": "claude/team-"' "$R/.claude/team.json"
}

@test "init: refuses outside a git repository" {
  mkdir -p "$BATS_TEST_TMPDIR/norepo"
  run bash "$PLUGIN_ROOT/scripts/setup/init-project.sh" --project "$BATS_TEST_TMPDIR/norepo" --apply
  [ "$status" -eq 1 ]
}

@test "all stack templates are valid JSON with required keys" {
  for t in "$PLUGIN_ROOT"/scripts/setup/templates/team.*.json; do
    jq -e '.schema_version and .test and .globs and .tdd and .hooks' "$t" >/dev/null
  done
}
