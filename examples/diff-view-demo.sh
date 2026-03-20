#!/usr/bin/env bash
# diff-view-demo.sh — Visual test for the diff view widget
#
# Shows a side-by-side diff of the last 2 commits in a git repo.
# Up/Down/PgUp/PgDn to scroll. q to quit.
#
# Usage:
#   bash diff-view-demo.sh                     # diff HEAD~1 in current repo
#   bash diff-view-demo.sh /path/to/repo       # diff HEAD~1 in specified repo
#   bash diff-view-demo.sh /path/to/repo 3     # diff HEAD~3

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../shellframe.sh"

REPO="${1:-$(pwd)}"
RANGE="${2:-1}"

cd "$REPO" || { printf 'Not a valid directory: %s\n' "$REPO"; exit 1; }
git rev-parse --show-toplevel &>/dev/null || { printf 'Not a git repo: %s\n' "$REPO"; exit 1; }

# Parse the diff
shellframe_diff_parse < <(git diff "HEAD~${RANGE}")

if (( SHELLFRAME_DIFF_ROW_COUNT == 0 )); then
    printf 'No diff output for HEAD~%s in %s\n' "$RANGE" "$REPO"
    exit 0
fi

# Initialise the diff view widget
shellframe_diff_view_init

# ── Screen: ROOT ────────────────────────────────────────────────────────────

_dv_ROOT_render() {
    local _rows _cols
    _shellframe_shell_terminal_size _rows _cols
    shellframe_shell_region header 1 1 "$_cols" 1 nofocus
    shellframe_shell_region diff   2 1 "$_cols" $(( _rows - 2 ))
    shellframe_shell_region footer "$_rows" 1 "$_cols" 1 nofocus
}

_dv_ROOT_header_render() {
    local _top="$1" _left="$2" _w="$3"
    printf '\033[%d;%dH%s' "$_top" "$_left" "${SHELLFRAME_REVERSE:-}" >&3
    local _title
    _title=$(printf ' Diff: HEAD~%s  (%d rows)' "$RANGE" "$SHELLFRAME_DIFF_ROW_COUNT")
    printf '%s' "$_title" >&3
    local _pad=$(( _w - ${#_title} ))
    local _i; for (( _i=0; _i < _pad; _i++ )); do printf ' ' >&3; done
    printf '%s' "${SHELLFRAME_RESET:-}" >&3
}

_dv_ROOT_diff_render() {
    shellframe_diff_view_render "$@"
}

_dv_ROOT_diff_on_key() {
    shellframe_diff_view_on_key "$1"
}

_dv_ROOT_diff_on_focus() {
    shellframe_diff_view_on_focus "$1"
}

_dv_ROOT_footer_render() {
    local _top="$1" _left="$2" _w="$3"
    printf '\033[%d;%dH%s' "$_top" "$_left" "${SHELLFRAME_GRAY:-}" >&3
    local _msg="Up/Down: scroll  PgUp/PgDn: page  Home/End: jump  q: quit"
    printf '%s' "$_msg" >&3
    local _pad=$(( _w - ${#_msg} ))
    local _i; for (( _i=0; _i < _pad; _i++ )); do printf ' ' >&3; done
    printf '%s' "${SHELLFRAME_RESET:-}" >&3
}

_dv_ROOT_quit() {
    _SHELLFRAME_SHELL_NEXT="__QUIT__"
}

# ── Run ─────────────────────────────────────────────────────────────────────

shellframe_shell "_dv" "ROOT"
