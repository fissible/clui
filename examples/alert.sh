#!/usr/bin/env bash
# examples/alert.sh — Demo for shellframe_alert informational modal widget

set -u
SHELLFRAME_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.."; pwd)"
source "$SHELLFRAME_DIR/shellframe.sh"

shellframe_alert "Deploy complete" \
    "web-server    restarted" \
    "cache         flushed" \
    "config.json   reloaded"

printf "Alert dismissed.\n"
