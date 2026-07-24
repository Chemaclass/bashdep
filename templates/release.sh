#!/bin/bash
#
# Generic release automation for a single-repo project, optimized for
# GitHub. One command cuts a tagged release:
#
#   validate → bump version → roll CHANGELOG → gate → build asset(s) →
#   commit + tag → push → create GitHub release + upload assets (verified).
#
# This is a reusable TEMPLATE. All project-specific bits live in a small
# config file (default: ./release.conf) that you provide; this script
# stays untouched. Copy this file plus release.conf.example into your
# repo, fill in the config, and run it. See templates/README.md.
#
# Usage (run from the repo root):
#   ./release.sh [version] [--major|--minor|--patch] [--dry-run] \
#                [--force] [--no-gh] [--trust-ci] [--remote=NAME] \
#                [--config=FILE]
#
# On failure before the commit, staged file mutations and the build dir
# are reverted automatically; after the commit, recovery steps are printed.
#

set -euo pipefail

# --- Config (populated by load_config from the config file) ------------------
CONFIG_FILE=""
REPO_PATH=""
REPO_URL=""
MAIN_BRANCH="main"
DIST_DIR="dist"
GATE_CMD="make test"
CHANGELOG_FILE="CHANGELOG.md"
ASSETS=()
COMMIT_PATHS=()

# --- Runtime state -----------------------------------------------------------
# STAGE tracks how far the release has progressed so the cleanup trap knows
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
PREVIOUS_VERSION=""

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
# the recorded name is the bare basename, not a path. Exposed for config
# release_build functions to checksum their assets.
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

# Return 0 when the [Unreleased] section of $CHANGELOG_FILE has at least
# one non-blank, non-heading line — i.e. there is something to release.
unreleased_has_content() {
  awk '
    /^## \[Unreleased\]/ { in_section = 1; next }
    /^## \[/            { in_section = 0 }
    in_section && /^###/ { next }
    in_section && NF     { found = 1 }
    END                  { exit found ? 0 : 1 }
  ' "${CHANGELOG_FILE:-CHANGELOG.md}"
}

# --- CLI parsing -------------------------------------------------------------

usage() {
  cat <<EOF
Usage: ./release.sh [version] [options]

Arguments:
  version       Target semver (e.g. 0.4.0). Optional — when omitted,
                auto-bumps the minor of the current version (e.g.
                0.3.0 → 0.4.0; patch resets to 0).

Options:
  --major       Auto-bump the major instead of minor (X.Y.Z → X+1.0.0).
                Ignored when an explicit version is given.
  --patch       Auto-bump the patch instead of minor (X.Y.Z → X.Y.Z+1).
                Ignored when an explicit version is given.
  --dry-run     Preview every step without mutating files, git, or network.
  --force       Skip interactive confirmation.
  --no-gh       Skip the GitHub release step.
  --trust-ci    Skip the local gate when HEAD already has a green CI run
                (requires gh). Falls back to running the gate.
  --remote=NAME Push to a remote other than origin.
  --config=FILE Config file to load (default: \$RELEASE_CONF or ./release.conf).
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
      --config=*) CONFIG_FILE="${1#*=}" ;;
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

# --- Config loading ----------------------------------------------------------

# Derive "owner/repo" from the configured remote's URL. Handles both
# git@host:owner/repo(.git) and https://host/owner/repo(.git).
derive_repo() {
  local url
  url=$(git remote get-url "$REMOTE" 2>/dev/null) || return 1
  url="${url%.git}"
  case $url in
    *://*) url="${url#*://}"; printf '%s\n' "${url#*/}" ;;
    *:*)   printf '%s\n' "${url#*:}" ;;
    *)     return 1 ;;
  esac
}

