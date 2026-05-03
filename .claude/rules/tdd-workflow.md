---
paths:
  - "bashdep"
  - "**/*.sh"
  - ".tasks/**/*.md"
---

# TDD Workflow

**Test-Driven Development is mandatory** for behavior changes in `bashdep`.

## The Cycle

```
RED      -> Write a failing test (must fail for the RIGHT reason)
GREEN    -> Write minimal code to make it pass (nothing extra)
REFACTOR -> Improve code while keeping all tests green
REPEAT   -> Until acceptance criteria are met
```

Bug fixes: write the regression test first (it must fail without the fix),
then fix.

## Task File (Recommended for non-trivial changes)

For features, refactors, or multi-test work, create
`.tasks/YYYY-MM-DD-slug.md`. Skip for one-line bug fixes.

```markdown
# [Feature/Fix Name]

**Date:** YYYY-MM-DD  **Status:** In Progress

## Acceptance Criteria
- [ ] Criterion 1

## Test Inventory
- [ ] `test_bashdep_<thing>_<behavior>`
- [ ] `test_bashdep_<thing>_<failure_mode>`

## Current Red Bar
Test: (none yet)

## Logbook
### YYYY-MM-DD HH:MM
- Created task, analyzed existing code
```

## RED Phase

1. Pick the **smallest next test** from inventory
2. Read the surrounding tests in `tests/unit/bashdep_test.sh` to match style:
    - Pure-logic tests at the top use `BASHDEP_*` globals + `bashdep::_*` helpers
    - Filesystem tests use `$TEST_DIR` + `_seed_lock` / `_seed_installed`
3. Write the test following Arrange-Act-Assert
4. Run: `lib/bashunit tests --filter <test_name>` — **must fail**
5. Verify the failure is for the RIGHT reason (assertion mismatch, not
    "command not found" or syntax error)

## GREEN Phase

1. Write **minimal** code in `bashdep` to pass — no extra features
2. Run: `lib/bashunit tests --filter <test_name>` — **must pass**
3. Run the full suite: `make test` — nothing else regressed

## REFACTOR Phase

1. Improve readability, naming, extract duplication — **no behavior changes**
2. Run `make test` after each change
3. Run quality checks: `make sa && make lint`

## Quality Gate (Before Commit)

```bash
make pre_commit/run    # test + sa + lint
```

If `pre_commit/install` was run, the hook does this on every commit.

## Definition of Done

- All tests green for the **right reason**
- All acceptance criteria met
- Quality gate passes (`make pre_commit/run`)
- Bash 3.2+ compatible
- `CHANGELOG.md` `## Unreleased` updated (if user-facing)
- `docs/api.md` updated (if public API changed)
- `docs/behavior.md` updated (if lockfile / dev-dep / error semantics changed)
