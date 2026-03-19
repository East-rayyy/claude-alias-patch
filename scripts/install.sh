#!/usr/bin/env bash
# Claude Alias Patch — Single-file installer
# Adds custom model alias support to Claude Code.
#
# Install:  curl -sL https://raw.githubusercontent.com/East-rayyy/claude-alias-patch/main/scripts/install.sh | bash
# Uninstall: curl -sL https://raw.githubusercontent.com/East-rayyy/claude-alias-patch/main/scripts/uninstall.sh | bash
#
set -euo pipefail

CACHE_DIR="$HOME/.cache/claude-alias-patch"
BIN_DIR="$HOME/.local/bin"
BIN_PATH="$BIN_DIR/claude"
BACKUP_PATH="$BIN_DIR/claude.bak"
WRAPPER_URL="https://raw.githubusercontent.com/East-rayyy/claude-alias-patch/main/scripts/claude-wrapper.sh"

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

# --- Write embedded patcher ---
mkdir -p "$CACHE_DIR"

cat > "$CACHE_DIR/patch.py" << 'PATCHER_EOF'
#!/usr/bin/env python3
"""Claude Code Custom Model Alias Patcher

Patches cli.js to dynamically register model aliases from ANTHROPIC_DEFAULT_*_MODEL env vars.
"""
import sys
import re
import os
import tempfile

