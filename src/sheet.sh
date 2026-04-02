#!/usr/bin/env bash
# shellframe/src/sheet.sh — Sheet navigation primitive
#
# A sheet is a partial overlay that sits above the current shellframe_shell
# screen. It shows one frozen dimmed row of the underlying screen at the top
# (the "back strip") and renders its own content from row 2 downward.
#
# Public API:
#   shellframe_sheet_push prefix screen  — open a sheet
#   shellframe_sheet_pop                 — schedule sheet dismissal
#   shellframe_sheet_active              — 0=true if a sheet is open
#   shellframe_sheet_draw rows cols      — called by shell.sh draw delegation
#   shellframe_sheet_on_key key          — called by shell.sh key delegation
#
# Consumer hooks (identical convention to shellframe_shell):
#   PREFIX_SCREEN_render()               — layout; set SHELLFRAME_SHEET_HEIGHT
#   PREFIX_SCREEN_REGION_render t l w h  — region render
#   PREFIX_SCREEN_REGION_on_key key      — region key handler (rc: 0=handled, 1=unhandled, 2=action)
#   PREFIX_SCREEN_REGION_on_focus active — focus change notification
#   PREFIX_SCREEN_REGION_action()        — called when on_key returns 2
#   PREFIX_SCREEN_quit()                 — called on Esc or Up-from-topmost
#
# Row coordinates in consumer hooks are sheet-relative: row 1 = first content
# row (screen row 2, immediately below the back strip). Use $SHELLFRAME_SHEET_WIDTH.
#
# KNOWN LIMITATION: back-strip dimming uses \033[2m...\033[22m. Rows containing
# \033[0m mid-string will have dim cancelled at that point — best-effort for v1.

# ── State globals ─────────────────────────────────────────────────────────────

_SHELLFRAME_SHEET_ACTIVE=0          # 0|1 — whether a sheet is currently open
_SHELLFRAME_SHEET_PREFIX=""         # consumer prefix (e.g. "_myapp")
_SHELLFRAME_SHEET_SCREEN=""         # current screen within the sheet
_SHELLFRAME_SHEET_NEXT=""           # next screen name; "__POP__" to dismiss
_SHELLFRAME_SHEET_FROZEN_ROWS=()    # full-screen framebuffer snapshot at push time
SHELLFRAME_SHEET_HEIGHT=0           # consumer sets in render hook; 0 = fill to bottom
SHELLFRAME_SHEET_WIDTH=0            # set before render hook; read-only for consumers
# Sheet-local focus / region registry (swapped in/out each frame)
_SHELLFRAME_SHEET_REGIONS=()
_SHELLFRAME_SHEET_FOCUS_RING=()
_SHELLFRAME_SHEET_FOCUS_IDX=0
_SHELLFRAME_SHEET_FOCUS_REQUEST=""

# ── shellframe_sheet_push ─────────────────────────────────────────────────────

shellframe_sheet_push() {
    local _prefix="$1" _screen="$2"

    if (( _SHELLFRAME_SHEET_ACTIVE )); then
        printf 'shellframe_sheet_push: sheet already active (stacking not supported in v1)\n' >&2
        return 1
    fi

    _SHELLFRAME_SHEET_ACTIVE=1
    _SHELLFRAME_SHEET_PREFIX="$_prefix"
    _SHELLFRAME_SHEET_SCREEN="$_screen"
    _SHELLFRAME_SHEET_NEXT=""

    # Snapshot current framebuffer for back strip and below-sheet frozen content
    local _rows="${_SHELLFRAME_SHELL_ROWS:-24}"
    _SHELLFRAME_SHEET_FROZEN_ROWS=()
    local _r
    for (( _r=1; _r<=_rows; _r++ )); do
        # Use :- default (not guard form) — _SF_ROW_CURR exists as an array;
        # bash 3.2 only treats the array itself as unbound, not missing keys.
        _SHELLFRAME_SHEET_FROZEN_ROWS[$_r]="${_SF_ROW_CURR[$_r]:-}"
    done

    # Reset sheet-local focus state (first frame starts at idx 0)
    _SHELLFRAME_SHEET_REGIONS=()
    _SHELLFRAME_SHEET_FOCUS_RING=()
    _SHELLFRAME_SHEET_FOCUS_IDX=0
    _SHELLFRAME_SHEET_FOCUS_REQUEST=""

    shellframe_shell_mark_dirty
}

# ── shellframe_sheet_pop ──────────────────────────────────────────────────────

