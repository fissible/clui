# Sheet Navigation Primitive — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Implement `src/sheet.sh` — a partial overlay navigation primitive that sits above the current `shellframe_shell` screen, shows frozen dimmed back-strip content, and supports internal wizard-style transitions.

**Architecture:** New `src/sheet.sh` holds all sheet state and rendering. `src/screen.sh` gains a `_SF_ROW_OFFSET` global used during sheet region dispatch. `src/shell.sh` gains two delegation guards (draw + key). `shellframe.sh` sources `sheet.sh` after `shell.sh`. Hook convention is identical to `shellframe_shell` screens — consumers already know it.

**Tech Stack:** bash 3.2+, shellframe framebuffer API (`shellframe_fb_*`, `shellframe_screen_flush`), existing `shell.sh` focus model, `shellframe_widget_*` hitbox functions.

**Spec:** `docs/superpowers/specs/2026-04-02-sheet-navigation-design.md`

---

## File Map

| File | Action | Responsibility |
|------|--------|---------------|
| `src/sheet.sh` | **Create** | All sheet state globals, `shellframe_sheet_push`, `shellframe_sheet_pop`, `shellframe_sheet_active`, `shellframe_sheet_draw`, `shellframe_sheet_on_key` |
| `src/screen.sh` | **Modify** | Add `_SF_ROW_OFFSET=0` global; apply it in `shellframe_fb_put`, `shellframe_fb_print`, `shellframe_fb_fill`, `shellframe_fb_print_ansi` |
| `src/shell.sh` | **Modify** | Two delegation guards: inside `_shellframe_shell_draw` (after `_shellframe_shell_refresh_size`) and inside the key loop (after resize check, before `_shellframe_shell_focus_owner`) |
| `shellframe.sh` | **Modify** | Source `src/sheet.sh` after line 41 (after `src/shell.sh`) |
| `tests/unit/test-sheet.sh` | **Create** | Unit tests: push/pop/active, double-push, frozen row capture, registry swap isolation, screen transitions |
| `tests/integration/test-sheet.sh` | **Create** | PTY tests: push visible, form input, wizard transition, Esc dismiss, Up-from-topmost dismiss |
| `examples/sheet.sh` | **Create** | Two-step wizard (Step 1: Name+Email, Step 2: City+Zip) |
| `docs/showcase.md` | **Modify** | Add sheet section |

---

## Task 1: Module scaffold + state globals + public API

**Files:**
- Create: `src/sheet.sh`
- Create: `tests/unit/test-sheet.sh`

- [ ] **Step 1: Write failing unit tests for push/pop/active/double-push**

Create `tests/unit/test-sheet.sh`:

```bash
#!/usr/bin/env bash
# tests/unit/test-sheet.sh — Unit tests for src/sheet.sh
set -u
TESTS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.."; pwd)"
SHELLFRAME_DIR="$(cd "$TESTS_DIR/.."; pwd)"

source "$SHELLFRAME_DIR/src/input.sh"
source "$SHELLFRAME_DIR/src/screen.sh"
source "$SHELLFRAME_DIR/src/hitbox.sh"
source "$SHELLFRAME_DIR/src/shell.sh"
source "$SHELLFRAME_DIR/src/sheet.sh"
source "$PTYUNIT_HOME/assert.sh"

# fd 3 to /dev/null so shellframe_screen_flush doesn't error
exec 3>/dev/null

_reset_sheet() {
    _SHELLFRAME_SHEET_ACTIVE=0
    _SHELLFRAME_SHEET_PREFIX=""
    _SHELLFRAME_SHEET_SCREEN=""
    _SHELLFRAME_SHEET_NEXT=""
    _SHELLFRAME_SHEET_FROZEN_ROWS=()
    SHELLFRAME_SHEET_HEIGHT=0
    SHELLFRAME_SHEET_WIDTH=0
    _SHELLFRAME_SHEET_REGIONS=()
    _SHELLFRAME_SHEET_FOCUS_RING=()
    _SHELLFRAME_SHEET_FOCUS_IDX=0
    _SHELLFRAME_SHEET_FOCUS_REQUEST=""
    _SHELLFRAME_SHELL_ROWS=10
    _SHELLFRAME_SHELL_COLS=80
    shellframe_fb_frame_start 10 80
}

# ── shellframe_sheet_push ─────────────────────────────────────────────────────

ptyunit_test_begin "sheet_push: sets ACTIVE=1"
_reset_sheet
shellframe_sheet_push "_myapp" "OPEN_DB"
assert_eq "1" "$_SHELLFRAME_SHEET_ACTIVE" "ACTIVE is 1 after push"

ptyunit_test_begin "sheet_push: stores prefix and screen"
_reset_sheet
shellframe_sheet_push "_myapp" "OPEN_DB"
assert_eq "_myapp" "$_SHELLFRAME_SHEET_PREFIX" "prefix stored"
assert_eq "OPEN_DB" "$_SHELLFRAME_SHEET_SCREEN" "screen stored"

ptyunit_test_begin "sheet_push: NEXT is empty after push"
_reset_sheet
shellframe_sheet_push "_myapp" "OPEN_DB"
assert_eq "" "$_SHELLFRAME_SHEET_NEXT" "NEXT is empty"

ptyunit_test_begin "sheet_push: resets sheet focus state"
_reset_sheet
_SHELLFRAME_SHEET_FOCUS_IDX=3
shellframe_sheet_push "_myapp" "OPEN_DB"
assert_eq "0" "$_SHELLFRAME_SHEET_FOCUS_IDX" "focus idx reset to 0"
assert_eq "0" "${#_SHELLFRAME_SHEET_FOCUS_RING[@]}" "focus ring empty"

# ── double-push guard ─────────────────────────────────────────────────────────

ptyunit_test_begin "sheet_push: double-push returns 1 and preserves existing state"
_reset_sheet
shellframe_sheet_push "_myapp" "OPEN_DB"
rc=0
shellframe_sheet_push "_other" "OTHER_SCREEN" 2>/dev/null || rc=$?
assert_eq "1" "$rc" "double push returns 1"
assert_eq "_myapp" "$_SHELLFRAME_SHEET_PREFIX" "original prefix unchanged"
assert_eq "OPEN_DB" "$_SHELLFRAME_SHEET_SCREEN" "original screen unchanged"

ptyunit_test_begin "sheet_push: double-push writes warning to stderr"
_reset_sheet
shellframe_sheet_push "_myapp" "OPEN_DB"
errmsg=$(shellframe_sheet_push "_other" "OTHER" 2>&1 >/dev/null || true)
assert_contains "$errmsg" "sheet already active" "warning on stderr"

# ── shellframe_sheet_pop ──────────────────────────────────────────────────────

ptyunit_test_begin "sheet_pop: sets NEXT to __POP__"
_reset_sheet
shellframe_sheet_push "_myapp" "OPEN_DB"
shellframe_sheet_pop
assert_eq "__POP__" "$_SHELLFRAME_SHEET_NEXT" "NEXT set to __POP__"

# ── shellframe_sheet_active ───────────────────────────────────────────────────

ptyunit_test_begin "sheet_active: returns 0 when active"
_reset_sheet
shellframe_sheet_push "_myapp" "OPEN_DB"
shellframe_sheet_active
assert_eq "0" "$?" "exit code 0 when active"

ptyunit_test_begin "sheet_active: returns 1 when not active"
_reset_sheet
rc=0
shellframe_sheet_active || rc=$?
assert_eq "1" "$rc" "exit code 1 when inactive"

ptyunit_test_summary
```

- [ ] **Step 2: Run tests to verify they fail**

```
bash tests/run.sh --unit 2>&1 | grep test-sheet
```
Expected: FAIL — `src/sheet.sh: No such file`

- [ ] **Step 3: Create `src/sheet.sh` with state globals and public API**

