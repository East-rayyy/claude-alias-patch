#!/usr/bin/env bash
# Claude Alias Patch — Wrapper script
# Intercepts `claude` commands, ensures cli.js is patched, handles updates.
# https://github.com/East-rayyy/claude-alias-patch
set -euo pipefail

REPO_BASE="https://raw.githubusercontent.com/East-rayyy/claude-alias-patch/main"
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

    # Step 1: Update patcher from repo
    if curl -fsSL "$REPO_BASE/lib/patcher.py" -o "$CACHE_DIR/patch.py.new"; then
        mv "$CACHE_DIR/patch.py.new" "$PATCHER"
        echo "  Patcher updated"
    else
        rm -f "$CACHE_DIR/patch.py.new" 2>/dev/null || true
        echo "  Could not fetch latest patcher — using cached copy" >&2
    fi

    # Step 2: Update wrapper from repo
    if curl -fsSL "$REPO_BASE/lib/wrapper.sh" -o "$CACHE_DIR/claude-wrapper.sh"; then
        chmod +x "$CACHE_DIR/claude-wrapper.sh"
        # Self-update: overwrite the running wrapper binary if changed
        BIN_PATH=$(command -v claude 2>/dev/null || echo "$HOME/.local/bin/claude")
        if [[ -f "$BIN_PATH" ]] && ! cmp -s "$CACHE_DIR/claude-wrapper.sh" "$BIN_PATH"; then
            cp "$CACHE_DIR/claude-wrapper.sh" "$BIN_PATH"
            chmod +x "$BIN_PATH"
            echo "  Wrapper updated"
        fi
    else
        echo "  Could not fetch latest wrapper — skipping self-update" >&2
    fi

    # Step 3: Fetch Claude Code from npm
    WORK_DIR=$(mktemp -d)
    cleanup_work_dir() { rm -rf "$WORK_DIR"; }
    trap cleanup_work_dir EXIT

    if ! npm pack "@anthropic-ai/claude-code@$CHANNEL" --pack-destination "$WORK_DIR" >/dev/null 2>&1; then
        echo "ERROR: Failed to fetch @anthropic-ai/claude-code@$CHANNEL from npm" >&2
        exit 1
    fi

    TGZ=$(ls "$WORK_DIR"/*.tgz 2>/dev/null | head -1)
    if [[ -z "$TGZ" ]]; then
        echo "ERROR: npm pack produced no output" >&2
        exit 1
    fi

    tar -xzf "$TGZ" -C "$CACHE_DIR" --strip-components=1

    NEW_VER=$(head -5 "$CLI_JS" | grep -oP '// Version: \K[\d.]+' || echo "unknown")

    # Step 4: Patch
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
    echo "Run the installer: curl -fsSL $REPO_BASE/linux-apply.sh | bash" >&2
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

# Strip parent session env vars to prevent interference when running
# claude from within an existing Claude Code session
unset CLAUDECODE 2>/dev/null || true
unset CLAUDE_CODE_ENTRYPOINT 2>/dev/null || true
unset CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS 2>/dev/null || true

exec node "$CLI_JS" "$@"
