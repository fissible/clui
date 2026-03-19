#!/usr/bin/env bash
# shellframe/src/widgets/diff-view.sh — Side-by-side diff viewer
#
# COMPATIBILITY: bash 3.2+ (macOS default).
# REQUIRES: split.sh, diff.sh, sync-scroll.sh, scroll.sh sourced first.
#
# ── Overview ──────────────────────────────────────────────────────────────────
#
# Renders a parsed diff (from shellframe_diff_parse) as a side-by-side view
# in a 2-pane split.  Left pane shows the old version, right pane shows the
# new version.  Scrolling is synchronized.
#
# Highlights:
#   - Changed lines: left in red, right in green
#   - Added lines: green on right, blank on left
#   - Deleted lines: red on left, blank on right
#   - Context lines: dimmed on both sides
#   - Separator rows: centered "───" indicator
#   - Line numbers in the gutter
#
# ── Input globals ────────────────────────────────────────────────────────────
#
#   SHELLFRAME_DIFF_TYPES[]   — populated by shellframe_diff_parse
#   SHELLFRAME_DIFF_LEFT[]    — populated by shellframe_diff_parse
#   SHELLFRAME_DIFF_RIGHT[]   — populated by shellframe_diff_parse
#   SHELLFRAME_DIFF_LNUMS[]   — populated by shellframe_diff_parse
#   SHELLFRAME_DIFF_RNUMS[]   — populated by shellframe_diff_parse
#   SHELLFRAME_DIFF_ROW_COUNT — populated by shellframe_diff_parse
#
# ── Public API ──────────────────────────────────────────────────────────────
#
#   shellframe_diff_view_init
#     Initialise split, scroll, and sync-scroll contexts for the diff view.
#     Call after shellframe_diff_parse.
#
#   shellframe_diff_view_render top left width height
#     Render the full diff view (separator + both panes).
#
#   shellframe_diff_view_on_key key
#     Handle scroll keys.  Returns 0 if handled, 1 if not.
#
#   shellframe_diff_view_on_focus focused
#     Track focus state for visual indicator.

SHELLFRAME_DIFF_VIEW_FOCUSED=0

# Gutter width: line number + space
_SHELLFRAME_DV_GUTTER=5

# ── shellframe_diff_view_init ───────────────────────────────────────────────

shellframe_diff_view_init() {
    shellframe_split_init "dv_split" "v" 2 "0:0"

    # Scroll contexts — total rows = diff row count, cols/viewport set at render
    shellframe_scroll_init "dv_left"  "${SHELLFRAME_DIFF_ROW_COUNT:-0}" 1 1 1
    shellframe_scroll_init "dv_right" "${SHELLFRAME_DIFF_ROW_COUNT:-0}" 1 1 1

    shellframe_sync_scroll_init "dv_sync" "dv_left" "dv_right"
}

# ── _shellframe_dv_render_pane ──────────────────────────────────────────────