shellframe_sheet_pop() {
    _SHELLFRAME_SHEET_NEXT="__POP__"
}

# ── shellframe_sheet_active ───────────────────────────────────────────────────

shellframe_sheet_active() {
    (( _SHELLFRAME_SHEET_ACTIVE ))
}

# ── shellframe_sheet_draw ─────────────────────────────────────────────────────
#
# Called by shell.sh when _SHELLFRAME_SHEET_ACTIVE=1 (replaces normal draw).
# Handles screen transitions and __POP__ dismissal, then renders the sheet
# frame: frozen back strip + sheet content + frozen content below sheet.
#
# rows cols — current terminal dimensions (provided by shell.sh delegation)

shellframe_sheet_draw() {
    local _rows="$1" _cols="$2"
    local _prefix="$_SHELLFRAME_SHEET_PREFIX"
    local _screen="$_SHELLFRAME_SHEET_SCREEN"

    # ── Screen transition / pop ───────────────────────────────────────────────
    if [[ -n "${_SHELLFRAME_SHEET_NEXT:-}" ]]; then
        if [[ "$_SHELLFRAME_SHEET_NEXT" == "__POP__" ]]; then
            # Restore full parent screen from frozen rows, then clear sheet state
            shellframe_fb_frame_start "$_rows" "$_cols"
            local _r
            for (( _r=1; _r<=_rows; _r++ )); do
                shellframe_fb_print_ansi "$_r" 1 "${_SHELLFRAME_SHEET_FROZEN_ROWS[$_r]:-}"
            done
            shellframe_screen_flush
            _SHELLFRAME_SHEET_ACTIVE=0
            _SHELLFRAME_SHEET_PREFIX=""
            _SHELLFRAME_SHEET_SCREEN=""
            _SHELLFRAME_SHEET_NEXT=""
            _SHELLFRAME_SHEET_FROZEN_ROWS=()
            _SHELLFRAME_SHEET_REGIONS=()
            _SHELLFRAME_SHEET_FOCUS_RING=()
            _SHELLFRAME_SHEET_FOCUS_IDX=0
            _SHELLFRAME_SHEET_FOCUS_REQUEST=""
            SHELLFRAME_SHEET_HEIGHT=0
            SHELLFRAME_SHEET_WIDTH=0
            shellframe_shell_mark_dirty
            return
        fi
        # Internal screen transition
        _SHELLFRAME_SHEET_SCREEN="$_SHELLFRAME_SHEET_NEXT"
        _prefix="$_SHELLFRAME_SHEET_PREFIX"
        _screen="$_SHELLFRAME_SHEET_SCREEN"
        _SHELLFRAME_SHEET_NEXT=""
        _SHELLFRAME_SHEET_REGIONS=()
        _SHELLFRAME_SHEET_FOCUS_RING=()
        _SHELLFRAME_SHEET_FOCUS_IDX=0
        _SHELLFRAME_SHEET_FOCUS_REQUEST=""
    fi

    # ── Registry swap in ──────────────────────────────────────────────────────
    # Save parent shell's focus state to locals
    local _saved_regions=()
    local _saved_ring=()
    local _saved_idx="$_SHELLFRAME_SHELL_FOCUS_IDX"
    local _saved_req="$_SHELLFRAME_SHELL_FOCUS_REQUEST"
    _saved_regions=("${_SHELLFRAME_SHELL_REGIONS[@]+"${_SHELLFRAME_SHELL_REGIONS[@]}"}")
    _saved_ring=("${_SHELLFRAME_SHELL_FOCUS_RING[@]+"${_SHELLFRAME_SHELL_FOCUS_RING[@]}"}")
    # Load sheet focus state into shell globals (for focus_init / focus_owner)
    _SHELLFRAME_SHELL_FOCUS_RING=("${_SHELLFRAME_SHEET_FOCUS_RING[@]+"${_SHELLFRAME_SHEET_FOCUS_RING[@]}"}")
    _SHELLFRAME_SHELL_FOCUS_IDX="$_SHELLFRAME_SHEET_FOCUS_IDX"
    _SHELLFRAME_SHELL_FOCUS_REQUEST="$_SHELLFRAME_SHEET_FOCUS_REQUEST"

    # ── Frame setup ───────────────────────────────────────────────────────────
    shellframe_fb_frame_start "$_rows" "$_cols"
    SHELLFRAME_SHEET_WIDTH="$_cols"
    SHELLFRAME_SHEET_HEIGHT=0

    # Reset region registry for re-registration by the render hook
    _SHELLFRAME_SHELL_REGIONS=()
    shellframe_widget_clear

    # ── Render hook: consumer registers regions + optionally sets SHEET_HEIGHT
    "${_prefix}_${_screen}_render"

    # ── Resolve sheet bounds ──────────────────────────────────────────────────
    local _sheet_top=2
    local _sheet_h
    if (( SHELLFRAME_SHEET_HEIGHT > 0 )); then
        _sheet_h="$SHELLFRAME_SHEET_HEIGHT"
    else
        _sheet_h=$(( _rows - 1 ))
    fi
    local _sheet_bottom=$(( _sheet_top + _sheet_h - 1 ))

    # ── Frozen rows into framebuffer ──────────────────────────────────────────
    # Row 1 (back strip): show dimmed parent content
    shellframe_fb_print_ansi 1 1 $'\033[2m'"${_SHELLFRAME_SHEET_FROZEN_ROWS[1]:-}"$'\033[22m'
    # Rows below sheet: show dimmed parent content (if sheet doesn't fill to bottom)
    local _r
    for (( _r=_sheet_bottom+1; _r<=_rows; _r++ )); do
        shellframe_fb_print_ansi "$_r" 1 $'\033[2m'"${_SHELLFRAME_SHEET_FROZEN_ROWS[$_r]:-}"$'\033[22m'
    done

    # ── Rebuild focus ring ────────────────────────────────────────────────────
    _shellframe_shell_focus_init

    # ── Fire on_focus for each region ─────────────────────────────────────────
    local _focused
    _shellframe_shell_focus_owner _focused
    local _entry _n
    for _entry in "${_SHELLFRAME_SHELL_REGIONS[@]+"${_SHELLFRAME_SHELL_REGIONS[@]}"}"; do
        _n="${_entry%%:*}"
        if declare -f "${_prefix}_${_screen}_${_n}_on_focus" >/dev/null 2>&1; then
            if [[ "$_n" == "$_focused" ]]; then
                "${_prefix}_${_screen}_${_n}_on_focus" 1
            else
                "${_prefix}_${_screen}_${_n}_on_focus" 0
            fi
        fi
    done

    # ── Render sheet regions (with sheet row offset applied) ──────────────────
    _SF_ROW_OFFSET=$(( _sheet_top - 1 ))
    for _entry in "${_SHELLFRAME_SHELL_REGIONS[@]+"${_SHELLFRAME_SHELL_REGIONS[@]}"}"; do
        _n="${_entry%%:*}"
        local _rest="${_entry#*:}"
        local _top="${_rest%%:*}"; _rest="${_rest#*:}"
        local _left="${_rest%%:*}"; _rest="${_rest#*:}"
        local _w="${_rest%%:*}"; _rest="${_rest#*:}"
        local _h="${_rest%%:*}"
        if declare -f "${_prefix}_${_screen}_${_n}_render" >/dev/null 2>&1; then
            "${_prefix}_${_screen}_${_n}_render" "$_top" "$_left" "$_w" "$_h"
        fi
    done
    _SF_ROW_OFFSET=0

    # ── Registry swap out ─────────────────────────────────────────────────────
    # Save updated sheet focus state
    _SHELLFRAME_SHEET_REGIONS=("${_SHELLFRAME_SHELL_REGIONS[@]+"${_SHELLFRAME_SHELL_REGIONS[@]}"}")
    _SHELLFRAME_SHEET_FOCUS_RING=("${_SHELLFRAME_SHELL_FOCUS_RING[@]+"${_SHELLFRAME_SHELL_FOCUS_RING[@]}"}")
    _SHELLFRAME_SHEET_FOCUS_IDX="$_SHELLFRAME_SHELL_FOCUS_IDX"
    _SHELLFRAME_SHEET_FOCUS_REQUEST="$_SHELLFRAME_SHELL_FOCUS_REQUEST"
    # Restore parent shell registry
    _SHELLFRAME_SHELL_REGIONS=("${_saved_regions[@]+"${_saved_regions[@]}"}")
    _SHELLFRAME_SHELL_FOCUS_RING=("${_saved_ring[@]+"${_saved_ring[@]}"}")
    _SHELLFRAME_SHELL_FOCUS_IDX="$_saved_idx"
    _SHELLFRAME_SHELL_FOCUS_REQUEST="$_saved_req"

    # ── Flush ─────────────────────────────────────────────────────────────────
    shellframe_screen_flush
}
