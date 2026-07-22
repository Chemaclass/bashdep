#!/bin/bash
#
# Release automation for bashdep.
#
# Usage:
#   ./release.sh <version> [--dry-run] [--force] [--no-gh] [--remote=NAME]
#
# What it does:
#   1. Validate semver, tooling, working-tree state, and CHANGELOG content.
#   2. Bump BASHDEP_VERSION in the bashdep script.
#   3. Roll the CHANGELOG: rename [Unreleased] → [X.Y.Z] - YYYY-MM-DD,
#      add a new empty Unreleased section, refresh compare links.
#   4. Run make test / sa / lint as a release gate.
#   5. Build the release asset into dist/: copy the bumped bashdep,
#      syntax-check it (bash -n), and write a sha256 checksum.
#   6. Commit and tag the release.
#   7. Push commit + tag to origin.
#   8. Create a GitHub release, upload bashdep + checksum, and verify
#      both assets attached.
#
# On failure before the commit, staged file mutations and dist/ are
# reverted automatically; after the commit, recovery steps are printed.
#
# Flags:
#   --dry-run     Preview every step. No file/git/network mutations.
#   --force       Skip interactive confirmation.
#   --no-gh       Skip the GitHub release step (still pushes commit + tag).
#   --remote=NAME Push to NAME instead of origin.
#

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

readonly REPO_PATH="Chemaclass/bashdep"
readonly REPO_URL="https://github.com/${REPO_PATH}"
readonly RELEASE_ASSET="bashdep"
readonly DIST_DIR="dist"
readonly CHECKSUM_FILE="checksum"
readonly MAIN_BRANCH="main"

# Tracks how far the release has progressed so the cleanup trap knows
# whether it is safe to auto-revert (before commit) or must only advise
# (after commit/push). Values: init | mutated | committed | pushed | done.
STAGE="init"

VERSION=""
BUMP_LEVEL="minor"
DRY_RUN=false
FORCE=false
WITH_GH_RELEASE=true
TRUST_CI=false
REMOTE="origin"

# --- Output helpers ----------------------------------------------------------

if [[ -t 1 ]]; then
  RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
  BLUE='\033[0;34m'; BOLD='\033[1m'; NC='\033[0m'
else
  RED=''; GREEN=''; YELLOW=''; BLUE=''; BOLD=''; NC=''
fi

log()    { printf '%b%s%b\n' "$BLUE"   "==> $*" "$NC"; }
ok()     { printf '%b%s%b\n' "$GREEN"  "  ✓ $*" "$NC"; }
warn()   { printf '%b%s%b\n' "$YELLOW" "  ! $*" "$NC" >&2; }
err()    { printf '%b%s%b\n' "$RED"    "  ✗ $*" "$NC" >&2; }
plan()   { printf '%b%s%b\n' "$YELLOW" "  · would $*" "$NC"; }
done_ok() { $DRY_RUN || ok "$*"; }

run() {
  if $DRY_RUN; then
    plan "$*"
  else
    "$@"
  fi
}

# Print the SHA-256 of a file as "<hash>  <basename>", portable across
# macOS (shasum) and Linux (sha256sum). Runs from the file's directory so
# the recorded name is the bare basename, not a path.
sha256_of() {
  local path=$1
  local base="${path##*/}"
  local dir="${path%/*}"
  [[ "$dir" == "$path" ]] && dir="."
  if command -v shasum >/dev/null 2>&1; then
    ( cd "$dir" && shasum -a 256 "$base" )
  else
    ( cd "$dir" && sha256sum "$base" )
  fi
}

# Return 0 when the [Unreleased] section has at least one non-blank,
# non-heading line — i.e. there is something to release.
unreleased_has_content() {
  awk '
    /^## \[Unreleased\]/ { in_section = 1; next }
    /^## \[/            { in_section = 0 }
    in_section && /^###/ { next }
    in_section && NF     { found = 1 }
    END                  { exit found ? 0 : 1 }
  ' CHANGELOG.md
}

