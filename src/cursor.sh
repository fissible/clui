#!/usr/bin/env bash
# shellframe/src/cursor.sh — Text cursor model for input fields and editors
#
# COMPATIBILITY: bash 3.2+ (macOS default).
#
# ── Overview ──────────────────────────────────────────────────────────────────
#
# Manages text content and cursor position for single-line text input.
# Provides the editing primitives consumed by shellframe_input_field (Phase 3
# #12) and the text editor (#16).
#
# State is keyed by a context name ($ctx), allowing multiple independent
# editing states on the same screen (e.g. a query bar and a filter field).
# Context names must match [a-zA-Z0-9_]+.
#
# ── Dynamic globals (internal; do not access directly) ────────────────────────
#
#   _SHELLFRAME_CUR_${ctx}_POS   — cursor position (int, 0-based, range [0,len])
#   _SHELLFRAME_CUR_${ctx}_TEXT  — text content (string)
#
# ── Public API ─────────────────────────────────────────────────────────────────
#
#   shellframe_cur_init ctx [text]
#     Initialise (or reset) a cursor context with optional initial text.
#     Cursor starts at the end of text.
#
#   shellframe_cur_pos ctx [out_var]
#     Print current cursor position to stdout, or set out_var.
#
#   shellframe_cur_text ctx [out_var]
#     Print current text content to stdout, or set out_var.
#
#   shellframe_cur_set ctx text [pos]
#     Replace text content.  Cursor is placed at end unless pos is given
#     (clamped to [0, new_len]).
#
#   shellframe_cur_move ctx direction
#     Move cursor.  direction: left | right | home | end | word_left | word_right
#     Cursor is clamped to valid range; no-ops at boundaries are not errors.
#
#   shellframe_cur_insert ctx char
#     Insert $char at cursor position.  Cursor advances by 1.
#
#   shellframe_cur_backspace ctx
#     Delete the character before the cursor (Backspace).  No-op at pos 0.
#
#   shellframe_cur_delete ctx
#     Delete the character at the cursor (Delete key).  No-op at end of text.
#
#   shellframe_cur_kill_to_end ctx
#     Delete from cursor to end of text (Ctrl-K).
#
#   shellframe_cur_kill_to_start ctx
#     Delete from start of text to cursor (Ctrl-U).  Cursor moves to 0.
#
#   shellframe_cur_kill_word_left ctx
#     Delete the word to the left of the cursor (Ctrl-W).  Skips trailing
#     whitespace leftward, then non-whitespace leftward.

# ── Internal helper ───────────────────────────────────────────────────────────

# Validate ctx: must be non-empty and match [a-zA-Z0-9_]+
_shellframe_cur_validate_ctx() {
    local _ctx="$1"
    if [[ -z "$_ctx" || ! "$_ctx" =~ ^[a-zA-Z0-9_]+$ ]]; then
        printf 'shellframe_cur: invalid context name: %q\n' "$_ctx" >&2
        return 1
    fi
}

# ── shellframe_cur_init ────────────────────────────────────────────────────────

# Initialise or reset a cursor context.  Text defaults to ""; cursor starts
# at end of text (position == length).
shellframe_cur_init() {
    local _ctx="$1" _text="${2:-}"
    _shellframe_cur_validate_ctx "$_ctx" || return 1
    printf -v "_SHELLFRAME_CUR_${_ctx}_TEXT" '%s' "$_text"
    printf -v "_SHELLFRAME_CUR_${_ctx}_POS"  '%d' "${#_text}"
}

# ── shellframe_cur_pos ─────────────────────────────────────────────────────────

shellframe_cur_pos() {
    local _ctx="$1" _out="${2:-}"
    _shellframe_cur_validate_ctx "$_ctx" || return 1
    local _pos_var="_SHELLFRAME_CUR_${_ctx}_POS"
    if [[ -n "$_out" ]]; then
        printf -v "$_out" '%d' "${!_pos_var:-0}"
    else
        printf '%d\n' "${!_pos_var:-0}"
    fi
}

# ── shellframe_cur_text ────────────────────────────────────────────────────────

