#!/usr/bin/env bash
# shellframe/src/keymap.sh — Keyboard input mapping module
#
# COMPATIBILITY: bash 3.2+ (macOS default).
# REQUIRES: src/input.sh sourced first (for SHELLFRAME_KEY_* constants).
#
# ── Overview ──────────────────────────────────────────────────────────────────
#
# Two layers:
#
#   1. Canonical key names  — shellframe_keyname maps a raw key sequence to a
#                             stable symbolic name ("up", "enter", "ctrl_w", …).
#                             This layer is fixed and not user-configurable.
#
#   2. Named keymaps        — Associates raw key sequences with application-
#                             defined action strings. Multiple independent
#                             keymaps can coexist (one per widget context).
#
# ── Layer 1: Canonical key names ──────────────────────────────────────────────
#
#   shellframe_keyname key [out_var]
#     Maps a raw key sequence to a canonical name.  Prints to stdout unless
#     out_var is given (uses printf -v).  Returns "" for unknown keys.
#
#     Canonical names:
#       up  down  left  right  enter  tab  shift_tab  space  esc
#       backspace  delete  home  end  page_up  page_down
#       ctrl_a  ctrl_e  ctrl_k  ctrl_u  ctrl_w
#       <single char>  — for printable ASCII or any unrecognised single byte
#
# ── Layer 2: Named keymaps ────────────────────────────────────────────────────
#
#   shellframe_keymap_bind keymap key action
#     Bind raw key sequence $key to action string $action in $keymap.
#
#   shellframe_keymap_lookup keymap key [out_var]
#     Return the action bound to $key in $keymap, or "" if unbound.
#
#   shellframe_keymap_default_nav keymap
#     Populate $keymap with standard navigation bindings:
#       up / down / left / right / home / end / page_up / page_down
#         → action names matching the canonical key name
#       enter → "confirm"   esc → "cancel"   q/Q → "quit"
#       space → "toggle"    tab → "focus_next"   shift_tab → "focus_prev"
#
#   shellframe_keymap_default_edit keymap
#     Populate $keymap with standard text-editing bindings:
#       left / right / home / end  → canonical name
#       ctrl_a → "home"   ctrl_e → "end"
#       backspace → "backspace"   delete → "delete"
#       ctrl_k → "kill_to_end"   ctrl_u → "kill_to_start"
#       ctrl_w → "kill_word_left"
#       enter → "confirm"   esc → "cancel"
#       tab → "focus_next"   shift_tab → "focus_prev"
#
# ── Keymap storage ────────────────────────────────────────────────────────────
#
# Bindings are stored as globals named:
#   _SHELLFRAME_KM_<KEYMAP>_<HEX>
# where <HEX> is the lowercase hex encoding of the raw key sequence bytes.
# Variable names contain only [A-Za-z0-9_] and are safe for indirect reference.

# ── Internal: hex encoder ──────────────────────────────────────────────────────

