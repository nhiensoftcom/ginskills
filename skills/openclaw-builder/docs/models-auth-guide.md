# Model Providers & Auth

## Quick Setup

```bash
openclaw onboard          # interactive wizard (recommended for new installs)
openclaw models list      # see available models
openclaw models status    # check auth status + which models are active
openclaw models set anthropic/claude-opus-4-6   # set primary model
```

## Provider Format

Models use `provider/model` format:
```
anthropic/claude-opus-4-6
openai/gpt-5.1-codex
openai/gpt-4o
gemini/gemini-2.5-pro
```

## Built-in Providers (no extra config needed)

| Provider | Auth env var | Example model |
|----------|-------------|---------------|
| Anthropic | `ANTHROPIC_API_KEY` | `anthropic/claude-opus-4-6` |
| OpenAI | `OPENAI_API_KEY` | `openai/gpt-4o` |
| Google Gemini | `GEMINI_API_KEY` | `gemini/gemini-2.5-pro` |
| OpenRouter | `OPENROUTER_API_KEY` | `openrouter/...` |
| Groq | `GROQ_API_KEY` | `groq/...` |
| xAI Grok | `XAI_API_KEY` | `xai/grok-3` |

## API Key Setup

**Option 1: Environment variable (simplest)**
```bash
export ANTHROPIC_API_KEY="sk-ant-..."
openclaw gateway
```

**Option 2: .env file (recommended for always-on gateway)**
```bash
cat >> ~/.openclaw/.env <<'EOF'
ANTHROPIC_API_KEY=sk-ant-...
OPENAI_API_KEY=sk-...
EOF
openclaw gateway restart
```

**Option 3: Config file**
```json5
{
  env: {
    vars: {
      ANTHROPIC_API_KEY: "sk-ant-...",
    }
  }
}
```

## Anthropic OAuth (subscription)

```bash
# Run on gateway host
openclaw models auth paste-token --provider anthropic
# Paste your Claude setup-token
```

## Set Primary Model

```json5
{
  agents: {
    defaults: {
      model: {
        primary: "anthropic/claude-sonnet-4-6",
        fallback: ["openai/gpt-4o"],     // fallback if primary fails
      }
    }
  }
}
```

## API Key Rotation (multiple keys)

```bash
# Env var — comma-separated list
export ANTHROPIC_API_KEYS="key1,key2,key3"

# Or numbered
export ANTHROPIC_API_KEY_1="key1"
export ANTHROPIC_API_KEY_2="key2"

# Live override (highest priority)
export OPENCLAW_LIVE_ANTHROPIC_KEY="key-override"
```

OpenClaw auto-rotates to next key on rate-limit (429) errors.

## Web Search Providers

```bash
openclaw configure --section web   # interactive setup
```

| Provider | API key env var | Notes |
|----------|----------------|-------|
| Brave | `BRAVE_API_KEY` | Fast, structured |
| Perplexity | `PERPLEXITY_API_KEY` | Detailed, filtered results |
| Gemini | `GEMINI_API_KEY` | Google Search grounding |
| Grok | `XAI_API_KEY` | xAI web-grounded |

Auto-detect order: Brave → Gemini → Kimi → Perplexity → Grok

```json5
{
  tools: {
    web: {
      search: {
        apiKey: "BRAVE_API_KEY_HERE",   // Brave (default)
        // provider: "perplexity",      // override provider
      }
    }
  }
}
```

## Session DM Scope (Security)

**Important for multi-user setups:**
```json5
{
  session: {
    dmScope: "per-channel-peer"   // isolate DM sessions per user
    // Options: "main" (default, single-user) | "per-peer" | "per-channel-peer" | "per-account-channel-peer"
  }
}
```

Default `"main"` shares one session for all DMs — fine for single user, **unsafe for multiple users**.
