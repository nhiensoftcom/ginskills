# ACP — Agent Client Protocol

## What is ACP?

ACP (Agent Client Protocol) is how IDEs and editors connect to the OpenClaw Gateway. It bridges prompts from an IDE over stdio → Gateway over WebSocket. OpenClaw maps ACP sessions to Gateway session keys.

Reference: https://agentclientprotocol.com

## How It Works

```
IDE/Editor  →  openclaw acp (stdio)  →  OpenClaw Gateway (WebSocket)  →  Agent
```

ACP does not pick agents directly — it routes by Gateway session key.

## Basic Usage

```bash
# Connect to local Gateway
openclaw acp

# Connect to remote Gateway
openclaw acp --url wss://gateway-host:18789 --token <token>

# Use token file (safer — token not visible in process list)
openclaw acp --url wss://gateway-host:18789 --token-file ~/.openclaw/gateway.token

# Attach to a specific agent session
openclaw acp --session agent:main:main
openclaw acp --session agent:design:main

# Attach by label
openclaw acp --session-label "support inbox"
```

## Targeting Agents

Use agent-scoped session keys:

```bash
openclaw acp --session agent:<agentId>:main
```

Examples:
- `agent:main:main` — default agent
- `agent:coding:main` — agent named "coding"
- `agent:qa:bug-123` — custom session thread

## Editor Setup

### Zed

Add to `~/.config/zed/settings.json`:

```json
{
  "agent_servers": {
    "OpenClaw ACP": {
      "type": "custom",
      "command": "openclaw",
      "args": ["acp"],
      "env": {}
    }
  }
}
```

Target specific agent:

```json
{
  "agent_servers": {
    "OpenClaw ACP": {
      "type": "custom",
      "command": "openclaw",
      "args": ["acp", "--url", "wss://gateway-host:18789", "--token-file", "~/.openclaw/gateway.token", "--session", "agent:coding:main"],
      "env": {}
    }
  }
}
```

### Claude Code / Codex via sessions_spawn

From within an OpenClaw agent session, spawn a coding agent via ACP:

```
sessions_spawn(runtime="acp", agentId="<acp-agent-id>", task="...", thread=true, mode="session")
```

This is the recommended way to use Claude Code or Codex inside OpenClaw — no manual ACP setup needed.

## Debug / Test

```bash
# Interactive ACP client (test without an IDE)
openclaw acp client

# Point at remote Gateway
openclaw acp client --server-args --url wss://gateway-host:18789 --token-file ~/.openclaw/gateway.token
```

## Session Mapping

| Flag | Behavior |
|------|----------|
| (none) | Isolated session with `acp:<uuid>` prefix |
| `--session <key>` | Use specific Gateway session key |
| `--session-label <label>` | Resolve existing session by label |
| `--reset-session` | Fresh session id for same key |

## Security Notes

- Prefer `--token-file` over `--token` (token visible in process list)
- Use env vars: `OPENCLAW_GATEWAY_TOKEN`, `OPENCLAW_GATEWAY_PASSWORD`
- ACP child processes receive `OPENCLAW_SHELL=acp` for context-specific rules
