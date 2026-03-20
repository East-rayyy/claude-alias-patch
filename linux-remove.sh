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
    # Check if backup symlink target still exists (native binary may have self-updated)
    if [[ -L "$BACKUP_PATH" ]]; then
        BACKUP_TARGET=$(readlink "$BACKUP_PATH")
        if [[ ! -e "$BACKUP_TARGET" ]]; then
            echo "  Backup target no longer exists: $BACKUP_TARGET"
            # Native binary auto-updated and cleaned up old version — find latest
            LATEST=$(ls -t "$HOME/.local/share/claude/versions/" 2>/dev/null | head -1)
            if [[ -n "$LATEST" ]]; then
                rm -f "$BIN_PATH" "$BACKUP_PATH" 2>/dev/null || true
                ln -s "$HOME/.local/share/claude/versions/$LATEST" "$BIN_PATH"
                echo "  Restored to latest native version: $LATEST"
            else
                rm -f "$BIN_PATH" "$BACKUP_PATH" 2>/dev/null || true
                echo "  Removed wrapper. No native binary found."
                echo "  Reinstall Claude Code: https://docs.anthropic.com/en/docs/claude-code/getting-started"
            fi
        else
            rm -f "$BIN_PATH" 2>/dev/null || true
            mv "$BACKUP_PATH" "$BIN_PATH"
            if [[ -L "$BIN_PATH" ]]; then
                echo "  Restored original symlink: $BIN_PATH → $(readlink -f "$BIN_PATH")"
            else
                echo "  Restored original: $BIN_PATH"
            fi
        fi
    else
        # Backup is a regular file — simple restore
        rm -f "$BIN_PATH" 2>/dev/null || true
        mv "$BACKUP_PATH" "$BIN_PATH"
        echo "  Restored original: $BIN_PATH"
    fi
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
