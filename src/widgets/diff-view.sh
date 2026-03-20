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

# Pane footer labels — set by the caller before render
SHELLFRAME_DIFF_VIEW_LEFT_FOOTER=""     # e.g. "HEAD~3  abc1234  2026-03-18"
SHELLFRAME_DIFF_VIEW_RIGHT_FOOTER=""    # e.g. "HEAD  def5678  2026-03-19"

# File header styling — set by the caller for a custom look, or leave empty for default
SHELLFRAME_DIFF_VIEW_FILE_HDR_ON=""     # ANSI sequence to start file header
SHELLFRAME_DIFF_VIEW_FILE_HDR_OFF=""    # ANSI sequence to end file header

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

    # Build all output into a buffer (no subshells), then write once
    local _buf="" _tmp=""

    local _fh_on="${SHELLFRAME_DIFF_VIEW_FILE_HDR_ON:-${_bold}${_reverse}}"
    local _fh_off="${SHELLFRAME_DIFF_VIEW_FILE_HDR_OFF:-${_reset}}"

    local _r
    for (( _r=0; _r < _height; _r++ )); do
        local _row_idx=$(( _scroll_top + _r ))
        local _screen_row=$(( _top + _r ))

        # Position cursor and clear the line area (printf -v, no fork)
        printf -v _tmp '\033[%d;%dH%*s\033[%d;%dH' \
            "$_screen_row" "$_left" "$_width" "" "$_screen_row" "$_left"
        _buf+="$_tmp"

        if (( _row_idx >= SHELLFRAME_DIFF_ROW_COUNT )); then
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

        case "$_type" in
            hdr)
                if [[ "$_side" == "left" ]]; then
                    printf -v _tmp '%s %-*.*s%s' "$_fh_on" \
                        "$(( _width - 1 ))" "$(( _width - 1 ))" "$_text" "$_fh_off"
                else
                    printf -v _tmp '%s%*s%s' "$_fh_on" "$_width" "" "$_fh_off"
                fi
                _buf+="$_tmp"
                continue
                ;;
            sep)
                local _pad=$(( (_width - 5) / 2 ))
                (( _pad < 0 )) && _pad=0
                printf -v _tmp '%s%*s·····%s' "$_gray" "$_pad" "" "$_reset"
                _buf+="$_tmp"
                continue
                ;;
        esac

        # Line number or blank gutter
        if [[ -n "$_lnum" ]]; then
            printf -v _tmp '%s%4s%s ' "$_gray" "$_lnum" "$_reset"
            _buf+="$_tmp"
        else
            _buf+="     "
        fi

        # Content with type-based coloring
        local _display="${_text:0:$_content_w}"

        case "$_type" in
            ctx)
                _buf+="$_display"
                ;;
            add)
                [[ "$_side" == "right" ]] && _buf+="${_green}${_display}${_reset}"
                ;;
            del)
                [[ "$_side" == "left" ]] && _buf+="${_red}${_display}${_reset}"
                ;;
            chg)
                if [[ "$_side" == "left" ]]; then
                    _buf+="${_red}${_display}${_reset}"
                else
                    _buf+="${_green}${_display}${_reset}"
                fi
                ;;
        esac
    done

    # Single write for the entire pane
    printf '%s' "$_buf" >&3
}

# ── shellframe_diff_view_render ─────────────────────────────────────────────

shellframe_diff_view_render() {
    local _top="$1" _left="$2" _width="$3" _height="$4"

    # Reserve bottom row for pane footers if either footer is set
    local _content_h="$_height"
    local _has_footer=0
    if [[ -n "${SHELLFRAME_DIFF_VIEW_LEFT_FOOTER:-}" || -n "${SHELLFRAME_DIFF_VIEW_RIGHT_FOOTER:-}" ]]; then
        _has_footer=1
        _content_h=$(( _height - 1 ))
        (( _content_h < 1 )) && _content_h=1
    fi

    # Draw the split separator (full height including footer row)
    shellframe_split_render "dv_split" "$_top" "$_left" "$_width" "$_height"

    # Compute pane bounds for content area (excluding footer)
    local _lt _ll _lw _lh _rt _rl _rw _rh
    shellframe_split_bounds "dv_split" 0 "$_top" "$_left" "$_width" "$_content_h" \
        _lt _ll _lw _lh
    shellframe_split_bounds "dv_split" 1 "$_top" "$_left" "$_width" "$_content_h" \
        _rt _rl _rw _rh

    # Render each pane
    _shellframe_dv_render_pane "$_lt" "$_ll" "$_lw" "$_lh" "left"
    _shellframe_dv_render_pane "$_rt" "$_rl" "$_rw" "$_rh" "right"

    # Render pane footers
    if (( _has_footer )); then
        local _footer_row=$(( _top + _height - 1 ))
        local _gray="${SHELLFRAME_GRAY:-}"
        local _reset="${SHELLFRAME_RESET:-}"
        local _rev="${SHELLFRAME_REVERSE:-}"
        local _fbuf="" _ftmp=""

        # Left footer
        local _lf="${SHELLFRAME_DIFF_VIEW_LEFT_FOOTER:-}"
        local _lf_clipped="${_lf:0:$(( _lw - 1 ))}"
        local _lpad=$(( _lw - ${#_lf_clipped} - 1 ))
        (( _lpad < 0 )) && _lpad=0
        printf -v _ftmp '\033[%d;%dH%s%s %s%*s%s' \
            "$_footer_row" "$_ll" "$_rev" "$_gray" "$_lf_clipped" "$_lpad" "" "$_reset"
        _fbuf+="$_ftmp"

        # Right footer
        local _rf="${SHELLFRAME_DIFF_VIEW_RIGHT_FOOTER:-}"
        local _rf_clipped="${_rf:0:$(( _rw - 1 ))}"
        local _rpad=$(( _rw - ${#_rf_clipped} - 1 ))
        (( _rpad < 0 )) && _rpad=0
        printf -v _ftmp '\033[%d;%dH%s%s %s%*s%s' \
            "$_footer_row" "$_rl" "$_rev" "$_gray" "$_rf_clipped" "$_rpad" "" "$_reset"
        _fbuf+="$_ftmp"

        printf '%s' "$_fbuf" >&3
    fi
}

# ── shellframe_diff_view_on_key ─────────────────────────────────────────────

shellframe_diff_view_on_key() {
    local _key="$1"

    case "$_key" in
        "$SHELLFRAME_KEY_UP")
            shellframe_sync_scroll_move "dv_sync" "dv_left" "up" 3
            return 0
            ;;
        "$SHELLFRAME_KEY_DOWN")
            shellframe_sync_scroll_move "dv_sync" "dv_left" "down" 3
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