# Render one side of the diff (left or right).
# _shellframe_dv_render_pane top left width height side
#   side: "left" | "right"
_shellframe_dv_render_pane() {
    local _top="$1" _left="$2" _width="$3" _height="$4" _side="$5"

    local _scroll_ctx="dv_${_side}"
    local _gutter="$_SHELLFRAME_DV_GUTTER"
    local _content_w=$(( _width - _gutter ))
    (( _content_w < 1 )) && _content_w=1

    # Update scroll viewport
    shellframe_scroll_resize "$_scroll_ctx" "$_height" "$_content_w"

    local _scroll_top
    shellframe_scroll_top "$_scroll_ctx" _scroll_top

    local _reset="${SHELLFRAME_RESET:-}"
    local _gray="${SHELLFRAME_GRAY:-}"
    local _red="${SHELLFRAME_RED:-}"
    local _green="${SHELLFRAME_GREEN:-}"
    local _bold="${SHELLFRAME_BOLD:-}"
    local _reverse="${SHELLFRAME_REVERSE:-}"

    local _r
    for (( _r=0; _r < _height; _r++ )); do
        local _row_idx=$(( _scroll_top + _r ))
        local _screen_row=$(( _top + _r ))

        # Position cursor and clear the line area
        printf '\033[%d;%dH' "$_screen_row" "$_left" >/dev/tty
        local _c
        for (( _c=0; _c < _width; _c++ )); do
            printf ' ' >/dev/tty
        done
        printf '\033[%d;%dH' "$_screen_row" "$_left" >/dev/tty

        if (( _row_idx >= SHELLFRAME_DIFF_ROW_COUNT )); then
            # Past end of diff — leave blank
            continue
        fi

        local _type="${SHELLFRAME_DIFF_TYPES[$_row_idx]}"
        local _text _lnum

        if [[ "$_side" == "left" ]]; then
            _text="${SHELLFRAME_DIFF_LEFT[$_row_idx]}"
            _lnum="${SHELLFRAME_DIFF_LNUMS[$_row_idx]}"
        else
            _text="${SHELLFRAME_DIFF_RIGHT[$_row_idx]}"
            _lnum="${SHELLFRAME_DIFF_RNUMS[$_row_idx]}"
        fi

        # Render gutter (line number)
        case "$_type" in
            hdr)
                if [[ "$_side" == "left" ]]; then
                    printf '%s%s %-*.*s%s' "$_bold" "$_reverse" \
                        "$(( _width - 1 ))" "$(( _width - 1 ))" "$_text" "$_reset" >/dev/tty
                else
                    printf '%s%s%*s%s' "$_bold" "$_reverse" "$_width" "" "$_reset" >/dev/tty
                fi
                continue
                ;;
            sep)
                printf '%s' "$_gray" >/dev/tty
                local _pad=$(( (_width - 5) / 2 ))
                (( _pad < 0 )) && _pad=0
                for (( _c=0; _c < _pad; _c++ )); do printf ' ' >/dev/tty; done
                printf '·····' >/dev/tty
                printf '%s' "$_reset" >/dev/tty
                continue
                ;;
        esac

        # Line number or blank gutter
        if [[ -n "$_lnum" ]]; then
            printf '%s%4s%s ' "$_gray" "$_lnum" "$_reset" >/dev/tty
        else
            printf '     ' >/dev/tty
        fi

        # Content with type-based coloring
        # Clip text to content width
        local _display="${_text:0:$_content_w}"

        case "$_type" in
            ctx)
                printf '%s' "$_display" >/dev/tty
                ;;
            add)
                if [[ "$_side" == "right" ]]; then
                    printf '%s%s%s' "$_green" "$_display" "$_reset" >/dev/tty
                fi
                ;;
            del)
                if [[ "$_side" == "left" ]]; then
                    printf '%s%s%s' "$_red" "$_display" "$_reset" >/dev/tty
                fi
                ;;
            chg)
                if [[ "$_side" == "left" ]]; then
                    printf '%s%s%s' "$_red" "$_display" "$_reset" >/dev/tty
                else
                    printf '%s%s%s' "$_green" "$_display" "$_reset" >/dev/tty
                fi
                ;;
        esac
    done
}

# ── shellframe_diff_view_render ─────────────────────────────────────────────

shellframe_diff_view_render() {
    local _top="$1" _left="$2" _width="$3" _height="$4"

    # Draw the split separator
    shellframe_split_render "dv_split" "$_top" "$_left" "$_width" "$_height"

    # Compute pane bounds
    local _lt _ll _lw _lh _rt _rl _rw _rh
    shellframe_split_bounds "dv_split" 0 "$_top" "$_left" "$_width" "$_height" \
        _lt _ll _lw _lh
    shellframe_split_bounds "dv_split" 1 "$_top" "$_left" "$_width" "$_height" \
        _rt _rl _rw _rh

    # Render each pane
    _shellframe_dv_render_pane "$_lt" "$_ll" "$_lw" "$_lh" "left"
    _shellframe_dv_render_pane "$_rt" "$_rl" "$_rw" "$_rh" "right"
}

# ── shellframe_diff_view_on_key ─────────────────────────────────────────────

shellframe_diff_view_on_key() {
    local _key="$1"

    case "$_key" in
        "$SHELLFRAME_KEY_UP")
            shellframe_sync_scroll_move "dv_sync" "dv_left" "up"
            return 0
            ;;
        "$SHELLFRAME_KEY_DOWN")
            shellframe_sync_scroll_move "dv_sync" "dv_left" "down"
            return 0
            ;;
        "$SHELLFRAME_KEY_PAGE_UP")
            shellframe_sync_scroll_move "dv_sync" "dv_left" "page_up"
            return 0
            ;;
        "$SHELLFRAME_KEY_PAGE_DOWN")
            shellframe_sync_scroll_move "dv_sync" "dv_left" "page_down"
            return 0
            ;;
        "$SHELLFRAME_KEY_HOME")
            shellframe_sync_scroll_move "dv_sync" "dv_left" "home"
            return 0
            ;;
        "$SHELLFRAME_KEY_END")
            shellframe_sync_scroll_move "dv_sync" "dv_left" "end"
            return 0
            ;;
    esac

    return 1
}

# ── shellframe_diff_view_on_focus ───────────────────────────────────────────

shellframe_diff_view_on_focus() {
    SHELLFRAME_DIFF_VIEW_FOCUSED="${1:-0}"
}
