#!/usr/bin/env bash
# examples/screen-test.sh — Screen enter/exit/raw roundtrip fixture
#
# Exercises shellframe_screen_enter, shellframe_cursor_hide, shellframe_raw_enter,
# shellframe_raw_save, shellframe_raw_exit, shellframe_cursor_show, and
# shellframe_screen_exit in sequence. Prints "screen-test-done" to stdout on
# clean exit.
#
# Used by tests/integration/test-screen.sh.

set -u
SHELLFRAME_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$SHELLFRAME_DIR/shellframe.sh"

exec 3>/dev/tty
shellframe_screen_enter
shellframe_cursor_hide
shellframe_raw_enter
printf '\033[1;1HScreen entered\n' >&3
saved=$(shellframe_raw_save)
shellframe_raw_exit "$saved"
shellframe_cursor_show
shellframe_screen_exit
printf 'screen-test-done\n'
