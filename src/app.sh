#!/usr/bin/env bash
# clui/src/app.sh — Application runtime (declarative screen FSM)
#
# API:
#   clui_app <prefix> [initial_screen]
#
#   <prefix>          — naming prefix for all screen functions (see below)
#   [initial_screen]  — first screen to display (default: ROOT)
#
# ── Screen definition ─────────────────────────────────────────────────────────
#
# A screen is a named state.  For each screen FOO, define these functions
# (replace PREFIX and FOO with your values):
#
#   PREFIX_FOO_type()      — print the widget type: action-list | confirm | alert
#   PREFIX_FOO_render()    — populate widget context globals before the widget runs
#   PREFIX_FOO_EVENT()     — print the next screen name, or __QUIT__ to end the app
#
# Events per widget type:
#   action-list  →  confirm (Enter)   |  quit (q)
#   confirm      →  yes    (Y/Enter)  |  no   (N/Esc/q)
#   alert        →  dismiss (any key)
#
# ── Widget context globals (set in render hooks) ──────────────────────────────
#
#   action-list screens:
#     _CLUI_APP_DRAW_FN   row renderer callback name (empty → built-in default)
#     _CLUI_APP_KEY_FN    extra key handler callback name (empty → none)
#     _CLUI_APP_HINT      footer hint text (empty → built-in default)
#
#   confirm screens:
#     _CLUI_APP_QUESTION  question text
#     _CLUI_APP_DETAILS   (array) detail lines shown above the question
#
#   alert screens:
#     _CLUI_APP_TITLE     title text
#     _CLUI_APP_DETAILS   (array) detail lines shown below the title
#
# ── Minimal example ───────────────────────────────────────────────────────────
#
#   _myapp_ROOT_type()    { printf 'action-list'; }
#   _myapp_ROOT_render()  { CLUI_AL_LABELS=(...); ...; _CLUI_APP_HINT="q quit"; }
#   _myapp_ROOT_confirm() { printf 'CONFIRM'; }
#   _myapp_ROOT_quit()    { printf '__QUIT__'; }
#
#   _myapp_CONFIRM_type()   { printf 'confirm'; }
#   _myapp_CONFIRM_render() { _CLUI_APP_QUESTION="Apply?"; }
#   _myapp_CONFIRM_yes()    { _do_work; printf 'DONE'; }
#   _myapp_CONFIRM_no()     { printf 'ROOT'; }
#
#   _myapp_DONE_type()      { printf 'alert'; }
#   _myapp_DONE_render()    { _CLUI_APP_TITLE="Done"; }
#   _myapp_DONE_dismiss()   { printf 'ROOT'; }
#
#   clui_app "_myapp" "ROOT"

_CLUI_APP_DRAW_FN=""
_CLUI_APP_KEY_FN=""
_CLUI_APP_HINT=""
_CLUI_APP_QUESTION=""
_CLUI_APP_TITLE=""
_CLUI_APP_DETAILS=()

# Map widget return code → event name string
_clui_app_event() {
    local _type="$1" _rc="$2"
    case "$_type" in
        action-list) (( _rc == 0 )) && printf 'confirm' || printf 'quit'   ;;
        confirm)     (( _rc == 0 )) && printf 'yes'     || printf 'no'     ;;
        alert)       printf 'dismiss'                                       ;;
    esac
}

clui_app() {
    local _prefix="$1"
    local _current="${2:-ROOT}"

    while [[ "$_current" != "__QUIT__" ]]; do

        # Reset widget context globals before each render
        _CLUI_APP_DRAW_FN=""
        _CLUI_APP_KEY_FN=""
        _CLUI_APP_HINT=""
        _CLUI_APP_QUESTION=""
        _CLUI_APP_TITLE=""
        _CLUI_APP_DETAILS=()

        # Get screen type, run render hook
        local _type
        _type=$("${_prefix}_${_current}_type")
        "${_prefix}_${_current}_render"

        # Run the widget for this screen type
        local _rc=0
        case "$_type" in
            action-list)
                clui_action_list \
                    "$_CLUI_APP_DRAW_FN" \
                    "$_CLUI_APP_KEY_FN" \
                    "$_CLUI_APP_HINT"
                _rc=$?
                ;;
            confirm)
                if (( ${#_CLUI_APP_DETAILS[@]} > 0 )); then
                    clui_confirm "$_CLUI_APP_QUESTION" "${_CLUI_APP_DETAILS[@]}"
                else
                    clui_confirm "$_CLUI_APP_QUESTION"
                fi
                _rc=$?
                ;;
            alert)
                if (( ${#_CLUI_APP_DETAILS[@]} > 0 )); then
                    clui_alert "$_CLUI_APP_TITLE" "${_CLUI_APP_DETAILS[@]}"
                else
                    clui_alert "$_CLUI_APP_TITLE"
                fi
                _rc=$?
                ;;
        esac

        # Map rc → event name, call transition hook, advance to next screen
        local _event _next
        _event=$(_clui_app_event "$_type" "$_rc")
        _next=$("${_prefix}_${_current}_${_event}")
        _current="$_next"
    done
}
