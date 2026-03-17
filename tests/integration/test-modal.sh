#!/usr/bin/env bash
# tests/integration/test-modal.sh — PTY tests for examples/modal.sh

set -u
TESTS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.."; pwd)"
SHELLFRAME_DIR="$(cd "$TESTS_DIR/.."; pwd)"
PTY_RUN="$TESTS_DIR/ptyunit/pty_run.py"
SCRIPT="$SHELLFRAME_DIR/examples/modal.sh"

source "$TESTS_DIR/ptyunit/assert.sh"

_pty() {
    python3 "$PTY_RUN" "$SCRIPT" "$@" 2>/dev/null
}

# ── Tests ─────────────────────────────────────────────────────────────────────

ptyunit_test_begin "modal: Enter with empty input — OK, empty name"
out=$(_pty ENTER)
assert_contains "$out" "Renamed to:"

ptyunit_test_begin "modal: type text then Enter — OK, name captured"
out=$(_pty r e p o r t ENTER)
assert_contains "$out" "Renamed to: report"

ptyunit_test_begin "modal: Tab moves to Cancel then Enter — cancelled"
out=$(_pty TAB ENTER)
assert_contains "$out" "Cancelled"

ptyunit_test_begin "modal: spaces in input are captured"
out=$(_pty f o o SPACE b a r ENTER)
assert_contains "$out" "Renamed to: foo bar"

ptyunit_test_begin "modal: Esc cancels"
out=$(_pty ESC)
assert_contains "$out" "Cancelled"

ptyunit_test_begin "modal: Backspace removes last char"
out=$(_pty h e l l o BACKSPACE ENTER)
assert_contains "$out" "Renamed to: hell"

ptyunit_test_summary
