#!/usr/bin/env bash
# tests/unit/test-split.sh — Unit tests for src/split.sh

set -u
TESTS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SHELLFRAME_DIR="$(cd "$TESTS_DIR/.." && pwd)"

source "$SHELLFRAME_DIR/src/scroll.sh"
source "$SHELLFRAME_DIR/src/split.sh"
source "$PTYUNIT_HOME/assert.sh"

# ── shellframe_split_init ────────────────────────────────────────────────────

ptyunit_test_begin "split_init: stores direction"
shellframe_split_init "s1" "v" 2 "0:0"
assert_eq "v" "$_SHELLFRAME_SPLIT_s1_DIR"

ptyunit_test_begin "split_init: stores count"
shellframe_split_init "s2" "h" 3 "10:0:10"
assert_eq "3" "$_SHELLFRAME_SPLIT_s2_COUNT"

ptyunit_test_begin "split_init: stores sizes"
shellframe_split_init "s3" "v" 2 "30:0"
assert_eq "30:0" "$_SHELLFRAME_SPLIT_s3_SIZES"

ptyunit_test_begin "split_init: default border is single"
shellframe_split_init "s4" "v" 2 "0:0"
assert_eq "single" "$_SHELLFRAME_SPLIT_s4_BORDER"

# ── shellframe_split_bounds: 2-pane vertical ─────────────────────────────────

ptyunit_test_begin "split_bounds: 2v flex+flex, child 0 gets half minus separator"
shellframe_split_init "b1" "v" 2 "0:0"
shellframe_split_bounds "b1" 0  1 1 80 24  t l w h
assert_eq "1" "$t" "top"
assert_eq "1" "$l" "left"
assert_eq "39" "$w" "width (39+1+40=80)"
assert_eq "24" "$h" "height"

ptyunit_test_begin "split_bounds: 2v flex+flex, child 1 gets remainder"
shellframe_split_bounds "b1" 1  1 1 80 24  t l w h
assert_eq "1" "$t" "top"
assert_eq "41" "$l" "left (39+1 separator+1)"
assert_eq "40" "$w" "width"
assert_eq "24" "$h" "height"

ptyunit_test_begin "split_bounds: 2v widths sum to container"
shellframe_split_bounds "b1" 0  1 1 80 24  t l w0 h
shellframe_split_bounds "b1" 1  1 1 80 24  t l w1 h
assert_eq "80" "$(( w0 + 1 + w1 ))" "w0 + sep + w1 = 80"

# ── shellframe_split_bounds: 2-pane vertical, fixed + flex ───────────────────

ptyunit_test_begin "split_bounds: 2v fixed 20 + flex, child 0 is 20 wide"
shellframe_split_init "b2" "v" 2 "20:0"
shellframe_split_bounds "b2" 0  1 1 80 24  t l w h
assert_eq "20" "$w"

ptyunit_test_begin "split_bounds: 2v fixed 20 + flex, child 1 is 59 wide"
shellframe_split_bounds "b2" 1  1 1 80 24  t l w h
assert_eq "59" "$w" "80 - 20 - 1 sep = 59"

# ── shellframe_split_bounds: 3-pane vertical ─────────────────────────────────

ptyunit_test_begin "split_bounds: 3v 20+flex+20, widths sum correctly"
shellframe_split_init "b3" "v" 3 "20:0:20"
shellframe_split_bounds "b3" 0  1 1 80 24  t l w0 h
shellframe_split_bounds "b3" 1  1 1 80 24  t l w1 h
shellframe_split_bounds "b3" 2  1 1 80 24  t l w2 h
assert_eq "20" "$w0" "child 0"
assert_eq "38" "$w1" "flex child (80-20-20-2seps)"
assert_eq "20" "$w2" "child 2"
assert_eq "80" "$(( w0 + 1 + w1 + 1 + w2 ))" "total"

# ── shellframe_split_bounds: 2-pane horizontal ──────────────────────────────

ptyunit_test_begin "split_bounds: 2h flex+flex, heights sum to container"
shellframe_split_init "b4" "h" 2 "0:0"
shellframe_split_bounds "b4" 0  1 1 80 24  t l w h0
shellframe_split_bounds "b4" 1  1 1 80 24  t l w h1
assert_eq "24" "$(( h0 + 1 + h1 ))" "h0 + sep + h1 = 24"

ptyunit_test_begin "split_bounds: 2h both children get full width"
shellframe_split_bounds "b4" 0  1 1 80 24  t l w h
assert_eq "80" "$w" "child 0 width"
shellframe_split_bounds "b4" 1  1 1 80 24  t l w h
assert_eq "80" "$w" "child 1 width"

# ── shellframe_split_bounds: minimum size clamping ───────────────────────────

ptyunit_test_begin "split_bounds: tiny container clamps children to minimum 1"
shellframe_split_init "b5" "v" 2 "0:0"
shellframe_split_bounds "b5" 0  1 1 3 1  t l w h
assert_eq "1" "$w" "minimum width is 1"

# ── shellframe_split_set_border ──────────────────────────────────────────────

ptyunit_test_begin "split_set_border: changes border style"
shellframe_split_init "b6" "v" 2 "0:0"
shellframe_split_set_border "b6" "none"
assert_eq "none" "$_SHELLFRAME_SPLIT_b6_BORDER"

# ── Summary ──────────────────────────────────────────────────────────────────

ptyunit_test_summary