# Encode a raw byte string as lowercase hex (e.g. $'\x1b[A' → "1b5b41").
# Uses printf '%d' "'c" — returns the ordinal of the character following the
# single quote.  Portable to bash 3.2+.
_shellframe_keymap_hex() {
    local _s="$1" _hex="" _i _code
    for (( _i=0; _i<${#_s}; _i++ )); do
        printf -v _code '%d' "'${_s:$_i:1}"
        printf -v _hex '%s%02x' "$_hex" "$_code"
    done
    printf '%s' "$_hex"
}

# ── shellframe_keyname ─────────────────────────────────────────────────────────

# Map a raw key sequence to a canonical symbolic name.
# Prints to stdout unless out_var is given (printf -v).
# Produces "" for unknown multi-byte sequences (not an error).
#
# GOTCHA: bash `case` treats [A as a glob bracket expression — always compare
# escape sequences with [[ == ]] against variables, never with case patterns.
shellframe_keyname() {
    local _key="$1" _out="${2:-}"
    local _name=""

    if   [[ "$_key" == "$SHELLFRAME_KEY_UP"        ]]; then _name="up"
    elif [[ "$_key" == "$SHELLFRAME_KEY_DOWN"      ]]; then _name="down"
    elif [[ "$_key" == "$SHELLFRAME_KEY_LEFT"      ]]; then _name="left"
    elif [[ "$_key" == "$SHELLFRAME_KEY_RIGHT"     ]]; then _name="right"
    elif [[ "$_key" == "$SHELLFRAME_KEY_ENTER"     ]]; then _name="enter"
    elif [[ "$_key" == "$SHELLFRAME_KEY_TAB"       ]]; then _name="tab"
    elif [[ "$_key" == "$SHELLFRAME_KEY_SHIFT_TAB" ]]; then _name="shift_tab"
    elif [[ "$_key" == "$SHELLFRAME_KEY_SPACE"     ]]; then _name="space"
    elif [[ "$_key" == "$SHELLFRAME_KEY_ESC"       ]]; then _name="esc"
    elif [[ "$_key" == "$SHELLFRAME_KEY_BACKSPACE" ]]; then _name="backspace"
    elif [[ "$_key" == "$SHELLFRAME_KEY_DELETE"    ]]; then _name="delete"
    elif [[ "$_key" == "$SHELLFRAME_KEY_HOME"      ]]; then _name="home"
    elif [[ "$_key" == "$SHELLFRAME_KEY_END"       ]]; then _name="end"
    elif [[ "$_key" == "$SHELLFRAME_KEY_PAGE_UP"   ]]; then _name="page_up"
    elif [[ "$_key" == "$SHELLFRAME_KEY_PAGE_DOWN" ]]; then _name="page_down"
    elif [[ "$_key" == "$SHELLFRAME_KEY_CTRL_A"    ]]; then _name="ctrl_a"
    elif [[ "$_key" == "$SHELLFRAME_KEY_CTRL_E"    ]]; then _name="ctrl_e"
    elif [[ "$_key" == "$SHELLFRAME_KEY_CTRL_K"    ]]; then _name="ctrl_k"
    elif [[ "$_key" == "$SHELLFRAME_KEY_CTRL_U"    ]]; then _name="ctrl_u"
    elif [[ "$_key" == "$SHELLFRAME_KEY_CTRL_W"    ]]; then _name="ctrl_w"
    elif [[ ${#_key} -eq 1 ]]; then
        # Single character: return as-is (printable chars and unrecognised
        # single-byte control chars).
        _name="$_key"
    fi
    # Multi-byte unknown sequence → _name stays "".

    if [[ -n "$_out" ]]; then
        printf -v "$_out" '%s' "$_name"
    else
        printf '%s\n' "$_name"
    fi
}

# ── shellframe_keymap_bind ─────────────────────────────────────────────────────

# Bind raw key sequence $key to action string $action in keymap $keymap.
# Replaces any existing binding for the same key.
shellframe_keymap_bind() {
    local _map="$1" _key="$2" _action="$3"
    local _hex _var
    _hex=$(_shellframe_keymap_hex "$_key")
    _var="_SHELLFRAME_KM_${_map}_${_hex}"
    printf -v "$_var" '%s' "$_action"
}

# ── shellframe_keymap_lookup ───────────────────────────────────────────────────

# Return the action bound to $key in $keymap.
# If out_var is given, uses printf -v; otherwise prints to stdout.
# Produces "" (empty) for unbound keys.
shellframe_keymap_lookup() {
    local _map="$1" _key="$2" _out="${3:-}"
    local _hex _var _action
    _hex=$(_shellframe_keymap_hex "$_key")
    _var="_SHELLFRAME_KM_${_map}_${_hex}"
    _action="${!_var:-}"
    if [[ -n "$_out" ]]; then
        printf -v "$_out" '%s' "$_action"
    else
        printf '%s\n' "$_action"
    fi
}

# ── shellframe_keymap_default_nav ──────────────────────────────────────────────

# Populate $keymap with standard navigation key bindings.
# Overwrites any existing bindings for these keys.
shellframe_keymap_default_nav() {
    local _map="$1"
    shellframe_keymap_bind "$_map" "$SHELLFRAME_KEY_UP"        "up"
    shellframe_keymap_bind "$_map" "$SHELLFRAME_KEY_DOWN"      "down"
    shellframe_keymap_bind "$_map" "$SHELLFRAME_KEY_LEFT"      "left"
    shellframe_keymap_bind "$_map" "$SHELLFRAME_KEY_RIGHT"     "right"
    shellframe_keymap_bind "$_map" "$SHELLFRAME_KEY_HOME"      "home"
    shellframe_keymap_bind "$_map" "$SHELLFRAME_KEY_END"       "end"
    shellframe_keymap_bind "$_map" "$SHELLFRAME_KEY_PAGE_UP"   "page_up"
    shellframe_keymap_bind "$_map" "$SHELLFRAME_KEY_PAGE_DOWN" "page_down"
    shellframe_keymap_bind "$_map" "$SHELLFRAME_KEY_ENTER"     "confirm"
    shellframe_keymap_bind "$_map" "$SHELLFRAME_KEY_SPACE"     "toggle"
    shellframe_keymap_bind "$_map" "$SHELLFRAME_KEY_ESC"       "cancel"
    shellframe_keymap_bind "$_map" "q"                         "quit"
    shellframe_keymap_bind "$_map" "Q"                         "quit"
    shellframe_keymap_bind "$_map" "$SHELLFRAME_KEY_TAB"       "focus_next"
    shellframe_keymap_bind "$_map" "$SHELLFRAME_KEY_SHIFT_TAB" "focus_prev"
}

# ── shellframe_keymap_default_edit ─────────────────────────────────────────────

# Populate $keymap with standard text-editing key bindings.
# Overwrites any existing bindings for these keys.
shellframe_keymap_default_edit() {
    local _map="$1"
    shellframe_keymap_bind "$_map" "$SHELLFRAME_KEY_LEFT"      "left"
    shellframe_keymap_bind "$_map" "$SHELLFRAME_KEY_RIGHT"     "right"
    shellframe_keymap_bind "$_map" "$SHELLFRAME_KEY_HOME"      "home"
    shellframe_keymap_bind "$_map" "$SHELLFRAME_KEY_END"       "end"
    shellframe_keymap_bind "$_map" "$SHELLFRAME_KEY_BACKSPACE" "backspace"
    shellframe_keymap_bind "$_map" "$SHELLFRAME_KEY_DELETE"    "delete"
    shellframe_keymap_bind "$_map" "$SHELLFRAME_KEY_CTRL_A"    "home"
    shellframe_keymap_bind "$_map" "$SHELLFRAME_KEY_CTRL_E"    "end"
    shellframe_keymap_bind "$_map" "$SHELLFRAME_KEY_CTRL_K"    "kill_to_end"
    shellframe_keymap_bind "$_map" "$SHELLFRAME_KEY_CTRL_U"    "kill_to_start"
    shellframe_keymap_bind "$_map" "$SHELLFRAME_KEY_CTRL_W"    "kill_word_left"
    shellframe_keymap_bind "$_map" "$SHELLFRAME_KEY_ENTER"     "confirm"
    shellframe_keymap_bind "$_map" "$SHELLFRAME_KEY_ESC"       "cancel"
    shellframe_keymap_bind "$_map" "$SHELLFRAME_KEY_TAB"       "focus_next"
    shellframe_keymap_bind "$_map" "$SHELLFRAME_KEY_SHIFT_TAB" "focus_prev"
}
