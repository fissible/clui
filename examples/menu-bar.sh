#!/usr/bin/env bash
# examples/menu-bar.sh — Demo for shellframe_menubar widget
#
# Shows a 3-menu bar (File/Edit/View) with a "Recent Files" submenu.
# Prints the selected result path on exit, or "Cancelled." on Esc.

set -u
SHELLFRAME_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$SHELLFRAME_DIR/shellframe.sh"

SHELLFRAME_MENU_NAMES=("File" "Edit" "View")
SHELLFRAME_MENU_FILE=("Open" "Save" "---" "@RECENT:Recent Files" "---" "Quit")
SHELLFRAME_MENU_EDIT=("Undo" "Redo" "---" "Cut" "Copy" "Paste")
SHELLFRAME_MENU_VIEW=("Zoom In" "Zoom Out" "---" "Full Screen")
SHELLFRAME_MENU_RECENT=("demo.db" "work.db" "archive.db")

SHELLFRAME_MENUBAR_CTX="demo"
shellframe_menubar_init "demo"
shellframe_menubar_on_focus 1

saved_stty=$(shellframe_raw_save)

_cleanup() {
    shellframe_raw_exit "$saved_stty"
    shellframe_cursor_show
    shellframe_screen_exit
}
trap '_cleanup' EXIT
trap 'exit 1' INT TERM

shellframe_screen_enter
shellframe_raw_enter
shellframe_cursor_hide

# Open fd 3 to /dev/tty for render output
exec 3>/dev/tty

cols=$(tput cols)
rows=$(tput lines)

while true; do
    shellframe_menubar_render 1 1 "$cols" "$rows"
    shellframe_read_key key
    shellframe_menubar_on_key "$key"
    rc=$?
    (( rc == 2 )) && break
done

trap - EXIT INT TERM
_cleanup

exec 3>&-

if [[ -n "$SHELLFRAME_MENUBAR_RESULT" ]]; then
    printf 'Selected: %s\n' "$SHELLFRAME_MENUBAR_RESULT"
else
    printf 'Cancelled.\n'
    exit 1
fi
