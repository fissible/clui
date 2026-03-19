#!/usr/bin/env bash
# shellframe/src/sync-scroll.sh — Synchronized scrolling across panes
#
# COMPATIBILITY: bash 3.2+ (macOS default).
# REQUIRES: src/scroll.sh sourced first.
#
# ── Overview ──────────────────────────────────────────────────────────────────
#
# Links multiple scroll contexts so they move in lockstep.  When one context
# scrolls, all linked contexts scroll to the same offset.
#
# Designed for side-by-side diff views where panes must stay aligned.
# Supports an optional line-mapping table for diffs where left and right have
# different line counts (not yet implemented — for now, 1:1 offset sync).
#
# ── Dynamic globals (internal) ──────────────────────────────────────────────
#
#   _SHELLFRAME_SYNC_${group}_MEMBERS  — colon-separated list of scroll contexts
#   _SHELLFRAME_SYNC_${group}_LOCKED   — 1 (synced) | 0 (independent)
#
# ── Public API ──────────────────────────────────────────────────────────────
#
#   shellframe_sync_scroll_init group ctx1 ctx2 [ctx3]
#     Create a sync group linking 2–3 scroll contexts.
#
#   shellframe_sync_scroll_move group source_ctx direction [amount]
#     Scroll source_ctx, then propagate the resulting offset to all other
#     members.  Use this instead of shellframe_scroll_move when synced.
#
#   shellframe_sync_scroll_set group locked
#     Set lock state: 1 = synced (default), 0 = independent scrolling.
#
#   shellframe_sync_scroll_locked group
#     Return 0 (true) if locked, 1 (false) if unlocked.

# ── Internal helper ─────────────────────────────────────────────────────────

_shellframe_sync_validate_group() {
    local _g="$1"
    if [[ -z "$_g" || ! "$_g" =~ ^[a-zA-Z0-9_]+$ ]]; then
        printf 'shellframe_sync_scroll: invalid group name: %q\n' "$_g" >&2
        return 1
    fi
}

# ── shellframe_sync_scroll_init ─────────────────────────────────────────────

shellframe_sync_scroll_init() {
    local _group="$1"
    shift
    _shellframe_sync_validate_group "$_group" || return 1

    local _members=""
    while (( $# > 0 )); do
        [[ -n "$_members" ]] && _members="${_members}:"
        _members="${_members}${1}"
        shift
    done

    printf -v "_SHELLFRAME_SYNC_${_group}_MEMBERS" '%s' "$_members"
    printf -v "_SHELLFRAME_SYNC_${_group}_LOCKED"  '%d' 1
}

# ── shellframe_sync_scroll_set ──────────────────────────────────────────────

shellframe_sync_scroll_set() {
    local _group="$1" _locked="$2"
    _shellframe_sync_validate_group "$_group" || return 1
    printf -v "_SHELLFRAME_SYNC_${_group}_LOCKED" '%d' "$_locked"
}

# ── shellframe_sync_scroll_locked ───────────────────────────────────────────

shellframe_sync_scroll_locked() {
    local _group="$1"
    _shellframe_sync_validate_group "$_group" || return 1
    local _var="_SHELLFRAME_SYNC_${_group}_LOCKED"
    (( ${!_var:-1} == 1 ))
}

# ── shellframe_sync_scroll_move ─────────────────────────────────────────────

# Scroll the source context, then propagate to all other members.
shellframe_sync_scroll_move() {
    local _group="$1" _source="$2" _dir="$3" _amt="${4:-1}"
    _shellframe_sync_validate_group "$_group" || return 1

    # Move the source context
    shellframe_scroll_move "$_source" "$_dir" "$_amt"

    # If unlocked, we're done
    local _locked_var="_SHELLFRAME_SYNC_${_group}_LOCKED"
    (( ${!_locked_var:-1} == 0 )) && return 0

    # Read the source's new offset
    local _new_top _new_left
    shellframe_scroll_top "$_source" _new_top
    shellframe_scroll_left "$_source" _new_left

    # Propagate to all other members
    local _members_var="_SHELLFRAME_SYNC_${_group}_MEMBERS"
    local _members="${!_members_var:-}"
    local _remaining="$_members"

    while [[ -n "$_remaining" ]]; do
        local _ctx="${_remaining%%:*}"
        if [[ "$_remaining" == *":"* ]]; then
            _remaining="${_remaining#*:}"
        else
            _remaining=""
        fi

        [[ "$_ctx" == "$_source" ]] && continue

        # Set the member's offset directly
        local _top_var="_SHELLFRAME_SCROLL_${_ctx}_TOP"
        local _left_var="_SHELLFRAME_SCROLL_${_ctx}_LEFT"
        local _rows_var="_SHELLFRAME_SCROLL_${_ctx}_ROWS"
        local _cols_var="_SHELLFRAME_SCROLL_${_ctx}_COLS"
        local _vrows_var="_SHELLFRAME_SCROLL_${_ctx}_VROWS"
        local _vcols_var="_SHELLFRAME_SCROLL_${_ctx}_VCOLS"

        local _rows="${!_rows_var:-0}"
        local _cols="${!_cols_var:-0}"
        local _vrows="${!_vrows_var:-0}"
        local _vcols="${!_vcols_var:-0}"

        # Clamp to this context's valid range
        local _max_top=$(( _rows - _vrows ))
        local _max_left=$(( _cols - _vcols ))
        (( _max_top < 0 ))  && _max_top=0
        (( _max_left < 0 )) && _max_left=0

        local _clamped_top="$_new_top"
        local _clamped_left="$_new_left"
        (( _clamped_top > _max_top ))   && _clamped_top="$_max_top"
        (( _clamped_top < 0 ))          && _clamped_top=0
        (( _clamped_left > _max_left )) && _clamped_left="$_max_left"
        (( _clamped_left < 0 ))         && _clamped_left=0

        printf -v "$_top_var"  '%d' "$_clamped_top"
        printf -v "$_left_var" '%d' "$_clamped_left"
    done
}
