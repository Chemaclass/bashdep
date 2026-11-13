---
paths:
  - "bashdep"
  - "**/*.sh"
  - ".tasks/**/*.md"
---

# TDD Workflow

Behavior changes in `bashdep` require RED, GREEN, REFACTOR. For bugs, write a
regression test that fails without the fix, then fix it.

## Task tracking

For features, refactors, and multiple tests, create `.tasks/YYYY-MM-DD-slug.md`.
Skip this for one-line fixes. Record the name, date, status, acceptance criteria,
test inventory, current failing test, and dated logbook. Mark passing items.

## Cycle

1. Pick the smallest test. Follow `tests/unit/bashdep_test.sh`: pure logic uses
    `BASHDEP_*` globals and private helpers; filesystem tests use `$TEST_DIR`,
    `_seed_lock`, and `_seed_installed`. Follow Arrange, Act, Assert.
2. Run `lib/bashunit tests --filter <test_name>`. It must fail from the expected
    assertion, not a syntax error or missing command.
3. Write only enough implementation to pass. Rerun the focused test, then
    `make test` to check regressions.
4. Refactor without changing behavior. Run `make test` after each refactoring,
    then `make sa` and `make lint`.
5. Repeat until every acceptance criterion passes for the right reason.

Before committing, run `make pre_commit/run` (tests, ShellCheck, editorconfig).
An installed pre-commit hook runs the same gate. Maintain Bash 3.2 compatibility
and update the changelog, API, and behavior documentation when affected.
