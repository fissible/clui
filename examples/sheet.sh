#!/usr/bin/env bash
# examples/sheet.sh — Two-step wizard using shellframe_sheet
#
# Demonstrates: sheet push from a parent shell screen, height change on
# transition, Back navigation, and Esc dismissal.
#
# Usage: ./examples/sheet.sh
# Prints submitted data to stdout on completion, or "Dismissed." if dismissed.

set -u
source "$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/shellframe.sh"

# ── App state ─────────────────────────────────────────────────────────────────

_WZ_RESULT=""   # set to "Submitted:name:city" on successful submit

# Field definitions: "label<TAB>cursor-ctx<TAB>type"
_WZ_STEP1_FIELDS=(
    $'Name\twzs1_name\ttext'
    $'Email\twzs1_email\ttext'
)
_WZ_STEP2_FIELDS=(
    $'City\twzs2_city\ttext'
    $'Zip\twzs2_zip\ttext'
)

# Initialize both forms at startup (each uses its own cursor contexts)
SHELLFRAME_FORM_FIELDS=("${_WZ_STEP1_FIELDS[@]}")
shellframe_form_init "step1"

SHELLFRAME_FORM_FIELDS=("${_WZ_STEP2_FIELDS[@]}")
shellframe_form_init "step2"

# ── Parent screen ─────────────────────────────────────────────────────────────

_wz_ROOT_render() {
    local _rows _cols
    _shellframe_shell_terminal_size _rows _cols
    shellframe_shell_region "content" 1 1 "$_cols" "$(( _rows - 1 ))"
    shellframe_shell_region "footer"  "$_rows" 1 "$_cols" 1 nofocus
}

_wz_ROOT_content_render() {
    local _top="$1" _left="$2" _width="$3"
    shellframe_fb_print "$_top" "$_left" "Welcome — press Enter to open the wizard"
}

_wz_ROOT_footer_render() {
    local _top="$1" _left="$2" _width="$3"
    shellframe_fb_fill "$_top" "$_left" "$_width" " " "${SHELLFRAME_GRAY:-}"
    shellframe_fb_print "$_top" "$_left" " Enter open wizard  q quit" "${SHELLFRAME_GRAY:-}"
}

_wz_ROOT_quit() { _SHELLFRAME_SHELL_NEXT="__QUIT__"; }

# Open the wizard sheet on Enter
_wz_ROOT_content_on_key() {
    if [[ "$1" == $'\n' || "$1" == $'\r' ]]; then
        shellframe_sheet_push "_wz" "STEP1"
        return 0
    fi
    return 1
}

# ── Sheet — Step 1 ────────────────────────────────────────────────────────────

_wz_STEP1_render() {
    SHELLFRAME_SHEET_HEIGHT=6
    shellframe_shell_region "form"   1 1 "$SHELLFRAME_SHEET_WIDTH" 4
    shellframe_shell_region "next"   5 1 "$SHELLFRAME_SHEET_WIDTH" 1
    shellframe_shell_region "footer" 6 1 "$SHELLFRAME_SHEET_WIDTH" 1 nofocus
}

_wz_STEP1_form_render() {
    SHELLFRAME_FORM_FIELDS=("${_WZ_STEP1_FIELDS[@]}")
    shellframe_form_render "step1" "$@"
}

_wz_STEP1_form_on_key() {
    SHELLFRAME_FORM_FIELDS=("${_WZ_STEP1_FIELDS[@]}")
    shellframe_form_on_key "step1" "$1"
}

_wz_STEP1_form_on_focus() {
    : # no-op; focus state tracked by form itself
}

_wz_STEP1_next_render() {
    local _top="$1" _left="$2" _width="$3"
    local _label="  [Next]  "
    shellframe_fb_print "$_top" "$(( _width - ${#_label} + 1 ))" "$_label"
}

_wz_STEP1_next_on_key() {
    if [[ "$1" == $'\n' || "$1" == $'\r' || "$1" == " " ]]; then
        return 2
    fi
    return 1
}

_wz_STEP1_next_action() {
    _SHELLFRAME_SHEET_NEXT="STEP2"
}