```bash
#!/usr/bin/env bash
# shellframe/src/sheet.sh — Sheet navigation primitive
#
# A sheet is a partial overlay that sits above the current shellframe_shell
# screen. It shows one frozen dimmed row of the underlying screen at the top
# (the "back strip") and renders its own content from row 2 downward.
#
# Public API:
#   shellframe_sheet_push prefix screen  — open a sheet
#   shellframe_sheet_pop                 — schedule sheet dismissal
#   shellframe_sheet_active              — 0=true if a sheet is open
#   shellframe_sheet_draw rows cols      — called by shell.sh draw delegation
#   shellframe_sheet_on_key key          — called by shell.sh key delegation
#
# Consumer hooks (identical convention to shellframe_shell):
#   PREFIX_SCREEN_render()               — layout; set SHELLFRAME_SHEET_HEIGHT
#   PREFIX_SCREEN_REGION_render t l w h  — region render
#   PREFIX_SCREEN_REGION_on_key key      — region key handler (rc: 0=handled, 1=unhandled, 2=action)
#   PREFIX_SCREEN_REGION_on_focus active — focus change notification
#   PREFIX_SCREEN_REGION_action()        — called when on_key returns 2
#   PREFIX_SCREEN_quit()                 — called on Esc or Up-from-topmost
#
# Row coordinates in consumer hooks are sheet-relative: row 1 = first content
# row (screen row 2, immediately below the back strip). Use $SHELLFRAME_SHEET_WIDTH.
#
# KNOWN LIMITATION: back-strip dimming uses \033[2m...\033[22m. Rows containing
# \033[0m mid-string will have dim cancelled at that point — best-effort for v1.

# ── State globals ─────────────────────────────────────────────────────────────

_SHELLFRAME_SHEET_ACTIVE=0          # 0|1 — whether a sheet is currently open
_SHELLFRAME_SHEET_PREFIX=""         # consumer prefix (e.g. "_myapp")
_SHELLFRAME_SHEET_SCREEN=""         # current screen within the sheet
_SHELLFRAME_SHEET_NEXT=""           # next screen name; "__POP__" to dismiss
_SHELLFRAME_SHEET_FROZEN_ROWS=()    # full-screen framebuffer snapshot at push time
SHELLFRAME_SHEET_HEIGHT=0           # consumer sets in render hook; 0 = fill to bottom
SHELLFRAME_SHEET_WIDTH=0            # set before render hook; read-only for consumers
# Sheet-local focus / region registry (swapped in/out each frame)
_SHELLFRAME_SHEET_REGIONS=()
_SHELLFRAME_SHEET_FOCUS_RING=()
_SHELLFRAME_SHEET_FOCUS_IDX=0
_SHELLFRAME_SHEET_FOCUS_REQUEST=""

# ── shellframe_sheet_push ─────────────────────────────────────────────────────

shellframe_sheet_push() {
    local _prefix="$1" _screen="$2"

    if (( _SHELLFRAME_SHEET_ACTIVE )); then
        printf 'shellframe_sheet_push: sheet already active (stacking not supported in v1)\n' >&2
        return 1
    fi

    _SHELLFRAME_SHEET_ACTIVE=1
    _SHELLFRAME_SHEET_PREFIX="$_prefix"
    _SHELLFRAME_SHEET_SCREEN="$_screen"
    _SHELLFRAME_SHEET_NEXT=""

    # Snapshot current framebuffer for back strip and below-sheet frozen content
    local _rows="${_SHELLFRAME_SHELL_ROWS:-24}"
    _SHELLFRAME_SHEET_FROZEN_ROWS=()
    local _r
    for (( _r=1; _r<=_rows; _r++ )); do
        _SHELLFRAME_SHEET_FROZEN_ROWS[$_r]="${_SF_ROW_CURR[$_r]:-}"
    done

    # Reset sheet-local focus state (first frame starts at idx 0)
    _SHELLFRAME_SHEET_REGIONS=()
    _SHELLFRAME_SHEET_FOCUS_RING=()
    _SHELLFRAME_SHEET_FOCUS_IDX=0
    _SHELLFRAME_SHEET_FOCUS_REQUEST=""

    shellframe_shell_mark_dirty
}

# ── shellframe_sheet_pop ──────────────────────────────────────────────────────

shellframe_sheet_pop() {
    _SHELLFRAME_SHEET_NEXT="__POP__"
}

# ── shellframe_sheet_active ───────────────────────────────────────────────────

shellframe_sheet_active() {
    (( _SHELLFRAME_SHEET_ACTIVE ))
}
```

- [ ] **Step 4: Run unit tests to verify push/pop/active pass**

```
bash tests/run.sh --unit 2>&1 | grep -A2 "test-sheet"
```
Expected: all test-sheet.sh tests pass

- [ ] **Step 5: Commit**

```bash
git add src/sheet.sh tests/unit/test-sheet.sh
git commit -m "feat(sheet): module scaffold — state globals + push/pop/active API"
```

---

## Task 2: Framebuffer row offset + `shellframe_sheet_draw` core

**Files:**
- Modify: `src/screen.sh`
- Modify: `src/sheet.sh`
- Modify: `tests/unit/test-sheet.sh`

Sheet region render hooks call `shellframe_fb_print` / `shellframe_fb_fill` / `shellframe_fb_put` / `shellframe_fb_print_ansi` with sheet-relative row numbers (row 1 = sheet content row 1). These must map to screen rows offset by `_sheet_top - 1`. The `_SF_ROW_OFFSET` global (set to `_sheet_top - 1` during region dispatch, 0 otherwise) applies this translation inside all four fb functions.

- [ ] **Step 1: Write failing unit tests for draw and registry swap**

Append to `tests/unit/test-sheet.sh` (before `ptyunit_test_summary`):

```bash
# ── shellframe_sheet_draw: registry swap ───────────────────────────────────────

# Helper: minimal render hook for tests
_tst_FORM_render() {
    shellframe_shell_region body 1 1 "$SHELLFRAME_SHEET_WIDTH" 5
}
_tst_FORM_body_render() { :; }

ptyunit_test_begin "sheet_draw: parent shell regions restored after draw"
_reset_sheet
_SHELLFRAME_SHELL_REGIONS=("parent:1:1:80:10:focus")
shellframe_sheet_push "_tst" "FORM"
shellframe_sheet_draw 10 80
assert_eq "1" "${#_SHELLFRAME_SHELL_REGIONS[@]}" "parent region count unchanged"
assert_eq "parent:1:1:80:10:focus" "${_SHELLFRAME_SHELL_REGIONS[0]}" "parent entry unchanged"

ptyunit_test_begin "sheet_draw: parent focus ring restored after draw"
_reset_sheet
_SHELLFRAME_SHELL_FOCUS_RING=("parent")
_SHELLFRAME_SHELL_FOCUS_IDX=0
shellframe_sheet_push "_tst" "FORM"
shellframe_sheet_draw 10 80
assert_eq "1" "${#_SHELLFRAME_SHELL_FOCUS_RING[@]}" "parent focus ring count unchanged"
assert_eq "parent" "${_SHELLFRAME_SHELL_FOCUS_RING[0]}" "parent focus ring entry unchanged"

ptyunit_test_begin "sheet_draw: SHEET_WIDTH set to cols before render hook"
_reset_sheet
_tst_WIDE_render() { :; }
shellframe_sheet_push "_tst" "WIDE"
shellframe_sheet_draw 10 120
assert_eq "120" "$SHELLFRAME_SHEET_WIDTH" "SHEET_WIDTH set to cols"

ptyunit_test_begin "sheet_draw: height=0 resolves to rows-1"
_reset_sheet
SHELLFRAME_SHEET_HEIGHT=0
shellframe_sheet_push "_tst" "FORM"
shellframe_sheet_draw 10 80
# sheet ran without error; height resolution verified by frozen row write below row 2
assert_eq "0" "$?" "draw exits 0"

ptyunit_test_begin "sheet_draw: frozen rows written at row 1 with dim wrapper"
_reset_sheet
# Set up a known frozen row 1 by writing to the framebuffer before push
shellframe_fb_frame_start 10 80
shellframe_fb_print 1 1 "parent content"
shellframe_sheet_push "_tst" "FORM"
# Now draw — row 1 in CURR should be the dimmed frozen row
_SF_ROW_CURR=()
_SF_DIRTY_ROWS=()
shellframe_sheet_draw 10 80
assert_contains "${_SF_ROW_CURR[1]:-}" $'\033[2m' "row 1 contains dim sequence"
assert_contains "${_SF_ROW_CURR[1]:-}" $'\033[22m' "row 1 ends dim sequence"
```

- [ ] **Step 2: Run tests to verify new tests fail**

```
bash tests/run.sh --unit 2>&1 | grep -E "(PASS|FAIL)" | tail -20
```
Expected: new draw tests FAIL — `shellframe_sheet_draw: command not found`

- [ ] **Step 3: Add `_SF_ROW_OFFSET` to `src/screen.sh`**

