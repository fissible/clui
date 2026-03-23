#!/usr/bin/env bash
# bootstrap.sh — Install fissible consumer dependencies
brew install fissible/tap/ptyunit 2>/dev/null || brew upgrade fissible/tap/ptyunit
