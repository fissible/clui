#!/usr/bin/env bash
# tests/unit/test-draw.sh — Unit tests for shellframe/src/draw.sh

set -u
TESTS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SHELLFRAME_DIR="$(cd "$TESTS_DIR/.." && pwd)"

source "$SHELLFRAME_DIR/src/draw.sh"
source "$TESTS_DIR/assert.sh"

# ── shellframe_pad_left ─────────────────────────────────────────────────────────────

shellframe_test_begin "shellframe_pad_left: basic left-align with padding"
result="$(shellframe_pad_left "hello" "hello" 10)"
assert_eq "hello     " "$result"

shellframe_test_begin "shellframe_pad_left: exact width — no padding"
result="$(shellframe_pad_left "hello" "hello" 5)"
assert_eq "hello" "$result"

shellframe_test_begin "shellframe_pad_left: wider than width — no truncation"
result="$(shellframe_pad_left "toolong" "toolong" 4)"
assert_eq "toolong" "$result"

shellframe_test_begin "shellframe_pad_left: zero width string"
result="$(shellframe_pad_left "" "" 5)"
assert_eq "     " "$result"

shellframe_test_begin "shellframe_pad_left: ANSI rendered; raw used for width"
# rendered has ANSI bold+reset (invisible), raw is plain text
raw="~/bin/gflow"
rendered="${SHELLFRAME_BOLD}~/bin/gflow${SHELLFRAME_RESET}"
result="$(shellframe_pad_left "$raw" "$rendered" 15)"
# Visible width of raw is 11; padding = 4 spaces; result is rendered + 4 spaces
expected="${SHELLFRAME_BOLD}~/bin/gflow${SHELLFRAME_RESET}    "
assert_eq "$expected" "$result" "ANSI padding width"

shellframe_test_begin "shellframe_pad_left: width equals raw length with ANSI in rendered"
raw="hi"
rendered="${SHELLFRAME_GREEN}hi${SHELLFRAME_RESET}"
result="$(shellframe_pad_left "$raw" "$rendered" 2)"
assert_eq "${SHELLFRAME_GREEN}hi${SHELLFRAME_RESET}" "$result" "exact width, ANSI rendered"

shellframe_test_summary
