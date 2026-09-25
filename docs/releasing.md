# Releasing

bashdep ships a single `bashdep` script. Releases are git tags + a GitHub release with two downloadable assets: the `bashdep` script and a `checksum` (sha256) to verify it. The whole flow is automated by `release.sh`.

The root `release.sh` is a thin wrapper around the reusable, project-agnostic engine in [`templates/release.sh`](../templates/release.sh). [`release.conf`](../release.conf) supplies the version, gate, assets, and release notes. bashdep uses the same template it offers other projects. See [templates/README.md](../templates/README.md) to use it in your own repo.

## Cutting a release

Prerequisites:

- On `main`, working tree clean.
- `gh` CLI authenticated (`gh auth status`).
- ShellCheck and editorconfig-checker installed (release script gates on them).

By default, the script increments the **minor** version and resets the patch number. Pass an explicit version to override it, or use `--major` / `--patch` for a different bump level.

Run the local gate and preview the release before cutting it:

```bash
make release/check                   # test, ShellCheck, lint, then preview
```

Pass a target version after the command to preview an explicit version, for example `make release/check 1.2.3`.

For a quick preview without running the gate, use `./release.sh --dry-run` or `make release/dry-run`. Dry-run checks the local tag and changelog but skips tests, static analysis, and lint. It warns if the working tree is dirty. A release requires a clean tree on `main`.

When the checks pass, run for real:

```bash
./release.sh                         # auto-bump minor (default)
./release.sh --major                 # auto-bump major
make release                         # via make
```

To choose a version, pass it as the first argument: `./release.sh 1.2.3` or `make release 1.2.3`.

The script:

1. Validates the version is semver and greater than the current, that the
    engine's own tooling is present (`git`, `awk`, and `gh` unless
    `--no-gh`), that you're on `main` with a clean tree, that the tag
    doesn't exist, and that `[Unreleased]` actually has content to ship.
    bashdep's gate (`make test sa lint`, from `release.conf`) additionally
    needs `make`, `shellcheck`, and `ec`; the checksum step needs
    `shasum`/`sha256sum`.
2. Bumps `BASHDEP_VERSION` in the `bashdep` script (via the config's
    `release_version_write`).
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

The release URL is printed at the end. If any step **before the commit** fails, the script auto-reverts the file mutations and removes `dist/`; after the commit it prints the exact recovery command instead.

The `dist/` build directory is git-ignored. It holds release assets.

## Flags

| Flag             | Effect                                                      |
| ---------------- | ----------------------------------------------------------- |
| `--major`        | Auto-bump major (X.Y.Z → X+1.0.0). Ignored if version given. |
| `--minor`        | Auto-bump minor (the default; explicit form).               |
| `--patch`        | Auto-bump patch (X.Y.Z → X.Y.Z+1). Ignored if version given. |
| `--dry-run`      | Preview every step without changes. Skips the release gate.  |
| `--force`        | Skip the interactive `Release X.Y.Z?` confirmation.         |
| `--no-gh`        | Skip the GitHub release step (still pushes commit + tag).   |
| `--trust-ci`     | Skip the local `test/sa/lint` gate when HEAD already has a green CI run (needs `gh`); otherwise runs the gate. |
| `--remote=NAME`  | Push to a remote other than `origin`.                       |

CI mode (no prompts, no `gh` step), with `NEXT_VERSION` set to the target version:

```bash
./release.sh "$NEXT_VERSION" --force --no-gh
```

## After the release

Consumers install via:

```bash
curl -fsSLo lib/bashdep https://github.com/Chemaclass/bashdep/releases/download/0.10.0/bashdep
chmod +x lib/bashdep
```

Optionally verify the download against the published `checksum` asset:

```bash
curl -fsSLO https://github.com/Chemaclass/bashdep/releases/download/0.10.0/checksum
( cd lib && shasum -a 256 -c ../checksum )   # or: sha256sum -c
```

Or stay on `main`:

```bash
curl -fsSLo lib/bashdep https://raw.githubusercontent.com/Chemaclass/bashdep/main/bashdep
```

Existing installs can self-refresh:

```bash
bashdep::self_update 0.10.0
```

## Hotfix

If a release needs a fix:

1. Branch from the tag: `git checkout -b hotfix/0.10.1 0.10.0`.
2. Apply the fix, open a PR, merge to `main`.
3. Run `./release.sh 0.10.1` from `main`.