# --- CLI parsing -------------------------------------------------------------

usage() {
  cat <<EOF
Usage: ./release.sh [version] [options]

Arguments:
  version       Target semver (e.g. 0.4.0). Optional — when omitted,
                auto-bumps the minor of the current BASHDEP_VERSION
                (e.g. 0.3.0 → 0.4.0; patch resets to 0).

Options:
  --major       Auto-bump the major instead of minor (X.Y.Z → X+1.0.0).
                Ignored when an explicit version is given.
  --patch       Auto-bump the patch instead of minor (X.Y.Z → X.Y.Z+1).
                Ignored when an explicit version is given.
  --dry-run     Preview every step without mutating files, git, or network.
  --force       Skip interactive confirmation.
  --no-gh       Skip the GitHub release step.
  --trust-ci    Skip the local test/sa/lint gate when HEAD already has a
                green CI run (requires gh). Falls back to running it.
  --remote=NAME Push to a remote other than origin.
  -h, --help    Show this help.

Examples:
  ./release.sh                       # auto-bump minor (default)
  ./release.sh --patch               # auto-bump patch
  ./release.sh --major --dry-run     # preview a major bump
  ./release.sh 0.4.0                 # explicit version, interactive
  ./release.sh 0.4.0 --force         # explicit, CI / non-interactive
EOF
}

parse_args() {
  while [[ $# -gt 0 ]]; do
    case $1 in
      -h|--help) usage; exit 0 ;;
      --major)   BUMP_LEVEL="major" ;;
      --minor)   BUMP_LEVEL="minor" ;;
      --patch)   BUMP_LEVEL="patch" ;;
      --dry-run) DRY_RUN=true ;;
      --force)   FORCE=true ;;
      --no-gh)   WITH_GH_RELEASE=false ;;
      --trust-ci) TRUST_CI=true ;;
      --remote=*) REMOTE="${1#*=}" ;;
      -*)        err "Unknown flag: $1"; usage >&2; exit 1 ;;
      *)
        if [[ -z "$VERSION" ]]; then
          VERSION="$1"
        else
          err "Too many positional args (got '$1')."; exit 1
        fi
        ;;
    esac
    shift
  done

  if [[ -n "$VERSION" ]] && ! [[ "$VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+(-[0-9A-Za-z.-]+)?$ ]]; then
    err "Invalid semver: '$VERSION'."
    exit 1
  fi
}

# Compute next version from a current X.Y.Z given a bump level.
# Echoes the new version on stdout.
bump_version_string() {
  local current=$1 level=$2
  local major minor patch
  IFS='.' read -r major minor patch <<<"$current"
  case $level in
    major) printf '%s.0.0\n'   "$((major + 1))" ;;
    minor) printf '%s.%s.0\n'  "$major" "$((minor + 1))" ;;
    patch) printf '%s.%s.%s\n' "$major" "$minor" "$((patch + 1))" ;;
    *)     err "Unknown bump level: $level"; return 1 ;;
  esac
}

# --- Pre-flight checks -------------------------------------------------------

require_cmd() {
  command -v "$1" >/dev/null 2>&1 || { err "Required command not found: $1"; exit 1; }
}

# Like require_cmd, but in --dry-run a missing command only warns — dry-run
# never actually runs the gates or touches the network, so previewing must
# not depend on the full release toolchain being installed.
require_cmd_soft() {
  command -v "$1" >/dev/null 2>&1 && return 0
  if $DRY_RUN; then
    warn "missing '$1' — allowed in --dry-run"
  else
    err "Required command not found: $1"
    exit 1
  fi
}