def main():
    if len(sys.argv) != 3:
        print(f"Usage: {sys.argv[0]} <input-cli.js> <output-cli.js>")
        sys.exit(1)

    input_path, output_path = sys.argv[1], sys.argv[2]

    if not os.path.isfile(input_path):
        print(f"ERROR: Input file not found: {input_path}")
        sys.exit(1)

    with open(input_path, "r", encoding="utf-8") as f:
        content = f.read()

    # Validate
    if "// Version:" not in content[:500]:
        print("ERROR: Input doesn't look like a Claude Code cli.js")
        sys.exit(1)

    version_match = re.search(r"// Version: ([\d.]+)", content[:500])
    version = version_match.group(1) if version_match else "unknown"
    print(f"Patching Claude Code cli.js v{version}")
    print()

    def validate_js_identifier(name, var):
        """Validate that a regex-extracted variable name is a valid JS identifier."""
        if not re.match(r'^[A-Za-z_$][A-Za-z0-9_$]*$', var):
            print(f"  FAIL {name} — extracted variable '{var}' is not a valid JS identifier")
            return False
        return True

    # The dynamic env var scanner — reused across patches
    # Scans process.env for ANTHROPIC_DEFAULT_*_MODEL, extracts alias, excludes built-ins
    SCAN = (
        'Object.keys(process.env)'
        '.filter(function(k){return/^ANTHROPIC_DEFAULT_\\w+_MODEL$/.test(k)})'
        '.map(function(k){return k.replace(/^ANTHROPIC_DEFAULT_/,"").replace(/_MODEL$/,"").toLowerCase().replace(/_/g,"-")})'
        '.filter(function(k){return["sonnet","opus","haiku","best","sonnet[1m]","opus[1m]","opusplan"].indexOf(k)<0})'
    )

    patch_count = 0
    fail_count = 0

    def apply_patch(name, pattern, replacement, skip_marker=None):
        nonlocal content, patch_count, fail_count

        # Idempotency: if replacement is already in the content, skip
        if replacement in content:
            print(f"  SKIP {name} (already patched)")
            return True
        # Secondary idempotency: check for a unique comment marker
        # (handles cases where SCAN filter changed between patcher versions)
        if skip_marker and skip_marker in content:
            print(f"  SKIP {name} (already patched)")
            return True

        count = content.count(pattern)
        if count == 0:
            print(f"  FAIL {name} — pattern not found")
            fail_count += 1
            return False
        if count > 1:
            print(f"  FAIL {name} — pattern found {count} times (expected 1)")
            fail_count += 1
            return False
        old_len = len(content)
        content = content.replace(pattern, replacement, 1)
        new_len = len(content)
        # Verify: length changed by expected amount
        expected_diff = len(replacement) - len(pattern)
        actual_diff = new_len - old_len
        if actual_diff != expected_diff:
            print(f"  FAIL {name} — size change mismatch (expected {expected_diff}, got {actual_diff})")
            fail_count += 1
            return False
        # Verify: replacement text is now present
        if replacement not in content:
            print(f"  FAIL {name} — replacement text not found after patching")
            fail_count += 1
            return False
        print(f"  OK   {name}")
        patch_count += 1
        return True

    print("Applying patches...")

    # --- PATCH 1: Task tool model enum ---
    # Accept any model alias string, not just the hardcoded sonnet/opus/haiku enum.
    enum_match = re.search(r'(\w+)\.enum\(\["sonnet","opus","haiku"\]\)\.optional\(\)\.describe\(', content)
    if not enum_match:
        if '/*ccpatch:model-enum*/' in content:
            print("  SKIP Patch 1: Task tool enum (already patched)")
        else:
            print("  FAIL Patch 1: Could not find Task tool enum pattern")
            fail_count += 1
    else:
        zod_var = enum_match.group(1)
        if not validate_js_identifier("Patch 1", zod_var):
            fail_count += 1
        else:
            apply_patch(
                "Patch 1: Task tool enum",
                f'{zod_var}.enum(["sonnet","opus","haiku"]).optional().describe(',
                f'{zod_var}.string()/*ccpatch:model-enum*/.optional().describe(',
            )

    # --- PATCH 2: Env var whitelist ---
    # Override YG6.has() so UVq() accepts any ANTHROPIC_DEFAULT_*_MODEL env var
    # from settings.json, even before they exist in process.env at module init.
    set_match = re.search(r'(\w+)=new Set\(\["ANTHROPIC_CUSTOM_HEADERS"', content)
    if not set_match:
        if '/*ccpatch:env-whitelist*/' in content:
            print("  SKIP Patch 2: Env var whitelist (already patched)")
        else:
            print("  FAIL Patch 2: Could not find env var whitelist Set")
            fail_count += 1
    else:
        set_var = set_match.group(1)
        if not validate_js_identifier("Patch 2", set_var):
            fail_count += 1
        else:
            apply_patch(
                "Patch 2: Env var whitelist",
                '"VERTEX_REGION_CLAUDE_HAIKU_4_5"])});',
                '"VERTEX_REGION_CLAUDE_HAIKU_4_5"]);'
                f'var _oh={set_var}.has.bind({set_var});'
                f'{set_var}.has=function(k){{return _oh(k)||/^ANTHROPIC_DEFAULT_\\w+_MODEL$/i.test(k)}}'
                '/*ccpatch:env-whitelist*/});',
                skip_marker='/*ccpatch:env-whitelist*/',
            )

    # --- PATCH 3: Model picker fallback ---
    # Include custom aliases in the fallback list when the picker errors.
    apply_patch(
        "Patch 3: Model picker fallback",
        'catch{return["sonnet","opus","haiku"]}',
        'catch{return["sonnet","opus","haiku"]/*ccpatch:picker-fallback*/.concat(' + SCAN + ')}',
        skip_marker='/*ccpatch:picker-fallback*/',
    )

    # --- PATCH 4: Task tool model description ---
    # List available custom aliases in the Task tool's model parameter description
    # so Claude knows they exist and can suggest them.
    DESCRIBE_ORIG = (
        '.describe("Optional model override for this agent. '
        "Takes precedence over the agent definition's model frontmatter. "
        "If omitted, uses the agent definition's model, or inherits from the parent.\")"
    )
    CUSTOM_LIST = (
        '(function(){var _c=' + SCAN + ';'
        'var _d="Optional model override for this agent. '
        "Takes precedence over the agent definition's model frontmatter. "
        "If omitted, uses the agent definition's model, or inherits from the parent. "
        'Available aliases: sonnet, opus, haiku";'
        'if(_c.length>0)_d+=", "+_c.join(", ");'
        '_d+=".";'
        'return _d})()'
    )
    apply_patch(
        "Patch 4: Task tool model description",
        DESCRIBE_ORIG,
        '.describe(/*ccpatch:tool-desc*/' + CUSTOM_LIST + ')',
        skip_marker='/*ccpatch:tool-desc*/',
    )

    # --- PATCH 5: Model picker UI ---
    # Show custom models in the model selection dropdown with their resolved
    # model ID as the description.
    PICKER_PATTERN = (
        '{value:"inherit",label:"Inherit from parent",'
        'description:"Use the same model as the main conversation"}]}'
    )
    PICKER_REPLACE = (
        '{value:"inherit",label:"Inherit from parent",'
        'description:"Use the same model as the main conversation"}]'
        '/*ccpatch:picker-options*/.concat(' + SCAN + '.map(function(k){'
        'return{value:k,label:k.charAt(0).toUpperCase()+k.slice(1),'
        'description:"Custom model ("+process.env["ANTHROPIC_DEFAULT_"+k.toUpperCase().replace(/-/g,"_")+"_MODEL"]+")"}'
        '}).filter(function(e){return e.description!="Custom model ()"}))'
        '}'
    )
    apply_patch(
        "Patch 5: Model picker UI",
        PICKER_PATTERN,
        PICKER_REPLACE,
        skip_marker='/*ccpatch:picker-options*/',
    )

    # --- PATCH 6: Alias resolver fallback ---
    # The built-in alias lists are built from process.env at module init,
    # before settings.json env vars are loaded. Custom aliases miss the guard
    # and skip the resolver switch entirely. This adds a fallback env var lookup
    # AFTER the switch block so custom aliases always resolve correctly.
    # Uses regex because the obfuscated function names change every build.
    if '/*ccpatch:fallback-resolver*/' in content:
        print("  SKIP Patch 6: Alias resolver fallback (already patched)")
    else:
        p6_match = re.search(
            r'(default:\})(if\([\w$]+\(\)==="firstParty"&&[\w$]+\([\w$]+\)&&[\w$]+\(\)\))',
            content
        )
        if not p6_match:
            print("  FAIL Patch 6: Alias resolver fallback — pattern not found")
            fail_count += 1
        elif content.count(p6_match.group(0)) > 1:
            print(f"  FAIL Patch 6: Alias resolver fallback — pattern found {content.count(p6_match.group(0))} times (expected 1)")
            fail_count += 1
        else:
            p6_original = p6_match.group(0)
            p6_firstparty = p6_match.group(2)
            p6_replacement = (
                p6_match.group(1)
                + 'var _fev="ANTHROPIC_DEFAULT_"+z.toUpperCase().replace(/-/g,"_")+"_MODEL";'
                + 'if(process.env[_fev])return process.env[_fev]/*ccpatch:fallback-resolver*/;'
                + p6_firstparty
            )
            old_len = len(content)
            content = content.replace(p6_original, p6_replacement, 1)
            new_len = len(content)
            expected_diff = len(p6_replacement) - len(p6_original)
            if new_len - old_len != expected_diff:
                print(f"  FAIL Patch 6: Alias resolver fallback — size change mismatch")
                fail_count += 1
            elif p6_replacement not in content:
                print(f"  FAIL Patch 6: Alias resolver fallback — replacement text not found after patching")
                fail_count += 1
            else:
                print(f"  OK   Patch 6: Alias resolver fallback")
                patch_count += 1

    print()
    print(f"=== Results ===")
    print(f"Patches applied: {patch_count}")
    print(f"Patches failed:  {fail_count}")

    if fail_count > 0:
        print(f"\nWARNING: {fail_count} patch(es) failed.")
        sys.exit(1)

    # Atomic write: write to temp file then rename
    out_dir = os.path.dirname(os.path.abspath(output_path))
    fd, tmp_path = tempfile.mkstemp(dir=out_dir, suffix=".tmp")
    try:
        with os.fdopen(fd, "w", encoding="utf-8") as f:
            f.write(content)
        os.rename(tmp_path, output_path)
    except:
        os.unlink(tmp_path)
        raise

    orig_size = os.path.getsize(input_path) if input_path != output_path else len(content)
    new_size = os.path.getsize(output_path)
    print(f"\nPatched file: {output_path}")
    print(f"Size: {new_size:,} bytes (diff: +{new_size - orig_size:,})")


