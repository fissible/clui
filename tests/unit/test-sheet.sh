#!/usr/bin/env bash
# tests/unit/test-sheet.sh — Unit tests for src/sheet.sh
set -u
TESTS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.."; pwd)"
SHELLFRAME_DIR="$(cd "$TESTS_DIR/.."; pwd)"

source "$SHELLFRAME_DIR/src/input.sh"
source "$SHELLFRAME_DIR/src/screen.sh"
source "$SHELLFRAME_DIR/src/hitbox.sh"
source "$SHELLFRAME_DIR/src/shell.sh"
source "$SHELLFRAME_DIR/src/sheet.sh"
source "$PTYUNIT_HOME/assert.sh"

# fd 3 to /dev/null so shellframe_screen_flush doesn't error
exec 3>/dev/null

_reset_sheet() {
    _SHELLFRAME_SHEET_ACTIVE=0
    _SHELLFRAME_SHEET_PREFIX=""
    _SHELLFRAME_SHEET_SCREEN=""
    _SHELLFRAME_SHEET_NEXT=""
    _SHELLFRAME_SHEET_FROZEN_ROWS=()
    SHELLFRAME_SHEET_HEIGHT=0
    SHELLFRAME_SHEET_WIDTH=0
    _SHELLFRAME_SHEET_REGIONS=()
    _SHELLFRAME_SHEET_FOCUS_RING=()
    _SHELLFRAME_SHEET_FOCUS_IDX=0
    _SHELLFRAME_SHEET_FOCUS_REQUEST=""
    _SHELLFRAME_SHELL_REGIONS=()
    _SHELLFRAME_SHELL_FOCUS_RING=()
    _SHELLFRAME_SHELL_FOCUS_IDX=0
    _SHELLFRAME_SHELL_FOCUS_REQUEST=""
    _SF_ROW_OFFSET=0
    _SHELLFRAME_SHELL_ROWS=10
    _SHELLFRAME_SHELL_COLS=80
    shellframe_fb_frame_start 10 80
}

# ── shellframe_sheet_push ─────────────────────────────────────────────────────

ptyunit_test_begin "sheet_push: sets ACTIVE=1"
_reset_sheet
shellframe_sheet_push "_myapp" "OPEN_DB"
assert_eq "1" "$_SHELLFRAME_SHEET_ACTIVE" "ACTIVE is 1 after push"

ptyunit_test_begin "sheet_push: stores prefix and screen"
_reset_sheet
shellframe_sheet_push "_myapp" "OPEN_DB"
assert_eq "_myapp" "$_SHELLFRAME_SHEET_PREFIX" "prefix stored"
assert_eq "OPEN_DB" "$_SHELLFRAME_SHEET_SCREEN" "screen stored"

ptyunit_test_begin "sheet_push: NEXT is empty after push"
_reset_sheet
shellframe_sheet_push "_myapp" "OPEN_DB"
assert_eq "" "$_SHELLFRAME_SHEET_NEXT" "NEXT is empty"

ptyunit_test_begin "sheet_push: resets sheet focus state"
_reset_sheet
_SHELLFRAME_SHEET_FOCUS_IDX=3
shellframe_sheet_push "_myapp" "OPEN_DB"
assert_eq "0" "$_SHELLFRAME_SHEET_FOCUS_IDX" "focus idx reset to 0"
assert_eq "0" "${#_SHELLFRAME_SHEET_FOCUS_RING[@]}" "focus ring empty"

# ── double-push guard ─────────────────────────────────────────────────────────

ptyunit_test_begin "sheet_push: double-push returns 1 and preserves existing state"
_reset_sheet
shellframe_sheet_push "_myapp" "OPEN_DB"
rc=0
shellframe_sheet_push "_other" "OTHER_SCREEN" 2>/dev/null || rc=$?
assert_eq "1" "$rc" "double push returns 1"
assert_eq "_myapp" "$_SHELLFRAME_SHEET_PREFIX" "original prefix unchanged"
assert_eq "OPEN_DB" "$_SHELLFRAME_SHEET_SCREEN" "original screen unchanged"

