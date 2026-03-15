#!/usr/bin/env bash
# examples/confirm.sh — Demo for shellframe_confirm modal widget

set -u
SHELLFRAME_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$SHELLFRAME_DIR/shellframe.sh"

shellframe_confirm "Delete 3 files permanently?" \
    "  config.json        delete" \
    "  cache/data.db      delete" \
    "  tmp/session.lock   delete"

if (( $? == 0 )); then
    printf "Confirmed: deleting files.\n"
else
    printf "Cancelled.\n"
fi