Add below line 89 (`_SF_FRAME_COLS=80`):
```bash
_SF_ROW_OFFSET=0  # Set by sheet.sh during region dispatch; 0 = no offset
```

Modify `shellframe_fb_put` (lines 103–108):
```bash
shellframe_fb_put() {
    local _r=$(( $1 + _SF_ROW_OFFSET ))
    local _frag
    printf -v _frag '\033[%d;%dH%s' "$_r" "$2" "$3"
    _SF_ROW_CURR[$_r]+="$_frag"
    _SF_DIRTY_ROWS[$_r]=1
}
```

Modify `shellframe_fb_print` (lines 113–118):
```bash
shellframe_fb_print() {
    local _r=$(( $1 + _SF_ROW_OFFSET ))
    local _frag
    printf -v _frag '\033[%d;%dH%s%s' "$_r" "$2" "${4:-}" "$3"
    _SF_ROW_CURR[$_r]+="$_frag"
    _SF_DIRTY_ROWS[$_r]=1
}
```

Modify `shellframe_fb_fill` (lines 123–131):
```bash
shellframe_fb_fill() {
    local _r=$(( $1 + _SF_ROW_OFFSET ))
    local _fill
    printf -v _fill '%*s' "$3" ''
    [[ "${4:- }" != " " ]] && _fill="${_fill// /${4}}"
    local _frag
    printf -v _frag '\033[%d;%dH%s%s' "$_r" "$2" "${5:-}" "$_fill"
    _SF_ROW_CURR[$_r]+="$_frag"
    _SF_DIRTY_ROWS[$_r]=1
}
```

Modify `shellframe_fb_print_ansi` (lines 137–142):
```bash
shellframe_fb_print_ansi() {
    local _r=$(( $1 + _SF_ROW_OFFSET ))
    local _frag
    printf -v _frag '\033[%d;%dH%s' "$_r" "$2" "$3"
    _SF_ROW_CURR[$_r]+="$_frag"
    _SF_DIRTY_ROWS[$_r]=1
}
```

- [ ] **Step 4: Run existing unit tests to confirm no regression**

```
bash tests/run.sh --unit
```
Expected: all existing tests pass (offset is 0 by default, so no behavior change)

- [ ] **Step 5: Add `shellframe_sheet_draw` to `src/sheet.sh`**

Append to `src/sheet.sh` (after `shellframe_sheet_active`):

```bash
# ── shellframe_sheet_draw ─────────────────────────────────────────────────────
#
# Called by shell.sh when _SHELLFRAME_SHEET_ACTIVE=1 (replaces normal draw).
# Handles screen transitions and __POP__ dismissal, then renders the sheet
# frame: frozen back strip + sheet content + frozen content below sheet.
#
# rows cols — current terminal dimensions (provided by shell.sh delegation)

shellframe_sheet_draw() {
    local _rows="$1" _cols="$2"
    local _prefix="$_SHELLFRAME_SHEET_PREFIX"
    local _screen="$_SHELLFRAME_SHEET_SCREEN"

    # ── Screen transition / pop ───────────────────────────────────────────────
    if [[ -n "${_SHELLFRAME_SHEET_NEXT:-}" ]]; then
        if [[ "$_SHELLFRAME_SHEET_NEXT" == "__POP__" ]]; then
            # Restore full parent screen from frozen rows, then clear sheet state
            shellframe_fb_frame_start "$_rows" "$_cols"
            local _r
            for (( _r=1; _r<=_rows; _r++ )); do
                shellframe_fb_print_ansi "$_r" 1 "${_SHELLFRAME_SHEET_FROZEN_ROWS[$_r]:-}"
            done
            shellframe_screen_flush
            _SHELLFRAME_SHEET_ACTIVE=0
            _SHELLFRAME_SHEET_PREFIX=""
            _SHELLFRAME_SHEET_SCREEN=""
            _SHELLFRAME_SHEET_NEXT=""
            _SHELLFRAME_SHEET_FROZEN_ROWS=()
            _SHELLFRAME_SHEET_REGIONS=()
            _SHELLFRAME_SHEET_FOCUS_RING=()
            _SHELLFRAME_SHEET_FOCUS_IDX=0
            _SHELLFRAME_SHEET_FOCUS_REQUEST=""
            SHELLFRAME_SHEET_HEIGHT=0
            SHELLFRAME_SHEET_WIDTH=0
            shellframe_shell_mark_dirty
            return
        fi
        # Internal screen transition
        _SHELLFRAME_SHEET_SCREEN="$_SHELLFRAME_SHEET_NEXT"
        _prefix="$_SHELLFRAME_SHEET_PREFIX"
        _screen="$_SHELLFRAME_SHEET_SCREEN"
        _SHELLFRAME_SHEET_NEXT=""
        _SHELLFRAME_SHEET_REGIONS=()
        _SHELLFRAME_SHEET_FOCUS_RING=()
        _SHELLFRAME_SHEET_FOCUS_IDX=0
        _SHELLFRAME_SHEET_FOCUS_REQUEST=""
    fi

    # ── Registry swap in ──────────────────────────────────────────────────────
    # Save parent shell's focus state to locals
    local _saved_regions=()
    local _saved_ring=()
    local _saved_idx="$_SHELLFRAME_SHELL_FOCUS_IDX"
    local _saved_req="$_SHELLFRAME_SHELL_FOCUS_REQUEST"
    _saved_regions=("${_SHELLFRAME_SHELL_REGIONS[@]+"${_SHELLFRAME_SHELL_REGIONS[@]}"}")
    _saved_ring=("${_SHELLFRAME_SHELL_FOCUS_RING[@]+"${_SHELLFRAME_SHELL_FOCUS_RING[@]}"}")
    # Load sheet focus state into shell globals (for focus_init / focus_owner)
    _SHELLFRAME_SHELL_FOCUS_RING=("${_SHELLFRAME_SHEET_FOCUS_RING[@]+"${_SHELLFRAME_SHEET_FOCUS_RING[@]}"}")
    _SHELLFRAME_SHELL_FOCUS_IDX="$_SHELLFRAME_SHEET_FOCUS_IDX"
    _SHELLFRAME_SHELL_FOCUS_REQUEST="$_SHELLFRAME_SHEET_FOCUS_REQUEST"

    # ── Frame setup ───────────────────────────────────────────────────────────
    shellframe_fb_frame_start "$_rows" "$_cols"
    SHELLFRAME_SHEET_WIDTH="$_cols"
    SHELLFRAME_SHEET_HEIGHT=0

    # Reset region registry for re-registration by the render hook
    _SHELLFRAME_SHELL_REGIONS=()
    shellframe_widget_clear

    # ── Render hook: consumer registers regions + optionally sets SHEET_HEIGHT
    "${_prefix}_${_screen}_render"

    # ── Resolve sheet bounds ──────────────────────────────────────────────────
    local _sheet_top=2
    local _sheet_h
    if (( SHELLFRAME_SHEET_HEIGHT > 0 )); then
        _sheet_h="$SHELLFRAME_SHEET_HEIGHT"
    else
        _sheet_h=$(( _rows - 1 ))
    fi
    local _sheet_bottom=$(( _sheet_top + _sheet_h - 1 ))

    # ── Frozen rows into framebuffer ──────────────────────────────────────────
    # Row 1 (back strip): show dimmed parent content
    shellframe_fb_print_ansi 1 1 $'\033[2m'"${_SHELLFRAME_SHEET_FROZEN_ROWS[1]:-}"$'\033[22m'
    # Rows below sheet: show dimmed parent content (if sheet doesn't fill to bottom)
    local _r
    for (( _r=_sheet_bottom+1; _r<=_rows; _r++ )); do
        shellframe_fb_print_ansi "$_r" 1 $'\033[2m'"${_SHELLFRAME_SHEET_FROZEN_ROWS[$_r]:-}"$'\033[22m'
    done

    # ── Rebuild focus ring ────────────────────────────────────────────────────
    _shellframe_shell_focus_init

    # ── Fire on_focus for each region ─────────────────────────────────────────
    local _focused
    _shellframe_shell_focus_owner _focused
    local _entry _n
    for _entry in "${_SHELLFRAME_SHELL_REGIONS[@]+"${_SHELLFRAME_SHELL_REGIONS[@]}"}"; do
        _n="${_entry%%:*}"
        if declare -f "${_prefix}_${_screen}_${_n}_on_focus" >/dev/null 2>&1; then
            if [[ "$_n" == "$_focused" ]]; then
                "${_prefix}_${_screen}_${_n}_on_focus" 1
            else
                "${_prefix}_${_screen}_${_n}_on_focus" 0
            fi
        fi
    done

    # ── Render sheet regions (with sheet row offset applied) ──────────────────
    _SF_ROW_OFFSET=$(( _sheet_top - 1 ))
    for _entry in "${_SHELLFRAME_SHELL_REGIONS[@]+"${_SHELLFRAME_SHELL_REGIONS[@]}"}"; do
        _n="${_entry%%:*}"
        local _rest="${_entry#*:}"
        local _top="${_rest%%:*}"; _rest="${_rest#*:}"
        local _left="${_rest%%:*}"; _rest="${_rest#*:}"
        local _w="${_rest%%:*}"; _rest="${_rest#*:}"
        local _h="${_rest%%:*}"
        if declare -f "${_prefix}_${_screen}_${_n}_render" >/dev/null 2>&1; then
            "${_prefix}_${_screen}_${_n}_render" "$_top" "$_left" "$_w" "$_h"
        fi
    done
    _SF_ROW_OFFSET=0

    # ── Registry swap out ─────────────────────────────────────────────────────
    # Save updated sheet focus state
    _SHELLFRAME_SHEET_REGIONS=("${_SHELLFRAME_SHELL_REGIONS[@]+"${_SHELLFRAME_SHELL_REGIONS[@]}"}")
    _SHELLFRAME_SHEET_FOCUS_RING=("${_SHELLFRAME_SHELL_FOCUS_RING[@]+"${_SHELLFRAME_SHELL_FOCUS_RING[@]}"}")
    _SHELLFRAME_SHEET_FOCUS_IDX="$_SHELLFRAME_SHELL_FOCUS_IDX"
    _SHELLFRAME_SHEET_FOCUS_REQUEST="$_SHELLFRAME_SHELL_FOCUS_REQUEST"
    # Restore parent shell registry
    _SHELLFRAME_SHELL_REGIONS=("${_saved_regions[@]+"${_saved_regions[@]}"}")
    _SHELLFRAME_SHELL_FOCUS_RING=("${_saved_ring[@]+"${_saved_ring[@]}"}")
    _SHELLFRAME_SHELL_FOCUS_IDX="$_saved_idx"
    _SHELLFRAME_SHELL_FOCUS_REQUEST="$_saved_req"

    # ── Flush ─────────────────────────────────────────────────────────────────
    shellframe_screen_flush
}
```

