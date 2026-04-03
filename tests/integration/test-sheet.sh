#!/usr/bin/env bash
# tests/integration/test-sheet.sh — PTY tests for examples/sheet.sh

set -u
TESTS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SHELLFRAME_DIR="$(cd "$TESTS_DIR/.." && pwd)"
PTY_RUN="$PTYUNIT_HOME/pty_run.py"
SCRIPT="$SHELLFRAME_DIR/examples/sheet.sh"

source "$PTYUNIT_HOME/assert.sh"

_pty() {
    python3 "$PTY_RUN" "$SCRIPT" "$@" 2>/dev/null
}

# ── Sheet visibility ──────────────────────────────────────────────────────────

ptyunit_test_begin "sheet: opening sheet shows Step 1 header"
out=$(_pty ENTER ESC q)
assert_contains "$out" "Step 1 of 2" "Step 1 header visible after opening sheet"

ptyunit_test_begin "sheet: back strip shows parent content dimmed"
out=$(_pty ENTER ESC q)
assert_contains "$out" "Welcome" "parent content visible in back strip"

# ── Form input ────────────────────────────────────────────────────────────────

ptyunit_test_begin "sheet: typing in Name field is accepted"
# Type 'alice' in Name field, Tab to next field/button, Tab to Next button, Enter
out=$(_pty ENTER a l i c e TAB TAB ENTER ESC q)
assert_contains "$out" "Step 2 of 2" "transitions to step 2 after name input"

# ── Wizard transition ─────────────────────────────────────────────────────────

ptyunit_test_begin "sheet: Next button transitions to Step 2"
out=$(_pty ENTER TAB ENTER ESC q)
assert_contains "$out" "Step 2 of 2" "Step 2 visible after Next"

ptyunit_test_begin "sheet: Step 2 shows city field"
out=$(_pty ENTER TAB ENTER ESC q)
assert_contains "$out" "City" "City field visible in Step 2"

ptyunit_test_begin "sheet: Back button returns to Step 1"
# Open sheet, go to step 2 via Next, then Tab to Back and press Enter
out=$(_pty ENTER TAB ENTER TAB TAB ENTER ESC q)
assert_contains "$out" "Step 1 of 2" "Step 1 visible after Back"

# ── Dismissal ─────────────────────────────────────────────────────────────────

ptyunit_test_begin "sheet: Esc dismisses sheet and restores parent"
out=$(_pty ENTER ESC q)
assert_contains "$out" "Welcome" "parent screen visible after Esc"

ptyunit_test_begin "sheet: submitting wizard exits and prints result"
# Open sheet, go to step 2 via Next, Tab to Submit and press Enter
out=$(_pty ENTER TAB ENTER TAB ENTER)
assert_contains "$out" "Submitted" "submit message printed on completion"

ptyunit_test_summary
