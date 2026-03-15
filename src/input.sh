#!/usr/bin/env bash
# shellframe/src/input.sh — Keyboard input reading
#
# COMPATIBILITY: bash 3.2+ (macOS default). Note: {varname} fd allocation
# (exec {fd}>&1) requires bash 4.1+; use fixed fd numbers (e.g. fd 3) instead.
#
# GOTCHA 1 — decimal timeouts: bash 3.2 does not accept fractional values for
# `read -t`. Use integers only. `-t 0.1` produces "invalid timeout
# specification" and silently fails, leaving the ESC byte as the entire key
# value while `[B` etc. remain in the buffer and echo on the next read.
#
# GOTCHA 2 — read -n2 with stty min 1: with `stty min 1 time 0` set, the OS
# satisfies a read() syscall as soon as ONE byte is available. bash's
# `read -nN` reads AT MOST N chars, so `read -n2` may return with just 1 char
# (the `[`), leaving `A`/`B`/`C`/`D` in the buffer unread. Read escape
# sequences one byte at a time instead.
#
# GOTCHA 3 — do not match \x03 (Ctrl+C) in the key handler: with stty -icanon
# and isig still enabled (the default), Ctrl+C sends SIGINT to the process
# rather than putting a \x03 byte in the input stream. Matching \x03 will
# instead catch a buffered byte left over from a previous Ctrl+C that
# interrupted a prior command, causing the TUI to immediately "abort" on
# startup. Handle Ctrl+C exclusively via trap.
#
# GOTCHA 4 — case pattern glob: in a bash `case` statement, `[A` is a glob
# bracket expression that matches the single character `A`, not the 2-char
# string `[A`. Store sequences in variables and compare with `[[ == ]]`.
#
# GOTCHA 5 — bash `read` converts \r to \n internally: even with stty -icrnl
# set (so the PTY line discipline does NOT translate CR→LF), bash's own `read`
# builtin converts \r (0x0D) to \n (0x0A) before storing the value. This means
# SHELLFRAME_KEY_ENTER must be $'\n', not $'\r'.
#   Additionally, `read -r -n1` (default \n delimiter) returns an empty string
#   when \n is received (because \n is the delimiter and is stripped). To
#   capture \n as a value, use `-d ''` (NUL delimiter) so that \n is treated
#   as a regular character instead of a line terminator.

# Pre-built key sequence constants for use with shellframe_read_key.
# Arrow keys (3-byte CSI sequences)
SHELLFRAME_KEY_UP=$'\x1b[A'
SHELLFRAME_KEY_DOWN=$'\x1b[B'
SHELLFRAME_KEY_RIGHT=$'\x1b[C'
SHELLFRAME_KEY_LEFT=$'\x1b[D'
# Common single-byte keys
SHELLFRAME_KEY_ENTER=$'\n'    # bash read converts \r→\n internally; use \n here
SHELLFRAME_KEY_SPACE=' '
SHELLFRAME_KEY_ESC=$'\x1b'
SHELLFRAME_KEY_TAB=$'\t'
SHELLFRAME_KEY_BACKSPACE=$'\x7f'
# Ctrl key combos (single-byte)
SHELLFRAME_KEY_CTRL_A=$'\x01'
SHELLFRAME_KEY_CTRL_E=$'\x05'
SHELLFRAME_KEY_CTRL_K=$'\x0b'
SHELLFRAME_KEY_CTRL_U=$'\x15'
SHELLFRAME_KEY_CTRL_W=$'\x17'
# 3-byte CSI sequences
SHELLFRAME_KEY_SHIFT_TAB=$'\x1b[Z'
SHELLFRAME_KEY_HOME=$'\x1b[H'
SHELLFRAME_KEY_END=$'\x1b[F'
# 4-byte CSI sequences: ESC [ <digit> ~
SHELLFRAME_KEY_DELETE=$'\x1b[3~'
SHELLFRAME_KEY_PAGE_UP=$'\x1b[5~'
SHELLFRAME_KEY_PAGE_DOWN=$'\x1b[6~'

# Read one keypress (including full escape sequences) into a variable.
#
# Usage:
#   local key
#   shellframe_read_key key
#   if   [[ "$key" == "$SHELLFRAME_KEY_UP"    ]]; then ...
#   elif [[ "$key" == "$SHELLFRAME_KEY_DOWN"  ]]; then ...
#   elif [[ "$key" == "$SHELLFRAME_KEY_ENTER" ]]; then ...
#
# Prerequisites: call inside a shellframe_raw_enter session so the terminal is in
# raw mode. Without raw mode, escape sequence bytes may echo between reads.
#
# Uses `read -d ''` (NUL delimiter) so that \n (produced by bash's internal
# \r→\n conversion when Enter is pressed) is captured as the key value rather
# than silently consumed as the line terminator.
#
# The -t 1 timeout on the follow-on reads handles a standalone ESC press
# gracefully (waits 1 s then returns just $'\x1b'). For arrow keys the
# follow-on bytes are already in the buffer and return immediately.
shellframe_read_key() {
    local _out_var="${1:-_SHELLFRAME_KEY}"
    local _k _c1 _c2 _c3
    IFS= read -r -n1 -d '' _k
    if [[ "$_k" == $'\x1b' ]]; then
        IFS= read -r -n1 -d '' -t 1 _c1
        IFS= read -r -n1 -d '' -t 1 _c2
        _k+="${_c1}${_c2}"
        # 4-byte sequences: ESC [ <digit> ~  (PgUp, PgDn, Delete, etc.)
        # Glob [0-9] matches a single digit — bash 3.2 safe.
        if [[ "$_c1" == '[' && "$_c2" == [0-9] ]]; then
            IFS= read -r -n1 -d '' -t 1 _c3
            _k+="${_c3}"
        fi
    fi
    printf -v "$_out_var" '%s' "$_k"
}