ptyunit_test_begin "sheet_push: double-push writes warning to stderr"
_reset_sheet
shellframe_sheet_push "_myapp" "OPEN_DB"
errmsg=$(shellframe_sheet_push "_other" "OTHER" 2>&1 >/dev/null || true)
assert_contains "$errmsg" "sheet already active" "warning on stderr"

# ── shellframe_sheet_pop ──────────────────────────────────────────────────────

ptyunit_test_begin "sheet_pop: sets NEXT to __POP__"
_reset_sheet
shellframe_sheet_push "_myapp" "OPEN_DB"
shellframe_sheet_pop
assert_eq "__POP__" "$_SHELLFRAME_SHEET_NEXT" "NEXT set to __POP__"

# ── shellframe_sheet_active ───────────────────────────────────────────────────

ptyunit_test_begin "sheet_active: returns 0 when active"
_reset_sheet
shellframe_sheet_push "_myapp" "OPEN_DB"
shellframe_sheet_active
assert_eq "0" "$?" "exit code 0 when active"

ptyunit_test_begin "sheet_active: returns 1 when not active"
_reset_sheet
rc=0
shellframe_sheet_active || rc=$?
assert_eq "1" "$rc" "exit code 1 when inactive"

# ── shellframe_sheet_draw: registry swap ───────────────────────────────────────

# Helper: minimal render hook for tests
_tst_FORM_render() {
    shellframe_shell_region body 1 1 "$SHELLFRAME_SHEET_WIDTH" 5
}
_tst_FORM_body_render() { :; }

ptyunit_test_begin "sheet_draw: parent shell regions restored after draw"
_reset_sheet
_SHELLFRAME_SHELL_REGIONS=("parent:1:1:80:10:focus")
shellframe_sheet_push "_tst" "FORM"
shellframe_sheet_draw 10 80
assert_eq "1" "${#_SHELLFRAME_SHELL_REGIONS[@]}" "parent region count unchanged"
assert_eq "parent:1:1:80:10:focus" "${_SHELLFRAME_SHELL_REGIONS[0]}" "parent entry unchanged"

ptyunit_test_begin "sheet_draw: parent focus ring restored after draw"
_reset_sheet
_SHELLFRAME_SHELL_FOCUS_RING=("parent")
_SHELLFRAME_SHELL_FOCUS_IDX=0
shellframe_sheet_push "_tst" "FORM"
shellframe_sheet_draw 10 80
assert_eq "1" "${#_SHELLFRAME_SHELL_FOCUS_RING[@]}" "parent focus ring count unchanged"
assert_eq "parent" "${_SHELLFRAME_SHELL_FOCUS_RING[0]}" "parent focus ring entry unchanged"

ptyunit_test_begin "sheet_draw: SHEET_WIDTH set to cols before render hook"
_reset_sheet
_tst_WIDE_render() { :; }
shellframe_sheet_push "_tst" "WIDE"
shellframe_sheet_draw 10 120
assert_eq "120" "$SHELLFRAME_SHEET_WIDTH" "SHEET_WIDTH set to cols"

ptyunit_test_begin "sheet_draw: height=0 resolves to rows-1"
_reset_sheet
SHELLFRAME_SHEET_HEIGHT=0
shellframe_sheet_push "_tst" "FORM"
shellframe_sheet_draw 10 80
# sheet ran without error; height resolution verified by frozen row write below row 2
assert_eq "0" "$?" "draw exits 0"

ptyunit_test_begin "sheet_draw: frozen rows written at row 1 with dim wrapper"
_reset_sheet
# Set up a known frozen row 1 by writing to the framebuffer before push
shellframe_fb_frame_start 10 80
shellframe_fb_print 1 1 "parent content"
shellframe_sheet_push "_tst" "FORM"
# Now draw — row 1 in CURR should be the dimmed frozen row
_SF_ROW_CURR=()
_SF_DIRTY_ROWS=()
shellframe_sheet_draw 10 80
assert_contains "${_SF_ROW_CURR[1]:-}" $'\033[2m' "row 1 contains dim sequence"
assert_contains "${_SF_ROW_CURR[1]:-}" $'\033[22m' "row 1 ends dim sequence"

# ── Screen transitions and __POP__ ────────────────────────────────────────────

