#!/usr/bin/env bash
# shellframe/src/widgets/menu-bar.sh — Horizontal menu bar widget (v2 composable)
#
# COMPATIBILITY: bash 3.2+ (macOS default).
# REQUIRES: src/clip.sh, src/selection.sh, src/panel.sh, src/draw.sh, src/input.sh
#
# ── Overview ──────────────────────────────────────────────────────────────────
#
# Renders a one-row menu bar with dropdown panels and one level of submenu
# nesting. State machine: idle → bar → dropdown → submenu.
#
# ── Data model ────────────────────────────────────────────────────────────────
#
#   SHELLFRAME_MENU_NAMES=("File" "Edit" "View")
#   SHELLFRAME_MENU_FILE=("Open" "Save" "---" "@RECENT:Recent Files" "---" "Quit")
#   SHELLFRAME_MENU_RECENT=("demo.db" "work.db")   # submenu via @VARNAME sigil
#
#   Item types:
#     plain string       — selectable leaf item
#     "---"              — separator (drawn as rule, never reachable by cursor)
#     "@VARNAME:Label"   — submenu item; Right/Enter opens SHELLFRAME_MENU_VARNAME
#
# ── Input globals ─────────────────────────────────────────────────────────────
#
#   SHELLFRAME_MENU_NAMES[@]         — top-level label order (caller sets)
#   SHELLFRAME_MENUBAR_CTX           — context name (default: "menubar")
#   SHELLFRAME_MENUBAR_FOCUSED       — 0 | 1
#   SHELLFRAME_MENUBAR_FOCUSABLE     — 1 (default) | 0
#   SHELLFRAME_MENUBAR_ACTIVE_COLOR  — ANSI escape for double-border color
#                                      (default: SHELLFRAME_BOLD)
#
# ── Output globals ────────────────────────────────────────────────────────────
#
#   SHELLFRAME_MENUBAR_RESULT  — set on return 2:
#                                "Menu|Item" or "Menu|Item|Sub" on selection
#                                "" (empty) on Esc dismiss
#
# ── Public API ────────────────────────────────────────────────────────────────
#
#   shellframe_menubar_init [ctx]
#     Initialise selection contexts. Call once after SHELLFRAME_MENU_NAMES is set.
#
#   shellframe_menubar_render top left width height
#     Draw bar row + open overlay panels. Output to fd 3.
#
#   shellframe_menubar_on_key key
#     Drive state machine. Returns 0 (handled), 1 (unrecognised), 2 (done).
#
#   shellframe_menubar_on_focus focused
#     1 → BAR state. 0 → IDLE (collapses open panels on next render).
#
#   shellframe_menubar_size
#     Print "1 1 0 1". Bar is always 1 row; overlays are absolute-positioned.
#
#   shellframe_menubar_open name
#     Focus bar and open named menu (hotkey seam). Returns 1 if name not found.

SHELLFRAME_MENU_NAMES=()
SHELLFRAME_MENUBAR_CTX="menubar"
SHELLFRAME_MENUBAR_FOCUSED=0
SHELLFRAME_MENUBAR_FOCUSABLE=1
SHELLFRAME_MENUBAR_ACTIVE_COLOR=""
SHELLFRAME_MENUBAR_RESULT=""

shellframe_menubar_init()   { true; }
shellframe_menubar_render() { true; }
shellframe_menubar_on_key() { return 1; }
shellframe_menubar_on_focus() { SHELLFRAME_MENUBAR_FOCUSED="${1:-0}"; }
shellframe_menubar_size()   { printf '%d %d %d %d' 1 1 0 1; }
shellframe_menubar_open()   { return 1; }