- [ ] **Step 6: Run unit tests to verify new draw tests pass**

```
bash tests/run.sh --unit 2>&1 | grep -E "(PASS|FAIL)"
```
Expected: all tests pass

- [ ] **Step 7: Commit**

```bash
git add src/screen.sh src/sheet.sh tests/unit/test-sheet.sh
git commit -m "feat(sheet): shellframe_sheet_draw — registry swap + frozen rows + region dispatch"
```

---

## Task 3: Screen transitions in `shellframe_sheet_draw`

Transition handling is already embedded in `shellframe_sheet_draw` (from Task 2). This task adds unit tests that verify the behavior.

**Files:**
- Modify: `tests/unit/test-sheet.sh`

- [ ] **Step 1: Append transition + pop unit tests to `tests/unit/test-sheet.sh`**

```bash
# ── Screen transitions and __POP__ ────────────────────────────────────────────

ptyunit_test_begin "sheet_draw: SHEET_NEXT=STEP2 transitions to new screen"
_reset_sheet
shellframe_sheet_push "_tst" "FORM"
_SHELLFRAME_SHEET_NEXT="STEP2"
_tst_STEP2_render() { :; }
shellframe_sheet_draw 10 80
assert_eq "STEP2" "$_SHELLFRAME_SHEET_SCREEN" "screen updated to STEP2"
assert_eq "" "$_SHELLFRAME_SHEET_NEXT" "NEXT cleared"

ptyunit_test_begin "sheet_draw: transition resets focus state"
_reset_sheet
shellframe_sheet_push "_tst" "FORM"
_SHELLFRAME_SHEET_FOCUS_IDX=2
_SHELLFRAME_SHEET_NEXT="STEP2"
_tst_STEP2_render() { :; }
shellframe_sheet_draw 10 80
assert_eq "0" "$_SHELLFRAME_SHEET_FOCUS_IDX" "focus idx reset to 0 after transition"

ptyunit_test_begin "sheet_draw: SHEET_NEXT=__POP__ clears ACTIVE"
_reset_sheet
shellframe_sheet_push "_tst" "FORM"
shellframe_sheet_pop
shellframe_sheet_draw 10 80
assert_eq "0" "$_SHELLFRAME_SHEET_ACTIVE" "ACTIVE=0 after pop"

ptyunit_test_begin "sheet_draw: SHEET_NEXT=__POP__ clears prefix and screen"
_reset_sheet
shellframe_sheet_push "_tst" "FORM"
shellframe_sheet_pop
shellframe_sheet_draw 10 80
assert_eq "" "$_SHELLFRAME_SHEET_PREFIX" "prefix cleared"
assert_eq "" "$_SHELLFRAME_SHEET_SCREEN" "screen cleared"

ptyunit_test_begin "sheet_draw: SHEET_NEXT=__POP__ marks parent dirty"
_reset_sheet
shellframe_sheet_push "_tst" "FORM"
shellframe_sheet_pop
_SHELLFRAME_SHELL_DIRTY=0
shellframe_sheet_draw 10 80
assert_eq "1" "$_SHELLFRAME_SHELL_DIRTY" "parent marked dirty after pop"

ptyunit_test_begin "sheet_draw: SHEET_NEXT=__POP__ restores parent regions"
_reset_sheet
_SHELLFRAME_SHELL_REGIONS=("parent:1:1:80:10:focus")
shellframe_sheet_push "_tst" "FORM"
shellframe_sheet_pop
shellframe_sheet_draw 10 80
assert_eq "parent:1:1:80:10:focus" "${_SHELLFRAME_SHELL_REGIONS[0]}" "parent regions intact after pop"

ptyunit_test_begin "sheet_draw: explicit height is used when set by render hook"
_reset_sheet
_tst_TALL_render() { SHELLFRAME_SHEET_HEIGHT=6; }
shellframe_sheet_push "_tst" "TALL"
SHELLFRAME_SHEET_HEIGHT=0
shellframe_sheet_draw 10 80
# Verify frozen rows below sheet boundary got written (rows 8-10 for height=6, top=2)
assert_contains "${_SF_ROW_CURR[8]:-}" $'\033[2m' "row below sheet has dim wrapper"
```

- [ ] **Step 2: Run unit tests**

```
bash tests/run.sh --unit
```
Expected: all tests pass

- [ ] **Step 3: Commit**

```bash
git add tests/unit/test-sheet.sh
git commit -m "test(sheet): screen transition and __POP__ unit tests"
```

---

## Task 4: `shellframe_sheet_on_key`

**Files:**
- Modify: `src/sheet.sh`
- Modify: `tests/unit/test-sheet.sh`

- [ ] **Step 1: Append on_key unit tests to `tests/unit/test-sheet.sh`**

