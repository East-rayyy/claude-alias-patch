#!/usr/bin/env bash
# Claude Alias Patch — Linux installer
# Adds custom model alias support to Claude Code.
#
# Apply:  curl -fsSL https://raw.githubusercontent.com/East-rayyy/claude-alias-patch/main/linux-apply.sh | bash
# Remove: curl -fsSL https://raw.githubusercontent.com/East-rayyy/claude-alias-patch/main/linux-remove.sh | bash
#
set -euo pipefail

REPO_BASE="https://raw.githubusercontent.com/East-rayyy/claude-alias-patch/main"
CACHE_DIR="$HOME/.cache/claude-alias-patch"
BIN_DIR="$HOME/.local/bin"
BIN_PATH="$BIN_DIR/claude"
BACKUP_PATH="$BIN_DIR/claude.bak"

echo ""
echo "  Claude Alias Patch — Installer"
echo "  github.com/East-rayyy/claude-alias-patch"
echo ""

# --- Prerequisites ---
check_prereq() {
    if ! command -v "$1" &>/dev/null; then
        echo "ERROR: $1 is required. Install it first." >&2
        exit 1
    fi
}

check_prereq node
check_prereq npm
check_prereq python3
check_prereq curl

NODE_MAJOR=$(node -e "process.stdout.write(String(process.versions.node.split('.')[0]))")
if [[ "$NODE_MAJOR" -lt 18 ]]; then
    echo "ERROR: Node.js >= 18 required (found $(node --version))" >&2
    exit 1
fi

echo "  Prerequisites: node $(node --version), npm $(npm --version), python3"

# --- Safety: ensure cache dir is not a symlink ---
if [[ -L "$CACHE_DIR" ]]; then
    echo "ERROR: $CACHE_DIR is a symlink — refusing to continue" >&2
    exit 1
fi

# --- Download patcher ---
mkdir -p "$CACHE_DIR"

if ! curl -fsSL "$REPO_BASE/lib/patcher.py" -o "$CACHE_DIR/patch.py"; then
    echo "ERROR: Failed to download patcher" >&2
    exit 1
fi

echo "  Patcher downloaded to $CACHE_DIR/patch.py"

# --- Fetch Claude Code from npm ---
echo ""
echo "  Fetching @anthropic-ai/claude-code from npm..."

WORK_DIR=$(mktemp -d)
cleanup_work_dir() { rm -rf "$WORK_DIR"; }
trap cleanup_work_dir EXIT

if ! npm pack @anthropic-ai/claude-code@latest --pack-destination "$WORK_DIR" >/dev/null 2>&1; then
    echo "ERROR: Failed to fetch @anthropic-ai/claude-code from npm" >&2
    exit 1
fi

