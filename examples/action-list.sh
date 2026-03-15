#!/usr/bin/env bash
# examples/action-list.sh — Interactive action-list widget demo
#
# Shows a list of fruits. Each item has a set of available actions;
# the user cycles through them with Space/→ and confirms with Enter.
# The final selections are printed to stdout.

set -u
source "$(cd "$(dirname "${BASH_SOURCE[0]}")/.."; pwd)/shellframe.sh"

# ── Populate widget globals ───────────────────────────────────────────────────
SHELLFRAME_AL_LABELS=(
    "apple"
    "banana"
    "cherry"
    "date"
    "elderberry"
)
SHELLFRAME_AL_ACTIONS=(
    "nothing eat"
    "nothing eat peel"
    "nothing eat"
    "nothing eat"
    "nothing eat"
)
SHELLFRAME_AL_IDX=(0 0 0 0 0)
SHELLFRAME_AL_META=("" "" "" "" "")

# ── Custom row renderer ───────────────────────────────────────────────────────
# Signature: draw_row_fn "$i" "$label" "$acts_str" "$aidx" "$meta"
_demo_draw_row() {
    local i="$1" label="$2" acts_str="$3" aidx="$4"

    local cursor="  "
    (( i == SHELLFRAME_AL_SELECTED )) && cursor="${SHELLFRAME_BOLD}> ${SHELLFRAME_RESET}"

    local -a acts
    IFS=' ' read -r -a acts <<< "$acts_str"
    local action="${acts[$aidx]}"

    local action_str
    case "$action" in
        nothing)  action_str="${SHELLFRAME_GRAY}[ ------- ]${SHELLFRAME_RESET}" ;;
        eat)      action_str="${SHELLFRAME_GREEN}[   eat   ]${SHELLFRAME_RESET}" ;;
        peel)     action_str="${SHELLFRAME_PURPLE}[  peel   ]${SHELLFRAME_RESET}" ;;
        *)        action_str="${SHELLFRAME_GRAY}[ $action ]${SHELLFRAME_RESET}" ;;
    esac

    printf "%b%-14s  %b\n" "$cursor" "$label" "$action_str"
}

# ── Run widget ────────────────────────────────────────────────────────────────
shellframe_action_list "_demo_draw_row" "" \
    "↑/↓ move  Space/→ cycle action  Enter confirm  q quit"
_result=$?

# ── Print result ──────────────────────────────────────────────────────────────
_print_results() {
    local i=0 label action
    local -a acts
    if (( _result == 0 )); then
        printf 'Confirmed!\n'
        for label in "${SHELLFRAME_AL_LABELS[@]}"; do
            IFS=' ' read -r -a acts <<< "${SHELLFRAME_AL_ACTIONS[$i]}"
            action="${acts[${SHELLFRAME_AL_IDX[$i]}]}"
            if [[ "$action" != "nothing" ]]; then
                printf "  %s → %s\n" "$label" "$action"
            fi
            (( i++ ))
        done
    else
        printf 'Aborted.\n'
    fi
}
_print_results
