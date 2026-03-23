#!/usr/bin/env bash
# tests/integration/test-editor.sh — PTY tests for examples/editor.sh

set -u
TESTS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.."; pwd)"
SHELLFRAME_DIR="$(cd "$TESTS_DIR/.."; pwd)"
PTY_RUN="$PTYUNIT_HOME/pty_run.py"
SCRIPT="$SHELLFRAME_DIR/examples/editor.sh"

source "$PTYUNIT_HOME/assert.sh"

_pty() {
    python3 "$PTY_RUN" "$SCRIPT" "$@" 2>/dev/null
}

# ── Tests ─────────────────────────────────────────────────────────────────────

ptyunit_test_begin "editor: type text then Ctrl-D — text on stdout"
out=$(_pty h e l l o '\x04')
assert_contains "$out" "hello"

ptyunit_test_begin "editor: Enter creates a new line"
out=$(_pty h e l l o ENTER w o r l d '\x04')
assert_contains "$out" "hello"
assert_contains "$out" "world"

ptyunit_test_begin "editor: Backspace deletes last char"
out=$(_pty h e l l o BACKSPACE '\x04')
assert_contains "$out" "hell"

ptyunit_test_begin "editor: Ctrl-K clears line; replacement text is submitted"
# Type 'hello', go Home, kill to EOL, type 'abc', submit — result should be 'abc'
out=$(_pty h e l l o HOME '\x0b' a b c '\x04')
assert_contains "$out" "abc"

ptyunit_test_begin "editor: Ctrl-U clears to start of line; prefix text is submitted"
# Type 'helloworld', Left×5, Ctrl-U clears 'hello', result should be 'world'
out=$(_pty h e l l o w o r l d LEFT LEFT LEFT LEFT LEFT '\x15' '\x04')
assert_contains "$out" "world"

ptyunit_test_summary
