# Test anti-patterns — and their tells

## Tautological

The assertion recomputes the expected value the same way the code under test
does (same formula, same helper, same constant). The test can only fail if
the language breaks.

**Tell**: delete the implementation's logic mentally — could the test's
expected value still be written? If producing the expected value requires the
same code you're testing, it's tautological. **Fix**: expected values from an
independent source — a committed fixture, the spec's own numbers, a value
computed by hand in the test as a literal.

## Implementation-coupled

The test asserts on internals: private helpers, call counts, intermediate
shapes, exact log strings.

**Tell**: the test breaks when internals are refactored but behavior hasn't
changed. **Fix**: assert at the seam's public interface on observable
behavior. Mocks only at boundaries the plan names (network, clock, disk) —
a mock of your own module is coupling wearing a disguise.

## Horizontal bulk

Writing all tests for all slices before any implementation. Bulk tests verify
*imagined* behavior; by slice 3 the real interfaces have drifted and the
tests get "fixed" to match code — backwards.

**Tell**: tests exist for seams whose slice hasn't started. **Fix**: vertical
slices — one slice's tests, then its implementation, then the next. Each test
is a tracer bullet through the real stack.

## Bonus tells worth rejecting

- A red that isn't assertion-level (import/resolution errors) handed off as
  done — that's `RED-TRANSITIONAL`; scaffold, then re-verify.
- A test that needs `sleep` to pass — a race acknowledged, not handled.
- Asserting on framework behavior the project doesn't own.