preflight() {
  log "Pre-flight checks"

  require_cmd git
  require_cmd awk
  require_cmd sed
  # Gate + build tools — checked up front so a missing one fails before any
  # file is mutated, not halfway through run_gates. Soft in dry-run, which
  # neither runs the gates nor builds.
  require_cmd_soft make
  require_cmd_soft shellcheck
  require_cmd_soft ec
  if ! command -v shasum >/dev/null 2>&1 && ! command -v sha256sum >/dev/null 2>&1; then
    if $DRY_RUN; then
      warn "missing 'shasum'/'sha256sum' — allowed in --dry-run"
    else
      err "Need 'shasum' or 'sha256sum' to checksum the release asset."
      exit 1
    fi
  fi
  if $WITH_GH_RELEASE || $TRUST_CI; then require_cmd gh; fi
  ok "required commands present"

  local branch
  branch=$(git rev-parse --abbrev-ref HEAD)
  if [[ "$branch" != "$MAIN_BRANCH" ]]; then
    if $DRY_RUN; then
      warn "not on $MAIN_BRANCH (current: '$branch') — allowed in --dry-run"
    else
      err "Releases must be cut from '$MAIN_BRANCH' (current: '$branch')."
      exit 1
    fi
  else
    ok "on $MAIN_BRANCH"
  fi

  if [[ -n "$(git status --porcelain)" ]]; then
    if $DRY_RUN; then
      warn "working tree dirty — allowed in --dry-run"
    else
      err "Working tree is dirty. Commit or stash first."
      git status --short >&2
      exit 1
    fi
  else
    ok "working tree clean"
  fi

  local current
  current=$(grep -E '^BASHDEP_VERSION=' bashdep | head -1 | sed -E 's/^BASHDEP_VERSION="([^"]+)"$/\1/')
  if [[ -z "$current" ]]; then
    err "Could not read current BASHDEP_VERSION from 'bashdep'."
    exit 1
  fi
  PREVIOUS_VERSION="$current"

  if [[ -z "$VERSION" ]]; then
    if ! [[ "$current" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
      err "Auto-bump requires the current version to be plain X.Y.Z (got '$current'). Pass an explicit version."
      exit 1
    fi
    VERSION=$(bump_version_string "$current" "$BUMP_LEVEL")
    ok "auto-bumped $BUMP_LEVEL: $current → $VERSION"
  fi

  if [[ "$current" == "$VERSION" ]]; then
    err "BASHDEP_VERSION is already '$VERSION'. Choose a higher version."
    exit 1
  fi

  if git rev-parse "$VERSION" >/dev/null 2>&1; then
    err "Tag '$VERSION' already exists."
    exit 1
  fi
  ok "tag $VERSION does not exist"

  ok "current version: $PREVIOUS_VERSION → new version: $VERSION"

  if ! grep -q '^## \[Unreleased\]' CHANGELOG.md; then
    err "CHANGELOG.md has no '[Unreleased]' section to roll."
    exit 1
  fi
  if ! unreleased_has_content; then
    err "CHANGELOG '[Unreleased]' section is empty — nothing to release."
    exit 1
  fi
  ok "CHANGELOG [Unreleased] has content"
}

confirm() {
  if $FORCE || $DRY_RUN; then return 0; fi
  printf '%bRelease %s? [y/N] %b' "$BOLD" "$VERSION" "$NC"
  local ans
  read -r ans
  case "$ans" in y|Y|yes|YES) return 0 ;; *) err "Aborted."; exit 1 ;; esac
}

# --- Mutations ---------------------------------------------------------------

bump_version() {
  log "Bump BASHDEP_VERSION → $VERSION"
  if $DRY_RUN; then
    plan "sed bashdep BASHDEP_VERSION=$PREVIOUS_VERSION → $VERSION"
    return
  fi
  STAGE="mutated"
  sed -i.bak -E "s/^BASHDEP_VERSION=\"[^\"]+\"$/BASHDEP_VERSION=\"$VERSION\"/" bashdep
  rm -f bashdep.bak
  if ! grep -q "BASHDEP_VERSION=\"$VERSION\"" bashdep; then
    err "Failed to bump BASHDEP_VERSION."
    exit 1
  fi
  done_ok "bashdep version bumped"
}