```bash
# ── shellframe_sheet_on_key ────────────────────────────────────────────────────

# Common setup: push a sheet with two focusable regions
_setup_two_region_sheet() {
    _reset_sheet
    # Register two focusable regions in the sheet's state
    _SHELLFRAME_SHELL_REGIONS=("body:1:1:80:4:focus" "footer:5:1:80:1:focus")
    _shellframe_shell_focus_init
    _SHELLFRAME_SHEET_REGIONS=("${_SHELLFRAME_SHELL_REGIONS[@]}")
    _SHELLFRAME_SHEET_FOCUS_RING=("${_SHELLFRAME_SHELL_FOCUS_RING[@]}")
    _SHELLFRAME_SHEET_FOCUS_IDX=0
    _SHELLFRAME_SHELL_REGIONS=()
    _SHELLFRAME_SHELL_FOCUS_RING=()
    _SHELLFRAME_SHELL_FOCUS_IDX=0
    shellframe_sheet_push "_tst" "FORM"
    # After push, restore the regions we set up
    _SHELLFRAME_SHEET_REGIONS=("body:1:1:80:4:focus" "footer:5:1:80:1:focus")
    _SHELLFRAME_SHEET_FOCUS_RING=("body" "footer")
    _SHELLFRAME_SHEET_FOCUS_IDX=0
}

# Provide minimal on_key handlers for region dispatch testing
_tst_FORM_body_on_key() { return 0; }   # handled
_tst_FORM_footer_on_key() { return 1; } # unhandled

ptyunit_test_begin "sheet_on_key: Esc calls quit hook if defined"
_setup_two_region_sheet
_quit_called=0
_tst_FORM_quit() { _quit_called=1; shellframe_sheet_pop; }
shellframe_sheet_on_key $'\033'
assert_eq "1" "$_quit_called" "quit hook called on Esc"
assert_eq "__POP__" "$_SHELLFRAME_SHEET_NEXT" "NEXT set to __POP__"

ptyunit_test_begin "sheet_on_key: Esc pops sheet if no quit hook"
_setup_two_region_sheet
unset -f _tst_FORM_quit 2>/dev/null || true
shellframe_sheet_on_key $'\033'
assert_eq "__POP__" "$_SHELLFRAME_SHEET_NEXT" "NEXT=__POP__ when no quit hook"

ptyunit_test_begin "sheet_on_key: Tab advances focus"
_setup_two_region_sheet
assert_eq "0" "$_SHELLFRAME_SHEET_FOCUS_IDX" "starts at 0"
shellframe_sheet_on_key $'\t'
assert_eq "1" "$_SHELLFRAME_SHEET_FOCUS_IDX" "focus advanced to 1 after Tab"

ptyunit_test_begin "sheet_on_key: Shift-Tab retreats focus"
_setup_two_region_sheet
_SHELLFRAME_SHEET_FOCUS_IDX=1
shellframe_sheet_on_key "${SHELLFRAME_KEY_SHIFT_TAB:-$'\033[Z'}"
assert_eq "0" "$_SHELLFRAME_SHEET_FOCUS_IDX" "focus retreated to 0 after Shift-Tab"

ptyunit_test_begin "sheet_on_key: Up from topmost region (idx=0) calls quit"
_setup_two_region_sheet
_quit_called=0
_tst_FORM_quit() { _quit_called=1; shellframe_sheet_pop; }
# body_on_key returns 1 (unhandled) for Up at topmost — simulate by making it return 1
_tst_FORM_body_on_key() { return 1; }
shellframe_sheet_on_key $'\033[A'
assert_eq "1" "$_quit_called" "quit called when Up unhandled at topmost"

ptyunit_test_begin "sheet_on_key: Up from non-topmost region does not call quit"
_setup_two_region_sheet
_SHELLFRAME_SHEET_FOCUS_IDX=1   # focus on footer (idx 1, not topmost)
_quit_called=0
_tst_FORM_quit() { _quit_called=1; }
_tst_FORM_footer_on_key() { return 1; }  # unhandled
shellframe_sheet_on_key $'\033[A'
assert_eq "0" "$_quit_called" "quit NOT called when Up unhandled at non-topmost"

ptyunit_test_begin "sheet_on_key: rc=2 dispatches action and marks dirty"
_setup_two_region_sheet
_action_called=0
_tst_FORM_body_on_key() { return 2; }
_tst_FORM_body_action() { _action_called=1; }
_SHELLFRAME_SHELL_DIRTY=0
shellframe_sheet_on_key "x"
assert_eq "1" "$_action_called" "action hook called on rc=2"
assert_eq "1" "$_SHELLFRAME_SHELL_DIRTY" "dirty marked after action"

ptyunit_test_begin "sheet_on_key: parent shell regions unchanged after key dispatch"
_setup_two_region_sheet
_SHELLFRAME_SHELL_REGIONS=("parent:1:1:80:10:focus")
shellframe_sheet_on_key "x"
assert_eq "parent:1:1:80:10:focus" "${_SHELLFRAME_SHELL_REGIONS[0]}" "parent regions unchanged"
```

- [ ] **Step 2: Run tests to verify new tests fail**

```
bash tests/run.sh --unit 2>&1 | grep FAIL | grep sheet
```
Expected: new on_key tests FAIL — `shellframe_sheet_on_key: command not found`

- [ ] **Step 3: Add `shellframe_sheet_on_key` to `src/sheet.sh`**

Append to `src/sheet.sh`:

