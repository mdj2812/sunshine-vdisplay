#!/usr/bin/env bash
# Backward-compatible wrapper for the full installer.
exec "$(dirname "$0")/install.sh" "$@"
