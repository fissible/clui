#!/usr/bin/env bash
# shellframe/src/widgets/autocomplete.sh — Autocomplete overlay
#
# COMPATIBILITY: bash 3.2+ (macOS default).
# REQUIRES: src/cursor.sh, src/widgets/input-field.sh, src/widgets/editor.sh,
#           src/widgets/context-menu.sh sourced first (via shellframe.sh).
#
# ── Overview ──────────────────────────────────────────────────────────────────
#
# Attaches to a field ("field" mode) or editor ("editor" mode) context and
# provides word-completion suggestions via a provider callback.
#
# The autocomplete overlay is triggered by the consumer (on_key handler or
# explicit shellframe_ac_trigger call).  It extracts the word-under-cursor,
# calls the provider, and presents matches in a context-menu popup.
#
# ── Public globals ─────────────────────────────────────────────────────────────
#
#   SHELLFRAME_AC_PROVIDER       — name of the provider function (required)
#                                  Signature: provider_fn prefix out_array_name
#   SHELLFRAME_AC_TRIGGER        — "auto" (default) | "manual"
#   SHELLFRAME_AC_MAX_HEIGHT     — max visible rows in popup (default: 8)
#   SHELLFRAME_AC_RESULT         — set to accepted completion string on accept
#
# ── Internal state ─────────────────────────────────────────────────────────────
#
#   _SHELLFRAME_AC_CTX           — attached context name
#   _SHELLFRAME_AC_MODE          — "field" | "editor"
#   _SHELLFRAME_AC_ACTIVE        — 1 if popup is visible, 0 otherwise
#   _SHELLFRAME_AC_MATCHES       — array of current match strings
#   _SHELLFRAME_AC_PREFIX        — current word prefix
#
# ── Public API ─────────────────────────────────────────────────────────────────
#
#   shellframe_ac_attach ctx mode
#     Attach to a context.  mode is "field" or "editor".
#     Resets all internal state.
#
#   shellframe_ac_detach
#     Detach and clear all state.
#
#   _shellframe_ac_prefix out_var
#     Extract the word-under-cursor from the attached context.
#     Word characters: [a-zA-Z0-9_.\-]
#     Sets out_var to the extracted prefix (may be empty).
#
#   shellframe_ac_dismiss
#     Hide the popup — sets _SHELLFRAME_AC_ACTIVE=0, clears matches/prefix.

# ── Public globals ─────────────────────────────────────────────────────────────

SHELLFRAME_AC_PROVIDER=""
SHELLFRAME_AC_TRIGGER="auto"
SHELLFRAME_AC_MAX_HEIGHT=8
SHELLFRAME_AC_RESULT=""

# ── Internal state ─────────────────────────────────────────────────────────────

_SHELLFRAME_AC_CTX=""
_SHELLFRAME_AC_MODE=""
_SHELLFRAME_AC_ACTIVE=0
_SHELLFRAME_AC_MATCHES=()
_SHELLFRAME_AC_PREFIX=""

# ── shellframe_ac_attach ───────────────────────────────────────────────────────

# Attach the autocomplete module to a cursor context (field or editor).
# Resets all transient state so a fresh session starts clean.
shellframe_ac_attach() {
    local _ctx="$1" _mode="$2"
    _SHELLFRAME_AC_CTX="$_ctx"
    _SHELLFRAME_AC_MODE="$_mode"
    _SHELLFRAME_AC_ACTIVE=0
    _SHELLFRAME_AC_MATCHES=()
    _SHELLFRAME_AC_PREFIX=""
}

# ── shellframe_ac_detach ───────────────────────────────────────────────────────

# Detach from the current context and clear all autocomplete state.
shellframe_ac_detach() {
    _SHELLFRAME_AC_CTX=""
    _SHELLFRAME_AC_MODE=""
    _SHELLFRAME_AC_ACTIVE=0
    _SHELLFRAME_AC_MATCHES=()
    _SHELLFRAME_AC_PREFIX=""
    SHELLFRAME_AC_RESULT=""
}

# ── _shellframe_ac_prefix ─────────────────────────────────────────────────────

# Extract the word-under-cursor from the attached context.
#
# For "field" mode: reads text and position via shellframe_cur_text / shellframe_cur_pos.
# For "editor" mode: reads the current line and column via shellframe_editor_line
#   and shellframe_editor_col / shellframe_editor_row.
#
# Word characters are [a-zA-Z0-9_.\-].  Walks leftward from the cursor position
# until a non-word character (or the start of the string) is found.
#
# Usage: _shellframe_ac_prefix out_var
_shellframe_ac_prefix() {
    local _out_var="$1"
    local _ctx="$_SHELLFRAME_AC_CTX"
    local _mode="$_SHELLFRAME_AC_MODE"
    local _text="" _pos=0

    if [[ "$_mode" == "field" ]]; then
        shellframe_cur_text "$_ctx" _text
        shellframe_cur_pos  "$_ctx" _pos
    else
        # editor mode
        local _row
        _row="$(shellframe_editor_row "$_ctx")"
        _text="$(shellframe_editor_line "$_ctx" "$_row")"
        _pos="$(shellframe_editor_col "$_ctx")"
    fi

    # Walk leftward from _pos matching word characters [a-zA-Z0-9_.\-]
    local _start="$_pos"
    while (( _start > 0 )); do
        local _ch="${_text:$(( _start - 1 )):1}"
        if [[ "$_ch" =~ [a-zA-Z0-9_.\ -] ]]; then
            # Exclude space explicitly — it's not a word char
            if [[ "$_ch" == ' ' ]]; then
                break
            fi
            (( _start-- ))
        else
            break
        fi
    done

    local _prefix="${_text:$_start:$(( _pos - _start ))}"
    printf -v "$_out_var" '%s' "$_prefix"
}

# ── shellframe_ac_dismiss ──────────────────────────────────────────────────────

# Hide the autocomplete popup.  Sets _SHELLFRAME_AC_ACTIVE=0 and clears
# transient match/prefix state.
shellframe_ac_dismiss() {
    _SHELLFRAME_AC_ACTIVE=0
    _SHELLFRAME_AC_MATCHES=()
    _SHELLFRAME_AC_PREFIX=""
}
