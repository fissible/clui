#!/usr/bin/env bash
# tests/unit/test-tab-bar.sh — Unit tests for src/widgets/tab-bar.sh

set -u
TESTS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SHELLFRAME_DIR="$(cd "$TESTS_DIR/.." && pwd)"

source "$SHELLFRAME_DIR/src/clip.sh"
source "$SHELLFRAME_DIR/src/draw.sh"
source "$SHELLFRAME_DIR/src/input.sh"
source "$SHELLFRAME_DIR/src/widgets/tab-bar.sh"
source "$TESTS_DIR/assert.sh"

SHELLFRAME_TABBAR_LABELS=("Files" "Edit" "View")

# ── shellframe_tabbar_on_key: left arrow ──────────────────────────────────────

test_begin "tabbar_on_key: left decrements active"
SHELLFRAME_TABBAR_ACTIVE=1
shellframe_tabbar_on_key $'\033[D'
assert_eq "0" "$SHELLFRAME_TABBAR_ACTIVE" "active decremented to 0"

test_begin "tabbar_on_key: left clamps at 0"
SHELLFRAME_TABBAR_ACTIVE=0
shellframe_tabbar_on_key $'\033[D'
assert_eq "0" "$SHELLFRAME_TABBAR_ACTIVE" "active stays at 0"

test_begin "tabbar_on_key: left returns 0 (handled)"
SHELLFRAME_TABBAR_ACTIVE=1
shellframe_tabbar_on_key $'\033[D'
assert_eq "0" "$?" "left arrow returns 0"

# ── shellframe_tabbar_on_key: right arrow ─────────────────────────────────────

test_begin "tabbar_on_key: right increments active"
SHELLFRAME_TABBAR_ACTIVE=0
shellframe_tabbar_on_key $'\033[C'
assert_eq "1" "$SHELLFRAME_TABBAR_ACTIVE" "active incremented to 1"

test_begin "tabbar_on_key: right clamps at last tab"
SHELLFRAME_TABBAR_ACTIVE=2
shellframe_tabbar_on_key $'\033[C'
assert_eq "2" "$SHELLFRAME_TABBAR_ACTIVE" "active stays at 2"

test_begin "tabbar_on_key: right returns 0 (handled)"
SHELLFRAME_TABBAR_ACTIVE=0
shellframe_tabbar_on_key $'\033[C'
assert_eq "0" "$?" "right arrow returns 0"

# ── shellframe_tabbar_on_key: unhandled ───────────────────────────────────────

test_begin "tabbar_on_key: unhandled key returns 1"
shellframe_tabbar_on_key "x"
assert_eq "1" "$?" "unhandled key returns 1"

test_begin "tabbar_on_key: Enter returns 1 (not handled by tabbar)"
shellframe_tabbar_on_key $'\r'
assert_eq "1" "$?" "Enter returns 1"

# ── shellframe_tabbar_on_key: empty labels ────────────────────────────────────

test_begin "tabbar_on_key: empty labels array returns 1"
SHELLFRAME_TABBAR_LABELS=()
shellframe_tabbar_on_key $'\033[C'
assert_eq "1" "$?" "no labels: right returns 1"
SHELLFRAME_TABBAR_LABELS=("Files" "Edit" "View")

# ── shellframe_tabbar_on_focus ─────────────────────────────────────────────────

test_begin "tabbar_on_focus: sets FOCUSED=1"
SHELLFRAME_TABBAR_FOCUSED=0
shellframe_tabbar_on_focus 1
assert_eq "1" "$SHELLFRAME_TABBAR_FOCUSED" "focused set to 1"

test_begin "tabbar_on_focus: sets FOCUSED=0"
SHELLFRAME_TABBAR_FOCUSED=1
shellframe_tabbar_on_focus 0
assert_eq "0" "$SHELLFRAME_TABBAR_FOCUSED" "focused set to 0"

# ── shellframe_tabbar_size ─────────────────────────────────────────────────────

test_begin "tabbar_size: returns 3 1 0 1"
assert_output "3 1 0 1" shellframe_tabbar_size

test_summary