_wz_STEP1_footer_render() {
    local _top="$1" _left="$2" _width="$3"
    shellframe_fb_fill "$_top" "$_left" "$_width" " " "${SHELLFRAME_GRAY:-}"
    shellframe_fb_print "$_top" "$_left" \
        " Step 1 of 2  Tab next field  Enter select  Esc cancel" "${SHELLFRAME_GRAY:-}"
}

_wz_STEP1_quit() { shellframe_sheet_pop; }

# form submit (Enter in last field) → transition to step 2
_wz_STEP1_form_action() {
    _SHELLFRAME_SHEET_NEXT="STEP2"
}

# ── Sheet — Step 2 ────────────────────────────────────────────────────────────

_wz_STEP2_render() {
    SHELLFRAME_SHEET_HEIGHT=7
    local _half=$(( SHELLFRAME_SHEET_WIDTH / 2 ))
    shellframe_shell_region "form"   1 1 "$SHELLFRAME_SHEET_WIDTH" 4
    shellframe_shell_region "submit" 5 1 "$_half" 1
    shellframe_shell_region "back"   5 "$(( _half + 1 ))" "$_half" 1
    shellframe_shell_region "footer" 7 1 "$SHELLFRAME_SHEET_WIDTH" 1 nofocus
}

_wz_STEP2_form_render() {
    SHELLFRAME_FORM_FIELDS=("${_WZ_STEP2_FIELDS[@]}")
    shellframe_form_render "step2" "$@"
}

_wz_STEP2_form_on_key() {
    SHELLFRAME_FORM_FIELDS=("${_WZ_STEP2_FIELDS[@]}")
    shellframe_form_on_key "step2" "$1"
}

_wz_STEP2_form_on_focus() {
    : # no-op
}

_wz_STEP2_form_action() {
    # Enter in last field acts like Submit
    _wz_STEP2_submit_action
}

_wz_STEP2_submit_render() {
    local _top="$1" _left="$2"
    shellframe_fb_print "$_top" "$_left" "[Submit]"
}

_wz_STEP2_submit_on_key() {
    if [[ "$1" == $'\n' || "$1" == $'\r' || "$1" == " " ]]; then
        return 2
    fi
    return 1
}

_wz_STEP2_submit_action() {
    # Collect values from both steps
    local _step1_vals=()
    SHELLFRAME_FORM_FIELDS=("${_WZ_STEP1_FIELDS[@]}")
    shellframe_form_values "step1" _step1_vals
    local _name="${_step1_vals[0]:-}"

    local _step2_vals=()
    SHELLFRAME_FORM_FIELDS=("${_WZ_STEP2_FIELDS[@]}")
    shellframe_form_values "step2" _step2_vals
    local _city="${_step2_vals[0]:-}"

    _WZ_RESULT="Submitted:${_name}:${_city}"
    _SHELLFRAME_SHEET_NEXT="__POP__"
    _SHELLFRAME_SHELL_NEXT="__QUIT__"
}

_wz_STEP2_back_render() {
    local _top="$1" _left="$2"
    shellframe_fb_print "$_top" "$_left" "[Back]"
}

_wz_STEP2_back_on_key() {
    if [[ "$1" == $'\n' || "$1" == $'\r' || "$1" == " " ]]; then
        return 2
    fi
    return 1
}

_wz_STEP2_back_action() {
    _SHELLFRAME_SHEET_NEXT="STEP1"
}

_wz_STEP2_footer_render() {
    local _top="$1" _left="$2" _width="$3"
    shellframe_fb_fill "$_top" "$_left" "$_width" " " "${SHELLFRAME_GRAY:-}"
    shellframe_fb_print "$_top" "$_left" \
        " Step 2 of 2  Tab next field  Enter select  Esc cancel" "${SHELLFRAME_GRAY:-}"
}

_wz_STEP2_quit() { shellframe_sheet_pop; }

# ── Run ───────────────────────────────────────────────────────────────────────

shellframe_shell "_wz" "ROOT"

[[ -n "$_WZ_RESULT" ]] && printf '%s\n' "$_WZ_RESULT" || printf 'Dismissed.\n'
