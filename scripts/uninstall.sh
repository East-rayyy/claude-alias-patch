#!/usr/bin/env bash
# Claude Alias Patch — Uninstaller
# Removes wrapper and cache, restores original claude binary.
set -euo pipefail

BIN_DIR="$HOME/.local/bin"
BIN_PATH="$BIN_DIR/claude"
BACKUP_PATH="$BIN_DIR/claude.bak"
CACHE_DIR="$HOME/.cache/claude-alias-patch"

echo ""
echo "  Claude Alias Patch — Uninstaller"
echo ""

# Restore backup
if [[ -e "$BACKUP_PATH" ]]; then
    rm -f "$BIN_PATH" 2>/dev/null || true
    mv "$BACKUP_PATH" "$BIN_PATH"
    echo "  Restored original: $BIN_PATH"
elif [[ -e "$BIN_PATH" ]] && grep -q 'claude-alias-patch' "$BIN_PATH" 2>/dev/null; then
    rm "$BIN_PATH"
    echo "  Removed wrapper: $BIN_PATH"
    echo "  No backup found. Reinstall Claude Code:"
    echo "    npm i -g @anthropic-ai/claude-code"
else
    echo "  No wrapper found at $BIN_PATH"
fi

# Remove cache
if [[ -d "$CACHE_DIR" ]]; then
    rm -rf "$CACHE_DIR"
    echo "  Removed cache: $CACHE_DIR"
else
    echo "  No cache found at $CACHE_DIR"
fi

echo ""
echo "  Uninstall complete."
