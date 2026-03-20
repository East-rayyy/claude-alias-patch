# Claude Alias Patch

Add custom model aliases to [Claude Code](https://github.com/anthropics/claude-code). Use Gemini, GPT, or any model as a subagent — Claude sees them as selectable options alongside Sonnet, Opus, and Haiku.

## How it works

Claude Code hardcodes its model aliases to `sonnet`, `opus`, and `haiku`. This patch extends that list by scanning for `ANTHROPIC_DEFAULT_*_MODEL` environment variables in your `~/.claude/settings.json`.

For example, setting `ANTHROPIC_DEFAULT_GEMINI_MODEL` registers `gemini` as a model alias. Claude can then select it when spawning subagents via the Task tool, in the model picker, and in agent definitions.

**If you don't set any custom env vars, the patch does nothing** — Claude Code works exactly like normal.

**You'll need an API proxy** that accepts Anthropic-format API calls and routes them to the correct provider. [LiteLLM](https://github.com/BerriAI/litellm), [OpenRouter](https://openrouter.ai/), and similar tools work.

## Install

```bash
curl -fsSL https://raw.githubusercontent.com/East-rayyy/claude-alias-patch/main/linux-apply.sh | bash
```

Prerequisites: Node.js >= 18, npm, python3.

The installer downloads Claude Code from npm, patches it, backs up your existing `claude` binary, and installs a wrapper script. Works whether you originally installed Claude Code via npm, the native binary, or a package manager.

## Configure

Add your custom models to `~/.claude/settings.json`. These env vars are **completely optional** — only add the ones you need:

```json
{
  "env": {
    "ANTHROPIC_BASE_URL": "http://localhost:PORT/v1",
    "ANTHROPIC_DEFAULT_GEMINI_MODEL": "google/gemini-2.5-pro",
    "ANTHROPIC_DEFAULT_GPT_MODEL": "openai/gpt-4o",
    "ANTHROPIC_DEFAULT_DEEPSEEK_MODEL": "deepseek/deepseek-r1"
  }
}
```

The naming convention is `ANTHROPIC_DEFAULT_{ALIAS}_MODEL`. The alias comes from the middle part:

- `ANTHROPIC_DEFAULT_GEMINI_MODEL` → alias `gemini`
- `ANTHROPIC_DEFAULT_GPT_MODEL` → alias `gpt`
- `ANTHROPIC_DEFAULT_DEEP_SEEK_MODEL` → alias `deep-seek` (underscores become hyphens)

Restart Claude Code after changing your env vars. Your custom aliases show up automatically in the model picker, the Task tool, and agent definitions.

## Update

```bash
claude update
```

The wrapper intercepts the update command, pulls the latest patcher from GitHub, fetches the latest Claude Code from npm, re-patches it, and self-updates the wrapper script. Everything stays current automatically.

## Uninstall

```bash
curl -fsSL https://raw.githubusercontent.com/East-rayyy/claude-alias-patch/main/linux-remove.sh | bash
```

Restores your original Claude Code binary and removes the cache.

## What it patches

6 locations in Claude Code's `cli.js`. Patches 1–5 use literal string matching; Patch 6 uses regex to handle obfuscated function names that change between builds:

| #   | What                    | Why                                                                   |
| --- | ----------------------- | --------------------------------------------------------------------- |
| 1   | Zod enum → string       | Accept any model alias, not just sonnet/opus/haiku                    |
| 2   | Env var whitelist       | Allow custom env vars through the settings.json loader                |
| 3   | Model picker fallback   | Include custom aliases in the fallback list                           |
| 4   | Tool description        | List available aliases in the Task tool's model parameter description |
| 5   | Model picker UI         | Show custom models in the model selection interface                   |
| 6   | Alias resolver fallback | Resolve custom aliases to their model ID at runtime                   |

All patches are idempotent — running the patcher twice produces the same result.

---

If you run into issues, open an issue or start a discussion.
