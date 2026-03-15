# shellframe — API Reference

---

## `src/screen.sh`

| Function | Description |
|---|---|
| `shellframe_screen_enter` | Switch to alternate screen buffer + clear |
| `shellframe_screen_exit` | Restore original screen (undoes `shellframe_screen_enter`) |
| `shellframe_screen_clear` | Clear screen + move cursor home (for redraws) |
| `shellframe_cursor_hide` | Hide cursor (`\033[?25l`) |
| `shellframe_cursor_show` | Show cursor (`\033[?25h`) |
| `shellframe_raw_save` | Print current stty state (capture with `$(...)`) |
| `shellframe_raw_enter` | Set raw terminal mode for the TUI session |
| `shellframe_raw_exit "$saved"` | Restore terminal to saved stty state |

---

## `src/input.sh`

| Symbol | Value | Description |
|---|---|---|
| `SHELLFRAME_KEY_UP` | `\x1b[A` | Up arrow |
| `SHELLFRAME_KEY_DOWN` | `\x1b[B` | Down arrow |
| `SHELLFRAME_KEY_RIGHT` | `\x1b[C` | Right arrow |
| `SHELLFRAME_KEY_LEFT` | `\x1b[D` | Left arrow |
| `SHELLFRAME_KEY_ENTER` | `\n` | Enter / Return (bash converts `\r`→`\n` internally) |
| `SHELLFRAME_KEY_SPACE` | ` ` | Space |
| `SHELLFRAME_KEY_ESC` | `\x1b` | Standalone Escape |

**`shellframe_read_key <varname>`**

