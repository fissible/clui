#!/usr/bin/env bash
# tests/unit/test-sync-scroll.sh — Unit tests for src/sync-scroll.sh

set -u
TESTS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SHELLFRAME_DIR="$(cd "$TESTS_DIR/.." && pwd)"

source "$SHELLFRAME_DIR/src/scroll.sh"
source "$SHELLFRAME_DIR/src/sync-scroll.sh"
source "$PTYUNIT_HOME/assert.sh"

# ── Setup helper ─────────────────────────────────────────────────────────────

_setup() {
    shellframe_scroll_init "left"  100 80 20 40
    shellframe_scroll_init "right" 120 80 20 40
    shellframe_sync_scroll_init "g1" "left" "right"
}

# ── shellframe_sync_scroll_move ──────────────────────────────────────────────

ptyunit_test_begin "sync_move: scrolling left also scrolls right"
_setup
shellframe_sync_scroll_move "g1" "left" "down" 10
assert_output "10" shellframe_scroll_top "left"
assert_output "10" shellframe_scroll_top "right"

ptyunit_test_begin "sync_move: scrolling right also scrolls left"
_setup
shellframe_sync_scroll_move "g1" "right" "down" 15
assert_output "15" shellframe_scroll_top "left"
assert_output "15" shellframe_scroll_top "right"

ptyunit_test_begin "sync_move: clamps to each context's own max"
_setup
shellframe_sync_scroll_move "g1" "right" "down" 200
# right max = 120 - 20 = 100, left max = 100 - 20 = 80
shellframe_scroll_top "left" _t
assert_eq "80" "$_t" "clamped to left's max"
shellframe_scroll_top "right" _t
assert_eq "100" "$_t" "right's own max"

ptyunit_test_begin "sync_move: page_down works"
_setup
shellframe_sync_scroll_move "g1" "left" "page_down"
shellframe_scroll_top "left" _t
assert_eq "20" "$_t" "page = viewport rows"
shellframe_scroll_top "right" _t
assert_eq "20" "$_t"

ptyunit_test_begin "sync_move: home resets to 0"
_setup
shellframe_sync_scroll_move "g1" "left" "down" 50
shellframe_sync_scroll_move "g1" "left" "home"
assert_output "0" shellframe_scroll_top "left"
assert_output "0" shellframe_scroll_top "right"

# ── Lock/unlock ──────────────────────────────────────────────────────────────

ptyunit_test_begin "sync_unlock: scrolling left does NOT scroll right"
_setup
shellframe_sync_scroll_set "g1" 0
shellframe_sync_scroll_move "g1" "left" "down" 10
shellframe_scroll_top "left" _t
assert_eq "10" "$_t"
shellframe_scroll_top "right" _t
assert_eq "0" "$_t" "should stay at 0"

ptyunit_test_begin "sync_relock: scrolling propagates again"
shellframe_sync_scroll_set "g1" 1
shellframe_sync_scroll_move "g1" "left" "down" 5
assert_output "15" shellframe_scroll_top "left"
assert_output "15" shellframe_scroll_top "right"

# ── shellframe_sync_scroll_locked ────────────────────────────────────────────

ptyunit_test_begin "sync_locked: returns 0 when locked"
_setup
shellframe_sync_scroll_locked "g1"
assert_eq "0" "$?" "exit code 0 = true"

ptyunit_test_begin "sync_locked: returns 1 when unlocked"
shellframe_sync_scroll_set "g1" 0
shellframe_sync_scroll_locked "g1"
_rc=$?
assert_eq "1" "$_rc" "exit code 1 = false"

# ── 3-member group ───────────────────────────────────────────────────────────

ptyunit_test_begin "sync_3member: all three scroll together"
shellframe_scroll_init "a" 100 80 20 40
shellframe_scroll_init "b" 100 80 20 40
shellframe_scroll_init "c" 100 80 20 40
shellframe_sync_scroll_init "g3" "a" "b" "c"
shellframe_sync_scroll_move "g3" "b" "down" 7
assert_output "7" shellframe_scroll_top "a"
assert_output "7" shellframe_scroll_top "b"
assert_output "7" shellframe_scroll_top "c"

# ── Summary ──────────────────────────────────────────────────────────────────

ptyunit_test_summary
