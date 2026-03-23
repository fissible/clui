#!/usr/bin/env bash
# tests/run.sh — ptyunit runner wrapper
#
# Locates the ptyunit installation and delegates to its run.sh.
# PTYUNIT_HOME may be set explicitly; otherwise resolved from Homebrew.
#
# Usage: bash tests/run.sh [--unit | --integration | --all] [--jobs N] ...

set -u

if [[ -z "${PTYUNIT_HOME:-}" ]]; then
    _prefix=$(brew --prefix ptyunit 2>/dev/null) || {
        printf 'error: ptyunit not found. Run: bash bootstrap.sh\n' >&2
        exit 1
    }
    PTYUNIT_HOME="$_prefix/libexec"
fi

if [[ ! -f "$PTYUNIT_HOME/run.sh" ]]; then
    printf 'error: ptyunit not found at %s\n' "$PTYUNIT_HOME" >&2
    printf 'Run: bash bootstrap.sh\n' >&2
    exit 1
fi

export PTYUNIT_HOME
exec bash "$PTYUNIT_HOME/run.sh" "$@"