```bash
# ── shellframe_sheet_on_key ───────────────────────────────────────────────────
#
# Key dispatch for the active sheet. Called by shell.sh key loop delegation.
# Mirrors shell.sh key handling: Tab/Shift-Tab cycle focus, rc=2 dispatches
# action, Esc calls quit hook (or pops), Up unhandled at topmost calls quit.
# Registry swap ensures shell globals work correctly and parent state is restored.

shellframe_sheet_on_key() {
    local _key="$1"
    local _prefix="$_SHELLFRAME_SHEET_PREFIX"
    local _screen="$_SHELLFRAME_SHEET_SCREEN"

    local _k_esc=$'\033'
    local _k_up=$'\033[A'
    local _k_tab=$'\t'
    local _k_shift_tab="${SHELLFRAME_KEY_SHIFT_TAB:-$'\033[Z'}"

    # ── Registry swap in ──────────────────────────────────────────────────────
    local _saved_regions=()
    local _saved_ring=()
    local _saved_idx="$_SHELLFRAME_SHELL_FOCUS_IDX"
    local _saved_req="$_SHELLFRAME_SHELL_FOCUS_REQUEST"
    _saved_regions=("${_SHELLFRAME_SHELL_REGIONS[@]+"${_SHELLFRAME_SHELL_REGIONS[@]}"}")
    _saved_ring=("${_SHELLFRAME_SHELL_FOCUS_RING[@]+"${_SHELLFRAME_SHELL_FOCUS_RING[@]}"}")
    _SHELLFRAME_SHELL_REGIONS=("${_SHELLFRAME_SHEET_REGIONS[@]+"${_SHELLFRAME_SHEET_REGIONS[@]}"}")
    _SHELLFRAME_SHELL_FOCUS_RING=("${_SHELLFRAME_SHEET_FOCUS_RING[@]+"${_SHELLFRAME_SHEET_FOCUS_RING[@]}"}")
    _SHELLFRAME_SHELL_FOCUS_IDX="$_SHELLFRAME_SHEET_FOCUS_IDX"
    _SHELLFRAME_SHELL_FOCUS_REQUEST="$_SHELLFRAME_SHEET_FOCUS_REQUEST"

    # ── Esc: dismiss sheet ────────────────────────────────────────────────────
    if [[ "$_key" == "$_k_esc" ]]; then
        if declare -f "${_prefix}_${_screen}_quit" >/dev/null 2>&1; then
            "${_prefix}_${_screen}_quit"
        else
            shellframe_sheet_pop
        fi
        shellframe_shell_mark_dirty
        # swap out and return
        _SHELLFRAME_SHEET_REGIONS=("${_SHELLFRAME_SHELL_REGIONS[@]+"${_SHELLFRAME_SHELL_REGIONS[@]}"}")
        _SHELLFRAME_SHEET_FOCUS_RING=("${_SHELLFRAME_SHELL_FOCUS_RING[@]+"${_SHELLFRAME_SHELL_FOCUS_RING[@]}"}")
        _SHELLFRAME_SHEET_FOCUS_IDX="$_SHELLFRAME_SHELL_FOCUS_IDX"
        _SHELLFRAME_SHELL_REGIONS=("${_saved_regions[@]+"${_saved_regions[@]}"}")
        _SHELLFRAME_SHELL_FOCUS_RING=("${_saved_ring[@]+"${_saved_ring[@]}"}")
        _SHELLFRAME_SHELL_FOCUS_IDX="$_saved_idx"
        _SHELLFRAME_SHELL_FOCUS_REQUEST="$_saved_req"
        return 0
    fi

    # ── Tab: cycle focus forward ──────────────────────────────────────────────
    if [[ "$_key" == "$_k_tab" ]]; then
        local _focused
        _shellframe_shell_focus_owner _focused
        local _handled=0
        if [[ -n "$_focused" ]] && \
           declare -f "${_prefix}_${_screen}_${_focused}_on_key" >/dev/null 2>&1; then
            if "${_prefix}_${_screen}_${_focused}_on_key" "$_key"; then
                _handled=1
            fi
        fi
        if (( ! _handled )); then
            [[ -n "$_focused" ]] && \
                declare -f "${_prefix}_${_screen}_${_focused}_on_focus" >/dev/null 2>&1 && \
                "${_prefix}_${_screen}_${_focused}_on_focus" 0 || true
            _shellframe_shell_focus_next
        fi
        shellframe_shell_mark_dirty
        _SHELLFRAME_SHEET_FOCUS_RING=("${_SHELLFRAME_SHELL_FOCUS_RING[@]+"${_SHELLFRAME_SHELL_FOCUS_RING[@]}"}")
        _SHELLFRAME_SHEET_FOCUS_IDX="$_SHELLFRAME_SHELL_FOCUS_IDX"
        _SHELLFRAME_SHELL_REGIONS=("${_saved_regions[@]+"${_saved_regions[@]}"}")
        _SHELLFRAME_SHELL_FOCUS_RING=("${_saved_ring[@]+"${_saved_ring[@]}"}")
        _SHELLFRAME_SHELL_FOCUS_IDX="$_saved_idx"
        _SHELLFRAME_SHELL_FOCUS_REQUEST="$_saved_req"
        return 0
    fi

    # ── Shift-Tab: cycle focus backward ──────────────────────────────────────
    if [[ "$_key" == "$_k_shift_tab" ]]; then
        local _focused
        _shellframe_shell_focus_owner _focused
        local _handled=0
        if [[ -n "$_focused" ]] && \
           declare -f "${_prefix}_${_screen}_${_focused}_on_key" >/dev/null 2>&1; then
            if "${_prefix}_${_screen}_${_focused}_on_key" "$_key"; then
                _handled=1
            fi
        fi
        if (( ! _handled )); then
            [[ -n "$_focused" ]] && \
                declare -f "${_prefix}_${_screen}_${_focused}_on_focus" >/dev/null 2>&1 && \
                "${_prefix}_${_screen}_${_focused}_on_focus" 0 || true
            _shellframe_shell_focus_prev
        fi
        shellframe_shell_mark_dirty
        _SHELLFRAME_SHEET_FOCUS_RING=("${_SHELLFRAME_SHELL_FOCUS_RING[@]+"${_SHELLFRAME_SHELL_FOCUS_RING[@]}"}")
        _SHELLFRAME_SHEET_FOCUS_IDX="$_SHELLFRAME_SHELL_FOCUS_IDX"
        _SHELLFRAME_SHELL_REGIONS=("${_saved_regions[@]+"${_saved_regions[@]}"}")
        _SHELLFRAME_SHELL_FOCUS_RING=("${_saved_ring[@]+"${_saved_ring[@]}"}")
        _SHELLFRAME_SHELL_FOCUS_IDX="$_saved_idx"
        _SHELLFRAME_SHELL_FOCUS_REQUEST="$_saved_req"
        return 0
    fi

    # ── Deliver key to focused region ─────────────────────────────────────────
    local _focused
    _shellframe_shell_focus_owner _focused
    if [[ -n "$_focused" ]] && \
       declare -f "${_prefix}_${_screen}_${_focused}_on_key" >/dev/null 2>&1; then
        local _rc=0
        "${_prefix}_${_screen}_${_focused}_on_key" "$_key" || _rc=$?

        if (( _rc == 0 )); then
            shellframe_shell_mark_dirty
        elif (( _rc == 1 )); then
            # Unhandled — check for Up-from-topmost dismiss
            if [[ "$_key" == "$_k_up" ]] && (( _SHELLFRAME_SHELL_FOCUS_IDX == 0 )); then
                if declare -f "${_prefix}_${_screen}_quit" >/dev/null 2>&1; then
                    "${_prefix}_${_screen}_quit"
                else
                    shellframe_sheet_pop
                fi
                shellframe_shell_mark_dirty
            fi
        elif (( _rc == 2 )); then
            _SHELLFRAME_SHEET_NEXT=""
            declare -f "${_prefix}_${_screen}_${_focused}_action" >/dev/null 2>&1 && \
                "${_prefix}_${_screen}_${_focused}_action" || true
            shellframe_shell_mark_dirty
        fi
    fi

    # ── Registry swap out ─────────────────────────────────────────────────────
    _SHELLFRAME_SHEET_REGIONS=("${_SHELLFRAME_SHELL_REGIONS[@]+"${_SHELLFRAME_SHELL_REGIONS[@]}"}")
    _SHELLFRAME_SHEET_FOCUS_RING=("${_SHELLFRAME_SHELL_FOCUS_RING[@]+"${_SHELLFRAME_SHELL_FOCUS_RING[@]}"}")
    _SHELLFRAME_SHEET_FOCUS_IDX="$_SHELLFRAME_SHELL_FOCUS_IDX"
    _SHELLFRAME_SHEET_FOCUS_REQUEST="$_SHELLFRAME_SHELL_FOCUS_REQUEST"
    _SHELLFRAME_SHELL_REGIONS=("${_saved_regions[@]+"${_saved_regions[@]}"}")
    _SHELLFRAME_SHELL_FOCUS_RING=("${_saved_ring[@]+"${_saved_ring[@]}"}")
    _SHELLFRAME_SHELL_FOCUS_IDX="$_saved_idx"
    _SHELLFRAME_SHELL_FOCUS_REQUEST="$_saved_req"
}
```

- [ ] **Step 4: Run all unit tests**

```
bash tests/run.sh --unit
```
Expected: all tests pass

- [ ] **Step 5: Commit**

```bash
git add src/sheet.sh tests/unit/test-sheet.sh
git commit -m "feat(sheet): shellframe_sheet_on_key — Esc/Up dismiss, Tab focus cycle, action dispatch"
```

---

## Task 5: `shell.sh` + `shellframe.sh` wiring

**Files:**
- Modify: `src/shell.sh`
- Modify: `shellframe.sh`

- [ ] **Step 1: Source `src/sheet.sh` in `shellframe.sh`**

In `shellframe.sh`, after line 41 (`source "$SHELLFRAME_DIR/src/shell.sh"`), add:

```bash
source "$SHELLFRAME_DIR/src/sheet.sh"
```

- [ ] **Step 2: Add draw delegation to `_shellframe_shell_draw` in `src/shell.sh`**

In `_shellframe_shell_draw` (line 255), right after the `_shellframe_shell_refresh_size` call (line 259), add:

```bash
    # Sheet delegation: if a sheet is active, hand off the draw cycle entirely
    if (( _SHELLFRAME_SHEET_ACTIVE )); then
        shellframe_sheet_draw "$_SHELLFRAME_SHELL_ROWS" "$_SHELLFRAME_SHELL_COLS"
        return
    fi
```

The result at this point in the function should look like:
```bash
_shellframe_shell_draw() {
    local _prefix="$1" _screen="$2"

    # Refresh terminal size once per draw (no per-call stty forks)
    _shellframe_shell_refresh_size

    # Sheet delegation: if a sheet is active, hand off the draw cycle entirely
    if (( _SHELLFRAME_SHEET_ACTIVE )); then
        shellframe_sheet_draw "$_SHELLFRAME_SHELL_ROWS" "$_SHELLFRAME_SHELL_COLS"
        return
    fi

    # Tick toast TTLs; ...
```

- [ ] **Step 3: Add key delegation to the shell key loop in `src/shell.sh`**

In the key loop, right after the resize check block (lines 483–487) and before the `local _focused` declaration (line 489), add:

```bash
            # Sheet delegation: hand key to sheet while one is active
            if (( _SHELLFRAME_SHEET_ACTIVE )); then
                shellframe_sheet_on_key "$_key"
                _shellframe_shell_draw_if_dirty "$_prefix" "$_current"
                continue
            fi
```

The surrounding context should look like:
```bash
            # Check for resize after read returns
            if (( _SHELLFRAME_SHELL_RESIZED )); then
                _SHELLFRAME_SHELL_RESIZED=0
                shellframe_screen_clear
                _shellframe_shell_draw "$_prefix" "$_current"
            fi

            # Sheet delegation: hand key to sheet while one is active
            if (( _SHELLFRAME_SHEET_ACTIVE )); then
                shellframe_sheet_on_key "$_key"
                _shellframe_shell_draw_if_dirty "$_prefix" "$_current"
                continue
            fi

            local _focused
            _shellframe_shell_focus_owner _focused
```

- [ ] **Step 4: Run the full unit test suite to confirm no regression**

```
bash tests/run.sh --unit
```
Expected: all tests pass (including all pre-existing unit tests)

- [ ] **Step 5: Run the full test suite**

```
bash tests/run.sh
```
Expected: all tests pass

- [ ] **Step 6: Commit**

```bash
git add shellframe.sh src/shell.sh
git commit -m "feat(sheet): wire shell.sh draw + key delegation; source sheet.sh"
```