shellframe_cur_text() {
    local _ctx="$1" _out="${2:-}"
    _shellframe_cur_validate_ctx "$_ctx" || return 1
    local _text_var="_SHELLFRAME_CUR_${_ctx}_TEXT"
    if [[ -n "$_out" ]]; then
        printf -v "$_out" '%s' "${!_text_var:-}"
    else
        printf '%s\n' "${!_text_var:-}"
    fi
}

# ── shellframe_cur_set ─────────────────────────────────────────────────────────

# Replace text content.  Cursor is placed at end unless pos is given.
shellframe_cur_set() {
    local _ctx="$1" _text="$2" _pos="${3:-}"
    _shellframe_cur_validate_ctx "$_ctx" || return 1
    local _len="${#_text}"
    if [[ -z "$_pos" ]]; then
        _pos="$_len"
    else
        (( _pos < 0 ))    && _pos=0
        (( _pos > _len )) && _pos="$_len"
    fi
    printf -v "_SHELLFRAME_CUR_${_ctx}_TEXT" '%s' "$_text"
    printf -v "_SHELLFRAME_CUR_${_ctx}_POS"  '%d' "$_pos"
}

# ── shellframe_cur_move ────────────────────────────────────────────────────────

# Move cursor in $direction.  Clamped to [0, len]; boundary no-ops are not errors.
# Directions: left | right | home | end | word_left | word_right
shellframe_cur_move() {
    local _ctx="$1" _dir="$2"
    _shellframe_cur_validate_ctx "$_ctx" || return 1

    local _pos_var="_SHELLFRAME_CUR_${_ctx}_POS"
    local _text_var="_SHELLFRAME_CUR_${_ctx}_TEXT"
    local _pos="${!_pos_var:-0}"
    local _text="${!_text_var:-}"
    local _len="${#_text}"

    case "$_dir" in
        left)
            (( _pos > 0 )) && (( _pos-- )) || true
            ;;
        right)
            (( _pos < _len )) && (( _pos++ )) || true
            ;;
        home)
            _pos=0
            ;;
        end)
            _pos="$_len"
            ;;
        word_left)
            # Skip whitespace to the left, then non-whitespace to the left.
            while (( _pos > 0 )) && [[ "${_text:$(( _pos - 1 )):1}" == ' ' ]]; do
                (( _pos-- ))
            done
            while (( _pos > 0 )) && [[ "${_text:$(( _pos - 1 )):1}" != ' ' ]]; do
                (( _pos-- ))
            done
            ;;
        word_right)
            # Skip non-whitespace to the right, then whitespace to the right.
            while (( _pos < _len )) && [[ "${_text:$_pos:1}" != ' ' ]]; do
                (( _pos++ ))
            done
            while (( _pos < _len )) && [[ "${_text:$_pos:1}" == ' ' ]]; do
                (( _pos++ ))
            done
            ;;
        *)
            printf 'shellframe_cur_move: unknown direction: %s\n' "$_dir" >&2
            return 1
            ;;
    esac

    printf -v "$_pos_var" '%d' "$_pos"
}

# ── shellframe_cur_insert ──────────────────────────────────────────────────────

# Insert $char at cursor position.  Cursor advances by 1.
shellframe_cur_insert() {
    local _ctx="$1" _char="$2"
    _shellframe_cur_validate_ctx "$_ctx" || return 1

    local _pos_var="_SHELLFRAME_CUR_${_ctx}_POS"
    local _text_var="_SHELLFRAME_CUR_${_ctx}_TEXT"
    local _pos="${!_pos_var:-0}"
    local _text="${!_text_var:-}"

    printf -v "$_text_var" '%s' "${_text:0:$_pos}${_char}${_text:$_pos}"
    printf -v "$_pos_var"  '%d' "$(( _pos + 1 ))"
}

# ── shellframe_cur_backspace ───────────────────────────────────────────────────

