#!/bin/bash
#
# Release automation for bashdep.
#
# Usage:
#   ./release.sh <version> [--dry-run] [--force] [--no-gh] [--remote=NAME]
#
# What it does:
#   1. Validate semver and working-tree state.
#   2. Bump BASHDEP_VERSION in the bashdep script.
#   3. Roll the CHANGELOG: rename [Unreleased] → [X.Y.Z] - YYYY-MM-DD,
#      add a new empty Unreleased section, refresh compare links.
#   4. Run make test / sa / lint as a release gate.
#   5. Commit and tag the release.
#   6. Push commit + tag to origin.
#   7. Create a GitHub release with the bashdep script attached as an asset.
#
# Flags:
#   --dry-run     Preview every step. No file/git/network mutations.
#   --force       Skip interactive confirmation.
#   --no-gh       Skip the GitHub release step (still pushes commit + tag).
#   --remote=NAME Push to NAME instead of origin.
#

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

readonly REPO_PATH="Chemaclass/bashdep"
readonly REPO_URL="https://github.com/${REPO_PATH}"
readonly RELEASE_ASSET="bashdep"
readonly MAIN_BRANCH="main"

VERSION=""
DRY_RUN=false
FORCE=false
WITH_GH_RELEASE=true
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

# --- CLI parsing -------------------------------------------------------------

usage() {
  cat <<EOF
Usage: ./release.sh <version> [options]

Arguments:
  version       Target semver (e.g. 0.4.0). Required.

Options:
  --dry-run     Preview every step without mutating files, git, or network.
  --force       Skip interactive confirmation.
  --no-gh       Skip the GitHub release step.
  --remote=NAME Push to a remote other than origin.
  -h, --help    Show this help.

Examples:
  ./release.sh 0.4.0                 # interactive release
  ./release.sh 0.4.0 --dry-run       # preview only
  ./release.sh 0.4.0 --force         # CI / non-interactive
EOF
}

parse_args() {
  while [[ $# -gt 0 ]]; do
    case $1 in
      -h|--help) usage; exit 0 ;;
      --dry-run) DRY_RUN=true ;;
      --force)   FORCE=true ;;
      --no-gh)   WITH_GH_RELEASE=false ;;
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

  if [[ -z "$VERSION" ]]; then
    err "Missing required <version>."
    usage >&2
    exit 1
  fi

  if ! [[ "$VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+(-[0-9A-Za-z.-]+)?$ ]]; then
    err "Invalid semver: '$VERSION'."
    exit 1
  fi
}

# --- Pre-flight checks -------------------------------------------------------

require_cmd() {
  command -v "$1" >/dev/null 2>&1 || { err "Required command not found: $1"; exit 1; }
}

preflight() {
  log "Pre-flight checks"

  require_cmd git
  require_cmd awk
  require_cmd sed
  if $WITH_GH_RELEASE; then require_cmd gh; fi
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

  if git rev-parse "$VERSION" >/dev/null 2>&1; then
    err "Tag '$VERSION' already exists."
    exit 1
  fi
  ok "tag $VERSION does not exist"

  local current
  current=$(grep -E '^BASHDEP_VERSION=' bashdep | head -1 | sed -E 's/^BASHDEP_VERSION="([^"]+)"$/\1/')
  if [[ -z "$current" ]]; then
    err "Could not read current BASHDEP_VERSION from 'bashdep'."
    exit 1
  fi
  if [[ "$current" == "$VERSION" ]]; then
    err "BASHDEP_VERSION is already '$VERSION'. Choose a higher version."
    exit 1
  fi
  PREVIOUS_VERSION="$current"
  ok "current version: $PREVIOUS_VERSION → new version: $VERSION"

  if ! grep -q '^## \[Unreleased\]' CHANGELOG.md; then
    err "CHANGELOG.md has no '[Unreleased]' section to roll."
    exit 1
  fi
  ok "CHANGELOG has [Unreleased] section"
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

run_gates() {
  log "Run release gates (test + sa + lint)"
  if $DRY_RUN; then
    plan "make test sa lint"
    return
  fi
  make test >/dev/null
  done_ok "tests pass"
  make sa >/dev/null
  done_ok "shellcheck pass"
  make lint >/dev/null
  done_ok "editorconfig pass"
}

commit_and_tag() {
  log "Commit + tag"
  run git add bashdep CHANGELOG.md
  run git commit -m "chore(release): $VERSION"
  run git tag -a "$VERSION" -m "Release $VERSION"
  done_ok "committed and tagged $VERSION"
}

push() {
  log "Push to $REMOTE"
  run git push "$REMOTE" "$MAIN_BRANCH"
  run git push "$REMOTE" "$VERSION"
  done_ok "pushed branch + tag"
}

create_gh_release() {
  if ! $WITH_GH_RELEASE; then
    warn "Skipping GitHub release step (--no-gh)"
    return
  fi
  log "Create GitHub release + attach asset"
  local notes_url="$REPO_URL/blob/$VERSION/CHANGELOG.md"
  local body
  body="See [CHANGELOG.md]($notes_url) for the full notes.

## Install
\`\`\`bash
curl -fsSLo lib/bashdep $REPO_URL/releases/download/$VERSION/$RELEASE_ASSET
chmod +x lib/bashdep
\`\`\`"
  if $DRY_RUN; then
    plan "gh release create $VERSION --title 'Release $VERSION' --notes <generated> $RELEASE_ASSET"
    return
  fi
  gh release create "$VERSION" \
    --repo "$REPO_PATH" \
    --title "Release $VERSION" \
    --notes "$body" \
    "$RELEASE_ASSET"
  done_ok "GitHub release created with $RELEASE_ASSET attached"
}

# --- Main --------------------------------------------------------------------

main() {
  parse_args "$@"
  preflight

  if $DRY_RUN; then
    log "DRY RUN — no changes will be made"
  fi

  confirm

  bump_version
  roll_changelog
  run_gates
  commit_and_tag
  push
  create_gh_release

  log "Done."
  done_ok "Release $VERSION published."
  if ! $DRY_RUN; then
    printf '%b%s%b %s\n' "$BLUE" "==>" "$NC" "$REPO_URL/releases/tag/$VERSION"
  fi
}

main "$@"
