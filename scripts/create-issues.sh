#!/usr/bin/env bash
# shellframe/scripts/create-issues.sh
# Creates GitHub issues for the ShellQL TUI foundation project.
# Run once: bash scripts/create-issues.sh
# After running, update PROJECT.md with the assigned issue numbers.

set -euo pipefail

REPO="fissible/shellframe"

create() {
  local title="$1" body="$2" label="$3"
  gh issue create --repo "$REPO" --title "$title" --body "$body" --label "$label" 2>/dev/null || \
  gh issue create --repo "$REPO" --title "$title" --body "$body"
}

echo "=== Phase 1: Core UI Contracts ==="

create \
  "[P1] Define component contract" \
  "Every shellframe widget needs a predictable interface for render, sizing/layout, focus state, input/event handling, and internal state updates.

**Settle these questions:**
- How does a component know its bounds? How does it respond to terminal resizing?
- How does it report desired/minimum size?
- How is focus passed in and out?
- How are child components composed?

**Deliverable:** A doc (or comment block in shellframe.sh) formalizing the contract. No code required — this is a specification.

**Effort:** S (1–2h)
**Phase:** 1 — Core UI Contracts
**Required by:** all Phase 3 primitives" \
  "phase:1,effort:S" 2>/dev/null || \
gh issue create --repo "$REPO" --title "[P1] Define component contract" --body "Every shellframe widget needs a predictable interface for render, sizing/layout, focus state, input/event handling, and internal state updates.

Settle: how a component knows its bounds, reports desired/minimum size, receives focus, and composes children.

**Deliverable:** Specification doc or comment block.
**Effort:** S (1–2h) | **Phase:** 1"

echo "Phase 1 issue 1 done"

gh issue create --repo "$REPO" \
  --title "[P1] Define layout contract" \
  --body "Create a simple layout system supporting:
- vertical stack
- horizontal stack
- fixed-size regions
- fill/remaining-space regions

Needed for: top bar, sidebar+main pane, footer, modal content.