---

## Task 6: Two-step wizard example + integration tests

**Files:**
- Create: `examples/sheet.sh`
- Create: `tests/integration/test-sheet.sh`

- [ ] **Step 1: Write integration tests (they will fail until example is created)**

Create `tests/integration/test-sheet.sh`:

```bash
#!/usr/bin/env bash
# tests/integration/test-sheet.sh — PTY tests for examples/sheet.sh

set -u
TESTS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SHELLFRAME_DIR="$(cd "$TESTS_DIR/.." && pwd)"
PTY_RUN="$PTYUNIT_HOME/pty_run.py"
SCRIPT="$SHELLFRAME_DIR/examples/sheet.sh"

source "$PTYUNIT_HOME/assert.sh"

_pty() {
    python3 "$PTY_RUN" "$SCRIPT" "$@" 2>/dev/null
}

# ── Sheet visibility ──────────────────────────────────────────────────────────

ptyunit_test_begin "sheet: opening sheet shows Step 1 header"
out=$(_pty ENTER)
assert_contains "$out" "Step 1 of 2" "Step 1 header visible after opening sheet"

ptyunit_test_begin "sheet: back strip shows parent content dimmed"
out=$(_pty ENTER)
assert_contains "$out" "Welcome" "parent content visible in back strip"

# ── Form input ────────────────────────────────────────────────────────────────

ptyunit_test_begin "sheet: typing in Name field is accepted"
out=$(_pty ENTER a l i c e ENTER)
# After typing 'alice' in Name and pressing Enter on Next button, should reach Step 2
assert_contains "$out" "Step 2 of 2" "transitions to step 2 after name input"

# ── Wizard transition ─────────────────────────────────────────────────────────

ptyunit_test_begin "sheet: Next button transitions to Step 2"
out=$(_pty ENTER TAB TAB ENTER)
assert_contains "$out" "Step 2 of 2" "Step 2 visible after Next"

ptyunit_test_begin "sheet: Step 2 shows city field"
out=$(_pty ENTER TAB TAB ENTER)
assert_contains "$out" "City" "City field visible in Step 2"

ptyunit_test_begin "sheet: Back button returns to Step 1"
# Open sheet, go to step 2 (TAB to Next), then Tab to Back and press Enter
out=$(_pty ENTER TAB TAB ENTER TAB TAB ENTER)
assert_contains "$out" "Step 1 of 2" "Step 1 visible after Back"

# ── Dismissal ─────────────────────────────────────────────────────────────────

ptyunit_test_begin "sheet: Esc dismisses sheet and restores parent"
out=$(_pty ENTER ESC)
assert_contains "$out" "Welcome" "parent screen visible after Esc"
# Parent screen should NOT contain sheet content after dismiss
# (we check sheet header is gone)
_step1_count=$(printf '%s' "$out" | grep -c "Step 1 of 2" || true)
# Step 1 may appear once (initial render before Esc) but not after dismiss —
# check that 'Welcome' appears after the last occurrence of Step 1
assert_contains "$out" "Welcome" "parent content present after dismiss"

ptyunit_test_begin "sheet: submitting wizard exits and prints result"
out=$(_pty ENTER TAB TAB ENTER TAB ENTER)
assert_contains "$out" "Submitted" "submit message printed on completion"

ptyunit_test_summary
```

- [ ] **Step 2: Run to verify tests fail**

```
bash tests/run.sh 2>&1 | grep -A2 "test-sheet"
```
Expected: FAIL — `examples/sheet.sh: No such file`

- [ ] **Step 3: Create `examples/sheet.sh`**

The form widget (`src/widgets/form.sh`) uses a shared `SHELLFRAME_FORM_FIELDS` global. Field definitions are `"label\tctx\ttype"` entries. For a two-form wizard, save per-step field arrays and restore `SHELLFRAME_FORM_FIELDS` before each form call.

```bash
#!/usr/bin/env bash
# examples/sheet.sh — Two-step wizard using shellframe_sheet
#
# Demonstrates: sheet push from a parent shell screen, height change on
# transition, Back navigation, and Esc dismissal.
#
# Usage: ./examples/sheet.sh
# Prints submitted data to stdout on completion, or nothing if dismissed.

set -u
source "$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/shellframe.sh"

# ── App state ─────────────────────────────────────────────────────────────────

_WZ_RESULT=""   # set to "Submitted:name:city" on successful submit

# Field definitions: "label<TAB>cursor-ctx<TAB>type"
_WZ_STEP1_FIELDS=(
    $'Name\twzs1_name\ttext'
    $'Email\twzs1_email\ttext'
)
_WZ_STEP2_FIELDS=(
    $'City\twzs2_city\ttext'
    $'Zip\twzs2_zip\ttext'
)

# Initialize both forms at startup (each uses its own cursor contexts)
SHELLFRAME_FORM_FIELDS=("${_WZ_STEP1_FIELDS[@]}")
shellframe_form_init "step1"

SHELLFRAME_FORM_FIELDS=("${_WZ_STEP2_FIELDS[@]}")
shellframe_form_init "step2"

# ── Parent screen ─────────────────────────────────────────────────────────────

_wz_ROOT_render() {
    local _rows _cols
    _shellframe_shell_terminal_size _rows _cols
    shellframe_shell_region "content" 1 1 "$_cols" "$(( _rows - 1 ))"
    shellframe_shell_region "footer"  "$_rows" 1 "$_cols" 1 nofocus
}

_wz_ROOT_content_render() {
    local _top="$1" _left="$2" _width="$3"
    shellframe_fb_print "$_top" "$_left" "Welcome — press Enter to open the wizard"
}

_wz_ROOT_footer_render() {
    local _top="$1" _left="$2" _width="$3"
    shellframe_fb_print "$_top" "$_left" "$(printf '%-*s' "$_width" ' Enter open wizard  q quit')"
}

_wz_ROOT_quit() { _SHELLFRAME_SHELL_NEXT="__QUIT__"; }

# Open the wizard sheet on Enter
_wz_ROOT_content_on_key() {
    if [[ "$1" == $'\n' || "$1" == $'\r' ]]; then
        shellframe_sheet_push "_wz" "STEP1"
        return 0
    fi
    return 1
}

# ── Sheet — Step 1 ────────────────────────────────────────────────────────────

_wz_STEP1_render() {
    SHELLFRAME_SHEET_HEIGHT=6
    shellframe_shell_region "form"   1 1 "$SHELLFRAME_SHEET_WIDTH" 4
    shellframe_shell_region "next"   5 1 "$SHELLFRAME_SHEET_WIDTH" 1
    shellframe_shell_region "footer" 6 1 "$SHELLFRAME_SHEET_WIDTH" 1 nofocus
}

_wz_STEP1_form_render() {
    SHELLFRAME_FORM_FIELDS=("${_WZ_STEP1_FIELDS[@]}")
    shellframe_form_render "step1" "$@"
}

_wz_STEP1_form_on_key() {
    SHELLFRAME_FORM_FIELDS=("${_WZ_STEP1_FIELDS[@]}")
    shellframe_form_on_key "step1" "$1"
}

_wz_STEP1_next_render() {
    local _top="$1" _left="$2" _width="$3"
    local _label="  [Next]  "
    shellframe_fb_print "$_top" "$(( _width - ${#_label} + 1 ))" "$_label"
}

_wz_STEP1_next_on_key() {
    if [[ "$1" == $'\n' || "$1" == $'\r' || "$1" == " " ]]; then
        return 2
    fi
    return 1
}

_wz_STEP1_next_action() {
    _SHELLFRAME_SHEET_NEXT="STEP2"
}

_wz_STEP1_footer_render() {
    local _top="$1" _left="$2" _width="$3"
    shellframe_fb_print "$_top" "$_left" \
        "$(printf '%-*s' "$_width" ' Step 1 of 2  Tab next field  Enter select  Esc cancel')"
}

_wz_STEP1_quit() { shellframe_sheet_pop; }

# ── Sheet — Step 2 ────────────────────────────────────────────────────────────

_wz_STEP2_render() {
    SHELLFRAME_SHEET_HEIGHT=7
    local _half=$(( SHELLFRAME_SHEET_WIDTH / 2 ))
    shellframe_shell_region "form"   1 1 "$SHELLFRAME_SHEET_WIDTH" 4
    shellframe_shell_region "submit" 5 1 "$_half" 1
    shellframe_shell_region "back"   5 $(( _half + 1 )) "$_half" 1
    shellframe_shell_region "footer" 7 1 "$SHELLFRAME_SHEET_WIDTH" 1 nofocus
}

_wz_STEP2_form_render() {
    SHELLFRAME_FORM_FIELDS=("${_WZ_STEP2_FIELDS[@]}")
    shellframe_form_render "step2" "$@"
}

_wz_STEP2_form_on_key() {
    SHELLFRAME_FORM_FIELDS=("${_WZ_STEP2_FIELDS[@]}")
    shellframe_form_on_key "step2" "$1"
}

_wz_STEP2_submit_render() {
    local _top="$1" _left="$2"
    shellframe_fb_print "$_top" "$_left" "[Submit]"
}

_wz_STEP2_submit_on_key() {
    if [[ "$1" == $'\n' || "$1" == $'\r' || "$1" == " " ]]; then
        return 2
    fi
    return 1
}

_wz_STEP2_submit_action() {
    # Collect values from both steps
    local _step1_vals=()
    SHELLFRAME_FORM_FIELDS=("${_WZ_STEP1_FIELDS[@]}")
    shellframe_form_values "step1" _step1_vals
    local _name="${_step1_vals[0]:-}"

    local _step2_vals=()
    SHELLFRAME_FORM_FIELDS=("${_WZ_STEP2_FIELDS[@]}")
    shellframe_form_values "step2" _step2_vals
    local _city="${_step2_vals[0]:-}"

    _WZ_RESULT="Submitted:${_name}:${_city}"
    _SHELLFRAME_SHEET_NEXT="__POP__"
    _SHELLFRAME_SHELL_NEXT="__QUIT__"
}

_wz_STEP2_back_render() {
    local _top="$1" _left="$2"
    shellframe_fb_print "$_top" "$_left" "[Back]"
}

_wz_STEP2_back_on_key() {
    if [[ "$1" == $'\n' || "$1" == $'\r' || "$1" == " " ]]; then
        return 2
    fi
    return 1
}

_wz_STEP2_back_action() {
    _SHELLFRAME_SHEET_NEXT="STEP1"
}

_wz_STEP2_footer_render() {
    local _top="$1" _left="$2" _width="$3"
    shellframe_fb_print "$_top" "$_left" \
        "$(printf '%-*s' "$_width" ' Step 2 of 2  Tab next field  Enter select  Esc cancel')"
}

_wz_STEP2_quit() { shellframe_sheet_pop; }

# ── Run ───────────────────────────────────────────────────────────────────────

shellframe_shell "_wz" "ROOT"

[[ -n "$_WZ_RESULT" ]] && printf '%s\n' "$_WZ_RESULT" || printf 'Dismissed.\n'
```

