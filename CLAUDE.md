# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project

Claude Alias Patch adds custom model aliases to Claude Code by patching its bundled `cli.js`. Users set `ANTHROPIC_DEFAULT_{ALIAS}_MODEL` env vars in `~/.claude/settings.json`, and the patcher injects code to make those aliases available in the Task tool, model picker, and alias resolver.

## Repository Structure

- `scripts/install.sh` — single-file installer. Contains the embedded Python patcher (heredoc) plus the bash installer logic (npm fetch, patching, wrapper install, backup)
- `scripts/claude-wrapper.sh` — wrapper that replaces the `claude` binary. Handles `claude update` (re-fetch + re-patch) and normal execution (auto re-patch if markers missing, then `exec node cli.js`)
- `scripts/uninstall.sh` — restores original binary from backup, removes cache
- `comments-log.md` — log of GitHub comments posted to related issues across repos

## Key Paths at Runtime

- `~/.cache/claude-alias-patch/` — cache dir: `cli.js` (patched), `patch.py` (extracted from install.sh), `.version`
- `~/.local/bin/claude` — wrapper script (replaces original binary)
- `~/.local/bin/claude.bak` — backup of original binary (symlink for native, file for npm)

## Installation Architecture

The installer detects the user's existing Claude Code installation type via `detect_claude_install()`:

| Type              | Detection                                                  | What happens                                                                           |
| ----------------- | ---------------------------------------------------------- | -------------------------------------------------------------------------------------- |
| `native`          | ELF/Mach-O binary in `~/.local/share/claude/versions/`     | Cannot patch embedded bytecode. Fetches cli.js from npm, patches it, installs wrapper. |
| `package-manager` | ELF/Mach-O binary elsewhere (brew, apt, etc.)              | Same as native — wrapper approach.                                                     |
| `npm-global`      | Symlink to `node_modules/@anthropic-ai/claude-code/cli.js` | Wrapper approach (survives `npm update`).                                              |
| `npm-local`       | Path contains `/.claude/local/`                            | Wrapper approach.                                                                      |
| `wrapper`         | Already contains `claude-alias-patch` marker               | Upgrade path — re-fetch + re-patch.                                                    |
| `none`            | `claude` not found in PATH                                 | Fresh install — fetch from npm + wrapper.                                              |

All paths converge on the same approach: fetch cli.js from npm, patch it, run via `exec node cli.js` through the wrapper.

## Patcher Architecture

The patcher (`patch.py`, embedded in `install.sh` lines 50–318) applies 6 patches to Claude Code's `cli.js`:

1. **Zod enum → string** — Task tool accepts any model alias string
2. **Env var whitelist** — monkey-patches `Set.has()` to accept `ANTHROPIC_DEFAULT_*_MODEL` vars
3. **Model picker fallback** — appends custom aliases to the catch-all fallback list
4. **Tool description** — dynamically lists available aliases in the Task tool's describe text
5. **Model picker UI** — adds custom models to the dropdown with their resolved model ID
6. **Alias resolver fallback** — regex-based (function names are obfuscated), adds env var lookup after the switch block

Patches 1–5 use literal string matching. Patch 6 uses regex because the target function names change between builds. All patches are idempotent — re-running shows `SKIP` for already-patched locations.

Each patch uses `/*ccpatch:<name>*/` comment markers for idempotency detection.

The `SCAN` constant (line 94–98) is the env var scanner snippet reused across patches 3, 4, and 5 — it extracts alias names from `process.env`.

## Testing Changes

There are no unit tests. Verify patches manually:

```bash
# Extract patcher from install.sh
sed -n '/^cat > .*patch\.py.*<< .PATCHER_EOF/,/^PATCHER_EOF/p' scripts/install.sh | tail -n +2 | head -n -1 > /tmp/patch.py

# Fetch latest Claude Code
npm pack @anthropic-ai/claude-code@latest
mkdir -p /tmp/test-pkg
tar -xzf anthropic-ai-claude-code-*.tgz -C /tmp/test-pkg --strip-components=1

# Run patcher — all 6 should show OK (or SKIP if already patched)
python3 /tmp/patch.py /tmp/test-pkg/cli.js /tmp/test-pkg/cli-patched.js

# Verify idempotency — all 6 should show SKIP
python3 /tmp/patch.py /tmp/test-pkg/cli-patched.js /tmp/test-pkg/cli-patched2.js
```

Shell script syntax check: `bash -n scripts/install.sh`

## CI

- `check-patches.yml` — daily cron (08:00 UTC) + manual trigger. Fetches latest Claude Code from npm and runs the patcher. Auto-creates a GitHub issue with `patch-failure` label on failure.
- `check-patches-pr.yml` — runs on PRs to `main`. Same patcher check.

Both workflows extract `patch.py` from the `install.sh` heredoc at CI time — the patcher is not a standalone file in the repo.

## Working on the Patcher

The patcher is embedded inside `install.sh`. When modifying patches:

1. Edit the Python code inside the `PATCHER_EOF` heredoc in `scripts/install.sh`
2. The `apply_patch()` function handles: uniqueness check (pattern must appear exactly once), size verification, idempotency via skip markers
3. For regex-based patches (Patch 6), the manual equivalent of `apply_patch()` is inlined
4. When Claude Code updates change obfuscated variable names, only the regex patterns need updating — not the replacement logic
5. Literal patches break when Anthropic changes the matched strings in `cli.js`

## PR Checklist

From the PR template — all must pass before merging:

- All 6 patches pass against the latest Claude Code release
- Patcher is idempotent (second run shows all SKIP)
- Shell scripts pass `bash -n` syntax check
- No external dependencies added