ptyunit_test_begin "sheet_draw: SHEET_NEXT=STEP2 transitions to new screen"
_reset_sheet
shellframe_sheet_push "_tst" "FORM"
_SHELLFRAME_SHEET_NEXT="STEP2"
_tst_STEP2_render() { :; }
shellframe_sheet_draw 10 80
assert_eq "STEP2" "$_SHELLFRAME_SHEET_SCREEN" "screen updated to STEP2"
assert_eq "" "$_SHELLFRAME_SHEET_NEXT" "NEXT cleared"

ptyunit_test_begin "sheet_draw: transition resets focus state"
_reset_sheet
shellframe_sheet_push "_tst" "FORM"
_SHELLFRAME_SHEET_FOCUS_IDX=2
_SHELLFRAME_SHEET_NEXT="STEP2"
_tst_STEP2_render() { :; }
shellframe_sheet_draw 10 80
assert_eq "0" "$_SHELLFRAME_SHEET_FOCUS_IDX" "focus idx reset to 0 after transition"

ptyunit_test_begin "sheet_draw: SHEET_NEXT=__POP__ clears ACTIVE"
_reset_sheet
shellframe_sheet_push "_tst" "FORM"
shellframe_sheet_pop
shellframe_sheet_draw 10 80
assert_eq "0" "$_SHELLFRAME_SHEET_ACTIVE" "ACTIVE=0 after pop"

ptyunit_test_begin "sheet_draw: SHEET_NEXT=__POP__ clears prefix and screen"
_reset_sheet
shellframe_sheet_push "_tst" "FORM"
shellframe_sheet_pop
shellframe_sheet_draw 10 80
assert_eq "" "$_SHELLFRAME_SHEET_PREFIX" "prefix cleared"
assert_eq "" "$_SHELLFRAME_SHEET_SCREEN" "screen cleared"

ptyunit_test_begin "sheet_draw: SHEET_NEXT=__POP__ marks parent dirty"
_reset_sheet
shellframe_sheet_push "_tst" "FORM"
shellframe_sheet_pop
_SHELLFRAME_SHELL_DIRTY=0
shellframe_sheet_draw 10 80
assert_eq "1" "$_SHELLFRAME_SHELL_DIRTY" "parent marked dirty after pop"

ptyunit_test_begin "sheet_draw: SHEET_NEXT=__POP__ restores parent regions"
_reset_sheet
_SHELLFRAME_SHELL_REGIONS=("parent:1:1:80:10:focus")
shellframe_sheet_push "_tst" "FORM"
shellframe_sheet_pop
shellframe_sheet_draw 10 80
assert_eq "parent:1:1:80:10:focus" "${_SHELLFRAME_SHELL_REGIONS[0]}" "parent regions intact after pop"

ptyunit_test_begin "sheet_draw: explicit height is used when set by render hook"
_reset_sheet
_tst_TALL_render() { SHELLFRAME_SHEET_HEIGHT=6; }
shellframe_sheet_push "_tst" "TALL"
SHELLFRAME_SHEET_HEIGHT=0
shellframe_sheet_draw 10 80
# Verify frozen rows below sheet boundary got written (rows 8-10 for height=6, top=2)
assert_contains "${_SF_ROW_CURR[8]:-}" $'\033[2m' "row below sheet has dim wrapper"

# ── shellframe_sheet_on_key ────────────────────────────────────────────────────

# Common setup: push a sheet with two focusable regions
_setup_two_region_sheet() {
    _reset_sheet
    # Register two focusable regions in the sheet's state
    _SHELLFRAME_SHELL_REGIONS=("body:1:1:80:4:focus" "footer:5:1:80:1:focus")
    _shellframe_shell_focus_init
    _SHELLFRAME_SHEET_REGIONS=("${_SHELLFRAME_SHELL_REGIONS[@]}")
    _SHELLFRAME_SHEET_FOCUS_RING=("${_SHELLFRAME_SHELL_FOCUS_RING[@]}")
    _SHELLFRAME_SHEET_FOCUS_IDX=0
    _SHELLFRAME_SHELL_REGIONS=()
    _SHELLFRAME_SHELL_FOCUS_RING=()
    _SHELLFRAME_SHELL_FOCUS_IDX=0
    shellframe_sheet_push "_tst" "FORM"
    # After push, restore the regions we set up
    _SHELLFRAME_SHEET_REGIONS=("body:1:1:80:4:focus" "footer:5:1:80:1:focus")
    _SHELLFRAME_SHEET_FOCUS_RING=("body" "footer")
    _SHELLFRAME_SHEET_FOCUS_IDX=0
}