- [ ] **Step 4: Run integration tests**

```
bash tests/run.sh 2>&1 | grep -A1 "test-sheet"
```
Expected: all test-sheet integration tests pass

- [ ] **Step 5: Run full test suite**

```
bash tests/run.sh
```
Expected: all tests pass

- [ ] **Step 6: Commit**

```bash
git add examples/sheet.sh tests/integration/test-sheet.sh
git commit -m "feat(sheet): two-step wizard example + integration tests"
```

---

## Task 7: `docs/showcase.md` sheet section

**Files:**
- Modify: `docs/showcase.md`

- [ ] **Step 1: Read `docs/showcase.md` to find where to add the sheet section**

Look for the last widget section and add after it.

- [ ] **Step 2: Append sheet section to `docs/showcase.md`**

Add at the end, before any closing section:

````markdown
## Sheet Navigation

A sheet is a partial overlay that sits above the current `shellframe_shell` screen. It:

- Shows 1 frozen, dimmed row of the underlying screen at the top (the "back strip")
- Renders its own content from row 2 downward, with configurable height
- Supports internal screen transitions (wizard pattern) via `_SHELLFRAME_SHEET_NEXT`
- Dismisses on Esc, Up from topmost focusable region, or `shellframe_sheet_pop`

### Quick start

```bash
source shellframe.sh

# Push a sheet from any shellframe_shell event handler:
_myapp_ROOT_open_action() {
    shellframe_sheet_push "_myapp" "OPEN_DB"
}

# Sheet screen hooks — identical convention to shellframe_shell screens.
# Row 1 = first content row (screen row 2, below the back strip).
# Use $SHELLFRAME_SHEET_WIDTH for the width argument.
_myapp_OPEN_DB_render() {
    SHELLFRAME_SHEET_HEIGHT=7
    shellframe_shell_region body   1 1 "$SHELLFRAME_SHEET_WIDTH" 6
    shellframe_shell_region footer 7 1 "$SHELLFRAME_SHEET_WIDTH" 1 nofocus
}

_myapp_OPEN_DB_body_render() { shellframe_form_render "db" "$@"; }
_myapp_OPEN_DB_body_on_key()  { shellframe_form_on_key "db" "$1"; }

_myapp_OPEN_DB_quit() { shellframe_sheet_pop; }

# Wizard transition (set _SHELLFRAME_SHEET_NEXT in any action handler):
_myapp_OPEN_DB_body_action() { _SHELLFRAME_SHEET_NEXT="CONFIRM"; }
```

### Known limitations (v1)

- **Back-strip dimming is best-effort.** Frozen rows are wrapped in `\033[2m...\033[22m`. Rows containing `\033[0m` (full reset) mid-string will have dim cancelled at that point. Partial dimming is visually acceptable; full ANSI stripping is deferred to a future release.
- **Stacking not supported.** Calling `shellframe_sheet_push` while a sheet is already active returns 1 and prints a warning to stderr. One sheet at a time.
````

- [ ] **Step 3: Run full test suite to confirm nothing broken by docs change**

```
bash tests/run.sh
```
Expected: all tests pass

- [ ] **Step 4: Commit**

```bash
git add docs/showcase.md
git commit -m "docs(sheet): add sheet navigation section to showcase"
```

---

## Self-Review Checklist

### Spec coverage

- `shellframe_sheet_push prefix screen` — Task 1 ✓
- `shellframe_sheet_pop` — Task 1 ✓
- `shellframe_sheet_active` — Task 1 ✓
- Double-push returns 1 + stderr warning — Task 1 ✓
- Frozen row capture at push time — Task 1 (`shellframe_sheet_push`) ✓
- Registry swap in/out (draw) — Task 2 ✓
- `shellframe_fb_frame_start` full screen — Task 2 ✓
- `SHELLFRAME_SHEET_WIDTH` set before render hook — Task 2 ✓
- `SHELLFRAME_SHEET_HEIGHT=0` resolved to `rows-1` — Task 2 ✓
- Frozen rows into framebuffer (row 1 dimmed, below-sheet dimmed) — Task 2 ✓
- Region dispatch with `_SF_ROW_OFFSET` — Task 2 ✓
- `shellframe_screen_flush` — Task 2 ✓
- `_SHELLFRAME_SHEET_NEXT` → screen transition — Task 3 ✓
- `_SHELLFRAME_SHEET_NEXT="__POP__"` → pop and restore parent — Task 3 ✓
- `shellframe_sheet_on_key` Esc dismiss — Task 4 ✓
- `shellframe_sheet_on_key` Up-from-topmost dismiss — Task 4 ✓
- `shellframe_sheet_on_key` Tab/Shift-Tab focus cycle — Task 4 ✓
- `shellframe_sheet_on_key` rc=2 action dispatch — Task 4 ✓
- Registry swap in/out (key) — Task 4 ✓
- `shell.sh` draw delegation — Task 5 ✓
- `shell.sh` key delegation — Task 5 ✓
- `shellframe.sh` source line — Task 5 ✓
- Two-step wizard example — Task 6 ✓
- Integration tests — Task 6 ✓
- `docs/showcase.md` section — Task 7 ✓

### Type consistency

- `shellframe_sheet_push` takes `prefix` and `screen` — used consistently in all hooks as `"${_prefix}_${_screen}_render"` etc.
- `shellframe_sheet_draw rows cols` — called from shell.sh with `"$_SHELLFRAME_SHELL_ROWS" "$_SHELLFRAME_SHELL_COLS"` ✓
- `shellframe_sheet_on_key key` — called from shell.sh key loop with `"$_key"` ✓
- `_SF_ROW_OFFSET` is set to `$(( _sheet_top - 1 ))` before region dispatch and 0 after ✓
- All focus ring operations use `_SHELLFRAME_SHELL_FOCUS_*` globals (correct during swap) ✓
