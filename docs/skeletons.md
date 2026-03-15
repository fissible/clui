# shellframe — TUI Skeletons

Copy-paste starting points for common patterns.

---

## Application skeleton (`shellframe_app`)

Use this for any multi-screen application. Define screens as function
triples; `shellframe_app` manages the loop.

```bash
source /path/to/shellframe/shellframe.sh

# Module-level context globals shared between screens
_APP_DATA=()

# ── Screen: MAIN (action-list) ──────────────────────────────────────
_app_MAIN_type()    { printf 'action-list'; }
_app_MAIN_render()  {
    SHELLFRAME_AL_LABELS=(...)
    SHELLFRAME_AL_ACTIONS=(...)
    SHELLFRAME_AL_IDX=(...)
    _SHELLFRAME_APP_DRAW_FN="_app_draw_row"   # optional custom renderer
    _SHELLFRAME_APP_HINT="Space cycle  Enter confirm  q quit"
}
_app_MAIN_confirm() { _SHELLFRAME_APP_NEXT="CONFIRM"; }   # or 'MAIN' if nothing selected
_app_MAIN_quit()    { _SHELLFRAME_APP_NEXT="__QUIT__"; }

# ── Screen: CONFIRM (yes/no modal) ─────────────────────────────────
_app_CONFIRM_type()   { printf 'confirm'; }
_app_CONFIRM_render() { _SHELLFRAME_APP_QUESTION="Apply changes?"; }
_app_CONFIRM_yes()    { _app_apply; _SHELLFRAME_APP_NEXT="RESULT"; }
_app_CONFIRM_no()     { _SHELLFRAME_APP_NEXT="MAIN"; }

# ── Screen: RESULT (alert modal) ───────────────────────────────────
_app_RESULT_type()    { printf 'alert'; }
_app_RESULT_render()  { _SHELLFRAME_APP_TITLE="Done"; _SHELLFRAME_APP_DETAILS=("${_APP_DATA[@]}"); }
_app_RESULT_dismiss() { _SHELLFRAME_APP_NEXT="MAIN"; }

# ── Entry point ────────────────────────────────────────────────────
my_app() {
    shellframe_app "_app" "MAIN"
}
```

---

## Custom widget skeleton

Use this when building a new widget or a single-screen TUI that doesn't
fit the three standard widget types.

```bash
source /path/to/shellframe/shellframe.sh

my_widget() {
    # ── Setup ──────────────────────────────────────────────────────
    local saved_stty
    saved_stty=$(shellframe_raw_save)
    exec 3>&1; exec 1>/dev/tty

    _exit() {
        shellframe_raw_exit "$saved_stty"
        shellframe_cursor_show
        shellframe_screen_exit
        { exec 1>&3; } 2>/dev/null || true
        { exec 3>&-; } 2>/dev/null || true
    }
    trap '_exit; exit 1' INT TERM

    shellframe_screen_enter
    shellframe_raw_enter
    shellframe_cursor_hide

    # ── Draw ───────────────────────────────────────────────────────
    _draw() {
        shellframe_screen_clear
        # ... printf your UI here using ANSI escape sequences ...
    }
    _draw

    # ── Input loop ─────────────────────────────────────────────────
    local key
    while true; do
        shellframe_read_key key
        if   [[ "$key" == "$SHELLFRAME_KEY_UP"    ]]; then : # handle up
        elif [[ "$key" == "$SHELLFRAME_KEY_DOWN"  ]]; then : # handle down
        elif [[ "$key" == "$SHELLFRAME_KEY_ENTER" ]]; then break
        elif [[ "$key" == 'q' ]]; then break
        fi
        _draw
    done

    # ── Teardown ───────────────────────────────────────────────────
    trap - INT TERM
    _exit
}
```

> **Note:** The `exec 3>&1 / exec 1>/dev/tty` plumbing is required if this
> widget may be called inside `$()` command substitution. See
> [Hard-won lessons](hard-won-lessons.md#9-command-substitution--pipes-stdout-away-from-the-terminal).