roll_changelog() {
  log "Roll CHANGELOG"
  local today
  today=$(date +%Y-%m-%d)

  if $DRY_RUN; then
    plan "rename [Unreleased] → [$VERSION] - $today, add new empty [Unreleased]"
    plan "refresh compare links: Unreleased…HEAD against $VERSION"
    plan "add [$VERSION]: …compare/$PREVIOUS_VERSION...$VERSION"
    return
  fi

  local tmp
  tmp=$(mktemp)
  awk -v ver="$VERSION" -v date="$today" '
    /^## \[Unreleased\]/ {
      print "## [Unreleased]"
      print ""
      print "### Added"
      print ""
      print "### Changed"
      print ""
      print "### Fixed"
      print ""
      print "## [" ver "] - " date
      next
    }
    { print }
  ' CHANGELOG.md > "$tmp"
  mv "$tmp" CHANGELOG.md

  awk -v ver="$VERSION" -v prev="$PREVIOUS_VERSION" -v repo="$REPO_URL" '
    /^\[Unreleased\]:/ {
      print "[Unreleased]: " repo "/compare/" ver "...HEAD"
      print "[" ver "]: " repo "/compare/" prev "..." ver
      next
    }
    { print }
  ' CHANGELOG.md > "$tmp"
  mv "$tmp" CHANGELOG.md

  done_ok "CHANGELOG rolled (Unreleased → $VERSION on $today)"
}

# Print the combined check-runs conclusion for the current HEAD commit:
# "success", "failure", "pending", or "none" (no checks / lookup failed).
ci_head_conclusion() {
  local sha
  sha=$(git rev-parse HEAD)
  gh api "repos/$REPO_PATH/commits/$sha/check-runs" --jq '
    def ok: .conclusion == "success" or .conclusion == "skipped" or .conclusion == "neutral";
    if (.check_runs | length) == 0 then "none"
    elif any(.check_runs[]; .status != "completed") then "pending"
    elif all(.check_runs[]; ok) then "success"
    else "failure" end' 2>/dev/null || echo "none"
}

# Return 0 when --trust-ci was passed and HEAD already has a green CI run,
# so the local gates can be safely skipped.
should_skip_gates() {
  $TRUST_CI || return 1
  [[ "$(ci_head_conclusion)" == "success" ]]
}

run_gates() {
  log "Run release gates (test + sa + lint)"
  if $DRY_RUN; then
    plan "make test sa lint (unless --trust-ci and HEAD is green)"
    return
  fi
  if should_skip_gates; then
    ok "trusting green CI on HEAD — skipping local gates"
    return
  fi
  make test >/dev/null
  done_ok "tests pass"
  make sa >/dev/null
  done_ok "shellcheck pass"
  make lint >/dev/null
  done_ok "editorconfig pass"
}

# Stage the release asset into $DIST_DIR: copy the (already version-bumped)
# bashdep script, syntax-check it, and write a sha256 checksum alongside.
# Both files are uploaded to the GitHub release. Honors dry-run.
build_asset() {
  log "Build release asset"
  local out="$DIST_DIR/$RELEASE_ASSET"
  if $DRY_RUN; then
    plan "stage $RELEASE_ASSET → $out, bash -n, write $DIST_DIR/$CHECKSUM_FILE"
    return
  fi

  rm -rf "$DIST_DIR"
  mkdir -p "$DIST_DIR"
  cp "$RELEASE_ASSET" "$out"
  chmod +x "$out"

  if ! bash -n "$out"; then
    err "Built asset failed 'bash -n' syntax check: $out"
    exit 1
  fi
  done_ok "asset syntax valid"

  sha256_of "$out" > "$DIST_DIR/$CHECKSUM_FILE"
  done_ok "checksum written ($DIST_DIR/$CHECKSUM_FILE)"
}

