#!/usr/bin/env bash
# tests/integration/test-menu-bar.sh — PTY tests for examples/menu-bar.sh

set -u
TESTS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.."; pwd)"
SHELLFRAME_DIR="$(cd "$TESTS_DIR/.."; pwd)"
PTY_RUN="$PTYUNIT_HOME/pty_run.py"
SCRIPT="$SHELLFRAME_DIR/examples/menu-bar.sh"

source "$PTYUNIT_HOME/assert.sh"

_pty() {
    python3 "$PTY_RUN" "$SCRIPT" "$@" 2>/dev/null
}

# ── Tests ──────────────────────────────────────────────────────────────────────

ptyunit_test_begin "menu-bar: Enter opens File dropdown, Enter selects Open"
out=$(_pty ENTER ENTER)
assert_contains "$out" "Selected: File|Open"

ptyunit_test_begin "menu-bar: Down then Enter selects Save"
# File menu: Open(0), Save(1), ---(2), @RECENT(3), ---(4), Quit(5)
# Enter opens dropdown (cursor=Open[0]), DOWN→Save[1], Enter selects Save
out=$(_pty ENTER DOWN ENTER)
assert_contains "$out" "Selected: File|Save"

ptyunit_test_begin "menu-bar: navigate to submenu and select first item"
# Enter opens File, DOWN×2 skips sep and reaches @RECENT[3], Right opens submenu, Enter selects demo.db
out=$(_pty ENTER DOWN DOWN RIGHT ENTER)
assert_contains "$out" "Selected: File|Recent Files|demo.db"

ptyunit_test_begin "menu-bar: submenu Down then Enter selects second item"
out=$(_pty ENTER DOWN DOWN RIGHT DOWN ENTER)
assert_contains "$out" "Selected: File|Recent Files|work.db"

ptyunit_test_begin "menu-bar: Left from submenu returns to dropdown"
# Left from submenu → dropdown (cursor still at @RECENT[3]); UP×2 reaches Open[0], Enter selects Open
out=$(_pty ENTER DOWN DOWN RIGHT LEFT UP UP ENTER)
assert_contains "$out" "Selected: File|Open"

ptyunit_test_begin "menu-bar: Right in bar moves to Edit, Enter opens, Enter selects Undo"
out=$(_pty RIGHT ENTER ENTER)
assert_contains "$out" "Selected: Edit|Undo"

ptyunit_test_begin "menu-bar: Esc from bar cancels"
out=$(_pty ESC)
assert_contains "$out" "Cancelled."

ptyunit_test_summary
