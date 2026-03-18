# Claude Alias Patch

Add custom model aliases to [Claude Code](https://github.com/anthropics/claude-code). Use Gemini, GPT, or any model as a subagent — Claude sees them as selectable options alongside Sonnet, Opus, and Haiku.

## How it works

Claude Code hardcodes its model aliases to `sonnet`, `opus`, and `haiku`. This patch extends that list by scanning for `ANTHROPIC_DEFAULT_*_MODEL` environment variables in your `~/.claude/settings.json`.

For example, setting `ANTHROPIC_DEFAULT_GEMINI_MODEL` registers `gemini` as a model alias. Claude can then select it when spawning subagents via the Task tool, in the model picker, and in agent definitions.

**If you don't set any custom env vars, the patch does nothing** — Claude Code works exactly like normal.

**You'll need an API proxy** that accepts Anthropic-format API calls and routes them to the correct provider. I use [9router](https://github.com/decolua/9router), but [LiteLLM](https://github.com/BerriAI/litellm) and [OpenRouter](https://openrouter.ai/) work too.

## Install

```bash
curl -sL https://raw.githubusercontent.com/East-rayyy/claude-alias-patch/main/scripts/install.sh | bash
```

Prerequisites: Node.js >= 18, npm, python3.

The installer downloads Claude Code from npm, patches it, backs up your existing `claude` binary, and installs a wrapper script. Works whether you originally installed Claude Code via npm or the native binary.

All scripts live in the [`scripts/`](scripts/) folder.

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

Restart Claude Code after changing your env vars. Your custom aliases show up automatically in the model picker, the Task tool, and agent definitions. No need to re-patch or rerun the installer — just edit and restart.

## My setup

I use [9router](https://github.com/decolua/9router) as my API proxy. Here's what my `settings.json` env looks like:

```json
{
  "env": {
    "ANTHROPIC_BASE_URL": "http://localhost:20128/v1",
    "ANTHROPIC_DEFAULT_SONNET_MODEL": "claude-sonnet-4-6",
    "ANTHROPIC_DEFAULT_OPUS_MODEL": "claude-opus-4-6",
    "ANTHROPIC_DEFAULT_HAIKU_MODEL": "claude-haiku-4-5",
    "ANTHROPIC_DEFAULT_GEMINI_MODEL": "google-gemini-code",
    "ANTHROPIC_DEFAULT_GPT_MODEL": "openai-gpt-codex",
    "ANTHROPIC_DEFAULT_GLM_MODEL": "glm-glm-coding"
  }
}
```

This gives me `gemini`, `gpt`, and `glm` as extra model aliases. 9router handles routing each model ID to the correct provider.

## Update

```bash
claude update
```

The wrapper intercepts the update command, fetches the latest Claude Code from npm, re-patches it, and reports the version.

## Uninstall

```bash
curl -sL https://raw.githubusercontent.com/East-rayyy/claude-alias-patch/main/scripts/uninstall.sh | bash
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

Enjoy! If you run into issues, open an issue or start a discussion.
