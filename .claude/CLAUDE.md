# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project

Claude Alias Patch adds custom model aliases to Claude Code by patching its bundled `cli.js`. Users set `ANTHROPIC_DEFAULT_{ALIAS}_MODEL` env vars in `~/.claude/settings.json`, and the patcher injects code to make those aliases available in the Task tool, model picker, and alias resolver.

## Repository Structure

- `linux-apply.sh` — installer script (user-facing). Downloads patcher + wrapper from GitHub, fetches Claude Code from npm, patches it, installs wrapper.
- `linux-remove.sh` — uninstaller (user-facing). Restores original binary from backup, removes cache.
- `lib/patcher.py` — Python patcher. Applies 6 patches to `cli.js`.
- `lib/wrapper.sh` — Bash wrapper that replaces the `claude` binary. Handles `claude update` (re-fetch + re-patch) and normal execution (auto re-patch if markers missing, then `exec node cli.js`).
- `comments-log.md` — log of GitHub comments posted to related issues across repos.

## Key Paths at Runtime

- `~/.cache/claude-alias-patch/` — cache dir: `cli.js` (patched), `patch.py` (downloaded from GitHub), `.version`
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

The patcher (`lib/patcher.py`) applies 6 patches to Claude Code's `cli.js`:

1. **Zod enum → string** — Task tool accepts any model alias string
2. **Env var whitelist** — monkey-patches `Set.has()` to accept `ANTHROPIC_DEFAULT_*_MODEL` vars
3. **Model picker fallback** — appends custom aliases to the catch-all fallback list
4. **Tool description** — dynamically lists available aliases in the Task tool's describe text
5. **Model picker UI** — adds custom models to the dropdown with their resolved model ID
6. **Alias resolver fallback** — regex-based (function names are obfuscated), adds env var lookup after the switch block

Patches 1–5 use literal string matching. Patch 6 uses regex because the target function names change between builds. All patches are idempotent — re-running shows `SKIP` for already-patched locations.

Each patch uses `/*ccpatch:<name>*/` comment markers for idempotency detection.

The `SCAN` constant is the env var scanner snippet reused across patches 3, 4, and 5 — it extracts alias names from `process.env`.

## Testing Changes

There are no unit tests. Verify patches manually:

```bash
# Fetch latest Claude Code
npm pack @anthropic-ai/claude-code@latest
mkdir -p /tmp/test-pkg
tar -xzf anthropic-ai-claude-code-*.tgz -C /tmp/test-pkg --strip-components=1

# Run patcher — all 6 should show OK (or SKIP if already patched)
python3 lib/patcher.py /tmp/test-pkg/cli.js /tmp/test-pkg/cli-patched.js

# Verify idempotency — all 6 should show SKIP
python3 lib/patcher.py /tmp/test-pkg/cli-patched.js /tmp/test-pkg/cli-patched2.js
```

Shell script syntax check: `bash -n linux-apply.sh && bash -n linux-remove.sh && bash -n lib/wrapper.sh`

## CI

- `check-patches.yml` — daily cron (08:00 UTC) + manual trigger. Fetches latest Claude Code from npm and runs `lib/patcher.py`. Auto-creates a GitHub issue with `patch-failure` label on failure.
- `check-patches-pr.yml` — runs on PRs to `main`. Same patcher check.

## Working on the Patcher

When modifying patches:

1. Edit `lib/patcher.py` directly
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