if __name__ == "__main__":
    main()
PATCHER_EOF

echo "  Patcher written to $CACHE_DIR/patch.py"

# --- Fetch Claude Code from npm ---
echo ""
echo "  Fetching @anthropic-ai/claude-code from npm..."

TMPDIR=$(mktemp -d)
cleanup_tmpdir() { rm -rf "$TMPDIR"; }
trap cleanup_tmpdir EXIT

if ! npm pack @anthropic-ai/claude-code@latest --pack-destination "$TMPDIR" >/dev/null 2>&1; then
    echo "ERROR: Failed to fetch @anthropic-ai/claude-code from npm" >&2
    exit 1
fi

TGZ=$(ls "$TMPDIR"/*.tgz 2>/dev/null | head -1)
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
echo ""
CLAUDE_PATH=$(which claude 2>/dev/null || echo "")
if [[ -n "$CLAUDE_PATH" ]]; then
    if grep -q 'claude-alias-patch' "$CLAUDE_PATH" 2>/dev/null; then
        echo "  Detected: existing wrapper (updating)"
    elif [[ -L "$CLAUDE_PATH" ]]; then
        REAL=$(readlink -f "$CLAUDE_PATH")
        if file "$REAL" 2>/dev/null | grep -qE 'ELF|Mach-O'; then
            echo "  Detected: native binary (via symlink → $REAL)"
            echo "  The binary will be backed up. The patched version runs from npm via node."
        fi
    elif file "$CLAUDE_PATH" 2>/dev/null | grep -qE 'ELF|Mach-O'; then
        echo "  Detected: native binary ($CLAUDE_PATH)"
        echo "  The binary will be backed up. The patched version runs from npm via node."
    else
        echo "  Detected: existing npm installation"
    fi
else
    echo "  No existing Claude Code installation found"
fi

# --- Install wrapper ---
echo ""
echo "  Installing wrapper..."
mkdir -p "$BIN_DIR"

# Download wrapper script
if ! curl -sL "$WRAPPER_URL" -o "$CACHE_DIR/claude-wrapper.sh" 2>/dev/null; then
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
RESOLVED=$(which claude 2>/dev/null || echo "")
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
echo "  Uninstall: curl -sL https://raw.githubusercontent.com/East-rayyy/claude-alias-patch/main/scripts/uninstall.sh | bash"
