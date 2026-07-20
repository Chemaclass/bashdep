# Releasing

bashdep ships a single `bashdep` script. Releases are git tags + a
GitHub release with two downloadable assets: the `bashdep` script and a
`checksum` (sha256) to verify it. The whole flow is automated by
`release.sh`.

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

1. Validates the version is semver and greater than the current, that the
    required tooling is present (`git`, `awk`, `sed`, `make`, `shellcheck`,
    `ec`, `shasum`/`sha256sum`, and `gh` unless `--no-gh`), that you're on
    `main` with a clean tree, that the tag doesn't exist, and that
    `[Unreleased]` actually has content to ship.
2. Bumps `BASHDEP_VERSION` in the `bashdep` script.
3. Rolls `CHANGELOG.md`: renames `[Unreleased]` to `[X.Y.Z] - YYYY-MM-DD`,
    adds a fresh empty `[Unreleased]` section, and refreshes the compare
    links at the bottom.
4. Runs `make test sa lint` as a release gate.
5. **Builds the asset** into `dist/`: copies the bumped `bashdep`,
    syntax-checks it with `bash -n`, and writes a sha256 `checksum`.
6. Commits with `chore(release): X.Y.Z` and tags `X.Y.Z`.
7. Pushes the commit and tag to the remote.
8. Creates the GitHub release via `gh release create`, uploads `bashdep`
    + `checksum`, and verifies both assets attached.

The release URL is printed at the end. If any step **before the commit**
fails, the script auto-reverts the file mutations and removes `dist/`;
after the commit it prints the exact recovery command instead.

The `dist/` build directory is git-ignored — it is a release artifact,
not source.

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

Optionally verify the download against the published `checksum` asset:

```bash
curl -fsSLO https://github.com/Chemaclass/bashdep/releases/download/0.4.0/checksum
( cd lib && shasum -a 256 -c ../checksum )   # or: sha256sum -c
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