commit_and_tag() {
  log "Commit + tag"
  run git add bashdep CHANGELOG.md
  run git commit -m "chore(release): $VERSION"
  run git tag -a "$VERSION" -m "Release $VERSION"
  STAGE="committed"
  done_ok "committed and tagged $VERSION"
}

push() {
  log "Push to $REMOTE"
  run git push "$REMOTE" "$MAIN_BRANCH"
  run git push "$REMOTE" "$VERSION"
  STAGE="pushed"
  done_ok "pushed branch + tag"
}

create_gh_release() {
  if ! $WITH_GH_RELEASE; then
    warn "Skipping GitHub release step (--no-gh)"
    return
  fi
  log "Create GitHub release + attach assets"
  local asset="$DIST_DIR/$RELEASE_ASSET"
  local checksum="$DIST_DIR/$CHECKSUM_FILE"
  local notes_url="$REPO_URL/blob/$VERSION/CHANGELOG.md"
  local body
  body="See [CHANGELOG.md]($notes_url) for the full notes.

## Install
\`\`\`bash
curl -fsSLo lib/bashdep $REPO_URL/releases/download/$VERSION/$RELEASE_ASSET
chmod +x lib/bashdep
\`\`\`

Verify with the attached \`$CHECKSUM_FILE\`."
  if $DRY_RUN; then
    plan "gh release create $VERSION --title 'Release $VERSION' --notes <generated> $asset $checksum"
    return
  fi
  gh release create "$VERSION" \
    --repo "$REPO_PATH" \
    --title "Release $VERSION" \
    --notes "$body" \
    "$asset" "$checksum"
  done_ok "GitHub release created"

  # Verify both assets actually attached (guards against a partial upload).
  local attached
  attached=$(gh release view "$VERSION" --repo "$REPO_PATH" \
    --json assets --jq '.assets[].name' 2>/dev/null || true)
  local name
  for name in "$RELEASE_ASSET" "$CHECKSUM_FILE"; do
    case $'\n'"$attached"$'\n' in
      *$'\n'"$name"$'\n'*) ok "asset attached: $name" ;;
      *) err "asset '$name' missing from release $VERSION"; exit 1 ;;
    esac
  done
}

# --- Main --------------------------------------------------------------------

# On unexpected exit, undo work that is safe to undo. Before the commit we
# own the file mutations and the dist/ dir, so revert them. After the commit
# the state is on disk (and maybe pushed), so only advise — never rewrite
# history automatically.
cleanup() {
  local code=$?
  [[ $code -eq 0 ]] && return 0
  $DRY_RUN && return 0
  case $STAGE in
    mutated)
      warn "release failed after mutating files — reverting"
      git checkout -- bashdep CHANGELOG.md 2>/dev/null || true
      rm -rf "$DIST_DIR"
      ;;
    committed)
      warn "release failed after commit/tag — undo with:"
      warn "  git reset --hard HEAD~1 && git tag -d $VERSION"
      ;;
    pushed)
      warn "release failed after push — the tag is on $REMOTE."
      warn "  finish manually or delete the remote tag to retry."
      ;;
  esac
}

main() {
  cd "$SCRIPT_DIR"
  parse_args "$@"
  preflight

  if $DRY_RUN; then
    log "DRY RUN — no changes will be made"
  fi

  confirm
  trap cleanup EXIT

  bump_version
  roll_changelog
  run_gates
  build_asset
  commit_and_tag
  push
  create_gh_release

  STAGE="done"
  log "Done."
  done_ok "Release $VERSION published."
  if ! $DRY_RUN; then
    printf '%b%s%b %s\n' "$BLUE" "==>" "$NC" "$REPO_URL/releases/tag/$VERSION"
  fi
}

# Run only when executed directly; sourcing (e.g. from tests) exposes the
# functions without side effects.
if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
  main "$@"
fi
