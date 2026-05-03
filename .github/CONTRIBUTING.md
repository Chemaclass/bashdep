# Contributing

Thanks for considering a contribution. This guide covers project layout,
how to run the suite, and the conventions we follow.

## Code of Conduct

This project follows a [Contributor Code of Conduct](CODE_OF_CONDUCT.md).
By participating you agree to abide by its terms.

## License

Contributions are licensed under [MIT](../LICENSE).

## Project layout

```
bashdep                     # Library entry point — sourced by consumers
tests/unit/bashdep_test.sh  # Unit tests (bashunit)
tests/unit/snapshots/       # Captured stdout for snapshot assertions
example/demo.sh             # End-to-end demo
.github/workflows/          # CI: tests, ShellCheck, editorconfig
Makefile                    # test / sa / lint / deps / pre_commit/install
```

The codebase is intentionally small and zero-runtime: only `curl`,
`awk`, `mktemp`, and POSIX-ish utilities at runtime. Tests run on
bash 3.2+ (default macOS) and bash 4+ (Linux CI).

## Workflow for pull requests

1. Fork/clone, branch from `main`.
2. Implement the change and add tests for it.
3. Run `make pre_commit/run` (test + ShellCheck + editorconfig).
4. Open the PR with a short summary and a test plan.

Set your git `user.name` / `user.email` so commit history stays clean:
see [first-time setup](https://git-scm.com/book/en/v2/Getting-Started-First-Time-Git-Setup).

## Bug reports

Please include:

- Summary and what you expected.
- Steps to reproduce (sample code beats prose).
- Actual output, pasted as text.
- Environment: OS, `bash --version`.

## Testing

Install dev dependencies (bashunit, pinned to the CI version):

```bash
make deps
```

Run the suite:

```bash
make test
# or directly:
lib/bashunit tests
```

Conventions in `tests/unit/bashdep_test.sh`:

- One test per behavior. Names describe the assertion (`test_bashdep_…`).
- Pure-logic tests (no filesystem) sit at the top of the file.
- Filesystem tests use `$TEST_DIR` (a `mktemp -d` set up in `set_up`,
  cleaned in `tear_down`). Use the `_seed_lock` / `_seed_installed`
  helpers to scaffold lockfile fixtures.
- Snapshot tests keep hardcoded `/tmp/test_<name>` paths because the
  snapshot embeds the path. Don't migrate those to `$TEST_DIR`.

## Coding guidelines

### ShellCheck

Install: <https://github.com/koalaman/shellcheck#installing>

```bash
make sa
```

`make sa` discovers scripts via `find` and matches CI scope: `bashdep`,
`bin/pre-commit`, and every `*.sh` outside `vendor/`, `lib/`, `local/`.

### editorconfig-checker

Install: <https://github.com/editorconfig-checker/editorconfig-checker#installation>

```bash
make lint
```

### Pre-commit hook (recommended)

Requires ShellCheck and editorconfig-checker on `$PATH`.

```bash
make pre_commit/install
```

Runs `make pre_commit/run` (test + sa + lint) on every commit.

### Style

We follow Google's
[Shell Style Guide](https://google.github.io/styleguide/shellguide.html)
where it doesn't conflict with this repo's conventions:
`function name() { … }`, snake_case, and the `bashdep::` namespace
prefix on every public function.
