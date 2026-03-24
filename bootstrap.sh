#!/usr/bin/env bash
# bootstrap.sh — Install fissible consumer dependencies (macOS/Homebrew only)
# In CI, ptyunit is checked out as a sibling directory by the shared workflow.
if ! command -v brew >/dev/null 2>&1; then
    printf 'bootstrap.sh: brew not found, skipping (expected in CI)\n'
    exit 0
fi
brew install fissible/tap/ptyunit 2>/dev/null || brew upgrade fissible/tap/ptyunit
