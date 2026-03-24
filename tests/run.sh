#!/usr/bin/env bash
# tests/run.sh — ptyunit runner wrapper
#
# Locates the ptyunit installation and delegates to its run.sh.
# PTYUNIT_HOME may be set explicitly; otherwise resolved from Homebrew.
#
# Usage: bash tests/run.sh [--unit | --integration | --all] [--jobs N] ...

set -u

if [[ -z "${PTYUNIT_HOME:-}" ]]; then
    # Check for sibling ptyunit checkout (used in CI and local fissible workspace)
    _sibling="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)/ptyunit"
    if [[ -f "$_sibling/run.sh" ]]; then
        PTYUNIT_HOME="$_sibling"
    elif _prefix=$(brew --prefix ptyunit 2>/dev/null); then
        PTYUNIT_HOME="$_prefix/libexec"
    else
        printf 'error: ptyunit not found. Run: bash bootstrap.sh\n' >&2
        exit 1
    fi
fi

if [[ ! -f "$PTYUNIT_HOME/run.sh" ]]; then
    printf 'error: ptyunit not found at %s\n' "$PTYUNIT_HOME" >&2
    printf 'Run: bash bootstrap.sh\n' >&2
    exit 1
fi

export PTYUNIT_HOME
exec bash "$PTYUNIT_HOME/run.sh" "$@"
