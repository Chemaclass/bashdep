---
paths:
  - "bashdep"
  - "**/*.sh"
  - "bin/pre-commit"
---

# Bash Style & Compatibility Rules

## Bash 3.2+ Compatibility (Critical)

`bashdep` must run on **macOS default bash (3.2)** and Linux bash 4+. The
following are allowed because they exist in 3.2: `[[ ]]`, indexed arrays,
`${var:-default}`, `${var/pattern/replacement}`, `$()`. The following are
**prohibited** (Bash 4.0+):

| Feature | Bash ver | Alternative |
|---------|----------|-------------|
| `declare -A` (associative arrays) | 4.0+ | Parallel indexed arrays or sorted lockfile lines |
| `${var,,}` / `${var^^}` (case) | 4.0+ | `tr '[:upper:]' '[:lower:]'` |
| `${array[-1]}` (negative index) | 4.3+ | `${array[${#array[@]}-1]}` |
| `&>>` (append both streams) | 4.0+ | `>> file 2>&1` |
| `mapfile` / `readarray` | 4.0+ | `while IFS= read -r line; do …; done < file` |
| `${parameter@Q}` (transformations) | 4.4+ | `printf '%q' "$parameter"` |

When in doubt: assume macOS default bash and avoid the feature.

## Runtime Dependency Policy

Library code in `bashdep` may only call: `curl`, `awk`, `mktemp`, `mkdir`,
`rm`, `cp`, `mv`, `printf`, `cat`, `grep`, `sort`, `tr`, `dirname`,
`basename`, `stat`, plus shell builtins. **Do not** introduce `jq`,
`python`, `node`, `xargs --max-args`, GNU-only flags, etc.

If a feature seems to need a new dependency, propose it in an issue first.

## Coding Conventions

- **2 spaces** indent, no tabs (enforced by `.editorconfig` + `make lint`)
- **No trailing whitespace**, file ends with a single newline
- Soft 100-char line cap; break long pipelines across lines with `\`
- Follow [Google Shell Style Guide](https://google.github.io/styleguide/shellguide.html) where it does not conflict with this repo
- Always quote variables unless explicit word splitting is wanted
- Use `$()` for command substitution, never backticks
- Use `printf` over `echo -e` (portable)

### Naming

- **Public functions:** `bashdep::function_name`
- **Private functions:** `bashdep::_function_name` (leading underscore after the namespace)
- **Local variables:** `lowercase_with_underscores`, declared `local`
- **Globals / config:** `BASHDEP_UPPERCASE_WITH_UNDERSCORES`

### Function Header (public functions)

Document non-trivial public functions with a short header:

```bash
# Brief description.
# Usage:
#   bashdep::name [arg=value] ...
#
# Returns: 0 on success, 1 on validation/IO failure.
function bashdep::name() {
  local arg=$1
  ...
}
```

### File Structure of `bashdep`

Constants → globals → private helpers (`bashdep::_*`) → public API
(`bashdep::*`). Do not interleave; readers scan top-to-bottom.

### Modes

Every mutating command must honor the four mode globals:

- `BASHDEP_DRY_RUN=true` — print `[dry-run] Would …` instead of acting
- `BASHDEP_SILENT=true` — suppress informational logs (errors still go to stderr)
- `BASHDEP_VERBOSE=true` — emit additional `bashdep::_vlog` traces
- `BASHDEP_FORCE=true` — bypass idempotence guards (re-download, overwrite)

Use the existing helpers (`bashdep::is_dry_run`, `bashdep::_log`,
`bashdep::_vlog`) — do not branch on the globals directly.

## ShellCheck

All code must pass `make sa`. Repo-wide directives in `Makefile`:
`-e SC1091 -e SC2155`. Add per-line directives sparingly with a reason:

```bash
# shellcheck disable=SC2034  # used by `eval` in caller
local var=value
```
