#!/bin/bash
#
# build.sh — amalgamate a multi-file bash project into one executable.
#
# Inlines static, top-level `source <path>` / `. <path>` directives
# (recursively, each file inlined once) into a single self-contained
# script, printed to stdout — suitable as a release asset produced by a
# release.conf `release_build` hook.
#
# What it inlines: a line that begins at column 0 with `source ` or `. `
# followed by a single literal path (optionally quoted). What it leaves
# untouched (printed as-is): dynamic includes — `source "$var"`, command
# substitution, globs — and any indented `source` (e.g. inside a function
# or conditional), since a line-based bundler cannot know when it runs.
# Keep your includes static and top-level for a clean bundle.
#
# Usage (run from your repo root):
#   build.sh ENTRY > OUTPUT
#   build.sh src/main.sh > dist/tool && chmod +x dist/tool
#
# Returns 1 on usage error or a missing entry file. A `source` whose target
# is missing is left in place (not fatal) so the result still shows intent.
#

set -euo pipefail

# Newline-delimited list of already-inlined absolute paths (dedup + cycle
# guard). Bash 3.2 has no associative arrays, so this mirrors bashdep's
# own "seen" pattern.
SEEN=""
# Recursion depth: 0 is the entry file (keeps its shebang); deeper files
# have their leading shebang stripped.
DEPTH=0

# Resolve $1 (a path, relative to directory $2 unless absolute) to a
# normalized absolute path. Falls back to the raw path if the directory
# cannot be entered.
resolve_path() {
  local path=$1 base=$2 d b
  b=$(basename "$path")
  case $path in
    /*) d=$(dirname "$path") ;;
    *)  d="$base/$(dirname "$path")" ;;
  esac
  d=$(cd "$d" 2>/dev/null && pwd) || { printf '%s\n' "$path"; return; }
  printf '%s/%s\n' "$d" "$b"
}

# If $1 is a static, inlineable source directive, echo its literal path and
# return 0; otherwise return 1. Only column-0 `source `/`. ` lines with a
# single literal (optionally quoted) path qualify — dynamic or glob paths
# and extra arguments are rejected.
parse_source_line() {
  local line=$1 rest path
  case $line in
    'source '*) rest=${line#source } ;;
    '. '*)      rest=${line#. } ;;
    *) return 1 ;;
  esac
  # Trim surrounding whitespace.
  rest=${rest#"${rest%%[![:space:]]*}"}
  rest=${rest%"${rest##*[![:space:]]}"}
  [[ -z "$rest" ]] && return 1
  # Strip one layer of matching quotes.
  case $rest in
    \"*\") path=${rest#\"}; path=${path%\"} ;;
    \'*\') path=${rest#\'}; path=${path%\'} ;;
    *)     path=$rest ;;
  esac
  # Reject extra args (internal whitespace) and dynamic/glob content.
  case $path in
    ''|*[[:space:]]*)          return 1 ;;
    *'$'*|*'`'*|*'*'*|*'?'*|*'['*) return 1 ;;
  esac
  printf '%s\n' "$path"
}

# Recursively print $1's contents with inlineable sources expanded.
inline_file() {
  local file=$1
  local dir abs
  dir=$(dirname "$file")
  abs=$(resolve_path "$file" ".")
  # Skip files already inlined (dedup + cycle guard).
  case $'\n'"$SEEN"$'\n' in
    *$'\n'"$abs"$'\n'*) return 0 ;;
  esac
  SEEN="$SEEN$abs"$'\n'

  local first=true line inc incabs
  while IFS= read -r line || [[ -n "$line" ]]; do
    if $first; then
      first=false
      # Drop the shebang of an included file — the entry keeps its own.
      if [[ $DEPTH -gt 0 && "$line" == '#!'* ]]; then
        continue
      fi
    fi
    if inc=$(parse_source_line "$line"); then
      incabs=$(resolve_path "$inc" "$dir")
      if [[ -f "$incabs" ]]; then
        # Silently drop a repeat include already inlined elsewhere.
        case $'\n'"$SEEN"$'\n' in
          *$'\n'"$incabs"$'\n'*) continue ;;
        esac
        printf '# >>> inlined: %s\n' "$inc"
        DEPTH=$((DEPTH + 1))
        inline_file "$incabs"
        DEPTH=$((DEPTH - 1))
        printf '# <<< end: %s\n' "$inc"
        continue
      fi
    fi
    printf '%s\n' "$line"
  done < "$file"
}

main() {
  if [[ $# -ne 1 ]]; then
    echo "Usage: build.sh ENTRY" >&2
    exit 1
  fi
  local entry=$1
  if [[ ! -f "$entry" ]]; then
    echo "Error: entry file not found: $entry" >&2
    exit 1
  fi
  DEPTH=0
  SEEN=""
  inline_file "$entry"
}

# Run only when executed directly; sourcing (e.g. from tests) exposes the
# functions without side effects.
if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
  main "$@"
fi
