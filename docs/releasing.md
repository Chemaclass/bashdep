# Releasing

bashdep ships a single `bashdep` script. Releases are git tags + a
GitHub release with the `bashdep` script attached as a downloadable
asset. The whole flow is automated by `release.sh`.

## Cutting a release

Prerequisites:

- On `main`, working tree clean.
- `gh` CLI authenticated (`gh auth status`).
- ShellCheck and editorconfig-checker installed (release script gates
  on them).

By default, the script auto-bumps the **minor** version (e.g. `0.3.0` →
`0.4.0`). Pass an explicit version to override, or use `--major` /
`--patch` for a different bump level.

Preview first (idempotent — touches nothing):

```bash
./release.sh --dry-run               # auto-bump minor
./release.sh --patch --dry-run       # auto-bump patch
./release.sh 0.4.0 --dry-run         # explicit version
make release/dry-run                 # via make
```

When happy, run for real:

```bash
./release.sh                         # auto-bump minor (default)
./release.sh --major                 # auto-bump major
./release.sh 0.4.0                   # explicit
make release                         # via make
make release 0.4.0                   # via make, explicit
```

The script:

1. Validates the version is semver and greater than the current.
2. Confirms you're on `main` with a clean tree, and the tag doesn't exist.
3. Bumps `BASHDEP_VERSION` in the `bashdep` script.
4. Rolls `CHANGELOG.md`: renames `[Unreleased]` to `[X.Y.Z] - YYYY-MM-DD`,
    adds a fresh empty `[Unreleased]` section, and refreshes the compare
    links at the bottom.
5. Runs `make test sa lint` as a release gate.
6. Commits with `chore(release): X.Y.Z` and tags `X.Y.Z`.
7. Pushes the commit and tag to the remote.
8. Creates the GitHub release via `gh release create` and attaches the
    `bashdep` script as a downloadable asset.

The release URL is printed at the end.

## Flags

| Flag             | Effect                                                      |
| ---------------- | ----------------------------------------------------------- |
| `--major`        | Auto-bump major (X.Y.Z → X+1.0.0). Ignored if version given. |
| `--minor`        | Auto-bump minor (the default; explicit form).               |
| `--patch`        | Auto-bump patch (X.Y.Z → X.Y.Z+1). Ignored if version given. |
| `--dry-run`      | Preview every step. No file/git/network changes.            |
| `--force`        | Skip the interactive `Release X.Y.Z?` confirmation.         |
| `--no-gh`        | Skip the GitHub release step (still pushes commit + tag).   |
| `--remote=NAME`  | Push to a remote other than `origin`.                       |

CI mode (no prompts, no `gh` step):

```bash
./release.sh 0.4.0 --force --no-gh
```

## After the release

Consumers install via:

```bash
curl -fsSLo lib/bashdep https://github.com/Chemaclass/bashdep/releases/download/0.4.0/bashdep
chmod +x lib/bashdep
```

Or stay on `main`:

```bash
curl -fsSLo lib/bashdep https://raw.githubusercontent.com/Chemaclass/bashdep/main/bashdep
```

Existing installs can self-refresh:

```bash
bashdep::self_update 0.4.0
```

## Hotfix

If a release needs a fix:

1. Branch from the tag: `git checkout -b hotfix/0.4.1 0.4.0`.
2. Apply the fix, open a PR, merge to `main`.
3. Run `./release.sh 0.4.1` from `main`.
