#!/usr/bin/env bash
# detect-stack.sh [project-dir] — print the detected stack id on stdout.
# Detection is marker-file based and deliberately dumb; the user confirms the
# rendered config before anything is written, so a wrong guess costs a prompt,
# not a broken gate. Refinements (vitest vs jest, pest vs phpunit) are
# resolved by init-project.sh when it fills the template placeholders.
set -u
DIR="${1:-$PWD}"

if [ -f "$DIR/composer.json" ]; then
  if grep -q '"laravel/framework"' "$DIR/composer.json" 2>/dev/null; then echo laravel; exit 0; fi
  if grep -q '"symfony/' "$DIR/composer.json" 2>/dev/null; then echo symfony; exit 0; fi
  echo php; exit 0
fi
if [ -f "$DIR/package.json" ]; then
  if grep -qE '"next"[[:space:]]*:' "$DIR/package.json" 2>/dev/null; then echo nextjs; exit 0; fi
  echo node; exit 0
fi
if [ -f "$DIR/pyproject.toml" ] || [ -f "$DIR/pytest.ini" ] || [ -f "$DIR/setup.py" ] || [ -f "$DIR/setup.cfg" ]; then
  echo python; exit 0
fi
if [ -f "$DIR/go.mod" ]; then echo go; exit 0; fi
if [ -f "$DIR/Cargo.toml" ]; then echo rust; exit 0; fi
echo generic
