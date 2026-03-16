#!/usr/bin/env bash
# Claude Alias Patch — Wrapper script
# Intercepts `claude` commands, ensures cli.js is patched, handles updates.
# https://github.com/East-rayyy/claude-alias-patch
set -euo pipefail

CACHE_DIR="$HOME/.cache/claude-alias-patch"
CLI_JS="$CACHE_DIR/cli.js"
PATCHER="$CACHE_DIR/patch.py"
VERSION_FILE="$CACHE_DIR/.version"
LOCK_FILE="$CACHE_DIR/.update.lock"

# Safety: refuse to run if cache dir is a symlink
if [[ -L "$CACHE_DIR" ]]; then
    echo "Claude Alias Patch: $CACHE_DIR is a symlink — refusing to run" >&2
    exit 1
fi

# --- Update handler ---
if [[ "${1:-}" == "update" && $# -le 2 ]]; then
    CURRENT_VER="unknown"
    [[ -f "$VERSION_FILE" ]] && CURRENT_VER=$(cat "$VERSION_FILE")

    CHANNEL="${2:-latest}"
    echo "Claude Alias Patch: Checking for updates (channel: $CHANNEL)..."

    # Acquire exclusive lock to prevent concurrent updates
    mkdir -p "$CACHE_DIR"
    exec 9>"$LOCK_FILE"
    if ! flock -n 9; then
        echo "Another update is already in progress" >&2
        exit 1
    fi

    TMPDIR=$(mktemp -d)
    cleanup_tmpdir() { rm -rf "$TMPDIR"; }
    trap cleanup_tmpdir EXIT

    if ! npm pack "@anthropic-ai/claude-code@$CHANNEL" --pack-destination "$TMPDIR" >/dev/null 2>&1; then
        echo "ERROR: Failed to fetch @anthropic-ai/claude-code@$CHANNEL from npm" >&2
        exit 1
    fi

    TGZ=$(ls "$TMPDIR"/*.tgz 2>/dev/null | head -1)
    if [[ -z "$TGZ" ]]; then
        echo "ERROR: npm pack produced no output" >&2
        exit 1
    fi

    tar -xzf "$TGZ" -C "$CACHE_DIR" --strip-components=1

    NEW_VER=$(head -5 "$CLI_JS" | grep -oP '// Version: \K[\d.]+' || echo "unknown")

    if python3 "$PATCHER" "$CLI_JS" "$CLI_JS" 2>&1; then
        echo "$NEW_VER" > "$VERSION_FILE"
        if [[ "$CURRENT_VER" == "$NEW_VER" ]]; then
            echo "Claude Code is up to date ($NEW_VER)"
        else
            echo "Successfully updated from $CURRENT_VER to $NEW_VER"
        fi
    else
        echo "WARNING: Patching failed. Custom model aliases may not work." >&2
        # Don't write version file on patch failure — forces re-patch attempt next run
    fi
    exit 0
fi

# --- Normal run ---
if [[ ! -f "$CLI_JS" ]]; then
    echo "Claude Alias Patch: cli.js not found at $CLI_JS" >&2
    echo "Run the installer: curl -sL https://raw.githubusercontent.com/East-rayyy/claude-alias-patch/main/scripts/install.sh | bash" >&2
    exit 1
fi

# Re-patch if needed (fast — just checks for marker comment)
if ! grep -q 'ccpatch:model-enum' "$CLI_JS" 2>/dev/null; then
    if [[ -f "$PATCHER" ]]; then
        python3 "$PATCHER" "$CLI_JS" "$CLI_JS" >/dev/null 2>&1 || true
    fi
fi

# Prevent Claude from auto-migrating to native binary (would overwrite this wrapper)
export DISABLE_AUTO_MIGRATE_TO_NATIVE=1

exec node "$CLI_JS" "$@"
