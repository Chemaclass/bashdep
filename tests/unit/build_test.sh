#!/bin/bash
# shellcheck disable=SC2155,SC2034,SC2016
#
# SC2016: several tests pass single-quoted literals like 'source "$LIB"'
# to parse_source_line on purpose — the `$` must stay unexpanded.
#
# Unit tests for the amalgamator (templates/build.sh). Pure-logic helpers
# (parse_source_line) are exercised by sourcing the script under its
# BASH_SOURCE guard; the end-to-end bundling is exercised by invoking the
# script as a subprocess against fixtures in $TEST_DIR.

TEST_DIR=""
BUILD=""

function set_up() {
  if ! declare -f parse_source_line >/dev/null 2>&1; then
    # shellcheck disable=SC1091
    source "$(current_dir)/../../templates/build.sh"
  fi
  set +e +u +o pipefail
  REPO_ROOT="$(cd "$(current_dir)/../.." && pwd)"
  BUILD="$REPO_ROOT/templates/build.sh"
  TEST_DIR=$(mktemp -d)
}

function tear_down() {
  if [[ -n "$TEST_DIR" && -d "$TEST_DIR" ]]; then
    rm -rf "$TEST_DIR"
  fi
}

# --- parse_source_line -------------------------------------------------------

function test_build_parse_source_accepts_relative() {
  assert_equals "./lib.sh" "$(parse_source_line 'source ./lib.sh')"
}

function test_build_parse_source_accepts_dot_form() {
  assert_equals "./lib.sh" "$(parse_source_line '. ./lib.sh')"
}

function test_build_parse_source_accepts_quoted() {
  assert_equals "./lib.sh" "$(parse_source_line 'source "./lib.sh"')"
}

function test_build_parse_source_rejects_dynamic_var() {
  parse_source_line 'source "$LIB"'
  assert_general_error
}

function test_build_parse_source_rejects_command_sub() {
  parse_source_line 'source "$(dirname "$0")/lib.sh"'
  assert_general_error
}

# Indented sources are treated as non-top-level (likely inside a function
# or conditional) and left untouched.
function test_build_parse_source_rejects_indented() {
  parse_source_line '  source ./lib.sh'
  assert_general_error
}

function test_build_parse_source_rejects_extra_args() {
  parse_source_line 'source ./lib.sh --flag'
  assert_general_error
}

function test_build_parse_source_rejects_plain_line() {
  parse_source_line 'echo hello'
  assert_general_error
}

# --- end-to-end bundling -----------------------------------------------------

function test_build_inlines_static_source() {
  printf '#!/bin/bash\nsource ./lib.sh\necho main\n' > "$TEST_DIR/main.sh"
  printf 'echo from-lib\n' > "$TEST_DIR/lib.sh"
  local out
  out=$(cd "$TEST_DIR" && bash "$BUILD" main.sh)
  assert_contains "echo from-lib" "$out"
}

function test_build_removes_the_source_directive() {
  printf '#!/bin/bash\nsource ./lib.sh\n' > "$TEST_DIR/main.sh"
  printf 'echo from-lib\n' > "$TEST_DIR/lib.sh"
  local out
  out=$(cd "$TEST_DIR" && bash "$BUILD" main.sh)
  assert_not_contains "source ./lib.sh" "$out"
}

function test_build_keeps_single_entry_shebang() {
  printf '#!/bin/bash\nsource ./lib.sh\n' > "$TEST_DIR/main.sh"
  printf '#!/bin/bash\necho lib\n' > "$TEST_DIR/lib.sh"
  local out count
  out=$(cd "$TEST_DIR" && bash "$BUILD" main.sh)
  count=$(printf '%s\n' "$out" | grep -c '^#!/bin/bash')
  assert_equals "1" "$count"
}

function test_build_dedups_diamond_include() {
  printf '#!/bin/bash\nsource ./a.sh\nsource ./b.sh\n' > "$TEST_DIR/main.sh"
  printf 'source ./common.sh\necho a\n' > "$TEST_DIR/a.sh"
  printf 'source ./common.sh\necho b\n' > "$TEST_DIR/b.sh"
  printf 'echo common\n' > "$TEST_DIR/common.sh"
  local out count
  out=$(cd "$TEST_DIR" && bash "$BUILD" main.sh)
  count=$(printf '%s\n' "$out" | grep -c 'echo common')
  assert_equals "1" "$count"
}

function test_build_dedup_repeat_include_emits_no_empty_markers() {
  printf '#!/bin/bash\nsource ./lib.sh\nsource ./lib.sh\n' > "$TEST_DIR/main.sh"
  printf 'echo x\n' > "$TEST_DIR/lib.sh"
  local out count
  out=$(cd "$TEST_DIR" && bash "$BUILD" main.sh)
  count=$(printf '%s\n' "$out" | grep -c '>>> inlined: ./lib.sh')
  assert_equals "1" "$count"
}

function test_build_inlines_recursively() {
  printf '#!/bin/bash\nsource ./a.sh\n' > "$TEST_DIR/main.sh"
  printf 'source ./b.sh\necho a\n' > "$TEST_DIR/a.sh"
  printf 'echo b\n' > "$TEST_DIR/b.sh"
  local out
  out=$(cd "$TEST_DIR" && bash "$BUILD" main.sh)
  assert_contains "echo b" "$out"
}

function test_build_leaves_dynamic_source_untouched() {
  printf '#!/bin/bash\nlib="./lib.sh"\nsource "$lib"\n' > "$TEST_DIR/main.sh"
  printf 'echo from-lib\n' > "$TEST_DIR/lib.sh"
  local out
  out=$(cd "$TEST_DIR" && bash "$BUILD" main.sh)
  assert_not_contains "echo from-lib" "$out"
}

function test_build_leaves_missing_include_in_place() {
  printf '#!/bin/bash\nsource ./nope.sh\n' > "$TEST_DIR/main.sh"
  local out
  out=$(cd "$TEST_DIR" && bash "$BUILD" main.sh)
  assert_contains "source ./nope.sh" "$out"
}

function test_build_output_is_valid_bash() {
  printf '#!/bin/bash\nsource ./lib.sh\ngreet\n' > "$TEST_DIR/main.sh"
  printf 'greet() { echo hi; }\n' > "$TEST_DIR/lib.sh"
  ( cd "$TEST_DIR" && bash "$BUILD" main.sh > bundle.sh )
  bash -n "$TEST_DIR/bundle.sh"
  assert_successful_code "$?"
}

function test_build_errors_on_missing_entry() {
  ( bash "$BUILD" "$TEST_DIR/does-not-exist.sh" ) 2>/dev/null
  assert_general_error
}

function test_build_errors_without_args() {
  ( bash "$BUILD" ) 2>/dev/null
  assert_general_error
}
