#!/usr/bin/env bash
set -euo pipefail

PROGRAM="kof-main-sync"
CONFIG_HOME="${XDG_CONFIG_HOME:-$HOME/.config}"
BIN_PATH="$HOME/.local/bin/$PROGRAM"
CONFIG_DIR="$CONFIG_HOME/$PROGRAM"

if [ -x "$BIN_PATH" ]; then
    "$BIN_PATH" uninstall
fi

if [ -f "$BIN_PATH" ]; then
    rm -f -- "$BIN_PATH"
fi

if [ -f "$CONFIG_DIR/config" ]; then
    rm -f -- "$CONFIG_DIR/config"
fi
if [ -d "$CONFIG_DIR" ]; then
    rmdir "$CONFIG_DIR" 2>/dev/null || true
fi

printf 'Removed the installed command, configuration, and managed cron entry.\n'
printf 'Kof checkouts, distributions, and logs were preserved.\n'
