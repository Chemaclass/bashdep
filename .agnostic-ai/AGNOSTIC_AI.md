# bashdep

bashdep downloads URLs declared in `.bashdep` into `lib/`. A per-directory
`.bashdep.lock` keeps installs idempotent. It has no registry or daemon.
Repository: https://github.com/Chemaclass/bashdep.

## Configuration

All paths in these instructions and skills are relative to the repository root.
Edit `.agnostic-ai/AGNOSTIC_AI.md`, `.agnostic-ai/rules/`, and `.agnostic-ai/skills/`.
Project settings live in `agnostic-ai.yaml`. Run `agnostic-ai sync`, then
`agnostic-ai sync --check`. Generated files are ignored by Git.

Claude reads `CLAUDE.md`, `.claude/rules/`, `.claude/skills/`, and
`.claude/settings.json`. Codex reads `AGENTS.md` and `.agents/skills/`.
Claude loads rules for matching paths. Codex receives the rules in root
`AGENTS.md`; apply each rule to its listed paths. The existing automatic
ShellCheck hook runs only in Claude. Both tools must run the quality gate.

## Layout and commands

`bashdep` is the single library entry point and CLI. `release.sh` handles releases;
see `docs/releasing.md`. `.bashdep` pins and checksums bashunit.
`install-dependencies.sh` installs it through bashdep. `tests/bootstrap.sh` holds
shared helpers, `tests/unit/bashdep_test.sh` the suite, and
`tests/unit/snapshots/` the expected output. `example/` holds the demo.
`lib/` is ignored. `.github/workflows/` runs tests, ShellCheck, and editorconfig.

```bash
make deps                        # Install bashunit
make test                        # Run tests; installs bashunit if needed
lib/bashunit tests --filter NAME  # Run one test
make sa                          # ShellCheck
make lint                        # editorconfig-checker
make check                       # All three checks
make pre_commit/run              # Same quality gate
./bashdep --help                  # CLI usage
```

Every change must pass the quality gate before pushing. Do not bypass hooks.
Behavior changes require a failing test first, then minimal code, then refactoring.
Keep the suite green for the right reason and follow existing test patterns.
The Bash, testing, and TDD rules contain the detailed conventions.

## Runtime contract

Support macOS Bash 3.2 and Linux Bash 4+. Library code may call only `curl`
(or `wget`), `awk`, `mktemp`, `mkdir`, `rm`, `cp`, `mv`, `printf`, `cat`, `grep`,
`sort`, `tr`, `dirname`, `basename`, and shell builtins. No `jq`, Python, or Node
at runtime. Public functions use `bashdep::`; private helpers use `bashdep::_`.

| Function | Purpose |
| --- | --- |
| `bashdep::install` | Install an inline URL array |
| `bashdep::install_from` | Install a `.bashdep` file |
| `bashdep::add` | Install URLs and append them pinned with `#sha256=` |
| `bashdep::setup` | Configure directories and modes |
| `bashdep::list` | List dependencies |
| `bashdep::uninstall` | Remove dependencies |
| `bashdep::clean` | Remove files absent from the lockfile |
| `bashdep::doctor` | Report missing and orphan files |
| `bashdep::self_update` | Download bashdep from upstream |
| `bashdep::version` | Print `BASHDEP_VERSION` |
| `bashdep::main` | Dispatch the CLI when executed, not sourced |
| `bashdep::usage` | Print usage |

Every mutating path must honor `BASHDEP_DRY_RUN`, `BASHDEP_SILENT`,
`BASHDEP_VERBOSE`, and `BASHDEP_FORCE` through the existing helpers.
Test fixtures must mock network calls. Never commit `lib/`, `local/`, or `tmp/`.

## Documentation and completion

Update `CHANGELOG.md` under Unreleased for user-visible changes. Update
`docs/api.md` for public signatures and `docs/behavior.md` for lockfile,
development dependency, or error semantics. Documentation must reflect the
actual API, with runnable examples and relevant cross-links between `api.md`,
`behavior.md`, and `releasing.md`. Do not invent flags.

Completion requires green tests, ShellCheck, editorconfig, Bash 3.2 compatibility,
mode coverage, and the relevant documentation updates.

## Skills

Use `/name` in Claude or `$name` in Codex. Skill references below use Claude's
spelling; use the same name with `$` in Codex.

- `/tdd-cycle`: one failing-test, implementation, and refactoring cycle.
- `/fix-test`: debug failing tests.
- `/add-command`: add a public lifecycle command with TDD.
- `/doctor-check`: audit coverage and doctor behavior.
- `/pre-release` and `/release`: validate and run the release script.
- `/commit` and `/pr`: commit and open a pull request.
- `/bashdep-gh-issue <N>`: take an issue through implementation to a PR.

## Git

Use `<type>(<scope>): <description>` conventional commits.
Types: `feat`, `fix`, `docs`, `style`, `refactor`, `test`, `chore`, `perf`, `ci`.
Scopes: `install`, `lock`, `doctor`, `clean`, `uninstall`, `setup`, `cli`, `docs`,
`ci`, `release`. Do not mention AI, Claude, or automation in commit messages.

Never commit secrets or `.env` contents. Never skip hooks or amend published
commits. Force-pushing `main` and destructive commands (`reset --hard`, `clean -f`,
`branch -D`) require an explicit request. Push only with user authorization.
Release only through `/release`, with explicit confirmation.
