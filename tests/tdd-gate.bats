#!/usr/bin/env bats
# Gate matrix: state × path-class × mode → decision.

load helpers

setup() { make_project; }

@test "unknown state: source edit denied in block mode" {
  write_state unknown
  run_check checks/tdd-gate.sh "$(payload_edit "$PROJ/src/index.js")" block
  assert_deny
  [[ "$output" == *"No verified test state"* ]]
}

@test "unknown state: source edit warns (not denies) in warn mode" {
  write_state unknown
  run_check checks/tdd-gate.sh "$(payload_edit "$PROJ/src/index.js")" warn
  assert_allow
  assert_warn
}

@test "missing state file: denied with setup guidance" {
  rm -f "$PROJ/.claude/tdd/state.json"
  run_check checks/tdd-gate.sh "$(payload_edit "$PROJ/src/index.js")" block
  assert_deny
  [[ "$output" == *"team:setup"* ]]
}

@test "test file edit always allowed (the red step)" {
  write_state unknown
  run_check checks/tdd-gate.sh "$(payload_edit "$PROJ/tests/example.test.js")" block
  assert_allow
}

@test "test file edit denied during implement phase" {
  write_state red observed 1
  echo implement >"$PROJ/.claude/tdd/phase"
  run_check checks/tdd-gate.sh "$(payload_edit "$PROJ/tests/example.test.js")" block
  assert_deny
  [[ "$output" == *"RED-REVISED"* ]]
}

@test "exempt path (docs) allowed regardless of state" {
  write_state unknown
  run_check checks/tdd-gate.sh "$(payload_edit "$PROJ/docs/readme.md")" block
  assert_allow
}

@test "fresh red opens the gate for source edits" {
  write_state red observed 1
  run_check checks/tdd-gate.sh "$(payload_edit "$PROJ/src/index.js")" block
  assert_allow
}

@test "red at brownfield baseline does NOT arm the gate" {
  write_state red full 5 5
  run_check checks/tdd-gate.sh "$(payload_edit "$PROJ/src/index.js")" block
  assert_deny
  [[ "$output" == *"baseline"* ]]
}

@test "red beyond brownfield baseline DOES arm the gate" {
  write_state red full 6 5
  run_check checks/tdd-gate.sh "$(payload_edit "$PROJ/src/index.js")" block
  assert_allow
}

@test "fingerprint mismatch reads as unusable state" {
  write_state red observed 1
  echo "new test" >"$PROJ/tests/new.test.js"   # tests changed after the run
  run_check checks/tdd-gate.sh "$(payload_edit "$PROJ/src/index.js")" block
  assert_deny
  [[ "$output" == *"Test files changed"* ]]
}

@test "green under budget allows edits (refactor under green)" {
  write_state green full 0
  run_check checks/tdd-gate.sh "$(payload_edit "$PROJ/src/index.js")" block
  assert_allow
}

@test "green with exhausted budget is denied" {
  write_state green full 0
  for i in 1 2 3; do
    echo "t $i src/index.js" >>"$PROJ/.claude/tdd/counters/source_edits.log"
  done
  run_check checks/tdd-gate.sh "$(payload_edit "$PROJ/src/index.js")" block
  assert_deny
  [[ "$output" == *"budget exhausted"* ]]
}

@test "refactor declaration raises the green budget" {
  write_state green full 0
  for i in 1 2 3; do
    echo "t $i src/index.js" >>"$PROJ/.claude/tdd/counters/source_edits.log"
  done
  echo "module split, no behavior change" >"$PROJ/.claude/tdd/refactor"
  run_check checks/tdd-gate.sh "$(payload_edit "$PROJ/src/index.js")" block
  assert_allow
}

@test "error state is denied with fix-config message, never treated as red" {
  write_state error full
  run_check checks/tdd-gate.sh "$(payload_edit "$PROJ/src/index.js")" block
  assert_deny
  [[ "$output" == *"broken"* ]]
}

@test "bootstrap mode warns and allows" {
  write_state unknown
  # flip bootstrap on
  sed -i 's/"bootstrap": false/"bootstrap": true/' "$PROJ/.claude/tdd/state.json"
  run_check checks/tdd-gate.sh "$(payload_edit "$PROJ/src/index.js")" block
  assert_allow
  [[ "$output" == *"bootstrap"* ]]
}

@test "TEAM_TDD_GATE=off bypasses and leaves an audit line" {
  write_state unknown
  TEAM_TDD_GATE=off run_check checks/tdd-gate.sh "$(payload_edit "$PROJ/src/index.js")" block
  assert_allow
  grep -q '"decision":"bypass-env"' "$PROJ/.claude/team/audit.log"
}

@test "human allow-file override admits matching path once and audits" {
  write_state unknown
  cat >"$PROJ/.claude/tdd/allow" <<EOF
{"paths":["src/**"],"expires_at":"2099-01-01T00:00:00Z","reason":"hotfix approved by human"}
EOF
  run_check checks/tdd-gate.sh "$(payload_edit "$PROJ/src/index.js")" block
  assert_allow
  grep -q '"decision":"override"' "$PROJ/.claude/team/audit.log"
}

@test "expired allow-file is consumed and does not admit" {
  write_state unknown
  cat >"$PROJ/.claude/tdd/allow" <<EOF
{"paths":["src/**"],"expires_at":"2000-01-01T00:00:00Z","reason":"stale"}
EOF
  run_check checks/tdd-gate.sh "$(payload_edit "$PROJ/src/index.js")" block
  assert_deny
  [ ! -f "$PROJ/.claude/tdd/allow" ]
}

@test "unclassified path fails closed as source (default_class)" {
  write_state unknown
  mkdir -p "$PROJ/weird"
  run_check checks/tdd-gate.sh "$(payload_edit "$PROJ/weird/thing.xyz")" block
  assert_deny
}

@test "file outside the project is ignored" {
  write_state unknown
  run_check checks/tdd-gate.sh "$(payload_edit "$BATS_TEST_TMPDIR/elsewhere.js")" block
  assert_allow
}

@test "unrecognized state schema_version reads as unknown (fail-closed)" {
  write_state green full 0
  sed -i 's/"schema_version": 1/"schema_version": 99/' "$PROJ/.claude/tdd/state.json"
  run_check checks/tdd-gate.sh "$(payload_edit "$PROJ/src/index.js")" block
  assert_deny
}