# Delete the character before the cursor (Backspace).  No-op at pos 0.
shellframe_cur_backspace() {
    local _ctx="$1"
    _shellframe_cur_validate_ctx "$_ctx" || return 1

    local _pos_var="_SHELLFRAME_CUR_${_ctx}_POS"
    local _text_var="_SHELLFRAME_CUR_${_ctx}_TEXT"
    local _pos="${!_pos_var:-0}"
    local _text="${!_text_var:-}"

    (( _pos == 0 )) && return 0

    printf -v "$_text_var" '%s' "${_text:0:$(( _pos - 1 ))}${_text:$_pos}"
    printf -v "$_pos_var"  '%d' "$(( _pos - 1 ))"
}

# ── shellframe_cur_delete ──────────────────────────────────────────────────────

# Delete the character at the cursor (Delete key).  No-op at end of text.
shellframe_cur_delete() {
    local _ctx="$1"
    _shellframe_cur_validate_ctx "$_ctx" || return 1

    local _pos_var="_SHELLFRAME_CUR_${_ctx}_POS"
    local _text_var="_SHELLFRAME_CUR_${_ctx}_TEXT"
    local _pos="${!_pos_var:-0}"
    local _text="${!_text_var:-}"
    local _len="${#_text}"

    (( _pos >= _len )) && return 0

    printf -v "$_text_var" '%s' "${_text:0:$_pos}${_text:$(( _pos + 1 ))}"
    # _pos unchanged — cursor stays at the same index
}

# ── shellframe_cur_kill_to_end ─────────────────────────────────────────────────

# Delete from cursor to end of text (Ctrl-K).  No-op if cursor is at end.
shellframe_cur_kill_to_end() {
    local _ctx="$1"
    _shellframe_cur_validate_ctx "$_ctx" || return 1

    local _pos_var="_SHELLFRAME_CUR_${_ctx}_POS"
    local _text_var="_SHELLFRAME_CUR_${_ctx}_TEXT"
    local _pos="${!_pos_var:-0}"
    local _text="${!_text_var:-}"

    printf -v "$_text_var" '%s' "${_text:0:$_pos}"
    # _pos unchanged — cursor already points to the new end
}

# ── shellframe_cur_kill_to_start ───────────────────────────────────────────────

# Delete from start of text to cursor (Ctrl-U).  Cursor moves to 0.
shellframe_cur_kill_to_start() {
    local _ctx="$1"
    _shellframe_cur_validate_ctx "$_ctx" || return 1

    local _pos_var="_SHELLFRAME_CUR_${_ctx}_POS"
    local _text_var="_SHELLFRAME_CUR_${_ctx}_TEXT"
    local _pos="${!_pos_var:-0}"
    local _text="${!_text_var:-}"

    printf -v "$_text_var" '%s' "${_text:$_pos}"
    printf -v "$_pos_var"  '%d' 0
}

# ── shellframe_cur_kill_word_left ──────────────────────────────────────────────

# Delete the word to the left of the cursor (Ctrl-W).
# Skips trailing whitespace leftward, then non-whitespace leftward.
# No-op if cursor is at position 0.
shellframe_cur_kill_word_left() {
    local _ctx="$1"
    _shellframe_cur_validate_ctx "$_ctx" || return 1

    local _pos_var="_SHELLFRAME_CUR_${_ctx}_POS"
    local _text_var="_SHELLFRAME_CUR_${_ctx}_TEXT"
    local _pos="${!_pos_var:-0}"
    local _text="${!_text_var:-}"

    (( _pos == 0 )) && return 0

    local _new_pos="$_pos"
    # Skip trailing whitespace to the left.
    while (( _new_pos > 0 )) && [[ "${_text:$(( _new_pos - 1 )):1}" == ' ' ]]; do
        (( _new_pos-- ))
    done
    # Skip non-whitespace to the left.
    while (( _new_pos > 0 )) && [[ "${_text:$(( _new_pos - 1 )):1}" != ' ' ]]; do
        (( _new_pos-- ))
    done

    printf -v "$_text_var" '%s' "${_text:0:$_new_pos}${_text:$_pos}"
    printf -v "$_pos_var"  '%d' "$_new_pos"
}