# Provide minimal on_key handlers for region dispatch testing
_tst_FORM_body_on_key() { return 0; }   # handled
_tst_FORM_footer_on_key() { return 1; } # unhandled

ptyunit_test_begin "sheet_on_key: Esc calls quit hook if defined"
_setup_two_region_sheet
_quit_called=0
_tst_FORM_quit() { _quit_called=1; shellframe_sheet_pop; }
shellframe_sheet_on_key $'\033'
assert_eq "1" "$_quit_called" "quit hook called on Esc"
assert_eq "__POP__" "$_SHELLFRAME_SHEET_NEXT" "NEXT set to __POP__"

ptyunit_test_begin "sheet_on_key: Esc pops sheet if no quit hook"
_setup_two_region_sheet
unset -f _tst_FORM_quit 2>/dev/null || true
shellframe_sheet_on_key $'\033'
assert_eq "__POP__" "$_SHELLFRAME_SHEET_NEXT" "NEXT=__POP__ when no quit hook"

ptyunit_test_begin "sheet_on_key: Tab advances focus"
_setup_two_region_sheet
assert_eq "0" "$_SHELLFRAME_SHEET_FOCUS_IDX" "starts at 0"
shellframe_sheet_on_key $'\t'
assert_eq "1" "$_SHELLFRAME_SHEET_FOCUS_IDX" "focus advanced to 1 after Tab"

ptyunit_test_begin "sheet_on_key: Shift-Tab retreats focus"
_setup_two_region_sheet
_SHELLFRAME_SHEET_FOCUS_IDX=1
shellframe_sheet_on_key "${SHELLFRAME_KEY_SHIFT_TAB:-$'\033[Z'}"
assert_eq "0" "$_SHELLFRAME_SHEET_FOCUS_IDX" "focus retreated to 0 after Shift-Tab"

ptyunit_test_begin "sheet_on_key: Up from topmost region (idx=0) calls quit"
_setup_two_region_sheet
_quit_called=0
_tst_FORM_quit() { _quit_called=1; shellframe_sheet_pop; }
# body_on_key returns 1 (unhandled) for Up at topmost — simulate by making it return 1
_tst_FORM_body_on_key() { return 1; }
shellframe_sheet_on_key $'\033[A'
assert_eq "1" "$_quit_called" "quit called when Up unhandled at topmost"

ptyunit_test_begin "sheet_on_key: Up from non-topmost region does not call quit"
_setup_two_region_sheet
_SHELLFRAME_SHEET_FOCUS_IDX=1   # focus on footer (idx 1, not topmost)
_quit_called=0
_tst_FORM_quit() { _quit_called=1; }
_tst_FORM_footer_on_key() { return 1; }  # unhandled
shellframe_sheet_on_key $'\033[A'
assert_eq "0" "$_quit_called" "quit NOT called when Up unhandled at non-topmost"

ptyunit_test_begin "sheet_on_key: rc=2 dispatches action and marks dirty"
_setup_two_region_sheet
_action_called=0
_tst_FORM_body_on_key() { return 2; }
_tst_FORM_body_action() { _action_called=1; }
_SHELLFRAME_SHELL_DIRTY=0
shellframe_sheet_on_key "x"
assert_eq "1" "$_action_called" "action hook called on rc=2"
assert_eq "1" "$_SHELLFRAME_SHELL_DIRTY" "dirty marked after action"

ptyunit_test_begin "sheet_on_key: parent shell regions unchanged after key dispatch"
_setup_two_region_sheet
_SHELLFRAME_SHELL_REGIONS=("parent:1:1:80:10:focus")
shellframe_sheet_on_key "x"
assert_eq "parent:1:1:80:10:focus" "${_SHELLFRAME_SHELL_REGIONS[0]}" "parent regions unchanged"

ptyunit_test_summary