Reads one keypress (including full escape sequences) into `$varname`.
Call inside a `shellframe_raw_enter` session. Compare results against the
`SHELLFRAME_KEY_*` constants using `[[ "$key" == "$SHELLFRAME_KEY_UP" ]]`.
Uses `read -d ''` (NUL delimiter) so Enter (`\n`) is captured rather
than consumed as the line terminator (see [Hard-won lessons](hard-won-lessons.md#7-bash-read-converts-r-to-n-internally--use-read--d--for-enter)).

---

## `src/draw.sh`

**`shellframe_pad_left <raw> <rendered> <width>`**

Left-aligns `$rendered` in a column of `$width` *visible* characters.
`$raw` must be the plain-text (no ANSI codes) equivalent of `$rendered`
so its `${#raw}` byte count equals its visible character count.

```bash
local raw="~/bin/gflow"
local rendered="${SHELLFRAME_GRAY}~/bin/${SHELLFRAME_RESET}${SHELLFRAME_BOLD}gflow${SHELLFRAME_RESET}"
printf '%b' "$(shellframe_pad_left "$raw" "$rendered" 20)"
```

Color constants `SHELLFRAME_BOLD`, `SHELLFRAME_RESET`, `SHELLFRAME_GREEN`, `SHELLFRAME_RED`,
`SHELLFRAME_PURPLE`, `SHELLFRAME_GRAY`, `SHELLFRAME_WHITE` are set via `tput` at source time.

---

## `src/widgets/action-list.sh`

**`shellframe_action_list [draw_row_fn] [extra_key_fn] [footer_text]`**

Full-screen interactive list where each row has a set of named actions the
user cycles through. Returns 0 on confirm, 1 on quit.

**Caller sets globals before calling:**

| Global | Description |
|---|---|
| `SHELLFRAME_AL_LABELS[@]` | Display label per row |
| `SHELLFRAME_AL_ACTIONS[@]` | Space-separated action list per row (e.g. `"nothing install"`) |
| `SHELLFRAME_AL_IDX[@]` | Current action index per row (init to 0) |
| `SHELLFRAME_AL_META[@]` | Optional per-row metadata string passed to callbacks |

**Widget sets globals (readable from callbacks):**

| Global | Description |
|---|---|
| `SHELLFRAME_AL_SELECTED` | Index of the currently highlighted row |
| `SHELLFRAME_AL_SAVED_STTY` | Saved stty state — use with `shellframe_raw_exit` in `extra_key_fn` |

**Built-in key bindings:** `↑`/`↓` move, `Space`/`→` cycle action, `Enter`/`c` confirm, `q` quit.

**draw_row_fn** signature: `draw_row_fn "$i" "$label" "$acts_str" "$aidx" "$meta"`
Must print one complete line (with `\n`). `SHELLFRAME_AL_SELECTED` is set globally.

**extra_key_fn** signature: `extra_key_fn "$key"`
Called for unhandled keys. Return 0=handled+redraw, 1=not handled, 2=quit.
Use `SHELLFRAME_AL_SAVED_STTY` to suspend the TUI (e.g. to run a pager).

See [`examples/action-list.sh`](../examples/action-list.sh) for a complete demo.

---

## `src/widgets/confirm.sh`

**`shellframe_confirm <question> [detail ...]`**

Centered modal yes/no dialog. Optional plain-text `detail` lines are shown
above the question (e.g. a summary of pending changes). Returns 0 for Yes,
1 for No or cancel.

| Key | Action |
|---|---|
| `←`/`→`  `h`/`l` | Toggle between Yes and No |
| `y` / `Y` | Select Yes and confirm immediately |
| `n` / `N` | Select No and confirm immediately |
| `Enter` / `c` | Confirm current selection (default: Yes) |
| `Esc` / `q` / `Q` | Cancel (same as No) |

```bash
shellframe_confirm "Apply 3 pending changes?" \
    "  config.json   delete" \
    "  main.sh       install"

if (( $? == 0 )); then
    echo "applying..."
fi
```

See [`examples/confirm.sh`](../examples/confirm.sh) for a complete demo.

---

## `src/widgets/alert.sh`

**`shellframe_alert <title> [detail ...]`**

Centered informational modal. Shows a bold `title` heading and optional
plain-text `detail` lines. Any keypress dismisses it. Always returns 0.

| Key | Action |
|---|---|
| Any key | Dismiss |

```bash
shellframe_alert "Deploy complete" \
    "web-server    restarted" \
    "cache         flushed"

echo "Back in the shell."
```

See [`examples/alert.sh`](../examples/alert.sh) for a complete demo.

---

## `src/app.sh`

**`shellframe_app <prefix> [initial_screen]`**

Declarative application runtime. Models a TUI application as a
finite-state machine: screens are states, keypresses produce events,
event handlers return the next screen name. `shellframe_app` owns the session
loop — you declare the screens; it handles widget dispatch and transitions.
`initial_screen` defaults to `ROOT`. Returns when any handler sets `_SHELLFRAME_APP_NEXT="__QUIT__"`.

### Screen functions

For each screen `FOO`, define three functions (replace `PREFIX` with your
chosen prefix):

| Function | How it outputs | Purpose |
|---|---|---|
| `PREFIX_FOO_type()` | `printf` | One of: `action-list` \| `confirm` \| `alert` — called in a subshell, do not modify globals |
| `PREFIX_FOO_render()` | *(assigns globals)* | Populate widget context globals; called directly, safe to mutate state |
| `PREFIX_FOO_EVENT()` | `_SHELLFRAME_APP_NEXT=` | Set `_SHELLFRAME_APP_NEXT` to next screen name; called directly, safe to mutate state |

**Events** each widget type produces:

| Widget | rc=0 event | rc=1 event |
|---|---|---|
| `action-list` | `confirm` | `quit` |
| `confirm` | `yes` | `no` |
| `alert` | `dismiss` | — |

### Output global

| Global | Set by | Purpose |
|---|---|---|
| `_SHELLFRAME_APP_NEXT` | `EVENT()` handlers | Next screen name (or `__QUIT__`). Reset to `""` before each event call. |

Event handlers run in the **current shell** (not a subshell), so they can freely
read and write application state globals alongside setting `_SHELLFRAME_APP_NEXT`.

### Widget context globals

Set these in your `render()` hook. They are reset to empty before every
`render()` call, so each screen starts from a clean slate.

| Global | Widget | Purpose |
|---|---|---|
| `_SHELLFRAME_APP_DRAW_FN` | `action-list` | Row renderer callback name (empty → built-in default) |
| `_SHELLFRAME_APP_KEY_FN` | `action-list` | Extra key handler callback name (empty → none) |
| `_SHELLFRAME_APP_HINT` | `action-list` | Footer hint text (empty → built-in default) |
| `_SHELLFRAME_APP_QUESTION` | `confirm` | Question text |
| `_SHELLFRAME_APP_TITLE` | `alert` | Title text |
| `_SHELLFRAME_APP_DETAILS` | `confirm` + `alert` | Array of detail lines |

### Application context

Application-level state shared between screens (e.g. a pending-changes list,
results from an apply step) is not managed by `shellframe_app`. Use your own
module-level globals, by convention prefixed with your app name:

```bash
_MYAPP_PENDING=()   # populated by ROOT_confirm, consumed by CONFIRM_render
_MYAPP_RESULTS=()   # populated by CONFIRM_yes, consumed by RESULT_render
```

### Example

```bash
# Module-level context
_MYAPP_RESULTS=()

_myapp_ROOT_type()    { printf 'action-list'; }
_myapp_ROOT_render()  {
    SHELLFRAME_AL_LABELS=("task-a" "task-b")
    SHELLFRAME_AL_ACTIONS=("nothing run" "nothing run")
    SHELLFRAME_AL_IDX=(0 0)
    _SHELLFRAME_APP_HINT="Space cycle  Enter confirm  q quit"
}
_myapp_ROOT_confirm() {
    # check SHELLFRAME_AL_IDX for selections; if nothing selected, go back
    _SHELLFRAME_APP_NEXT="CONFIRM"
}
_myapp_ROOT_quit() { _SHELLFRAME_APP_NEXT="__QUIT__"; }

_myapp_CONFIRM_type()    { printf 'confirm'; }
_myapp_CONFIRM_render()  { _SHELLFRAME_APP_QUESTION="Run selected tasks?"; }
_myapp_CONFIRM_yes()     { _MYAPP_RESULTS=("task-a: ok" "task-b: ok"); _SHELLFRAME_APP_NEXT="RESULT"; }
_myapp_CONFIRM_no()      { _SHELLFRAME_APP_NEXT="ROOT"; }

_myapp_RESULT_type()     { printf 'alert'; }
_myapp_RESULT_render()   { _SHELLFRAME_APP_TITLE="Done"; _SHELLFRAME_APP_DETAILS=("${_MYAPP_RESULTS[@]}"); }
_myapp_RESULT_dismiss()  { _SHELLFRAME_APP_NEXT="ROOT"; }

shellframe_app "_myapp" "ROOT"
```

For a full real-world example see [`macbin/scripts`](https://github.com/fissible/macbin)
— a three-screen app (action list → confirm → result alert) that manages
symlinks in `~/bin`.