# Source the config file and derive internal settings. Validates the two
# mandatory hooks (release_version_read / release_version_write) and the
# mandatory RELEASE_COMMIT_PATHS list.
load_config() {
  local cfg="${CONFIG_FILE:-${RELEASE_CONF:-release.conf}}"
  if [[ ! -f "$cfg" ]]; then
    err "Config file not found: '$cfg' (see templates/release.conf.example)."
    exit 1
  fi
  # shellcheck disable=SC1090
  source "$cfg"

  declare -f release_version_read >/dev/null 2>&1 || {
    err "config '$cfg' must define release_version_read()."; exit 1; }
  declare -f release_version_write >/dev/null 2>&1 || {
    err "config '$cfg' must define release_version_write()."; exit 1; }
  if [[ "${RELEASE_COMMIT_PATHS+set}" != set || ${#RELEASE_COMMIT_PATHS[@]} -eq 0 ]]; then
    err "config '$cfg' must set RELEASE_COMMIT_PATHS (files the release commit stages — at least the version file)."
    exit 1
  fi

  REPO_PATH="${RELEASE_REPO:-$(derive_repo || true)}"
  if [[ -z "$REPO_PATH" ]]; then
    err "RELEASE_REPO unset and could not derive owner/repo from remote '$REMOTE'."
    exit 1
  fi
  REPO_URL="https://github.com/$REPO_PATH"
  MAIN_BRANCH="${RELEASE_MAIN_BRANCH:-main}"
  DIST_DIR="${RELEASE_DIST_DIR:-dist}"
  GATE_CMD="${RELEASE_GATE-make test}"
  CHANGELOG_FILE="${RELEASE_CHANGELOG-CHANGELOG.md}"
  COMMIT_PATHS=("${RELEASE_COMMIT_PATHS[@]}")
  if [[ "${RELEASE_ASSETS+set}" == set ]]; then
    ASSETS=("${RELEASE_ASSETS[@]}")
  else
    ASSETS=()
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
  current=$(release_version_read) || true
  if [[ -z "$current" ]]; then
    err "release_version_read returned nothing — check the config."
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
    err "Version is already '$VERSION'. Choose a higher version."
    exit 1
  fi

  if git rev-parse "$VERSION" >/dev/null 2>&1; then
    err "Tag '$VERSION' already exists."
    exit 1
  fi
  ok "tag $VERSION does not exist"

  ok "current version: $PREVIOUS_VERSION → new version: $VERSION"

  if [[ -n "$CHANGELOG_FILE" ]]; then
    if ! grep -q '^## \[Unreleased\]' "$CHANGELOG_FILE"; then
      err "$CHANGELOG_FILE has no '[Unreleased]' section to roll."
      exit 1
    fi
    if ! unreleased_has_content; then
      err "$CHANGELOG_FILE '[Unreleased]' section is empty — nothing to release."
      exit 1
    fi
    ok "$CHANGELOG_FILE [Unreleased] has content"
  fi
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
  log "Bump version → $VERSION"
  if $DRY_RUN; then
    plan "write version $PREVIOUS_VERSION → $VERSION"
    return
  fi
  STAGE="mutated"
  release_version_write "$VERSION" || { err "release_version_write failed."; exit 1; }
  local now
  now=$(release_version_read) || true
  if [[ "$now" != "$VERSION" ]]; then
    err "Version write did not take (read back '$now', expected '$VERSION')."
    exit 1
  fi
  done_ok "version bumped"
}

roll_changelog() {
  [[ -n "$CHANGELOG_FILE" ]] || return 0
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
  ' "$CHANGELOG_FILE" > "$tmp"
  mv "$tmp" "$CHANGELOG_FILE"

  tmp=$(mktemp)
  awk -v ver="$VERSION" -v prev="$PREVIOUS_VERSION" -v repo="$REPO_URL" '
    /^\[Unreleased\]:/ {
      print "[Unreleased]: " repo "/compare/" ver "...HEAD"
      print "[" ver "]: " repo "/compare/" prev "..." ver
      next
    }
    { print }
  ' "$CHANGELOG_FILE" > "$tmp"
  mv "$tmp" "$CHANGELOG_FILE"

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
# so the local gate can be safely skipped.
should_skip_gates() {
  $TRUST_CI || return 1
  [[ "$(ci_head_conclusion)" == "success" ]]
}

run_gates() {
  if [[ -z "$GATE_CMD" ]]; then
    log "No gate configured — skipping"
    return 0
  fi
  log "Run release gate: $GATE_CMD"
  if $DRY_RUN; then
    plan "run gate '$GATE_CMD' (unless --trust-ci and HEAD is green)"
    return
  fi
  if should_skip_gates; then
    ok "trusting green CI on HEAD — skipping gate"
    return
  fi
  eval "$GATE_CMD" || { err "release gate failed: $GATE_CMD"; exit 1; }
  done_ok "gate passed"
}

# Build the release asset(s) via the config's release_build hook (if any),
# then verify every declared asset was produced. Honors dry-run.
build_step() {
  if [[ ${#ASSETS[@]} -eq 0 ]] && ! declare -f release_build >/dev/null 2>&1; then
    return 0
  fi
  log "Build release asset(s)"
  if $DRY_RUN; then
    plan "run release_build → produce ${ASSETS[*]:-<none>}"
    return
  fi
  if declare -f release_build >/dev/null 2>&1; then
    release_build || { err "release_build failed."; exit 1; }
  fi
  local a
  for a in ${ASSETS[@]+"${ASSETS[@]}"}; do
    [[ -f "$a" ]] || { err "expected asset not produced: $a"; exit 1; }
    done_ok "asset ready: $a"
  done
}

commit_and_tag() {
  log "Commit + tag"
  run git add ${COMMIT_PATHS[@]+"${COMMIT_PATHS[@]}"}
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
  local body
  if declare -f release_notes >/dev/null 2>&1; then
    body=$(release_notes)
  else
    body="See the CHANGELOG for the full notes."
  fi
  if $DRY_RUN; then
    plan "gh release create $VERSION --title 'Release $VERSION' + upload ${ASSETS[*]:-<none>}"
    return
  fi
  gh release create "$VERSION" \
    --repo "$REPO_PATH" \
    --title "Release $VERSION" \
    --notes "$body" \
    ${ASSETS[@]+"${ASSETS[@]}"}
  done_ok "GitHub release created"

  # Verify each asset actually attached (guards against a partial upload).
  local attached name base
  attached=$(gh release view "$VERSION" --repo "$REPO_PATH" \
    --json assets --jq '.assets[].name' 2>/dev/null || true)
  for name in ${ASSETS[@]+"${ASSETS[@]}"}; do
    base="${name##*/}"
    case $'\n'"$attached"$'\n' in
      *$'\n'"$base"$'\n'*) ok "asset attached: $base" ;;
      *) err "asset '$base' missing from release $VERSION"; exit 1 ;;
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
      git checkout -- ${COMMIT_PATHS[@]+"${COMMIT_PATHS[@]}"} 2>/dev/null || true
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
  parse_args "$@"
  load_config
  preflight

  if $DRY_RUN; then
    log "DRY RUN — no changes will be made"
  fi

  confirm
  trap cleanup EXIT

  bump_version
  roll_changelog
  run_gates
  build_step
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