**Deliverable:** Layout primitive functions in \`src/layout.sh\`.
**Effort:** S (1–2h) | **Phase:** 1 | **Deps:** component contract"

echo "Phase 1 issue 2 done"

gh issue create --repo "$REPO" \
  --title "[P1] Define focus model" \
  --body "Define a single, shared focus system so every widget doesn't invent its own.

Needs:
- focusable vs non-focusable components
- active focus path
- tab / shift-tab traversal
- modal focus trapping
- parent container delegation

**Deliverable:** Focus model in \`src/focus.sh\`.
**Effort:** S (1–2h) | **Phase:** 1"

echo "Phase 1 issue 3 done"

echo ""
echo "=== Phase 2: Shared Behavior Modules ==="

gh issue create --repo "$REPO" \
  --title "[P2] Keyboard input mapping module" \
  --body "Centralize key parsing and action mapping so widgets don't each implement their own.

Must handle: arrows, enter, esc, tab, shift-tab, page up/down, home/end, common shortcuts (/, q, ?).

**Deliverable:** \`src/keyboard.sh\` with a \`shellframe_key_read\` function and named key constants.
**Effort:** M (~half day) | **Phase:** 2"

echo "Phase 2 issue 4 done"

gh issue create --repo "$REPO" \
  --title "[P2] Selection model module" \
  --body "Reusable selection behavior for lists, trees, grids, and tab bars.

Must support: single selection, cursor movement, wrap vs clamp, selected-item tracking.

**Deliverable:** \`src/selection.sh\` with functions consumed by list/tree/grid widgets.
**Effort:** S (1–2h) | **Phase:** 2"

echo "Phase 2 issue 5 done"

gh issue create --repo "$REPO" \
  --title "[P2] Cursor model module" \
  --body "Reusable cursor/edit behavior shared by the input field, text editor, and (later) grid cell navigation.

Must support: insert, delete, move left/right, word jump, home/end, position tracking.

**Deliverable:** \`src/cursor.sh\`.
**Effort:** M (~half day) | **Phase:** 2"

echo "Phase 2 issue 6 done"

gh issue create --repo "$REPO" \
  --title "[P2] Clipping and measurement helpers" \
  --body "Shared helpers used by layout, scroll container, and text rendering:
- visible range calculation
- text width clipping (respects ANSI escape codes)
- padding/border offset math
- viewport coordinate math

**Deliverable:** Functions in \`src/draw.sh\` or a new \`src/measure.sh\`.
**Effort:** S (1–2h) | **Phase:** 2"

echo "Phase 2 issue 7 done"

echo ""
echo "=== Phase 3: Foundation Primitives ==="

gh issue create --repo "$REPO" \
  --title "[P3] Text primitive" \
  --body "Centralize all text rendering rules. This becomes the base for labels, titles, status lines, table cells, and menu items.

Needs:
- plain text rendering to coordinates
- width clipping (ANSI-aware)
- truncation with ellipsis
- optional word wrapping
- alignment: left / center / right
- style support (bold, dim, color via ANSI)

**Deliverable:** \`src/text.sh\` with \`shellframe_text_render\`.
**Effort:** M (~half day) | **Phase:** 3 | **Deps:** P2 clipping helpers"

echo "Phase 3 issue 8 done"

gh issue create --repo "$REPO" \
  --title "[P3] Box/Panel primitive" \
  --body "A bordered container with optional title. Used as the visual frame for most widgets.

Needs:
- border rendering (single/double line, configurable)
- title rendering (left/center/right aligned in top border)
- configurable padding
- clipped inner content area (returns bounds for child rendering)
- focused/unfocused visual state (border color/weight change)

**Deliverable:** \`src/panel.sh\` with \`shellframe_panel_draw\`.
**Effort:** M (~half day) | **Phase:** 3 | **Deps:** P2 clipping, P3 text"

echo "Phase 3 issue 9 done"

gh issue create --repo "$REPO" \
  --title "[P3] Scroll container" \
  --body "A reusable scrollable viewport. Scrolling must NOT be baked into individual widgets.

Needs:
- vertical scrolling
- optional horizontal scrolling
- clipping rendered content to viewport bounds
- scroll offset tracking
- page up/down, home/end
- keep-selected-item-visible behavior (scroll to show cursor)

**Deliverable:** \`src/scroll.sh\` with \`shellframe_scroll_*\` functions.
**Effort:** L (~1 day) | **Phase:** 3 | **Deps:** P2 clipping helpers"

echo "Phase 3 issue 10 done"

gh issue create --repo "$REPO" \
  --title "[P3] Selectable list widget" \
  --body "Simple vertical list with selection. Becomes the basis for menus, recent files, query history, pickers.

Needs:
- item array rendering
- selection state (cursor index)
- keyboard navigation (up/down/enter/esc)
- integration with scroll container (no baked-in scroll logic)
- customizable item renderer callback

**Deliverable:** \`src/widgets/list.sh\` with \`shellframe_list\`.
**Effort:** M (~half day) | **Phase:** 3 | **Deps:** P2 selection model, P3 scroll container"

echo "Phase 3 issue 11 done"

gh issue create --repo "$REPO" \
  --title "[P3] Input field widget" \
  --body "Single-line text entry. Build early; text editor extends this rather than duplicating it.

Needs:
- single-line text buffer
- visible cursor with movement (left/right/home/end/word-jump)
- insert and delete
- placeholder text
- submit (enter) and cancel (esc) hooks
- controlled (caller sets value) or internal state option

**Deliverable:** \`src/widgets/input.sh\` with \`shellframe_input\`.
**Effort:** M (~half day) | **Phase:** 3 | **Deps:** P2 cursor model"

echo "Phase 3 issue 12 done"

gh issue create --repo "$REPO" \
  --title "[P3] Tab bar widget" \
  --body "Simple horizontal tab selector.

Needs:
- tab label array
- active tab index
- overflow indicator when tabs exceed width
- keyboard switching (left/right arrows or number keys)

**Deliverable:** \`src/widgets/tabs.sh\` with \`shellframe_tabs\`.
**Effort:** S (1–2h) | **Phase:** 3 | **Deps:** P1 focus model, P2 selection model"

echo "Phase 3 issue 13 done"

gh issue create --repo "$REPO" \
  --title "[P3] Modal/dialog widget" \
  --body "Reusable overlay container for confirmations, prompts, and alerts.

Needs:
- centered rendering over current screen content
- focus trap while open (no focus leaking to background)
- dismiss (esc) and confirm (enter) action hooks
- optional embedded input field (for prompt-style dialogs)
- configurable size (fixed or content-driven)

**Deliverable:** \`src/widgets/modal.sh\` with \`shellframe_modal\`.
**Effort:** M (~half day) | **Phase:** 3 | **Deps:** P1 focus model, P3 panel"

echo "Phase 3 issue 14 done"

gh issue create --repo "$REPO" \
  --title "[P3] Tree view widget" \
  --body "Generic nested navigation structure for schema browser, file browser, saved query folders.

Needs:
- expandable/collapsible nodes
- selected node tracking
- keyboard navigation (up/down/enter to expand, left to collapse)
- indentation proportional to depth
- optional icons/glyphs per node type

**Deliverable:** \`src/widgets/tree.sh\` with \`shellframe_tree\`.
**Effort:** L (~1 day) | **Phase:** 3 | **Deps:** P2 selection model, P3 scroll container, selectable list"

echo "Phase 3 issue 15 done"

gh issue create --repo "$REPO" \
  --title "[P3] Text editor widget" \
  --body "Multiline extension of the input field. Shares text-editing behavior with input field; must not duplicate cursor logic.

Needs:
- multiline text buffer
- 2D cursor movement (up/down/left/right/home/end/pg)
- vertical scrolling via scroll container
- line break handling
- submit action hook (configurable key, e.g. ctrl+enter)

**Deliverable:** \`src/widgets/editor.sh\` with \`shellframe_editor\`.
**Effort:** L (~1 day) | **Phase:** 3 | **Deps:** P2 cursor model, P3 scroll container, input field"

echo "Phase 3 issue 16 done"

gh issue create --repo "$REPO" \
  --title "[P3] Data grid widget" \
  --body "The most important reusable complex primitive. Used for table rows, query results, index listings, pragma output.

Needs:
- row/column data array
- sticky header row
- horizontal AND vertical scrolling (via scroll container)
- selected row (and optionally selected cell) tracking
- column width strategy: fixed / auto / min-max
- ANSI-aware clipped cell rendering

**Deliverable:** \`src/widgets/grid.sh\` with \`shellframe_grid\`.
**Effort:** XL (2–3 days) | **Phase:** 3 | **Deps:** P2 selection model, clipping helpers, P3 scroll container"

echo "Phase 3 issue 17 done"

echo ""
echo "=== Phase 4: App Shell ==="

gh issue create --repo "$REPO" \
  --title "[P4] Generic app shell" \
  --body "A generic multi-screen application shell, extending shellframe_app. Must be generic enough for future shellframe apps, not just ShellQL.

App shell regions:
- top bar
- left sidebar (optional, togglable)
- main pane
- bottom command/status bar

App shell responsibilities:
- region layout via layout primitives
- focus switching between panes (tab/ctrl-arrows)
- screen/route management
- command dispatch
- global shortcuts (q to quit, ? for help, etc.)
- modal layering

**Deliverable:** Updates to \`src/app.sh\` and a new \`src/shell.sh\` for the multi-pane shell pattern.
**Effort:** L (~1 day) | **Phase:** 4 | **Deps:** P1 contracts, P3 panel, modal"

echo "Phase 4 issue 18 done"

echo ""
echo "All shellframe issues created."
echo "Now update PROJECT.md with the assigned issue numbers."