TGZ=$(ls "$WORK_DIR"/*.tgz 2>/dev/null | head -1)
if [[ -z "$TGZ" ]]; then
    echo "ERROR: npm pack produced no output" >&2
    exit 1
fi

tar -xzf "$TGZ" -C "$CACHE_DIR" --strip-components=1

VERSION=$(head -5 "$CACHE_DIR/cli.js" | grep -oP '// Version: \K[\d.]+' || echo "unknown")
echo "  Extracted v$VERSION"

# --- Patch ---
echo ""
echo "  Patching cli.js..."
if ! python3 "$CACHE_DIR/patch.py" "$CACHE_DIR/cli.js" "$CACHE_DIR/cli.js"; then
    echo ""
    echo "ERROR: Patching failed." >&2
    exit 1
fi

echo "$VERSION" > "$CACHE_DIR/.version"

# --- Detect existing installation ---
detect_claude_install() {
    local claude_path
    claude_path=$(command -v claude 2>/dev/null) || { echo "none"; return; }

    # Already our wrapper
    if grep -q 'claude-alias-patch' "$claude_path" 2>/dev/null; then
        echo "wrapper"; return
    fi

    # Resolve symlinks to check the real binary
    local resolved
    resolved=$(readlink -f "$claude_path" 2>/dev/null) || resolved="$claude_path"

    # ELF or Mach-O binary
    if file "$resolved" 2>/dev/null | grep -qE 'ELF|Mach-O'; then
        if [[ "$resolved" == *"/.local/share/claude/versions/"* ]]; then
            echo "native"
        else
            echo "package-manager"
        fi
        return
    fi

    # npm global — symlink to cli.js
    if [[ "$resolved" == *"/node_modules/@anthropic-ai/claude-code/cli.js" ]]; then
        echo "npm-global"; return
    fi

    # npm local install
    if [[ "$resolved" == *"/.claude/local/"* ]]; then
        echo "npm-local"; return
    fi

    echo "unknown"
}

echo ""
INSTALL_TYPE=$(detect_claude_install)
CLAUDE_PATH=$(command -v claude 2>/dev/null || echo "")

case "$INSTALL_TYPE" in
    wrapper)
        echo "  Detected: existing wrapper (upgrading)"
        ;;
    native)
        RESOLVED=$(readlink -f "$CLAUDE_PATH" 2>/dev/null || echo "$CLAUDE_PATH")
        echo "  Detected: native binary ($RESOLVED)"
        echo ""
        echo "  Native binaries embed cli.js — they cannot be patched directly."
        echo "  The wrapper runs a patched copy from npm via node instead."
        echo "  Your native binary will be backed up to $BACKUP_PATH"
        ;;
    package-manager)
        RESOLVED=$(readlink -f "$CLAUDE_PATH" 2>/dev/null || echo "$CLAUDE_PATH")
        echo "  Detected: package-manager binary ($RESOLVED)"
        echo ""
        echo "  Package-manager binaries cannot be patched directly."
        echo "  The wrapper runs a patched copy from npm via node instead."
        echo "  Your binary will be backed up to $BACKUP_PATH"
        ;;
    npm-global|npm-local)
        echo "  Detected: npm installation ($CLAUDE_PATH)"
        ;;
    none)
        echo "  No existing Claude Code installation found"
        ;;
    unknown)
        echo "  Detected: unknown installation type ($CLAUDE_PATH)"
        echo "  The wrapper will be installed alongside it."
        ;;
esac

# --- Install wrapper ---
echo ""
echo "  Installing wrapper..."
mkdir -p "$BIN_DIR"

# Download wrapper script
if ! curl -fsSL "$REPO_BASE/lib/wrapper.sh" -o "$CACHE_DIR/claude-wrapper.sh"; then
    echo "ERROR: Failed to download wrapper script" >&2
    exit 1
fi
chmod +x "$CACHE_DIR/claude-wrapper.sh"

# Backup existing claude binary/symlink (only if not already our wrapper)
if [[ -e "$BIN_PATH" ]]; then
    if grep -q 'claude-alias-patch' "$BIN_PATH" 2>/dev/null; then
        echo "  Existing wrapper detected — overwriting"
    else
        if [[ ! -e "$BACKUP_PATH" ]]; then
            cp -a "$BIN_PATH" "$BACKUP_PATH"
            echo "  Backed up original to $BACKUP_PATH"
        else
            echo "  Backup already exists at $BACKUP_PATH"
        fi
    fi
fi

# Remove before copy — handles "Text file busy" when ELF binary is running
rm -f "$BIN_PATH" 2>/dev/null || true
cp "$CACHE_DIR/claude-wrapper.sh" "$BIN_PATH"
chmod +x "$BIN_PATH"

# Verify PATH
RESOLVED=$(command -v claude 2>/dev/null || echo "")
if [[ "$RESOLVED" != "$BIN_PATH" && -n "$RESOLVED" ]]; then
    echo ""
    echo "  WARNING: 'claude' resolves to $RESOLVED instead of $BIN_PATH"
    echo "  Add to your shell profile: export PATH=\"$BIN_DIR:\$PATH\""
fi

echo ""
echo "  Done!"
echo ""
echo "  Version:   $VERSION (patched)"
echo "  Wrapper:   $BIN_PATH"
echo "  Cache:     $CACHE_DIR"
echo ""
echo "  Next: Add custom models to ~/.claude/settings.json:"
echo ""
echo '    {'
echo '      "env": {'
echo '        "ANTHROPIC_DEFAULT_GEMINI_MODEL": "google/gemini-2.5-pro",'
echo '        "ANTHROPIC_DEFAULT_GPT_MODEL": "openai/gpt-4o"'
echo '      }'
echo '    }'
echo ""
echo "  Then restart Claude Code. Your custom aliases will appear automatically."
echo "  Update: claude update"
echo "  Remove: curl -fsSL $REPO_BASE/linux-remove.sh | bash"
